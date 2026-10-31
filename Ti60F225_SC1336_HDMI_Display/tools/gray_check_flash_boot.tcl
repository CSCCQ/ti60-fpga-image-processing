# Observe autonomous boot. No reset, boot-entry patch, or application download.
proc gray_check_flash_boot {length crc status_address} {
    for {set attempt 0} {$attempt < 12} {incr attempt} {
        resume
        sleep 5000
        halt
        wait_halt 2000
        mem2array boot 32 0xf9000fe0 8
        echo "FLASH_BOOT magic=$boot(0) stage=$boot(1) error=$boot(2) jedec=$boot(3) bytes=$boot(4) expected_crc=$boot(5) actual_crc=$boot(6)"
        if {$boot(0) != 0x42595247 || $boot(2) != 0} {
            resume
            error "Autonomous loader did not report a valid boot; no firmware downloaded."
        }
        if {$boot(1) == 6} {
            if {$boot(4) != $length || $boot(5) != $crc || $boot(6) != $crc} {
                resume
                error "Autonomous boot payload differs from the selected release."
            }
            mem2array app 32 $status_address 17
            if {$app(0) == 0x47445331 && $app(1) == 1 && $app(2) > 0 && $app(2) < 8 && $app(3) == 0} {
                echo "AUTONOMOUS_MAIN stage=$app(2) error=$app(3) inferences=$app(4) boxes=$app(6) flags=$app(9) selftests=$app(15) max_difference=$app(16)"
                resume
                echo "SUCCESS: firmware loaded itself from Flash; main is running; CPU resumed."
                return
            }
        }
    }
    resume
    error "Autonomous startup did not complete within 60 seconds."
}
