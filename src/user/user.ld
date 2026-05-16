ENTRY(user_entry)

USER_BASE = 0x01000000;

SECTIONS
{
    . = USER_BASE;

    .text : ALIGN(4096) {
        __user_text_start = .;
        KEEP(*(.user_entry))
        KEEP(*(.user_shell))
        *(.text .text.*)
        __user_text_end = .;
    }

    . = ALIGN(4096);
    .rodata : ALIGN(4096) {
        __user_rodata_start = .;
        *(.srodata .srodata.*)
        *(.rodata .rodata.*)
        __user_rodata_end = .;
    }

    . = ALIGN(4096);
    .data : ALIGN(4096) {
        __user_data_start = .;
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.sdata .sdata.*)
        *(.data .data.*)
        __user_data_end = .;
    }

    . = ALIGN(4096);
    .bss (NOLOAD) : ALIGN(4096) {
        __user_bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        __user_bss_end = .;
    }

    . = ALIGN(4096);
    __user_image_end = .;
}
