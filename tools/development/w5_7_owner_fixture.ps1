# Instrument a fresh isolated candidate only. Production scripts/content stay identical.
$originalProofProject=$testProject
$ownerProject=Join-Path $tempRoot 'owner-project'
New-Item -ItemType Directory -Force $ownerProject | Out-Null
foreach($relative in $manifest.Keys){
 $target=Join-Path $ownerProject $relative
 New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($target)) | Out-Null
 Copy-Item -LiteralPath (Join-Path $testProject $relative) -Destination $target
}
$base=[IO.File]::ReadAllText((Join-Path $ownerProject 'tests/networking/w5_3_process.gd'))
$base=$base.Replace('extends SceneTree',@'
extends Node
var root: Window:
    get: return get_tree().root
var physics_frame: Signal:
    get: return get_tree().physics_frame
var process_frame: Signal:
    get: return get_tree().process_frame
var paused: bool:
    get: return get_tree().paused
func create_timer(seconds: float) -> SceneTreeTimer: return get_tree().create_timer(seconds)
func quit(code: int = 0) -> void: get_tree().quit(code)
'@)
$base=$base.Replace('func _initialize() -> void: call_deferred("_run")',@'
func _ready() -> void:
    if OS.get_environment("LEYFORGE_REPAIR_PROOF_DIR").is_empty():
        queue_free();return
    call_deferred("_run")
'@)
$base=$base.Replace('func _run() -> void:',@'
func _run() -> void:
    directory=OS.get_environment("LEYFORGE_REPAIR_PROOF_DIR")
    label=OS.get_environment("LEYFORGE_REPAIR_PROOF_NAME")
    await process_frame
'@)
$base=$base.Replace('game = load("res://scenes/main/wave_1_playground.tscn").instantiate()','game = get_tree().current_scene')
$base=$base.Replace('root.add_child(game)','if game == null: quit(1);return')
$base=$base.Replace('(600000 if OS.get_cmdline_user_args().has("--w55-proof") or OS.get_cmdline_user_args().has("--w56-proof") else 180000)','600000')
[IO.File]::WriteAllText((Join-Path $ownerProject 'tests/networking/w5_6_repair_owner_base.gd'),$base.Replace((' '*4),[string][char]9),(New-Object Text.UTF8Encoding($false)))
$parent='w5_6_repair_owner_base.gd'
foreach($name in @('w5_4_process.gd','w5_5_process.gd','w5_6_process.gd','w5_6_repair_process.gd','w5_7_process.gd')){
 $text=[IO.File]::ReadAllText((Join-Path $ownerProject "tests/networking/$name"))
 $text=[regex]::Replace($text,'\Aextends "[^"]+"',('extends "res://tests/networking/'+$parent+'"'))
 if($name -eq 'w5_7_process.gd'){
  $text=$text.Replace('game = load("res://scenes/main/wave_1_playground.tscn").instantiate()','game = get_tree().current_scene')
  $text=$text.Replace('root.add_child(game)','if game == null: quit(1);return')
 }
 $generated=$name.Replace('.gd','_owner.gd')
 [IO.File]::WriteAllText((Join-Path $ownerProject "tests/networking/$generated"),$text,(New-Object Text.UTF8Encoding($false)))
 $parent=$generated
}
$project=Join-Path $ownerProject project.godot
$nl=[Environment]::NewLine
[IO.File]::AppendAllText($project,($nl+'[autoload]'+$nl+$nl+'RepairInputProof="*res://tests/networking/w5_7_process_owner.gd"'+$nl),(New-Object Text.UTF8Encoding($false)))
$instrumentation=@{project_sha256=(Get-FileHash $project).Hash;clean_cache=(-not (Test-Path (Join-Path $ownerProject '.godot')));production_files_match=$true;generated_tests=@{}}
foreach($relative in $manifest.Keys){
 if($relative -eq 'project.godot'){continue}
 Check ((Get-FileHash (Join-Path $ownerProject $relative)).Hash -eq $manifest[$relative]) "Owner production bytes changed: $relative"
}
foreach($path in Get-ChildItem (Join-Path $ownerProject tests/networking) -Filter '*owner*.gd'){
 $instrumentation.generated_tests[$path.Name]=(Get-FileHash $path.FullName).Hash
}
$instrumentation | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $evidenceRoot 'owner-instrumentation.json')
$gate.exact_owner_launchers=$true;$gate.owner_fixture_instrumentation='isolated test autoload; unmodified production scripts/content; physical Input and GUI events';$gate.owner_clean_cache=$instrumentation.clean_cache
$testProject=$ownerProject
