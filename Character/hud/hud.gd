extends Control
class_name HUD
@export var player: Player
@export var scan_effect_scene: PackedScene
@export var enemy_marker_scene: PackedScene
@export var health_label: Label
@export var ammo_label: Label
@export var shards_label: Label

@export var interact_box: HBoxContainer
@export var interact_label: Label
@export var interact_texture: TextureRect
@export var ui: Control
@export var campaign: CampaignManager


var interact_textures: Dictionary = {
	Enums.InteractTypes.HEALTH : "PASS",
	Enums.InteractTypes.SHARDS : preload("res://2d_assets/TB_Textures/flash-drive.png"),
	Enums.InteractTypes.BONFIRE: preload ("res://addons/plenticons/icons/64x-hidpi/symbols/refresh-green.png"),
	Enums.InteractTypes.BITS: preload("res://2d_assets/icon_neural-bit.png")
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
		Enums.InteractTypes.SHARDS:
			interact_label.text = "F | Salvage  +%d" % value
		Enums.InteractTypes.BITS:
			interact_label.text = "F | Bits  +%d" % value
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


func _process(_delta: float) -> void:
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

func update_status(health: int, max_health: int, magazine_capacity: int, magazine_size: int, shards:int, bits: int) -> void:
	ui.update_status(health, max_health, magazine_capacity, magazine_size, shards, bits)
	#health_label.text = "Health: %d" % health
	#ammo_label.text = "Ammo: %d / %d" % [magazine_capacity, magazine_size]
	#shards_label.text = ": " + str(sharsds)
