"""Process, procfs, service manager, and syscall trace smoke test cases."""
from .model import TestCase


def runtime_tests() -> list[TestCase]:
    """Returns process observation and service runtime behavior tests."""
    input_burst = "inputcheck\n" + ("x" * 4096)

    return [
        TestCase("ps", "ps", ["pid", "exe", "shell"]),
        TestCase("id", "id", ["uid=0", "gid=0"]),
        TestCase("ps -f", "ps -f", ["pid", "ppid", "uid", "gid", "state", "mode", "shell"]),
        TestCase("ps -l", "ps -l", ["pid", "ppid", "uid", "gid", "cpu", "mem", "shell"]),
        TestCase("ps -ef", "ps -ef", ["pid", "ppid", "uid", "gid", "state", "mode", "svcmgtd"]),
        TestCase("ps -e -f", "ps -e -f", ["pid", "ppid", "uid", "gid", "state", "mode", "svcmgtd"]),
        TestCase(
            "ls /proc",
            "ls /proc",
            ["uptime", "cpuinfo", "kmsg", "3/", "4/", "5/", "6/", "7/", "8/", "9/"],
            not_contains=["./", "../"],
            regex=[r"\d+/"],
        ),
        TestCase(
            "ls -a /proc",
            "ls -a /proc",
            ["./", "../", "uptime", "cpuinfo", "kmsg", "3/", "4/", "5/", "6/", "7/", "8/", "9/"],
            regex=[r"\d+/"],
        ),
        TestCase("cat /proc/processes", "cat /proc/processes", ["pid", "ppid", "uid", "gid", "exe"]),
        TestCase("cat /proc/fsinfo", "cat /proc/fsinfo", ["Filesystem", "rootfs", "tmpfs", "appfs", "/bin"]),
        TestCase(
            "console 4096-byte burst",
            input_burst,
            ["inputcheck: 4096-byte burst ok"],
            timeout=15.0,
            append_newline=False,
        ),
        TestCase(
            "cat /proc/tty",
            "cat /proc/tty",
            ["capacity: 4096", "buffered:", "received:", "dropped: 0"],
        ),
        TestCase(
            "standard input references tty0",
            "cat /proc/1/fd/0",
            ["kind: tty", "tty_id: 0", "path: /dev/stdin"],
        ),
        TestCase("write through /dev/tty0", "echo tty0-ok > /dev/tty0", ["tty0-ok"]),
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
        TestCase("cat /proc/3/status", "cat /proc/3/status", ["pid: 3", "uid: 0", "gid: 0", "exe: /bin/svcmgtd"]),
        TestCase("svc list", "svc list", ["service", "procmgtd", "blockd", "fsd", "netd"]),
        TestCase("svc status", "svc status", ["service", "state", "starts", "restarts", "ready_tick", "procmgtd"]),
        TestCase("svc status netd", "svc status netd", ["netd", "reason"]),
        TestCase("svc degraded", "svc degraded", ["service", "state"]),
        TestCase("svc logs", "svc logs", ["started", "ready"]),
        TestCase("rkxinfo svc root only", "rkxinfo svc", ["path: /bin/svc", "allowed_uids: 0"]),
        TestCase("rkxinfo ls all users", "rkxinfo ls", ["path: /bin/ls", "allowed_uids: all"]),
        TestCase("stracectl app", "stracectl ls /bin", ["shell", "tcpcheck", "curl"], timeout=12.0),
        TestCase("stracectl on", "stracectl on", ["strace on"]),
        TestCase("stracectl off", "stracectl off", ["strace off"]),
    ]
