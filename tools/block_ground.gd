extends "res://tools/block_suburban.gd"

# ─────────────────────────────────────────────
# BLOCK GROUND — square ground tiles in four sizes, so a site can be floored
# to an exact shape with holes in it.
#
#   maps/blocks/ground/tile_*.map
#
#   godot --headless --path . --script res://tools/block_ground.gd -- maps/blocks
#
# WHY TILES AND NOT ONE PLATE. A level used to be floored with one enormous
# slab per material, and then every road, car park aisle and building pad was
# laid ON TOP of it with its own surface at the same height. Two horizontal
# faces at the same height in the same place is the one defect none of the
# other checks can see — the brush probe only compares brushes inside a single
# .map, and the piece-pair test sees almost no shared volume because a road
# bed is 0.3 m deep on a slab that is already there. The depth buffer cannot
# choose between them, so the ground crawls and flickers as the camera moves.
# On Polaris that was 15% of the whole map.
#
# The fix is that the ground must have HOLES where something else brings its
# own surface. Holes need tiles, tiles need sizes, and four sizes — 32, 16, 8
# and 4 m — let a filler subdivide down to a 4 m fit along any edge while
# still laying 32 m plates across open ground. Anything finer is not worth the
# instance count; anything coarser leaves a visible gap at a kerb.
#
# EVERY TILE IS 4 M THICK AND ITS TOP IS AT z = -0.06, so tiles butt on their
# sides without a step and a building founded below ground still has slab to
# be founded in.
#
# WHY -0.06 AND NOT 0. Half the kit carries its own surface at exactly 0 — a
# driveway apron, a storage yard, a loading pad — and flush with the ground is
# two horizontal faces at one height, which is this whole file's reason for
# existing. The clearance has to be made HERE and not in those pieces: lifting
# the aprons instead pushed them up into the shutters, kerbs and walls standing
# on them, 32 overlapping pairs in the self-storage yard alone. 6 cm is twice
# what the coplanar check calls the same plane and a twentieth of what anything
# in the game calls a step.
# ─────────────────────────────────────────────

# 64 m at the top so open ground costs few instances: the first cut topped
# out at 32 and Polaris came back with 1,036 tiles for ground that is mostly
# empty. Down to 4 at the bottom so an edge still lands close to a kerb.
const TILE_SIZES: Array = [64.0, 32.0, 16.0, 8.0, 4.0]
const GROUND_TEX := {
	"asphalt": {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE},
	"dirt": {"top": DIRT, "side": SPOIL, "bottom": SPOIL},
	"grass": {"top": "PSX_Textures/grass_4", "side": SPOIL, "bottom": SPOIL},
}


func _initialize() -> void:
	var base := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_ground.gd -- maps/blocks [--force]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("ground")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var written := 0
	for kind: String in GROUND_TEX:
		for size: float in TILE_SIZES:
			var name := "tile_%s_%d" % [kind, int(size)]
			var path := dir.path_join(name + ".map")
			if FileAccess.file_exists(path) and not force:
				print("SKIP  %s exists — pass --force to overwrite it." % path)
				continue
			_brushes = []
			_ghost_from = -1
			_entities = []
			var h := size * 0.5
			box(Vector3(-h, -h, -4.0), Vector3(h, h, -0.06), GROUND_TEX[kind])
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
				quit(1)
				return
			f.store_string(_map_text())
			f.close()
			written += 1
			print("      %-20s %.0f x %.0f m" % [name, size, size])
	print("BLOCK GROUND DONE: %d written" % written)
	quit()
