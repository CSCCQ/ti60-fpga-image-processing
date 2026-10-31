param([string]$EfinityRoot='E:/Efinity/2026.1',
      [string]$IdeRoot='E:/Efinity/efinity-riscv-ide-2026.1',
      [int]$JtagClockHz=100000,[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Verify-Submission.ps1')
. (Join-Path $PSScriptRoot 'Environment.ps1') -EfinityRoot $EfinityRoot
$bit=Join-Path $root 'release/fpga/Ti60_Demo.bit'
if($CheckOnly){Write-Output 'PASS: accepted V3 SRAM image. No board access.';return}
$logs=Join-Path $root 'build/deploy'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$log=Join-Path $logs 'load_sram.log'
& (Join-Path $EfinityRoot 'python311/bin/python.exe') -u (Join-Path $EfinityRoot 'pgm/bin/efx_pgm/ftdi_program.py') $bit -m jtag -b 'Generic Board Profile Using FT232H' --jtag_clock_freq $JtagClockHz *> $log
$rc=$LASTEXITCODE;Get-Content -LiteralPath $log -Tail 12
if($rc -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch '0x10660A79' -Quiet)){throw 'SRAM programming failed'}
Start-Sleep -Seconds 5
& (Join-Path $PSScriptRoot 'Check-Startup.ps1') -IdeRoot $IdeRoot
Write-Output 'SUCCESS: SRAM V3 loaded; firmware startup confirmed. Flash was not changed.'
