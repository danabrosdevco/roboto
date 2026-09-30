@tool
extends EditorPlugin

# ─────────────────────────────────────────────
# EXPORT BUILD — one button in the editor's top bar.
#
# Saves the open scenes (the export reads what is on disk), then runs
# tools/export_build.bat in its own console window: bump the version, export
# a release build to ../Exports/DataCenterWars2109_v<version>, zip it, open the
# folder. The window stays up with the result until you press a key.
#
# Everything real lives in tools/export.ps1; this is only the button. Switch it
# on once: Project > Project Settings > Plugins > Export build.
# ─────────────────────────────────────────────

var _button: Button


func _enter_tree() -> void:
	_button = Button.new()
	_button.text = "Export build"
	_button.flat = true
	_button.tooltip_text = "Save open scenes, bump the version and export the next playtest build to ../Exports.\nUnsaved script edits are not included: save those first."
	_button.pressed.connect(_on_pressed)
	add_control_to_container(CONTAINER_TOOLBAR, _button)


func _exit_tree() -> void:
	if _button != null:
		remove_control_from_container(CONTAINER_TOOLBAR, _button)
		_button.queue_free()
		_button = null


func _on_pressed() -> void:
	EditorInterface.save_all_scenes()
	# The same as double-clicking the .bat: Windows opens it in a console.
	OS.shell_open(ProjectSettings.globalize_path("res://tools/export_build.bat").replace("/", "\\"))
