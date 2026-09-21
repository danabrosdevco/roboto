extends Node3D
class_name SignalArc

# ─────────────────────────────────────────────
# SIGNAL ARC — what a robot losing its signal looks like.
#
# Electricity spitting off the chassis: short, fast, blue-white, gone. NOT the
# mechanic's welding sparks and NOT the reclaimer's grinder — those are work
# being done and they read as orange and continuous. This is something failing,
# so it is cold, it is in the HUD's own SIGNAL blue, and each arc lives about a
# fifth of a second.
#
# IT CRACKLES. How degraded a robot is shows as how OFTEN it spits, not how
# much: a short burst, then a gap, and the gap closes as the signal dies until
# at E-KILL it never stops. A fading constant stream looked like a robot that
# was slightly on fire.
#
# CPU PARTICLES, AND THAT IS NOT A PREFERENCE. The first version used
# GPUParticles3D and it crashed the NVIDIA OpenGL driver — nvoglv64.dll, the
# same offset every time — in the Foundry, the moment an EMP put a handful of
# robots into the arc band in one frame. The Compatibility renderer does GPU
# particles through transform-feedback buffers, which is exactly where driver
# crashes like that live, and it never happened in two weeks of play before this
# effect existed. CPUParticles3D simulates on the CPU and draws with an ordinary
# instanced mesh: no particle buffers on the GPU at all. Twenty-odd sparks a
# robot cost nothing to simulate. Do not "upgrade" this back.
#
# Built in code, no authored art, the mesh and its material shared by every arc
# in the level. Enemy makes one the first time a robot's signal drops and only
# ever dims it after that — see Enemy._tick_signal_vfx.
# ─────────────────────────────────────────────

## HUDPalette.SIGNAL. The colour the HUD already uses for signal integrity, so
## a player who has read a squad bar knows what the sparks mean.
const ARC_COLOUR := Color(0.40, 0.78, 0.95)
const CORE_COLOUR := Color(0.88, 0.97, 1.0)

## How long one crackle spits for.
const CRACKLE := 0.12
## The gap between crackles just past FUZZED. It closes to nothing by E-KILL.
const MAX_GAP := 1.1

@export var body_height: float = 1.6
@export var body_radius: float = 0.45

# One quad and one fade for every arc in the level.
static var _quad: QuadMesh = null
static var _fade: Curve = null

var _particles: CPUParticles3D
var _intensity: float = 0.0
var _clock: float = 0.0


## Called every physics frame while the robot is degraded. 0 is a clean signal,
## 1 is dead.
func tick(delta: float, value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	if _particles == null:
		return
	if _intensity <= 0.01:
		_particles.emitting = false
		return
	# Burst, gap, burst. The gap shrinks with degradation; at the top it is gone.
	var gap: float = lerpf(MAX_GAP, 0.0, _intensity)
	_clock += delta
	if _clock >= CRACKLE + gap:
		_clock = 0.0
	_particles.emitting = _clock < CRACKLE or gap <= 0.02


## Stops it. The sparks already in the air finish their fifth of a second.
func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	if _particles != null and _intensity <= 0.01:
		_particles.emitting = false


func _ready() -> void:
	_particles = CPUParticles3D.new()
	_particles.amount = 22
	_particles.lifetime = 0.22
	_particles.explosiveness = 0.35
	_particles.randomness = 0.85
	_particles.local_coords = false   # arcs stay where they were thrown
	_particles.emitting = false
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_particles.emission_box_extents = Vector3(body_radius, body_height * 0.5, body_radius)
	# Outward and a little up: an arc jumps off the plating, it does not fall
	# out of it.
	_particles.direction = Vector3(0, 0.35, 0)
	_particles.spread = 180.0
	_particles.initial_velocity_min = 2.4
	_particles.initial_velocity_max = 6.5
	# Hard damping is what makes it read as electrical rather than as debris:
	# it leaps, then stops dead instead of arcing over.
	_particles.damping_min = 14.0
	_particles.damping_max = 26.0
	_particles.gravity = Vector3(0, -2.0, 0)
	_particles.scale_amount_min = 0.5
	_particles.scale_amount_max = 1.4
	_particles.scale_amount_curve = _shared_fade()
	_particles.color = ARC_COLOUR
	_particles.mesh = _shared_quad()
	add_child(_particles)


static func _shared_fade() -> Curve:
	if _fade == null:
		_fade = Curve.new()
		_fade.add_point(Vector2(0.0, 1.0))
		_fade.add_point(Vector2(0.35, 0.9))
		_fade.add_point(Vector2(1.0, 0.0))
	return _fade


# A tiny quad, unshaded and additive, so a dozen of them stack into a flicker
# instead of into a wall of blue.
static func _shared_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(0.075, 0.075)
		var draw := StandardMaterial3D.new()
		draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		draw.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		draw.vertex_color_use_as_albedo = true
		draw.albedo_color = CORE_COLOUR
		draw.disable_receive_shadows = true
		_quad.material = draw
	return _quad
