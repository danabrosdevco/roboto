extends Node3D
class_name TransmitPing

# ─────────────────────────────────────────────
# TRANSMITTING MAKES YOU LOUD.
#
# Every order the player gives is a radio transmission, and a transmission is
# the loudest thing on a battlefield full of machines that do nothing but
# listen. This is that transmission, made visible: a wavefront that leaves
# your position and runs out across the ground at a speed you can watch, and
# that tells anything with a receiver roughly where you are as it passes.
#
# WHY THIS IS THE RIGHT COST TO CHARGE. The game's verb is command. Charging
# for movement or for shooting would be charging for something every shooter
# charges for; charging for ORDERS makes the thing that is uniquely this game
# the thing that is uniquely dangerous. You stop spamming the dial. You batch
# your orders. You give them from a position you are about to leave, and you
# learn to kill the listening posts before you start talking.
#
# IT IS NOT A SOUND. Suppressing it is not about being quiet — it is about
# emitting less, or emitting from somewhere you are not. Everything downstream
# of that (relays, decoys, a squadmate who repeats for you) is a mechanic this
# makes possible, and none of it is built yet.
#
# THE FRONT TRAVELS. A receiver 40 m out learns about you later than one at
# 10 m, which is most of the tension: you can see the ring reaching for the
# hill before whatever is on the hill reacts to it.
# ─────────────────────────────────────────────

const _RING := preload("res://Character/components/transmit_ring.gdshader")
## How far below the origin to look for ground to run the ring along. Same
## reach as the shockwave's: further than this and the transmission went out
## from something standing in the air.
const GROUND_REACH: float = 2.5

## Metres the front runs out to.
var radius: float = 45.0
## Seconds it takes to get there. Deliberately slow enough to watch — this is
## not a blast, it is a thing arriving at people.
var travel: float = 0.9
## Signal cyan by default: this is the player's own carrier.
var colour: Color = Color(0.40, 0.78, 0.95)

var _ring: MeshInstance3D = null
## Set by aim(). Zero heading means the wave is a circle.
var _heading: Vector2 = Vector2.ZERO
var _cone_cos: float = -1.0
## How much an aimed front stops being an arc of a circle. See the shader.
## 0.85 rather than 1.0: a dead-straight front reads as a wall sliding at you,
## and a little residual curve keeps it reading as something radiating from a
## transmitter that happens to be pointed.
const AIM_FLATTEN: float = 0.85


## Put this transmission into the world at `origin`. `host` is whatever should
## own it — the level, normally, not the player: a ring parented to a body that
## then walks away drags its own wavefront along with it.
##
## AN INSTANCE METHOD RATHER THAN A STATIC FACTORY, and callers preload this
## script rather than naming the class. `class_name` only enters the global
## class list when the EDITOR scans the file, and this project's checks and
## headless runs happen with the editor untouched — a brand new class_name
## does not resolve in either until someone opens Godot. Preloading the path
## works the moment the file exists.
func fire(host: Node, origin: Vector3, reach: float,
		tint: Color = Color(0.40, 0.78, 0.95), seconds: float = 0.9) -> Node3D:
	if host == null or not is_instance_valid(host):
		push_warning("TransmitPing.fire: no host to put the transmission in, so nothing is drawn. The order still went out.")
		queue_free()
		return null
	radius = maxf(reach, 1.0)
	travel = maxf(seconds, 0.05)
	colour = tint
	host.add_child(self)
	global_position = origin
	return self


func _ready() -> void:
	# A frame late, exactly as shockwave.gd does it: `fire` sets our position
	# AFTER add_child, so inside _ready we are still at the host's origin and a
	# ring built here would be laid out in the wrong place.
	_start.call_deferred()


func _start() -> void:
	var ground := _ground_under(global_position)
	if ground.is_empty():
		# Nothing underneath — transmitted from a rooftop edge, or mid-fall.
		# No ring rather than one floating at knee height over a drop.
		push_warning("TransmitPing: no ground within %.1f m of the transmitter, so the wavefront is not drawn. The transmission itself still happened." % GROUND_REACH)
		queue_free()
		return

	# ALWAYS FLAT. This used to bank the quad to the ground's normal, the way
	# shockwave.gd does — which is right for dust, because dust lies on the
	# slope it landed on. It is wrong for this, and badly so: a transmission's
	# footprint is a horizontal circle whatever the floor happens to be doing
	# underneath it.
	#
	# And the failure is ugly rather than subtle. Indoors the ray lands on a
	# ramp, a kerb or a raised slab, the 45 m quad tips with it, and what the
	# player gets is a bright band running corner to corner across the screen.
	# Seen in the depot.
	#
	# The ray is still worth casting — it is what puts the ring at FLOOR
	# height rather than at the transmitter's waist. Only the normal is
	# discarded.
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.global_transform = Transform3D(Basis(), ground.position + Vector3.UP * 0.10)

	_ring = MeshInstance3D.new()
	_ring.mesh = PlaneMesh.new()   # 2x2, so scale IS the reach
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Its OWN material. A shared one would fade every transmission on the map
	# together — the bug shockwave.gd's comment already warns about.
	var mat := ShaderMaterial.new()
	mat.shader = _RING
	mat.set_shader_parameter(&"wave", colour)
	mat.set_shader_parameter(&"life", 0.0)
	_ring.material_override = mat
	pivot.add_child(_ring)

	_ring.scale = Vector3.ONE * radius * 0.04
	# aim() may have been called before the ring existed -- fire() returns
	# immediately and this runs a frame later.
	_apply_aim()
	var tween := create_tween().set_parallel(true)
	# LINEAR, unlike the shockwave's eased expansion. A blast decelerates; a
	# radio wave does not, and the constant speed is what lets the player read
	# "it will reach that ridge in about a second".
	tween.tween_property(_ring, "scale", Vector3.ONE * radius, travel)
	tween.tween_method(_fade, 0.0, 1.0, travel * 1.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


## Point this transmission somewhere: it goes out as a lobe along `dir`
## rather than as a circle. Call it any time after fire(); the ring is built a
## frame late, so the values are stashed and applied when it exists.
##
## `dir` is a WORLD direction and is flattened here. The quad lies in the
## world XZ plane with an identity basis (see _start), so world X and Z map
## straight onto the plane's own axes and no basis maths is needed — which is
## the second reason not to bank the ring to the ground normal.
func aim(dir: Vector3, cone_degrees: float) -> void:
	var flat := Vector2(dir.x, dir.z)
	if flat.length() < 0.001:
		push_warning("TransmitPing.aim: no bearing in that direction, so the wave stays a circle.")
		return
	_heading = flat.normalized()
	_cone_cos = cos(deg_to_rad(clampf(cone_degrees, 1.0, 360.0) * 0.5))
	_apply_aim()


func _apply_aim() -> void:
	if _ring == null or not is_instance_valid(_ring):
		return   # built a frame late; _start calls this again once it exists
	var mat := _ring.material_override as ShaderMaterial
	mat.set_shader_parameter(&"heading", _heading)
	mat.set_shader_parameter(&"cone_cos", _cone_cos)
	mat.set_shader_parameter(&"flatten", AIM_FLATTEN if _heading != Vector2.ZERO else 0.0)


## Hand each node to `cb` at the moment the front reaches it.
##
## ON THIS NODE'S OWN TWEEN, not a SceneTree timer. A timer outlives whatever
## scheduled it and fires into a torn-down tree at level exit; a tween owned by
## this node is freed with it and its pending callbacks go quietly. Same trap
## the signal arcs hit.
func notify_as_front_arrives(nodes: Array, cb: Callable) -> void:
	if nodes.is_empty():
		return
	var tween := create_tween().set_parallel(true)
	for n in nodes:
		if n == null or not is_instance_valid(n) or not (n is Node3D):
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		var at: float = clampf(d / maxf(radius, 0.01), 0.0, 1.0) * travel
		tween.tween_callback(cb.bind(n)).set_delay(at)


func _fade(life: float) -> void:
	if _ring == null or not is_instance_valid(_ring):
		return
	(_ring.material_override as ShaderMaterial).set_shader_parameter(&"life", life)


# The ground straight under `at`, looking past anybody standing on the spot —
# a transmission from inside a huddle must not lay its ring on a squadmate's
# head. Lifted from shockwave.gd, which solved this first.
func _ground_under(at: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5,
		at + Vector3.DOWN * GROUND_REACH)
	var skip: Array[RID] = []
	for _i in 4:
		q.exclude = skip
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or not (hit.collider is CharacterBody3D or hit.collider is RigidBody3D):
			return hit
		skip.append(hit.rid)
	return {}
