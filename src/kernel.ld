ENTRY(boot)

KERNEL_BASE = 0x80200000;
KERNEL_STACK_SIZE = 64K;
FREE_RAM_SIZE = 128M;

SECTIONS
{
    . = KERNEL_BASE;
    __kernel_base = .;

    .text : ALIGN(16) {
        __text_start = .;
        KEEP(*(.text.boot))
        KEEP(*(.text.trap_entry))
        *(.text .text.*)
        __text_end = .;
    }

    .rodata : ALIGN(16) {
        __rodata_start = .;
        *(.srodata .srodata.*)
        *(.rodata .rodata.*)
        *(.rdata .rdata.*)
        __rodata_end = .;
    }

    .data : ALIGN(16) {
        __data_start = .;
        *(.sdata .sdata.*)
        *(.data .data.*)
        __data_end = .;
    }

    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    }

    . = ALIGN(16);
    __kernel_end = .;

    .kernel_stack (NOLOAD) : ALIGN(16) {
        __stack_bottom = .;
        . += KERNEL_STACK_SIZE;
        __stack_top = .;
    }

    . = ALIGN(4096);
    .free_ram (NOLOAD) : ALIGN(4096) {
        __free_ram_start = .;
        . += FREE_RAM_SIZE;
        __free_ram_end = .;
    }
}
