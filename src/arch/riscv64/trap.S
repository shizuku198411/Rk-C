.section .text.trap_entry
.global trap_entry
.align 4
trap_entry:
    csrr t0, sstatus
    andi t0, t0, 0x100
    bnez t0, 1f
    csrrw sp, sscratch, sp
    j 2f
1:
    csrw sscratch, sp
2:
    csrc sstatus, 2

    addi sp, sp, -8 * 34
    sd ra,  8 * 0(sp)
    sd gp,  8 * 1(sp)
    sd tp,  8 * 2(sp)
    sd t0,  8 * 3(sp)
    sd t1,  8 * 4(sp)
    sd t2,  8 * 5(sp)
    sd t3,  8 * 6(sp)
    sd t4,  8 * 7(sp)
    sd t5,  8 * 8(sp)
    sd t6,  8 * 9(sp)
    sd a0,  8 * 10(sp)
    sd a1,  8 * 11(sp)
    sd a2,  8 * 12(sp)
    sd a3,  8 * 13(sp)
    sd a4,  8 * 14(sp)
    sd a5,  8 * 15(sp)
    sd a6,  8 * 16(sp)
    sd a7,  8 * 17(sp)
    sd s0,  8 * 18(sp)
    sd s1,  8 * 19(sp)
    sd s2,  8 * 20(sp)
    sd s3,  8 * 21(sp)
    sd s4,  8 * 22(sp)
    sd s5,  8 * 23(sp)
    sd s6,  8 * 24(sp)
    sd s7,  8 * 25(sp)
    sd s8,  8 * 26(sp)
    sd s9,  8 * 27(sp)
    sd s10, 8 * 28(sp)
    sd s11, 8 * 29(sp)

    csrr a0, sscratch
    sd a0, 8 * 30(sp)

    csrr a0, sepc
    sd a0, 8 * 31(sp)

    # save original sstatus before hardening handler state.
    # this preserves SUM/SPIE/SPP for the interrupted context.
    csrr a0, sstatus
    sd a0, 8 * 32(sp)

    # do not run kernel trap handler with SUM enabled.
    #   SUM = 1 << 18 (0x40000)
    li t0, 1 << 18
    csrc sstatus, t0

    addi a0, sp, 8 * 34
    csrw sscratch, a0

    # from here, run kernel code with kernel gp.
.option push
.option norelax
    lla gp, __global_pointer$
.option pop

    mv a0, sp
    call trap_handler

    ld a0, 8 * 31(sp)
    csrw sepc, a0

    ld a0, 8 * 32(sp)
    csrw sstatus, a0

    ld ra,  8 * 0(sp)
    ld gp,  8 * 1(sp)
    ld tp,  8 * 2(sp)
    ld t0,  8 * 3(sp)
    ld t1,  8 * 4(sp)
    ld t2,  8 * 5(sp)
    ld t3,  8 * 6(sp)
    ld t4,  8 * 7(sp)
    ld t5,  8 * 8(sp)
    ld t6,  8 * 9(sp)
    ld a0,  8 * 10(sp)
    ld a1,  8 * 11(sp)
    ld a2,  8 * 12(sp)
    ld a3,  8 * 13(sp)
    ld a4,  8 * 14(sp)
    ld a5,  8 * 15(sp)
    ld a6,  8 * 16(sp)
    ld a7,  8 * 17(sp)
    ld s0,  8 * 18(sp)
    ld s1,  8 * 19(sp)
    ld s2,  8 * 20(sp)
    ld s3,  8 * 21(sp)
    ld s4,  8 * 22(sp)
    ld s5,  8 * 23(sp)
    ld s6,  8 * 24(sp)
    ld s7,  8 * 25(sp)
    ld s8,  8 * 26(sp)
    ld s9,  8 * 27(sp)
    ld s10, 8 * 28(sp)
    ld s11, 8 * 29(sp)
    ld sp,  8 * 30(sp)
    sret
