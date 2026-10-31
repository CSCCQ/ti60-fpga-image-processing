param([string]$IdeRoot='E:/Efinity/efinity-riscv-ide-2026.1',
      [string]$Python='python',[switch]$InstallRom)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$env:GRAY_RISCV_IDE=$IdeRoot
$arguments=@('-E',(Join-Path $PSScriptRoot 'flash_boot/build.py'))
if($InstallRom){$arguments+='--install-rom'}
& $Python @arguments
if($LASTEXITCODE -ne 0){throw 'Boot image generation failed. Build-Firmware.ps1 must succeed first.'}
Write-Output 'Generated build/boot. Existing release images were not overwritten. If ROM was installed, recompile and validate the FPGA before deploying.'
