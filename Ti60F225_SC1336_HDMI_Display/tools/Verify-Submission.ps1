$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$manifest=Get-Content -LiteralPath (Join-Path $root 'release/files.sha256.json') -Raw | ConvertFrom-Json
foreach($item in $manifest.files){
    $path=[IO.Path]::GetFullPath((Join-Path $root $item.path))
    if(!$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Manifest path escapes project'}
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing submission file: $($item.path)"}
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() -ne $item.sha256){throw "Changed submission file: $($item.path)"}
}
Write-Output "PASS: $($manifest.files.Count) submission files match SHA256 manifest."
