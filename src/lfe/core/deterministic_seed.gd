class_name LfeDeterministicSeed
extends RefCounted

const DEFAULT_WORLD_SEED: int = 184552221
const _POSITIVE_31_BIT_MASK: int = 0x7fffffff


static func from_user_args(arguments: PackedStringArray, fallback: int = DEFAULT_WORLD_SEED) -> int:
	for argument: String in arguments:
		if argument.begins_with("--seed="):
			return from_text(argument.trim_prefix("--seed="))
	return normalize(fallback)


static func from_text(seed_text: String) -> int:
	var normalized_text: String = seed_text.strip_edges()
	if normalized_text.is_empty():
		return DEFAULT_WORLD_SEED
	if normalized_text.is_valid_int():
		return normalize(normalized_text.to_int())

	var value: int = 2166136261
	for byte: int in normalized_text.to_utf8_buffer():
		value = ((value ^ byte) * 16777619) & _POSITIVE_31_BIT_MASK
	return value


static func normalize(seed_value: int) -> int:
	return seed_value & _POSITIVE_31_BIT_MASK
