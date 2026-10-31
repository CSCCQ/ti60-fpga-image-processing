.section .init,"ax"
.global _start
_start:
    j boot_start
    .word 0x42595247 /* GRYB: also recognized by the optional JTAG loader */
    .word 1
    .word 0
boot_start:
    csrw mie, zero
    csrci mstatus, 8
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, _stack_top
    la t0, __bss_start
    la t1, __bss_end
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:  call boot_main
3:  j 3b
