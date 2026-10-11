extends SceneTree

# ─────────────────────────────────────────────
# ARMED BIPED CHASSIS — CONCEPT PASS
#
#   godot --audio-driver Dummy --path . --script res://tools/mockup_mech.gd -- <out dir>
#
# IT NEEDS A WINDOW. The icon studio renders, so run it WITHOUT --headless.
#
# Throwaway visualiser, not game code. Four humanoid silhouettes in the
# Walker's own vocabulary, drawn through the same icon studio the UI icons come
# from, so what you are looking at is this game's line art and not a sketch in
# somebody else's style. Whichever survives gets modelled properly.
#
# WHAT ARMS ARE ACTUALLY FOR, which is the whole question here. The Walker is
# already a two-legged gun: bolting arms on it and changing nothing else buys a
# silhouette and no gameplay. Each of these uses the arms for something the
# roster cannot currently do:
#
#   LANCER   a weapon in each hand        — two hardpoints, mixed loadout
#   BULWARK  a tower shield on one arm    — walks INTO fire; see suppression
#   WRECKER  heavy arms, no gun           — melee and salvage, hands not muzzles
#   ARBITER  slim arms, big sensor head   — designator, and the arms are tools
#
# WHAT IS INHERITED FROM THE WALKER, so these read as the same factory:
#   - a chamfered hull box with a sloped glacis and a cut-back tail
#   - a turret ring, and a head that is a box with its cheeks and brow cut
#   - ONE eye, offset to the left of the face
#   - a whip antenna off the back corner
#   - boxy limb segments: hip cap, thigh, shin, flat foot
#   - digitigrade legs: knee forward over a long flat foot
# Measurements below are the walker's own, read out of walker.tscn, so the
# family resemblance is literal rather than approximate.
#
# ARMS HANG OFF THE SHOULDER BEVELS the walker already has cut into its hull.
# That is not a detail: those two chamfers are the only place on the existing
# silhouette where an arm could plausibly mount, and using them is what stops
# these looking like a Walker with limbs glued to its flanks.
# ─────────────────────────────────────────────

const _Studio := preload("res://Character/hud/icons/icon_studio.gd")
const _Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _Parts := preload("res://tools/mockup_parts.gd")

const SHOT := Vector2i(380, 380)
const CELL := Vector2i(400, 430)
const COLS := 2
const SHEET_BG := Color(0.043, 0.071, 0.063)

# ── THE WALKER, FOR REFERENCE ─────────────────
# Straight out of walker.tscn. Nothing below should drift from these without a
# reason, because they are what makes a new frame look issued rather than found.
const W_HULL := Vector3(1.5, 0.9, 1.75)
const W_TURRET := Vector3(1.18, 0.6, 1.3)
const W_EYE_R := 0.17
const W_RING_R := 0.54
const W_THIGH := Vector3(0.34, 0.74, 0.4)
const W_SHIN := Vector3(0.26, 0.86, 0.3)
const W_FOOT := Vector3(0.4, 0.15, 0.86)

var _studio: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("mockup_quad: this renders, so it needs a window. Run it WITHOUT --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 and args[0].strip_edges() != "" else "user://mockups"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_studio = _Studio.new()
	root.add_child(_studio)

	var variants := [
		["WALKER  for scale", _walker_reference],
		["C  the original", _picket_umbrella],
		["C1  dish + pod, paired", _picket_c1],
		["C2  launcher-led, dish on shoulder", _picket_c2],
		["C3  on rover wheels", _picket_c3],
	]

	# SHEET ONE: what each one looks like, one per cell.
	var cells: Array = []
	for v in variants:
		var body := Node3D.new()
		(v[1] as Callable).call(body)
		cells.append([v[0], await _studio.render_body(body, SHOT,
				_Studio.Framing.THREE_QUARTER, false, false, 0.0)])
	var path := "%s/picket_refine.png" % out_dir
	_save(await _sheet(cells), path)
	print("mockup_quad: %s" % ProjectSettings.globalize_path(path))

	# ...AND THE SIZES, MEASURED.
	#
	# The sheet above cannot tell you any of this: the studio fits each body to
	# its own box, so a two-metre frame and a five-metre one come out the same
	# height on the page. A "for scale" label on one cell would be a lie.
	#
	# A single wide render of all five at true scale was the obvious fix and it
	# came back solid white — the studio's auto-framing does not cope with a
	# 4:1 group. Measuring the bounding boxes answers the real question ("does
	# it fit through a door, does it clear a bridge") better than a picture
	# would anyway, and it cannot be misread.
	print("")
	print("  FRAME                          W     H     L   (metres)")
	for v in variants:
		var body := Node3D.new()
		(v[1] as Callable).call(body)
		root.add_child(body)
		await process_frame
		await process_frame
		var bb := _measure(body, body)
		print("  %-28s %5.2f %5.2f %5.2f" % [str(v[0]), bb.size.x, bb.size.y, bb.size.z])
		body.queue_free()
	quit(0)


## Union of every visible piece, in the body's own space. CSG needs a couple of
## frames in the tree before its meshes exist, which is why the caller waits.
##
## SUBTRACTION SHAPES DO NOT COUNT. They are deliberately oversized — a glacis
## cut is 1.4x the hull width so it slices cleanly through both flanks — and
## including them put the Walker at 3.3 m wide when its hull is 1.5. They carve
## material away; they are not part of the result.
func _measure(n: Node, body: Node3D) -> AABB:
	if n is CSGShape3D and (n as CSGShape3D).operation == CSGShape3D.OPERATION_SUBTRACTION:
		return AABB()
	var out := AABB()
	var started := false
	for c in n.get_children():
		var sub := _measure(c, body)
		if sub.size != Vector3.ZERO:
			out = sub if not started else out.merge(sub)
			started = true
	if n is VisualInstance3D:
		var local := body.global_transform.affine_inverse() * (n as VisualInstance3D).global_transform
		var a := local * (n as VisualInstance3D).get_aabb()
		out = a if not started else out.merge(a)
	return out


# ─────────────────────────────────────────────
# SHARED PARTS — the bits that make it a Roboto frame
# ─────────────────────────────────────────────

## The hull: a chamfered box with the walker's sloped glacis and cut tail.
## `size` is the uncut block; the cuts take material OFF it, so a hull quoted
## at 2.4 long is shorter than that once the nose and tail are sliced.
func _hull(to: Node, size: Vector3, at: Vector3) -> Node3D:
	var hull := _Parts.box(to, size, at)
	hull.name = "Hull"
	# Sloped glacis, taken off the front.
	var g := _Parts.box(hull, Vector3(size.x * 1.4, size.y * 1.2, size.z * 0.8),
			Vector3(0, -size.y * 0.72, -size.z * 0.62), Vector3(-30.0 * _Parts.DEG, 0, 0))
	g.operation = CSGShape3D.OPERATION_SUBTRACTION
	# Cut-back tail.
	var t := _Parts.box(hull, Vector3(size.x * 1.4, size.y * 1.2, size.z * 0.6),
			Vector3(0, -size.y * 0.68, size.z * 0.64), Vector3(20.0 * _Parts.DEG, 0, 0))
	t.operation = CSGShape3D.OPERATION_SUBTRACTION
	# Shoulder bevels down both flanks — the walker's, scaled.
	for s in [-1.0, 1.0]:
		var b := _Parts.box(hull, Vector3(size.x * 0.7, size.y * 0.8, size.z * 1.4),
				Vector3(s * size.x * 0.68, size.y * 0.66, 0), Vector3(0, 0, s * 30.0 * _Parts.DEG))
		b.operation = CSGShape3D.OPERATION_SUBTRACTION
	return hull


## Turret ring, turret, eye, antenna and a stub gun. `scale_f` keeps the whole
## head in proportion on the bigger and smaller frames without redrawing it.
func _head(to: Node, at: Vector3, scale_f: float = 1.0) -> Node3D:
	_Parts.cyl(to, W_RING_R * scale_f, 0.12 * scale_f, at)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = at + Vector3(0, 0.19 * scale_f, 0)
	to.add_child(turret)
	var body := _Parts.box(turret, W_TURRET * scale_f, Vector3.ZERO)
	body.name = "TurretBody"
	# Cheek and brow, cut exactly as the walker's are.
	var cheek := _Parts.box(body, Vector3(W_TURRET.x * 1.3, 0.7, 0.7) * scale_f,
			Vector3(0, -0.44, -0.86) * scale_f, Vector3(-35.0 * _Parts.DEG, 0, 0))
	cheek.operation = CSGShape3D.OPERATION_SUBTRACTION
	var brow := _Parts.box(body, Vector3(W_TURRET.x * 1.3, 0.7, 0.7) * scale_f,
			Vector3(0, 0.5, -0.78) * scale_f, Vector3(25.0 * _Parts.DEG, 0, 0))
	brow.operation = CSGShape3D.OPERATION_SUBTRACTION
	# ONE EYE, off-centre. The asymmetry is the walker's single most
	# recognisable feature and the cheapest thing to carry over.
	_Parts.sphere(turret, W_EYE_R * scale_f,
			Vector3(-0.34, 0.14, -0.66) * scale_f, Vector3(1, 0.82, 1))
	_Parts.box(turret, Vector3(0.03, 0.85, 0.03) * scale_f,
			Vector3(-0.5, 0.68, 0.48) * scale_f)
	# Mantlet and barrel.
	_Parts.box(turret, Vector3(0.5, 0.36, 0.26) * scale_f, Vector3(-0.2, 0.02, -0.62) * scale_f)
	_Parts.cyl(turret, 0.075 * scale_f, 1.5 * scale_f,
			Vector3(-0.2, 0.02, -1.35) * scale_f, Vector3(90.0 * _Parts.DEG, 0, 0))
	return turret


## One leg. `splay` swings it out sideways from the hip, `reach` forward or
## back, and `digitigrade` decides whether the knee breaks forward over a short
## foot (a dog) or the limb drops straight to a flat pad (an elephant).
func _leg(to: Node, hip: Vector3, thigh_len: float, shin_len: float,
		splay: float, reach: float, digitigrade: bool, thick: float = 1.0) -> void:
	var leg := Node3D.new()
	leg.position = hip
	leg.rotation = Vector3(reach * _Parts.DEG, 0, splay * _Parts.DEG)
	to.add_child(leg)
	_Parts.sphere(leg, 0.19 * thick, Vector3.ZERO)
	var knee_drop := -thigh_len
	if digitigrade:
		# Thigh angles back, shin angles forward, foot flat and long: the
		# walker's own leg, which is what makes these read as its relatives.
		_Parts.box(leg, Vector3(W_THIGH.x * thick, thigh_len, W_THIGH.z * thick),
				Vector3(0, knee_drop * 0.5, thigh_len * 0.18), Vector3(15.0 * _Parts.DEG, 0, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, knee_drop, thigh_len * 0.38)
		leg.add_child(knee)
		_Parts.sphere(knee, 0.15 * thick, Vector3.ZERO)
		_Parts.box(knee, Vector3(W_SHIN.x * thick, shin_len, W_SHIN.z * thick),
				Vector3(0, -shin_len * 0.5, -shin_len * 0.2), Vector3(-15.0 * _Parts.DEG, 0, 0))
		_Parts.box(knee, Vector3(W_FOOT.x * thick, W_FOOT.y, W_FOOT.z),
				Vector3(0, -shin_len - 0.06, -shin_len * 0.42 - 0.18))
	else:
		# A pillar: straight down, pad at the bottom. Reads as load-bearing
		# rather than quick, which is the whole difference between the Dray
		# and the Hound at the same size.
		_Parts.box(leg, Vector3(W_THIGH.x * 1.25 * thick, thigh_len, W_THIGH.z * 1.25 * thick),
				Vector3(0, knee_drop * 0.5, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, knee_drop, 0)
		leg.add_child(knee)
		_Parts.ring(knee, 0.05 * thick, 0.2 * thick, Vector3.ZERO)
		_Parts.box(knee, Vector3(W_SHIN.x * 1.3 * thick, shin_len, W_SHIN.z * 1.3 * thick),
				Vector3(0, -shin_len * 0.5, 0))
		_Parts.cyl(knee, 0.26 * thick, 0.14, Vector3(0, -shin_len - 0.05, 0))


## ONE ARM. Shoulder ball, upper arm, elbow, forearm, and whatever the hand is.
##
## MOUNTED ON THE SHOULDER BEVEL, outboard and high, where the walker's hull is
## already chamfered away. `droop` swings it down from horizontal, `out` swings
## it away from the body, and `fore` swings it forward — three angles rather
## than a pose, so a variant can hold a gun level or let a hand hang.
func _arm(to: Node, shoulder: Vector3, upper_len: float, fore_len: float,
		droop: float, out_ang: float, fore_ang: float, thick: float = 1.0,
		hand: String = "none") -> Node3D:
	var arm := Node3D.new()
	arm.position = shoulder
	arm.rotation = Vector3(fore_ang * _Parts.DEG, 0, out_ang * _Parts.DEG)
	to.add_child(arm)
	_Parts.sphere(arm, 0.26 * thick, Vector3.ZERO)
	_Parts.box(arm, Vector3(0.36 * thick, upper_len, 0.36 * thick),
			Vector3(0, -upper_len * 0.5, 0))
	var elbow := Node3D.new()
	elbow.position = Vector3(0, -upper_len, 0)
	elbow.rotation = Vector3(droop * _Parts.DEG, 0, 0)
	arm.add_child(elbow)
	_Parts.sphere(elbow, 0.19 * thick, Vector3.ZERO)
	_Parts.box(elbow, Vector3(0.3 * thick, fore_len, 0.3 * thick),
			Vector3(0, -fore_len * 0.5, 0))
	var wrist := Node3D.new()
	wrist.position = Vector3(0, -fore_len, 0)
	elbow.add_child(wrist)
	match hand:
		"gun":
			# A weapon hardpoint, not a fist. The point of the Lancer is that
			# this is a MOUNT and the catalogue decides what sits on it.
			#
			# ALONG THE FOREARM, not along the wrist's -Z. The first pass put
			# the barrel on local -Z, forgetting that `droop` has already
			# rotated this frame — so with the forearm levelled forward, -Z
			# pointed at the sky and the Lancer held two guns straight up.
			# Continuing down -Y means the barrel follows the limb wherever
			# the arm is posed, which is what a hardpoint does.
			_Parts.box(wrist, Vector3(0.34, 0.42, 0.34) * thick, Vector3(0, -0.16, 0))
			_Parts.cyl(wrist, 0.08 * thick, 1.4, Vector3(0, -1.05, 0))
		"claw":
			# Two opposed jaws. Reads as a grab at any size, which a hand with
			# fingers does not once it is forty pixels tall.
			_Parts.box(wrist, Vector3(0.42, 0.26, 0.34) * thick, Vector3(0, -0.14, 0))
			for s in [-1.0, 1.0]:
				_Parts.wedge(wrist, 0.5, 0.16, 0.14, 0.2,
						Vector3(s * 0.16, -0.5, 0),
						Vector3(90.0 * _Parts.DEG, 0, s * 18.0 * _Parts.DEG))
		"tool":
			# A short multi-tool stub: a cylinder and a lamp, which is what the
			# Reclaimer's language already uses for "this one works".
			_Parts.cyl(wrist, 0.13 * thick, 0.46, Vector3(0, -0.24, 0))
			_Parts.box(wrist, Vector3(0.18, 0.1, 0.06), Vector3(0, -0.46, -0.12))
	return wrist


## The tower shield, which is the Bulwark's entire reason to exist. A slab with
## a rolled rim and a vision slot cut through it, carried on the forearm rather
## than held — a shield a machine has to grip is a shield it cannot shoot past.
func _tower_shield(to: Node, counter_droop: float) -> void:
	# STOOD BACK UP. The shield hangs off the wrist, and the wrist carries the
	# forearm's droop — so built straight into it the slab came out lying flat,
	# a paddle held out sideways rather than a wall held in front. Undoing the
	# droop here keeps it vertical in the world however the arm is posed.
	var mount := Node3D.new()
	mount.rotation = Vector3(-counter_droop * _Parts.DEG, 0, 0)
	to.add_child(mount)
	var face := _Parts.plate(mount, 1.3, 2.0, 0.14, 0.28, Vector3(0, -0.45, -0.34))
	face.name = "Shield"
	var slot := _Parts.box(face, Vector3(0.64, 0.13, 0.5), Vector3(-0.12, 0.66, 0.07))
	slot.operation = CSGShape3D.OPERATION_SUBTRACTION
	_Parts.studs(mount, 4, Vector3(-0.44, -1.32, -0.42), Vector3(0.29, 0, 0), 0.045)


# ─────────────────────────────────────────────
# THE FOUR, PLUS THE WALKER TO MEASURE THEM AGAINST
# ─────────────────────────────────────────────

## The Walker as it ships, so the sheet has a known quantity on it. A concept
## sheet with no reference is four drawings of nothing in particular.
func _walker_reference(root_node: Node3D) -> void:
	_hull(root_node, W_HULL, Vector3(0, 0.3, 0))
	_head(root_node, Vector3(0, 0.76, 0), 1.0)
	for sx in [-1.0, 1.0]:
		_leg(root_node, Vector3(sx * 0.7, -0.2, 0), 0.74, 0.86, 0.0, 0.0, true)


## LANCER — the straight answer. A weapon in each hand, head set low between
## the shoulders, Walker legs underneath. The gameplay is the pair of mounts:
## it is the first frame that can carry two different weapons and choose which
## one the situation wants.
func _lancer(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.55, 1.15, 1.35), Vector3(0, 0.55, 0))
	_head(root_node, Vector3(0, 1.14, -0.1), 0.62)
	for sx in [-1.0, 1.0]:
		_arm(root_node, Vector3(sx * 0.92, 0.88, 0), 0.62, 0.6, 72.0,
				sx * 10.0, 0.0, 1.0, "gun")
	for sx in [-1.0, 1.0]:
		_leg(root_node, Vector3(sx * 0.48, -0.1, 0), 0.8, 0.92, sx * 3.0, 0.0, true)


## BULWARK — a tower shield on the left arm and a weapon on the right, hunched
## forward behind it. Short, wide, heavy.
##
## THE ONE THAT USES A SYSTEM WE ALREADY HAVE. Suppression is measured along a
## round's flight path now, so a frame whose job is to absorb fire and keep
## walking is a frame that eats suppression for the squad behind it. Nothing in
## the roster currently does that, and no amount of armour on an existing
## chassis would, because armour is health and this is about the LANE.
func _bulwark(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.85, 1.1, 1.5), Vector3(0, 0.45, 0))
	_head(root_node, Vector3(0, 0.98, -0.15), 0.58)
	# Shield arm, held across the body and low.
	var left := _arm(root_node, Vector3(-1.02, 0.78, -0.1), 0.5, 0.52, 80.0,
			14.0, -8.0, 1.2, "none")
	_tower_shield(left, 80.0)
	# Weapon arm, tucked in tight behind the shield line.
	_arm(root_node, Vector3(0.98, 0.8, 0.05), 0.52, 0.52, 74.0, -8.0, 0.0, 1.1, "gun")
	for sx in [-1.0, 1.0]:
		_leg(root_node, Vector3(sx * 0.55, -0.15, 0), 0.7, 0.78, sx * 6.0, 0.0, true, 1.2)


## WRECKER — no gun at all. Two heavy arms with grabs on the end, a low wide
## body and short legs.
##
## HANDS, NOT MUZZLES. The roster has melee chassis and it has a Reclaimer that
## recovers wrecks, and neither can do the other's job; this is one frame that
## can take a position apart and then drag the pieces home. It is also the only
## concept here whose silhouette says "no ranged threat" at a glance, which is
## a readability win for whoever is shooting at it.
func _wrecker(root_node: Node3D) -> void:
	_hull(root_node, Vector3(2.0, 1.0, 1.6), Vector3(0, 0.3, 0))
	_head(root_node, Vector3(0, 0.82, -0.3), 0.5)
	for sx in [-1.0, 1.0]:
		_arm(root_node, Vector3(sx * 1.12, 0.62, -0.05), 0.74, 0.72, 62.0,
				sx * 16.0, -10.0, 1.45, "claw")
	for sx in [-1.0, 1.0]:
		_leg(root_node, Vector3(sx * 0.6, -0.3, 0), 0.6, 0.68, sx * 8.0, 0.0, true, 1.3)


## ARBITER — tall and upright, slim arms, an oversized sensor head and a mast
## array on the back. The arms carry tools rather than weapons.
##
## THE DESIGNATOR MADE INTO A FRAME. Spotting already tightens the whole
## squad's aim and the mortar already fires on what somebody else can see — so
## a chassis built around the sensor head is a force multiplier rather than
## another gun, and it should look fragile enough that you have to protect it.
func _arbiter(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.2, 1.3, 1.1), Vector3(0, 0.9, 0))
	_head(root_node, Vector3(0, 1.62, -0.05), 0.82)
	# Mast array on the back deck — the thing it is actually for.
	for i in 3:
		var x := -0.3 + float(i) * 0.3
		_Parts.box(root_node, Vector3(0.045, 1.0 + float(i % 2) * 0.35, 0.045),
				Vector3(x, 1.9 + float(i % 2) * 0.18, 0.62))
	_Parts.ring(root_node, 0.05, 0.3, Vector3(0.0, 2.52, 0.62), Vector3(0, 0, 20.0 * _Parts.DEG))
	for sx in [-1.0, 1.0]:
		_arm(root_node, Vector3(sx * 0.74, 1.18, 0), 0.6, 0.58, 58.0,
				sx * 6.0, 0.0, 0.78, "tool")
	for sx in [-1.0, 1.0]:
		_leg(root_node, Vector3(sx * 0.42, 0.28, 0), 0.9, 1.0, sx * 2.0, 0.0, true, 0.82)

# ─────────────────────────────────────────────
# THE SHEET
# ─────────────────────────────────────────────
func _label_image(text: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x, 30)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _Kit.FONT_BODY)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(l)
	root.add_child(vp)
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _sheet(parts: Array) -> Image:
	var rows := int(ceil(parts.size() / float(COLS)))
	var sheet := Image.create(CELL.x * COLS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(SHEET_BG)
	for i in parts.size():
		var img: Image = parts[i][1]
		var col: int = i % COLS
		var row: int = i / COLS
		var ox := col * CELL.x
		var oy := row * CELL.y
		if img != null:
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
					Vector2i(ox + (CELL.x - img.get_width()) / 2, oy + 12))
		var label: Image = await _label_image(str(parts[i][0]))
		if label.get_format() != Image.FORMAT_RGBA8:
			label.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(label, Rect2i(Vector2i.ZERO, label.get_size()),
				Vector2i(ox, oy + CELL.y - 36))
	return sheet


func _save(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		printerr("mockup_quad: could not write %s (%s)" % [path, error_string(err)])


# ─────────────────────────────────────────────
# PICKET — FIVE OPTIONS
#
# The frame that closes the worst hole in the roster: nothing in the game can
# shoot upward. The Walker's gun stops at 35 degrees of elevation, so a
# quadcopter directly overhead is untouchable by the heaviest thing we own.
#
# WHAT A SILHOUETTE HAS TO SAY HERE, and it is unusually specific: "this one
# shoots UP". If a player cannot tell at a glance that a frame is the answer to
# the thing bombing them, the frame has failed before its stats matter. Every
# option below is a different answer to that one question.
# ─────────────────────────────────────────────

## A. TRIPOD — a short barrel on a tall tripod, pointed up at rest.
## The classic AA gun. Reads instantly; the risk is that it reads as scenery
## rather than as a unit, because nothing else in this game stands on three.
func _picket_tripod(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.1, 0.5, 1.1), Vector3(0, 0.95, 0))
	for i in 3:
		var a := deg_to_rad(90.0 + float(i) * 120.0)
		var foot := Vector3(cos(a) * 1.15, -0.55, sin(a) * 1.15)
		_Parts.box(root_node, Vector3(0.18, 1.7, 0.18),
				Vector3(foot.x * 0.5, 0.35, foot.z * 0.5),
				Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5))
		_Parts.plate(root_node, 0.5, 0.5, 0.1, 0.1, foot, Vector3(PI * 0.5, 0, 0))
	# The gun: short, fat, and canted hard up. Twin barrels, because one barrel
	# at this angle reads as a mortar and two read as a flak mount.
	var mount := _node_at(root_node, Vector3(0, 1.3, 0), Vector3(62.0 * _Parts.DEG, 0, 0))
	_Parts.box(mount, Vector3(0.7, 0.5, 0.8), Vector3.ZERO)
	for s in [-1.0, 1.0]:
		_Parts.cyl(mount, 0.09, 1.6, Vector3(s * 0.18, 0.1, -0.9), Vector3(PI * 0.5, 0, 0))
	_Parts.sphere(root_node, 0.22, Vector3(0.3, 1.25, 0.42))


## B. TURRET ROVER — the Rover hull with a high-angle mount where its turret is.
## The cheapest to build and the easiest to read as OURS, because the chassis
## under it is already in the game. The risk is the opposite of A: too familiar
## to register as a new thing.
func _picket_rover(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.7, 0.75, 2.4), Vector3(0, 0.45, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_Parts.cyl(root_node, 0.34, 0.26, Vector3(sx * 0.86, 0.1, sz * 0.78),
					Vector3(0, 0, PI * 0.5))
	_Parts.cyl(root_node, 0.5, 0.12, Vector3(0, 0.85, 0.1))
	var mount := _node_at(root_node, Vector3(0, 1.0, 0.1), Vector3(58.0 * _Parts.DEG, 0, 0))
	_Parts.box(mount, Vector3(0.8, 0.55, 0.9), Vector3.ZERO)
	for s in [-1.0, 1.0]:
		_Parts.cyl(mount, 0.08, 1.9, Vector3(s * 0.2, 0.08, -1.0), Vector3(PI * 0.5, 0, 0))
	_Parts.sphere(root_node, 0.2, Vector3(-0.3, 0.86, -1.0))


## C. UMBRELLA — a dish, not a gun. A radar bowl that aims and a short stub
## launcher beside it, on Walker legs. Says "air defence" rather than "gun"
## and is the only option that reads at a distance from any angle, because the
## dish is a shape nothing else in the roster has.
func _picket_umbrella(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.4, 0.95, 1.5), Vector3(0, 0.5, 0))
	var dish := _node_at(root_node, Vector3(-0.1, 1.5, 0.1), Vector3(-55.0 * _Parts.DEG, 0, 0))
	_Parts.cyl(dish, 0.95, 0.16, Vector3.ZERO, Vector3.ZERO, true, 16)
	_Parts.cyl(dish, 0.07, 0.7, Vector3(0, 0.4, 0))
	_Parts.sphere(dish, 0.14, Vector3(0, 0.75, 0))
	# The launcher: four short tubes, stubby, clearly not a cannon.
	var box := _node_at(root_node, Vector3(0.78, 1.15, 0), Vector3(-50.0 * _Parts.DEG, 0, 0))
	for i in 4:
		@warning_ignore("integer_division")
		var c := i % 2
		@warning_ignore("integer_division")
		var r := i / 2
		_Parts.cyl(box, 0.11, 0.9, Vector3(-0.14 + float(c) * 0.28, 0.0, -0.16 + float(r) * 0.3),
				Vector3(PI * 0.5, 0, 0))
	for sx in [-1.0, 1.0]:
		_leg(root_node, Vector3(sx * 0.6, -0.1, 0), 0.7, 0.8, sx * 5.0, 0.0, true)


## D. MANTIS — legs splayed wide and low, body slung between them, guns held
## UP on two short arms. The stance does the talking: it is crouched and
## looking at the sky, which no other frame in the game is doing.
func _picket_mantis(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.5, 0.62, 1.7), Vector3(0, 0.62, 0))
	_head(root_node, Vector3(0, 0.98, -0.3), 0.5)
	for sx in [-1.0, 1.0]:
		# Arms raised, not hanging: negative droop puts the forearm above the
		# shoulder, which is the whole read.
		var arm := _arm(root_node, Vector3(sx * 0.82, 0.78, -0.1), 0.52, 0.56,
				-58.0, sx * 20.0, 0.0, 0.95, "none")
		_Parts.cyl(arm, 0.085, 1.5, Vector3(0, -0.75, 0))
		_Parts.box(arm, Vector3(0.3, 0.34, 0.3), Vector3(0, -0.14, 0))
	for sx in [-1.0, 1.0]:
		_leg(root_node, Vector3(sx * 0.78, 0.0, 0), 0.52, 0.62, sx * 26.0, 0.0, true, 1.1)


## E. SPIRE — a tall thin mast with a ring of small barrels at the top. Reads
## as a point-defence post rather than a gun platform, and is the only option
## whose answer to "which way is it shooting" is "all of them at once".
func _picket_spire(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.25, 0.7, 1.25), Vector3(0, 0.1, 0))
	_Parts.box(root_node, Vector3(0.3, 2.1, 0.3), Vector3(0, 1.3, 0))
	_Parts.cyl(root_node, 0.62, 0.3, Vector3(0, 2.35, 0))
	for i in 6:
		var a := deg_to_rad(float(i) * 60.0)
		_Parts.cyl(root_node, 0.06, 0.9,
				Vector3(cos(a) * 0.5, 2.62, sin(a) * 0.5),
				Vector3(-50.0 * _Parts.DEG * cos(a), 0, 50.0 * _Parts.DEG * sin(a)))
	_Parts.sphere(root_node, 0.2, Vector3(0, 2.52, -0.58))
	for sx in [-1.0, 1.0]:
		_leg(root_node, Vector3(sx * 0.52, -0.25, 0), 0.6, 0.7, sx * 10.0, 0.0, true)


## A bare transform, for hanging a canted assembly off.
func _node_at(to: Node, at: Vector3, euler: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	n.rotation = euler
	to.add_child(n)
	return n


# ─────────────────────────────────────────────
# PICKET — REFINING C (UMBRELLA)
#
# C won on the one thing that mattered: the dish is the only shape in the
# roster that says "this is for aircraft" before you have parsed anything
# else. A, B and D all failed the same way — they looked like guns, and a gun
# that happens to elevate is not a readable answer to being bombed.
#
# THREE FAULTS TO FIX, from the render:
#   the dish is too big for the body and reads as the whole unit
#   the launcher is lost beside it, so the frame looks unarmed
#   4.07 m tall, which out-tops the Walker — wrong for a 2-supply frame
# ─────────────────────────────────────────────

## C1 — dish smaller, launcher bigger. The two read as a pair rather than a
## bowl with an accessory.
func _picket_c1(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.5, 0.95, 1.6), Vector3(0, 0.45, 0))
	_picket_dish(root_node, Vector3(-0.52, 1.12, 0.12), 0.62)
	_picket_pods(root_node, Vector3(0.6, 1.0, -0.05), 2, 3, 0.115, 1.0)
	for sx in [-1.0, 1.0]:
		_leg(root_node, Vector3(sx * 0.6, -0.12, 0), 0.66, 0.76, sx * 6.0, 0.0, true)


## C2 — the launcher IS the unit and the dish is a sensor on its shoulder. Six
## tubes in a block, canted up hard.
func _picket_c2(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.55, 0.9, 1.5), Vector3(0, 0.45, 0))
	_picket_pods(root_node, Vector3(0.0, 1.22, 0.0), 3, 2, 0.14, 1.25)
	_picket_dish(root_node, Vector3(-0.86, 1.22, 0.42), 0.4)
	for sx in [-1.0, 1.0]:
		_leg(root_node, Vector3(sx * 0.62, -0.12, 0), 0.66, 0.76, sx * 6.0, 0.0, true)


## C3 — on the Rover's wheels instead of legs. Cheaper to field and cheaper to
## believe: a 2-supply frame on a chassis the player already owns.
func _picket_c3(root_node: Node3D) -> void:
	_hull(root_node, Vector3(1.7, 0.8, 2.3), Vector3(0, 0.5, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_Parts.cyl(root_node, 0.36, 0.28, Vector3(sx * 0.88, 0.12, sz * 0.74),
					Vector3(0, 0, PI * 0.5))
	_Parts.cyl(root_node, 0.46, 0.1, Vector3(0, 0.92, 0.1))
	_picket_pods(root_node, Vector3(0.0, 1.22, 0.1), 3, 2, 0.13, 1.15)
	_picket_dish(root_node, Vector3(-0.78, 1.16, 0.75), 0.38)


## The dish. A shallow cone on a short neck, canted up — the shape that does
## all the work.
func _picket_dish(to: Node, at: Vector3, r: float) -> void:
	var d := _node_at(to, at, Vector3(-52.0 * _Parts.DEG, 0, 0))
	_Parts.cyl(d, r, 0.14, Vector3.ZERO, Vector3.ZERO, true, 16)
	_Parts.cyl(d, 0.055, r * 0.75, Vector3(0, r * 0.45, 0))
	_Parts.sphere(d, 0.1, Vector3(0, r * 0.82, 0))
	_Parts.cyl(to, 0.1, 0.5, at + Vector3(0, -0.34, 0))


## The launcher: a block of tubes, canted up. `cols` x `rows`, so the same
## helper gives a modest pod and a serious battery.
func _picket_pods(to: Node, at: Vector3, cols: int, rows: int, r: float, len_f: float) -> void:
	# POSITIVE X. A rotation about +X maps -Z to (0, sin, -cos), so a NEGATIVE
	# angle sends the muzzle DOWN and forward — on the one frame whose whole
	# premise is shooting up. Three of the five first-round options had this
	# sign wrong, which is most of why A, B and D "looked like guns": their
	# barrels were aimed at the floor.
	#
	# The dish below is NOT the same case and is correctly negative: a cone's
	# axis is +Y, and +X by a negative angle tilts +Y up and forward.
	var b := _node_at(to, at, Vector3(54.0 * _Parts.DEG, 0, 0))
	_Parts.plate(b, float(cols) * r * 2.4, float(rows) * r * 2.4, 0.16, 0.08,
			Vector3(0, 0, 0.12))
	for c in cols:
		for w in rows:
			var x := (float(c) - float(cols - 1) * 0.5) * r * 2.3
			var y := (float(w) - float(rows - 1) * 0.5) * r * 2.3
			_Parts.cyl(b, r, 1.1 * len_f, Vector3(x, y, -0.5 * len_f),
					Vector3(PI * 0.5, 0, 0))
