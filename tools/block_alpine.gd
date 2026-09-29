extends "res://tools/block_doodads.gd"

# ─────────────────────────────────────────────
# BLOCK ALPINE — dead wood and mountain ground cover, for scattering over the
# bare valleys on Hillfort and anywhere else above the treeline.
#
#   maps/blocks/alpine/alpine_*.map
#
#   godot --headless --path . --script res://tools/block_alpine.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_alpine.gd -- maps/blocks --force
#
# Built on block_doodads.gd, which this extends: the same brush kit, hull and
# no-overwrite rule. Build the prefabs with block_prefabs.gd afterwards.
#
# EVERYTHING HERE IS MEANT TO BE SCATTERED, and TerrainScatterLayer draws the
# scenes it is given as MultiMeshes — it takes their MESHES and ignores their
# collision, using its own `collision_radius` instead. So the collision in
# these pieces is for the hand-placed case only, and the small stuff carries
# none at all: a knee-high tussock with a collider punches a hole in the
# navmesh and fans triangles out across the ground around it.
#
# THE LOOK. Dead, not autumnal — snags, snapped trunks, root plates heaved out
# of thin soil, krummholz mats that gave up. Nothing here has leaves. The
# machines' world is grey and this is the brown in it, so it wants to be
# sparse and it wants to read at 200 m as a texture rather than as objects.
# ─────────────────────────────────────────────

const BARK := "PSX_Textures/wood_8"
const SPLIT := "PSX_Textures/wood_2"
const GRASS := "PSX_Textures/grass_7@0.5"
const SCREE := "PSX_Textures/rock_4"
const SOIL := "PSX_Textures/dirt_5"


func _initialize() -> void:
	var base := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
		else:
			print("ignoring argument '%s'" % a)
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_alpine.gd -- maps/blocks [--force]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var made := {
		"alpine_snag_tall": _snag_tall,
		"alpine_snag_broken": _snag_broken,
		"alpine_snag_leaning": _snag_leaning,
		"alpine_pine_dead": _pine_dead,
		"alpine_pine_skeleton": _pine_skeleton,
		"alpine_stump": _stump,
		"alpine_deadfall": _deadfall,
		"alpine_root_plate": _root_plate,
		"alpine_log_pile": _log_pile,
		"alpine_scrub": _scrub,
		"alpine_tussock": _tussock,
		"alpine_talus": _talus,
		"alpine_erratic": _erratic,
		"alpine_marker_post": _marker_post,
		"alpine_snag_forked": _snag_forked,
		"alpine_pine_flagged": _pine_flagged,
		"alpine_snag_short": _snag_short,
		"alpine_pine_spar": _pine_spar,
		"alpine_deadfall_snapped": _deadfall_snapped,
		"alpine_stump_burnt": _stump_burnt,
		"alpine_tussock_wide": _tussock_wide,
		"alpine_scrub_low": _scrub_low,
	}
	var dir := base.path_join("alpine")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var skipped := 0
	for name: String in made:
		var path := dir.path_join(name + ".map")
		if FileAccess.file_exists(path) and not force:
			print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
			skipped += 1
			continue
		_brushes = []
		# A piece that called no_collision() must not hand the flag to the next.
		_ghost_from = -1
		_entities = []
		(made[name] as Callable).call()
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		print("      %-24s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK ALPINE DONE%s" % ((" (%d skipped)" % skipped) if skipped > 0 else ""))
	quit()


# ── Parts ────────────────────────────────────────────────────────────────────

## A TAPERED limb between two points, in any direction: the hull of two rings.
## Everything woody here is one of these — trunk sections, branches, roots.
##
## Keep the narrow end at 0.06 m or more. Below that the ring rounds away to a
## single point on the 1/32 m grid, the hull has no volume, and solid() drops
## the brush with a warning instead of drawing a twig.
func limb(a: Vector3, b: Vector3, r0: float, r1: float, tex: Variant, sides: int = 6) -> void:
	if a.distance_to(b) < 0.1:
		return
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3(0, 0, 1) if absf(axis.z) < 0.9 else Vector3(1, 0, 0)).normalized()
	var v := axis.cross(u).normalized()
	var pts: Array = []
	for i in sides:
		var ang := TAU * (i + 0.5) / sides
		var o := u * cos(ang) + v * sin(ang)
		pts.append(a + o * maxf(r0, 0.06))
		pts.append(b + o * maxf(r1, 0.06))
	solid(pts, tex)


## A trunk from the ground up: `n` sections that taper and wander, so it leans
## and kinks the way a tree does instead of standing like a pipe. Returns the
## top, for whatever goes on it.
func trunk(base: Vector3, height: float, r_base: float, r_top: float, lean: Vector3,
		seed_value: int, n: int = 5, tex: Variant = BARK) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var at := base
	var r := r_base
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var wander := Vector3(rng.randf_range(-0.14, 0.14), rng.randf_range(-0.14, 0.14), 0.0) * height * 0.1
		var next := base + lean * (t1 * t1) + Vector3(0.0, 0.0, height * t1) + wander
		var r_next: float = lerpf(r_base, r_top, t1)
		limb(at, next, r, r_next, tex, 6 if t0 < 0.5 else 5)
		at = next
		r = r_next
	return at


## The flare where a trunk meets the ground: four or five roots running out and
## down. Thin soil on a mountain leaves these half exposed, which is most of
## what makes a dead tree look like it grew there.
func root_flare(base: Vector3, r: float, reach: float, seed_value: int, n: int = 5) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), sin(a), 0.0) * reach * rng.randf_range(0.7, 1.3)
		limb(base + Vector3(0.0, 0.0, r * 0.8), base + out + Vector3(0.0, 0.0, -r * 0.5),
				r * 0.55, r * 0.2, BARK, 5)


## Bare branches in a whorl, swept down and out the way a dead conifer's are.
func whorl(at: Vector3, count: int, reach: float, droop: float, thick: float,
		seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var a := TAU * i / count + rng.randf_range(-0.35, 0.35)
		var len_i := reach * rng.randf_range(0.6, 1.0)
		var out := Vector3(cos(a), sin(a), 0.0) * len_i
		var tip := at + out + Vector3(0.0, 0.0, -droop * len_i)
		limb(at, tip, thick, thick * 0.35, BARK, 4)
		# One fork on the longer branches, or the tree reads as a bottle brush.
		if len_i > reach * 0.8:
			var mid := at.lerp(tip, 0.55)
			limb(mid, mid + out * 0.5 + Vector3(0.0, 0.0, droop * len_i * 0.3),
					thick * 0.5, thick * 0.2, BARK, 4)


## A splintered break: spikes of pale inner wood standing out of the snapped
## end. What tells a snapped trunk from a cut one.
func splinters(at: Vector3, r: float, seed_value: int, n: int = 5) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.4, 0.4)
		var off := Vector3(cos(a), sin(a), 0.0) * r * rng.randf_range(0.2, 0.7)
		limb(at + off * 0.3, at + off + Vector3(0.0, 0.0, r * rng.randf_range(0.8, 2.4)),
				r * 0.3, r * 0.1, SPLIT, 4)


# ── The pieces ───────────────────────────────────────────────────────────────

## A bare standing trunk about 10 m, every branch long gone but the stubs.
## The backbone of the set: scatter these thinly and the valley stops reading
## as empty ground.
func _snag_tall() -> void:
	var top := trunk(Vector3.ZERO, 9.6, 0.46, 0.13, Vector3(0.5, -0.2, 0.0), 21, 6)
	root_flare(Vector3.ZERO, 0.46, 1.5, 22, 5)
	splinters(top, 0.16, 23, 4)
	no_collision()
	# Four stubs where branches broke off, at different heights and bearings.
	for i in 4:
		var z := 3.4 + i * 1.6
		var a := 1.1 + i * 2.2
		var at := Vector3(0.5 * (z / 9.6) * (z / 9.6), -0.2 * (z / 9.6) * (z / 9.6), z)
		limb(at, at + Vector3(cos(a), sin(a), -0.25) * (1.5 - i * 0.2), 0.16, 0.07, BARK, 4)


## Snapped off at chest height and a bit, the break still splintered. Reads at
## a distance as a post, which is what you want among the taller ones.
func _snag_broken() -> void:
	var top := trunk(Vector3.ZERO, 4.2, 0.52, 0.34, Vector3(-0.25, 0.3, 0.0), 31, 3)
	root_flare(Vector3.ZERO, 0.52, 1.7, 32, 5)
	splinters(top, 0.34, 33, 6)
	no_collision()
	limb(Vector3(0.0, 0.0, 2.1), Vector3(1.6, 0.7, 1.5), 0.17, 0.07, BARK, 4)


## Leaning hard, its uphill roots pulled clear of the soil. For slopes and the
## lips of cuts — it does most of its work as a silhouette.
func _snag_leaning() -> void:
	var top := trunk(Vector3.ZERO, 7.4, 0.42, 0.14, Vector3(2.6, 0.6, 0.0), 41, 5)
	splinters(top, 0.16, 42, 4)
	# Downhill roots still holding; uphill ones lifted and bare.
	for i in 3:
		var a := -0.9 + i * 0.9
		limb(Vector3(0.0, 0.0, 0.3), Vector3(cos(a), sin(a), 0.0) * 1.9 + Vector3(0.0, 0.0, -0.3),
				0.22, 0.08, BARK, 5)
	no_collision()
	for i in 3:
		var a := 2.3 + i * 0.8
		limb(Vector3(0.0, 0.0, 0.5), Vector3(cos(a), sin(a), 0.0) * 2.1 + Vector3(0.0, 0.0, 0.8),
				0.2, 0.07, BARK, 5)
	for i in 3:
		var z := 3.0 + i * 1.5
		var t := z / 7.4
		var at := Vector3(2.6 * t * t, 0.6 * t * t, z)
		limb(at, at + Vector3(cos(i * 2.4), sin(i * 2.4), -0.4) * 1.4, 0.14, 0.06, BARK, 4)


## A dead conifer with its branch whorls still on, twelve metres. The tallest
## thing in the set and the one that carries a skyline.
func _pine_dead() -> void:
	var top := trunk(Vector3.ZERO, 11.4, 0.5, 0.1, Vector3(0.3, 0.4, 0.0), 51, 7)
	root_flare(Vector3.ZERO, 0.5, 1.6, 52, 5)
	no_collision()
	for i in 6:
		var t := 0.32 + i * 0.11
		var z := 11.4 * t
		var at := Vector3(0.3 * t * t, 0.4 * t * t, z)
		whorl(at, 5 - int(i / 3), 2.9 - i * 0.34, 0.45, 0.16 - i * 0.015, 53 + i)
	limb(top, top + Vector3(0.1, 0.1, 0.9), 0.1, 0.06, BARK, 4)


## A smaller dead conifer, six and a half metres, branches closer together.
## Two sizes of the same tree is what stops a scatter looking stamped.
func _pine_skeleton() -> void:
	var top := trunk(Vector3.ZERO, 6.2, 0.36, 0.1, Vector3(-0.4, 0.2, 0.0), 61, 5)
	root_flare(Vector3.ZERO, 0.36, 1.2, 62, 4)
	no_collision()
	for i in 5:
		var t := 0.28 + i * 0.14
		var z := 6.2 * t
		var at := Vector3(-0.4 * t * t, 0.2 * t * t, z)
		whorl(at, 5, 2.0 - i * 0.26, 0.4, 0.13 - i * 0.014, 63 + i)
	limb(top, top + Vector3(-0.1, 0.0, 0.6), 0.09, 0.06, BARK, 4)


## A stump with its root flare and a splintered top. Goes anywhere, and a few
## of these among the snags implies the rest were taken.
func _stump() -> void:
	var top := trunk(Vector3.ZERO, 1.1, 0.6, 0.48, Vector3(0.1, 0.05, 0.0), 71, 2)
	root_flare(Vector3.ZERO, 0.6, 1.8, 72, 6)
	splinters(top, 0.48, 73, 7)


## A fallen trunk lying along X, roots at one end. Cover you can stand behind,
## and the piece that makes a slope look like it used to hold trees.
func _deadfall() -> void:
	# Slightly off the ground at the root end, settled at the tip.
	limb(Vector3(-4.2, 0.0, 0.75), Vector3(-1.0, 0.25, 0.55), 0.44, 0.38, BARK, 6)
	limb(Vector3(-1.0, 0.25, 0.55), Vector3(2.0, -0.1, 0.38), 0.38, 0.28, BARK, 6)
	limb(Vector3(2.0, -0.1, 0.38), Vector3(4.6, -0.4, 0.3), 0.28, 0.14, BARK, 5)
	# The root plate, stood on edge where it tore out.
	for i in 6:
		var a := TAU * i / 6.0 + 0.2
		limb(Vector3(-4.2, 0.0, 0.75),
				Vector3(-4.9, cos(a) * 1.3, 0.75 + sin(a) * 1.3), 0.2, 0.08, BARK, 4)
	no_collision()
	for i in 3:
		var x := -2.4 + i * 2.4
		limb(Vector3(x, 0.1, 0.5), Vector3(x + 0.6, 1.4 - i * 2.4, 0.9), 0.14, 0.06, BARK, 4)
	splinters(Vector3(4.6, -0.4, 0.3), 0.16, 74, 4)


## An upturned root plate with the trunk snapped short above it: a tree that
## went over and took its soil with it. Good on a lip or beside a washout.
func _root_plate() -> void:
	# The disc of soil and root, stood almost vertical.
	solid([Vector3(-0.35, -1.9, 0.0), Vector3(0.35, -1.9, 0.0),
			Vector3(-0.5, -1.6, 1.4), Vector3(0.5, -1.6, 1.4),
			Vector3(-0.55, 0.0, 2.5), Vector3(0.55, 0.0, 2.5),
			Vector3(-0.5, 1.6, 1.5), Vector3(0.5, 1.6, 1.5),
			Vector3(-0.35, 1.9, 0.1), Vector3(0.35, 1.9, 0.1)], SOIL)
	limb(Vector3(0.0, 0.0, 1.2), Vector3(0.9, 0.2, 3.1), 0.42, 0.3, BARK, 6)
	splinters(Vector3(0.9, 0.2, 3.1), 0.3, 81, 6)
	no_collision()
	for i in 7:
		var a := TAU * i / 7.0
		var out := Vector3(0.0, cos(a) * 2.0, 1.25 + sin(a) * 1.25)
		limb(Vector3(-0.2, cos(a) * 0.5, 1.2 + sin(a) * 0.5), out + Vector3(-0.5, 0.0, 0.0),
				0.17, 0.07, BARK, 4)


## Three trunks jammed together where they came down. A ready-made piece of
## cover, and it breaks up a slope better than three deadfalls side by side.
func _log_pile() -> void:
	limb(Vector3(-2.6, -0.9, 0.42), Vector3(2.8, -0.6, 0.38), 0.4, 0.26, BARK, 6)
	limb(Vector3(-2.2, 0.2, 0.44), Vector3(3.1, 0.6, 0.34), 0.36, 0.22, BARK, 6)
	limb(Vector3(-1.4, -0.2, 1.05), Vector3(2.4, 1.1, 0.95), 0.34, 0.2, BARK, 6)
	no_collision()
	limb(Vector3(-0.4, 0.0, 1.3), Vector3(-1.9, 1.6, 0.6), 0.14, 0.06, BARK, 4)
	splinters(Vector3(2.8, -0.6, 0.38), 0.14, 91, 3)
	splinters(Vector3(-2.2, 0.2, 0.44), 0.14, 92, 3)


## Krummholz: a wind-flattened mat of dead branches about three metres across
## and knee high. The commonest thing above the treeline and the piece that
## does the most for a bare valley floor.
func _scrub() -> void:
	no_collision()
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), sin(a), 0.0) * rng.randf_range(0.9, 1.6)
		limb(Vector3(0.0, 0.0, 0.18), out + Vector3(0.0, 0.0, rng.randf_range(0.25, 0.7)),
				0.13, 0.06, BARK, 4)
		limb(out * 0.6 + Vector3(0.0, 0.0, 0.4), out * 1.25 + Vector3(0.0, 0.0, 0.25),
				0.08, 0.06, BARK, 4)
	solid([Vector3(-0.45, -0.45, 0.0), Vector3(0.45, -0.45, 0.0), Vector3(0.45, 0.45, 0.0),
			Vector3(-0.45, 0.45, 0.0), Vector3(0.0, 0.0, 0.42)], BARK)


## A tussock of dead mountain grass, waist high at most. Mesh only and meant
## to go down in hundreds — set a visibility range on its layer.
func _tussock() -> void:
	no_collision()
	var rng := RandomNumberGenerator.new()
	rng.seed = 111
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.4, 0.4)
		var lean := Vector3(cos(a), sin(a), 0.0) * rng.randf_range(0.18, 0.42)
		solid([Vector3(cos(a) * 0.1, sin(a) * 0.1, 0.0),
				Vector3(cos(a + 2.1) * 0.12, sin(a + 2.1) * 0.12, 0.0),
				Vector3(cos(a + 4.2) * 0.1, sin(a + 4.2) * 0.1, 0.0),
				lean + Vector3(0.0, 0.0, rng.randf_range(0.35, 0.62))], GRASS)


## A patch of angular scree about four metres across, ankle deep. Mesh only:
## a knee-high stone with a collider punches a hole in the navmesh.
func _talus() -> void:
	no_collision()
	var rng := RandomNumberGenerator.new()
	rng.seed = 121
	for i in 14:
		var a := rng.randf_range(0.0, TAU)
		var d := sqrt(rng.randf()) * 1.9
		var c := Vector3(cos(a) * d, sin(a) * d, 0.0)
		var sz := rng.randf_range(0.16, 0.44)
		rock(c, Vector3(sz, sz * rng.randf_range(0.6, 1.2), sz * 0.55), 122 + i, SCREE, 7)


## A lone erratic, chest to head high, lichened on top. One of these among the
## dead wood gives a scatter something that is not a tree.
func _erratic() -> void:
	rock(Vector3(0.0, 0.0, 0.2), Vector3(1.7, 1.45, 1.05), 131, ROCK, 13)
	no_collision()
	rock(Vector3(0.1, -0.1, 1.05), Vector3(1.1, 0.95, 0.18), 132, STRATA, 9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 133
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		rock(Vector3(cos(a) * rng.randf_range(1.6, 2.4), sin(a) * rng.randf_range(1.6, 2.4), -0.05),
				Vector3(0.34, 0.3, 0.2), 134 + i, SCREE, 7)


## A route marker: a post with a cross-board and a lit band, of the kind the
## machines would leave along a road they graded. The one made thing in the
## set — a scatter of pure nature reads as wilderness, and this is not that.
func _marker_post() -> void:
	limb(Vector3(0.0, 0.0, 0.0), Vector3(0.06, 0.03, 2.6), 0.11, 0.08, BARK, 5)
	no_collision()
	box(Vector3(-0.32, -0.05, 2.15), Vector3(0.32, 0.05, 2.45), SPLIT)
	# Proud of the board's face by 40 mm, not skinned onto it: under 1/32 m a
	# box builds as nothing, and flush with the face it would z-fight.
	box(Vector3(-0.3, -0.09, 2.24), Vector3(0.3, -0.05, 2.34), "PSX_Textures/glitch_tx_1@0.5")
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		rock(Vector3(cos(a) * 0.4, sin(a) * 0.4, -0.02), Vector3(0.26, 0.22, 0.16), 141 + i, SCREE, 7)


# ── Variants ─────────────────────────────────────────────────────────────────
#
# WHY THERE ARE THIS MANY. A scatter layer varies yaw and scale and nothing
# else, so the only thing that breaks up a hillside is the number of distinct
# SILHOUETTES in the list. Five standing trees at nine a hectare repeats badly;
# nine does not. Each of these is a different outline on purpose — a fork, a
# one-sided flag, a squat stub, a bare spar — not another pass at the same
# tree with the seed changed.


## A trunk that forks into two leaders at half height. The most useful variant
## in the set: nothing else here makes a Y against the sky.
func _snag_forked() -> void:
	var fork := trunk(Vector3.ZERO, 4.6, 0.5, 0.33, Vector3(0.2, -0.3, 0.0), 151, 3)
	root_flare(Vector3.ZERO, 0.5, 1.6, 152, 5)
	var a := trunk(fork, 4.4, 0.26, 0.1, Vector3(1.9, 0.5, 0.0), 153, 3)
	var b := trunk(fork, 3.5, 0.24, 0.1, Vector3(-1.5, -0.9, 0.0), 154, 3)
	splinters(a, 0.11, 155, 3)
	splinters(b, 0.11, 156, 3)
	no_collision()
	for i in 3:
		var z := 5.8 + i * 1.3
		limb(Vector3(0.9 + i * 0.3, 0.2, z), Vector3(2.2 + i * 0.4, 1.3 - i * 0.9, z - 0.4),
				0.13, 0.06, BARK, 4)


## Wind-flagged: branches on one side only, the windward side scoured bare.
## The most alpine shape there is, and it reads from a long way off.
func _pine_flagged() -> void:
	var top := trunk(Vector3.ZERO, 9.2, 0.42, 0.11, Vector3(1.1, 0.2, 0.0), 161, 6)
	root_flare(Vector3.ZERO, 0.42, 1.4, 162, 5)
	no_collision()
	var rng := RandomNumberGenerator.new()
	rng.seed = 163
	for i in 6:
		var t := 0.3 + i * 0.115
		var z := 9.2 * t
		var at := Vector3(1.1 * t * t, 0.2 * t * t, z)
		# A 120° arc downwind instead of a full whorl.
		for j in 3:
			var ang := 0.6 + j * 0.5 + rng.randf_range(-0.2, 0.2)
			var reach := (2.6 - i * 0.3) * rng.randf_range(0.7, 1.0)
			limb(at, at + Vector3(cos(ang), sin(ang), -0.35) * reach,
					0.15 - i * 0.015, 0.06, BARK, 4)
	splinters(top, 0.11, 164, 3)


## A squat broken stub, chest high and wide. Fills the gap between the stump
## and the snapped trunk, and gives the low end of the scatter something that
## is not a rock.
func _snag_short() -> void:
	var top := trunk(Vector3.ZERO, 2.6, 0.72, 0.58, Vector3(0.2, 0.15, 0.0), 171, 2)
	root_flare(Vector3.ZERO, 0.72, 2.1, 172, 6)
	splinters(top, 0.58, 173, 8)
	no_collision()
	limb(Vector3(0.0, 0.0, 1.5), Vector3(1.5, -1.1, 1.1), 0.2, 0.08, BARK, 4)


## The tallest thing in the set at fourteen metres, and nearly bare — two
## whorls left at the top and a long clean spar below. Scatter one of these
## per grove and it does the work of a landmark.
func _pine_spar() -> void:
	var top := trunk(Vector3.ZERO, 13.6, 0.52, 0.09, Vector3(-0.6, 0.5, 0.0), 181, 8)
	root_flare(Vector3.ZERO, 0.52, 1.7, 182, 6)
	no_collision()
	for i in 2:
		var t := 0.74 + i * 0.1
		var at := Vector3(-0.6 * t * t, 0.5 * t * t, 13.6 * t)
		whorl(at, 4, 1.7 - i * 0.4, 0.5, 0.11, 183 + i)
	for i in 3:
		var z := 4.0 + i * 2.2
		var t := z / 13.6
		var at := Vector3(-0.6 * t * t, 0.5 * t * t, z)
		limb(at, at + Vector3(cos(i * 2.1), sin(i * 2.1), -0.3) * 1.1, 0.12, 0.06, BARK, 4)
	splinters(top, 0.09, 186, 3)


## A fallen trunk that broke over something on the way down, the two halves at
## an angle to each other. Reads differently from the straight deadfall at any
## yaw, which is the whole point of it.
func _deadfall_snapped() -> void:
	limb(Vector3(-3.6, -0.6, 0.5), Vector3(-0.4, 0.0, 1.15), 0.4, 0.3, BARK, 6)
	limb(Vector3(-0.4, 0.0, 1.15), Vector3(3.4, 1.4, 0.36), 0.28, 0.15, BARK, 5)
	# What it broke over.
	rock(Vector3(-0.3, 0.1, 0.35), Vector3(0.9, 0.8, 0.7), 191, ROCK, 11)
	no_collision()
	splinters(Vector3(-0.4, 0.0, 1.15), 0.16, 192, 5)
	for i in 2:
		limb(Vector3(-2.2 + i * 3.0, -0.3 + i * 0.8, 0.7),
				Vector3(-1.6 + i * 3.4, -1.6 + i * 2.6, 1.0), 0.13, 0.06, BARK, 4)


## A stump burnt out to a shell: black, shattered, the inside gone. One of
## these in ten says what happened to the rest of the trees.
func _stump_burnt() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 201
	# A broken ring rather than a drum — it is what is left of the outside.
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.12, 0.12)
		var h := rng.randf_range(0.5, 1.5)
		var o := Vector3(cos(a), sin(a), 0.0)
		limb(Vector3.ZERO + o * 0.45, o * 0.34 + Vector3(0.0, 0.0, h), 0.2, 0.13, SCORCH, 4)
	root_flare(Vector3.ZERO, 0.55, 1.9, 202, 5)
	no_collision()
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		rock(Vector3(cos(a) * rng.randf_range(0.8, 1.7), sin(a) * rng.randf_range(0.8, 1.7), -0.03),
				Vector3(0.22, 0.2, 0.12), 203 + i, SCORCH, 7)


## A broader, flatter grass clump. Two tussocks at 240 a hectare is the
## difference between ground cover and wallpaper.
func _tussock_wide() -> void:
	no_collision()
	var rng := RandomNumberGenerator.new()
	rng.seed = 211
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.35, 0.35)
		var lean := Vector3(cos(a), sin(a), 0.0) * rng.randf_range(0.3, 0.68)
		solid([Vector3(cos(a) * 0.14, sin(a) * 0.14, 0.0),
				Vector3(cos(a + 2.1) * 0.16, sin(a + 2.1) * 0.16, 0.0),
				Vector3(cos(a + 4.2) * 0.14, sin(a + 4.2) * 0.14, 0.0),
				lean + Vector3(0.0, 0.0, rng.randf_range(0.2, 0.38))], GRASS)


## A small krummholz mat, half the size of the other one and lower. Scrub at
## two sizes stops a slope looking stencilled.
func _scrub_low() -> void:
	no_collision()
	var rng := RandomNumberGenerator.new()
	rng.seed = 221
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.35, 0.35)
		var out := Vector3(cos(a), sin(a), 0.0) * rng.randf_range(0.5, 1.0)
		limb(Vector3(0.0, 0.0, 0.12), out + Vector3(0.0, 0.0, rng.randf_range(0.15, 0.4)),
				0.1, 0.06, BARK, 4)
	solid([Vector3(-0.3, -0.3, 0.0), Vector3(0.3, -0.3, 0.0), Vector3(0.3, 0.3, 0.0),
			Vector3(-0.3, 0.3, 0.0), Vector3(0.0, 0.0, 0.26)], BARK)
