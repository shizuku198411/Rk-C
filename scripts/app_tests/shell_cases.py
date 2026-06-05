"""Shell navigation and command help smoke test cases."""
from .model import TestCase


def shell_tests() -> list[TestCase]:
    """Returns shell built-in, path navigation, and application help tests."""
    tests = [
        TestCase("shell help", "help", ["available commands:", "curl", "stracectl", "dmesg", "which"]),
        TestCase("shell ticks", "ticks", regex=[r"\d+"]),
        TestCase("shell traps", "traps", ["trap count:", "supervisor timer", "supervisor external"]),
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
        "chown": "usage: chown",
        "passwd": "usage: passwd",
        "capcheck": "usage: capcheck",
        "pollcheck": "usage: pollcheck",
        "writecheck": "usage: writecheck",
        "heapcheck": "usage: heapcheck",
        "orccheck": "usage: orccheck",
        "which": "usage: which",
        "login": "cannnot execute /bin/login directly from shell.",
    }
    for app, expected in help_cases.items():
        tests.append(TestCase(f"{app} --help", f"{app} --help", [expected]))

    return tests
