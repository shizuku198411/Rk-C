#!/usr/bin/env python3
import argparse
import os
import re
import selectors
import signal
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass, field
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
PROMPT_MARKER = "$ "


@dataclass
class TestCase:
    name: str
    command: str
    contains: list[str] = field(default_factory=list)
    regex: list[str] = field(default_factory=list)
    any_of: list[str] = field(default_factory=list)
    timeout: float = 8.0


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
    subprocess.run(["make", "build-bins"], check=True)


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
    subprocess.run(["make", f"DISK_IMG={test_disk}", "appfs"], check=True)


def start_http_server(port: int) -> tuple[ThreadingHTTPServer, tempfile.TemporaryDirectory[str]]:
    root = tempfile.TemporaryDirectory()
    index = Path(root.name) / "index.html"
    index.write_text("rk-c app test http ok\n", encoding="ascii")

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=root.name, **kwargs)

        def log_message(self, fmt: str, *args) -> None:
            return

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, root


def base_tests() -> list[TestCase]:
    tests = [
        TestCase("shell help", "help", ["available commands:", "curl", "stracectl"]),
        TestCase("shell ticks", "ticks", regex=[r"\d+"]),
        TestCase("shell traps", "traps", ["trap count:", "supervisor timer"]),
        TestCase("shell bitmap", "bitmap", ["bitmap:", "free"]),
        TestCase("shell history", "history", ["history"]),
        TestCase("shell cd", "cd /bin", []),
        TestCase("shell cwd ls", "ls", ["shell", "curl"]),
        TestCase("shell cd root", "cd /", []),
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
    }
    for app, expected in help_cases.items():
        tests.append(TestCase(f"{app} --help", f"{app} --help", [expected]))

    tests.extend(
        [
            TestCase("ls /bin", "ls /bin", ["shell", "svcmgtd", "curl"]),
            TestCase("ls -l /bin", "ls -l /bin", ["shell", "bytes"]),
            TestCase("mkdir /tmp/appsmoke", "mkdir /tmp/appsmoke", []),
            TestCase("ls /tmp after mkdir", "ls /tmp", ["appsmoke/"]),
            TestCase("rmdir /tmp/appsmoke", "rmdir /tmp/appsmoke", []),
            TestCase("date", "date", regex=[r"\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}"]),
            TestCase("redirection creates file", "date > /tmp/date_smoke", []),
            TestCase("cat redirected file", "cat /tmp/date_smoke", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("pipe cat", "cat /tmp/date_smoke | cat", regex=[r"\d{4}/\d{2}/\d{2}"]),
            TestCase("rm redirected file", "rm /tmp/date_smoke", []),
            TestCase("ps", "ps", ["pid", "ppid", "svcmgtd", "shell"]),
            TestCase("svc list", "svc list", ["service", "procmgtd", "blockd", "fsd", "netd"]),
            TestCase("kill invalid pid", "kill 999", ["kill: failed"]),
            TestCase("ipc invalid send", "ipc send 999 hello", ["usage:"]),
            TestCase("stracectl app", "stracectl ls /bin", ["shell", "curl"], timeout=12.0),
            TestCase("stracectl on", "stracectl on", ["strace on"]),
            TestCase("stracectl off", "stracectl off", ["strace off"]),
            TestCase(
                "ping gateway",
                "ping 10.0.2.2",
                ["PING 10.0.2.2"],
                any_of=["reply from", "timeout from"],
                timeout=12.0,
            ),
        ]
    )
    return tests


def network_tests(host_ip: str, host_http_port: int) -> list[TestCase]:
    return [
        TestCase(
            "tcpcheck host http port",
            f"tcpcheck {host_ip} {host_http_port}",
            ["tcpcheck: connecting"],
            any_of=["tcpcheck: connected", "tcpcheck: connect failed"],
            timeout=14.0,
        ),
        TestCase(
            "curl host http",
            f"curl http://{host_ip}:{host_http_port}/",
            [],
            any_of=["rk-c app test http ok", "curl: HTTP request failed"],
            timeout=14.0,
        ),
        TestCase(
            "nslookup example.com",
            "nslookup example.com",
            ["Name: example.com"],
            any_of=["Address:", "nslookup: no A record"],
            timeout=14.0,
        ),
    ]


def validate(case: TestCase, output: str) -> list[str]:
    clean = strip_ansi(output)
    errors = []
    for expected in case.contains:
        if expected not in clean:
            errors.append(f"missing substring {expected!r}")
    for pattern in case.regex:
        if not re.search(pattern, clean):
            errors.append(f"missing regex {pattern!r}")
    if case.any_of and not any(item in clean for item in case.any_of):
        errors.append(f"missing one of {case.any_of!r}")
    return errors


def print_failure(case: TestCase, output: str, errors: list[str]) -> None:
    print(f"[FAIL] {case.name}")
    for error in errors:
      print(f"       {error}")
    clean = strip_ansi(output)
    tail = clean[-1200:].replace("\r", "")
    print("------- output tail -------")
    print(tail)
    print("---------------------------")


def main() -> int:
    parser = argparse.ArgumentParser(description="Boot QEMU and smoke-test all user apps.")
    parser.add_argument("--no-build", action="store_true", help="skip make build before booting")
    parser.add_argument("--qemu-net", default="user", choices=["user", "tap"], help="QEMU_NET value")
    parser.add_argument("--tap-if", default=None, help="QEMU_TAP_IF value when --qemu-net=tap")
    parser.add_argument("--boot-timeout", type=float, default=25.0)
    parser.add_argument("--log", default="build/test_apps_qemu.log")
    parser.add_argument("--base-disk", default="bin/disk.img")
    parser.add_argument("--test-disk", default="bin/test-disk.img")
    parser.add_argument("--keep-test-disk", action="store_true")
    parser.add_argument("--host-ip", default="10.0.2.2")
    parser.add_argument("--host-http-port", type=int, default=18080)
    parser.add_argument("--skip-network-smoke", action="store_true")
    args = parser.parse_args()

    test_disk = Path(args.test_disk)
    prepare_test_disk(test_disk, Path(args.base_disk), args.no_build)

    http_server = None
    http_root = None
    if not args.skip_network_smoke:
        http_server, http_root = start_http_server(args.host_http_port)

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
        if args.qemu_net == "user" and "service ready netd" not in boot_clean:
            boot_errors.append("missing boot substring 'service ready netd'")

        if boot_errors:
            print_failure(TestCase("boot", ""), boot, boot_errors)
            failures += 1
        else:
            print("[PASS] boot")

        qemu.buffer = ""
        tests = base_tests()
        if not args.skip_network_smoke:
            tests.extend(network_tests(args.host_ip, args.host_http_port))

        for case in tests:
            try:
                out = qemu.run_command(case.command, case.timeout)
                errors = validate(case, out)
            except Exception as exc:
                out = qemu.buffer
                errors = [str(exc)]

            if errors:
                print_failure(case, out, errors)
                failures += 1
            else:
                print(f"[PASS] {case.name}")
    finally:
        qemu.close()
        if http_server is not None:
            http_server.shutdown()
            http_server.server_close()
        if http_root is not None:
            http_root.cleanup()
        if not args.keep_test_disk:
            test_disk.unlink(missing_ok=True)

    if failures:
        print(f"{failures} test(s) failed")
        return 1

    print("all app smoke tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
