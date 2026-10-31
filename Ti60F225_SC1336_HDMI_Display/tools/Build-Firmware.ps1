param([string]$IdeRoot='E:/Efinity/efinity-riscv-ide-2026.1',[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$app=Join-Path $root 'embedded_sw/SapphireSoc32/software/standalone/evsoc'
$make=Join-Path $IdeRoot 'build_tools/bin/make.exe'
if(!(Test-Path -LiteralPath $make)){throw "RISC-V IDE not found: $IdeRoot"}
$env:PATH="$IdeRoot/toolchain/bin;$IdeRoot/build_tools/bin;"+$env:PATH
$logs=Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$log=Join-Path $logs 'firmware_build.log'
Push-Location $app
try {
    if($CheckOnly){& $make -n all -B BSP=efinix/EfxSapphireSoc *> $log}
    else {& $make all -B -j4 BSP=efinix/EfxSapphireSoc *> $log}
    if($LASTEXITCODE -ne 0){Get-Content -LiteralPath $log -Tail 30;throw 'Firmware build failed'}
    Get-Content -LiteralPath $log -Tail 10
} finally {Pop-Location}
if($CheckOnly){Write-Output 'PASS: make dependency dry run.'}
else {Write-Output 'Firmware rebuilt in evsoc/build; accepted release/firmware was not overwritten.'}
