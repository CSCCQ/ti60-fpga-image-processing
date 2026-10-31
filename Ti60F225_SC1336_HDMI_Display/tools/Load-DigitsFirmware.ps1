param(
    [string]$IdeRoot='E:/Efinity/efinity-riscv-ide-2026.1',
    [string]$InterfaceConfig='',
    [string]$ElfPath='',
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$app=Join-Path $projectRoot 'embedded_sw/SapphireSoc32/software/standalone/evsoc'
$elf=Join-Path $projectRoot 'release/firmware/evsoc_tinyml_digits.elf'
if($ElfPath){$elf=(Resolve-Path -LiteralPath $ElfPath).Path}
$bsp=Join-Path $projectRoot 'embedded_sw/SapphireSoc32/bsp/efinix/EfxSapphireSoc/openocd'
$openocd=Join-Path $IdeRoot 'openocd/bin/openocd.exe'
$nm=Join-Path $IdeRoot 'toolchain/bin/riscv-none-elf-nm.exe'
if(!$InterfaceConfig){$InterfaceConfig=Join-Path $PSScriptRoot 'gray_ft232h.cfg'}
$targetConfig=Join-Path $bsp 'debug_ti.cfg'
$verifyConfig=Join-Path $PSScriptRoot 'gray_verify_readback.tcl'
$runtimeConfig=Join-Path $PSScriptRoot 'gray_check_digits_runtime.tcl'
$bootConfig=Join-Path $PSScriptRoot 'gray_prepare_jtag_boot.tcl'
foreach($path in @($openocd,$nm,$elf,$InterfaceConfig,$targetConfig,$verifyConfig,$runtimeConfig,$bootConfig)){
    if(!(Test-Path -LiteralPath $path)){throw "Missing file: $path"}
}
# Read the ELF32 program headers: only PT_LOAD file bytes are downloaded.
# Debug sections and the zero-initialized BSS must not be compared as file data.
$elfBytes=[System.IO.File]::ReadAllBytes($elf)
if($elfBytes.Length -lt 52 -or [BitConverter]::ToUInt32($elfBytes,0) -ne 0x464c457f -or
   $elfBytes[4] -ne 1 -or $elfBytes[5] -ne 1 -or
   [BitConverter]::ToUInt16($elfBytes,18) -ne 243){
    throw 'Expected a little-endian RISC-V ELF32 application.'
}
$entry=[BitConverter]::ToUInt32($elfBytes,24)
$phOffset=[BitConverter]::ToUInt32($elfBytes,28)
$phSize=[BitConverter]::ToUInt16($elfBytes,42)
$phCount=[BitConverter]::ToUInt16($elfBytes,44)
if($phSize -lt 32 -or ([uint64]$phOffset + [uint64]$phSize*$phCount) -gt $elfBytes.Length){
    throw 'Invalid ELF program-header table.'
}
$segments=@()
for($i=0;$i -lt $phCount;$i++){
    $header=[int]($phOffset+$i*$phSize)
    if([BitConverter]::ToUInt32($elfBytes,$header) -ne 1){continue}
    $offset=[BitConverter]::ToUInt32($elfBytes,$header+4)
    $address=[BitConverter]::ToUInt32($elfBytes,$header+12)
    $size=[BitConverter]::ToUInt32($elfBytes,$header+16)
    $memorySize=[BitConverter]::ToUInt32($elfBytes,$header+20)
    if($size -gt $memorySize -or ([uint64]$offset+$size) -gt $elfBytes.Length -or
       ([uint64]$address+$memorySize) -gt 4294967296){throw 'Invalid ELF load segment.'}
    if($size -gt 0){$segments+= [pscustomobject]@{Offset=$offset;Address=$address;Size=$size}}
}
if($segments.Count -eq 0){throw 'ELF contains no loadable file data.'}
$statusSymbol = & $nm -g --defined-only $elf | Where-Object {$_ -match '^([0-9a-fA-F]+)\s+\w\s+gray_digit_status$'}
if($LASTEXITCODE -ne 0 -or @($statusSymbol).Count -ne 1){
    throw 'ELF lacks gray_digit_status. Rebuild the current application before loading.'
}
$statusAddress=[Convert]::ToUInt32(($statusSymbol -split '\s+')[0],16)
$elfTcl=$elf.Replace('\','/')
Write-Host "ELF: $elf"
Write-Host 'First load the matching release/fpga/Ti60_Demo.bit and release the Programmer USB connection.'
Write-Host 'This loads the application, compares every downloaded byte by readback, then starts it.'
Write-Host 'Manual recovery only: normal operation starts the firmware from Flash. Readback may take a few minutes.'
foreach($segment in $segments){Write-Host ('Verify {0} bytes at 0x{1:X8}' -f $segment.Size,$segment.Address)}
if($CheckOnly){
    Write-Host ('CheckOnly: paths and ELF segments valid; entry 0x{0:X8}. No board access.' -f $entry)
    exit 0
}
$tempDir=Join-Path ([System.IO.Path]::GetTempPath()) ('gray-fw-'+[guid]::NewGuid().ToString('N'))
$temporaryFiles=@()
$locationPushed=$false
try{
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    # Optional manual debugging: park the recognized loader in volatile RAM
    # before reset, so it cannot replace this download with the Flash version.
    # A power cycle restores the persisted autonomous bootloader.
    $argsToOpenOcd=@('-f',$InterfaceConfig,'-f',$targetConfig,'-f',$verifyConfig,'-f',$runtimeConfig,'-f',$bootConfig,
        '-c','gray_prepare_jtag_boot','-c',"load_image {$elfTcl}")
    for($i=0;$i -lt $segments.Count;$i++){
        $segment=$segments[$i]
        $expectedFile=Join-Path $tempDir ("segment-$i.expected.bin")
        $readbackFile=Join-Path $tempDir ("segment-$i.readback.bin")
        $temporaryFiles+=@($expectedFile,$readbackFile)
        $expectedBytes=New-Object byte[] $segment.Size
        [Array]::Copy($elfBytes,[int]$segment.Offset,$expectedBytes,0,[int]$segment.Size)
        [System.IO.File]::WriteAllBytes($expectedFile,$expectedBytes)
        $verifyCommand='gray_verify_readback {{{0}}} {{{1}}} 0x{2:X8} {3}' -f
            $expectedFile.Replace('\','/'),$readbackFile.Replace('\','/'),$segment.Address,$segment.Size
        $argsToOpenOcd+=@('-c',$verifyCommand)
    }
    $argsToOpenOcd+=@('-c','reset halt','-c','wait_halt 2000','-c','reg x10 0','-c','reg x11 0','-c',('resume 0x{0:X8}' -f $entry),
        '-c',('gray_check_runtime 0x{0:X8}' -f $statusAddress),'-c','shutdown')
    Push-Location $app
    $locationPushed=$true
    & $openocd @argsToOpenOcd
    if($LASTEXITCODE -ne 0){throw "OpenOCD failed (exit $LASTEXITCODE). Firmware start was not confirmed; see the preceding message."}
    Write-Host 'SUCCESS: all downloaded bytes verified and application main confirmed running.'
    Write-Host 'In FULL BINARY view, hold K2 to toggle digit detection; show printed digits from test.docx.'
}finally{
    if($locationPushed){Pop-Location}
    foreach($temporaryFile in $temporaryFiles){
        if(Test-Path -LiteralPath $temporaryFile){Remove-Item -LiteralPath $temporaryFile -Force}
    }
    if(Test-Path -LiteralPath $tempDir){Remove-Item -LiteralPath $tempDir}
}
