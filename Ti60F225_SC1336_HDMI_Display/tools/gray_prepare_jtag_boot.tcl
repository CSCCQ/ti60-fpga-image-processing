# Optional JTAG loading must park either the legacy or autonomous bootloader
# before CPU reset, so it cannot overwrite a manually downloaded application.
# This changes volatile on-chip RAM only, never the FPGA configuration flash.
proc gray_prepare_jtag_boot {} {
    halt
    wait_halt 2000
    mem2array bridge 32 0xf8110000 1
    if {$bridge(0) != 0x47525931} {
        error "Not a gray video bridge; refusing to alter the boot entry."
    }
    mem2array boot 32 0xf9000000 3
    if {$boot(0) != 0x0000006f} {
        set legacy [expr {$boot(0) == 0x00001197 && $boot(1) == 0xb1818193 && $boot(2) == 0x91c18113}]
        set flashboot [expr {$boot(0) == 0x0100006f && $boot(1) == 0x42595247 && $boot(2) == 1}]
        if {!$legacy && !$flashboot} {
            error "Unknown boot image; refusing to replace its entry."
        }
        mww 0xf9000000 0x0000006f
    }
    mem2array boot_check 32 0xf9000000 1
    if {$boot_check(0) != 0x0000006f} {
        error "JTAG boot guard readback failed."
    }
    reset halt
    wait_halt 2000
    echo "JTAG boot guard verified: CPU reset cannot overwrite the manually loaded firmware."
}
