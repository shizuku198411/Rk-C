.section .text.boot
.global boot
boot:
    lla t0, __stack_top
    mv sp, t0
    csrw sscratch, sp
    j kernel_main
