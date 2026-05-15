.section .text.boot
.global boot
boot:
    # OpenSBI passes:
    #   a0 = hartid
    #   a1 = fdt address
    #
    # currently Rk-C supports only hart0.
    # park secondary harts before touching the shared boot stack.
    bnez a0, park_hart

.option push
.option norelax
    lla gp, __global_pointer$
.option pop
    lla t0, __stack_top
    mv sp, t0
    csrw sscratch, sp
    j kernel_main

park_hart:
    # disable supervisor interrupts for secondary harts.
    csrw sie, zero
    csrw sip, zero

park_loop:
    wfi
    j park_loop