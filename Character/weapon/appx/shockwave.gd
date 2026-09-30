extends Node3D

# ─────────────────────────────────────────────
# SHOCKWAVE — the edge of a blast, drawn: a ring of dust that runs out along
# the ground to exactly as far as the blast reaches, a bubble of bent air
# around the bang, and a flash.
#
# THE RING IS THE LETHAL RADIUS. Under an Explosion it measures that blast's
# damage sphere — as widened for this round by whatever fired it (see
# AIGrenadeProjectile._widen) — so what runs out along the ground is exactly
# what hurt. Anywhere else it uses `radius`.
#
# No particles: two meshes with materials of their own and a light, eased by
# one tween and freed with it. Nothing is left running per frame, and nothing
# goes near the GPU particle path that crashed the NVIDIA driver (see
# signal_arc.gd).
# ─────────────────────────────────────────────

const _RING := preload("res://Character/weapon/appx/shock_ring.gdshader")
const _BUBBLE := preload("res://Character/weapon/appx/shock_bubble.gdshader")
## Further below the blast than this, it went off in the air or against a wall:
## no ground near enough to run a ring along.
const GROUND_REACH := 1.5

## How far the ring runs with no blast to measure.
@export var radius: float = 3.0
## Seconds for the ring to run out and fade.
@export var ring_time: float = 0.45
## Seconds for the bubble of air.
@export var bubble_time: float = 0.22
## The bubble at its biggest, as a fraction of the ring's reach.
@export var bubble_reach: float = 0.5
@export var flash_energy: float = 6.0
@export var flash_colour: Color = Color(1.0, 0.72, 0.45)
@export var flash_time: float = 0.22


func _ready() -> void:
	# Built a frame late on purpose. The projectile adds its blast to the level
	# and only THEN moves it to where it went off, so inside that add_child
	# this is still sitting at the level's origin.
	_start.call_deferred()


func _start() -> void:
	var reach := _blast_radius()
	var tween := create_tween().set_parallel(true)

	var ground := _ground_under(global_position)
	if not ground.is_empty():
		var normal: Vector3 = ground.normal
		var pivot := Node3D.new()
		add_child(pivot)
		# Lifted off the surface so it never fights the ground for the pixel.
		pivot.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, normal)),
			ground.position + normal * 0.08)
		var ring := _mesh(PlaneMesh.new(), _RING)   # 2x2: scale IS its radius
		pivot.add_child(ring)
		ring.scale = Vector3.ONE * reach * 0.15
		tween.tween_property(ring, "scale", Vector3.ONE * reach, ring_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_method(_fade.bind(ring), 0.0, 1.0, ring_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var bubble := _mesh(sphere, _BUBBLE)
	add_child(bubble)
	bubble.scale = Vector3.ONE * 0.3
	tween.tween_property(bubble, "scale", Vector3.ONE * reach * bubble_reach, bubble_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_fade.bind(bubble), 0.0, 1.0, bubble_time)

	var flash := OmniLight3D.new()
	flash.light_color = flash_colour
	flash.light_energy = flash_energy
	flash.omni_range = reach * 2.2
	add_child(flash)
	tween.tween_property(flash, "light_energy", 0.0, flash_time).set_ease(Tween.EASE_OUT)

	tween.chain().tween_callback(queue_free)


# How far through its life a mesh is, for its shader. A method rather than a
# tweened "shader_parameter/life": a ShaderMaterial only lists a parameter as
# a property once it has been set, so tween_property could not find it.
func _fade(life: float, m: MeshInstance3D) -> void:
	(m.material_override as ShaderMaterial).set_shader_parameter(&"life", life)


# A mesh with a material of its OWN: the tween fades this blast's, and a
# material shared through the scene would fade every blast in the level at once.
func _mesh(mesh: Mesh, shader: Shader) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = shader
	m.material_override = mat
	return m


# The damage sphere of the Explosion this sits under.
func _blast_radius() -> float:
	var area = get_parent().get("damage_area") if get_parent() != null else null
	if area is Area3D:
		for child in (area as Area3D).get_children():
			var shape := child as CollisionShape3D
			if shape != null and shape.shape is SphereShape3D:
				return (shape.shape as SphereShape3D).radius
	return radius   # not under a blast with a damage sphere: the export decides


# The ground straight under `at`, through anybody standing in the blast: a
# ring laid over a robot's head is not on the ground.
func _ground_under(at: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * GROUND_REACH)
	var skip: Array[RID] = []
	for _i in 4:
		q.exclude = skip
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or not (hit.collider is CharacterBody3D or hit.collider is RigidBody3D):
			return hit
		skip.append(hit.rid)   # a robot, or the spent round itself: look past it
	return {}   # a crowd four deep over the spot: no ring rather than one on a head
