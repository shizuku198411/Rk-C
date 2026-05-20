#!/usr/bin/env python3
import argparse
import os
import re
import selectors
import signal
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path


ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
PROMPT_MARKER = "$ "
TEST_APP_NAMES = ["faultcheck", "capcheck", "pollcheck", "signalcheck", "writecheck"]


@dataclass
class TestCase:
    name: str
    command: str
    contains: list[str] = field(default_factory=list)
    not_contains: list[str] = field(default_factory=list)
    regex: list[str] = field(default_factory=list)
    any_of: list[str] = field(default_factory=list)
    timeout: float = 8.0
    recover_timeout: float | None = None
    delay_before: float = 0.0


@dataclass
class CommandResult:
    output: str
    errors: list[str]
    fatal: bool = False


@dataclass
class TestSection:
    name: str
    tests: list[TestCase]


class QemuConsole:
    def __init__(self, command: list[str], log_path: Path | None = None):
        self.command = command
        self.log_path = log_path
        self.proc: subprocess.Popen[bytes] | None = None
        self.selector = selectors.DefaultSelector()
        self.buffer = ""
        self.log_file = None

    def start(self) -> None:
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
        if self.proc is None or self.proc.stdin is None:
            raise RuntimeError("QEMU is not running")
        self.proc.stdin.write(data.encode("utf-8"))
        self.proc.stdin.flush()

    def read_some(self, timeout: float) -> str:
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
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if needle in self.buffer:
                out = self.buffer
                self.buffer = ""
                return out
            self.buffer += self.read_some(max(0.05, min(0.5, deadline - time.monotonic())))
        raise TimeoutError(f"timed out waiting for {needle!r}")

    def run_command(self, command: str, timeout: float) -> str:
        self.buffer = ""
        self.send(command + "\n")
        return self.wait_for(PROMPT_MARKER, timeout)


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def run_build() -> None:
    subprocess.run(["make", "build-test-bins"], check=True)


def prepare_test_disk(test_disk: Path, base_disk: Path, no_build: bool) -> None:
    test_disk.parent.mkdir(parents=True, exist_ok=True)
    test_disk.unlink(missing_ok=True)
    if not no_build:
        run_build()

    if not base_disk.exists():
        raise FileNotFoundError(
            f"base disk image not found: {base_disk}; run make build once or pass --base-disk"
        )

    shutil.copyfile(base_disk, test_disk)
    subprocess.run(
        ["make", f"DISK_IMG={test_disk}", f"APPFS_EXTRA_APPS={' '.join(TEST_APP_NAMES)}", "appfs"],
        check=True,
    )


def normal_tests() -> list[TestCase]:
    tests = [
        TestCase("shell help", "help", ["available commands:", "curl", "stracectl", "dmesg"]),
        TestCase("shell ticks", "ticks", regex=[r"\d+"]),
        TestCase("shell traps", "traps", ["trap count:", "supervisor timer"]),
        TestCase("shell bitmap", "bitmap", ["bitmap:", "free"]),
        TestCase("shell history", "history", ["history"]),
        TestCase("shell cd", "cd /bin", []),
        TestCase("shell cwd ls", "ls", ["shell", "tcpcheck", "curl"]),
        TestCase("shell cd dot", "cd .", []),
        TestCase("shell pwd after dot", "pwd", ["/bin"]),
        TestCase("shell cd parent", "cd ..", []),
        TestCase("shell pwd after parent", "pwd", ["/"]),
        TestCase("shell cd root", "cd /", []),
        TestCase("shell cd etc", "cd /etc", []),
        TestCase("wc relative path", "wc interface.conf", ["/etc/interface.conf"], regex=[r"\d+ \d+ \d+ /etc/interface\.conf"]),
        TestCase("shell cd root after wc", "cd /", []),
    ]

    help_cases = {
        "ls": "usage: ls",
        "cat": "usage: cat",
        "mkdir": "usage: mkdir",
        "rm": "usage: rm",
        "rmdir": "usage: rmdir",
        "date": "usage: date",
        "edit": "usage: edit",
        "ipc": "usage:",
        "kill": "usage: kill",
        "svc": "usage:",
        "ping": "usage: ping",
        "nslookup": "usage: nslookup",
        "tcpcheck": "usage: tcpcheck",
        "curl": "usage: curl",
        "stracectl": "usage:",
        "dmesg": "usage: dmesg",
        "rkxinfo": "usage: rkxinfo",
        "echo": "usage: echo",
        "touch": "usage: touch",
        "cp": "usage: cp",
        "mv": "usage: mv",
        "df": "usage: df",
        "paniclog": "usage: paniclog",
        "id": "usage: id",
        "chmod": "usage: chmod",
        "capcheck": "usage: capcheck",
        "pollcheck": "usage: pollcheck",
        "writecheck": "usage: writecheck",
    }
    for app, expected in help_cases.items():
        tests.append(TestCase(f"{app} --help", f"{app} --help", [expected]))

    tests.extend(
        [
            TestCase("ls root dirs", "ls /", ["var/"], not_contains=["var/log/"]),
            TestCase("ls /var", "ls /var", ["log/"]),
            TestCase("ls /bin", "ls /bin", ["shell", "svcmgtd", "tcpcheck", "curl", "dmesg"], not_contains=["./", "../"]),
            TestCase("ls -a dot entries", "ls -a /bin", ["./", "../", "shell"]),
            TestCase("ls -al dot entries", "ls -al /bin", ["./", "../", "shell", "bytes"]),
            TestCase("ls parent path", "ls /bin/..", ["bin/", "tmp/"]),
            TestCase("ls -l /bin", "ls -l /bin", ["shell", "bytes"]),
            TestCase("touch chmod target", "touch /tmp/chmod_smoke", []),
            TestCase("ls -l default mode", "ls -l /tmp", ["-rw-r--r--", "0:0", "chmod_smoke"]),
            TestCase("chmod 600", "chmod 600 /tmp/chmod_smoke", []),
            TestCase("ls -l chmod 600", "ls -l /tmp", ["-rw-------", "0:0", "chmod_smoke"]),
            TestCase("rm chmod target", "rm /tmp/chmod_smoke", []),
            TestCase("rkxinfo curl", "rkxinfo curl", ["path: /bin/curl", "magic: RKX1", "version: 2", "text:", "stack_pages:"]),
            TestCase("mkdir /tmp/appsmoke", "mkdir /tmp/appsmoke", []),
            TestCase("ls /tmp after mkdir", "ls /tmp", ["appsmoke/"]),
            TestCase("rmdir /tmp/appsmoke", "rmdir /tmp/appsmoke", []),
            TestCase("date", "date", regex=[r"\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}"]),
            TestCase("redirection creates file", "date > /tmp/date_smoke", []),
            TestCase("cat redirected file", "cat /tmp/date_smoke", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("pipe cat", "cat /tmp/date_smoke | cat", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("cp file", "cp /tmp/date_smoke /tmp/date_copy", []),
            TestCase("cat copied file", "cat /tmp/date_copy", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("mv rename file", "mv /tmp/date_copy /tmp/date_moved", []),
            TestCase("cat renamed file", "cat /tmp/date_moved", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("mkdir /tmp/mvdir", "mkdir /tmp/mvdir", []),
            TestCase("prepare rootfs mv file", "date > /mv_cross", []),
            TestCase("mv rootfs file into tmpfs directory", "mv /mv_cross /tmp", []),
            TestCase("cat rootfs file moved into tmpfs", "cat /tmp/mv_cross", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("mv tmpfs file with new name", "mv /tmp/mv_cross /tmp/mv_cross_renamed", []),
            TestCase("cat renamed tmpfs file", "cat /tmp/mv_cross_renamed", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("prepare rootfs mv file explicit dst", "date > /mv_cross2", []),
            TestCase("mv rootfs file to explicit tmpfs path", "mv /mv_cross2 /tmp/mv_cross2_renamed", []),
            TestCase("cat explicit tmpfs path", "cat /tmp/mv_cross2_renamed", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("mv file into directory", "mv /tmp/date_moved /tmp/mvdir", []),
            TestCase("cat moved file", "cat /tmp/mvdir/date_moved", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("prepare mv multi file a", "date > /tmp/mv_a", []),
            TestCase("prepare mv multi file b", "date > /tmp/mv_b", []),
            TestCase("mv multiple files", "mv /tmp/mv_a /tmp/mv_b /tmp/mvdir", []),
            TestCase("cat moved multi file a", "cat /tmp/mvdir/mv_a", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("cat moved multi file b", "cat /tmp/mvdir/mv_b", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("rm moved file", "rm /tmp/mvdir/date_moved", []),
            TestCase("rm moved multi file a", "rm /tmp/mvdir/mv_a", []),
            TestCase("rm moved multi file b", "rm /tmp/mvdir/mv_b", []),
            TestCase("rm cross moved file", "rm /tmp/mv_cross_renamed", []),
            TestCase("rm explicit cross moved file", "rm /tmp/mv_cross2_renamed", []),
            TestCase("rmdir /tmp/mvdir", "rmdir /tmp/mvdir", []),
            TestCase("rm redirected file", "rm /tmp/date_smoke", []),
            TestCase("ps", "ps", ["pid", "exe", "shell"]),
            TestCase("id", "id", ["uid=0", "gid=0"]),
            TestCase("ps -f", "ps -f", ["pid", "ppid", "uid", "gid", "state", "mode", "shell"]),
            TestCase("ps -l", "ps -l", ["pid", "ppid", "uid", "gid", "cpu", "mem", "shell"]),
            TestCase("ps -ef", "ps -ef", ["pid", "ppid", "uid", "gid", "state", "mode", "svcmgtd"]),
            TestCase("ps -e -f", "ps -e -f", ["pid", "ppid", "uid", "gid", "state", "mode", "svcmgtd"]),
            TestCase("ls /proc", "ls /proc", ["uptime", "cpuinfo", "kmsg"], not_contains=["./", "../"], regex=[r"\d+/"]),
            TestCase("ls -a /proc", "ls -a /proc", ["./", "../", "uptime", "cpuinfo", "kmsg"], regex=[r"\d+/"]),
            TestCase("cat /proc/processes", "cat /proc/processes", ["pid", "ppid", "uid", "gid", "exe"]),
            TestCase("cat /proc/fsinfo", "cat /proc/fsinfo", ["Filesystem", "rootfs", "tmpfs", "appfs", "/bin"]),
            TestCase("df", "df", ["Filesystem", "rootfs", "tmpfs", "appfs", "Mounted on"]),
            TestCase("shell cd /proc", "cd /proc", []),
            TestCase("shell pwd after cd /proc", "pwd", ["/proc"]),
            TestCase("shell ls proc cwd", "ls", ["uptime", "cpuinfo", "kmsg"], not_contains=["./", "../"], regex=[r"\d+/"]),
            TestCase("shell cd proc pid", "cd 1", []),
            TestCase("shell pwd after cd proc pid", "pwd", ["/proc/1"]),
            TestCase("shell ls proc pid cwd", "ls", ["status", "rkx_map"], not_contains=["./", "../"]),
            TestCase("shell cd proc parent", "cd ..", []),
            TestCase("shell pwd after cd proc parent", "pwd", ["/proc"]),
            TestCase("shell cd root after proc", "cd /", []),
            TestCase("dmesg", "dmesg", ["[boot]", "set trap vector"]),
            TestCase("cat /proc/kmsg", "cat /proc/kmsg", ["[boot]"]),
            TestCase("cat /proc/uptime", "cat /proc/uptime", ["ticks:"], regex=[r"uptime: \d{2}:\d{2}:\d{2}"]),
            TestCase("ls /proc/1", "ls /proc/1", ["status", "rkx_map"], not_contains=["./", "../"]),
            TestCase("cat /proc/1/status", "cat /proc/1/status", ["pid: 1", "uid: 0", "gid: 0", "cpu:", "mem:", "exe: init"]),
            TestCase("cat /proc/3/rkx_map", "cat /proc/3/rkx_map", ["r-x text", "r-- rodata", "rw- stack"]),
            TestCase("svc list", "svc list", ["service", "procmgtd", "blockd", "fsd", "netd"]),
            TestCase("svc status", "svc status", ["service", "state", "starts", "restarts", "ready_tick", "procmgtd"]),
            TestCase("svc status netd", "svc status netd", ["netd", "reason"]),
            TestCase("svc degraded", "svc degraded", ["service", "state"]),
            TestCase("svc logs", "svc logs", ["started", "ready"]),
            TestCase("stracectl app", "stracectl ls /bin", ["shell", "tcpcheck", "curl"], timeout=12.0),
            TestCase("stracectl on", "stracectl on", ["strace on"]),
            TestCase("stracectl off", "stracectl off", ["strace off"]),
        ]
    )
    return tests


def abnormal_tests() -> list[TestCase]:
    return [
        TestCase("kill invalid pid", "kill 999", ["kill: failed"]),
        TestCase("svc stop required service", "svc stop fsd", ["cannot stop required service"]),
        TestCase("ipc invalid send", "ipc send 999 hello", ["ipc: send failed"]),
        TestCase("deny write under /bin", "ls > /bin/ls.txt", ["redirect: failed to open /bin/ls.txt"]),
        TestCase("deny mkdir under /bin", "mkdir /bin/scratch", ["mkdir: failed"]),
        TestCase("deny unlink under /bin", "rm /bin/ls", ["rm: failed"]),
        TestCase(
            "pollcheck event wait",
            "pollcheck",
            [
                "pollcheck: ipc empty ok",
                "pollcheck: timer ok",
                "pollcheck: pipe read empty ok",
                "pollcheck: pipe write ready ok",
                "pollcheck: pipe read ready ok",
                "pollcheck: invalid fd error ok",
                "pollcheck: ok",
            ],
            timeout=12.0,
        ),
        TestCase(
            "signalcheck process events",
            "signalcheck",
            [
                "signalcheck: child wait ok",
                "signalcheck: child_exited signal ok",
                "signalcheck: empty signal queue ok",
                "signalcheck: ok",
            ],
            timeout=12.0,
        ),
        TestCase(
            "writecheck file write modes",
            "writecheck",
            [
                "writecheck: create overwrite ok",
                "writecheck: append existing ok",
                "writecheck: overwrite existing ok",
                "writecheck: append missing denied ok",
                "writecheck: create append ok",
                "writecheck: invalid flags denied ok",
                "writecheck: ok",
            ],
            timeout=12.0,
        ),
        TestCase(
            "capcheck unauthorized rkx caps",
            "capcheck",
            [
                "capcheck: requested caps visible",
                "capcheck: requested cap names visible",
                "capcheck: granted caps stripped",
                "capcheck: raw_net denied",
                "capcheck: process_list denied",
                "capcheck: forged kill denied",
                "capcheck: ok",
            ],
            timeout=12.0,
        ),
        *[
            TestCase("faultcheck --help", "faultcheck --help", ["usage: faultcheck"]),
            TestCase("faultcheck bad cstring", "faultcheck bad-cstring", ["bad-cstring: rejected"]),
            TestCase(
                "faultcheck write text",
                "faultcheck write-text",
                ["write-text: touching text"],
                any_of=[
                    "PAGE FAULT DETECTED: Store/AMO Page Fault",
                    "PAGE FAULT DETECTED: Store/AMO Access Fault",
                ],
                timeout=10.0,
            ),
            TestCase(
                "faultcheck exec stack",
                "faultcheck exec-stack",
                ["exec-stack: jumping to stack"],
                any_of=[
                    "PAGE FAULT DETECTED: Instruction Page Fault",
                    "PAGE FAULT DETECTED: Instruction Access Fault",
                ],
                timeout=10.0,
            ),
            TestCase(
                "user panic log",
                "paniclog",
                [
                    "pid=",
                    "exe=/bin/faultcheck",
                    "scause=",
                    "stval=",
                    "sepc=",
                    "sp=",
                    "a0=",
                    "a1=",
                    "a2=",
                    "a3=",
                ],
            ),
        ],
    ]


def network_tests(host_ip: str, delay: float) -> list[TestCase]:
    return [
        TestCase(
            "ping gateway",
            f"ping {host_ip}",
            [f"PING {host_ip}"],
            any_of=["reply from", "timeout from"],
            timeout=12.0,
            delay_before=delay,
        ),
        TestCase(
            "nslookup example.com",
            "nslookup example.com",
            ["Name: example.com"],
            any_of=["Address:", "nslookup: no A record"],
            timeout=30.0,
            delay_before=delay,
        ),
        TestCase(
            "curl example.com http",
            "curl -i http://example.com",
            ["HTTP/1.1 200 OK"],
            timeout=30.0,
            recover_timeout=120.0,
            delay_before=delay,
        ),
        TestCase(
            "curl example.com https",
            "curl -v https://example.com",
            ["TLS: TLS1.3"],
            timeout=45.0,
            recover_timeout=180.0,
            delay_before=delay,
        ),
    ]


def validate(case: TestCase, output: str) -> list[str]:
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
    clean = strip_ansi(output).replace("\r", "")
    lines = [line.rstrip() for line in clean.splitlines()]
    lines = [line for line in lines if line.strip()]
    text = " | ".join(lines)
    if len(text) > limit:
        text = "..." + text[-limit:]
    return text


def print_result(status: str, case: TestCase, output: str) -> None:
    print(f"[{status}] {case.name}")
    print(f"       expected: {expected_summary(case)}")
    print(f"       actual  : {actual_summary(output)}")


def print_section(name: str) -> None:
    print("")
    print("=" * 72)
    print(name)
    print("=" * 72)


def print_failure(case: TestCase, output: str, errors: list[str]) -> None:
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
    if case.delay_before > 0:
        time.sleep(case.delay_before)

    try:
        output = qemu.run_command(case.command, case.timeout)
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


def main() -> int:
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
    args = parser.parse_args()

    test_disk = Path(args.test_disk)
    prepare_test_disk(test_disk, Path(args.base_disk), args.no_build)

    env_prefix = [f"DISK_IMG={test_disk}", f"QEMU_NET={args.qemu_net}"]
    if args.tap_if is not None:
        env_prefix.append(f"QEMU_TAP_IF={args.tap_if}")

    command = ["make", *env_prefix, "qemu-run-built"]
    qemu = QemuConsole(command, Path(args.log))
    failures = 0
    try:
        qemu.start()
        boot = qemu.wait_for(PROMPT_MARKER, args.boot_timeout)
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
        sections = [
            TestSection("normal tests", normal_tests()),
            TestSection("abnormal/security tests", abnormal_tests()),
        ]
        if not args.skip_network_smoke:
            sections.append(TestSection("network tests", network_tests(args.host_ip, args.network_test_delay)))

        stop = False
        for section in sections:
            if stop:
                break
            print_section(section.name)
            for case in section.tests:
                result = run_and_validate(
                    qemu,
                    case,
                    args.command_recover_timeout,
                )

                if result.errors:
                    print_failure(case, result.output, result.errors)
                    failures += 1
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
        return 1

    print("all app smoke tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
