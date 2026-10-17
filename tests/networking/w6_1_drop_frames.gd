extends SceneTree

# Rendered presentation probe: the real presenter receives a fixed small target
# after an actual main-thread stall. No synthetic delta or alternate interpolator.
var output: String
var presenter: LeyforgeResourcePresenter
var world: LeyforgeWave1Playground
var body: Node3D
var driver: FrameDriver
var rows: Array = []
var converged: Array = []
var trial: int = -1
var phase: int = 0
var frames: int = 0
var previous_usec: int = 0
var before: Vector3
var stalls: Array = [0,0,0,131,131,131,200,200,200,400,400,400]

class FrameDriver extends Node:
	var probe: Variant
	func _process(delta: float) -> void: probe.advance(delta)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not output.is_absolute_path(): quit(1);return
	root.size=Vector2i(640,360)
	Engine.max_fps=60
	world=LeyforgeWave1Playground.new()
	presenter=LeyforgeResourcePresenter.new()
	presenter._world=world
	presenter.set_physics_process(false)
	body=Node3D.new()
	var mesh: MeshInstance3D=MeshInstance3D.new()
	mesh.name="Visual";mesh.mesh=BoxMesh.new();body.add_child(mesh)
	presenter.add_child(body)
	presenter._nodes["abcdef"]=body
	presenter._drop_targets["abcdef"]=Vector3.ZERO
	root.add_child(presenter)
	presenter.set_physics_process(false)
	var camera: Camera3D=Camera3D.new();camera.position=Vector3(0,0,3);root.add_child(camera)
	driver=FrameDriver.new();driver.probe=self;driver.process_priority=-1000;root.add_child(driver)
	RenderingServer.frame_post_draw.connect(record)

func advance(delta: float) -> void:
	if trial<0 or (phase==3 and body.position.distance_to(presenter._drop_targets["abcdef"])<0.000001):
		if trial>=0: converged.append({"trial":trial,"error_m":body.position.distance_to(presenter._drop_targets["abcdef"])})
		trial+=1;phase=0;frames=0
		if trial>=stalls.size():
			driver.set_process(false);presenter.set_process(false)
			call_deferred("finish");return
		body.position=Vector3.ZERO;presenter._drop_targets["abcdef"]=Vector3.ZERO
	frames+=1
	if phase==0 and frames>=8:
		# This blocks a real rendered interval; the NEXT engine delta includes it.
		if stalls[trial]>0: OS.delay_msec(stalls[trial])
		phase=1
	elif phase==1:
		presenter._drop_targets["abcdef"]=Vector3(0.063,0,0);phase=2
	elif phase==2: phase=3
	before=body.position
	rows.append({"trial":trial,"requested_stall_ms":stalls[trial],"phase":phase,
		"engine_frame":Engine.get_process_frames(),"delta_sec":delta,
		"before":LfeMovementProtocol.array3(before),"target":LfeMovementProtocol.array3(presenter._drop_targets["abcdef"])})

func record() -> void:
	if rows.is_empty() or trial>=stalls.size(): return
	var now: int=Time.get_ticks_usec()
	var row: Dictionary=rows[-1]
	row["post_draw_usec"]=now
	row["actual_render_gap_ms"]=(now-previous_usec)/1000.0 if previous_usec else 0.0
	row["visual"]=LfeMovementProtocol.array3(body.position)
	row["step_m"]=body.position.distance_to(before)
	row["lag_m"]=body.position.distance_to(presenter._drop_targets["abcdef"])
	previous_usec=now

func finish() -> void:
	var checks: Array = []
	for index: int in stalls.size():
		var maximum_step: float=0.0
		var maximum_gap: float=0.0
		var maximum_lag: float=0.0
		for row: Dictionary in rows:
			if row["trial"]!=index: continue
			maximum_step=maxf(maximum_step,row.get("step_m",0))
			maximum_gap=maxf(maximum_gap,row.get("actual_render_gap_ms",0))
			maximum_lag=maxf(maximum_lag,row.get("lag_m",0))
		checks.append({"trial":index,"maximum_step_m":maximum_step,"maximum_render_gap_ms":maximum_gap,
			"maximum_lag_m":maximum_lag,"passed":maximum_step<0.04 and maximum_step>0.000001 and maximum_lag<0.08
			and converged[index]["error_m"]<0.001 and maximum_gap>=stalls[index]})
	var passed: bool=checks.all(func(check: Dictionary) -> bool: return check["passed"])
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"converged":converged,"rows":rows,"trials":stalls.size(),"presenter_sha256":FileAccess.get_sha256("res://src/game/items/resource_presenter.gd")},"\t"));file=null
	world.free();quit(0 if passed else 1)
