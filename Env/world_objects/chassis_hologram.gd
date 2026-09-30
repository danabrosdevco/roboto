extends Node3D
class_name ChassisHologram

# ─────────────────────────────────────────────
# CHASSIS HOLOGRAM — a bay in the depot projecting a frame you can walk round.
#
# The squad manager tells you a Reclaimer has 2 module slots and costs 130. It
# cannot tell you what a Reclaimer IS. Standing next to one, at its own size,
# is the only thing that does — and the depot has four empty bays in the wall
# doing nothing.
#
# The projection is the REAL chassis scene, not a stand-in model: whatever
# frame lands in the catalogue next shows up here the day it does, with no
# second model to keep in step. It is stripped down to the meshes before it is
# put in the tree — script, groups, colliders, sensors, sound and particles all
# go, so what stands in the bay is a shape and nothing else. Put in whole, the
# "enemies" group on the soldier chassis would leave four live hostiles
# standing in your own base.
#
# Four bays, six buildable frames: each bay opens on a different one and F
# steps it to the next, so every frame can be seen from any bay.
# ─────────────────────────────────────────────

## Where the projected frame is built. Turns slowly so you can see all of it.
@export var model_root: Node3D
@export var name_label: Label3D
@export var facts_label: Label3D
@export var glow: OmniLight3D
@export var ring: MeshInstance3D
@export var interactible: Interactible
@export var use_sound: AudioStreamPlayer3D

## Which buildable frame this bay opens on. Bays count from 0, so the four in
## the depot wall show four different frames without being told which.
@export var start_index: int = 0
## Seconds for one full turn. Slow: it is a display, not a carousel.
@export var spin_seconds: float = 16.0
## How tall a frame the bay is lit for. Sets the scan pitch, nothing else.
@export var bay_height: float = 3.0
@export var tint: Color = Color(0.35, 0.82, 1.0)
## A frame an operation has still to unlock: shown, but plainly not on offer.
@export var locked_tint: Color = Color(1.0, 0.62, 0.22)

## Emitted when the bay is switched, so a tutorial or an objective can listen.
signal switched(frame: ChassisDefinition)

var frame: ChassisDefinition          # what is standing in the bay now
var _frames: Array[ChassisDefinition] = []
var _at: int = 0
var _skin: ShaderMaterial
var _spin: Tween
var _build: Tween

const _SHADER := preload("res://Env/world_objects/chassis_hologram.gdshader")
const _Ground := preload("res://Campaign/ground_snap.gd")
## Nodes that are no part of the SHAPE of a frame. Every one of these is freed
## before the projection reaches the tree — a Detection area in the base would
## start looking for targets, and GPUParticles3D in Compatibility takes the
## graphics driver down with it.
const _DROP := ["Area3D", "CollisionShape3D", "CollisionPolygon3D", "AudioStreamPlayer",
	"AudioStreamPlayer3D", "NavigationAgent3D", "GPUParticles3D", "CPUParticles3D",
	"OmniLight3D", "SpotLight3D", "Camera3D", "Timer", "RayCast3D", "AnimationPlayer"]


func _ready() -> void:
	_skin = ShaderMaterial.new()
	_skin.shader = _SHADER
	if interactible != null:
		interactible.type = Enums.InteractTypes.OBJECTIVE
		interactible.destroy_on_use = false   # a display you can press once is a poster
		interactible.disable_on_use = false
		if not interactible.interacted.is_connected(_on_interacted):
			interactible.interacted.connect(_on_interacted)
		_claim_prompt.call_deferred()
	_frames = _buildable()
	if _frames.is_empty():
		# No catalogue — a test rig, or the level opened on its own. An unlit
		# empty bay is the honest answer, not an error.
		_show_empty()
		return
	_at = posmod(start_index, _frames.size())
	_project(_frames[_at], false)


## The frames the factory can build, in catalogue order. Locked ones are in:
## seeing what Coast Road pays out is the reason to go and clear it.
func _buildable() -> Array[ChassisDefinition]:
	var out: Array[ChassisDefinition] = []
	var campaign := get_tree().get_first_node_in_group("campaign")
	if campaign == null or not ("catalogue" in campaign):
		return out
	var catalogue = campaign.catalogue
	if catalogue == null or not ("chassis" in catalogue):
		return out
	for c in catalogue.chassis:
		if c != null and c.purchasable:
			out.append(c)
	return out


## Step the bay on to the next frame in the catalogue, wrapping.
func step() -> void:
	if _frames.size() < 2:
		return   # one frame to show, so there is nowhere to step to
	_at = posmod(_at + 1, _frames.size())
	_project(_frames[_at], true)


func _on_interacted(_source: Interactible) -> void:
	if use_sound != null:
		use_sound.play()
	step()


# The HUD reads its prompt off the Interactible "mission_objective" meta — the
# same hook DummyTerminal uses. Deferred and conditional, so a bay some mission
# has made a target still shows the objective text instead of this.
func _claim_prompt() -> void:
	if interactible == null or not is_instance_valid(interactible):
		return
	if not interactible.has_meta("mission_objective"):
		interactible.set_meta("mission_objective", self)


func get_prompt() -> String:
	if _frames.size() < 2:
		return "Bay Offline"
	return "Next Frame"


func _project(def: ChassisDefinition, sweep: bool) -> void:
	frame = def
	_dress(def)
	_rebuild_model(def)
	_relabel(def)
	if _build != null and _build.is_valid():
		_build.kill()
	if not sweep:
		_skin.set_shader_parameter("reveal", 1.0)
		return
	# A switched bay BUILDS the frame up from the pad rather than cutting to
	# it. The sweep is the one part of the effect the shader cannot time on its
	# own, because only the bay knows when it was pressed.
	_skin.set_shader_parameter("reveal", 0.0)
	_build = create_tween()
	_build.tween_property(_skin, "shader_parameter/reveal", 1.0, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	switched.emit(def)


# Tint, pad ring and bay light all from the one colour: cyan for a frame the
# factory can build today, amber for one an operation still owes you.
func _dress(def: ChassisDefinition) -> void:
	var colour: Color = locked_tint if _locked_by(def) != null else tint
	_skin.set_shader_parameter("tint", colour)
	_skin.set_shader_parameter("base_y", (model_root if model_root != null else self).global_position.y)
	_skin.set_shader_parameter("span", maxf(bay_height, 0.5))
	if glow != null:
		glow.light_color = colour
	if ring != null:
		var worn := ring.get_surface_override_material(0)
		if worn is StandardMaterial3D:
			var mat := (worn as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.albedo_color = colour
			mat.emission = colour
			ring.set_surface_override_material(0, mat)
	# Lifted well off the tint: the plate hangs in front of the bay's own lit
	# grid, and the colour that reads on the projection is unreadable on that.
	if name_label != null:
		name_label.modulate = colour.lightened(0.7)
	if facts_label != null:
		facts_label.modulate = colour.lightened(0.6)


func _rebuild_model(def: ChassisDefinition) -> void:
	if model_root == null:
		return
	for old in model_root.get_children():
		model_root.remove_child(old)
		old.free()
	if def == null or def.scene == null:
		return
	var body := def.scene.instantiate() as Node3D
	# How far below its origin the frame stands in the field, taken while it
	# still HAS colliders — _strip is about to take them off.
	var foot := _Ground.foot_depth(body)
	# Stripped BEFORE it goes in the tree: _ready has not run yet, so nothing
	# has registered itself, claimed a nav agent or joined a group.
	_strip(body)
	model_root.add_child(body)
	_seat(body, foot)
	if _spin == null or not _spin.is_valid():
		_spin = create_tween().set_loops()
		_spin.tween_property(model_root, "rotation:y", TAU, maxf(spin_seconds, 1.0)).from(0.0)


# A frame sits at its own origin, which for a soldier is the middle of its
# capsule — a metre off the floor, so dropped straight onto the pad it stands
# shin-deep in it. `foot` is how far below its origin the frame stands in the
# field, and standing it that way here is the whole point: a Rover seated on
# the bottom of its MESH instead hangs half a metre off the pad, because the
# lowest thing in its hull is not what its wheels rest on.
#
# The mesh is still measured, for the height the sweep runs over and for where
# the name plate hangs. CSG is built a frame or two after it enters the tree
# and reads as empty until it is, so that measurement waits for it.
func _seat(body: Node3D, foot: float) -> void:
	var last := AABB()
	for _tries in 20:
		if not is_instance_valid(body) or body.get_parent() != model_root:
			return   # switched again while we waited
		var box := _bounds(body)
		# Settled, not merely non-empty. A rover reads as its lamps for a frame
		# or two before the CSG hull lands, and a name plate pinned to THAT
		# hangs at knee height on the finished machine.
		if box.size.y > 0.01 and box.position.is_equal_approx(last.position) and box.size.is_equal_approx(last.size):
			_stand_on(body, box, foot)
			return
		last = box
		await get_tree().process_frame
	if last.size.y > 0.01:
		_stand_on(body, last, foot)   # still shifting after 20 frames: take what we have
		return
	push_warning("ChassisHologram '%s': nothing measurable in %s, left at its own origin." % [
		name, frame.id if frame != null else &"?"])


func _stand_on(body: Node3D, box: AABB, foot: float) -> void:
	# No colliders to stand on (a display-only frame): the bottom of the mesh
	# goes on the pad instead, which is at least never inside it.
	body.position.y = foot if foot > 0.01 else -box.position.y
	var top: float = box.position.y + body.position.y + box.size.y
	_skin.set_shader_parameter("base_y", model_root.global_position.y)
	_skin.set_shader_parameter("span", maxf(top, 0.5))
	# The plate rides above whatever is in the bay, so a Leaper is not labelled
	# from three metres up and a Rover does not wear its own name.
	var head: float = model_root.position.y + top
	if name_label != null:
		name_label.position.y = head + 0.85
	if facts_label != null:
		facts_label.position.y = head + 0.50


# Everything the bay will actually draw, in `body` space. Measured through the
# LOCAL transforms rather than global ones: model_root is turning, and an AABB
# rotated into the world and back is a hair different every frame, so a
# measurement taken that way never reads as settled.
func _bounds(body: Node3D) -> AABB:
	var box := AABB()
	var any := false
	for piece in _pieces(body, Transform3D.IDENTITY):
		var here: AABB = (piece[0] as Transform3D) * (piece[1] as AABB)
		if here.size == Vector3.ZERO:
			continue
		box = here if not any else box.merge(here)
		any = true
	return box


# [transform in `body` space, own AABB] for every mesh that will be drawn.
func _pieces(node: Node, at: Transform3D) -> Array:
	var out := []
	for child in node.get_children():
		var here := at
		if child is Node3D:
			here = at * (child as Node3D).transform
		if child is VisualInstance3D and (child as VisualInstance3D).is_visible_in_tree():
			out.append([here, (child as VisualInstance3D).get_aabb()])
		out.append_array(_pieces(child, here))
	return out


# Everything that is not a shape goes; what is left keeps its mesh and wears
# the hologram skin. Walked top down, and a node that is dropped takes its
# children with it, so its subtree is never visited.
func _strip(node: Node) -> void:
	for group in node.get_groups():
		node.remove_from_group(group)   # "enemies", on the soldier chassis
	if node.get_script() != null:
		node.set_script(null)
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = _skin
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		if _DROP.has(child.get_class()):
			node.remove_child(child)
			child.free()
			continue
		_strip(child)


func _relabel(def: ChassisDefinition) -> void:
	if name_label != null:
		name_label.text = def.display_name.to_upper() if def != null else "EMPTY BAY"
	if facts_label == null:
		return
	if def == null:
		facts_label.text = ""
		return
	# ASCII only. The project font is DS-Digital, which has no middle dot.
	var facts := PackedStringArray()
	var locked: MissionDefinition = _locked_by(def)
	if locked != null:
		facts.append("LOCKED > CLEAR %s" % locked.display_name.to_upper())
	else:
		facts.append("%d RES" % def.cost)
	facts.append("%d HP" % def.base_health)
	if def.weapon_slots > 0:
		facts.append("%d GUN" % def.weapon_slots)
	else:
		facts.append(def.built_in.to_upper())
	facts.append("%d KIT" % def.equipment_slots)
	facts.append("%d MOD" % def.module_slots)
	if def.supply > 1:
		facts.append("%d SEATS" % def.supply)
	facts_label.text = " | ".join(facts)


func _show_empty() -> void:
	if name_label != null:
		name_label.text = "BAY OFFLINE"
	if facts_label != null:
		facts_label.text = ""
	if glow != null:
		glow.light_energy = 0.0


func _locked_by(def: ChassisDefinition) -> MissionDefinition:
	if def == null:
		return null
	var campaign := get_tree().get_first_node_in_group("campaign")
	if campaign == null or not campaign.has_method("locked_by"):
		return null
	return campaign.locked_by(def.id)
