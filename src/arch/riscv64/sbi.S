.section .text
.global sbi_putchar
sbi_putchar:
    li a7, 1
    li a6, 0
    ecall
    ret

.global sbi_getchar
sbi_getchar:
    li a7, 2
    li a6, 0
    ecall
    ret

.global sbi_shutdown
sbi_shutdown:
    li a7, 8
    li a6, 0
    ecall
    j loop
loop:
    wfi
    j loop
