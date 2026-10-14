extends Node

var configured: Dictionary = {}
func _ready() -> void:
	process_priority = -10000

func _process(_delta: float) -> void:
	var secret: PackedByteArray = LfePrivateSessionAuth.parse_invite(OS.get_environment("LEYFORGE_TEST_INVITE"))
	if secret.size() != 16: return
	for game: Node in get_tree().root.get_children():
		if not game is LeyforgeWave1Playground or game.network_session == null: continue
		var session: LfeNetworkSession = game.network_session
		if configured.has(session.get_instance_id()): continue
		if session.mode == "HOST" and session.private_auth != null:
			session.private_auth._secret = secret.duplicate()
			configured[session.get_instance_id()] = true
		elif session.mode == "JOIN":
			if session.invite_secret.is_empty(): session.invite_secret = secret.duplicate()
			configured[session.get_instance_id()] = true
