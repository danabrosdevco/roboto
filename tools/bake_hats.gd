extends SceneTree

# ─────────────────────────────────────────────
# BAKE THE RANK HEADGEAR TO MESHES, ONCE, HERE.
#
# The hats were authored as CSG in tools/mockup_parts.gd because that is the
# only way to iterate on them — eight rounds of it. CSG must not survive into
# the game: Character/characters/ai/csg_bake.gd exists because a CSGShape3D
# rebuilds its geometry the first time it enters the tree, and a reserve wave of
# 40 robots cost 335.8 ms on that frame. Adding six to ten CSG shapes per robot
# for a hat would hand all of that straight back.
#
# So this does what CsgBake does at startup, but offline and permanently: builds
# each hat, takes the CSG's OWN output through get_meshes(), and writes a scene
# containing nothing but MeshInstance3D nodes sharing those meshes. The shipped
# hats are then as cheap as any other mesh, and CsgBake has nothing to do.
#
# Run:
#   godot --audio-driver Dummy --path . --script res://tools/bake_hats.gd
#
# IT IS IDEMPOTENT. Re-run it whenever a builder in mockup_parts.gd changes; it
# overwrites the scenes in place and nothing else refers to them by content.
# ─────────────────────────────────────────────

const Parts := preload("res://tools/mockup_parts.gd")

const OUT_DIR := "res://Character/characters/ai/hats"

## Which builder goes in which file. Keyed by the name the scene takes, so the
## mapping is readable from a directory listing alone.
static func _hats() -> Array:
	return [
		["rover_beret", Parts.rover_beret],
		["rover_slouch", Parts.rover_slouch],
		["walker_tarleton", Parts.walker_tarleton],
		["walker_peaked_cap", Parts.walker_peaked_cap],
		["walker_bearskin", Parts.walker_bearskin],
		["reclaimer_hardhat", Parts.reclaimer_hardhat],
		["reclaimer_flatcap", Parts.reclaimer_flatcap],
		["soldier_pickelhaube", Parts.soldier_pickelhaube],
		["soldier_brodie", Parts.soldier_brodie],
		["soldier_pads", Parts.soldier_pads],
		["soldier_cap", Parts.soldier_cap],
	]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# One holder, well under the map, for the single frame the CSG needs to
	# exist in the tree before its geometry can be read. Same trick CsgBake uses.
	var holder := Node3D.new()
	holder.name = "BakeProbes"
	holder.position = Vector3(0.0, -10000.0, 0.0)
	root.add_child(holder)

	var built: Dictionary = {}
	for row: Array in _hats():
		var key: String = row[0]
		var rig := Node3D.new()
		rig.name = "Headgear"
		(row[1] as Callable).call(rig)
		# The builders only TAG their pieces; tools/mockup_shots.gd is what
		# turns those tags into materials at render time. Do the same here, so
		# the baked scene carries the right surface instead of default white.
		_paint(rig)
		holder.add_child(rig)
		built[key] = rig

	# ONE frame for every hat together, not one frame each. CSG geometry is not
	# available until the frame after the node enters the tree.
	await process_frame
	await process_frame

	var total := 0
	for key: String in built:
		var rig: Node3D = built[key]
		var baked := _bake(rig, key)
		total += baked
		print("  %-22s %2d meshes" % [key, baked])
	print("bake_hats: %d meshes across %d hats -> %s" % [total, built.size(), OUT_DIR])
	quit(0)


## Tag -> material, in the same order mockup_shots.gd resolves them.
func _paint(rig: Node3D) -> void:
	var armor := Parts.armor_material()
	var wool := Parts.wool_material()
	var fur := Parts.fur_material()
	var steel := Parts.plate_material()
	var hivis := Parts.hivis_material()
	for child in rig.get_children():
		var csg := child as CSGShape3D
		if csg == null:
			continue
		var mat: Material = armor
		if csg.has_meta("wool") or csg.has_meta("fabric"):
			mat = wool
		elif csg.has_meta("fur"):
			mat = fur
		elif csg.has_meta("plate"):
			mat = steel
		elif csg.has_meta("hivis"):
			mat = hivis
		# A CSGCombiner3D has no `material` — the pauldron frusta are combiners,
		# and assigning it threw mid-loop and baked the whole hat to nothing.
		if csg is CSGCombiner3D:
			(csg as CSGCombiner3D).material_override = mat
		else:
			csg.material = mat


## Swap every CSG root under `rig` for a MeshInstance3D carrying its own output,
## then save the result as a scene.
func _bake(rig: Node3D, key: String) -> int:
	var out := Node3D.new()
	out.name = "Headgear"
	var n := 0
	for child in rig.get_children():
		var csg := child as CSGShape3D
		if csg == null:
			continue
		var meshes: Array = csg.get_meshes()
		# get_meshes() is empty for a shape nested inside another CSG root —
		# those are merged into their root and come back through it. Every hat
		# piece is added straight to the rig, so each is its own root; a miss
		# here means a builder changed and started nesting.
		if meshes.size() < 2 or meshes[1] == null:
			push_warning("bake_hats: %s/%s produced no mesh" % [key, csg.name])
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[1]
		mi.transform = csg.transform
		mi.name = "Piece%d" % n
		# The mock-up material rides along so the hat looks right on its own.
		# In game FactionLivery overrides it, which is the point of listing the
		# pieces there — but a hat opened on its own should not be white.
		var src: Material = csg.material_override if csg is CSGCombiner3D else csg.material
		if src != null:
			mi.material_override = src
		# WHICH SURFACE THIS IS, carried into the scene as metadata so RankKit can
		# give it the faction colour on its OWN texture rather than the hull's.
		# The material itself cannot say — by the time it is a baked override it is
		# just a StandardMaterial3D like any other.
		# "fabric" is the camo tag the soldier cap was authored with before wool
		# existed; it maps to wool so that cap does not render in hull concrete.
		for kind in ["wool", "fabric", "fur", "plate", "lame", "hivis"]:
			if csg.has_meta(kind):
				mi.set_meta("surface", "wool" if kind == "fabric" else kind)
				break
		out.add_child(mi)
		n += 1

	for c in out.get_children():
		c.owner = out

	var packed := PackedScene.new()
	if packed.pack(out) != OK:
		push_error("bake_hats: could not pack %s" % key)
		return 0
	var path := "%s/hat_%s.tscn" % [OUT_DIR, key]
	if ResourceSaver.save(packed, path) != OK:
		push_error("bake_hats: could not save %s" % path)
		return 0
	return n
