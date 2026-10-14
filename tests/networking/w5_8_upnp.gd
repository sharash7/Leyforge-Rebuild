extends SceneTree
class Gateway extends RefCounted:
	var discovery: int = 0
	var mapping: int = 0
	var adds: int = 0
	var deletes: int = 0
	var requested_lease: int = 0
	var proto: String = ""
	func discover(_timeout: int,_ttl: int,_filter: String) -> int: return discovery
	func get_gateway() -> Variant: return self
	func is_valid_gateway() -> bool: return true
	func add_port_mapping(_external: int,_internal: int,_description: String,protocol: String,lease: int) -> int:
		adds += 1; requested_lease = lease; proto = protocol; return mapping
	func query_external_address() -> String: return "100.64.2.1"
	func delete_port_mapping(_port: int,_protocol: String) -> int: deletes += 1; return 0
var checks: int = 0
var failures: Array = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	for case: String in ["disabled","success","discovery","mapping"]:
		var gateway: Gateway = Gateway.new()
		if case == "discovery": gateway.discovery = 1
		if case == "mapping": gateway.mapping = 1
		var connectivity: LfeHostConnectivity = LfeHostConnectivity.new(); root.add_child(connectivity)
		connectivity.configure(25652,case != "disabled",func(): return gateway)
		var deadline: int = Time.get_ticks_msec()+5000
		while connectivity._thread != null and Time.get_ticks_msec() < deadline: await process_frame
		check(connectivity._thread == null,"bounded worker "+case)
		if case == "success":
			check(connectivity._mapped and gateway.proto == "UDP" and gateway.requested_lease == 3600,"UDP leased mapping")
			check(not connectivity.warning.is_empty() and connectivity.external_address == "100.64.2.1","truthful possible CGNAT warning")
			connectivity._renew_at = Time.get_ticks_msec()
			await process_frame
			while connectivity._thread != null: await process_frame
			check(gateway.adds == 2,"lease renewed")
		elif case == "disabled": check(gateway.adds == 0,"explicit opt in only")
		else: check(not connectivity._mapped and connectivity.status.contains("failed"),"failure preserves hosting/manual route")
		root.remove_child(connectivity); connectivity.free()
		check(gateway.deletes == (1 if case == "success" else 0),"owned mapping cleanup "+case)
	# A worker may finish before the main thread publishes its result.
	var unpolled_gateway: Gateway = Gateway.new()
	var unpolled: LfeHostConnectivity = LfeHostConnectivity.new(); root.add_child(unpolled)
	unpolled.set_process(false)
	unpolled.configure(25652,true,func(): return unpolled_gateway)
	while unpolled._thread.is_alive(): await process_frame
	root.remove_child(unpolled); unpolled.free()
	check(unpolled_gateway.deletes == 1,"completed unpolled mapping cleaned on shutdown")
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}));file=null
	print("W5_8_UPNP checks=%d failures=%d" % [checks,failures.size()]);quit(0 if failures.is_empty() else 1)
