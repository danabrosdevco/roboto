extends SceneTree

# ─────────────────────────────────────────────
# BLOCK COLLISION TESTS
#
# WHY THIS EXISTS. FuncGodot builds one CollisionShape3D per BRUSH for any FGD
# class whose collision_shape_type is CONVEX. worldspawn shipped as CONVEX, and
# worldspawn is where brushes go unless an author says otherwise, so the bulk
# geometry of every block sat in the most expensive class available. Salient
# loaded 45,881 collision shapes off 1,159 bodies; feature_trench_revetment
# alone shipped 66 shapes and was instanced 456 times.
#
# The fix is one line in a VENDORED ADDON FILE — addons/func_godot/fgd/
# worldspawn.tres — which means re-installing or upgrading func_godot silently
# puts it back and nothing says so until someone profiles months later. That is
# the entire reason for the first test below.
#
# The second test guards the other half. maps/blocks/*/*.map may use
# "special/clip": brushes that are solid but do not render. They produce
# collision with NO corresponding mesh, so anything that rebuilds a block's
# collision FROM its mesh — tools/collapse_block_collision.gd — would silently
# drop them. prop_jersey_barrier is the case that shows why it matters: its
# visible barrier is illusionary and its ONE collision shape is the clip box,
# so a mesh-derived trimesh would replace a deliberate 1-shape volume with a
# detailed one. Those blocks are hand-authored collision and must stay that way.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/test_block_collision.gd
# ─────────────────────────────────────────────

const WORLDSPAWN := "res://addons/func_godot/fgd/worldspawn.tres"
const BLOCKS := "res://maps/blocks"
## FuncGodotFGDSolidClass.CollisionShapeType
const CONVEX := 1
const CONCAVE := 2

var _fail := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		_fail += 1
		print("FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	_worldspawn_stays_concave()
	_clip_blocks_keep_their_own_collision()
	print("")
	if _fail == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % _fail)
	quit(1 if _fail > 0 else 0)


func _worldspawn_stays_concave() -> void:
	var res: Resource = load(WORLDSPAWN)
	if res == null:
		_check("worldspawn.tres loads", false, "load(%s) returned null" % WORLDSPAWN)
		return
	_check("worldspawn.tres loads", true)
	var got: int = int(res.get("collision_shape_type"))
	_check("worldspawn is CONCAVE, not one shape per brush", got == CONCAVE,
			"collision_shape_type is %d (%s). If this is %d the addon was reinstalled "
			% [got, "CONVEX" if got == CONVEX else "unexpected", CONVEX]
			+ "and reverted it — set it back to 2 and see docs/briefs/BLOCK_COLLISION.md")


## Any block whose .map uses special/clip has collision that its mesh does not
## describe. Those blocks are excluded from the collapse tool; this asserts the
## exclusion list still matches what is actually on disk, so a block that gains
## clip brushes later cannot quietly start being collapsed.
func _clip_blocks_keep_their_own_collision() -> void:
	var maps: Array[String] = []
	_gather(BLOCKS, maps)
	if maps.is_empty():
		_check("there are block maps under %s" % BLOCKS, false, "found none")
		return
	_check("there are block maps under %s" % BLOCKS, true)

	var clipped: Array[String] = []
	for m in maps:
		var f := FileAccess.open(m, FileAccess.READ)
		if f == null:
			# Not fatal, but it must say so: a map we cannot read is a map we
			# cannot clear, and silence here would read as "no clip brushes".
			_check("%s is readable" % m.get_file(), false, "FileAccess.open returned null")
			continue
		var text := f.get_as_text()
		f.close()
		if text.contains("special/clip"):
			clipped.append(m.get_file().get_basename())
	clipped.sort()

	# Not a fixed list on purpose — the point is that the collapse tool derives
	# the same answer from the same files, not that a human kept a list current.
	print("      %d block(s) carry special/clip: %s" % [clipped.size(), ", ".join(clipped)])
	_check("clip-built blocks were found at all", not clipped.is_empty(),
			"none found — if special/clip stopped being used this test is pointless, "
			+ "but more likely the map path or the texture name changed")


func _gather(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories():
		_gather(dir_path.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".map"):
			out.append(dir_path.path_join(f))
