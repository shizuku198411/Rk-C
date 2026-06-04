.section .text
.global arch_wfi
arch_wfi:
    wfi
    ret

.global arch_read_scause
arch_read_scause:
    csrr a0, scause
    ret

.global arch_read_stval
arch_read_stval:
    csrr a0, stval
    ret

.global arch_read_sepc
arch_read_sepc:
    csrr a0, sepc
    ret

.global arch_read_sie
arch_read_sie:
    csrr a0, sie
    ret

.global arch_write_sie
arch_write_sie:
    csrw sie, a0
    ret

.global arch_read_sstatus
arch_read_sstatus:
    csrr a0, sstatus
    ret

.global arch_write_sstatus
arch_write_sstatus:
    csrw sstatus, a0
    ret

.global arch_write_sepc
arch_write_sepc:
    csrw sepc, a0
    ret

.global arch_write_stvec
arch_write_stvec:
    csrw stvec, a0
    ret

.global arch_read_stvec
arch_read_stvec:
    csrr a0, stvec
    ret

.global arch_write_sscratch
arch_write_sscratch:
    csrw sscratch, a0
    ret

.global arch_read_sscratch
arch_read_sscratch:
    csrr a0, sscratch
    ret

.global arch_write_satp
arch_write_satp:
    csrw satp, a0
    ret

.global arch_read_satp
arch_read_satp:
    csrr a0, satp
    ret

.global arch_read_scounteren
arch_read_scounteren:
    csrr a0, scounteren
    ret

.global arch_rdtime
arch_rdtime:
    rdtime a0
    ret

.global arch_write_stimecmp
arch_write_stimecmp:
    csrw stimecmp, a0
    ret

.global arch_flush_tlb
arch_flush_tlb:
    sfence.vma zero, zero
    ret

.global arch_fence_rw_rw
arch_fence_rw_rw:
    fence rw, rw
    ret

.global arch_fence_iorw_iorw
arch_fence_iorw_iorw:
    fence iorw, iorw
    ret

.global arch_fence_i
arch_fence_i:
    fence.i
    ret

.global arch_enter_user
arch_enter_user:
    csrw sepc, a0
    csrw sscratch, a2
    mv sp, a1

    csrr t0, sstatus
    li t1, 0x100
    not t1, t1
    and t0, t0, t1
    li t1, 0x20
    or t0, t0, t1
    csrw sstatus, t0
    mv a0, a3
    mv a1, a4
    sret
