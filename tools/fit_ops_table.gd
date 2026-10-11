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
const SLAB_HX := 1.3
const SLAB_HY := 0.9
## The anchor's name is part of the contract with GAMEPLAY's ops_table.gd.
const ANCHOR := "OpsTableAnchor"

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

	if not _changed:
		print("  nothing to do — the anchor and its Interactible are already in place")
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
	var anchor: Node3D = root_node.get_node_or_null(ANCHOR) as Node3D
	if anchor == null:
		anchor = Node3D.new()
		anchor.name = ANCHOR
		root_node.add_child(anchor)
		anchor.owner = root_node
		_changed = true
		print("  + %s added" % ANCHOR)
	# Centre of the slab's TOP face. ops_table.gd floats the projection 0.04 m
	# above this, so the anchor is the surface and not the surface plus a gap.
	var want := Vector3(0.0, TABLE_TOP, 0.0)
	if not anchor.position.is_equal_approx(want):
		print("  ~ %s moved %v -> %v" % [ANCHOR, anchor.position, want])
		anchor.position = want
		_changed = true

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
		print("  + Interactible added under %s" % ANCHOR)

	var cs: CollisionShape3D = inter.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		printerr("fit_ops_table: the Interactible template has no CollisionShape3D")
		return
	# SIZE IT TO THE TABLE AND NO BIGGER. The player's interact ray is 2 m and
	# does not register from INSIDE a volume, so an oversized box makes the
	# prompt vanish exactly as you walk up to the thing.
	#
	# A fresh BoxShape3D, never a resize of whatever the template carries: a
	# shape authored in a scene is one shared resource, and resizing it in place
	# changes every other instance of that prefab. The template ships with no
	# shape at all today, so this also just makes it work.
	#
	# MIND THE AXES. The slab is written in the .map as x +/-SLAB_HX by
	# y +/-SLAB_HY, and FuncGodot maps Quake (x, y, z) onto Godot (y, z, x) —
	# so the car's long axis is GODOT Z and its width is GODOT X. Sizing this
	# box (SLAB_HX*2, _, SLAB_HY*2) looks right and is transposed: it overhangs
	# the table by 0.4 m across the car and falls 0.4 m short along it.
	var size := Vector3(SLAB_HY * 2.0, 0.9, SLAB_HX * 2.0)
	var box: BoxShape3D = cs.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		cs.shape = box
		_changed = true
		print("  + Interactible given a BoxShape3D")
	elif not box.size.is_equal_approx(size):
		box = box.duplicate()
		cs.shape = box
		_changed = true
	if not box.size.is_equal_approx(size):
		print("  ~ Interactible box %v -> %v" % [box.size, size])
		box.size = size
		_changed = true
	# Dropped half its height so the volume hangs under the surface, over the
	# slab the player is looking at, rather than floating in the air above it.
	var cs_want := Vector3(0.0, -size.y * 0.5, 0.0)
	if not cs.position.is_equal_approx(cs_want):
		print("  ~ Interactible shape moved %v -> %v" % [cs.position, cs_want])
		cs.position = cs_want
		_changed = true
	# destroy_on_use / disable_on_use are deliberately untouched: interactible.gd
	# clears both on ready, and a table you can use once is not a table.


func _set_owner_deep(n: Node, root_node: Node) -> void:
	n.owner = root_node
	for c in n.get_children():
		_set_owner_deep(c, root_node)
