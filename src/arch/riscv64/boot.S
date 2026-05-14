.section .text.boot
.global boot
boot:
.option push
.option norelax
    lla gp, __global_pointer$
.option pop
    lla t0, __stack_top
    mv sp, t0
    csrw sscratch, sp
    j kernel_main
