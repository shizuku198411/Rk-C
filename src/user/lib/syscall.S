.section .text

.global user_sys_write
user_sys_write:
    li a3, 1
    ecall
    ret

.global user_sys_read
user_sys_read:
    li a3, 2
    ecall
    ret

.global user_sys_ps
user_sys_ps:
    li a3, 3
    ecall
    ret

.global user_sys_ticks
user_sys_ticks:
    li a3, 4
    ecall
    ret

.global user_sys_exit
user_sys_exit:
    li a3, 5
    ecall
1:
    wfi
    j 1b

.global user_sys_ls
user_sys_ls:
    li a3, 6
    ecall
    ret

.global user_sys_cat
user_sys_cat:
    li a3, 7
    ecall
    ret

.global user_sys_mkdir
user_sys_mkdir:
    li a3, 9
    ecall
    ret

.global user_sys_exec
user_sys_exec:
    li a3, 11
    ecall
    ret

.global user_sys_wait
user_sys_wait:
    li a3, 12
    ecall
    ret

.global user_sys_unlink
user_sys_unlink:
    li a3, 13
    ecall
    ret

.global user_sys_rmdir
user_sys_rmdir:
    li a3, 14
    ecall
    ret

.global user_sys_shutdown
user_sys_shutdown:
    li a3, 15
    ecall

.global user_sys_getdatetime
user_sys_getdatetime:
    li a3, 16
    ecall
    ret
