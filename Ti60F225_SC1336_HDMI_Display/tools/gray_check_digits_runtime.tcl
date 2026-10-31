# Caller has verified and resumed the current ELF. Confirm main actually ran.
proc gray_check_runtime {address {startup_wait_ms 10000}} {
    # Let startup finish without repeated halts during its large BSS clear.
    # The manual's run example also allows about ten seconds before output.
    sleep $startup_wait_ms
    for {set attempt 0} {$attempt < 6} {incr attempt} {
        halt
        wait_halt 2000
        mem2array status 32 $address 17
        if {$status(0) != 0x47445331 || $status(1) != 1} {
            error "Runtime status signature mismatch; CPU remains halted."
        }
        if {$status(2) >= 1 && $status(2) <= 8} {
            echo "GRAY_RUNTIME stage=$status(2) error=$status(3) inferences=$status(4) frame=$status(5) boxes=$status(6) sequence=$status(7) epoch=$status(8) flags=$status(9) published=$status(10) rejected=$status(11) candidates=$status(12) label=$status(13) score_milli=$status(14) selftests=$status(15) max_difference=$status(16)"
            if {$status(3) != 0} {
                error "Firmware reached main but reported error $status(3); CPU remains halted."
            }
            resume
            echo "Runtime confirmed: application entered main."
            return
        }
        resume
        sleep 2000
    }
    error "Download verified, but main did not start after startup wait and retries."
}
