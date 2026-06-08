#!/usr/bin/env python3
"""Boots Rk-C on QEMU and executes categorized application smoke tests."""
import argparse
import importlib.util
import json
import os
import re
import selectors
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from app_tests.filesystem_cases import filesystem_tests
from app_tests.model import TestCase, TestSection
from app_tests.network_cases import network_tests
from app_tests.runtime_cases import runtime_tests
from app_tests.security_cases import security_tests
from app_tests.shell_cases import shell_tests
from app_tests.user_cases import user_tests


ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
PROMPT_MARKER = "$ "
TEST_APP_NAMES = ["faultcheck", "capcheck", "pollcheck", "signalcheck", "writecheck", "heapcheck", "inputcheck", "orccheck"]
OPTIONAL_TOOLCHAIN_TESTS = os.environ.get("RKC_OPTIONAL_TOOLCHAIN_TESTS", "")
OPTIONAL_TOOLCHAIN_TEST_APPS = os.environ.get("RKC_OPTIONAL_TOOLCHAIN_TEST_APPS", "").split()


@dataclass
class CommandResult:
    """Stores a command response and validation outcome."""

    output: str
    errors: list[str]
    fatal: bool = False


@dataclass
class TestRecord:
    """Stores one executed test result for the structured summary."""

    number: int
    section: str
    name: str
    command: str
    status: str
    category: str
    duration_sec: float
    errors: list[str]
    fatal: bool
    expected: str
    actual: str
    rerun_command: str


class QemuConsole:
    """Runs QEMU and exchanges commands through its serial console."""

    def __init__(self, command: list[str], log_path: Path | None = None):
        self.command = command
        self.log_path = log_path
        self.proc: subprocess.Popen[bytes] | None = None
        self.selector = selectors.DefaultSelector()
        self.buffer = ""
        self.log_file = None

    def start(self) -> None:
        """Starts the QEMU process and captures its serial output."""
        if self.log_path is not None:
            self.log_path.parent.mkdir(parents=True, exist_ok=True)
            self.log_file = self.log_path.open("w", encoding="utf-8", errors="replace")

        self.proc = subprocess.Popen(
            self.command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
            preexec_fn=os.setsid,
        )
        assert self.proc.stdout is not None
        os.set_blocking(self.proc.stdout.fileno(), False)
        self.selector.register(self.proc.stdout, selectors.EVENT_READ)

    def close(self) -> None:
        """Requests shutdown and forcibly cleans up QEMU when needed."""
        if self.proc is None:
            return

        if self.proc.poll() is None:
            try:
                self.send("shutdown\n")
                self.proc.wait(timeout=3)
            except Exception:
                pass

        if self.proc.poll() is None:
            try:
                os.killpg(os.getpgid(self.proc.pid), signal.SIGTERM)
                self.proc.wait(timeout=3)
            except Exception:
                pass

        if self.proc.poll() is None:
            try:
                os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
            except Exception:
                pass

        if self.log_file is not None:
            self.log_file.close()
            self.log_file = None

    def send(self, data: str) -> None:
        """Writes terminal input to the running guest."""
        if self.proc is None or self.proc.stdin is None:
            raise RuntimeError("QEMU is not running")
        self.proc.stdin.write(data.encode("utf-8"))
        self.proc.stdin.flush()

    def read_some(self, timeout: float) -> str:
        """Reads currently available serial console output."""
        if self.proc is None:
            raise RuntimeError("QEMU is not running")
        if self.proc.poll() is not None:
            raise RuntimeError(f"QEMU exited with status {self.proc.returncode}")

        chunks: list[str] = []
        for key, _ in self.selector.select(timeout):
            data = key.fileobj.read()
            if not data:
                continue
            text = data.decode("utf-8", errors="replace")
            if self.log_file is not None:
                self.log_file.write(text)
                self.log_file.flush()
            chunks.append(text)
        return "".join(chunks)

    def wait_for(self, needle: str, timeout: float) -> str:
        """Reads console output until the requested terminal marker appears."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if needle in self.buffer:
                out = self.buffer
                self.buffer = ""
                return out
            self.buffer += self.read_some(max(0.05, min(0.5, deadline - time.monotonic())))
        raise TimeoutError(f"timed out waiting for {needle!r}")

    def run_command(self, command: str, timeout: float, append_newline: bool = True) -> str:
        """Runs one shell input sequence and waits for the next prompt."""
        self.buffer = ""
        self.send(command + ("\n" if append_newline else ""))
        return self.wait_for(PROMPT_MARKER, timeout)

    def login(self, username: str, password: str, timeout: float) -> str:
        """Authenticates to the initial login process."""
        boot = self.wait_for("login: ", timeout)
        self.send(username + "\n")
        boot += self.wait_for("password: ", timeout)
        self.send(password + "\n")
        boot += self.wait_for(PROMPT_MARKER, timeout)
        return boot


def strip_ansi(text: str) -> str:
    """Removes terminal escape sequences before assertion matching."""
    return ANSI_RE.sub("", text)


def run_build() -> None:
    """Builds regular and test-only RKX binaries."""
    subprocess.run(["make", "build-test-bins"], check=True)


def prepare_test_disk(test_disk: Path, base_disk: Path, no_build: bool) -> None:
    """Creates a clean disk image and packs apps for one test execution."""
    test_disk.parent.mkdir(parents=True, exist_ok=True)
    test_disk.unlink(missing_ok=True)
    if not no_build:
        run_build()

    disk_size = 16 * 1024 * 1024
    if base_disk.exists():
        disk_size = base_disk.stat().st_size

    with test_disk.open("wb") as disk:
        disk.truncate(disk_size)

    test_app_names = [*TEST_APP_NAMES, *OPTIONAL_TOOLCHAIN_TEST_APPS]
    subprocess.run(
        ["make", f"DISK_IMG={test_disk}", f"APPFS_EXTRA_APPS={' '.join(test_app_names)}", "appfs"],
        check=True,
    )


def validate(case: TestCase, output: str) -> list[str]:
    """Checks console text against all expectations for a test case."""
    clean = strip_ansi(output)
    errors = []
    for expected in case.contains:
        if expected not in clean:
            errors.append(f"missing substring {expected!r}")
    for unexpected in case.not_contains:
        if unexpected in clean:
            errors.append(f"unexpected substring {unexpected!r}")
    for pattern in case.regex:
        if not re.search(pattern, clean):
            errors.append(f"missing regex {pattern!r}")
    if case.any_of and not any(item in clean for item in case.any_of):
        errors.append(f"missing one of {case.any_of!r}")
    return errors


def expected_summary(case: TestCase) -> str:
    """Builds the compact expected-output description shown in logs."""
    parts = []
    if case.contains:
        parts.append("contains=" + repr(case.contains))
    if case.not_contains:
        parts.append("not_contains=" + repr(case.not_contains))
    if case.regex:
        parts.append("regex=" + repr(case.regex))
    if case.any_of:
        parts.append("any_of=" + repr(case.any_of))
    if not parts:
        return "prompt returned"

    return "; ".join(parts)


def actual_summary(output: str, limit: int = 420) -> str:
    """Builds a bounded one-line display of actual console output."""
    clean = strip_ansi(output).replace("\r", "")
    lines = [line.rstrip() for line in clean.splitlines()]
    lines = [line for line in lines if line.strip()]
    text = " | ".join(lines)
    if len(text) > limit:
        text = "..." + text[-limit:]
    return text


def shell_quote(value: str) -> str:
    """Quotes one shell argument without importing shell-specific helpers."""
    if re.fullmatch(r"[A-Za-z0-9_./:=+-]+", value):
        return value
    return "'" + value.replace("'", "'\"'\"'") + "'"


def classify_failure(case: TestCase, errors: list[str], fatal: bool) -> str:
    """Assigns a stable failure category for summary filtering."""
    if case.name == "boot":
        return "boot"
    joined = "\n".join(errors)
    if "recovery failed" in joined:
        return "prompt_recovery"
    if "timed out waiting" in joined:
        return "timeout"
    if "QEMU exited with status" in joined:
        return "qemu_exit"
    if fatal:
        return "console_desync"
    if "missing substring" in joined or "missing regex" in joined or "missing one of" in joined:
        return "validation_missing"
    if "unexpected substring" in joined:
        return "validation_unexpected"
    return "exception"


def normalize_filter_text(text: str) -> str:
    """Normalizes section and case filter text for forgiving matching."""
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def matches_filter(value: str, filters: list[str]) -> bool:
    """Returns whether a value matches any exact, normalized, or substring filter."""
    if not filters:
        return True
    normalized_value = normalize_filter_text(value)
    lowered_value = value.lower()
    for raw_filter in filters:
        normalized_filter = normalize_filter_text(raw_filter)
        lowered_filter = raw_filter.lower()
        if normalized_filter == normalized_value:
            return True
        if lowered_filter in lowered_value:
            return True
    return False


def case_matches_selector(case: TestCase, selector: str) -> bool:
    """Matches a case by number, exact/normalized name, substring, or command."""
    if selector.isdigit() and case.number == int(selector):
        return True
    normalized_selector = normalize_filter_text(selector)
    if normalized_selector == normalize_filter_text(case.name):
        return True
    lowered_selector = selector.lower()
    return lowered_selector in case.name.lower() or lowered_selector in case.command.lower()


def select_sections(
    sections: list[TestSection],
    section_filters: list[str],
    start_at: str | None,
    stop_after: str | None,
) -> list[TestSection]:
    """Applies section and case-range filters while preserving section order."""
    selected_sections = []
    found_start = start_at is None
    found_stop = False

    for section in sections:
        if not matches_filter(section.name, section_filters):
            continue

        selected_tests = []
        for case in section.tests:
            if not found_start:
                if case_matches_selector(case, start_at or ""):
                    found_start = True
                else:
                    continue

            selected_tests.append(case)

            if stop_after is not None and case_matches_selector(case, stop_after):
                found_stop = True
                break

        if selected_tests:
            selected_sections.append(TestSection(section.name, selected_tests))

        if found_stop:
            break

    if start_at is not None and not found_start:
        raise ValueError(f"--start-at did not match any test case: {start_at}")
    if stop_after is not None and not found_stop:
        raise ValueError(f"--stop-after did not match any selected test case: {stop_after}")
    return selected_sections


def assign_case_numbers(sections: list[TestSection]) -> None:
    """Assigns stable case numbers in the full dependency-preserving order."""
    case_number = 1
    for section in sections:
        for case in section.tests:
            case.number = case_number
            case_number += 1


def make_rerun_command(args: argparse.Namespace, section: str, case: TestCase) -> str:
    """Builds a command that reruns a section up to the target case."""
    command = [
        "python3",
        "scripts/test_apps.py",
        "--no-build",
        "--qemu-net",
        args.qemu_net,
        "--boot-timeout",
        str(args.boot_timeout),
        "--command-recover-timeout",
        str(args.command_recover_timeout),
    ]
    if section != "boot":
        command.extend(["--section", section, "--stop-after", str(case.number)])
    if args.tap_if is not None:
        command.extend(["--tap-if", args.tap_if])
    if args.skip_network_smoke:
        command.append("--skip-network-smoke")
    if args.keep_test_disk:
        command.append("--keep-test-disk")
    if args.network_test_delay != 1.0:
        command.extend(["--network-test-delay", str(args.network_test_delay)])
    if args.host_ip != "10.0.1.1":
        command.extend(["--host-ip", args.host_ip])
    return " ".join(shell_quote(item) for item in command)


def record_result(
    args: argparse.Namespace,
    records: list[TestRecord],
    section: str,
    case: TestCase,
    status: str,
    result: CommandResult,
    duration_sec: float,
) -> None:
    """Appends one result to the structured summary records."""
    category = "pass" if status == "PASS" else classify_failure(case, result.errors, result.fatal)
    records.append(
        TestRecord(
            number=case.number,
            section=section,
            name=case.name,
            command=case.command,
            status=status.lower(),
            category=category,
            duration_sec=round(duration_sec, 3),
            errors=result.errors,
            fatal=result.fatal,
            expected=expected_summary(case),
            actual=actual_summary(result.output),
            rerun_command=make_rerun_command(args, section, case),
        )
    )


def write_summary(
    path: Path,
    args: argparse.Namespace,
    qemu_command: list[str],
    records: list[TestRecord],
    failures: int,
    elapsed_sec: float,
) -> None:
    """Writes a structured test summary for flaky failure triage."""
    path.parent.mkdir(parents=True, exist_ok=True)
    summary = {
        "status": "fail" if failures else "pass",
        "failures": failures,
        "elapsed_sec": round(elapsed_sec, 3),
        "qemu_command": qemu_command,
        "options": {
            "qemu_net": args.qemu_net,
            "tap_if": args.tap_if,
            "skip_network_smoke": args.skip_network_smoke,
            "boot_timeout": args.boot_timeout,
            "command_recover_timeout": args.command_recover_timeout,
            "section": args.section,
            "start_at": args.start_at,
            "stop_after": args.stop_after,
        },
        "results": [record.__dict__ for record in records],
        "failed_results": [record.__dict__ for record in records if record.status != "pass"],
    }
    path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def print_result(status: str, case: TestCase, output: str) -> None:
    """Prints one PASS or FAIL test result with a concise output summary."""
    label = case.name
    if case.number > 0:
        label = f"#{case.number:03d} {case.name}"

    if status == "PASS":
        print("[" + "\033[32m" + "PASS" + "\033[0m" + "] " + label)
    else:
        print("[" + "\033[31m" + "FAIL" + "\033[0m" + "] " + label)
    print(f"       expected: {expected_summary(case)}")
    print(f"       actual  : {actual_summary(output)}")


def print_section(name: str) -> None:
    """Prints a category heading in test output."""
    print("")
    print("=" * 72)
    print(name)
    print("=" * 72)


def print_failure(case: TestCase, output: str, errors: list[str]) -> None:
    """Prints validation failures plus enough console tail for diagnosis."""
    print_result("FAIL", case, output)
    for error in errors:
        print(f"       {error}")
    clean = strip_ansi(output)
    tail = clean[-1200:].replace("\r", "")
    print("------- output tail -------")
    print(tail)
    print("---------------------------")


def run_and_validate(
    qemu: QemuConsole,
    case: TestCase,
    default_recover_timeout: float,
) -> CommandResult:
    """Runs one case and attempts prompt recovery after a command timeout."""
    if case.delay_before > 0:
        time.sleep(case.delay_before)

    try:
        output = qemu.run_command(case.command, case.timeout, case.append_newline)
        return CommandResult(output, validate(case, output))
    except TimeoutError as exc:
        timeout_output = qemu.buffer
        recover_timeout = (
            case.recover_timeout if case.recover_timeout is not None else default_recover_timeout
        )
        if recover_timeout <= 0:
            return CommandResult(timeout_output, [str(exc)], fatal=True)

        try:
            recovered_output = qemu.wait_for(PROMPT_MARKER, recover_timeout)
        except Exception as recover_exc:
            return CommandResult(
                qemu.buffer,
                [str(exc), f"recovery failed: {recover_exc}"],
                fatal=True,
            )

        output = timeout_output + recovered_output
        errors = validate(case, output)
        if errors:
            errors.insert(0, f"{exc}; recovered prompt after extra wait")
        return CommandResult(output, errors)
    except Exception as exc:
        return CommandResult(qemu.buffer, [str(exc)], fatal=True)


def build_sections(include_network: bool, host_ip: str, network_delay: float) -> list[TestSection]:
    """Assembles categorized cases in dependency-preserving execution order."""
    sections = [
        TestSection("shell/command tests", shell_tests()),
        TestSection("filesystem tests", filesystem_tests()),
        TestSection("runtime/service tests", runtime_tests()),
        TestSection("security/fault tests", security_tests()),
        TestSection("multi-user tests", user_tests()),
    ]
    if OPTIONAL_TOOLCHAIN_TESTS:
        optional_toolchain_tests = Path(OPTIONAL_TOOLCHAIN_TESTS)
        spec = importlib.util.spec_from_file_location(
            "optional_toolchain_app_cases",
            optional_toolchain_tests,
        )
        if spec is None or spec.loader is None:
            raise RuntimeError(f"failed to load {optional_toolchain_tests}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        sections.append(TestSection("optional toolchain tests", module.toolchain_tests(TestCase)))
    if include_network:
        sections.append(TestSection("network tests", network_tests(host_ip, network_delay)))
    return sections


def print_test_list(sections: list[TestSection]) -> None:
    """Prints the ordered test list without booting QEMU."""
    for section in sections:
        print_section(section.name)
        for case in section.tests:
            print(f"#{case.number:03d} {case.name}")
            print(f"       command: {case.command}")


def main() -> int:
    """Parses test options, boots QEMU, and reports categorized test results."""
    parser = argparse.ArgumentParser(description="Boot QEMU and smoke-test all user apps.")
    parser.add_argument("--no-build", action="store_true", help="skip make build before booting")
    parser.add_argument("--qemu-net", default="tap", choices=["user", "tap"], help="QEMU_NET value")
    parser.add_argument("--tap-if", default=None, help="QEMU_TAP_IF value when --qemu-net=tap")
    parser.add_argument("--boot-timeout", type=float, default=25.0)
    parser.add_argument("--log", default="build/test_apps_qemu.log")
    parser.add_argument(
        "--summary",
        default="build/test_apps_summary.json",
        help="write a structured JSON result summary to this path",
    )
    parser.add_argument("--no-summary", action="store_true", help="do not write a JSON summary")
    parser.add_argument("--base-disk", default="bin/disk.img")
    parser.add_argument("--test-disk", default="bin/test-disk.img")
    parser.add_argument("--keep-test-disk", action="store_true")
    parser.add_argument("--host-ip", default="10.0.1.1")
    parser.add_argument("--skip-network-smoke", action="store_true")
    parser.add_argument(
        "--network-test-delay",
        type=float,
        default=1.0,
        help="seconds to sleep before each network smoke test",
    )
    parser.add_argument(
        "--command-recover-timeout",
        type=float,
        default=20.0,
        help="extra seconds to wait for the prompt after a command timeout",
    )
    parser.add_argument(
        "--allowed-failures",
        type=int,
        default=0,
        help="allow up to this many failed test cases before returning a failing status",
    )
    parser.add_argument(
        "--section",
        action="append",
        default=[],
        help="run only matching section(s); accepts exact, normalized, or substring matches",
    )
    parser.add_argument(
        "--start-at",
        default=None,
        help="start execution at a matching case number, name, or command substring",
    )
    parser.add_argument(
        "--stop-after",
        default=None,
        help="stop after a matching case number, name, or command substring",
    )
    parser.add_argument("--list-tests", action="store_true", help="list selected tests and exit")
    args = parser.parse_args()

    sections = build_sections(
        not args.skip_network_smoke,
        args.host_ip,
        args.network_test_delay,
    )
    assign_case_numbers(sections)
    try:
        sections = select_sections(sections, args.section, args.start_at, args.stop_after)
    except ValueError as exc:
        print(f"test selection error: {exc}", file=sys.stderr)
        return 2
    if not sections:
        print("test selection error: no test cases selected", file=sys.stderr)
        return 2

    if args.list_tests:
        print_test_list(sections)
        return 0

    test_disk = Path(args.test_disk)
    prepare_test_disk(test_disk, Path(args.base_disk), args.no_build)

    env_prefix = [f"DISK_IMG={test_disk}", f"QEMU_NET={args.qemu_net}"]
    if args.tap_if is not None:
        env_prefix.append(f"QEMU_TAP_IF={args.tap_if}")

    command = ["make", *env_prefix, "qemu-run-built"]
    qemu = QemuConsole(command, Path(args.log))
    failures = 0
    failed_cases: list[TestCase] = []
    records: list[TestRecord] = []
    started_at = time.monotonic()
    try:
        boot_failed = False
        qemu.start()
        boot_start = time.monotonic()
        try:
            boot = qemu.login("root", "root", args.boot_timeout)
        except Exception as exc:
            boot = qemu.buffer
            boot_case = TestCase("boot", "")
            boot_case.number = 0
            boot_errors = [str(exc)]
            print_failure(boot_case, boot, boot_errors)
            failures += 1
            failed_cases.append(boot_case)
            record_result(
                args,
                records,
                "boot",
                boot_case,
                "FAIL",
                CommandResult(boot, boot_errors, fatal=True),
                time.monotonic() - boot_start,
            )
            boot_failed = True

        if boot_failed:
            sections = []
        else:
            boot_clean = strip_ansi(boot)
            boot_errors = []
            for expected in ["service ready procmgtd", "service ready blockd", "service ready fsd"]:
                if expected not in boot_clean:
                    boot_errors.append(f"missing boot substring {expected!r}")
            if not args.skip_network_smoke and "service ready netd" not in boot_clean:
                boot_errors.append("missing boot substring 'service ready netd'")

            if boot_errors:
                boot_case = TestCase("boot", "")
                boot_case.number = 0
                print_failure(boot_case, boot, boot_errors)
                failures += 1
                failed_cases.append(boot_case)
                record_result(
                    args,
                    records,
                    "boot",
                    boot_case,
                    "FAIL",
                    CommandResult(boot, boot_errors, fatal=True),
                    time.monotonic() - boot_start,
                )
                sections = []
            else:
                boot_case = TestCase(
                    "boot",
                    "",
                    [
                        "service ready procmgtd",
                        "service ready blockd",
                        "service ready fsd",
                        *(["service ready netd"] if not args.skip_network_smoke else []),
                    ],
                )
                boot_case.number = 0
                print_result(
                    "PASS",
                    boot_case,
                    boot,
                )
                record_result(
                    args,
                    records,
                    "boot",
                    boot_case,
                    "PASS",
                    CommandResult(boot, []),
                    time.monotonic() - boot_start,
                )

            qemu.buffer = ""

        stop = False
        for section in sections:
            if stop:
                break
            print_section(section.name)
            for case in section.tests:
                case_start = time.monotonic()
                result = run_and_validate(qemu, case, args.command_recover_timeout)
                duration_sec = time.monotonic() - case_start

                if result.errors:
                    print_failure(case, result.output, result.errors)
                    failures += 1
                    failed_cases.append(case)
                    record_result(args, records, section.name, case, "FAIL", result, duration_sec)
                    if result.fatal:
                        print("fatal console desync; stopping remaining tests")
                        stop = True
                        break
                else:
                    print_result("PASS", case, result.output)
                    record_result(args, records, section.name, case, "PASS", result, duration_sec)
    finally:
        qemu.close()
        if not args.keep_test_disk:
            test_disk.unlink(missing_ok=True)
        if not args.no_summary:
            write_summary(
                Path(args.summary),
                args,
                command,
                records,
                failures,
                time.monotonic() - started_at,
            )

    if failures:
        print(f"{failures} test(s) failed")
        print("failed test cases:")
        for case in failed_cases:
            print(f"  #{case.number:03d} {case.command}")
        if not args.no_summary:
            print(f"structured summary: {args.summary}")
        if failures <= args.allowed_failures:
            print(f"allowing {failures} failure(s); threshold is {args.allowed_failures}")
            return 0
        return 1

    print("all app smoke tests passed")
    if not args.no_summary:
        print(f"structured summary: {args.summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
