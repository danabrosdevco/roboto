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
