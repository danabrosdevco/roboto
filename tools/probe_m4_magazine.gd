extends SceneTree

# ─────────────────────────────────────────────
# WHERE THE ANCIENT RIFLE'S MAGAZINE ACTUALLY IS.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_m4_magazine.gd
#
# The rifle imports as ONE MeshInstance3D whose surfaces are split by material
# and span the whole weapon, so the magazine is separated at load by taking the
# triangles whose centroid falls inside a measured box
# (PlayerAncientRifle.MAG_BOXES), then clipped at PlayerAncientRifle.MAG_LIP.
#
# NOTE WHAT THIS CAN AND CANNOT TELL YOU. It reports the BOXES only, so a
# triangle the boxes leave behind may still be cut in half by the plane and be
# perfectly fine. It is for reading the geometry and finding candidates; what
# actually came away is a question for tools/probe_m4_split_shot.gd.
#
# This prints the geometry BELOW THE BORE as a grid, so the magazine, the
# trigger guard and the gap between them can be read off rather than guessed,
# and then says what the current boxes would and would not take.
# ─────────────────────────────────────────────

const SCENE := "res://Character/weapon/m4_hud_weapon.tscn"
const RIFLE := preload("res://Character/weapon/player_ancient_rifle.gd")

## Everything under the RECEIVER, not under the bore. It was 0.0 — the bore line
## — and that is exactly where the shroud hid: the piece left hanging on the gun
## sits at y +0.02 to +0.10, above the bore and below the receiver, so a probe
## that stopped at 0 reported a clean cut over a visibly broken one.
const BELOW := 0.12


func _init() -> void:
	var inst: Node = load(SCENE).instantiate()
	root.add_child(inst)
	var mi := _find_mesh(inst)
	if mi == null:
		printerr("no MeshInstance3D under the rifle")
		quit(1)
		return
	print("mesh: %s   surfaces %d" % [mi.name, mi.mesh.get_surface_count()])

	# Every triangle centroid under the bore, with which box (if any) takes it.
	var tris: Array = []
	for s in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var raw = arrays[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = raw if raw != null else PackedInt32Array()
		if idx.is_empty():
			for i in verts.size():
				idx.append(i)
		for t in range(0, idx.size() - 2, 3):
			var mid: Vector3 = (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			if mid.y < BELOW:
				tris.append(mid)

	print("%d triangle(s) below y=%.2f" % [tris.size(), BELOW])
	print("")
	print("── X PROFILE (each row 0.05 wide): count, y range ──")
	var buckets := {}
	for p in tris:
		var k := int(floor(p.x / 0.05))
		if not buckets.has(k):
			buckets[k] = {"n": 0, "lo": 99.0, "hi": -99.0, "zlo": 99.0, "zhi": -99.0, "in": 0}
		var b = buckets[k]
		b["n"] += 1
		b["lo"] = minf(b["lo"], p.y)
		b["hi"] = maxf(b["hi"], p.y)
		b["zlo"] = minf(b["zlo"], p.z)
		b["zhi"] = maxf(b["zhi"], p.z)
		for box in RIFLE.MAG_BOXES:
			if box.has_point(p):
				b["in"] += 1
				break
	var keys := buckets.keys()
	keys.sort()
	print("   x from   x to    tris   y low   y high   z low  z high   taken by current boxes")
	for k in keys:
		var b = buckets[k]
		var flag := ""
		if int(b["in"]) == 0:
			flag = "   none"
		elif int(b["in"]) == int(b["n"]):
			flag = "   ALL"
		else:
			flag = "   PARTIAL <-- a cut runs through this slice"
		print("   %6.2f  %6.2f  %6d  %6.2f  %7.2f  %6.2f  %6.2f  %4d/%-4d%s" % [
			float(k) * 0.05, float(k + 1) * 0.05, b["n"], b["lo"], b["hi"],
			b["zlo"], b["zhi"], b["in"], b["n"], flag])

	_leftovers(mi)
	_grid(tris)
	inst.free()
	quit(0)


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		if (n as MeshInstance3D).mesh.get_surface_count() > 1:
			return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


## An X/Y grid of the magazine region, so the magwell lip and the gap before
## the trigger guard can be READ rather than guessed. Called from _init when
## GRID=1.
func _grid(tris: Array) -> void:
	print("")
	print("── X/Y GRID, x 0.60..1.30, y -0.80..0.12 (· none, # geometry) ──")
	var cols := 28
	var rows := 18
	var x0 := 0.60
	var x1 := 1.30
	var y0 := -0.80
	var y1 := 0.12
	var cell := {}
	for p in tris:
		if p.x < x0 or p.x >= x1 or p.y < y0 or p.y >= y1:
			continue
		var cx := int((p.x - x0) / (x1 - x0) * float(cols))
		var cy := int((p.y - y0) / (y1 - y0) * float(rows))
		cell["%d,%d" % [cx, cy]] = int(cell.get("%d,%d" % [cx, cy], 0)) + 1
	for r in range(rows - 1, -1, -1):
		var line := "   y %6.2f  " % (y0 + (float(r) + 0.5) * (y1 - y0) / float(rows))
		for c in cols:
			line += "#" if cell.has("%d,%d" % [c, r]) else "·"
		print(line)
	var axis := "             "
	for c in cols:
		axis += "|" if c % 4 == 0 else " "
	print(axis)
	var nums := "             "
	for c in range(0, cols, 4):
		nums += "%-4.2f" % (x0 + float(c) * (x1 - x0) / float(cols))
	print(nums)


## Every triangle in the magazine neighbourhood that the current BOXES do NOT
## take. Candidates for a fault, not proof of one — the clip plane may still cut
## through them. Their bounds are what a box has to grow to cover if one must.
func _leftovers(mi: MeshInstance3D) -> void:
	var region := AABB(Vector3(0.55, -1.10, -0.20), Vector3(0.62, 1.22, 0.40))
	var left: Array = []
	for s in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var raw = arrays[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = raw if raw != null else PackedInt32Array()
		if idx.is_empty():
			for i in verts.size():
				idx.append(i)
		for t in range(0, idx.size() - 2, 3):
			var mid: Vector3 = (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			if not region.has_point(mid):
				continue
			var taken := false
			for box in RIFLE.MAG_BOXES:
				if box.has_point(mid):
					taken = true
					break
			if not taken:
				left.append(mid)
	print("")
	print("── LEFT BEHIND in the magazine region: %d triangle(s) ──" % left.size())
	if left.is_empty():
		return
	var lo := Vector3(99, 99, 99)
	var hi := Vector3(-99, -99, -99)
	for p in left:
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		print("     (%6.3f, %6.3f, %6.3f)" % [p.x, p.y, p.z])
	print("   bounds  x %.3f..%.3f   y %.3f..%.3f   z %.3f..%.3f" % [
		lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
