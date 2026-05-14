.section .user_entry, "ax"
.balign 16
.global user_entry
user_entry:
.option push
.option norelax
    lla gp, __global_pointer$
.option pop
    tail user_start
