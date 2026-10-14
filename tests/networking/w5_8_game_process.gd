extends "res://tests/networking/w5_7_process.gd"
func _command(c: Dictionary) -> void:
	if c.get("op") == "w58_silence":
		game.network_session.suppress_application = true
		commands.append({"op":"w58_silence"}); _write_report(); return
	if c.get("op") == "w58_next_invite":
		game.session_view._invite_input.text = OS.get_environment("LEYFORGE_TEST_NEXT_INVITE")
		await _button(game.session_view.reconnect_button)
		commands.append({"op":"w58_next_invite"}); _write_report(); return
	await super._command(c)

func _extend_quality_report(report: Dictionary) -> void:
	if game.network_session == null: return
	if game.movement != null:
		report["maximum_error"] = game.movement.maximum_error
		if game.player != null and not game.movement.latest_self.is_empty(): report["final_error"] = game.player.global_position.distance_to(LfeMovementProtocol.vec3(game.movement.latest_self["position"]))
	if game.network_session.get_script().resource_path.ends_with("w5_8_delayed_session.gd"):
		report["lost_unreliable"] = game.network_session.lost_unreliable
		report["queued_packets"] = game.network_session.outbound.size()
