class_name LfeCommandResult
extends RefCounted

var success: bool
var reason_code: String
var data: Dictionary

func _init(ok: bool,reason: String,payload: Dictionary={}) -> void:
	success=ok;reason_code=reason;data=payload

static func accepted(payload: Dictionary={}) -> LfeCommandResult:
	return LfeCommandResult.new(true,"ok",payload)

static func rejected(reason: String) -> LfeCommandResult:
	return LfeCommandResult.new(false,reason)
