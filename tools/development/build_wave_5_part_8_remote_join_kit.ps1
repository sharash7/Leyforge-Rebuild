[CmdletBinding()]
param([string]$OutputPath='', [string]$GodotRoot='', [string]$VerificationSnapshotPath='')
$ErrorActionPreference='Stop'
$repositoryRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if(-not $OutputPath){$OutputPath=Join-Path $repositoryRoot ('builds/w58-remote-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))}
$OutputPath=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $OutputPath){throw 'Kit output must be a new directory; existing data is never overwritten'}
$sourceRoot=$repositoryRoot
$sourceCommit='UNCOMMITTED-VERIFICATION-CANDIDATE'
$certified=$true
if($VerificationSnapshotPath){
 $sourceRoot=(Resolve-Path -LiteralPath $VerificationSnapshotPath).Path
 if(-not $sourceRoot.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'Verification snapshot must be an isolated temporary candidate'}
 $inventory=Get-Content (Join-Path $sourceRoot '.verification_snapshot_inventory.json') -Raw | ConvertFrom-Json
 $sourceCommit='UNCOMMITTED-VERIFICATION-CANDIDATE';$certified=$false
}else{
 $sourceCommit=(& git -C $repositoryRoot rev-parse HEAD)
 $inventory=@(& git -C $repositoryRoot ls-tree -r --name-only HEAD)
 $version=(& git -C $repositoryRoot show HEAD:project.godot) -join "`n"
 if($version -notmatch 'config/version="0.6.0-wave5-w5.8"'){throw 'Committed W5.8 source required'}
 $gateRun=Get-ChildItem (Join-Path $repositoryRoot '.verification/wave5/w5_8') -Directory | Sort-Object Name | Select-Object -Last 1
 $gate=Get-Content (Join-Path $gateRun.FullName 'gate.json') -Raw | ConvertFrom-Json
 if(-not $gate.passed -or -not $gate.certified){throw 'Complete W5.8 automated certification required before friend packaging'}
 $pins=Get-Content (Join-Path $gateRun.FullName 'source_manifest.json') -Raw | ConvertFrom-Json
 foreach($pin in $pins.PSObject.Properties){
  $info=New-Object Diagnostics.ProcessStartInfo
  $info.FileName='git.exe';$info.WorkingDirectory=$repositoryRoot;$info.Arguments='show HEAD:'+$pin.Name
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true
  $proc=[Diagnostics.Process]::Start($info);$sha=[Security.Cryptography.SHA256]::Create()
  try{$digest=[BitConverter]::ToString($sha.ComputeHash($proc.StandardOutput.BaseStream)).Replace('-','')}finally{$sha.Dispose()}
  $proc.WaitForExit()
  if($proc.ExitCode -ne 0 -or $digest -ne $pin.Value){throw "Committed source differs from certified candidate: $($pin.Name)"}
 }

}
$launchers=@('tools/development/w5_2_launcher.ps1','tools/development/run_wave_5_part_8_remote_join.ps1')
# The canonical application preloads these two scripts even outside playtest mode.
$runtimeDrivers=@('tests/wave_1/wave_1_playtest_driver.gd','tests/wave_2/wave_2_playtest_driver.gd','tests/support/world_save_view.gd')
$files=@($inventory | Where-Object { $_ -eq 'project.godot' -or $_ -match '^(src|content|scenes|addons)/' -or $_ -in $launchers -or $_ -in $runtimeDrivers })
$files=@($files | Where-Object { $_ -notmatch '^addons/.*/bin/' -or $_ -match 'libvoxel\.windows\.editor\.x86_64\.dll$' })
New-Item -ItemType Directory -Path $OutputPath | Out-Null
foreach($relative in $files){
 $target=Join-Path $OutputPath $relative
 New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($target)) | Out-Null
 if($VerificationSnapshotPath){Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $target}
 else{
  $info=New-Object Diagnostics.ProcessStartInfo
  $info.FileName='git.exe';$info.WorkingDirectory=$repositoryRoot;$info.Arguments='show HEAD:'+ $relative
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true
  $proc=[Diagnostics.Process]::Start($info);$stream=[IO.File]::Create($target)
  try{$proc.StandardOutput.BaseStream.CopyTo($stream)}finally{$stream.Dispose()}
  $proc.WaitForExit();if($proc.ExitCode -ne 0){throw "Cannot package committed $relative"}
 }
}
if(-not $GodotRoot){$GodotRoot='D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed'}
$runtime=Join-Path $OutputPath runtime
New-Item -ItemType Directory -Path $runtime | Out-Null
$expected=@{'godot.windows.editor.x86_64.console.exe'='06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A';'godot.windows.editor.x86_64.exe'='87D0A6077ABE38B905F973B23D9F27FD4F3B7A8DB2309DFD6807FAD7DFF582C8'}
foreach($name in $expected.Keys){$path=Join-Path $GodotRoot $name;if((Get-FileHash $path).Hash -ne $expected[$name]){throw 'Only the approved fixed runtime can be bundled'};Copy-Item -LiteralPath $path -Destination (Join-Path $runtime $name)}
& (Join-Path $runtime 'godot.windows.editor.x86_64.console.exe') --headless --path $OutputPath --script (Join-Path $repositoryRoot 'tools/development/w5_8_runtime_notices.gd') -- ("--output="+(Join-Path $runtime 'LICENSE_AND_NOTICES.txt'))
if($LASTEXITCODE -ne 0){throw 'Runtime notice extraction failed'}
$joinScript='param([string]$Address="", [int]$Port=25652)' + "`n" + '& (Join-Path $PSScriptRoot "tools/development/run_wave_5_part_8_remote_join.ps1") -Address $Address -Port $Port -GodotRoot (Join-Path $PSScriptRoot runtime)'
[IO.File]::WriteAllText((Join-Path $OutputPath run_wave_5_part_8_remote_join.ps1),$joinScript)
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'tools/development/README_W5_8_REMOTE_TEST.txt') -Destination $OutputPath
$hashes=@{}
foreach($file in Get-ChildItem -LiteralPath $OutputPath -Recurse -File){$relative=$file.FullName.Substring($OutputPath.Length+1).Replace('\','/');$hashes[$relative]=(Get-FileHash $file.FullName).Hash}
@{application='0.6.0-wave5-w5.8';protocol=7;source_commit=$sourceCommit;certified_source=$certified;files=$hashes} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputPath kit_manifest.json) -Encoding UTF8
Write-Output "W5_8_REMOTE_KIT=$OutputPath"
