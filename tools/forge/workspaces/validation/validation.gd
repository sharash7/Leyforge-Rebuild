extends VBoxContainer
signal requested
signal publish_requested
var report: RichTextLabel
var publish_button: Button

func _ready() -> void:
	var actions: HBoxContainer = HBoxContainer.new(); add_child(actions)
	var validate_button: Button = Button.new(); validate_button.text = "Validate draft"; actions.add_child(validate_button); validate_button.pressed.connect(func() -> void: requested.emit())
	publish_button = Button.new(); publish_button.text = "Review Publish…"; actions.add_child(publish_button); publish_button.pressed.connect(func() -> void: publish_requested.emit())
	report = RichTextLabel.new(); report.size_flags_vertical = Control.SIZE_EXPAND_FILL; report.selection_enabled = true; add_child(report)

func refresh(document: RefCounted) -> void:
	var current: bool = document.validation.get("revision", -1) == document.revision
	publish_button.disabled = not current or not document.validation.get("success", false) or not document.dirty()
	report.text = "Destination: %s\nRevision %d · %s\n\n" % [document.root.path_join(document.relative_path), document.revision, "Current validation PASS" if current and document.validation.get("success", false) else "Validation required / failed"]
	for diagnostic: Dictionary in document.validation.get("diagnostics", []): report.text += "%s · %s · %s %s\n%s\n\n" % [diagnostic.code, diagnostic.source, diagnostic.id, diagnostic.field, diagnostic.message]
	report.text += "Before → After\n"
	for change: Dictionary in document.diff(): report.text += "%s / %s\n%s → %s\n\n" % [change.id, change.field, str(change.before), str(change.after)]
	report.text += "\nCanonical reference locations (derived, discardable)\n"
	for reference: Dictionary in document.validation.get("references", []): report.text += "%s · %s %s\n" % [reference.id, reference.source, reference.field]
