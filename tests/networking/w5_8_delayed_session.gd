extends LfeNetworkSession

var suppress_application: bool = false
# Test-only impairment; no machine-wide routing/firewall changes.
var outbound: Array = []
var auth_queue: Array = []
var send_count: int = 0
var delay: int = int(OS.get_environment("LEYFORGE_TEST_ONE_WAY_MSEC"))
var last_reliable: Dictionary = {}
var lost_unreliable: int = 0
var unreliable_count: int = 0
func send_packet(peer: int, bytes: PackedByteArray, transfer_mode: int, channel: int) -> Error:
	if suppress_application: return OK
	if delay == 0: return super.send_packet(peer,bytes,transfer_mode,channel)
	send_count += 1
	if transfer_mode == MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED:
		unreliable_count += 1
		if unreliable_count % 20 == 0: lost_unreliable += 1; return OK
	if outbound.size() >= 4096: return ERR_OUT_OF_MEMORY
	var due: int = Time.get_ticks_msec()+delay+(send_count%5-2)*3
	if transfer_mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE:
		due = maxi(due,int(last_reliable.get(channel,0))+1); last_reliable[channel] = due
	outbound.append({"peer":peer,"bytes":bytes.duplicate(),"mode":transfer_mode,"channel":channel,"due":due,"generation":generation})
	return OK
func _send_control(peer: int, packet: Dictionary) -> void:
	if suppress_application: return
	if delay == 0: super._send_control(peer,packet); return
	var owned: int = generation
	await get_tree().create_timer(delay/1000.0).timeout
	if owned == generation and not suppress_application: super._send_control(peer,packet)
func _auth(id: int, bytes: PackedByteArray) -> void:
	if delay == 0: super._auth(id,bytes); return
	if auth_queue.size() >= 16: return
	auth_queue.append({"id":id,"bytes":bytes.duplicate(),"due":Time.get_ticks_msec()+delay,"generation":generation})
func _process(delta: float) -> void:
	if suppress_application:
		if _api != null: _api.poll()
		return
	super._process(delta)
	var now: int = Time.get_ticks_msec()
	for i: int in range(outbound.size()-1,-1,-1):
		var item: Dictionary = outbound[i]
		if item["generation"] != generation: outbound.remove_at(i)
	# Preserve reliable channel order, allow jitter/reorder of unreliable packets.
	var remaining: Array = []
	for item: Dictionary in outbound:
		if item["due"] <= now: super.send_packet(item["peer"],item["bytes"],item["mode"],item["channel"])
		else: remaining.append(item)
	outbound = remaining
	remaining = []
	for item: Dictionary in auth_queue:
		if item["generation"] != generation: continue
		if item["due"] <= now: super._auth(item["id"],item["bytes"])
		else: remaining.append(item)
	auth_queue = remaining
