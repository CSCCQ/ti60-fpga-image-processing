param([string]$IdeRoot='E:/Efinity/efinity-riscv-ide-2026.1',
      [string]$Log='build/deploy/autonomous_runtime.log',
      [string]$ReleaseAudit='release/release.json',
      [string]$TargetConfig='embedded_sw/SapphireSoc32/bsp/efinix/EfxSapphireSoc/openocd/debug_ti.cfg')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$app=Join-Path $root 'embedded_sw/SapphireSoc32/software/standalone/evsoc'
$ide=$IdeRoot
$manifest=Get-Content -LiteralPath (Join-Path $root 'release/boot/manifest.json') -Raw | ConvertFrom-Json
$release=Get-Content -LiteralPath (Join-Path $root $ReleaseAudit) -Raw | ConvertFrom-Json
$bit=Join-Path $root (Join-Path $release.hardware_output 'Ti60_Demo.bit')
if(!$release.software_and_hardware_checks_passed -or (Get-FileHash -LiteralPath $bit).Hash.ToLower() -ne $release.bit_sha256.ToLower()){throw 'Expected an audited FPGA release before autonomous-start verification.'}
$elf=Join-Path $root 'release/firmware/evsoc_tinyml_digits.elf'
if((Get-FileHash -LiteralPath $elf).Hash.ToLower() -ne $manifest.elf_sha256){throw 'Application differs from the Flash manifest.'}
$sym=& "$ide/toolchain/bin/riscv-none-elf-nm.exe" -g --defined-only $elf | Where-Object {$_ -match '^([0-9a-fA-F]+)\s+\w\s+gray_digit_status$'}
if($LASTEXITCODE -ne 0 -or @($sym).Count -ne 1){throw 'Runtime status symbol missing.'}
$address=[Convert]::ToUInt32(($sym -split '\s+')[0],16)
$target=Join-Path $root $TargetConfig
$logPath=Join-Path $root $Log
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null
Push-Location $app
try {
    & "$ide/openocd/bin/openocd.exe" -f (Join-Path $PSScriptRoot 'gray_ft232h.cfg') -f $target -f (Join-Path $PSScriptRoot 'gray_check_flash_boot.tcl') -c ('gray_check_flash_boot {0} {1} 0x{2:X8}' -f $manifest.application_bytes,$manifest.crc32,$address) -c shutdown *> $logPath
    $rc=$LASTEXITCODE
} finally {Pop-Location}
Get-Content -LiteralPath $logPath -Tail 16
if($rc -ne 0 -or !(Select-String -LiteralPath $logPath -SimpleMatch 'SUCCESS: firmware loaded itself from Flash' -Quiet)){throw 'Autonomous boot verification failed; inspect the log.'}
@{passed=$true;firmware_downloaded=$false;cpu_resumed=$true;
  elf_sha256=$manifest.elf_sha256;boot_sha256=$manifest.boot_sha256;
  bit_sha256=$release.bit_sha256.ToLower();firmware_image_sha256=$manifest.image_sha256;
  application_bytes=$manifest.application_bytes;crc32=$manifest.crc32;
  verified=(Get-Date).ToString('o');log=$logPath} | ConvertTo-Json |
  Set-Content -Encoding UTF8 -LiteralPath ([System.IO.Path]::ChangeExtension($logPath,'.result.json'))
