ENTRY(user_entry)

USER_BASE = 0x01000000;

SECTIONS
{
    . = USER_BASE;

    .text : ALIGN(16) {
        KEEP(*(.user_entry))
        KEEP(*(.user_shell))
        *(.text .text.*)
        *(.rodata .rodata.*)
    }

    .data : ALIGN(16) {
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.sdata .sdata.*)
        *(.data .data.*)
    }

    .bss (NOLOAD) : ALIGN(16) {
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
    }
}
