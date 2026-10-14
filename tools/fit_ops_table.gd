extends SceneTree

# ─────────────────────────────────────────────
# FIT THE OPS TABLE — the anchor and the Interactible, re-appliably.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/fit_ops_table.gd [-- --check]
#
# WHY THIS EXISTS AND WHY IT IS A SCRIPT. The operations table in
# maps/blocks/railhead/railhead_car_ops.tscn needs two nodes that FuncGodot
# cannot produce: an empty at the centre of the table's top surface, which is
# where Env/world_objects/ops_table.gd generates the holographic board from,
# and an Interactible so F does anything.
#
# It now seats TWO of those pairs. The second is the departure lever's pivot,
# outboard of the table's exit end, which Env/world_objects/departure_lever.gd
# generates a handle on — docs/briefs/OPS_TABLE_LEVER.md. Same reasoning
# throughout: a point class the FGD cannot express, on a scene that is
# rewritten from scratch every rebuild.
#
# Neither can come out of the .map. This project's FGD has only SOLID classes
# — worldspawn, func_detail, func_detail_illusionary, func_geo, func_illusionary
# — and no point class at all, so there is nothing to put an empty in.
#
# And they cannot simply be added to the .tscn by hand, because
# tools/block_prefabs.gd builds that scene FROM SCRATCH on every rebuild: it
# makes a fresh root, adds one FuncGodotMap, and saves over the top. Anything
# hand-added is silently gone the next time the car's geometry changes. That
# has already happened once in this project, to hand-placed objectives on a
# regenerated terrain map, and the lesson was to make the re-application a
# script rather than a memory.
#
# So: rebuild the car, then run this. It is IDEMPOTENT — it updates the nodes
# if they are already there rather than adding a second set — so running it
# twice is harmless and running it after every rebuild is the intended use.
#
# `--check` reports what it would do and writes nothing. Use it in a gate.
#
# The geometry it depends on lives in tools/block_railhead.gd as TABLE_TOP and
# the slab's half-extents, and the contract those satisfy is written down in
# docs/briefs/OPS_TABLE_FURNITURE.md. If the table moves, change the constants
# below to match and run this again.
# ─────────────────────────────────────────────

const CAR := "res://maps/blocks/railhead/railhead_car_ops.tscn"
const INTERACTIBLE := "res://Env/world_objects/components/template_interactible.tscn"

## Must agree with block_railhead.gd's TABLE_TOP and the slab box in _car_ops.
const TABLE_TOP := 0.95
const SLAB_HX := 3.5
const SLAB_HY := 1.5
## The anchor's name is part of the contract with GAMEPLAY's ops_table.gd.
const ANCHOR := "OpsTableAnchor"

## ─────────────────────────────────────────────
## THE DEPARTURE LEVER'S EMPTY. Same deal as the table's: a point class this
## project's FGD cannot express, on a scene that gets rewritten from scratch
## every rebuild, so it is seated by script. The handle itself is generated at
## runtime by Env/world_objects/departure_lever.gd — a handle drawn in the .map
## is welded into the car's one merged mesh and cannot rotate.
##
## Design and the geometry TERRAIN builds around it:
## docs/briefs/OPS_TABLE_LEVER.md.
##
## WHY IT IS OUTBOARD OF THE SLAB, which is the whole reason these numbers are
## what they are. The table's own Interactible is sized to the full slab
## footprint and 1.4 m tall, so it fills Godot Z [-3.5, +3.5] from 0.30 to 1.70
## — and an interact ray is a RayCast3D, which returns the CLOSEST collider.
## Anything inside that box is unreachable: F gets the table, every time.
##
##   lever volume   Z [-4.18, -3.62]   (centre -3.90, depth 0.56)
##   table volume   Z [-3.50, +3.50]
##   clearance      0.12 m
##
## The handle's arc has to live in that gap too. At arm_length 0.35 the knob
## swings from Z -3.82 (stowed, -20 degrees) to Z -4.05 (thrown, -80), both
## inside the lever's own volume and both clear of the table's. Changing
## departure_lever.gd's angles or arm length means re-checking that.
const LEVER := "OpsLeverAnchor"
## Out along the car from the table's centre. Past SLAB_HX, under the housing
## TERRAIN hangs off the plinth's end face.
const LEVER_OUT := 3.7
## Pivot height, inside the plinth face's clear band (0.12 .. 0.89) so the
## housing can carry it. Not on top of the slab: nothing stands on the slab,
## because the runtime projection's 6.6 x 2.7 m plate leaves 0.16 m of bare
## surface and the projection draws additively with no depth test.
const LEVER_PIVOT_Y := 0.80
## Its interact volume. Height and the 0.15 lift match the table's for the same
## reason — a box hung entirely below the surface is one the player's 1.50 m
## eye ray sails straight over unless they happen to be looking steeply down.
## RESIZED when the handle grew from 0.35 m to 0.95. A 0.95 m arm swinging
## -20 to -80 degrees sweeps its knob from Z -4.05 to -4.70 and from Y 0.98 up
## to 1.76, none of which fitted the old 0.56-deep box — the handle would have
## hung outside its own trigger, which looks identical to a broken lever.
##
## Kept as tight as the arc allows rather than padded out. The player walks to
## the end of the table to use this, and a volume stretched toward them is one
## they end up standing INSIDE, where the interact ray reports nothing at all.
const LEVER_BOX := Vector3(1.2, 1.6, 0.86)
const LEVER_BOX_OFFSET := Vector3(0.0, 0.55, -0.69)

var _check := false
var _changed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--check":
			_check = true

	var packed: PackedScene = load(CAR)
	if packed == null:
		printerr("fit_ops_table: could not load %s" % CAR)
		quit(1)
		return
	var root_node: Node = packed.instantiate()

	_fit_anchor(root_node)
	_fit_lever(root_node)

	if not _changed:
		print("  nothing to do — both anchors and their Interactibles are already in place")
		root_node.free()
		quit(0)
		return
	if _check:
		print("")
		print("  --check: nothing written. Re-run without it to apply.")
		root_node.free()
		quit(1)
		return

	var out := PackedScene.new()
	if out.pack(root_node) != OK:
		printerr("fit_ops_table: pack failed")
		root_node.free()
		quit(1)
		return
	var err := ResourceSaver.save(out, CAR)
	if err != OK:
		printerr("fit_ops_table: could not write %s (%s)" % [CAR, error_string(err)])
		root_node.free()
		quit(1)
		return
	print("")
	print("  written: %s" % CAR)
	root_node.free()
	quit(0)


func _fit_anchor(root_node: Node) -> void:
	# Centre of the slab's TOP face. ops_table.gd floats the projection 0.04 m
	# above this, so the anchor is the surface and not the surface plus a gap.
	var anchor := _seat_empty(root_node, ANCHOR, Vector3(0.0, TABLE_TOP, 0.0))
	if anchor == null:
		return
	# MIND THE AXES. The slab is written in the .map as x +/-SLAB_HX by
	# y +/-SLAB_HY, and FuncGodot maps Quake (x, y, z) onto Godot (y, z, x) —
	# so the car's long axis is GODOT Z and its width is GODOT X. Sizing this
	# box (SLAB_HX*2, _, SLAB_HY*2) looks right and is transposed: it overhangs
	# the table by 0.4 m across the car and falls 0.4 m short along it.
	#
	# Centred 0.05 above the anchor, so the volume runs 0.30..1.70 in the car:
	# from under the slab to just over a standing player's eye.
	_seat_interactible(root_node, anchor, Vector3(SLAB_HY * 2.0, 1.4, SLAB_HX * 2.0), Vector3(0.0, 0.05, 0.0))


## The departure lever's pivot, outboard of the table's exit end. The constants
## above carry the arithmetic and the reason for every one of them.
func _fit_lever(root_node: Node) -> void:
	var anchor := _seat_empty(root_node, LEVER, Vector3(0.0, LEVER_PIVOT_Y, -LEVER_OUT))
	if anchor == null:
		return
	_seat_interactible(root_node, anchor, LEVER_BOX, LEVER_BOX_OFFSET)


## An empty at `want`, added if absent and moved if it has drifted. Idempotent,
## which is the whole point of this script: TERRAIN re-runs it after every
## geometry rebuild and running it twice must be harmless.
func _seat_empty(root_node: Node, named: String, want: Vector3) -> Node3D:
	var anchor: Node3D = root_node.get_node_or_null(named) as Node3D
	if anchor == null:
		anchor = Node3D.new()
		anchor.name = named
		root_node.add_child(anchor)
		anchor.owner = root_node
		_changed = true
		print("  + %s added" % named)
	if not anchor.position.is_equal_approx(want):
		print("  ~ %s moved %v -> %v" % [named, anchor.position, want])
		anchor.position = want
		_changed = true
	return anchor


## An Interactible under `anchor`, with a box of exactly `size` at `offset`.
##
## SIZE IT TO THE THING AND NO BIGGER. The player's interact ray is 2 m and
## does not register from INSIDE a volume, so an oversized box makes the prompt
## vanish exactly as you walk up to whatever it is on.
##
## A fresh BoxShape3D, never a resize of whatever the template carries: a shape
## authored in a scene is one shared resource, and resizing it in place changes
## every other instance of that prefab. The template ships with no shape at all
## today, so this also just makes it work.
##
## AND THE HEIGHT IS NOT THE OBJECT'S HEIGHT. Only the FOOTPRINT has to match;
## the vertical extent has to cover the heights an interact ray is actually
## cast at. The table sized 0.9 and hung under its surface spanned 0.05..0.95 —
## entirely below the top — and the player's ray, cast from a 1.50 m eye,
## sailed over it unless they happened to be looking steeply down. 1.4
## straddling the surface puts eye level inside it. The player still stands
## OUTSIDE the box horizontally, which is what the 2 m ray needs.
##
## destroy_on_use / disable_on_use are deliberately untouched: interactible.gd
## clears both on ready, and a table you can use once is not a table.
func _seat_interactible(root_node: Node, anchor: Node3D, size: Vector3, offset: Vector3) -> void:
	var inter: Node = anchor.get_node_or_null("Interactible")
	if inter == null:
		var tmpl: PackedScene = load(INTERACTIBLE)
		if tmpl == null:
			printerr("fit_ops_table: could not load %s" % INTERACTIBLE)
			return
		inter = tmpl.instantiate()
		anchor.add_child(inter)
		_set_owner_deep(inter, root_node)
		_changed = true
		print("  + Interactible added under %s" % anchor.name)

	var cs: CollisionShape3D = inter.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		printerr("fit_ops_table: the Interactible template has no CollisionShape3D")
		return
	var box: BoxShape3D = cs.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		cs.shape = box
		_changed = true
		print("  + %s Interactible given a BoxShape3D" % anchor.name)
	elif not box.size.is_equal_approx(size):
		box = box.duplicate()
		cs.shape = box
		_changed = true
	if not box.size.is_equal_approx(size):
		print("  ~ %s Interactible box %v -> %v" % [anchor.name, box.size, size])
		box.size = size
		_changed = true
	if not cs.position.is_equal_approx(offset):
		print("  ~ %s Interactible shape moved %v -> %v" % [anchor.name, cs.position, offset])
		cs.position = offset
		_changed = true


func _set_owner_deep(n: Node, root_node: Node) -> void:
	n.owner = root_node
	for c in n.get_children():
		_set_owner_deep(c, root_node)
