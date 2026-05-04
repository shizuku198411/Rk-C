.section .text

.global user_raw_syscall3
user_raw_syscall3:
    mv t0, a3
    mv a3, a0
    mv a0, a1
    mv a1, a2
    mv a2, t0
    ecall
    ret
