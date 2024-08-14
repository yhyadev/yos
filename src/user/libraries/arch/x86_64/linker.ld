TARGET(elf64-x86-64)
ENTRY(_start)

PHDRS {
    none PT_NULL FLAGS(0);
    text PT_LOAD FLAGS(4 | 1); /* r-x */
    rodata PT_LOAD FLAGS(4); /* r-- */
    data PT_LOAD FLAGS(4 | 2); /* rw- */
    bss PT_LOAD FLAGS(4 | 2); /* rw- */
}

SECTIONS {
    . = 0x200000;

    . = ALIGN(0x1000);

    .text . : {
        *(.text)
        *(.text.*)
    }:text

    . = ALIGN(0x1000);

    .rodata . : {
        *(.rodata)
        *(.rodata.*)
    }:rodata

    . = ALIGN(0x1000);

    .data . : {
        *(.data)
        *(.data.*)
    }:data

    . = ALIGN(0x1000);

    .bss . : {
        *(.bss)
        *(.bss.*)
    }:bss

    . = ALIGN(0x1000);

    /DISCARD/ : {
        *(.comment)
        *(.comment.*)
    }

    . = ALIGN(0x1000);
}
