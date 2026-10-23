extends RefCounted
class_name ConceptsCore

# ─────────────────────────────────────────────
# CONCEPT BUILDERS — THE COMPUTE CORE OBJECTIVE. Five concepts, three sizes
# each, fifteen builders.
#
# THIS IS ARCHITECTURE, NOT A ROBOT. Nothing here touches concept_kit.gd's
# frame vocabulary — no head(), no legs, no chamfered hull. The shipped cores
# are TrenchBroom brush geometry built by the TERRAIN lane out of
# tools/block_industrial.gd's core_column(); these are drawn with CSG
# primitives only because CSG is what the icon studio can photograph. Read
# every shape below as "a brush would go here", not as a mesh to export. That
# is also why there are no curves worth the name: a cylinder here stands for a
# 12- or 16-sided brush drum, which is what compute_chiller_yard already uses.
#
# CONVENTIONS, stated so nobody has to infer them from the numbers:
#
#   GROUND IS y = 0 and every builder stands ON it. The renderer puts a
#   3.81 m Walker on the same plane, so if a concept floats it will be obvious.
#
#   FRONT IS -Z. The player approaches from -Z and the APPROACH FACE — the
#   niche, alcove, bay or console the interact raycast has to hit — always
#   faces that way, centred on x = 0, with its lit plate between y 1.1 and
#   y 2.0. That band is not decoration: the raycast is 2 m long and starts at
#   the camera, so anything the player can press has to be a vertical face
#   standing within 2 m of where the core's own collision stops him.
#
#   SIZE MEANS HEIGHT. The shipped trio is quoted 4.2 / 7.0 / 12.4 m and those
#   are heights — the footprints are 1.9, 3.4 and 5.2 m square. Every concept
#   below hits the three heights; what the concepts disagree about is whether
#   anything ELSE is allowed to change with them.
#
# THE QUESTION ALL FIFTEEN EXIST TO ASK: one form scaled, or three forms?
# A and B say one form, by two different arguments. C, D and E say three.
# docs/concepts/archive/COMPUTE_CORES.md carries the argument; this file carries the
# geometry.
# ─────────────────────────────────────────────

const _Parts := preload("res://tools/mockup_parts.gd")
const DEG := PI / 180.0

## The heights the shipped trio is quoted at. Builders are tuned to land on
## these, and the renderer prints what they actually measured — if the two
## disagree, believe the renderer.
const H_SMALL := 4.2
const H_MEDIUM := 7.0
const H_LARGE := 12.4


# ─────────────────────────────────────────────
# SHARED FITTINGS
#
# The family tells, lifted out of maps/blocks/compute: a stepped concrete
# plinth, battered cage posts, cable risers up the back, drum chillers with a
# fan ring, cable trays on stands, and handrails. Every concept is built from
# these so that five different silhouettes still read as one installation.
# ─────────────────────────────────────────────

## A two-step concrete plinth, top face at `h`. The step is what stops a slab
## from looking like it was dropped on the ground.
static func _plinth(to: Node, hw: float, hd: float, h: float) -> void:
	_Parts.box(to, Vector3(hw * 2.0, h * 0.55, hd * 2.0), Vector3(0, h * 0.275, 0))
	_Parts.box(to, Vector3(hw * 1.8, h * 0.5, hd * 1.8), Vector3(0, h * 0.75, 0))


## THE APPROACH FACE, and the one fitting that is identical on all fifteen
## builders. A recess cut into a face, with a lit plate set INTO the recess
## rather than laid on the wall — two faces on one plane fight over which you
## see, which is the same note _core_head carries in block_industrial.gd.
##
## `into` must be the CSG body being cut: the subtraction is parented to it, and
## a subtraction parented to a bare Node3D cuts nothing and warns about it.
## `face_z` is the body-local z of the face being cut, and the cut goes in +Z.
static func _console(into: CSGShape3D, face_z: float, w: float = 1.5) -> void:
	if not (into is CSGShape3D):
		push_warning("_console: nothing to cut into, so no approach face was drawn")
		return
	var cut := _Parts.box(into, Vector3(w, 0.9, 0.5), Vector3(0, 1.55, face_z + 0.24))
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	# The plate, sunk 0.06 into the back of the recess. This is the thing the
	# raycast hits and the thing the player's eye lands on.
	_Parts.plate(into.get_parent(), w * 0.8, 0.62, 0.1, 0.1,
			into.position + Vector3(0, 1.55, face_z + 0.42))
	# A kick rail under it, so there is a horizontal at knee height saying
	# "stand here" rather than a hole in a wall.
	_Parts.box(into.get_parent(), Vector3(w * 0.95, 0.09, 0.14),
			into.position + Vector3(0, 1.02, face_z - 0.06))


## Battered cage posts at the four corners, leaning in by `lean` over the rise.
## Four separate boxes rather than a frame: that is how they are brushed.
static func _cage(to: Node, hw: float, hd: float, y0: float, y1: float,
		post: float, lean: float) -> void:
	var rise := y1 - y0
	if rise <= 0.0:
		push_warning("_cage: %.2f m of rise, so no posts were drawn" % rise)
		return
	# THE SIGNS. A rotation of t about Z takes +Y to (-sin t, cos t), so the top
	# of a post moves in -X for a POSITIVE angle: the +X post needs +t to lean
	# IN. About X, +Y goes to (0, cos t, sin t), so the +Z post needs -t. Drawn
	# with these the other way round, which is what the first pass did, every
	# cage and every pylon on the sheet splayed outward like a derrick stood on
	# its head — and it is not subtle, it is the first thing you see.
	var tilt: float = atan2(lean, rise)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_Parts.box(to, Vector3(post, rise, post),
					Vector3(sx * (hw - lean * 0.5), y0 + rise * 0.5, sz * (hd - lean * 0.5)),
					Vector3(-sz * tilt, 0, sx * tilt))


## Two cable risers and their tie, up the BACK face. The front is where a body
## works; the back is where the pipework goes, and a blank back face is the
## thing that makes a slab read as a placeholder.
static func _risers(to: Node, hw: float, back_z: float, y0: float, y1: float,
		r: float) -> void:
	for sx: float in [-1.0, 1.0]:
		_Parts.cyl(to, r, y1 - y0, Vector3(sx * hw * 0.5, (y0 + y1) * 0.5, back_z + r))
	_Parts.box(to, Vector3(hw * 1.1, r * 2.2, r * 2.2), Vector3(0, y1, back_z + r))


## A drum chiller: a squat cylinder with a fan ring recessed in its lid and a
## stand under it. compute_chiller_yard's whole read is a field of these, so
## one of them anywhere says "cooling" before any label does.
static func _drum(to: Node, at: Vector3, r: float, h: float) -> void:
	_Parts.box(to, Vector3(r * 1.9, 0.18, r * 1.9), at + Vector3(0, 0.09, 0))
	_Parts.cyl(to, r, h, at + Vector3(0, 0.18 + h * 0.5, 0), Vector3.ZERO, false, 12)
	# The fan ring is SUNK INTO the lid, not sat on it: a torus laid on the top
	# face stands half its own thickness proud and quietly adds 0.12 m to the
	# measured height of everything a drum is the tallest thing on.
	_Parts.ring(to, r * 0.42, r * 0.66, at + Vector3(0, 0.18 + h - 0.07, 0))


## A cable tray on stands, running along x at height `y`. Flat bar plus two
## legs per bay; this is compute_cable_run's language brought up off the floor.
static func _tray(to: Node, x0: float, x1: float, z: float, y: float) -> void:
	var span: float = absf(x1 - x0)
	_Parts.box(to, Vector3(span, 0.12, 0.44), Vector3((x0 + x1) * 0.5, y, z))
	for s: float in [0.12, 0.88]:
		var x: float = lerpf(x0, x1, s)
		_Parts.box(to, Vector3(0.14, y, 0.14), Vector3(x, y * 0.5, z))


## A handrail: posts and two bars. Nothing says "people serviced this" cheaper,
## and it is the one fitting that is always robot-scale whatever the core is.
static func _rail(to: Node, x0: float, x1: float, z: float, y0: float) -> void:
	var posts: int = maxi(2, int(absf(x1 - x0) / 1.6) + 1)
	for i in posts:
		var x: float = lerpf(x0, x1, float(i) / float(posts - 1))
		_Parts.box(to, Vector3(0.1, 1.05, 0.1), Vector3(x, y0 + 0.525, z))
	for h: float in [0.52, 1.0]:
		_Parts.box(to, Vector3(absf(x1 - x0), 0.07, 0.07),
				Vector3((x0 + x1) * 0.5, y0 + h, z))


## A lattice bay: four uprights already exist, this adds the X bracing on one
## face between two heights. Drawn as two crossed bars, because a real brush
## lattice is exactly that and nothing finer survives at 40 m.
static func _brace(to: Node, hw: float, z: float, y0: float, y1: float,
		bar: float) -> void:
	var rise := y1 - y0
	var ang: float = atan2(rise, hw * 2.0)
	var diag: float = sqrt(rise * rise + hw * hw * 4.0)
	for s: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(diag, bar, bar), Vector3(0, (y0 + y1) * 0.5, z),
				Vector3(0, 0, s * ang))
	# The tie sits UNDER the bay's top, not on it. On it, the topmost bay's tie
	# is the highest thing in the model and the pylon measures half a bar over
	# the height it was drawn to.
	_Parts.box(to, Vector3(hw * 2.0, bar, bar), Vector3(0, y1 - bar * 0.5, z))


## A ramp up onto a raised deck, front face, so a robot can actually get on it.
## move_and_slide has no step-up: a vertical face of ANY height stops a body
## dead, which is the note yard_slab() carries in block_industrial.gd and the
## reason the large concepts here are not simply slabs with a lip.
static func _ramp(to: Node, w: float, z_front: float, deck_y: float) -> void:
	var run: float = deck_y * 5.0
	var ang: float = atan2(deck_y, run)
	var leng: float = sqrt(deck_y * deck_y + run * run)
	_Parts.box(to, Vector3(w, 0.22, leng),
			Vector3(0, deck_y * 0.5 - 0.06, z_front - run * 0.5), Vector3(ang, 0, 0))


# ─────────────────────────────────────────────
# A — CASSETTE STACK.  POSITION: ONE FORM, SCALED.
#
# The shipped core, restated with one rule added: THE CASSETTE IS A CONSTANT
# 1.0 m AT EVERY SIZE. Today the module scales with the column, so three sizes
# produce three identical photographs; hold the module and the small core is a
# stack of three, the medium a stack of five, the large a stack of nine. The
# silhouette does not change — the COUNT does, and a count is something the eye
# reads without a reference object in frame.
#
# Everything else is block_industrial.gd's core_column verbatim: stepped
# plinth, collar, lit gap under every cassette, service alcove in the bottom
# one, battered cage, risers up the back, sheared head.
# ─────────────────────────────────────────────

const _MOD := 1.0      ## cassette height. THE RULER. Do not scale this.
const _GAP := 0.26     ## the lit slot under each cassette.
const _PAD := 0.22     ## plinth top.


static func _stack(to: Node3D, cw: float, modules: int, target: float) -> void:
	# The collar takes up whatever the whole modules do not, so the column
	# lands on the quoted height without the module drifting.
	var collar: float = target - _PAD - float(modules) * (_MOD + _GAP)
	if collar < 0.15:
		push_warning("_stack: %d modules do not fit under %.1f m, so nothing was drawn" % [modules, target])
		return
	var pw: float = cw * 0.68
	_plinth(to, pw, pw, _PAD)
	_Parts.box(to, Vector3(pw * 1.3, collar, pw * 1.3), Vector3(0, _PAD + collar * 0.5, 0))

	var y: float = _PAD + collar
	for i in modules:
		# The lit slot goes UNDER each cassette, including the first: the stack
		# stands off its collar with light beneath it instead of growing out of
		# the concrete.
		_Parts.box(to, Vector3(cw * 1.36, _GAP, cw * 1.36), Vector3(0, y + _GAP * 0.5, 0))
		y += _GAP
		var body := _Parts.box(to, Vector3(cw * 2.0, _MOD, cw * 2.0),
				Vector3(0, y + _MOD * 0.5, 0))
		if i == modules - 1:
			# The sheared head: a slice off the front top. A SUBTRACTION, so
			# the measured height is still the back edge, which is the height
			# the level designer placed it at.
			var shear := _Parts.box(body, Vector3(cw * 3.0, cw * 2.2, cw * 2.2),
					Vector3(0, _MOD * 0.5 + cw * 0.88, -cw * 1.5), Vector3(38.0 * DEG, 0, 0))
			shear.operation = CSGShape3D.OPERATION_SUBTRACTION
		elif i == 0:
			_console(body, -cw, minf(cw * 1.3, 1.6))
		else:
			# Louvre ribs on the flanks, so the middle of a nine-high stack is
			# not nine blank boxes.
			for sx: float in [-1.0, 1.0]:
				for k in 2:
					_Parts.box(to, Vector3(0.08, 0.12, cw * 1.5),
							Vector3(sx * cw + sx * 0.04, y + 0.34 + float(k) * 0.34, 0))
		y += _MOD

	var post: float = clampf(cw * 0.17, 0.1, 0.3)
	var pc: float = cw + post * 0.35
	_cage(to, pc, pc, _PAD, y - cw * 0.5, post, cw * 0.1)
	_risers(to, cw, cw, _PAD, y - _MOD * 0.6, clampf(cw * 0.09, 0.06, 0.16))


static func a_small(to: Node3D) -> void:
	_stack(to, 0.95, 3, H_SMALL)


static func a_medium(to: Node3D) -> void:
	_stack(to, 1.7, 5, H_MEDIUM)


static func a_large(to: Node3D) -> void:
	_stack(to, 2.6, 9, H_LARGE)


# ─────────────────────────────────────────────
# B — MAST AND DESK.  POSITION: ONE FORM, SCALED — with a ruler bolted to it.
#
# A battered mast out of compute_monolith's language, and in front of it a
# CONSOLE THAT NEVER CHANGES SIZE: 1.6 m of desk, a canopy at 2.4 m, a handrail
# and a cable tray, built once at robot scale and bolted to all three. The mast
# scales; the furniture does not.
#
# The argument is that a scaled form is only unreadable because there is
# nothing in it of known size. Put a known size IN the silhouette and the same
# shape at three heights reads as three heights. It also buys something
# gameplay wants: the approach face is at the same place, the same size, at
# every size, so one reach_size serves all three.
# ─────────────────────────────────────────────

static func _mast(to: Node3D, mw: float, target: float) -> void:
	var base: float = 0.25
	_plinth(to, mw * 1.45, mw * 1.45, base)
	# Battered in three stages. Stacked boxes rather than a true frustum,
	# because that is how a brush mast is cut and a tapered brush's side quads
	# go non-planar on this grid — block_ai_infra.gd's drums carry the same
	# note.
	# A BATTER, NOT A ZIGGURAT. The first pass took 16% off the width at each of
	# three stages and photographed as a wedding cake — three boxes, not one
	# mast. 7% over equal thirds is a lean you read without being able to point
	# at where it happens, which is what compute_monolith does.
	var rise: float = target - base
	var y: float = base
	var w: float = mw
	for i in 3:
		var seg: float = rise / 3.0
		var stage := _Parts.box(to, Vector3(w * 2.0, seg, w * 1.7),
				Vector3(0, y + seg * 0.5, 0))
		# A GROOVE UP THE FRONT, through every stage. Without it three stacked
		# boxes read as three stacked boxes however small the step between them
		# is; one continuous vertical line through all three is what makes the
		# eye take them as one mast, and it is the monolith's own tell.
		var groove := _Parts.box(stage, Vector3(w * 0.42, seg * 1.2, 0.5),
				Vector3(0, 0, -w * 0.85))
		groove.operation = CSGShape3D.OPERATION_SUBTRACTION
		if i < 2:
			# A shadow line at every change of section. NOT after the last: the
			# shear goes there, and a band proud of it costs height.
			_Parts.box(to, Vector3(w * 2.08, 0.08, w * 1.78), Vector3(0, y + seg, 0))
		else:
			_shear_top(to, stage, Vector3(w * 2.0, seg, w * 1.7), y + seg)
		y += seg
		w *= 0.93
	_risers(to, mw, mw * 0.85, base, target * 0.72, clampf(mw * 0.1, 0.06, 0.16))


## THE SHEARED TOP, as a real plane and not a corner knocked off.
##
## A rotated box subtracted from a corner cuts a corner: it is a cube at 38
## degrees and only its nearest vertex is inside the body, so the mast kept
## photographing with a flat lid through two passes. A PLANE cut is a
## half-space — a box far larger than the body with ONE FACE on the cut plane —
## and that is what this builds.
##
## The plane passes through the BACK TOP EDGE, so the measured height is
## unchanged and the whole drop happens at the front, which is the face the
## player is looking at.
static func _shear_top(to: Node, body: CSGShape3D, size: Vector3, top_y: float) -> void:
	var th: float = 34.0 * DEG
	# The cut plane's normal, pointing up and FORWARD (-Z), and the rotation
	# that takes a box's +Y onto it.
	var n := Vector3(0, cos(th), -sin(th))
	var big: float = maxf(size.x, size.z) * 9.0
	var through := Vector3(0, size.y * 0.5, size.z * 0.5)   # the back top edge
	var cut := _Parts.box(body, Vector3(big, big, big), through + n * big * 0.5,
			Vector3(-th, 0, 0))
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	# The lit plate, lying IN the cut and sunk 0.04 into it. Set back from the
	# edges so there is a dark border round the light, which is the note
	# _core_head carries in block_industrial.gd.
	var mid := Vector3(0, top_y - size.z * 0.5 * tan(th), 0)
	_Parts.plate(to, size.x * 0.56, size.z * 0.62, 0.09, 0.12, mid - n * 0.04,
			Vector3(-(PI * 0.5 + th), 0, 0))


## THE FURNITURE. Identical on all three — this is the whole concept, so if a
## number in here ever starts depending on the mast, the concept is gone.
static func _desk(to: Node3D, mast_front_z: float) -> void:
	var z: float = mast_front_z - 0.8
	_Parts.box(to, Vector3(2.3, 0.24, 1.6), Vector3(0, 0.12, z))
	var body := _Parts.box(to, Vector3(1.6, 0.95, 0.7), Vector3(0, 0.715, z - 0.4))
	# The sloped working face, cut back under the lip.
	var slope := _Parts.box(body, Vector3(2.0, 0.6, 0.6),
			Vector3(0, 0.46, -0.44), Vector3(32.0 * DEG, 0, 0))
	slope.operation = CSGShape3D.OPERATION_SUBTRACTION
	_Parts.plate(to, 1.2, 0.4, 0.08, 0.08, Vector3(0, 1.08, z - 0.76),
			Vector3(-32.0 * DEG, 0, 0))
	# A hood over the desk at 2.3 m, not a canopy over the whole station. The
	# first version was a 2.8 x 1.7 roof and it photographed as a table laid
	# across the front of the mast, hiding the thing it was meant to measure.
	for sx: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(0.12, 2.25, 0.12), Vector3(sx * 0.9, 1.125, z - 0.1))
	_Parts.plate(to, 2.0, 1.0, 0.1, 0.16, Vector3(0, 2.3, z - 0.3), Vector3(PI * 0.5, 0, 0))
	_rail(to, -1.1, 1.1, z - 0.85, 0.24)
	_tray(to, -0.5, 0.5, z + 0.45, 1.8)


static func b_small(to: Node3D) -> void:
	_mast(to, 0.80, H_SMALL)
	_desk(to, -0.80 * 0.85)


static func b_medium(to: Node3D) -> void:
	_mast(to, 1.15, H_MEDIUM)
	_desk(to, -1.15 * 0.85)


static func b_large(to: Node3D) -> void:
	_mast(to, 1.75, H_LARGE)
	_desk(to, -1.75 * 0.85)


# ─────────────────────────────────────────────
# C — UNIT / MACHINE / INSTALLATION.  POSITION: THREE FORMS.
#
# The three sizes are three different things that happen to do the same job.
# Small is ONE CABINET — a fridge with a hatch, bolted to a pad, something a
# recovery vehicle could winch away. Medium is a MACHINE: two cabinets under a
# gantry with a chiller on the deck, too big to move and too small to garrison.
# Large is an INSTALLATION: a railed deck you walk up a ramp onto, four columns
# standing on it, a roof truss over them and a stair tower.
#
# What it buys is the judgement the brief says is missing — at any range, the
# silhouette tells you whether this is a two-minute stop or the thing the whole
# mission is about. What it costs is that the large one has to not become
# compute_data_hall, which is the real risk and is argued in the doc.
# ─────────────────────────────────────────────

## One cabinet: body, louvres down both flanks, a hatch, a lifting eye.
static func _cabinet(to: Node3D, w: float, h: float, d: float, at: Vector3,
			with_console: bool) -> void:
	var body := _Parts.box(to, Vector3(w, h, d), at + Vector3(0, h * 0.5, 0))
	if with_console:
		_console(body, -d * 0.5, minf(w * 0.7, 1.5))
	else:
		var hatch := _Parts.box(body, Vector3(w * 0.5, h * 0.44, 0.16),
				Vector3(0, -h * 0.12, -d * 0.5 + 0.06))
		hatch.operation = CSGShape3D.OPERATION_SUBTRACTION
	for sx: float in [-1.0, 1.0]:
		for k in int(h / 0.42):
			_Parts.box(to, Vector3(0.09, 0.14, d * 0.78),
					at + Vector3(sx * (w * 0.5 + 0.04), 0.5 + float(k) * 0.42, 0))
	# Lifting eyes. A cabinet is a thing with a part number; a monument is not.
	for sx: float in [-1.0, 1.0]:
		_Parts.ring(to, 0.05, 0.14, at + Vector3(sx * w * 0.3, h + 0.1, 0),
				Vector3(0, PI * 0.5, 0))


static func c_small(to: Node3D) -> void:
	# ONE UNIT. 1.9 m across so it drops straight into the slot the shipped
	# small core occupies, and the drum on the lid buys the last 0.45 m.
	_plinth(to, 1.2, 1.0, 0.26)
	_cabinet(to, 1.9, 3.49, 1.5, Vector3(0, 0.26, 0), true)
	_drum(to, Vector3(0, 3.75, 0.1), 0.52, 0.27)
	_risers(to, 0.9, 0.75, 0.26, 3.2, 0.09)


static func c_medium(to: Node3D) -> void:
	# A MACHINE: two cabinets with a working slot between them, under a gantry
	# that carries the trays and a chiller. Nothing here is liftable.
	_plinth(to, 2.9, 1.5, 0.3)
	for sx: float in [-1.0, 1.0]:
		_cabinet(to, 2.0, 4.1, 2.0, Vector3(sx * 1.6, 0.3, 0), sx < 0.0)
	# The slot between them, and the second console on its inner wall: this is
	# the approach face at this size and it is 1.2 m wide, which is room for
	# one robot and not for a squad.
	_Parts.box(to, Vector3(1.2, 2.4, 1.3), Vector3(0, 0.3 + 1.2, 0.35))
	# THE POSTS ARE THE TOP, at 7.0, and everything they carry sits below them.
	# Drawn the other way round — deck at 6.6 with a handrail on it — the rail
	# is the tallest thing on the model and the "7 m" core measures 7.65.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-0.8, 0.8]:
			_Parts.box(to, Vector3(0.24, 7.0, 0.24), Vector3(sx * 2.75, 3.5, sz))
	_Parts.box(to, Vector3(6.1, 0.3, 2.2), Vector3(0, 5.75, 0))
	_drum(to, Vector3(-1.4, 5.9, 0), 0.6, 0.22)
	_tray(to, -2.4, 2.4, 0.85, 5.1)
	_rail(to, -2.6, 2.6, -1.1, 5.9)
	_risers(to, 3.0, 1.1, 0.3, 5.6, 0.14)


static func c_large(to: Node3D) -> void:
	# AN INSTALLATION. A deck you walk onto, four columns, a roof over them and
	# a stair tower that makes the 12.4. Thirteen metres across: this one is
	# terrain, and the squad will fight ON it, not round it.
	var deck := 1.2
	_Parts.box(to, Vector3(13.0, deck, 9.0), Vector3(0, deck * 0.5, 0))
	_ramp(to, 4.0, -4.5, deck)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cabinet(to, 2.4, 6.0, 2.4, Vector3(sx * 3.4, deck, sz * 2.4),
					sz < 0.0 and sx < 0.0)
	# The roof truss: two chords and the bracing between them, spanning the
	# columns at 9.6–10.4. A roof is what turns four cabinets into a building.
	for sz: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(12.0, 0.34, 0.34), Vector3(0, 9.7, sz * 3.0))
		_Parts.box(to, Vector3(12.0, 0.34, 0.34), Vector3(0, 10.4, sz * 3.0))
		for k in 7:
			_Parts.box(to, Vector3(0.9, 0.18, 0.18),
					Vector3(-5.1 + float(k) * 1.7, 10.05, sz * 3.0),
					Vector3(0, 0, (38.0 if k % 2 == 0 else -38.0) * DEG))
	for sx: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(0.3, 10.4, 0.3), Vector3(sx * 5.6, 5.2, -3.0))
		_Parts.box(to, Vector3(0.3, 10.4, 0.3), Vector3(sx * 5.6, 5.2, 3.0))
	# The stair tower, in the BACK corner, to 12.4. In the front corner it stood
	# across the deck and read as a fifth column in the middle of the building;
	# behind the roofline it does what it is for, which is to make the top of
	# the silhouette taller than the roof and obviously climbable.
	_Parts.box(to, Vector3(2.2, 12.4, 2.2), Vector3(5.2, 6.2, 2.9))
	for k in 9:
		_Parts.box(to, Vector3(2.0, 0.16, 0.9),
				Vector3(5.2, 1.6 + float(k) * 1.2, 4.3))
	_Parts.box(to, Vector3(2.6, 0.4, 2.6), Vector3(5.2, 12.2, 2.9))
	for sx: float in [-1.0, 1.0]:
		_drum(to, Vector3(sx * 1.6, deck, 3.4), 0.9, 1.3)
	_tray(to, -5.0, 5.0, 1.6, deck + 2.6)
	_rail(to, -6.2, -2.3, -4.4, deck)
	_rail(to, 2.3, 6.2, -4.4, deck)


# ─────────────────────────────────────────────
# D — BLOCK / SLOT / COURT.  POSITION: THREE FORMS.
#
# What changes with size is not mass but ENCLOSURE — where the player has to
# put his body to press the key.
#
#   small  BLOCK. A sealed slab. You stand in the open beside it.
#   medium SLOT. Two slabs with a 2.4 m gap; the consoles face each other
#          inside it. You step into a doorway.
#   large  COURT. Six slabs on a ring with two entrances, a drum in the middle.
#          You go INSIDE, and while you hold it you cannot see out.
#
# This is the only concept where the size changes the FIGHT and not just the
# look: a big core costs more because of where it makes you stand. It is also
# the one with the most ways to go wrong, and the doc says so.
# ─────────────────────────────────────────────

static func d_small(to: Node3D) -> void:
	_plinth(to, 1.45, 1.35, 0.3)
	var body := _Parts.box(to, Vector3(2.2, 3.9, 2.0), Vector3(0, 0.3 + 1.95, 0))
	# Chamfered crown — a 45-degree cut off all four top edges, which is the one
	# shape a brush does for free. FOUR CUTS, one per edge: a single box turned
	# 45 degrees about two axes at once does not cut four edges, it cuts a
	# corner, and the first pass came out looking struck by something.
	# Godot composes euler as Ry * Rx * Rz, so a 45-degree ROLL ABOUT X makes a
	# diamond section along the box's long axis and the Y term then swings that
	# bar round to each of the four edges in turn.
	for i in 4:
		var a: float = TAU * float(i) / 4.0
		var cut := _Parts.box(body, Vector3(4.0, 1.1, 1.1),
				Vector3(sin(a) * 1.1, 1.95, cos(a) * 1.0),
				Vector3(45.0 * DEG, -a, 0))
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	_console(body, -1.0, 1.4)
	for sx: float in [-1.0, 1.0]:
		_Parts.cyl(to, 0.16, 1.0, Vector3(sx * 1.45, 0.5, -1.5), Vector3.ZERO, false, 8)
	_risers(to, 1.0, 1.0, 0.3, 3.4, 0.11)


static func d_medium(to: Node3D) -> void:
	# TWO SLABS, 2.4 m apart. The gap is wide enough for two robots abreast and
	# narrow enough that the far wall is in the player's face, which is the
	# point: at this size the objective has an inside.
	for sx: float in [-1.0, 1.0]:
		_plinth(to, 1.75, 1.0, 0.3)
		var slab := _Parts.box(to, Vector3(2.6, 6.4, 1.6), Vector3(sx * 2.5, 0.3 + 3.2, 0))
		# The console on the INNER face, which is +Z of the left slab... except
		# both slabs' inner faces point along x, so the recess is cut by hand
		# here rather than through _console, which only cuts -Z faces.
		var cut := _Parts.box(slab, Vector3(0.5, 0.9, 1.5),
				Vector3(-sx * 1.05, -1.65, 0))
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		_Parts.plate(to, 1.2, 0.62, 0.1, 0.1,
				Vector3(sx * 1.32, 1.85, 0), Vector3(0, PI * 0.5, 0))
		for k in 5:
			_Parts.box(to, Vector3(2.7, 0.12, 0.2),
					Vector3(sx * 2.5, 1.4 + float(k) * 1.1, -0.85))
	# Plinths under both and the lintel across the top: without the tie they
	# are two monoliths standing near each other, not one split object.
	for sx: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(3.0, 0.3, 2.0), Vector3(sx * 2.5, 0.15, 0))
	_Parts.box(to, Vector3(7.0, 0.6, 1.3), Vector3(0, 6.7, 0))
	_Parts.box(to, Vector3(7.0, 0.3, 0.5), Vector3(0, 6.25, -0.6))
	_tray(to, -2.0, 2.0, 0.6, 5.2)
	# The floor of the slot, so the inside is a place and not a gap.
	_Parts.box(to, Vector3(2.4, 0.18, 2.0), Vector3(0, 0.09, 0))


static func d_large(to: Node3D) -> void:
	# A COURT. Eight bays on a ring of 6.4, two of them left open as entrances
	# at front and back. You hold this from inside it.
	var r := 6.4
	for i in 8:
		if i == 0 or i == 4:
			continue      # front and back: the way in.
		var a: float = TAU * float(i) / 8.0
		var at := Vector3(sin(a) * r, 0, -cos(a) * r)
		var slab := _Parts.box(to, Vector3(3.6, 12.1, 1.7), at + Vector3(0, 6.35, 0),
				Vector3(0, -a, 0))
		var shear := _Parts.box(slab, Vector3(5.0, 3.0, 3.0),
				Vector3(0, 6.6, -1.8), Vector3(32.0 * DEG, 0, 0))
		shear.operation = CSGShape3D.OPERATION_SUBTRACTION
		_Parts.box(to, Vector3(4.2, 0.6, 2.4), at + Vector3(0, 0.3, 0), Vector3(0, -a, 0))
	# The overhead ring: eight bars tying the heads together. This is what
	# makes it one object rather than a henge, and it frames the sky from
	# inside, which is the whole feeling the concept is after.
	for i in 8:
		var a0: float = TAU * float(i) / 8.0
		var a1: float = TAU * float(i + 1) / 8.0
		var p0 := Vector3(sin(a0) * r, 0, -cos(a0) * r)
		var p1 := Vector3(sin(a1) * r, 0, -cos(a1) * r)
		var mid := (p0 + p1) * 0.5
		_Parts.box(to, Vector3(p0.distance_to(p1), 0.34, 0.34),
				mid + Vector3(0, 11.2, 0), Vector3(0, -(a0 + a1) * 0.5, 0))
	# The well in the middle: a drum altar with the console on its front face.
	# The floor is flush so the squad can stand anywhere in here.
	_Parts.box(to, Vector3(11.0, 0.22, 11.0), Vector3(0, 0.11, 0))
	_Parts.cyl(to, 2.0, 1.1, Vector3(0, 0.66, 0), Vector3.ZERO, false, 12)
	var alt := _Parts.box(to, Vector3(2.0, 2.3, 2.0), Vector3(0, 1.15, 0))
	_console(alt, -1.0, 1.5)
	_Parts.ring(to, 0.5, 1.5, Vector3(0, 2.4, 0))
	for sx: float in [-1.0, 1.0]:
		_tray(to, sx * 2.6, sx * 5.4, 0, 2.2)


# ─────────────────────────────────────────────
# E — PYLON AND APRON.  POSITION: THREE FORMS, by what piles up underneath.
#
# One tall element — a braced heat pylon — reads the same at all three sizes,
# on purpose: it is the landmark you steer by and it should be recognisable at
# a kilometre. What changes is the APRON. Small is the pylon on a pad. Medium
# adds a skirt of chillers and a rail. Large stands the pylon on a two-storey
# base block with the approach bay cut into it, inside a 16 m apron.
#
# The footprint therefore grows far faster than the height — 2.8, then 7, then
# 16 m — and footprint is the thing perspective does NOT flatten. A big core
# announces itself as a long walk across open ground before you can read a
# single detail on it, which is exactly the judgement the brief asks for.
# ─────────────────────────────────────────────

static func _pylon(to: Node3D, hw_base: float, y0: float, y1: float) -> void:
	var rise := y1 - y0
	var bar: float = clampf(hw_base * 0.16, 0.12, 0.34)
	var hw_top: float = hw_base * 0.5
	var lean: float = hw_base - hw_top
	var tilt: float = atan2(lean, rise)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			# Signs as in _cage: +X leans in on +t about Z, +Z on -t about X.
			_Parts.box(to, Vector3(bar, rise, bar),
					Vector3(sx * (hw_base - lean * 0.5), y0 + rise * 0.5,
							sz * (hw_base - lean * 0.5)),
					Vector3(-sz * tilt, 0, sx * tilt))
	var bays: int = maxi(2, int(rise / 1.8))
	for k in bays:
		var b0: float = y0 + rise * float(k) / float(bays)
		var b1: float = y0 + rise * float(k + 1) / float(bays)
		var hw: float = lerpf(hw_base, hw_top, (float(k) + 0.5) / float(bays))
		for sz: float in [-1.0, 1.0]:
			_brace(to, hw, sz * hw, b0, b1, bar * 0.62)
	# The head: a cassette in the top bay with its lit plate, and a cap.
	_Parts.box(to, Vector3(hw_top * 1.9, rise * 0.14, hw_top * 1.9),
			Vector3(0, y1 - rise * 0.09, 0))
	_Parts.box(to, Vector3(hw_top * 2.3, 0.3, hw_top * 2.3), Vector3(0, y1 - 0.15, 0))


static func e_small(to: Node3D) -> void:
	_Parts.box(to, Vector3(2.8, 0.22, 2.8), Vector3(0, 0.11, 0))
	_pylon(to, 1.05, 0.22, H_SMALL)
	# The cassette between the front legs IS the approach face at this size:
	# a lattice with nothing in it has nowhere to stand and would be
	# disqualified on the brief's own rule.
	var body := _Parts.box(to, Vector3(1.7, 1.5, 1.1), Vector3(0, 1.5, -0.3))
	_console(body, -0.55, 1.4)
	_tray(to, -1.0, 1.0, 1.1, 0.75)


static func e_medium(to: Node3D) -> void:
	_Parts.box(to, Vector3(7.0, 0.22, 7.0), Vector3(0, 0.11, 0))
	_Parts.box(to, Vector3(3.9, 0.5, 3.9), Vector3(0, 0.36, 0))
	_pylon(to, 1.7, 0.6, H_MEDIUM)
	var body := _Parts.box(to, Vector3(2.4, 2.0, 1.4), Vector3(0, 1.6, -0.9))
	_console(body, -0.7, 1.5)
	for sx: float in [-1.0, 1.0]:
		_drum(to, Vector3(sx * 2.5, 0.22, 1.9), 0.7, 1.1)
	_Parts.box(to, Vector3(1.8, 1.3, 1.1), Vector3(-2.6, 0.87, -1.6))
	_tray(to, -2.4, 2.4, 2.4, 1.5)
	_rail(to, -3.4, -1.3, -3.3, 0.22)
	_rail(to, 1.3, 3.4, -3.3, 0.22)


static func e_large(to: Node3D) -> void:
	# The pylon now stands on a BUILDING. The approach bay is a 3.6 m recess
	# cut into the front of it, so the player presses the key standing under
	# five metres of concrete — which is both the most defensible spot on the
	# map and a box he can be grenaded in.
	_Parts.box(to, Vector3(16.0, 0.22, 16.0), Vector3(0, 0.11, 0))
	var block := _Parts.box(to, Vector3(10.0, 5.0, 10.0), Vector3(0, 2.5, 0))
	var bay := _Parts.box(block, Vector3(3.6, 3.0, 2.6), Vector3(0, -1.0, -3.9))
	bay.operation = CSGShape3D.OPERATION_SUBTRACTION
	_console(block, -3.4, 1.6)
	# Band courses, so a 10 m cube is not a 10 m cube.
	for y: float in [1.6, 3.4]:
		_Parts.box(to, Vector3(10.4, 0.26, 10.4), Vector3(0, y, 0))
	_Parts.box(to, Vector3(11.0, 0.45, 11.0), Vector3(0, 5.0, 0))
	_pylon(to, 2.6, 5.2, H_LARGE)
	for sx: float in [-1.0, 1.0]:
		_drum(to, Vector3(sx * 6.4, 0.22, 2.6), 1.1, 1.9)
		_drum(to, Vector3(sx * 6.4, 0.22, 5.4), 1.1, 1.9)
		_Parts.box(to, Vector3(2.2, 2.6, 1.6), Vector3(sx * 6.6, 1.31, -3.2))
	_tray(to, -6.0, 6.0, 5.6, 6.0)
	_rail(to, -7.6, -2.2, -7.6, 0.22)
	_rail(to, 2.2, 7.6, -7.6, 0.22)
	_risers(to, 4.0, 5.0, 0.22, 5.0, 0.22)


# ─────────────────────────────────────────────
# THE SET, for the renderer. Rows are concepts, columns are sizes.
# ─────────────────────────────────────────────

static func sets() -> Array:
	return [
		["A  CASSETTE STACK   one form scaled", a_small, a_medium, a_large],
		["B  MAST AND DESK    one form scaled", b_small, b_medium, b_large],
		["C  UNIT/MACHINE/INSTALLATION  three forms", c_small, c_medium, c_large],
		["D  BLOCK/SLOT/COURT           three forms", d_small, d_medium, d_large],
		["E  PYLON AND APRON            three forms", e_small, e_medium, e_large],
	]
