# The Efinix legacy vexriscv target has no checksum_memory implementation.
# Compare raw dump_image bytes on the host while the target stays halted.
# Any error stops the command sequence before the subsequent resume command.
proc gray_verify_readback {expected_file readback_file address size} {
    echo "Reading back $size bytes at $address ..."
    dump_image $readback_file $address $size
    set fd [open $expected_file rb]
    set expected [read $fd]
    close $fd
    set fd [open $readback_file rb]
    set actual [read $fd]
    close $fd
    if {[string length $expected] != $size || [string length $actual] != $size} {
        error "Readback length mismatch at $address; firmware remains halted."
    }
    if {![string equal $expected $actual]} {
        error "Readback data mismatch at $address; firmware remains halted."
    }
    echo "Readback verified: $size bytes at $address"
}
