extends Control
class_name HUD
@export var player: Player
@export var scan_effect_scene: PackedScene
@export var enemy_marker_scene: PackedScene
@export var health_label: Label
@export var ammo_label: Label

@export var interact_box: HBoxContainer
@export var interact_label: Label
@export var interact_texture: TextureRect
@export var ui: Control
@export var campaign: CampaignManager


var interact_textures: Dictionary = {
	Enums.InteractTypes.HEALTH : "PASS",
	Enums.InteractTypes.BONFIRE: preload ("res://addons/plenticons/icons/64x-hidpi/symbols/refresh-green.png"),
}

# ── OPTIONS ───────────────────────────────────
# BRIGHTNESS and SCREEN NOISE both land on the SignalFilter's material. The
# authored noise values are captured once, so the option SCALES what the scene
# says rather than replacing it — retune the material in hud.tscn and the
# option follows along.
var _filter_mat: ShaderMaterial
var _base_noise: Dictionary = {}


func _ready() -> void:
	var filter := get_node_or_null("SignalFilter") as CanvasItem
	if filter != null and filter.material is ShaderMaterial:
		_filter_mat = filter.material
		for p in ["grain", "dropout", "block_glitch"]:
			var v = _filter_mat.get_shader_parameter(p)
			_base_noise[p] = float(v) if v != null else 0.0
	Settings.add_listener(_on_setting_changed)
	_on_setting_changed("*")


func _exit_tree() -> void:
	Settings.remove_listener(_on_setting_changed)


func _on_setting_changed(_key: String) -> void:
	if _filter_mat == null:
		return
	_filter_mat.set_shader_parameter("gamma", Settings.get_float("display.brightness"))
	var noise := Settings.get_float("display.screen_noise")
	for p in _base_noise:
		_filter_mat.set_shader_parameter(p, _base_noise[p] * noise)


func activate_scan_effect(time: float):
	var new_scan_effect_scene = scan_effect_scene.instantiate()
	add_child(new_scan_effect_scene)
	move_child(new_scan_effect_scene,0)
	update_scanner(time)

# One marker per target, ever. Re-marking something that is already marked just
# resets its timer — previously every scan spawned a fresh Control on top of the
# old one and you ended up with a stack of brackets on the same robot.
var _enemy_markers: Dictionary = {}   # instance_id -> ScanEnemyMarker

func activate_enemy_marker(obj:Node3D, duration: float):
	if obj == null or not is_instance_valid(obj):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var id := obj.get_instance_id()
	var existing = _enemy_markers.get(id)
	if existing != null and is_instance_valid(existing):
		existing.duration = duration
		existing.time = 0.0
		return

	var screen_pos = camera.unproject_position(obj.global_position)
	var hud_marker = enemy_marker_scene.instantiate()
	hud_marker.position = Vector2(screen_pos.x, screen_pos.y)
	hud_marker.target = obj
	hud_marker.duration = duration
	add_child(hud_marker)
	move_child(hud_marker, 0)
	_enemy_markers[id] = hud_marker
	hud_marker.tree_exited.connect(func(): _enemy_markers.erase(id))


func activate_interactible(interactible: Interactible):
	if interactible == null:
		deactivate_interaction()
		return
	var type = interactible.get_type()
	var value = interactible.get_value()
	_current_interactible = interactible
	interact_box.visible = true
	#print (interactible)
	match type:
		Enums.InteractTypes.BONFIRE:
			if not interactible.get_activated():
				interact_label.text = "F | Activate SLAB"
			else:
				interact_label.text = "F | Reconstruct at SLAB"
		Enums.InteractTypes.MISSION:
			# The terminal knows which operation is queued. `value` is
			# meaningless on a terminal, which is where "F | 0" came from.
			interact_label.text = "F | %s" % _prompt_from(interactible.get_parent(), "Select Mission")
		Enums.InteractTypes.OBJECTIVE:
			# The console doesn't own the objective — InteractObjective holds an
			# array of them and tags each one on _ready, so ask the tag.
			var objective := _objective_tag(interactible)
			interact_label.text = _objective_prompt(objective)
		Enums.InteractTypes.HEALTH:
			interact_label.text = "F | Repair  +%d" % value
		_:
			interact_label.text = "F | %d" % value  # default label for others

	if interact_textures.has(type):
		interact_texture.texture = interact_textures[type]
		interact_texture.visible = true
	else:
		# Hide it rather than blanking it — an empty TextureRect still reserves
		# its width and leaves a gap where an icon should be.
		interact_texture.texture = null
		interact_texture.visible = false


# Anything that can describe itself does; everything else falls back.
func _prompt_from(source, fallback: String) -> String:
	if source != null and is_instance_valid(source) and source.has_method("get_prompt"):
		var text: String = source.get_prompt()
		if text != "":
			return text
	return fallback


# Godot's get_meta(name, default) only honours the default when it is NOT null:
# a null default takes the same ERR_FAIL path as passing no default at all, so
# asking an untagged console for its objective printed an error every frame you
# looked at a standalone terminal. has_meta first is the only quiet way to ask.
func _objective_tag(source: Object) -> Object:
	if source == null or not is_instance_valid(source):
		return null
	if not source.has_meta("mission_objective"):
		return null
	var tag = source.get_meta("mission_objective")
	if tag is Object and is_instance_valid(tag):
		return tag
	return null

# "F | Capture Lock Relay  40%" while it counts, and no F once it is taken:
# there is nothing left to press there.
func _objective_prompt(objective: Object) -> String:
	var text := _prompt_from(objective, "Interact")
	if objective != null and is_instance_valid(objective) and objective.get("completed") == true:
		return text
	return "F | %s" % text


# Kept so the prompt follows a capture while you look at the console. The
# player script only pushes a new interactible when the raycast target CHANGES,
# so without this the prompt sat at 0% for the whole capture — and refreshing
# only WHILE it counted froze it on the last count, 99%, once it resolved.
var _current_interactible: Interactible


func _process(delta: float) -> void:
	# FOLDED IN RATHER THAN A SECOND _process. The HUD already had one, and it
	# returns early on every frame nothing is being looked at — so a decay put
	# below those returns would never run, and a set_process(false) to stop the
	# decay would have silently killed the interact prompt.
	_tick_damage_pulse(delta)
	if _current_interactible == null or not is_instance_valid(_current_interactible):
		return   # looking at nothing
	if not interact_box.visible:
		return   # no prompt up to keep current
	if _current_interactible.get_type() != Enums.InteractTypes.OBJECTIVE:
		return   # only objective consoles change while you look at them
	var text := _objective_prompt(_objective_tag(_current_interactible))
	if interact_label.text != text:
		interact_label.text = text


func deactivate_interaction():
	interact_box.visible = false
	_current_interactible = null

func update_scanner(time:float):
	ui.update_scanner(time)

func update_status(health: int, max_health: int, magazine_capacity: int, magazine_size: int) -> void:
	ui.update_status(health, max_health, magazine_capacity, magazine_size)
	#health_label.text = "Health: %d" % health
	#ammo_label.text = "Ammo: %d / %d" % [magazine_capacity, magazine_size]


# ─────────────────────────────────────────────
# DAMAGE AND SIGNAL — WIP
# ─────────────────────────────────────────────
# signal_filter.gdshader has carried a `damage` uniform labelled "chassis
# integrity loss" since it was written, and nothing in the game has ever set it.
# This sets it.
#
# TWO SOURCES, ONE UNIFORM. A FLOOR from how hurt you are, which does not
# recover, and a SPIKE on each hit, which does. The screen reacting to a hit and
# the screen looking damaged are different statements, and a single value driven
# only by health can make neither.
#
# The artefact knobs ride along with the spike, scaled by the player's SCREEN
# NOISE option exactly as they already are for the ambient look — so someone who
# has turned the noise down does not get it back through the damage path.

const _DamageDirections := preload("res://Character/hud/damage_directions.gd")

# ─────────────────────────────────────────────
# THE FEED IS THE PLAYER'S SIGNAL INTEGRITY. One number, read twice: the blue
# strip shows it and the shader degrades by it, so the bar and the picture
# cannot disagree.
#
# IT USED TO BE DERIVED FROM HEALTH, which was a proxy invented because the
# player had no signal_integrity of its own. It has one now — see AI — and the
# two sources that already existed (near-miss suppression from every shot, and
# EMP) drive it without anything here being involved. Health is health; being
# shot at is what costs you the link.
# ─────────────────────────────────────────────

## How far one hit punches the feed past where signal alone has it, and how
## fast that falls back. This is the FLINCH, not the damage: the lasting
## degradation comes from signal, which the same shot already suppressed.
@export var damage_spike: float = 0.2
@export var damage_spike_decay: float = 2.2
## The most the spike may ever reach, however many hits land in one frame.
##
## This is the knob that stops a burst of automatic fire blinding you. At 0.45
## a spike per hit, three rounds arriving on the same frame pinned the uniform
## at 1.0 and the screen went to unreadable static — photographed, and three
## rounds in a frame is an ordinary burst, not an edge case.
@export var damage_spike_cap: float = 0.3
## Ceiling on signal loss and spike together. Past roughly here the feed stops
## being a degraded picture and becomes no picture, and a player who cannot see
## cannot fight back out of trouble.
@export var damage_ceiling: float = 0.85

var _signal: float = 1.0
var _damage_pulse: float = 0.0
var _directions: Control = null


## The player's live signal_integrity, pushed every physics frame. 1.0 clean,
## 0.0 e-killed.
func set_signal(integrity: float) -> void:
	var v: float = clampf(integrity, 0.0, 1.0)
	if is_equal_approx(v, _signal):
		return
	_signal = v
	_apply_damage_uniform()


## A hit landed. `from` may be null — a fall, or something that did not announce
## itself — in which case the screen still reacts but no arc is drawn, because
## an arc pointing in an arbitrary direction is worse than none.
func register_hit(amount: float, from = null) -> void:
	_damage_pulse = minf(_damage_pulse + damage_spike, damage_spike_cap)
	_apply_damage_uniform()
	if from == null or not (from is Node3D) or not is_instance_valid(from):
		return
	_ensure_directions()
	if _directions != null:
		_directions.add_hit((from as Node3D).global_position, amount)


func _ensure_directions() -> void:
	if _directions != null and is_instance_valid(_directions):
		return
	_directions = _DamageDirections.new()
	_directions.name = "DamageDirections"
	add_child(_directions)
	# UNDER the signal filter, so the arcs are quantised and dithered with
	# everything else. Drawn on top they read as a different game's UI.
	var filter := get_node_or_null("SignalFilter")
	if filter != null:
		move_child(_directions, filter.get_index())


func _apply_damage_uniform() -> void:
	var d: float = clampf((1.0 - _signal) + _damage_pulse, 0.0, damage_ceiling)
	# THE BAR IS THE SIGNAL ITSELF, 1:1, not the shader value. The spike is a
	# flinch on the picture and must not move the readout — a strip that dipped
	# every time you were grazed would stop being a reading of anything.
	#
	# Outside the filter's null check, because the strip is the only readout of
	# this number and has to survive a HUD with no SignalFilter — the headless
	# harnesses build exactly that.
	if ui != null and ui.has_method("update_signal"):
		ui.update_signal(_signal, d)
	if _filter_mat == null:
		return
	_filter_mat.set_shader_parameter("damage", d)
	# The artefacts lift with the SPIKE only. Riding the signal loss as well
	# would leave a suppressed player permanently staring through static, which
	# reads as a broken game rather than a broken robot.
	var noise := Settings.get_float("display.screen_noise")
	for p in _base_noise:
		# A light lift only. The uniform itself now drives resolution, posterising
		# and chroma loss, so multiplying the grain on top of that as well was
		# counting the same hit twice and was most of why a burst whited out.
		var lift: float = 1.0 + _damage_pulse * 1.2
		_filter_mat.set_shader_parameter(p, float(_base_noise[p]) * noise * lift)


func _tick_damage_pulse(delta: float) -> void:
	if _damage_pulse <= 0.0:
		return
	_damage_pulse = maxf(_damage_pulse - delta * damage_spike_decay, 0.0)
	_apply_damage_uniform()
