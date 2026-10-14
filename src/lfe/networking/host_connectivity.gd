class_name LfeHostConnectivity
extends Node

const LEASE_SECONDS: int = 3600
const RENEW_MSEC: int = 1800000
var status: String = "UPnP disabled; public route unknown"
var external_address: String = ""
var warning: String = ""
var port: int = 0
var addresses: Array[String] = []
var _thread: Thread
var _gateway: Variant
var _factory: Callable
var _mapped: bool = false
var _renew_at: int = 0
var _stopping: bool = false
var _mutex: Mutex = Mutex.new()

static func classification(address: String) -> String:
	if not address.is_valid_ip_address(): return "unknown"
	if address.contains(":"):
		var lower: String = address.to_lower()
		if lower in ["::","::1"] or lower.begins_with("fe8") or lower.begins_with("fe9") or lower.begins_with("fea") or lower.begins_with("feb") or lower.begins_with("fc") or lower.begins_with("fd"): return "non_routable"
		return "global_candidate"
	var parts: PackedStringArray = address.split(".")
	var a: int = int(parts[0]); var b: int = int(parts[1])
	if a == 10 or a == 127 or a == 0 or a >= 224 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 169 and b == 254) or (a == 100 and b >= 64 and b <= 127): return "non_routable"
	return "global_candidate"

func configure(game_port: int, enabled: bool, factory: Callable = Callable()) -> void:
	port = game_port; _factory = factory
	for address: String in IP.get_local_addresses():
		if addresses.size() >= 16: break
		if address.is_valid_ip_address() and address not in ["::","::1","0.0.0.0"] and not address.begins_with("127.") and not address.begins_with("169.254.") and not address.to_lower().begins_with("fe80:"):
			addresses.append(address)
	if enabled:
		status = "UPnP discovering; public route unknown"
		_start_work("map")

func _start_work(operation: String) -> void:
	if _thread != null: return
	_thread = Thread.new()
	if _thread.start(_work.bind(operation)) != OK:
		_thread = null; status = "UPnP worker failed; use manual UDP forwarding"

func _work(operation: String) -> Dictionary:
	# Gateway belongs only to this worker. No Nodes/scene/network API on this thread.
	if operation == "map":
		_gateway = _factory.call() if _factory.is_valid() else UPNP.new()
		var discovered: int = _gateway.discover(2000,2,"InternetGatewayDevice")
		if discovered != UPNP.UPNP_RESULT_SUCCESS or _gateway.get_gateway() == null or not _gateway.get_gateway().is_valid_gateway(): return {"mapped":false,"address":"","result":"discovery_failed"}
	var code: int = _gateway.add_port_mapping(port,port,"Leyforge Private Session","UDP",LEASE_SECONDS)
	var address: String = _gateway.query_external_address() if code == UPNP.UPNP_RESULT_SUCCESS else ""
	_mutex.lock(); var stopping: bool = _stopping; _mutex.unlock()
	if stopping and code == UPNP.UPNP_RESULT_SUCCESS:
		_gateway.delete_port_mapping(port,"UDP")
		return {"mapped":false,"address":"","result":"closed"}
	return {"mapped":code == UPNP.UPNP_RESULT_SUCCESS,"address":address,"result":"mapped" if code == UPNP.UPNP_RESULT_SUCCESS else "mapping_failed_%d" % code}

func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		var result: Dictionary = _thread.wait_to_finish(); _thread = null
		# A failed renewal may leave an earlier leased mapping until its expiry.
		_mapped = _mapped or result["mapped"]
		external_address = result["address"]
		warning = "Direct inbound hosting may be blocked by CGNAT/double NAT." if classification(external_address) == "non_routable" else ""
		status = "UPnP mapped (UDP, 3600s lease); WAN reachability unverified" if result["mapped"] else "UPnP unavailable / failed (%s); use manual UDP forwarding" % result["result"]
		_renew_at = Time.get_ticks_msec()+RENEW_MSEC if result["mapped"] else 0
	if _renew_at > 0 and Time.get_ticks_msec() >= _renew_at and _thread == null:
		_renew_at = 0; _start_work("renew")

func _cleanup() -> void:
	if _mapped and _gateway != null: _gateway.delete_port_mapping(port,"UDP")

func _exit_tree() -> void:
	_mutex.lock(); _stopping = true; _mutex.unlock()
	if _thread != null:
		var result: Dictionary = _thread.wait_to_finish(); _thread = null
		if result.get("result") == "closed": _mapped = false
		else: _mapped = _mapped or result.get("mapped",false)
	# Shutdown waits only after gameplay/transport end; cleanup is still worker-owned.
	var cleanup: Thread = Thread.new()
	if cleanup.start(_cleanup) == OK: cleanup.wait_to_finish()
