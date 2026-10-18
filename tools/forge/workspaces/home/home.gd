extends VBoxContainer
var details: Label
func _ready() -> void:
	var title: Label = Label.new(); title.text = "Forge Home"; title.add_theme_font_size_override("font_size", 26); add_child(title)
	details = Label.new(); details.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY; add_child(details)
	var purpose: Label = Label.new(); purpose.text = "Content Presentation edits existing solid blocks.\nVoxel Asset authors individual spatial cells in a 16³, one-metre volume.\nValidate and review changes before explicitly publishing; bake source separately.\n\nShared Forge domains: Asset, Entity, Blueprint and World.\nFull Block Forge, textures and subsequent workspaces remain future coverage."; purpose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(purpose)

func refresh(document: RefCounted) -> void:
	details.text = "Repository: %s\nCanonical: %s\nDraft: %s\nBase SHA-256: %s\nRevision: %d · %s\nValidation: %s\n" % [document.root, document.relative_path, ProjectSettings.globalize_path("user://forge/session.json"), document.base_hash, document.revision, "Unpublished changes" if document.dirty() else "Matches canonical", "Current PASS" if document.validation.get("success", false) and document.validation.get("revision") == document.revision else "Needs validation"]
