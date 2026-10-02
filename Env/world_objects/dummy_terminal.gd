extends Node3D
class_name DummyTerminal

# ─────────────────────────────────────────────
# DUMMY TERMINAL — something to walk up to and press F on.
#
# Deliberately does nothing on its own. It exists so a tutorial can teach the
# interact verb, and so anything that wants to react has a signal to hang off.
#
# It is a plain Interactible of type OBJECTIVE, which means:
#   - the player routes to it with no special-casing (test_character.interact()
#     does nothing for OBJECTIVE except fire the signal, which is exactly right)
#   - it can be dropped straight into an InteractObjective's `interactibles`
#     array and become a real mission objective with no changes
#
# Reusable by default. MissionTerminal sets destroy_on_use = false for the same
# reason: a terminal you can only press once is not a terminal.
# ─────────────────────────────────────────────

signal used(terminal: DummyTerminal)

@export var interactible: Interactible
@export var label: Label3D
@export var indicator: OmniLight3D
@export var use_sound: AudioStreamPlayer3D

## Shown in the HUD as "F | <prompt_text>".
@export var prompt_text: String = "Use Terminal"
## Shown on the terminal's own Label3D. Empty hides it.
@export var label_text: String = "TERMINAL"
## After the prompt changes on use. Leave empty to keep prompt_text.
@export var used_prompt_text: String = "Terminal Active"
## One-shot terminals disable after a single use. Off means it can be pressed
## repeatedly, which is what a tutorial usually wants.
@export var one_shot: bool = false

@export var idle_color: Color = Color(0.45, 0.85, 0.55)
@export var used_color: Color = Color(0.95, 0.78, 0.35)

var was_used: bool = false


func _ready() -> void:
	if interactible == null:
		interactible = _find_interactible()
	if interactible == null:
		push_warning("DummyTerminal '%s' has no Interactible child — nothing can be pressed." % name)
		return

	interactible.type = Enums.InteractTypes.OBJECTIVE
	# A terminal that vanishes the first time you press it is not a terminal.
	# one_shot disables it instead, which keeps the body in the world.
	interactible.destroy_on_use = false
	interactible.disable_on_use = one_shot
	if not interactible.interacted.is_connected(_on_interacted):
		interactible.interacted.connect(_on_interacted)

	_apply_panel()
	_refresh()
	_claim_prompt.call_deferred()


# The HUD reads the prompt off the Interactible's "mission_objective" meta,
# which InteractObjective sets on its own consoles during _ready. Deferred and
# conditional so a terminal that IS an objective target still shows the
# objective's text, and a standalone one shows ours instead of "Interact".
func _claim_prompt() -> void:
	if interactible == null or not is_instance_valid(interactible):
		return
	if not interactible.has_meta("mission_objective"):
		interactible.set_meta("mission_objective", self)


func get_prompt() -> String:
	if was_used and used_prompt_text != "":
		return used_prompt_text
	return prompt_text


func _on_interacted(_source: Interactible) -> void:
	was_used = true
	if use_sound != null:
		use_sound.play()
	_refresh()
	used.emit(self)


# Put it back to untouched. Levels reset their interactibles on player death,
# so a tutorial terminal should come back with them.
func reset() -> void:
	was_used = false
	if interactible != null and is_instance_valid(interactible):
		interactible.reset()
	_refresh()


func _refresh() -> void:
	if label != null:
		label.text = label_text
		label.visible = label_text != ""
	if indicator != null:
		indicator.light_color = used_color if was_used else idle_color


func _find_interactible() -> Interactible:
	for child in get_children():
		if child is Interactible:
			return child
	return null

# ── BEING SOMETHING ELSE'S FRONT PANEL ───────
#
# A capture point used to be this console on its own. It can also be the
# interactive face of a much bigger object — a compute core — in which case the
# casing has to go and the reach has to grow to match what the player is actually
# walking up to.

## The console's own casing. Hidden when `show_body` is false.
@export var body_pieces: Array[Node3D] = []
@export var show_body: bool = true

## Reach volume in metres, in this terminal's own space. ZERO keeps whatever the
## scene authored.
##
## SIZE IT TO THE FOOTPRINT OF WHAT IT IS THE PANEL FOR, not bigger. The player's
## InteractRaycast is 2 m long, masks the Interactible layer ONLY — so it passes
## straight through the core's solid body — and does NOT hit from inside. A
## volume that reaches out past the player swallows the camera and the ray then
## starts inside it and reports nothing at all. At the footprint exactly, the
## player cannot stand closer than their own radius, which leaves the camera half
## a metre outside and the ray crossing cleanly in.
@export var reach_size: Vector3 = Vector3.ZERO
## Where the reach volume is centred vertically. Eye height, not the middle of a
## twelve-metre core.
@export var reach_height: float = 1.0
## Lift the indicator lamp to here. 0 leaves it where the scene put it — which is
## inside the core, where it lights nothing.
@export var indicator_height: float = 0.0


## Casing, reach and lamp. Called from _ready once the interactible is resolved.
func _apply_panel() -> void:
	for piece in body_pieces:
		if piece != null and is_instance_valid(piece):
			piece.visible = show_body
	if indicator_height != 0.0 and indicator != null:
		indicator.position.y = indicator_height
	if reach_size == Vector3.ZERO:
		return
	if interactible == null:
		return                      # already warned about in _ready
	var cs := interactible.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		push_warning("DummyTerminal '%s' has no CollisionShape3D under its Interactible, so reach_size does nothing and it keeps the console-sized reach." % name)
		return
	var box := cs.shape as BoxShape3D
	if box == null:
		push_warning("DummyTerminal '%s' reach is not a BoxShape3D, so reach_size does nothing." % name)
		return
	# DUPLICATED FIRST. A shape set in a scene is ONE resource shared by every
	# instance of that scene, so resizing it in place would resize the reach of
	# every terminal in the level — and of every level loaded afterwards.
	box = box.duplicate()
	box.size = reach_size
	cs.shape = box
	cs.position = Vector3(0.0, reach_height, 0.0)
