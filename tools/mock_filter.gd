extends SceneTree

# ─────────────────────────────────────────────────────────────────────
# MOCK FILTER — OUTGOING FEEDBACK ON THE SIGNAL FILTER
#
# The screen already flinches when you are HIT: hud.gd's damage_spike pushes
# the `damage` uniform past where signal loss alone has it, and `damage` costs
# you resolution, edges and packet integrity. Nothing moves the filter when a
# shot of YOURS lands. This renders candidate answers to that, all through the
# real shader, at the real resolution, from one camera.
#
#   godot --audio-driver Dummy --path . --script res://tools/mock_filter.gd \
#       -- docs/concepts
#
# NOT headless, and this is the whole reason the tool is shaped like this.
# signal_filter.gdshader samples hint_screen_texture. Under --headless there is
# no screen to sample, every fetch() returns black, and the PNG comes back a
# flat field that looks like a successful render of a dark scene. Three
# "the lighting is broken" investigations in this project were this shader; one
# of them was a probe reporting clean while the screenshot showed broken.
#
# THE UNIFORMS ARE READ OUT OF Character/hud/hud.tscn, NOT off the shader's
# declared defaults. They differ, today, in three places that all matter here:
#   palette_strength  scene 0.60   shader default 0.55
#   signal_fps        scene 8.0    shader default 15.0
#   dropout           scene 0.003  shader default 0.012
# A mock-up built on the shader defaults would be a picture of a different
# game — with four times the packet loss and artefacts crawling at twice the
# rate. Every variant below is expressed as a DELTA on whatever the scene says,
# so retuning hud.tscn retunes these pictures too.
#
# 1152 x 648 because that is what the game renders at: project.godot sets
# window/stretch/mode="viewport" and leaves the viewport at the default, so the
# game draws 648p and scales it to the window. The shader snaps to an integer
# grid of floor(height / signal_height) — 1 at 648p, 3 at 1080p — so a 1080p
# grab is a visibly chunkier picture than anybody plays.
#
# The eye is at 1.50 m above the collision under it, which is where the AKR's
# camera sits, so the framing is a standing drone's and not a flypast.
#
# Never writes campaign.json — CampaignManager.autosave off, and Settings
# redirected to a probe path, same as every other tool in this folder.
# ─────────────────────────────────────────────────────────────────────

const WIDTH := 1152
const HEIGHT := 648
const HUD_SCENE := "res://Character/hud/hud.tscn"
const FILTER_NODE := "SignalFilter"
const LEVEL := "res://maps/proving_level.tscn"

## Eye height of the player's camera, above whatever collision is under it.
const EYE := 1.50

## Down the causeway into the arena. CHOSEN BY LOOKING, not by reasoning: the
## proving-ground camera already in tools/probe_shots_filtered.gd (0, 1.5, 84)
## came back as a flat teal field, because at eye height it is inside the far
## wall — a picture of a wall, which would have said nothing about an effect
## whose whole job is edge definition and tonal steps, while looking like a
## successfully rendered dark scene.
##
## This frame has what the comparison needs: a lit stone floor in the mid
## tones, walls in two shades, a gantry and two mast silhouettes against a
## bright sky, and real shadow under the overpass. Ten luma steps have
## something to spend themselves on here.
const CAM_FROM := Vector3(0.0, EYE, 60.0)
const CAM_AT := Vector3(0.0, 4.0, 0.0)
const CAM_FOV := 62.0

## Two chassis in frame, at the same range, so a kill bloom scaled to target
## size has two sizes to be scaled to.
const SOLDIER := "res://Character/characters/ai/soldier_rifle.tscn"
const BULWARK := "res://Character/characters/ai/bulwark.tscn"

# ── THE EXISTING INCOMING NUMBERS, FOR THE BEFORE/AFTER ──────────────
# Read off hud.gd's exports rather than retyped, so the comparison frames
# cannot drift from the thing they are being compared against.
const DAMAGE_SPIKE_CAP := 0.3      # hud.gd damage_spike_cap
const DAMAGE_CEILING := 0.85       # hud.gd damage_ceiling
const SUPPRESSED := 0.55           # a plausible mid-firefight signal loss

# ── THE PROPOSAL'S OWN NUMBERS ───────────────────────────────────────
# An INDEPENDENT accumulator and an INDEPENDENT cap. Sharing hud.gd's would
# rebuild the known bug mirrored: the comment on damage_spike_cap records three
# rounds in one frame pinning the uniform at 1.0 and the screen going to
# unreadable static, photographed. Outgoing fire is denser than incoming, not
# sparser — see _print_burst_math() — so it needs its own ceiling, not a share
# of someone else's.
const CLARITY_SPIKE := 0.12        # per landed shot
const CLARITY_CAP := 0.35          # the most it may ever reach
const CLARITY_DECAY := 4.5         # per second — twice damage_spike_decay

## The fastest thing the player can hold the trigger on: pistol_hud_weapon.tscn
## FIRE_RATE = 0.015, which is 66.7 rounds a second — faster than the 60 Hz
## physics tick, so it can land more than one shot in a single frame.
const FASTEST_FIRE_RATE := 0.015


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = String(args[0]) if args.size() > 0 else "docs/concepts"
	DirAccess.make_dir_recursive_absolute(out_dir)

	Settings.path = "user://settings_probe_mock_filter.json"
	await process_frame

	var mat := _hud_filter()
	if mat == null:
		printerr("mock_filter: no %s ShaderMaterial in %s. The HUD has been rearranged and these pictures would be of nothing — refusing to render rather than writing a flat PNG that looks like proof." % [FILTER_NODE, HUD_SCENE])
		quit(1)
		return
	var base := _snapshot(mat)
	print("")
	print("  Filter read from %s:" % HUD_SCENE.get_file())
	for k in ["luma_levels", "chroma_levels", "edge_strength", "contrast",
			"saturation", "grain", "dropout", "block_glitch", "signal_fps",
			"palette_strength", "exposure"]:
		print("    %-18s %s" % [k, base.get(k, "(absent)")])

	_print_burst_math()

	# ── the scene ────────────────────────────────────────────────
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		printerr("mock_filter: %s will not load." % LEVEL)
		quit(1)
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)

	# The filter goes in the ROOT viewport, over the world, exactly where
	# hud.tscn puts it. A SubViewport was the obvious way to pin the
	# resolution and it is wrong here: a SubViewport is a different render
	# target, and a shader that reads the screen is the one kind that can tell.
	var layer := CanvasLayer.new()
	layer.layer = 100
	var rect := ColorRect.new()
	rect.material = mat
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	root.add_child(layer)

	# Colliders and anything that settles need frames before a raycast against
	# them means anything.
	for _i in 60:
		await physics_frame

	var seen := root.get_visible_rect().size
	if int(seen.y) != HEIGHT:
		push_warning("mock_filter: viewport is %dx%d, not %dx%d. The signal grid is floor(height / signal_height), so this is a DIFFERENT picture and not merely a bigger one — do not compare these frames to the game." % [
				int(seen.x), int(seen.y), WIDTH, HEIGHT])

	var space := level.get_world_3d().direct_space_state
	var cam := Camera3D.new()
	cam.far = 4000.0
	level.add_child(cam)
	cam.make_current()
	cam.fov = CAM_FOV
	var from := CAM_FROM
	from.y += _ground(space, from.x, from.z)
	cam.position = from
	cam.look_at(CAM_AT, Vector3.UP)

	# ── the cast ─────────────────────────────────────────────────
	# Two chassis at the same range, so "bigger target, bigger bloom" has two
	# targets to read against. Their faction is set but no AIManager exists
	# here, so they stand — which is what a mock-up wants: the camera must not
	# move between variants or the comparison is worthless.
	var sizes := {}
	# 14 m out, not 30. At 30 m a Soldier is eight pixels tall through a filter
	# that quantises to a 648p grid, and "the bloom is bigger on a Bulwark" is
	# not a judgement anyone can make about eight pixels.
	for spec in [[SOLDIER, Vector3(-3.5, 0.0, 46.0), "soldier"],
			[BULWARK, Vector3(4.0, 0.0, 46.0), "bulwark"]]:
		var bot = load(String(spec[0])).instantiate()
		level.add_child(bot)
		await process_frame
		var p: Vector3 = spec[1]
		p.y = _ground(space, p.x, p.z) + 0.2
		bot.global_position = p
		if "faction" in bot:
			bot.faction = Enums.Factions.ENEMY
		bot.look_at(Vector3(p.x, p.y, 70.0), Vector3.UP)
		for _i in 10:
			await physics_frame
		sizes[String(spec[2])] = _visual_height(bot)

	# BLOOM SCALE IS DERIVED, NOT TYPED. A typed table of chassis heights goes
	# stale the first time the art is rebuilt; this measures the visual AABB
	# that is actually standing in the frame.
	var h_soldier: float = maxf(float(sizes.get("soldier", 1.8)), 0.1)
	var h_bulwark: float = maxf(float(sizes.get("bulwark", 3.0)), 0.1)
	var ref: float = h_soldier
	print("")
	print("  Measured visual height in frame: soldier %.2f m, bulwark %.2f m" % [h_soldier, h_bulwark])
	print("  Bloom scale = height / soldier height, clamped to 2.0:")
	print("    soldier %.2f    bulwark %.2f" % [
			minf(h_soldier / ref, 2.0), minf(h_bulwark / ref, 2.0)])

	for _i in 30:
		await physics_frame

	# ── the variants ─────────────────────────────────────────────
	var variants: Array = [
		# WHAT THEY ALREADY HAVE. Three frames, so the proposal is judged
		# against the game rather than in isolation.
		["01_rest", "Resting state. damage = 0. The game as it ships.",
			_blend(base, 0.0, 0.0, {})],
		["02_suppressed", "Suppressed. damage = %.2f from signal loss. No hit, no spike." % SUPPRESSED,
			_blend(base, SUPPRESSED, 0.0, {})],
		["03_hit_flinch", "BEING HIT, at the existing cap. damage = %.2f." % DAMAGE_SPIKE_CAP,
			_blend(base, DAMAGE_SPIKE_CAP, 0.0, {})],

		# THE PROPOSAL.
		["04_clarify_half", "Landing a shot, half strength. clarity = %.3f." % (CLARITY_CAP * 0.5),
			_blend(base, 0.0, 0.5, {})],
		["05_clarify_cap", "Landing a shot, at the clarity cap %.2f. From rest." % CLARITY_CAP,
			_blend(base, 0.0, 1.0, {})],
		["06_clarify_over_suppressed",
			"THE CASE THAT MATTERS. Suppressed to %.2f AND landing shots at the cap." % SUPPRESSED,
			_blend(base, SUPPRESSED, 1.0, {})],

		# THE WORST CASE. Everything at once: held trigger landing, taking
		# return fire, link already down. If the screen is unreadable anywhere,
		# it is here.
		["07_everything_at_once",
			"WORST CASE. signal loss %.2f + incoming spike %.2f (clamped to ceiling %.2f) and outgoing clarity at the cap." % [SUPPRESSED, DAMAGE_SPIKE_CAP, DAMAGE_CEILING],
			_blend(base, minf(SUPPRESSED + DAMAGE_SPIKE_CAP, DAMAGE_CEILING), 1.0, {})],

		# THE ALTERNATIVES, so "it loses" is a thing the human can see rather
		# than a thing I assert.
		["08_kill_bloom_soldier",
			"ALTERNATIVE A — single-frame bloom on a kill, scaled to a Soldier (x%.2f)." % minf(h_soldier / ref, 2.0),
			_bloom(base, minf(h_soldier / ref, 2.0))],
		["09_kill_bloom_bulwark",
			"ALTERNATIVE A — the same bloom scaled to a Bulwark (x%.2f)." % minf(h_bulwark / ref, 2.0),
			_bloom(base, minf(h_bulwark / ref, 2.0))],
		["10_ekill_colour",
			"ALTERNATIVE B — e-kill as a colour shift, not a brightness spike. Palette only.",
			_ekill_colour(base)],
		["11_clarify_overcooked",
			"WHY %.2f AND NOT MORE. The same effect with luma_levels at 24 and edges at 1.6." % CLARITY_CAP,
			_overcooked(base)],
	]

	print("")
	print("  Shooting %d frames into %s" % [variants.size(), out_dir])
	for v in variants:
		_apply(mat, base, v[2] as Dictionary)
		# TWICE, AND THE SECOND KEPT. The first frame after a uniform change
		# comes off a screen texture that was filtered with the OLD values, and
		# this shader reads that texture — so pass one is a cross-fade of two
		# settings and pass two is the setting. The 12 frames per pass also let
		# the artefact clock at signal_fps = 8 advance, so a variant is not
		# judged on one frozen phase of static.
		for pass_i in 2:
			for _i in 12:
				await process_frame
			if pass_i == 1:
				await RenderingServer.frame_post_draw
				var img := root.get_texture().get_image()
				var path: String = out_dir.path_join("filter_%s.png" % v[0])
				var err := img.save_png(path)
				if err == OK:
					print("    %-34s %s" % [path.get_file(), v[1]])
				else:
					printerr("    could not write %s (%s)" % [path, error_string(err)])
	print("")
	print("  Done. These are pictures, not a verdict: whether the clarify flash")
	print("  FEELS like a reward is the human's call and nothing here measures it.")
	print("")
	quit(0)


# ─────────────────────────────────────────────────────────────────────
# THE PROPOSAL, AS UNIFORM MATHS
# ─────────────────────────────────────────────────────────────────────

## `damage` is the existing incoming axis, 0..damage_ceiling.
## `k` is the outgoing clarity, NORMALISED to 0..1 against CLARITY_CAP, so the
## cap is one number in one place and every frame here respects it.
##
## NOTE WHAT THIS DOES NOT TOUCH: the signal grid (signal_height), the palette
## tints, and chroma_divisor. The shader's own comments record three separate
## attempts at degrading via block size and palette banding, all of which read
## as a different art direction rather than a different signal. Clarifying has
## the same hazard in the other direction: grow the grid or move the tints on a
## landed shot and the world changes colour when you shoot, which is a bug
## wearing a feature's clothes.
func _blend(base: Dictionary, damage: float, k: float, extra: Dictionary) -> Dictionary:
	var kk: float = clampf(k, 0.0, 1.0)
	var out := {
		"damage": clampf(damage, 0.0, DAMAGE_CEILING),

		# MORE TONAL STEPS, which is the clarify. Going UP is the safe
		# direction: the shader's comment records posterising luma DOWN
		# snapping a smooth sky into two flat bands that landed on different
		# hues, with a hard seam between them. Adding steps cannot do that —
		# it only ever subdivides a band that already existed.
		"luma_levels": _f(base, "luma_levels", 10.0) + 8.0 * kk,
		"chroma_levels": _f(base, "chroma_levels", 5.0) + 3.0 * kk,

		# THE SILHOUETTES SNAP. The edge pass is what puts shape into low-poly
		# geometry with no internal detail; `damage` fades it to make things
		# hard to tell apart, so lifting it is the exact inverse of the
		# existing punish rather than a competing effect.
		"edge_strength": _f(base, "edge_strength", 0.75) + 0.50 * kk,
		"contrast": _f(base, "contrast", 1.12) + 0.08 * kk,
		"saturation": _f(base, "saturation", 0.9) + 0.10 * kk,

		# THE STATIC DROPS. These three are the ones hud.gd already owns and
		# already scales by the player's SCREEN NOISE option and by the incoming
		# spike. THEY MUST BE COMPOSED IN ONE PLACE. _apply_damage_uniform()
		# writes grain/dropout/block_glitch as base * noise * (1 + pulse*1.2);
		# a second function multiplying its own factor onto the material would
		# be writing over that every frame, and whichever ran last would win.
		# Shipping this means one write with both factors, not two writes.
		"grain": _f(base, "grain", 0.05) * (1.0 - 0.85 * kk),
		"dropout": _f(base, "dropout", 0.003) * (1.0 - kk),
		"block_glitch": _f(base, "block_glitch", 0.12) * (1.0 - 0.90 * kk),
	}
	for key in extra:
		out[key] = extra[key]
	return out


## ALTERNATIVE A — a one-frame bloom on a kill, scaled to the target.
## Exposure and the highlight tint, nothing structural.
func _bloom(base: Dictionary, scale: float) -> Dictionary:
	var hi: Color = base.get("high_tint", Color(0.87, 0.94, 0.72))
	var out := _blend(base, 0.0, 0.0, {})
	out["exposure"] = _f(base, "exposure", 1.05) + 0.45 * scale
	out["black_lift"] = _f(base, "black_lift", 0.05) + 0.10 * scale
	out["high_tint"] = hi.lerp(Color(1.0, 1.0, 0.94), minf(0.55 * scale, 0.9))
	return out


## ALTERNATIVE B — an e-kill reads as a HUE, so the two death types are
## distinguishable in peripheral vision without either being brighter.
## Palette only: no exposure, no extra steps, no edge change.
func _ekill_colour(base: Dictionary) -> Dictionary:
	var out := _blend(base, 0.0, 0.35, {})
	out["mid_tint"] = Color(0.24, 0.42, 0.58)
	out["high_tint"] = Color(0.70, 0.88, 1.0)
	out["shadow_tint"] = Color(0.05, 0.09, 0.15)
	return out


## Deliberately too far, so "0.35 is the number" is an argument with a picture
## behind it instead of a claim.
func _overcooked(base: Dictionary) -> Dictionary:
	var out := _blend(base, 0.0, 1.0, {})
	out["luma_levels"] = 24.0
	out["edge_strength"] = 1.6
	out["contrast"] = _f(base, "contrast", 1.12) + 0.25
	out["saturation"] = _f(base, "saturation", 0.9) + 0.35
	out["grain"] = 0.0
	return out


# ─────────────────────────────────────────────────────────────────────
# THE CAP, SHOWN RATHER THAN ASSERTED
# ─────────────────────────────────────────────────────────────────────

## Held trigger, every round landing, integrated at 60 Hz. The point is the
## number this saturates at, and that it is the cap and not 1.0.
func _print_burst_math() -> void:
	print("")
	print("  WORST-CASE BURST, integrated at 60 Hz. spike %.2f, cap %.2f, decay %.1f/s" % [
			CLARITY_SPIKE, CLARITY_CAP, CLARITY_DECAY])
	print("  Fastest player weapon is pistol_hud_weapon.tscn at FIRE_RATE %.3f s" % FASTEST_FIRE_RATE)
	print("  = %.1f rounds/s, which is MORE THAN ONE PER PHYSICS FRAME." % (1.0 / FASTEST_FIRE_RATE))
	print("")
	print("  %6s  %7s  %9s  %s" % ["t", "landed", "clarity", "uncapped would be"])
	var dt := 1.0 / 60.0
	var clarity := 0.0
	var uncapped := 0.0
	var t := 0.0
	var acc := 0.0
	var landed := 0
	for i in 61:          # one second of held trigger
		# Rounds due this frame. At 66.7 rps this is 1 most frames and 2 on
		# some — the case a per-hit spike with no cap cannot survive.
		acc += dt
		var n := 0
		while acc >= FASTEST_FIRE_RATE:
			acc -= FASTEST_FIRE_RATE
			n += 1
		landed += n
		clarity = minf(clarity + CLARITY_SPIKE * float(n), CLARITY_CAP)
		uncapped += CLARITY_SPIKE * float(n)
		clarity = maxf(clarity - dt * CLARITY_DECAY, 0.0)
		uncapped = maxf(uncapped - dt * CLARITY_DECAY, 0.0)
		t += dt
		if i % 10 == 0:
			print("  %5.2fs  %7d  %9.3f  %.2f" % [t, landed, clarity, uncapped])
	print("")
	print("  Saturates at the cap and stays there. Uncapped it reaches %.1f," % uncapped)
	print("  which would drive luma_levels past the shader's 32-step range and")
	print("  edge_strength past 2.0 — the mirror image of the incoming bug the")
	print("  damage_spike_cap comment records.")
	print("")
	print("  A SHOTGUN IS NOT NINE HITS. hud_weapon_template.gd already lands")
	print("  the per-shot bonus on the CENTRE round only (`struck`) and runs one")
	print("  suppression pass per shot, explicitly so a shotgun does not count")
	print("  eight times over. The clarity spike belongs on that same hook, so")
	print("  pellets=9 is one spike and not nine.")


# ─────────────────────────────────────────────────────────────────────
# RIG
# ─────────────────────────────────────────────────────────────────────

## Every uniform the scene sets, so a variant can be a delta on the authored
## values instead of a second copy of them.
func _snapshot(mat: ShaderMaterial) -> Dictionary:
	var out := {}
	if mat.shader == null:
		return out
	for u in mat.shader.get_shader_uniform_list():
		var name: String = String(u.get("name", ""))
		if name == "":
			continue
		var v: Variant = mat.get_shader_parameter(name)
		if v != null:
			out[name] = v
	return out


func _f(base: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = base.get(key)
	return float(v) if v != null else fallback


## Reset to the authored values first, THEN apply the delta. Without the reset
## a variant inherits whatever the previous one set for any key it does not
## mention, and the frames stop being comparable to each other — which is the
## entire point of the exercise.
func _apply(mat: ShaderMaterial, base: Dictionary, delta: Dictionary) -> void:
	for k in base:
		mat.set_shader_parameter(k, base[k])
	for k in delta:
		mat.set_shader_parameter(k, delta[k])


## The HUD's own filter material, read out of the scene file rather than by
## instantiating the HUD — hud.gd wants a player and a campaign that do not
## exist here. Duplicated, so nothing in this tool can write back into the
## resource the game ships.
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
				return (m as ShaderMaterial).duplicate()
			return null
	return null


## Top of the collision under x,z. Cast from above the tallest thing here.
func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 1200.0, z), Vector3(x, -400.0, z))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		# SAY SO. A camera placed off the end of the world photographs the sky,
		# which reads as a rendering fault rather than as a bad coordinate.
		push_warning("mock_filter: nothing under (%.1f, %.1f) in %s — the eye height is measured from 0 and the frame may be buried or floating." % [x, z, LEVEL])
		return 0.0
	return float((hit["position"] as Vector3).y)


## Height of a spawned chassis in metres, so bloom scale is derived from the
## thing standing in the frame rather than from a typed table that goes stale
## when the art is rebuilt.
##
## MEASURED OFF THE COLLISION SHAPE, NOT THE VISUALS. The first version walked
## VisualInstance3D.get_aabb() and reported a Soldier at 10.00 m and a Bulwark
## at 2.20 — so the bloom came out FOUR TIMES BIGGER for the smaller robot, and
## would have been reported as "size scaling does not read". It was reading the
## visibility AABB of the SparkBurst / OilSpray particle systems every chassis
## carries, which is sized for where sparks fly, not for the robot.
##
## Area3D subtrees are skipped for the same class of reason: the Detection area
## on a Soldier is a 25 m sphere.
func _visual_height(n: Node) -> float:
	var h := 0.0
	if n is Area3D:
		return 0.0
	if n is CollisionShape3D:
		var s: Shape3D = (n as CollisionShape3D).shape
		if s is CapsuleShape3D:
			h = maxf(h, (s as CapsuleShape3D).height)
		elif s is CylinderShape3D:
			h = maxf(h, (s as CylinderShape3D).height)
		elif s is BoxShape3D:
			h = maxf(h, (s as BoxShape3D).size.y)
		elif s is SphereShape3D:
			h = maxf(h, (s as SphereShape3D).radius * 2.0)
	for c in n.get_children():
		h = maxf(h, _visual_height(c))
	return h
