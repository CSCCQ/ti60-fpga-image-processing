param([ValidateSet('All','Firmware','Configuration')][string]$Part='All',
      [string]$EfinityRoot='E:/Efinity/2026.1',
      [int]$JtagClockHz=1000000,[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Verify-Submission.ps1')
. (Join-Path $PSScriptRoot 'Environment.ps1') -EfinityRoot $EfinityRoot
$python=Join-Path $EfinityRoot 'python311/bin/python.exe'
$pgm=Join-Path $EfinityRoot 'pgm/bin/efx_pgm/ftdi_program.py'
$bridge=Join-Path $EfinityRoot 'pgm/fli/titanium/u10660A79.bit'
$parts=@()
if($Part -in @('All','Firmware')){$parts+=@{name='firmware';file='release/boot/digits_flash.hex';address=4194304}}
if($Part -in @('All','Configuration')){$parts+=@{name='configuration';file='release/fpga/Ti60_Demo.hex';address=0}}
foreach($item in $parts){
    $lines=[IO.File]::ReadAllLines((Join-Path $root $item.file))
    if($lines.Length -le 0 -or $lines.Length -gt 4194304){throw 'Image crosses a Flash partition'}
    foreach($line in $lines){if($line -notmatch '^[0-9a-fA-F]{2}$'){throw 'Expected Efinity byte-HEX, not Intel HEX'}}
}
if(!(Test-Path -LiteralPath $bridge)){throw 'Ti60 JTAG-to-SPI bridge is missing'}
if($CheckOnly){Write-Output "PASS: Flash $Part plan and image boundaries. No board access.";return}
if(Get-Process openocd -ErrorAction SilentlyContinue){throw 'Close the other OpenOCD session first'}
$logs=Join-Path $root ('build/deploy/'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$log=Join-Path $logs 'bridge.log'
& $python -u $pgm $bridge -m jtag -b 'Generic Board Profile Using FT232H' --jtag_clock_freq $JtagClockHz *> $log
if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch '0x10660A79' -Quiet)){Get-Content $log -Tail 20;throw 'Expected Ti60 not detected; Flash untouched'}
# Save the connected board's existing Flash before erasing either partition.
$backup=Join-Path $logs 'original_flash.hex'
& $python -u $pgm -m jtag_bridge --jtag_bridge_mode read --address 0 --num_bytes 8388608 -o $backup -b 'Generic Board Profile Using FT232H' --jtag_clock_freq $JtagClockHz *> (Join-Path $logs 'backup.log')
if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $backup)){throw 'Flash backup failed; nothing erased'}
$count=0
foreach($line in [IO.File]::ReadLines($backup)){if($line -notmatch '^[0-9a-fA-F]{2}$'){throw 'Invalid Flash backup'};$count++}
if($count -ne 8388608){throw 'Incomplete Flash backup; nothing erased'}
@{bytes=$count;hex_sha256=(Get-FileHash -LiteralPath $backup).Hash;created=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logs 'backup.json') -Encoding UTF8
foreach($item in $parts){
    $log=Join-Path $logs ($item.name+'.log')
    & $python -u $pgm (Join-Path $root $item.file) -m jtag_bridge --jtag_bridge_mode all --address $item.address --verify_method hostx1 -b 'Generic Board Profile Using FT232H' --jtag_clock_freq $JtagClockHz *> $log
    $rc=$LASTEXITCODE;Get-Content -LiteralPath $log -Tail 22
    if($rc -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch 'Flash verify successful' -Quiet)){throw 'Flash readback failed; retain backup and inspect logs before power cycling'}
}
@{part=$Part;host_readback_verified=$true;cold_power_cycle_verified=$false;finished=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logs 'program.result.json') -Encoding UTF8
Write-Output 'SUCCESS: Flash write and host readback passed. Power off for five seconds, power on without a PC download, then check the image and digit recognition.'
