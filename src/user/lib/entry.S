.section .user_entry, "ax"
.balign 16
.global user_entry
user_entry:
    tail user_start
