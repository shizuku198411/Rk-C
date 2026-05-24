#!/usr/bin/env python3
"""Boots Rk-C on QEMU and executes categorized application smoke tests."""
import argparse
import importlib.util
import os
import re
import selectors
import signal
import subprocess
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
TEST_APP_NAMES = ["faultcheck", "capcheck", "pollcheck", "signalcheck", "writecheck", "heapcheck", "orccheck"]
OPTIONAL_TOOLCHAIN_TESTS = os.environ.get("RKC_OPTIONAL_TOOLCHAIN_TESTS", "")
OPTIONAL_TOOLCHAIN_TEST_APPS = os.environ.get("RKC_OPTIONAL_TOOLCHAIN_TEST_APPS", "").split()


@dataclass
class CommandResult:
    """Stores a command response and validation outcome."""

    output: str
    errors: list[str]
    fatal: bool = False


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


def main() -> int:
    """Parses test options, boots QEMU, and reports categorized test results."""
    parser = argparse.ArgumentParser(description="Boot QEMU and smoke-test all user apps.")
    parser.add_argument("--no-build", action="store_true", help="skip make build before booting")
    parser.add_argument("--qemu-net", default="tap", choices=["user", "tap"], help="QEMU_NET value")
    parser.add_argument("--tap-if", default=None, help="QEMU_TAP_IF value when --qemu-net=tap")
    parser.add_argument("--boot-timeout", type=float, default=25.0)
    parser.add_argument("--log", default="build/test_apps_qemu.log")
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
    args = parser.parse_args()

    test_disk = Path(args.test_disk)
    prepare_test_disk(test_disk, Path(args.base_disk), args.no_build)

    env_prefix = [f"DISK_IMG={test_disk}", f"QEMU_NET={args.qemu_net}"]
    if args.tap_if is not None:
        env_prefix.append(f"QEMU_TAP_IF={args.tap_if}")

    command = ["make", *env_prefix, "qemu-run-built"]
    qemu = QemuConsole(command, Path(args.log))
    failures = 0
    failed_cases: list[TestCase] = []
    case_number = 1
    try:
        qemu.start()
        boot = qemu.login("root", "root", args.boot_timeout)
        boot_clean = strip_ansi(boot)
        boot_errors = []
        for expected in ["service ready procmgtd", "service ready blockd", "service ready fsd"]:
            if expected not in boot_clean:
                boot_errors.append(f"missing boot substring {expected!r}")
        if not args.skip_network_smoke and "service ready netd" not in boot_clean:
            boot_errors.append("missing boot substring 'service ready netd'")

        if boot_errors:
            print_failure(TestCase("boot", ""), boot, boot_errors)
            failures += 1
        else:
            print_result(
                "PASS",
                TestCase(
                    "boot",
                    "",
                    [
                        "service ready procmgtd",
                        "service ready blockd",
                        "service ready fsd",
                        *(["service ready netd"] if not args.skip_network_smoke else []),
                    ],
                ),
                boot,
            )

        qemu.buffer = ""
        sections = build_sections(
            not args.skip_network_smoke,
            args.host_ip,
            args.network_test_delay,
        )

        stop = False
        for section in sections:
            if stop:
                break
            print_section(section.name)
            for case in section.tests:
                case.number = case_number
                case_number += 1
                result = run_and_validate(qemu, case, args.command_recover_timeout)

                if result.errors:
                    print_failure(case, result.output, result.errors)
                    failures += 1
                    failed_cases.append(case)
                    if result.fatal:
                        print("fatal console desync; stopping remaining tests")
                        stop = True
                        break
                else:
                    print_result("PASS", case, result.output)
    finally:
        qemu.close()
        if not args.keep_test_disk:
            test_disk.unlink(missing_ok=True)

    if failures:
        print(f"{failures} test(s) failed")
        print("failed test cases:")
        for case in failed_cases:
            print(f"  #{case.number:03d} {case.command}")
        if failures <= args.allowed_failures:
            print(f"allowing {failures} failure(s); threshold is {args.allowed_failures}")
            return 0
        return 1

    print("all app smoke tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
