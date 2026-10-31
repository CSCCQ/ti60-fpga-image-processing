param([string]$EfinityRoot='E:/Efinity/2026.1')
$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath (Join-Path $EfinityRoot 'scripts/efx_run.py'))){throw "Efinity installation not found: $EfinityRoot"}
$env:EFINITY_HOME=$EfinityRoot
$env:EFXPGM_HOME="$EfinityRoot/pgm"
$env:EFXDBG_HOME="$EfinityRoot/debugger"
$env:EFXPT_HOME="$EfinityRoot/pt"
$env:EFXIPM_HOME="$EfinityRoot/ipm"
$env:EFXSVF_HOME="$EfinityRoot/debugger/svf_player"
$env:EFXSERDESDBG_HOME="$EfinityRoot/debugger/serdes_debug_tool"
$env:EFINITY_USER_DIR_INI=$env:LOCALAPPDATA+'/efinity/user_dir.ini'
$env:PYTHONHOME="$EfinityRoot/python311"
$env:PATH="$EfinityRoot/python311/bin;$EfinityRoot/bin;$EfinityRoot/pgm/bin;$EfinityRoot/debugger/bin;"+$env:PATH
