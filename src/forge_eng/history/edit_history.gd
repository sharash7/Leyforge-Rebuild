extends RefCounted
## Linear content commands. Camera and navigation never enter this history.
var commands: Array = []
var cursor: int = 0

func push(command: Dictionary) -> void:
	commands.resize(cursor)
	commands.append(command.duplicate(true))
	cursor += 1

func undo() -> Dictionary:
	if cursor == 0: return {}
	cursor -= 1
	return commands[cursor].duplicate(true)

func redo() -> Dictionary:
	if cursor == commands.size(): return {}
	var command: Dictionary = commands[cursor].duplicate(true)
	cursor += 1
	return command
