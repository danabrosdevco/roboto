extends ColorRect

# ─────────────────────────────────────────────
# THE DOOR INTO THE SIM.
#
#   var wipe = _Wipe.new()
#   layer.add_child(wipe)
#   wipe.midpoint.connect(func(): ...put the arena up...)
#   wipe.play()
#
# Pressing ENTER THE ARENA used to pop a panel over the operations board with
# no transition at all, which read as opening a menu rather than going
# somewhere. The arena is not a menu — it is the one place in the game you
# reach without travelling, because it runs on your own hardware.
#
# IT SWAPS THE SCREEN AT ITS OWN MIDPOINT. The caller does not time anything:
# it connects `midpoint` and builds the new screen there, under full cover, so
# the board never flickers out from under the player.
#
# A TWEEN, NOT A COROUTINE, and that is load-bearing. An `await
# get_tree().process_frame` loop that outlives the tree segfaults in cleanup
# when the game quits mid-animation; a tween is owned by this node and dies
# with it. The same bug cost a session once already.
# ─────────────────────────────────────────────

const SHADER := preload("res://Character/hud/cyberspace_wipe.gdshader")
const Kit := preload("res://Character/hud/squad/ui_kit.gd")

## The screen is covered at `seconds * IN_FRACTION` and clear at `seconds`.
@export var seconds: float = 0.9
const IN_FRACTION := 0.42

## What it says while you are in it. Empty for no caption.
@export var caption: String = "ENTERING SIM ARENA"

## Fully covered: whatever is behind this is safe to tear down and rebuild.
signal midpoint
## Clear again, and this node is about to free itself.
signal finished

var _label: Label = null


func _ready() -> void:
	# NEVER PAUSABLE. This exists to cover a pause and a level load, and a Tween
	# on a pausable node does not advance while the tree is paused — so the wipe
	# would sit frozen exactly when it is needed. Set here rather than left to
	# the caller so no caller can forget it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# NOTHING BEHIND IT IS CLICKABLE while it runs — a button pressed through
	# the wipe would act on a screen the player can no longer see.
	mouse_filter = Control.MOUSE_FILTER_STOP
	color = Color(0.0, 0.0, 0.0, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("tint", HUDPalette.SIGNAL)
	# Per-play, so two entries in a row do not tear on the same rows.
	mat.set_shader_parameter("seed", randf() * 128.0)
	material = mat

	if caption != "":
		_label = Kit.label(caption, HUDPalette.SIGNAL, Kit.HEADING, true)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_label.modulate.a = 0.0
		add_child(_label)


func play() -> void:
	var t := create_tween()
	t.set_parallel(false)
	t.tween_property(material, "shader_parameter/progress", IN_FRACTION,
		seconds * IN_FRACTION)
	t.tween_callback(func(): midpoint.emit())
	if _label != null:
		# Only while the screen is covered. A caption still fading as the arena
		# appears looks like a label on the arena.
		t.parallel().tween_property(_label, "modulate:a", 1.0, seconds * 0.18)
		t.parallel().tween_property(_label, "modulate:a", 0.0, seconds * 0.30) \
			.set_delay(seconds * 0.28)
	t.tween_property(material, "shader_parameter/progress", 1.0,
		seconds * (1.0 - IN_FRACTION))
	t.tween_callback(func(): finished.emit())
	t.tween_callback(queue_free)
