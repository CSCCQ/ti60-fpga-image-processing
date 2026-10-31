param([string]$EfinityRoot='E:/Efinity/2026.1',
      [ValidateSet('compile','map','pnr')][string]$Flow='compile',
      [switch]$CheckOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Environment.ps1') -EfinityRoot $EfinityRoot
$python=Join-Path $EfinityRoot 'python311/bin/python.exe'
& $python (Join-Path $PSScriptRoot 'verify_project.py')
if($LASTEXITCODE -ne 0){throw 'Project dependency check failed'}
if($CheckOnly){Write-Output 'PASS: FPGA paths verified; no compilation.';return}
$output=Join-Path $root 'build/fpga'
New-Item -ItemType Directory -Force -Path $output | Out-Null
Push-Location $root
try {
    & $python (Join-Path $EfinityRoot 'scripts/efx_run.py') Ti60_Demo.xml --flow $Flow --output_dir build/fpga --work_dir build/fpga *> (Join-Path $output 'build.log')
    $code=$LASTEXITCODE
    Get-Content -LiteralPath (Join-Path $output 'build.log') -Tail 25
    if($code -ne 0){throw 'FPGA build failed; see build/fpga/build.log'}
} finally {Pop-Location}
Write-Output 'Build output: build/fpga. The accepted release/fpga images were not overwritten. Recheck resources and timing before deploying a rebuilt image.'
