extends Area3D

# ─────────────────────────────────────────────
# JAMMER — a piece of ground where the signal layer does not work.
#
# WHAT IT IS FOR. Every other threat in this game is answered by shooting it.
# A dead zone cannot be: standing in it does not hurt you, it takes away the
# thing you ARE. You keep your gun and lose your squad, your contact marks and
# your roster — the whole command layer the game is built on — for exactly as
# long as you choose to be in there.
#
# AND IT IS A CHOICE, which is why the volume is visible from outside. A
# jammer you discover by losing your squad is a trap you learn once. A jammer
# you can see from the ridge is a question: go round it, push through it fast,
# or find the emitter and kill it.
#
# IT IS NOT YOURS ALONE. Every robot on both sides runs the same signal rules
# (see AI.SIGNAL_*), so a dead zone degrades the garrison standing in it as
# much as it degrades you. That is the interesting case, not an oversight:
# the enemy's own jammer is cover you can fight inside, if you are willing to
# fight without a squad while they fight without accuracy.
#
# HOW IT TALKS TO TRANSMITTING. A transmission out of a dead zone is a
# transmission into a wall — and a player who cannot be heard also cannot be
# located. Not wired up yet; see SquadCommander._transmit.
#
# BUILT FROM TWO NUMBERS. radius and height make the collision shape and the
# shell, so placing one is placing one node and typing two figures. Nothing to
# keep in step by hand, which is the failure mode every hand-built trigger
# volume in this project has eventually hit.
# ─────────────────────────────────────────────

const _SHELL := preload("res://Env/world_objects/jammer_field.gdshader")

@export_group("Shape")
@export var radius: float = 22.0
@export var height: float = 14.0

@export_group("Jamming")
## Integrity eaten per second while inside. 0.30 walks a clean signal down
## through FUZZED, DEGRADED and CRITICAL to the e-kill floor in about three
## seconds — long enough to turn round in, short enough to mean it.
@export var drain_per_second: float = 0.30
## How far down it can push anything. The default is the floor: a jammer takes
## the command layer away completely. Raise it for a zone that only fuzzes.
@export var floor_integrity: float = 0.0
## Held down rather than left to recover, so the climb back only starts when
## you are out. Refreshed every tick while inside.
@export var hold_seconds: float = 0.8
## Off means the volume is inert — the emitter is dead, or it has not switched
## on yet. The shell goes with it.
@export var active: bool = true

@export_group("Look")
@export var tint: Color = Color(0.69, 0.20, 0.47)

var _shell: MeshInstance3D = null
var _mat: ShaderMaterial = null


func _ready() -> void:
	monitoring = true
	# Everything with a signal is a body — robots and the player alike.
	collision_mask = 0xFFFFFFFF
	_build_shape()
	_build_shell()
	set_physics_process(true)


func _build_shape() -> void:
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	var col := CollisionShape3D.new()
	col.shape = cyl
	# The volume sits ON the ground: the node goes at the emitter's feet and
	# the cylinder is lifted half its height, rather than the designer having
	# to remember to float the node.
	col.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(col)


func _build_shell() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	# Open ends. A capped cylinder seen from inside is a ceiling, and this is
	# meant to read as a wall you are standing in the middle of.
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 48
	_shell = MeshInstance3D.new()
	_shell.mesh = cyl
	_shell.position = Vector3(0.0, height * 0.5, 0.0)
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = _SHELL
	_mat.set_shader_parameter(&"tint", tint)
	_shell.material_override = _mat
	_shell.visible = active
	add_child(_shell)


## Switch the emitter off — or back on. The shell follows, because a dead
## jammer that still glows is the worst possible lie to tell the player.
func set_active(on: bool) -> void:
	active = on
	if _shell != null and is_instance_valid(_shell):
		_shell.visible = on


func _physics_process(delta: float) -> void:
	if not active:
		return   # emitter down or not yet switched on: the volume does nothing
	for body in get_overlapping_bodies():
		if body == null or not is_instance_valid(body):
			continue
		if not body.has_method("receive_signal_damage"):
			continue   # no signal to take: scenery, a crate, a spent round
		# FLOORED, not driven to zero regardless. A zone tuned to merely fuzz
		# should not creep past its own floor just because you stood in it
		# longer, and the check has to be here rather than after the damage —
		# receive_signal_damage has no idea what this volume's floor is.
		var now: float = float(body.signal_integrity)
		if now <= floor_integrity:
			body.lock_signal(hold_seconds)
			continue
		var bite: float = minf(drain_per_second * delta, now - floor_integrity)
		body.receive_signal_damage(bite, self)
		# Held, so passive recovery does not fight the drain tick for tick.
		# Without this a 0.04/s climb cancels an eighth of the bite every
		# frame and the floor is never quite reached.
		body.lock_signal(hold_seconds)
