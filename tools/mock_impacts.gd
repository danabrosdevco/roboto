extends SceneTree

# ─────────────────────────────────────────────
# MOCK IMPACTS — rendered proposals for THE LIFE OF A ROUND: the tracer that
# carries it and the impact that ends it.
#
# The two are one system and are budgeted in one ledger, because they are fed
# by the same event at the same rate. A tracer is the worse of the two for
# performance: an impact is a one-shot and a round in flight persists over
# frames.
#
# Nothing in the game is touched. Every effect in here is built at runtime by
# this tool, in a real level, so the pictures are of this game's lighting and
# this game's screen filter rather than of a sandbox.
#
#   MODE=survey  godot --headless --path . --script res://tools/mock_impacts.gd -- --no-save
#   MODE=bench   godot --headless --path . --script res://tools/mock_impacts.gd -- --no-save
#   MODE=rates   godot --headless --path . --script res://tools/mock_impacts.gd -- --no-save
#   RENDER_OUT="D:/Godot Games/roboto/docs/concepts" \
#       godot --path . --audio-driver Dummy --script res://tools/mock_impacts.gd -- --no-save
#
#   ONLY=sparks       one shot, by substring of its name
#   NOFILTER=1        same cameras with the signal filter OFF, suffixed _raw
#   FREEZE=0.25       hold every effect at 25% of its life (see THE FREEZE)
#
# MODE=shots (the default) REFUSES --headless, because the dummy renderer
# returns blank textures and the signal filter READS THE SCREEN — a headless
# render comes back flat and looks like proof. survey, bench and rates are
# headless on purpose: they touch no pixels.
#
# ── THE FREEZE ───────────────────────────────
# An impact lives a fifth of a second and a tracer under a second. A still of
# either is a still of nothing unless the clock is stopped, so every channel's
# age is driven by one number this tool can pin — the same hatch
# core_pulse.gd opens with CORE_PHASE so a still can photograph a pulsing core.
# FREEZE=0.0 is the instant of the shot, 1.0 the moment it is recycled.
#
# ── WHY IT IS ALL ONE FILE ───────────────────
# This is a proposal, not a feature. The pooled field, the shaders, the bucket
# test, the tracer vocabulary and the cameras are all in here so the human can
# read the whole argument in one place, run it, and then decide what earns a
# home in Character/. If it does, ImpactField moves to Character/weapon/ as its
# own scene and this tool keeps only the cameras.
# ─────────────────────────────────────────────

const WIDTH := 1152
const HEIGHT := 648
const HUD_SCENE := "res://Character/hud/hud.tscn"
const FILTER_NODE := "SignalFilter"
## The game's eye height. 1.50, not the 1.65 some older shot tools use.
const EYE := 1.50


# ═════════════════════════════════════════════
# WHAT THE SURFACE IS — the three buckets.
#
# The cheap version of material awareness, and the whole reason it is cheap:
# the decision is made from WHAT THE COLLIDER ALREADY IS, which the raycast has
# already handed over. No material lookup, no texture name, no second query.
#
#   ROBOT    the round connected with something that takes damage.
#            hud_weapon_template._one_round ALREADY knows this — it keeps the
#            victim in _struck_this_shot to score the suppression bonus. The
#            test is `struck != null` and it costs nothing whatsoever.
#   TERRAIN  GeneratedTerrain.
#   BRUSH    everything else, which in practice means FuncGodot brush geometry:
#            a StaticBody3D called entity_N_worldspawn or entity_N_func_detail.
#
# ── THE WALK UP IS TWO LEVELS, NOT ONE, AND THAT WAS MEASURED ──
# The first version of this tested the collider and its parent, which looked
# obviously sufficient from reading generated_terrain.gd:378 — _build_collision
# adds a StaticBody3D called "Collision" and the group is joined in _ready.
# It is wrong. _build_all puts everything under an intermediate holder called
# "_Built" (generated_terrain.gd:346), so the real chain is
#
#     GeneratedTerrain("terrain")  ->  _Built  ->  Collision(StaticBody3D)
#
# and a one-level walk calls the Salient's entire ground BRUSH. MODE=survey
# caught it; reading the file did not.
#
# ── SO IT IS MEMOISED, which makes the depth question moot ──
# A level has a HANDFUL of distinct colliders — the survey finds ONE in the
# proving ground and TWO in the Salient — so after the first round into each,
# the bucket is a dictionary hit. That is what makes this genuinely cheap: not
# the shortness of the walk, but the fact that it almost never runs.
#
# WHAT THIS GETS WRONG, said plainly. A level whose ground is brushwork rather
# than GeneratedTerrain — the proving ground is exactly that, its floor is a
# brush textured Dirt_04 — lands in BRUSH and gets chips where it wants dust.
# Mud and metal in one bucket is the price of not looking at the material.
# ═════════════════════════════════════════════

enum Bucket { ROBOT, TERRAIN, BRUSH }

const BUCKET_NAMES := ["robot", "terrain", "brush"]

## collider instance id -> bucket, for everything that is not a robot. Static
## so the cache survives the weapon that asked; cleared on level change.
static var _bucket_cache: Dictionary = {}
## How the cache is doing, for the bench. Not read by anything else.
static var bucket_lookups := 0
static var bucket_misses := 0


static func clear_bucket_cache() -> void:
	_bucket_cache.clear()
	bucket_lookups = 0
	bucket_misses = 0


## Which bucket a hit belongs in. `struck` is the body the round damaged, or
## null — the caller already has it.
static func bucket_of(collider: Object, struck: Node) -> int:
	if struck != null:
		return Bucket.ROBOT   # free: the weapon already worked this out
	var n := collider as Node
	if n == null:
		return Bucket.BRUSH
	bucket_lookups += 1
	var id: int = n.get_instance_id()
	var cached: Variant = _bucket_cache.get(id)
	if cached != null:
		return int(cached)
	bucket_misses += 1
	var b: int = Bucket.BRUSH
	# Bounded at three, which covers GeneratedTerrain -> _Built -> Collision
	# with one to spare. Unbounded would be a walk to the scene root on every
	# miss, and a miss happens once per collider per level.
	var walk: Node = n
	for _i in 3:
		if walk == null:
			break
		if walk.is_in_group(&"terrain"):
			b = Bucket.TERRAIN
			break
		walk = walk.get_parent()
	_bucket_cache[id] = b
	return b


# ═════════════════════════════════════════════
# THE TRACER VOCABULARY
#
# A tracer is INFORMATION. The player should be able to say what is shooting at
# them from the shape alone, without looking at the shooter — and today they
# cannot, because every weapon in the game fires the same streak. tracer.gd
# already split the COLOUR two ways (incoming red, outgoing yellow-white) for
# exactly this reason and stopped there.
#
# ── THE CLASSES ARE THE GAME'S, NOT A GUESS ──
# Read out of Character/weapon/ai-wep_*.tscn. fire_cooldown is the INTERVAL
# INSIDE A BURST (enemy.gd:3059 re-arms fire_time from it per round), so it is
# the cadence, and that is what decides whether a burst reads as a chain or as
# separate rounds:
#
#   squad automatic   cd 0.11   18 dmg   burst 10-?   85 m
#   machine gun       cd 0.13   15 dmg   burst 8-16   99 m
#   heavy MG          cd 0.12   22 dmg   burst 14-26  105 m
#   M4 / rifle        cd 0.35   30 dmg   no burst     80 m
#   pistol            cd 0.55   24 dmg   no burst     35 m
#   shotgun           cd 0.90   70 dmg   9 pellets    45 m
#   autocannon        cd 0.50   60 dmg   burst 3      120 m
#   light cannon      cd 1.60   48 dmg   burst 1      85 m
#   marksman          cd 1.90   48 dmg   burst 1      130 m
#   bolt              cd 0.80   62 dmg   burst 1      100 m
#   recoilless        cd 4.50  110 dmg   projectile 34 m/s
#   rocket pods       cd 0.50   55 dmg   projectile 32 m/s
#
# ── THE AUTOCANNON IS NOT THE BEADED CHAIN ──
# The brief guessed it would be. The table says otherwise: the autocannon
# fires THREE rounds half a second apart and hits for 60 — that is a thumper,
# and it wants the single solid heavy streak. The rapid-fire weapons in this
# game are the squad automatic, the machine gun and the heavy MG at 0.11-0.13,
# and they are the chain. Named by the data rather than by the name.
# ═════════════════════════════════════════════

## name, speed m/s, length m, calibre m (cross-section), bead period m
## (0 = solid), duty (lit fraction of the period), head flare m, body colour,
## head colour, smoke.
const TRACER_SPECS: Array = [
	["small_arms", 150.0, 2.6, 0.030, 0.0, 1.0, 0.10, Color(1.00, 0.86, 0.34), Color(1.00, 0.99, 0.90), 0.0],
	["rapid", 95.0, 1.8, 0.040, 0.0, 1.0, 0.12, Color(1.00, 0.78, 0.22), Color(1.00, 0.98, 0.88), 0.0],
	["heavy_mg", 120.0, 4.0, 0.065, 0.0, 1.0, 0.22, Color(1.00, 0.62, 0.14), Color(1.00, 0.95, 0.80), 0.0],
	["autocannon", 170.0, 8.0, 0.110, 0.0, 1.0, 0.40, Color(1.00, 0.52, 0.10), Color(1.00, 0.94, 0.78), 0.35],
	["cannon", 190.0, 13.0, 0.170, 0.0, 1.0, 0.60, Color(1.00, 0.44, 0.08), Color(1.00, 0.96, 0.86), 0.80],
	# The authored comparison: the same rapid round with a dash pattern baked
	# into one long streak instead of several short ones in flight.
	["beaded_authored", 95.0, 10.0, 0.045, 1.10, 0.40, 0.14, Color(1.00, 0.78, 0.22), Color(1.00, 0.98, 0.88), 0.0],
	# Not a tracer at all. A motor and a column, visibly slower than anything
	# that is a bullet, so "that is a rocket, move" is legible from the shape.
	["rocket", 34.0, 1.3, 0.140, 0.0, 1.0, 0.30, Color(1.00, 0.70, 0.30), Color(1.00, 0.98, 0.92), 2.40],
	# ── TOOL ONLY, from here down. Five rows identical in every respect
	# except CROSS-SECTION, for the thickness ladder. They are in the same
	# table because the channel machinery is per-spec, and they are at the end
	# because SHIPPING_SPECS counts only what is above them — the bench must
	# not bill the game for pools that exist to answer a question.
	["ladder_02", 120.0, 3.4, 0.020, 0.0, 1.0, 0.60, Color(1.00, 0.62, 0.14), Color(1.00, 0.95, 0.80), 0.0],
	["ladder_05", 120.0, 3.4, 0.050, 0.0, 1.0, 0.60, Color(1.00, 0.62, 0.14), Color(1.00, 0.95, 0.80), 0.0],
	["ladder_10", 120.0, 3.4, 0.100, 0.0, 1.0, 0.60, Color(1.00, 0.62, 0.14), Color(1.00, 0.95, 0.80), 0.0],
	["ladder_20", 120.0, 3.4, 0.200, 0.0, 1.0, 0.60, Color(1.00, 0.62, 0.14), Color(1.00, 0.95, 0.80), 0.0],
	["ladder_40", 120.0, 3.4, 0.400, 0.0, 1.0, 0.60, Color(1.00, 0.62, 0.14), Color(1.00, 0.95, 0.80), 0.0],
	# The soft-edged pair, for shot 27. Same widths as two of the hard rows,
	# with the cross-section faded out instead of cut off — see SOFT BEATS
	# THICK in the tracer shader.
	["soft_05", 120.0, 3.4, 0.050, 0.0, 1.0, 0.60, Color(1.00, 0.62, 0.14), Color(1.00, 0.95, 0.80), 0.0],
	["soft_15", 120.0, 3.4, 0.150, 0.0, 1.0, 0.60, Color(1.00, 0.62, 0.14), Color(1.00, 0.95, 0.80), 0.0],
]

## The two soft-edged rows, which the tracer shader treats differently.
const SOFT_FIRST := 12

## How many of TRACER_SPECS would actually ship. The rest are tool-only.
const SHIPPING_SPECS := 7
## Where the ladder rows start in TRACER_SPECS.
const LADDER_FIRST := 7

const SPEC_NAMES := ["small_arms", "rapid", "heavy_mg", "autocannon", "cannon", "beaded_authored", "rocket"]

## Which spec each weapon class uses, and the cadence it fires at. Used by
## MODE=rates and by the vocabulary sheet so a row is fired at its real rate.
const WEAPON_CLASSES: Array = [
	# label, spec, fire_cooldown, rounds per burst (typical)
	["squad automatic 0.11s", 1, 0.11, 10],
	["machine gun 0.13s", 1, 0.13, 12],
	["heavy MG 0.12s", 2, 0.12, 20],
	["M4 rifle 0.35s", 0, 0.35, 3],
	["pistol 0.55s", 0, 0.55, 1],
	["autocannon 0.50s", 3, 0.50, 3],
	["marksman 1.90s", 4, 1.90, 1],
	["recoilless 4.50s", 6, 4.50, 1],
]


# ═════════════════════════════════════════════
# THE POOLED FIELD
#
# One node. Four impact channels and one tracer channel PER SPEC, every one a
# MultiMeshInstance3D over a fixed-size ring buffer. Nothing is allocated after
# _ready: a shot WRITES INTO SLOTS it does not own and the oldest occupant is
# overwritten. That is the whole ceiling policy — there is no queue, no cull
# pass and no "too many effects" branch, because a ring buffer cannot overflow.
#
# Built pooled from the first line rather than made nice and optimised later,
# because in this project that order does not survive contact: a robot costs
# 0.115 ms merely to exist, about 80 fit in a 60 Hz frame, the Qamareen mission
# ships 186 bodies, and mines were once 68 of 128 ms of script time.
#
# ── WHY THE TRACER CHANNEL IS SPLIT PER SPEC ──
# One MultiMesh per look, rather than one MultiMesh and a uniform array indexed
# per instance. Three reasons, in order of how much they matter: a dynamically
# indexed uniform array is the one GLSL construct this project has no other
# example of and would be the first thing to break on a driver; the per-class
# pools cannot starve each other, so a machine gun firing flat out cannot eat
# the slot a recoilless round needed; and it is seven draw calls, which against
# a 16.67 ms frame is not a cost worth arguing about.
# ═════════════════════════════════════════════

class ImpactField extends Node3D:

	# ── THE BUDGET ────────────────────────────
	# Live effects, not events.
	const PITS := 192
	const SPARKS := 480
	const CHIPS := 160
	const DUST := 128
	const SPARKS_PER := 6
	const CHIPS_PER := 2
	## Per spec. Seven specs, so 7 x 96 = 672 slots in the air at once. See
	## MODE=rates for where 96 comes from: the rapid classes need about 60 at
	## 1-in-5 across a whole Qamareen, and 96 leaves headroom before the ring
	## starts eating its own tail.
	const TRACERS := 96

	# ── LIFETIMES, seconds ────────────────────
	const PIT_LIFE := 14.0      # the only long one: a wall remembers
	const SPARK_LIFE := 0.22
	const CHIP_LIFE := 1.10
	const DUST_LIFE := 1.80
	## A tracer dies when it arrives, not on a clock. This is the cap for one
	## that was fired at nothing.
	const TRACER_LIFE := 2.50

	const GRAVITY := 16.0       # chips and sparks, m/s² — heavier than real,
	                            # because a 0.2 s arc needs to read

	var pit_mm: MultiMesh
	var spark_mm: MultiMesh
	var chip_mm: MultiMesh
	var dust_mm: MultiMesh
	## One per TRACER_SPECS row.
	var tracer_mm: Array[MultiMesh] = []
	## Cross-section multiplier per spec, for the thickness ladder. 1.0 is the
	## spec's own calibre. It exists because thickness turned out to be the
	## single thing that decides whether the signal filter renders a tracer as
	## light or as a black dash — see THE EDGE PASS EATS THIN BRIGHT THINGS.
	var cal_mul := PackedFloat32Array()

	# ── CONSTANT APPARENT WIDTH ───────────────
	#
	# The measured consequence of the edge pass. A streak narrower than about
	# six or seven SCREEN PIXELS is rendered near-black by the filter, and
	# screen pixels are a function of range — so a fixed world calibre is
	# legible at ten metres and inverted at sixty. Fixing a world width that
	# survives at sixty makes a bullet look like a pipe up close.
	#
	# So the width is solved per round, per frame, from its distance to the
	# eye: never thinner than `floor_px` pixels, never thinner than its own
	# calibre. One subtraction, one length and one max in a loop that is
	# already touching every slot.
	#
	# Set `eye` and `m_per_px_at_1m` and it engages; leave eye at ZERO and
	# every tracer keeps its authored world calibre, which is what the
	# thickness ladder needs.
	var eye: Vector3 = Vector3.ZERO
	var m_per_px_at_1m := 0.0
	var floor_px := 9.0

	## Per-slot state. Parallel arrays rather than an array of dictionaries: a
	## dictionary per live effect is an allocation per shot, which is the one
	## thing this design exists to avoid.
	var _pit_age := PackedFloat32Array()
	var _spark_age := PackedFloat32Array()
	var _spark_pos := PackedVector3Array()
	var _spark_vel := PackedVector3Array()
	var _chip_age := PackedFloat32Array()
	var _chip_pos := PackedVector3Array()
	var _chip_vel := PackedVector3Array()
	var _chip_spin := PackedVector3Array()
	var _dust_age := PackedFloat32Array()
	var _dust_pos := PackedVector3Array()
	## Tracers, one array per spec.
	var _tr_age: Array[PackedFloat32Array] = []
	var _tr_from: Array[PackedVector3Array] = []
	var _tr_dir: Array[PackedVector3Array] = []
	var _tr_range: Array[PackedFloat32Array] = []
	var _tr_next: PackedInt32Array = PackedInt32Array()

	var _pit_next := 0
	var _spark_next := 0
	var _chip_next := 0
	var _dust_next := 0

	## For the budget readout. Not used by the tick.
	var impacts := 0
	var tracers := 0
	var recycled := 0

	## When >= 0 every age is pinned and nothing advances. See THE FREEZE.
	var freeze := -1.0

	## How many TRACER_SPECS rows to build channels for. Set BEFORE the node
	## enters the tree. The default is what would ship; the shot tool raises it
	## to include the tool-only ladder rows, which must never reach the bench —
	## five extra channels the game would not have is five extra loops in the
	## tick, and the budget would be reporting a cost nobody pays.
	var spec_count := SHIPPING_SPECS


	func _ready() -> void:
		_pit_age.resize(PITS)
		_spark_age.resize(SPARKS)
		_spark_pos.resize(SPARKS)
		_spark_vel.resize(SPARKS)
		_chip_age.resize(CHIPS)
		_chip_pos.resize(CHIPS)
		_chip_vel.resize(CHIPS)
		_chip_spin.resize(CHIPS)
		_dust_age.resize(DUST)
		_dust_pos.resize(DUST)
		# -1 is "never used", so the parking pass below can put every instance
		# at zero scale once and then leave it alone.
		_pit_age.fill(-1.0)
		_spark_age.fill(-1.0)
		_chip_age.fill(-1.0)
		_dust_age.fill(-1.0)

		pit_mm = _channel(_quad(1.0), _pit_shader(), PITS, false)
		spark_mm = _channel(_box(Vector3(0.022, 0.022, 1.0)), _spark_shader(), SPARKS, false)
		chip_mm = _channel(_box(Vector3(0.055, 0.055, 0.055)), _chip_shader(), CHIPS, true)
		dust_mm = _channel(_quad(1.0), _dust_shader(), DUST, false)

		cal_mul.resize(spec_count)
		cal_mul.fill(1.0)
		_tr_next.resize(spec_count)
		for si in spec_count:
			var spec: Array = TRACER_SPECS[si]
			# A UNIT box, scaled entirely by the instance transform, so the
			# shader's local z is a clean -0.5..0.5 along the streak and the
			# dash pattern has a coordinate to work in.
			var mesh := _box(Vector3.ONE)
			var mm := _channel(mesh, _tracer_shader(), TRACERS, false)
			var mat: ShaderMaterial = mesh.surface_get_material(0)
			mat.set_shader_parameter("body_col", Vector3(spec[7].r, spec[7].g, spec[7].b))
			mat.set_shader_parameter("head_col", Vector3(spec[8].r, spec[8].g, spec[8].b))
			mat.set_shader_parameter("bead_period", float(spec[4]))
			mat.set_shader_parameter("duty", float(spec[5]))
			mat.set_shader_parameter("head_len", float(spec[6]))
			mat.set_shader_parameter("smoke", float(spec[9]))
			mat.set_shader_parameter("soft", 1.0 if si >= SOFT_FIRST else 0.0)
			mat.set_shader_parameter("tint", Vector3.ONE)
			tracer_mm.append(mm)
			var a := PackedFloat32Array()
			a.resize(TRACERS)
			a.fill(-1.0)
			_tr_age.append(a)
			var f := PackedVector3Array()
			f.resize(TRACERS)
			_tr_from.append(f)
			var d := PackedVector3Array()
			d.resize(TRACERS)
			_tr_dir.append(d)
			var r := PackedFloat32Array()
			r.resize(TRACERS)
			_tr_range.append(r)
			_tr_next[si] = 0

		# NO _process. The project's rule, and this wants the physics clock
		# anyway so a frozen render is reproducible.
		set_physics_process(true)


	## Recolour one spec's whole channel — the faction-colour experiment. One
	## uniform write, not a per-tracer material, because a ShaderMaterial per
	## round is the resource-sharing trap this project has already paid for.
	func tint_spec(spec_index: int, tint: Color) -> void:
		var mat: ShaderMaterial = tracer_mm[spec_index].mesh.surface_get_material(0)
		mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))


	func _channel(mesh: Mesh, shader: Shader, count: int, shadows: bool) -> MultiMesh:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = count
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mesh.surface_set_material(0, mat)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# One AABB for the whole channel: a MultiMesh is culled as a unit, and
		# a computed AABB would park the lot offscreen the moment a slot moved.
		mi.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
		add_child(mi)
		# Every unused slot at zero scale, once. instance_count of 480 draws
		# 480 boxes whether or not they are in use, so the empty ones have to
		# be degenerate rather than merely transparent.
		for i in count:
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			mm.set_instance_custom_data(i, Color(1.0, 0.0, 0.0, 0.0))
		return mm


	# ── REGISTERING AN IMPACT ─────────────────
	#
	# The whole per-round cost, and the number the budget rests on. No
	# instantiate, no add_child, no material, no allocation: a handful of
	# writes into arrays that already exist.
	func impact(at: Vector3, normal: Vector3, incoming: Vector3, bucket: int, through: bool = false) -> void:
		impacts += 1
		var n: Vector3 = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
		var refl: Vector3 = incoming.normalized().bounce(n) if incoming.length_squared() > 0.0001 else n

		# ── THE PIT. Lies on the surface, 2 cm off it so it cannot z-fight.
		if _pit_age[_pit_next] > 0.0:
			recycled += 1
		var size: float = [0.26, 0.40, 0.34][bucket] * randf_range(0.8, 1.3)
		var t := Transform3D(Basis.looking_at(-n, _any_up(n)).scaled(Vector3(size, size, 1.0)), at + n * 0.02)
		pit_mm.set_instance_transform(_pit_next, t)
		pit_mm.set_instance_custom_data(_pit_next, Color(0.0, randf(), float(bucket), 1.0))
		_pit_age[_pit_next] = 0.0
		_pit_next = (_pit_next + 1) % PITS

		# ── THE SPARKS. A fan up the reflected vector, not a sphere: a sphere
		# is a firework and a fan is a ricochet. Wide on a robot (hard on hard,
		# it shatters) and tight on brush.
		var spread: float = [0.75, 0.35, 0.5][bucket]
		var speed: float = [14.0, 5.0, 9.0][bucket]
		var count: int = SPARKS_PER if bucket != Bucket.TERRAIN else 2
		for _i in count:
			_spark_pos[_spark_next] = at + n * 0.03
			_spark_vel[_spark_next] = (refl + Vector3(randf_range(-spread, spread),
					randf_range(-spread, spread), randf_range(-spread, spread))).normalized() \
					* speed * randf_range(0.45, 1.0)
			_spark_age[_spark_next] = 0.0
			spark_mm.set_instance_custom_data(_spark_next, Color(0.0, randf(), float(bucket), 1.0))
			_spark_next = (_spark_next + 1) % SPARKS

		# ── THE CHIP. One piece of the wall, thrown, and it bounces ONCE —
		# see tick(). Brush only: soft ground throws dust, not shrapnel, and a
		# robot throws sparks.
		if bucket == Bucket.BRUSH:
			for _i in CHIPS_PER:
				_chip_pos[_chip_next] = at + n * 0.06
				_chip_vel[_chip_next] = (n + Vector3(randf_range(-0.7, 0.7), randf_range(0.0, 0.9),
						randf_range(-0.7, 0.7))).normalized() * randf_range(2.6, 5.4)
				_chip_spin[_chip_next] = Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
				_chip_age[_chip_next] = 0.0
				chip_mm.set_instance_custom_data(_chip_next, Color(0.0, randf(), 0.0, 1.0))
				_chip_next = (_chip_next + 1) % CHIPS

		# ── THE DUST. Terrain gets a puff every round; everything else gets
		# one in eight, which is what makes a long firefight visibly foul the
		# room without any separate "haze" system. `through` puts the puff on
		# the FAR side — see the penetration tell.
		if bucket == Bucket.TERRAIN or through or randf() < 0.12:
			_dust_pos[_dust_next] = at + n * (0.2 if not through else -0.35)
			_dust_age[_dust_next] = 0.0
			dust_mm.set_instance_custom_data(_dust_next, Color(0.0, randf(),
					1.0 if through else float(bucket), 1.0))
			_dust_next = (_dust_next + 1) % DUST


	# ── FIRING A TRACER ───────────────────────
	#
	# `travel` is how far the round has to go, which the shooter ALREADY KNOWS:
	# ai_weapon.fire() raycasts before it spawns a tracer and passes the impact
	# point to Tracer.launch(). So a tracer needs no per-frame raycast of its
	# own, and the one in tracer.gd's legacy path — the path the PLAYER's
	# weapon still uses — is pure waste.
	func fire_tracer(spec_index: int, from: Vector3, dir: Vector3, travel: float, age: float = 0.0) -> void:
		tracers += 1
		var i: int = _tr_next[spec_index]
		if _tr_age[spec_index][i] > 0.0:
			recycled += 1
		_tr_from[spec_index][i] = from
		_tr_dir[spec_index][i] = dir.normalized()
		_tr_range[spec_index][i] = travel
		# `age` BACKDATES THE ROUND, which is how a still of a burst is made.
		#
		# The first version staged a row by firing one round, stepping the
		# cadence, firing the next, and so on — which is right for ONE row and
		# wrong the moment there are six, because stepping advances the whole
		# field and every row already placed ages while the next is being
		# built. The sheet came back with its top row fresh and its bottom row
		# two seconds downrange and out of frame.
		#
		# Backdating instead places the k-th round of a burst at exactly the
		# age it would have, independently of every other row, so a sheet is a
		# single instant whatever order it was assembled in.
		_tr_age[spec_index][i] = age
		_tr_next[spec_index] = (i + 1) % TRACERS


	# ── THE TICK ──────────────────────────────
	#
	# One pass over fixed arrays. It costs the same whether one effect is live
	# or all of them are, which is the other half of the bargain: the frame
	# cost is a CONSTANT, not a function of how hard the fight is.
	func _physics_process(delta: float) -> void:
		if freeze >= 0.0:
			return   # pinned by FREEZE; tick() was already stepped by hand
		tick(delta)


	func tick(delta: float) -> void:
		for i in PITS:
			var a: float = _pit_age[i]
			if a < 0.0:
				continue
			a += delta
			if a >= PIT_LIFE:
				_pit_age[i] = -1.0
				pit_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
				continue
			_pit_age[i] = a
			pit_mm.set_instance_custom_data(i, _reage(pit_mm.get_instance_custom_data(i), a / PIT_LIFE))

		for i in SPARKS:
			var a: float = _spark_age[i]
			if a < 0.0:
				continue
			a += delta
			if a >= SPARK_LIFE:
				_spark_age[i] = -1.0
				spark_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
				continue
			_spark_age[i] = a
			var v: Vector3 = _spark_vel[i] + Vector3.DOWN * GRAVITY * delta
			_spark_vel[i] = v
			var p: Vector3 = _spark_pos[i] + v * delta
			_spark_pos[i] = p
			# The streak is the distance covered this frame, stretched — which
			# is why a fast spark is a line and a dying one is a dot.
			var length: float = clampf(v.length() * 0.035, 0.03, 0.55)
			# SPARKS NEED THE APPARENT-WIDTH FLOOR TOO, and that was found the
			# hard way: at their physical 2.2 cm they are under two pixels at
			# twelve metres, the edge pass renders them near-black, and against
			# a dark wall they are simply not there. Three renders of the spark
			# shot came back looking like the channel was switched off.
			var sw: float = 1.0
			if m_per_px_at_1m > 0.0:
				sw = maxf(1.0, p.distance_to(eye) * m_per_px_at_1m * floor_px / 0.022)
			spark_mm.set_instance_transform(i, Transform3D(
					Basis.looking_at(v.normalized(), _any_up(v.normalized())).scaled(Vector3(sw, sw, length)), p))
			spark_mm.set_instance_custom_data(i, _reage(spark_mm.get_instance_custom_data(i), a / SPARK_LIFE))

		for i in CHIPS:
			var a: float = _chip_age[i]
			if a < 0.0:
				continue
			a += delta
			if a >= CHIP_LIFE:
				_chip_age[i] = -1.0
				chip_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
				continue
			var v: Vector3 = _chip_vel[i] + Vector3.DOWN * GRAVITY * delta
			var p: Vector3 = _chip_pos[i] + v * delta
			# ONE BOUNCE, AND NO RAYCAST TO FIND IT. The floor is taken as the
			# height the chip started at: a chip comes off a wall and lands at
			# the foot of it, and a physics query per chip per frame is exactly
			# the cost this design refuses to pay. custom.b is the "bounced"
			# flag.
			var cd: Color = chip_mm.get_instance_custom_data(i)
			if v.y < 0.0 and p.y < _chip_pos[i].y and cd.b < 0.5 and a > 0.25:
				v = Vector3(v.x * 0.4, absf(v.y) * 0.32, v.z * 0.4)
				cd.b = 1.0
			_chip_vel[i] = v
			_chip_pos[i] = p
			_chip_age[i] = a
			chip_mm.set_instance_transform(i, Transform3D(Basis.from_euler(_chip_spin[i] * a), p))
			cd.r = a / CHIP_LIFE
			chip_mm.set_instance_custom_data(i, cd)

		for i in DUST:
			var a: float = _dust_age[i]
			if a < 0.0:
				continue
			a += delta
			if a >= DUST_LIFE:
				_dust_age[i] = -1.0
				dust_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
				continue
			_dust_age[i] = a
			var k: float = a / DUST_LIFE
			# Billboarded in the shader, so the transform carries only the
			# growth and a slow drift upward.
			var grow: float = lerpf(0.35, 1.9, sqrt(k))
			dust_mm.set_instance_transform(i, Transform3D(
					Basis().scaled(Vector3(grow, grow, grow)),
					_dust_pos[i] + Vector3.UP * k * 0.55))
			dust_mm.set_instance_custom_data(i, _reage(dust_mm.get_instance_custom_data(i), k))

		for si in tracer_mm.size():
			var spec: Array = TRACER_SPECS[si]
			var speed: float = float(spec[1])
			var length: float = float(spec[2])
			var cal: float = float(spec[3]) * cal_mul[si]
			var mm: MultiMesh = tracer_mm[si]
			var ages: PackedFloat32Array = _tr_age[si]
			for i in TRACERS:
				var a: float = ages[i]
				if a < 0.0:
					continue
				a += delta
				var flown: float = a * speed
				var travel: float = _tr_range[si][i]
				if a >= TRACER_LIFE or flown >= travel:
					ages[i] = -1.0
					mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
					continue
				ages[i] = a
				var dir: Vector3 = _tr_dir[si][i]
				# THE STREAK GROWS OUT OF THE MUZZLE rather than appearing at
				# full length. A round that is born 11 m long pops into
				# existence as a wall; one that extends reads as leaving.
				var lit: float = minf(length, flown)
				var head: Vector3 = _tr_from[si][i] + dir * flown
				var mid: Vector3 = head - dir * (lit * 0.5)
				# Never thinner on screen than floor_px. See CONSTANT
				# APPARENT WIDTH; m_per_px_at_1m of 0 switches it off.
				var w: float = cal
				if m_per_px_at_1m > 0.0:
					w = maxf(cal, mid.distance_to(eye) * m_per_px_at_1m * floor_px)
				mm.set_instance_transform(i, Transform3D(
						Basis.looking_at(dir, _any_up(dir)).scaled(Vector3(w, w, lit)), mid))
				# custom = (age01, 0, flown, lit) — flown so the bead pattern
				# is anchored in WORLD distance and the beads therefore stay
				# still relative to the ground as the streak travels, instead
				# of crawling along it.
				mm.set_instance_custom_data(i, Color(a / TRACER_LIFE, 0.0, flown, lit))


	# ── THE FREEZE IS A TIME, NOT A FRACTION, AND THAT WAS A CORRECTION ──
	#
	# It began as "hold every channel at k of its own life", which cannot be
	# done and is not even a coherent request. A single frame of a world is one
	# INSTANT, and at any instant the 0.22 s sparks and the 14 s scorch are at
	# completely different points of their own lives — that is what it means
	# for them to have different lifetimes.
	#
	# Worse, the implementation stepped the simulation to k x the LONGEST life,
	# so FREEZE=0.22 stepped 3.08 seconds and every spark, chip and dust puff
	# in the picture was long dead. The render came back with nothing in it but
	# scorch marks and looked like the effects had failed.
	#
	# So the parameter is SECONDS SINCE THE LAST ROUND LANDED. Small numbers
	# catch the flash, larger ones the room afterwards.
	func settle(seconds: float) -> void:
		freeze = -1.0
		const STEP := 1.0 / 240.0
		var t := 0.0
		while t < seconds:
			tick(STEP)
			t += STEP
		# One more tick, so a channel whose state was backdated rather than
		# simulated gets its transforms written before the frame is captured.
		tick(0.0001)
		freeze = seconds


	## Step the whole field by a real number of seconds without freezing it.
	func fly(seconds: float) -> void:
		freeze = -1.0
		const STEP := 1.0 / 240.0
		var t := 0.0
		while t < seconds:
			tick(STEP)
			t += STEP


	static func _reage(cd: Color, k: float) -> Color:
		cd.r = k
		return cd


	## A quad or box oriented from one vector needs an up that is not parallel
	## to it, or Basis.looking_at returns garbage and the instance vanishes.
	static func _any_up(n: Vector3) -> Vector3:
		return Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT


	static func _quad(size: float) -> Mesh:
		var m := QuadMesh.new()
		m.size = Vector2(size, size)
		return m


	static func _box(size: Vector3) -> Mesh:
		var m := BoxMesh.new()
		m.size = size
		return m


	# ═════════════════════════════════════════
	# THE SHADERS
	#
	# INSTANCE_CUSTOM carries state, never TIME, so the look is a pure function
	# of the simulation and the freeze works — a still is then evidence.
	#
	# All of them lean on VALUE CONTRAST rather than on gradients or on hue.
	# The signal filter quantises luma to ten levels and chroma to five, with a
	# Bayer-8 ordered dither at 0.85 applied BEFORE the quantisation — which is
	# the thing that saves these effects, because a dithered gradient survives
	# ten steps where a flat one would band. See docs/concepts/IMPACTS.md.
	# ═════════════════════════════════════════

	## INSTANCE_CUSTOM IS VERTEX-ONLY. Godot 4 exposes it in vertex() and
	## nowhere else; reading it in fragment() is "Unknown identifier in
	## expression". Worse, the DUMMY renderer reports that as a shader compile
	## failure and then carries straight on, so a headless run of this tool
	## printed its whole bench with five broken shaders and looked like it had
	## worked. Every shader below carries the data across in a `varying vec4
	## cd` declared and filled in its own vertex().
	static func _shader(code: String) -> Shader:
		var s := Shader.new()
		s.code = code
		return s


	static func _pit_shader() -> Shader:
		return _shader("""
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

varying vec4 cd;

void vertex() { cd = INSTANCE_CUSTOM; }

void fragment() {
	float age = cd.r;
	float live = cd.a;
	float bucket = cd.b;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// A pit, not a blob: a dark core, a hot rim for the first instant, and a
	// ragged edge so twenty of them do not read as polka dots.
	float ragged = 0.80 + 0.20 * sin(atan(p.y, p.x) * 7.0 + cd.g * 31.4);
	float core = 1.0 - smoothstep(0.0, ragged, r);
	float rim = smoothstep(ragged * 0.55, ragged * 0.95, r) * (1.0 - smoothstep(ragged * 0.95, ragged, r));
	// Terrain scuffs pale; brush and metal scorch dark.
	float is_terrain = step(0.5, bucket) * step(bucket, 1.5);
	vec3 scorch = mix(vec3(0.03, 0.03, 0.035), vec3(0.46, 0.41, 0.32), is_terrain);
	float heat = exp(-age * 24.0);
	ALBEDO = scorch + vec3(1.0, 0.45, 0.10) * rim * heat * 3.0;
	ALPHA = live * core * (1.0 - smoothstep(0.55, 1.0, age)) * 0.92;
}
""")


	static func _spark_shader() -> Shader:
		return _shader("""
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

varying vec4 cd;

void vertex() { cd = INSTANCE_CUSTOM; }

void fragment() {
	float age = cd.r;
	float live = cd.a;
	// Hot white at the head, orange as it cools, gone. Pushed well off the
	// tracer's own hue band for the same reason tracer.gd pushes outgoing off
	// incoming: the filter subsamples chroma, so two shades of one colour
	// become one colour.
	vec3 hot = vec3(1.0, 0.97, 0.86);
	vec3 cool = vec3(1.0, 0.42, 0.08);
	float fade = pow(1.0 - age, 1.6);
	ALBEDO = mix(hot, cool, age) * fade * 2.6;
	ALPHA = live * fade;
}
""")


	static func _chip_shader() -> Shader:
		return _shader("""
shader_type spatial;
render_mode blend_mix, cull_back;

varying vec4 cd;

void vertex() { cd = INSTANCE_CUSTOM; }

void fragment() {
	float age = cd.r;
	// Lit, unlike the rest: a chip is a piece of the wall and has to take the
	// level's own light or it reads as a sprite.
	ALBEDO = vec3(0.34, 0.32, 0.30);
	ROUGHNESS = 0.9;
	ALPHA = cd.a * (1.0 - smoothstep(0.75, 1.0, age));
}
""")


	static func _dust_shader() -> Shader:
		return _shader("""
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;
	// Billboard. Keeps the instance's scale, drops its rotation.
	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = mat4(
		vec4(sx, 0.0, 0.0, 0.0),
		vec4(0.0, sy, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		mv[3]);
}

void fragment() {
	float age = cd.r;
	float live = cd.a;
	float exit_puff = cd.b;
	vec2 p = UV * 2.0 - 1.0;
	float soft = 1.0 - smoothstep(0.1, 1.0, length(p));
	// Pale, and NOT subtle. Ten luma levels will eat a 5% haze outright.
	vec3 tint = mix(vec3(0.72, 0.66, 0.56), vec3(0.88, 0.86, 0.84), exit_puff);
	ALBEDO = tint;
	ALPHA = live * soft * 0.50 * (1.0 - age) * (1.0 - age);
}
""")


	## THE TRACER. One shader, driven entirely by uniforms, so a weapon class
	## is a set of numbers rather than a new effect.
	##
	## bead_period 0 is the SOLID streak — the single elongated bar, uniform
	## along its length, that a heavy round should be. Above 0 it is the
	## AUTHORED beaded chain: one long streak cut into dashes in the fragment
	## shader. The third possibility is not in here at all, because it needs no
	## code: several SHORT solid streaks in flight at once, which is what a
	## rapid-fire weapon produces on its own. See the A/B in the shots.
	static func _tracer_shader() -> Shader:
		return _shader("""
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform vec3 body_col = vec3(1.0, 0.8, 0.3);
uniform vec3 head_col = vec3(1.0, 1.0, 0.9);
uniform vec3 tint = vec3(1.0);
uniform float bead_period = 0.0;
uniform float duty = 1.0;
uniform float head_len = 0.4;
uniform float smoke = 0.0;
// ── SOFT EDGES: THE IDEA THAT DID NOT WORK ──
//
// signal_filter.gdshader's edge pass keys on the luma STEP between a pixel
// and its four neighbours, not on brightness, so the hypothesis was that
// FADING the cross-section would spread the same contrast over several pixels,
// drop every individual step under edge_threshold, and rescue a thin streak
// without making it fat.
//
// Shot 27 says no. A streak two pixels wide has nothing to spread a ramp
// over — the fade lands inside a single pixel and the step is the same step,
// only dimmer. Softness buys nothing that width has not already bought, and
// the governing variable really is APPARENT WIDTH.
//
// Left in, switched on for two rows of shot 27, because a negative result
// that is not written down gets re-tried.
uniform float soft = 0.0;

varying float along;
varying float across;
varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;
	// The mesh is a UNIT box scaled by the instance, so local z is a clean
	// -0.5..0.5 from tail to head whatever the streak's length.
	along = VERTEX.z + 0.5;
	// 0 on a side face's centre line, 1 at its edges. min() picks the axis
	// that VARIES across whichever of the four side faces is being drawn —
	// the other is pinned at 0.5 by being the face itself.
	across = 2.0 * min(abs(VERTEX.x), abs(VERTEX.y));
}

void fragment() {
	float flown = cd.b;
	float lit = max(cd.a, 0.0001);
	// Where this fragment is in WORLD distance from the muzzle. Anchoring the
	// pattern here rather than in UV is what keeps authored beads STILL
	// relative to the ground as the round travels; anchored in UV they crawl
	// along the streak, which reads as a glitch rather than as motion.
	float world_at = flown - (1.0 - along) * lit;

	// ── the head flare ──
	float from_head = (1.0 - along) * lit;
	float head = 1.0 - smoothstep(0.0, max(head_len, 0.0001), from_head);

	// ── the body, solid or beaded ──
	float body = 1.0;
	if (bead_period > 0.0) {
		float ph = fract(world_at / bead_period);
		// Soft-edged dashes. A hard step aliases to a dotted mess at range.
		body = smoothstep(0.0, 0.18, ph) * (1.0 - smoothstep(duty - 0.18, duty, ph));
	}
	// The tail falls off so the streak has a direction even when solid.
	float taper = smoothstep(0.0, 0.35, along);

	float a = max(body * taper, head);
	vec3 col = mix(body_col, head_col, head * head) * tint;
	// Smoke: a dull grey smear BEHIND the round, which is what tells a rocket
	// and a cannon shell from a bullet at a glance.
	if (smoke > 0.0) {
		float trail = (1.0 - smoothstep(0.0, 1.0, along)) * smoke;
		col = mix(col, vec3(0.42, 0.40, 0.38), clamp(trail, 0.0, 0.75));
		a = max(a, trail * 0.5);
	}
	ALBEDO = col * 1.15;
	// The soft cross-section. Mixed rather than branched so the two rows of
	// shot 27 are otherwise the same shader doing the same work.
	a *= mix(1.0, 1.0 - smoothstep(0.15, 1.0, across), soft);
	ALPHA = clamp(a, 0.0, 1.0) * step(0.0001, lit);
}
""")


# ═════════════════════════════════════════════
# ENTRY
# ═════════════════════════════════════════════

func _initialize() -> void:
	await process_frame
	var mode := OS.get_environment("MODE").to_lower()
	if mode == "survey":
		await _survey()
	elif mode == "bench":
		_bench()
	elif mode == "rates":
		_rates()
	else:
		await _shots()


# ─────────────────────────────────────────────
# SURVEY — what does a round actually hit, and what can we learn about it?
# ─────────────────────────────────────────────
const SURVEY_LEVELS := ["proving", "salient"]


func _survey() -> void:
	print("engine: %s" % ProjectSettings.get_setting("physics/3d/physics_engine", "<default>"))
	for level_name: String in SURVEY_LEVELS:
		clear_bucket_cache()
		var level := _load_level(level_name)
		if level == null:
			continue
		for _i in 90:
			await physics_frame
		var space := level.get_world_3d().direct_space_state
		print("\n-- %s --" % level_name)
		var seen := {}
		var faces_seen := 0
		var hits := 0
		var rect: Array = _survey_rect(level_name)
		for x in range(int(rect[0]), int(rect[1]), int(rect[4])):
			for z in range(int(rect[2]), int(rect[3]), int(rect[4])):
				hits += _survey_ray(space, Vector3(x, 400.0, z), Vector3(x, -60.0, z), seen)
				hits += _survey_ray(space, Vector3(x, 2.0, z), Vector3(x + 60.0, 2.0, z), seen)
		for k in seen:
			var e: Dictionary = seen[k]
			if int(e["faces"]) >= 0:
				faces_seen += 1
			print("  %5d  %-38s  bucket=%-7s  chain=%s  face_index=%s"
					% [e["n"], k, BUCKET_NAMES[int(e["bucket"])], e["chain"], e["faces"]])
		print("  %d hits, %d distinct colliders, %d returned a usable face_index"
				% [hits, seen.size(), faces_seen])
		print("  bucket cache: %d lookups, %d misses" % [bucket_lookups, bucket_misses])
		_drop_level(level)
		await process_frame
	quit()


func _survey_rect(level_name: String) -> Array:
	if level_name == "proving":
		return [-34, 34, -30, 92, 5]
	return [-180, 120, -130, 140, 20]


func _survey_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, seen: Dictionary) -> int:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 0
	var col: Object = hit["collider"]
	var node := col as Node
	var key := "%s/%s" % [col.get_class(), _shape_class(hit)]
	if not seen.has(key):
		# The ancestor chain, named, because the bucket test has to walk it and
		# the chain is the thing that was wrong the first time.
		var chain: Array = []
		var w: Node = node
		for _i in 4:
			if w == null:
				break
			chain.append("%s%s" % [w.name, "(terrain)" if w.is_in_group(&"terrain") else ""])
			w = w.get_parent()
		seen[key] = {
			"n": 0,
			"chain": " < ".join(chain),
			"bucket": bucket_of(col, null),
			"faces": int(hit.get("face_index", -1)),
		}
	seen[key]["n"] = int(seen[key]["n"]) + 1
	return 1


func _shape_class(hit: Dictionary) -> String:
	var col: Object = hit["collider"]
	if not (col is CollisionObject3D):
		return "?"
	var body := col as CollisionObject3D
	var idx: int = int(hit.get("shape", -1))
	if idx < 0:
		return "shape?"
	var s: Shape3D = body.shape_owner_get_shape(body.shape_find_owner(idx), 0)
	return s.get_class() if s != null else "null"


# ─────────────────────────────────────────────
# RATES — how many of these things are actually in the air at Qamareen?
#
# Arithmetic, printed, so the pool sizes above are a consequence of something
# rather than a guess. 186 bodies is the measured Qamareen figure.
# ─────────────────────────────────────────────
const QAMAREEN_BODIES := 186


func _rates() -> void:
	print("── rounds per second, by what fraction of 186 bodies is in contact ──")
	print("   (fire_cooldown is the INTRA-BURST interval: enemy.gd:3059)")
	for frac in [0.1, 0.25, 0.5, 1.0]:
		var shooting := int(QAMAREEN_BODIES * frac)
		print("  %3d shooting (%.0f%%):" % [shooting, frac * 100.0])
		for w: Array in WEAPON_CLASSES:
			var cd: float = float(w[2])
			var rps: float = float(shooting) / cd
			# Bursts are followed by a re-aim, so sustained output is well
			# under cyclic. 45% duty is the generous end of what enemy.gd's
			# AIM/FIRE loop produces.
			var sustained: float = rps * 0.45
			print("     %-24s %7.0f rounds/s cyclic, %6.0f sustained" % [w[0], rps, sustained])
		break
	print()
	print("── live tracers, which is the number the pool has to hold ──")
	print("   live = rounds/s x flight time x tracer fraction")
	for shooting in [19, 47, 93]:
		print("  %3d shooting:" % shooting)
		for w: Array in WEAPON_CLASSES:
			var spec: Array = TRACER_SPECS[int(w[1])]
			var speed: float = float(spec[1])
			# 60 m is a representative engagement range in this game; the
			# weapon tables run 35 to 130 m effective.
			var flight: float = 60.0 / speed
			var sustained: float = float(shooting) / float(w[2]) * 0.45
			print("     %-24s flight %.2fs -> %6.0f live every round, %5.0f live at 1-in-5"
					% [w[0], flight, sustained * flight, sustained * flight * 0.2])
	print()
	# ── DOES CADENCE ALONE MAKE A BEADED CHAIN? ──
	#
	# THE FIRST VERSION OF THIS ASKED THE WRONG QUESTION and I am leaving the
	# correction in rather than quietly swapping it, because the wrong measure
	# is the intuitive one. It compared the bead SPACING against the streak's
	# own LENGTH and called anything wider than three lengths "separate
	# rounds". That is not what makes a chain read as a chain.
	#
	# What makes a chain is HOW MANY LIT SEGMENTS ARE IN THE AIR AT ONCE along
	# the line of fire, and what fraction of that line is lit. A reference
	# image showing six or seven beads is showing six or seven ROUNDS; the gaps
	# between them being several bead-lengths wide is the whole point of the
	# look, not a disqualification from it.
	#
	#   beads in flight = engagement range / (speed x cadence)
	#   duty            = streak length / (speed x cadence)
	print("── does cadence alone make a beaded chain? ──")
	print("   beads = range / (speed x cd).  duty = streak / (speed x cd).")
	print("   The reference reads as roughly 6-8 beads at a duty near 0.4.")
	for rng in [40.0, 80.0]:
		print("  at %.0f m:" % rng)
		for w: Array in WEAPON_CLASSES:
			var spec: Array = TRACER_SPECS[int(w[1])]
			var speed: float = float(spec[1])
			var length: float = float(spec[2])
			var gap: float = speed * float(w[2])
			var beads: float = rng / gap
			var duty: float = length / gap
			var verdict := "one round at a time"
			if beads >= 3.0 and duty >= 0.10:
				verdict = "A CHAIN"
			elif beads >= 3.0:
				verdict = "a chain, too sparse to read"
			print("     %-24s %5.1f m apart -> %4.1f beads, duty %.2f  %s"
					% [w[0], gap, beads, duty, verdict])
	print()
	print("   and at the SHIPPING tracer speed of 160 m/s (tracer.gd), 80 m:")
	for w: Array in WEAPON_CLASSES:
		var gap: float = 160.0 * float(w[2])
		print("     %-24s %6.1f m apart -> %4.1f beads" % [w[0], gap, 80.0 / gap])
	quit()


# ─────────────────────────────────────────────
# BENCH — what does one impact cost, what does one tracer cost, and what does
# the pool cost per frame?
#
# CPU TIME, SYNCHRONOUSLY, NO AWAITS. Timing a loop that awaits physics_frame
# in headless measures the 16.67 ms tick and not the work — that mistake has
# cost this project four benchmark sweeps. There is nothing to pace here
# because nothing waits.
# ─────────────────────────────────────────────

func _bench() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var field := ImpactField.new()
	# add_child alone. Calling _ready() by hand as well built every channel
	# TWICE, so tracer_mm held fourteen entries against seven specs and the
	# tick walked off the end of TRACER_SPECS.
	holder.add_child(field)

	var n := 20000
	var normal := Vector3(0, 0, 1)
	var incoming := Vector3(0.3, -0.2, 1).normalized()

	# Warm: first touch of a MultiMesh buffer allocates on the servers.
	for i in 500:
		field.impact(Vector3(randf() * 20.0, 1.0, 0.0), normal, incoming, i % 3)
		field.fire_tracer(i % SHIPPING_SPECS, Vector3.ZERO, Vector3.FORWARD, 60.0)

	print("── one impact ──")
	for b in 3:
		var t0 := Time.get_ticks_usec()
		for i in n:
			field.impact(Vector3(fmod(float(i), 20.0), 1.0, 0.0), normal, incoming, b)
		var us := float(Time.get_ticks_usec() - t0) / float(n)
		print("  %-8s %8.3f us  (%.4f ms)  %d effect slots spent" % [BUCKET_NAMES[b], us, us / 1000.0, _slots_for(b)])

	print("── one tracer, fired ──")
	var t_tr := Time.get_ticks_usec()
	for i in n:
		field.fire_tracer(i % SHIPPING_SPECS, Vector3(0, 2, 0), Vector3.FORWARD, 60.0)
	var tr_us := float(Time.get_ticks_usec() - t_tr) / float(n)
	print("  %8.3f us  (%.4f ms) — four array writes and a modulo" % [tr_us, tr_us / 1000.0])

	print("── the bucket test ──")
	var body := StaticBody3D.new()
	var built := Node3D.new()
	built.name = "_Built"
	var carrier := Node3D.new()
	carrier.add_to_group(&"terrain")
	carrier.add_child(built)
	built.add_child(body)
	holder.add_child(carrier)
	var plain := StaticBody3D.new()
	holder.add_child(plain)
	clear_bucket_cache()
	# Cold: every call a miss, so the walk is timed.
	var t_cold := Time.get_ticks_usec()
	var sink := 0
	for i in 2000:
		clear_bucket_cache()
		sink += bucket_of(plain, null)
		sink += bucket_of(body, null)
	var cold := float(Time.get_ticks_usec() - t_cold) / 4000.0
	clear_bucket_cache()
	var t_warm := Time.get_ticks_usec()
	for i in n:
		sink += bucket_of(plain, null)
		sink += bucket_of(body, null)
		sink += bucket_of(plain, body)
	var warm := float(Time.get_ticks_usec() - t_warm) / float(n * 3)
	print("  cold (cache miss, walks the chain)  %8.4f us" % cold)
	print("  warm (cache hit)                    %8.4f us   %d lookups, %d misses (%d)"
			% [warm, bucket_lookups, bucket_misses, sink])
	print("  a level has 1-2 distinct colliders, so in play it is ALL warm.")

	# EMPTY FIRST, because the saturated number alone is misleading and the
	# first version of this bench printed it as "at rest". The tick walks every
	# slot whether or not it holds anything, so the empty cost is the floor a
	# quiet level pays for having the field in the scene at all — and the gap
	# between the two is what a live-list rewrite would be worth.
	print("── the pool tick, EMPTY ──")
	var t_empty := Time.get_ticks_usec()
	for i in 600:
		field.tick(1.0 / 60.0)
	print("  %8.4f ms per physics frame with nothing live"
			% [float(Time.get_ticks_usec() - t_empty) / 600.0 / 1000.0])

	print("── the pool tick, saturated ──")
	for i in 400:
		field.impact(Vector3(randf() * 30.0, 2.0, randf() * 30.0), normal, incoming, i % 3)
	for si in SHIPPING_SPECS:
		for _j in ImpactField.TRACERS:
			field.fire_tracer(si, Vector3(randf() * 40.0, 2.0, 0.0), Vector3.FORWARD, 400.0)
	var frames := 600
	var t2 := Time.get_ticks_usec()
	for i in frames:
		field.tick(1.0 / 60.0)
		if i % 2 == 0:
			for j in 6:
				field.impact(Vector3(randf() * 30.0, 2.0, randf() * 30.0), normal, incoming, j % 3)
				field.fire_tracer(j % SHIPPING_SPECS, Vector3(randf() * 40.0, 2.0, 0.0),
						Vector3.FORWARD, 400.0)
	var tick_ms := float(Time.get_ticks_usec() - t2) / float(frames) / 1000.0
	var slots: int = ImpactField.PITS + ImpactField.SPARKS + ImpactField.CHIPS + ImpactField.DUST \
			+ ImpactField.TRACERS * SHIPPING_SPECS
	print("  %8.4f ms per physics frame over %d slots (%d pit / %d spark / %d chip / %d dust / %d x %d tracer)"
			% [tick_ms, slots, ImpactField.PITS, ImpactField.SPARKS, ImpactField.CHIPS,
			ImpactField.DUST, SHIPPING_SPECS, ImpactField.TRACERS])
	print("  %d impacts, %d tracers, %d slots recycled at the ceiling"
			% [field.impacts, field.tracers, field.recycled])

	print("── what that buys, against a 16.67 ms frame ──")
	var t3 := Time.get_ticks_usec()
	for i in n:
		field.impact(Vector3(fmod(float(i), 20.0), 1.0, 0.0), normal, incoming, Bucket.BRUSH)
		field.fire_tracer(1, Vector3(0, 2, 0), Vector3.FORWARD, 60.0)
	var per_round := float(Time.get_ticks_usec() - t3) / float(n) / 1000.0
	print("  one round, tracer + impact        %.4f ms" % per_round)
	print("  the tick, FULLY SATURATED         %.4f ms  (= %.2f awake robots at 0.115 ms)"
			% [tick_ms, tick_ms / 0.115])
	print("  1.00 ms of headroom buys          %d rounds registered in a single frame"
			% int(1.0 / maxf(per_round, 1e-9)))
	print("  saturated, the whole field is     %.1f%% of a 60 Hz frame" % [tick_ms / 16.67 * 100.0])
	quit()


func _slots_for(b: int) -> int:
	if b == Bucket.TERRAIN:
		return 1 + 2 + 1
	if b == Bucket.ROBOT:
		return 1 + ImpactField.SPARKS_PER
	return 1 + ImpactField.SPARKS_PER + ImpactField.CHIPS_PER


# ─────────────────────────────────────────────
# SHOTS
#
# level, name, eye, look at, fov, what to stage.
# The eye is always 1.50 m above whatever collision is under it.
# ─────────────────────────────────────────────
# ── WHERE THESE CAMERAS CAME FROM ──
# Measured, not chosen. The first set was aimed at (0, 2.2, 44), which looked
# like the blockhouse face and is in fact the GATEWAY THROUGH IT: every impact
# staged correctly, landed on a wall sixty metres further on, and the picture
# came back with nothing in it. A fan of rays from a handful of candidate eyes
# found the real surfaces — the east arena wall is 11.6 m from (22, ., 20), the
# blockhouse face 12.7 m from (0, ., 52), and a gateway pillar 6.0 m from
# (0, ., 30). _stage now prints the range it actually hit and says so when
# nothing is closer than 24 m, so this cannot happen quietly again.
const SHOTS: Array = [
	# ── IMPACTS, on the east arena wall, at the range a firefight in this
	# game is actually fought at.
	["proving", "01_today", Vector3(22.0, EYE, 20.0), Vector3(34.0, 2.1, 20.0), 62.0, "none"],
	["proving", "02_sparks", Vector3(22.0, EYE, 20.0), Vector3(34.0, 2.1, 20.0), 62.0, "sparks"],
	["proving", "03_pits", Vector3(22.0, EYE, 20.0), Vector3(34.0, 2.1, 20.0), 62.0, "pits"],
	["proving", "04_chips", Vector3(22.0, EYE, 20.0), Vector3(34.0, 2.1, 20.0), 62.0, "chips"],
	["proving", "05_everything", Vector3(22.0, EYE, 20.0), Vector3(34.0, 2.1, 20.0), 62.0, "all"],
	# 3.6 m: one hole, rather than a pattern.
	["proving", "06_one_round_close", Vector3(30.0, EYE, 20.0), Vector3(34.0, 1.7, 20.0), 50.0, "one"],
	["proving", "07_through_vs_stopped", Vector3(27.0, EYE, 20.0), Vector3(34.0, 1.9, 20.0), 56.0, "pen"],
	["proving", "08_after_the_firefight", Vector3(22.0, EYE, 20.0), Vector3(34.0, 2.1, 20.0), 62.0, "firefight"],
	# The near miss wants open ground AHEAD, so this one looks up the arena.
	["proving", "09_near_miss", Vector3(0.0, EYE, -40.0), Vector3(0.0, 3.0, 20.0), 64.0, "nearmiss"],
	# ── TRACERS, CROSSING THE FRAME. A round flying away from the eye is
	# foreshortened to a dot and has no shape at all — which is a finding in
	# its own right, and shot 25 is the proof of it. Everything about the
	# VOCABULARY has to be judged side-on, because side-on is how you see
	# somebody else's fire.
	["proving", "20_vocabulary", Vector3(0.0, EYE, -40.0), Vector3(0.0, 6.5, -8.0), 60.0, "vocab"],
	["proving", "21_emergent_vs_authored", Vector3(0.0, EYE, -40.0), Vector3(0.0, 4.4, -8.0), 56.0, "ab_bead"],
	["proving", "22_tracer_fraction", Vector3(0.0, EYE, -40.0), Vector3(0.0, 4.4, -8.0), 56.0, "ab_frac"],
	["proving", "23_faction_colour", Vector3(0.0, EYE, -40.0), Vector3(0.0, 4.4, -8.0), 56.0, "ab_faction"],
	["proving", "24_incoming_burst", Vector3(0.0, EYE, -40.0), Vector3(0.0, 3.2, 20.0), 64.0, "incoming"],
	["proving", "25_outgoing_vs_crossing", Vector3(0.0, EYE, -40.0), Vector3(0.0, 4.0, -8.0), 60.0, "ab_axis"],
	# THE MOST IMPORTANT PICTURE HERE. Five identical bursts at five
	# cross-sections, through the game's own filter, to find the width at
	# which a hot streak stops being rendered black. See the note on the edge
	# pass in docs/concepts/IMPACTS.md.
	["proving", "26_thickness_ladder", Vector3(0.0, EYE, -40.0), Vector3(0.0, 5.0, -8.0), 58.0, "ladder"],
	# ...and the cure. Four rows: hard and soft edges at two widths, through
	# the same filter. If the soft thin row survives, thinness was never the
	# problem and the fix costs one line of shader rather than a bullet the
	# width of a drainpipe.
	["proving", "27_soft_vs_hard", Vector3(0.0, EYE, -40.0), Vector3(0.0, 4.4, -8.0), 58.0, "soft"],
	# ── THE BUCKETS, in a level with real GeneratedTerrain under it and a
	# robot standing on it: dust off the ground, sparks off the machine.
	["salient", "10_bucket_terrain", Vector3(-95.0, EYE, 105.0), Vector3(-86.0, 0.2, 100.0), 62.0, "ground"],
	["salient", "11_bucket_robot", Vector3(-95.0, EYE, 105.0), Vector3(-89.0, 1.0, 102.0), 46.0, "robot"],
]

const ROBOT_SCENE := "res://Character/characters/ai/soldier_rifle.tscn"

## The faction colour language, from Character/hud/hud_palette.gd.
const FACTION_TINTS: Array = [
	["adversary amber", Color(0.91, 0.63, 0.23)],
	["home green", Color(0.64, 0.73, 0.44)],
	["argus tyrian", Color(0.69, 0.20, 0.47)],
]


func _shots() -> void:
	if DisplayServer.get_name() == "headless":
		print("FAIL  mock_impacts needs a WINDOW. The dummy renderer returns blank")
		print("      textures and signal_filter.gdshader reads the screen, so a")
		print("      headless render comes back flat and looks like proof.")
		print("      Drop --headless and run muted: --audio-driver Dummy")
		quit(1)
		return
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	if not DirAccess.dir_exists_absolute(out):
		if DirAccess.make_dir_recursive_absolute(out) != OK:
			print("FAIL  could not make %s" % out)
			quit(1)
			return
	var only := OS.get_environment("ONLY")
	var bare := OS.get_environment("NOFILTER") != ""
	var suffix := "_raw" if bare else ""
	# SECONDS since the last round landed, not a fraction of anything. 0.05
	# catches the flash of the newest round while the burst's older pits are
	# still on the wall.
	var freeze_env := OS.get_environment("FREEZE")
	var freeze: float = 0.05
	if freeze_env.is_valid_float():
		freeze = clampf(freeze_env.to_float(), 0.0, 20.0)

	# NOEDGE=1 keeps the whole filter and turns OFF ONE TERM — the edge pass.
	# It is here because NOFILTER could not answer the question it was asked.
	# The filtered tracers came back as dark dashes and the unfiltered ones as
	# white streaks, which says the filter did it but not WHICH PART, and
	# "the filter" is five separate operations. With edge_strength at zero and
	# everything else untouched, the cause is isolated rather than inferred.
	var noedge := OS.get_environment("NOEDGE") != ""
	if noedge:
		suffix = "_noedge"

	var mat: ShaderMaterial = null
	if not bare:
		mat = _hud_filter()
		if mat == null:
			print("FAIL  no %s material in %s — has the HUD been rearranged?" % [FILTER_NODE, HUD_SCENE])
			quit(1)
			return
		if noedge:
			mat.set_shader_parameter("edge_strength", 0.0)
	print("   filter: %s%s   freeze: %.2f s after the last round" % [
			mat.shader.resource_path.get_file() if mat != null else "OFF (NOFILTER)",
			"  (edge pass OFF)" if noedge else "", freeze])

	var order: Array = []
	for s: Array in SHOTS:
		if not order.has(s[0]):
			order.append(s[0])

	var done := 0
	for level_name: String in order:
		var wanted: Array = []
		for s: Array in SHOTS:
			if s[0] == level_name and (only == "" or only in String(s[1])):
				wanted.append(s)
		if wanted.is_empty():
			continue
		clear_bucket_cache()
		var level := _load_level(level_name)
		if level == null:
			quit(1)
			return
		# The filter goes in the ROOT viewport, over the world, where hud.tscn
		# puts it when the game runs. A SubViewport is a different render
		# target and a shader that reads the screen is the one kind that can
		# tell — see the note in probe_shots_filtered.gd.
		var layer: CanvasLayer = null
		if mat != null:
			layer = CanvasLayer.new()
			layer.layer = 100
			var rect := ColorRect.new()
			rect.material = mat
			rect.anchor_right = 1.0
			rect.anchor_bottom = 1.0
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.add_child(rect)
			root.add_child(layer)
		var seen := root.get_visible_rect().size
		if int(seen.y) != HEIGHT:
			push_warning("mock_impacts: viewport is %dx%d, not %dx%d — the signal grid will not match the game's"
					% [int(seen.x), int(seen.y), WIDTH, HEIGHT])
		for _i in 60:
			await physics_frame
		var space := level.get_world_3d().direct_space_state
		var cam := Camera3D.new()
		cam.far = 4000.0
		level.add_child(cam)
		cam.make_current()

		for s: Array in wanted:
			var from: Vector3 = s[2]
			from.y += _ground(space, from.x, from.z)
			cam.fov = float(s[4])
			cam.position = from
			cam.look_at(s[3], Vector3.UP)

			var field := ImpactField.new()
			# The shot tool needs the tool-only ladder channels as well.
			field.spec_count = TRACER_SPECS.size()
			level.add_child(field)
			# Metres per screen pixel at one metre, from THIS camera's fov and
			# THIS viewport's height — so the apparent-width floor is in the
			# units the filter's edge pass actually works in.
			if not String(s[5]).begins_with("ladder") and String(s[5]) != "soft":
				field.eye = from
				field.m_per_px_at_1m = 2.0 * tan(deg_to_rad(float(s[4]) * 0.5)) / float(HEIGHT)
			var robot: Node3D = null
			var target: Vector3 = s[3]
			if String(s[5]) == "robot":
				robot = _stand_a_robot(level, space, s[3])
				if robot != null:
					# AIM AT WHERE THE ROBOT ENDED UP, not at where the shot
					# table guessed it would be. The table's y is absolute and
					# the robot's is derived from the ground, so the two
					# disagreed by whatever the terrain was doing there — and
					# the first render put every round in the mud behind it.
					target = robot.global_position + Vector3.UP * 0.25
					cam.look_at(target, Vector3.UP)
			await process_frame
			var staged := _stage(field, space, from, target, String(s[5]), freeze)
			print("   %-10s %-26s %d impact(s) at %.0f-%.0f m, %d tracer(s), %d recycled"
					% [level_name, s[1], field.impacts, _last_near, _last_far,
					field.tracers, field.recycled])
			# The near miss is MEANT to end on something far away — that is
			# what a miss is — so it is the one shot this warning is wrong for.
			if field.impacts > 0 and _last_near > 24.0 and String(s[5]) != "nearmiss":
				print("        ^ NOTHING IS CLOSER THAN %.0f m. The camera is almost certainly"
						% _last_near)
				print("          aimed through an opening and the effects are on a far wall.")
			# Two passes: the first frame off a fresh camera comes back blank
			# while the renderer warms, and the filter needs the warm one
			# because it reads the screen.
			for pass_i in 2:
				for _i in 12:
					await process_frame
				if pass_i == 1:
					root.get_texture().get_image().save_png(
							out.path_join("impact_%s%s.png" % [s[1], suffix]))
			done += 1
			if staged == 0:
				print("        (nothing staged — the camera may be looking at open sky)")
			level.remove_child(field)
			field.queue_free()
			if robot != null:
				level.remove_child(robot)
				robot.queue_free()
			await process_frame

		root.remove_child(level)
		level.queue_free()
		if layer != null:
			root.remove_child(layer)
			layer.queue_free()
		await process_frame
	print("   wrote %d shot(s) to %s" % [done, out])
	quit()


## Put the effects on the real geometry in front of the camera, by raycasting
## from the eye exactly as a round does. Nothing is placed at a typed
## coordinate — a decal floating a metre off the wall is the fault this avoids,
## and it is the one a hand-written position produces every time.
## Nearest and furthest thing the last staging pass actually hit, in metres.
var _last_near := 0.0
var _last_far := 0.0


func _stage(field: ImpactField, space: PhysicsDirectSpaceState3D, eye: Vector3,
		at: Vector3, what: String, freeze: float) -> int:
	seed(20261018)
	_last_near = 0.0
	_last_far = 0.0
	var aim: Vector3 = (at - eye).normalized()
	# The tracer sheets, by name. A LIST, not a prefix test: "ladder" was added
	# without a prefix, fell through to the impact path, and quietly rendered
	# seven bullet holes on a distant wall instead of the thickness ladder.
	const TRACER_SHEETS := ["vocab", "ab_bead", "ab_frac", "ab_faction", "ab_axis",
			"ladder", "soft", "incoming"]
	if TRACER_SHEETS.has(what):
		return _stage_tracers(field, eye, aim, what)
	if what == "none":
		field.settle(freeze)
		return 0

	# A BURST, NOT A VOLLEY. Rounds land `cadence` apart, and the field is
	# stepped between them, so the picture has the newest round's sparks still
	# hot, the one before it dying, and every pit from the whole burst. That is
	# what a burst actually looks like, and it is also the only way to see all
	# four channels at once — in a single volley they would share one age.
	var shots: int = 14
	var spread := 0.05
	var cadence := 0.12
	if what == "one":
		shots = 1
		spread = 0.0
	elif what == "firefight":
		shots = 180
		spread = 0.10
		cadence = 0.11
	elif what == "pen":
		shots = 10
		spread = 0.045
	elif what == "ground":
		shots = 20
		spread = 0.09
	elif what == "robot":
		shots = 9
		spread = 0.013
	elif what == "nearmiss":
		shots = 4
		spread = 0.004

	var placed := 0
	# HOW FAR AWAY THE THING IN THE PICTURE IS. Reported because a camera that
	# is aimed through a doorway stages its impacts on a wall sixty metres
	# behind it and still reports "26 impacts" — which is exactly what the
	# first run of this did, and the picture came back with nothing in it.
	# A render is evidence only if the thing is in it.
	_last_near = 1e9
	_last_far = 0.0
	for i in shots:
		var dir: Vector3 = aim
		if spread > 0.0:
			dir = (aim + Vector3(randf_range(-spread, spread),
					randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
		var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 160.0)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var d: float = eye.distance_to(hit["position"])
		_last_near = minf(_last_near, d)
		_last_far = maxf(_last_far, d)
		var bucket: int = bucket_of(hit["collider"], _struck(hit["collider"]))
		var through: bool = what == "pen" and (i % 2 == 0)
		field.impact(hit["position"], hit["normal"], dir, bucket, through)
		placed += 1
		if i < shots - 1:
			field.fly(cadence)

	# ISOLATE ONE CHANNEL by emptying the others, rather than by writing four
	# variants of impact(): the point of these pictures is to tell the human
	# which channel is doing the work, and a separate code path per picture
	# would be a picture of a separate thing.
	if what == "sparks":
		_mute(field, ["pit", "chip", "dust"])
	elif what == "pits":
		_mute(field, ["spark", "chip", "dust"])
	elif what == "chips":
		_mute(field, ["pit", "spark", "dust"])

	if what == "nearmiss":
		# The visual half of a near miss: rounds whipping past inside arm's
		# reach and going on downrange. The CRACK is audio and cannot be
		# photographed; this is what is left of the event that can.
		#
		# Backdated from a muzzle BEHIND the camera, so each round is caught a
		# metre or two in front of the eye rather than arriving exactly at it.
		var right: Vector3 = aim.cross(Vector3.UP).normalized()
		var speed: float = float(TRACER_SPECS[1][1])
		for i in 4:
			var lateral: float = [-0.9, -0.35, 0.45, 1.0][i]
			var rise: float = [0.35, -0.2, 0.15, 0.5][i]
			var muzzle: Vector3 = eye - aim * 70.0 + right * lateral + Vector3.UP * rise
			# flown 72 m puts the head about 2 m past the eye.
			field.fire_tracer(1, muzzle, aim, 300.0, (70.0 + 2.0 + float(i) * 1.1) / speed)
		field.settle(freeze)
		return placed

	field.settle(freeze)
	return placed


## The tracer sheets. Rounds are fired AT THEIR OWN CADENCE from a muzzle and
## then flown, so what is in the picture is what a burst actually looks like
## rather than a row of streaks placed by hand at a pleasing spacing. That
## distinction is the whole emergent-versus-authored question.
func _stage_tracers(field: ImpactField, eye: Vector3, aim: Vector3, what: String) -> int:
	var right: Vector3 = aim.cross(Vector3.UP).normalized()
	var fired := 0

	# ── THE CROSSING LANE ─────────────────────
	# Rounds are fired LEFT TO RIGHT across the view at a fixed depth, which
	# is the only way a streak has a length on screen. Everything is derived
	# from the camera rather than typed as world coordinates, so the same
	# staging works in any level.
	var depth := 26.0
	var start: Vector3 = eye + aim * depth - right * 34.0
	var path: Vector3 = right

	## One row of a sheet: a burst of `rounds` at `cd` apart, caught as one
	## instant. The k-th round is BACKDATED by k x cd, so its distance from the
	## muzzle is k x cd x speed — which is the cadence and nothing else.
	##
	## NOTHING IS PLACED BY HAND AT A PLEASING SPACING. That is the entire
	## emergent-versus-authored question: if these rows read as chains, the
	## chain is a consequence of fire rate and flight speed and costs nothing
	## to author.
	var row := func(spec_i: int, cd: float, rounds: int, height: float, every: int) -> int:
		var n := 0
		var origin: Vector3 = start + Vector3.UP * height
		for k in rounds:
			if k % every == 0:
				field.fire_tracer(spec_i, origin, path, 300.0, float(k) * cd)
				n += 1
		return n

	if what == "vocab":
		# One row per weapon class, stacked in height, each fired at its OWN
		# fire_cooldown for its own burst length. Stacked rather than side by
		# side because the shapes differ in LENGTH, and length is only
		# comparable along a common axis.
		var rows: Array = [0, 2, 3, 5, 6, 7]   # indices into WEAPON_CLASSES
		for ri in rows.size():
			var w: Array = WEAPON_CLASSES[rows[ri]]
			fired += row.call(int(w[1]), float(w[2]), int(w[3]) + 4, 0.4 + float(ri) * 1.6, 1)
		field.settle(0.0)
		return fired

	if what == "ab_bead":
		# TOP: the EMERGENT chain — several short rounds in flight at the
		# rapid class's own 0.11 s cadence. Nothing authored, no shader
		# pattern, no new asset: it is the cadence and the flight speed.
		# BOTTOM: the AUTHORED chain — one long streak with a dash pattern
		# cut into it by the fragment shader.
		fired += row.call(1, 0.11, 20, 4.2, 1)
		fired += row.call(5, 0.60, 4, 1.0, 1)
		field.settle(0.0)
		return fired

	if what == "ab_frac":
		# TOP: every round tracered. BOTTOM: one in five. Same burst, same
		# cadence — the only difference is how many are lit.
		fired += row.call(1, 0.11, 26, 4.2, 1)
		fired += row.call(1, 0.11, 26, 1.0, 5)
		field.settle(0.0)
		return fired

	if what == "ab_faction":
		# The same burst three times in the three faction colours, so "does
		# tyrian survive ten luma steps and five chroma steps" is asked of the
		# actual palette value rather than of a guess. Three specs are
		# borrowed as carriers so each row holds its own tint without a
		# material per round.
		for ri in FACTION_TINTS.size():
			var spec_i: int = [0, 1, 2][ri]
			field.tint_spec(spec_i, FACTION_TINTS[ri][1])
			fired += row.call(spec_i, 0.13, 16, 0.8 + float(ri) * 1.9, 1)
		field.settle(0.0)
		return fired

	if what == "ladder":
		# ── THE EDGE PASS EATS THIN BRIGHT THINGS ──
		#
		# signal_filter.gdshader ends with
		#     col = mix(col, edge_color, edge)
		# where edge_color is (0.02, 0.06, 0.06) — near black — and `edge`
		# comes from the largest LUMA STEP between a pixel and its four
		# neighbours. A hot streak one or two pixels wide against open sky is
		# a maximal luma step on EVERY pixel it owns, so the edge term
		# reaches its full 0.75 across the whole streak and three quarters of
		# a white tracer is replaced with near-black.
		#
		# The filter does not dim a thin bright object. It INVERTS it.
		#
		# A wide streak survives because its INTERIOR has no discontinuity:
		# only the rim is outlined, which is the effect the pass was written
		# for. So the question is purely one of apparent width, and this
		# ladder measures it rather than arguing about it: same burst, same
		# brightness, same range, five cross-sections.
		# Five rows that differ in ONE respect. The first attempt reused five
		# of the weapon specs, which differ in speed, length and colour as
		# well — so it compared five things at once and proved nothing about
		# any of them.
		for ri in 5:
			fired += row.call(LADDER_FIRST + ri, 0.09, 9, 0.6 + float(ri) * 1.5, 1)
		field.settle(0.0)
		return fired

	if what == "soft":
		# Bottom to top: hard 0.05, SOFT 0.05, hard 0.15, SOFT 0.15.
		var pairs: Array = [LADDER_FIRST + 1, SOFT_FIRST, LADDER_FIRST + 2, SOFT_FIRST + 1]
		for ri in pairs.size():
			fired += row.call(int(pairs[ri]), 0.09, 9, 0.8 + float(ri) * 1.8, 1)
		field.settle(0.0)
		return fired

	if what == "ab_axis":
		# THE FORESHORTENING PROOF. The same weapon, same cadence, twice: once
		# crossing the frame and once fired straight down the camera's own
		# axis. The second has no shape at all, which is why your OWN outgoing
		# fire can never carry the vocabulary — only incoming and flanking
		# fire can, and that is the half of it that matters anyway.
		fired += row.call(2, 0.12, 16, 3.6, 1)
		var muzzle: Vector3 = eye + Vector3(0.0, -0.3, 0.0) + right * 1.2
		for k in 16:
			field.fire_tracer(2, muzzle, aim, 300.0, float(k) * 0.12)
			fired += 1
		field.settle(0.0)
		return fired

	# "incoming": the receiving end — three shooters on different bearings,
	# converging on the eye at 1-in-5. The only picture here that is about the
	# game rather than about the effect.
	var bearings: Array = [-0.30, -0.02, 0.26]
	for bi in bearings.size():
		var dir: Vector3 = (aim + right * float(bearings[bi])).normalized()
		var origin: Vector3 = eye + dir * 80.0 + Vector3.UP * (3.0 + float(bi) * 0.8)
		var spec_i: int = [1, 2, 0][bi]
		var cd: float = [0.12, 0.12, 0.35][bi]
		var at_you: Vector3 = (eye + Vector3.UP * 0.4 - origin).normalized()
		for k in 22:
			if k % 5 == 0:
				field.fire_tracer(spec_i, origin, at_you, 120.0, float(k) * cd)
				fired += 1
	field.settle(0.0)
	return fired


## Park every slot of the named channels, so one picture shows one channel.
func _mute(field: ImpactField, channels: Array) -> void:
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for c: String in channels:
		var mm: MultiMesh = field.pit_mm
		var ages: PackedFloat32Array = field._pit_age
		if c == "spark":
			mm = field.spark_mm
			ages = field._spark_age
		elif c == "chip":
			mm = field.chip_mm
			ages = field._chip_age
		elif c == "dust":
			mm = field.dust_mm
			ages = field._dust_age
		for i in mm.instance_count:
			mm.set_instance_transform(i, zero)
			ages[i] = -1.0


## The ROBOT bucket's own test, as the weapon already does it.
func _struck(collider: Object) -> Node:
	var n := collider as Node
	if n == null:
		return null
	if n.has_method("apply_damage"):
		return n
	if n.get_parent() != null and n.get_parent().has_method("apply_damage"):
		return n.get_parent()
	return null


## One robot, standing in front of the camera and NOT thinking. process_mode
## DISABLED once it is placed: a robot that runs its AI during a render walks
## out of frame between the warm pass and the kept one.
func _stand_a_robot(level: Node3D, space: PhysicsDirectSpaceState3D, near: Vector3) -> Node3D:
	var packed := load(ROBOT_SCENE) as PackedScene
	if packed == null:
		push_warning("mock_impacts: %s will not load, so the robot bucket has no robot in it" % ROBOT_SCENE)
		return null
	var r := packed.instantiate() as Node3D
	level.add_child(r)
	# A CharacterBody3D's ORIGIN IS THE MIDDLE OF ITS CAPSULE, not its feet.
	# Placed at ground level the robot is buried to the waist, which is what
	# the first render of this shot showed — a dome sticking out of the mud.
	# Lifted by half the capsule, read off the scene rather than assumed.
	var lift := 1.0
	var shape := r.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape != null and shape.shape is CapsuleShape3D:
		lift = (shape.shape as CapsuleShape3D).height * 0.5
	else:
		push_warning("mock_impacts: %s has no capsule CollisionShape3D, so the lift is a guess" % ROBOT_SCENE)
	r.global_position = Vector3(near.x, _ground(space, near.x, near.z) + lift, near.z)
	# PROCESS_MODE_DISABLED ALSO TAKES THE BODY OUT OF THE PHYSICS WORLD.
	# It was the obvious way to stop the robot thinking, and it worked — the
	# robot stood still, rendered correctly, and every round aimed at it went
	# straight through and hit the ground eleven metres behind. The ROBOT
	# bucket cannot be demonstrated on a body the raycast cannot see.
	# Switching off the node's own callbacks leaves the collider registered.
	r.set_process(false)
	r.set_physics_process(false)
	r.set_process_internal(false)
	r.set_physics_process_internal(false)
	for child in r.get_children():
		if child is Node:
			(child as Node).set_process(false)
			(child as Node).set_physics_process(false)
	return r


func _load_level(level_name: String) -> Node3D:
	var path := "res://maps/%s_level.tscn" % level_name
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL  %s will not load" % path)
		return null
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	return level


## remove_child before the free: queue_free is deferred, and the next level
## would otherwise load into a tree that still holds this one.
func _drop_level(level: Node3D) -> void:
	root.remove_child(level)
	level.queue_free()


func _hud_filter() -> ShaderMaterial:
	var packed := load(HUD_SCENE) as PackedScene
	if packed == null:
		return null
	var state := packed.get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) != FILTER_NODE:
			continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) != "material":
				continue
			var m: Variant = state.get_node_property_value(i, j)
			if m is ShaderMaterial:
				# Duplicated so nothing here can write back into the HUD's own
				# resource if this tool ever grows a knob.
				return (m as ShaderMaterial).duplicate()
			return null
	return null


func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 1200.0, z), Vector3(x, -400.0, z))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		push_warning("mock_impacts: nothing under %.0f, %.0f — camera placed at y = 0" % [x, z])
		return 0.0
	return (hit["position"] as Vector3).y
