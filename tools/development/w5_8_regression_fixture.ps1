# Test-only protocol-7 credentials for retained gameplay/lifecycle gates.
# No production HOST configuration override exists.
# Retained launchers in external snapshots inherit only this approved runtime root.
$env:LEYFORGE_GODOT_ROOT=Split-Path $godotPath -Parent
if(-not $env:LEYFORGE_TEST_INVITE){
 $bytes=New-Object byte[] 16
 $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
 try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
 $env:LEYFORGE_TEST_INVITE=[BitConverter]::ToString($bytes).Replace('-','').ToLowerInvariant()
 [Array]::Clear($bytes,0,$bytes.Length)
}
$env:LEYFORGE_INVITE=$env:LEYFORGE_TEST_INVITE
$fixtureProject=Join-Path $testProject project.godot
$fixtureText=[IO.File]::ReadAllText($fixtureProject)
if($fixtureText -notmatch 'W58FixtureInvite='){
 [IO.File]::AppendAllText($fixtureProject,("`n[autoload]`nW58FixtureInvite="+'"*res://tests/networking/w5_8_regression_bridge.gd"'+"`n"),(New-Object Text.UTF8Encoding($false)))
}
$gate.private_admission_fixture=@{test_only=$true;environment_memory_only=$true;project_sha256=(Get-FileHash -LiteralPath $fixtureProject).Hash;bridge_sha256=(Get-FileHash -LiteralPath (Join-Path $testProject 'tests/networking/w5_8_regression_bridge.gd')).Hash}
