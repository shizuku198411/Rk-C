"""Invalid operation, protection boundary, and fault handling test cases."""
from .model import TestCase


def security_tests() -> list[TestCase]:
    """Returns negative-path, capability, heap, and fault isolation tests."""
    overlong_command = "a" * 75

    return [
        TestCase("missing command", "definitely_missing_command", ["command not found: /bin/definitely_missing_command"]),
        TestCase("deny truncated command path", overlong_command, ["command path too long"]),
        TestCase("deny server binary in pipeline", "echo ok | userd", ["cannnot execute /bin/userd directly from shell."]),
        TestCase("kill invalid pid", "kill 999", ["kill: failed"]),
        TestCase("svc stop required service", "svc stop fsd", ["cannot stop required service"]),
        TestCase("ipc invalid send", "ipc send 999 hello", ["ipc: send failed"]),
        TestCase("deny write under /bin", "ls > /bin/ls.txt", ["redirect: failed to open /bin/ls.txt"]),
        TestCase("deny mkdir under /bin", "mkdir /bin/scratch", ["mkdir: failed"]),
        TestCase("deny unlink under /bin", "rm /bin/ls", ["rm: failed"]),
        TestCase("deny read-only dev stdout", "cat /dev/stdout", ["cat: failed"]),
        TestCase("deny invalid chown target", "chown 123:456 /tmp/chown_user_file", ["chown: invalid argument"]),
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
                "writecheck: large rootfs write ok",
                "writecheck: released blocks reused ok",
                "writecheck: ok",
            ],
            timeout=12.0,
        ),
        TestCase("heapcheck user heap", "heapcheck", ["heapcheck: ok"], timeout=12.0),
        TestCase(
            "orccheck managed heap",
            "orccheck",
            [
                "orccheck: allocator release ok",
                "orccheck: string ok",
                "orccheck: seq ok",
                "orccheck: ref ok",
                "orccheck: ok",
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
            ["pid=", "exe=/bin/faultcheck", "scause=", "stval=", "sepc=", "sp=", "a0=", "a1=", "a2=", "a3="],
        ),
    ]
