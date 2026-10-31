OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { OCR (rwx) : ORIGIN = 0xf9000000, LENGTH = 0xd00 }
SECTIONS {
 .text : { KEEP(*(.init)) *(.text*) *(.rodata*) } > OCR
 .data : { *(.sdata*) *(.data*) } > OCR
 .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.sbss*) *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > OCR
 __global_pointer$ = 0xf9000800;
 _stack_top = 0xf9000fe0;
 ASSERT(__bss_end <= 0xf9000d00, "Boot code leaves less than 736 bytes of stack")
 /DISCARD/ : { *(.comment*) *(.eh_frame*) }
}
