extends SceneTree

# ─────────────────────────────────────────────
# MAP OVERLAP — which brushes of a .map file interpenetrate, by the same
# numbering TrenchBroom uses, so a reported pair can be selected in the editor.
#
#   MAP=res://maps/proving/proving_level.map godot --headless --path . \
#       --script res://tools/probe_map_overlap.gd
#
# Headless is fine: this does its own geometry and never touches the physics
# server or the renderer.
#
# WHY THIS EXISTS WHEN EVERY BLOCK TOOL ALREADY HAS A CLEARANCE CHECK. Because
# each of those checks the thing it was written for and nothing else.
# block_arena tests the 56 COVER footprints against each other and prints
# "none overlapping" over a map with plenty of overlaps in it: it never looks at
# the ground, the lanes, the tower, the bases or the skyline, and it compares 2D
# boxes rather than solids. The fortress ring checker had the same fault. A
# checker that skips a category hides every fault in that category, so this one
# has no categories — it reads the written file and tests every brush against
# every other brush.
#
# HOW. A .map brush IS an intersection of half-spaces, which is exactly what
# Geometry3D.compute_convex_mesh_points wants, so a brush corners itself out of
# its own face planes with no hull building anywhere. Two brushes overlap if the
# union of their planes still encloses a volume.
#
# EVERY PLANE IS PULLED IN BY MARGIN FIRST, because brushes are MEANT to share
# faces — a wall butted against a wall is the whole idea of brush geometry. A
# shared face erodes to nothing; a real interpenetration survives. At a quarter
# unit, anything sharing more than half a unit (1.6 cm) reports, which is tight
# and right for geometry written on a 1-unit grid.
# ─────────────────────────────────────────────

## Units per metre, as FuncGodot reads the file.
const UPM := 32.0
## How far each face plane moves inward before testing, in Quake units.
const MARGIN := 0.25
## Pairs to print before summarising.
const SHOW := 400


class Brush:
	var ent := 0		## entity index, as the // entity comments number it
	var idx := 0		## brush index within that entity, ditto
	var classname := ""
	var planes: Array[Plane] = []
	var points: PackedVector3Array = []
	var aabb := AABB()
	var tex := {}		## texture name -> face count, for naming the thing

	func label() -> String:
		return "e%d/b%d" % [ent, idx]

	## The texture most of its faces wear, which is what a brush looks like.
	func main_tex() -> String:
		var best := ""
		var n := 0
		for k: String in tex:
			if int(tex[k]) > n:
				n = int(tex[k])
				best = k
		return best.get_file()


func _initialize() -> void:
	var path := OS.get_environment("MAP")
	if path == "":
		print("usage: MAP=res://maps/<name>.map")
		quit(2)
		return
	if not path.begins_with("res://") and not path.is_absolute_path():
		path = "res://" + path
	var brushes := _parse(path)
	if brushes.is_empty():
		print("FAIL  no brushes read from %s" % path)
		quit(1)
		return
	print("   %s" % path)
	print("   %d brush(es) in %d entity(s)" % [brushes.size(), _entity_count(brushes)])
	var thin := 0
	for b: Brush in brushes:
		if b.points.size() < 4:
			thin += 1
			print("   %-9s %-22s DEGENERATE — %d corner(s), it builds as nothing" % [
					b.label(), b.main_tex(), b.points.size()])
	var pairs: Array = []
	for i in brushes.size():
		var a: Brush = brushes[i]
		if a.points.size() < 4:
			continue
		for j in range(i + 1, brushes.size()):
			var b: Brush = brushes[j]
			if b.points.size() < 4:
				continue
			if not a.aabb.intersects(b.aabb):
				continue
			var shared := _shared(a, b)
			if shared.size == Vector3.ZERO:
				continue
			pairs.append([shared.size.x * shared.size.y * shared.size.z, a, b, shared])
	pairs.sort_custom(func(p, q): return float(p[0]) > float(q[0]))
	if pairs.is_empty():
		print("   no overlapping brush pairs")
	else:
		print("")
		print("   %-9s %-9s %-42s %s" % ["brush", "and", "shared space (m)", "textures"])
		for k in mini(pairs.size(), SHOW):
			var row: Array = pairs[k]
			var a: Brush = row[1]
			var b: Brush = row[2]
			var s: AABB = row[3]
			print("   %-9s %-9s %6.2f x %6.2f x %6.2f at (%7.2f %7.2f %7.2f)  %s / %s" % [
					a.label(), b.label(),
					s.size.x / UPM, s.size.y / UPM, s.size.z / UPM,
					s.get_center().x / UPM, s.get_center().y / UPM, s.get_center().z / UPM,
					a.main_tex(), b.main_tex()])
		if pairs.size() > SHOW:
			print("   ... and %d more" % (pairs.size() - SHOW))
	print("")
	print("   %d overlapping pair(s), %d degenerate brush(es)" % [pairs.size(), thin])
	quit(1 if pairs.size() > 0 or thin > 0 else 0)


## The volume two brushes share, as a box, or a zero-size AABB if they only
## touch. Both sets of planes pulled in by MARGIN, then asked what is left.
func _shared(a: Brush, b: Brush) -> AABB:
	var planes: Array[Plane] = []
	for p: Plane in a.planes:
		planes.append(Plane(p.normal, p.d - MARGIN))
	for p: Plane in b.planes:
		planes.append(Plane(p.normal, p.d - MARGIN))
	var pts := Geometry3D.compute_convex_mesh_points(planes)
	if pts.size() < 4:
		return AABB()
	var box := AABB(pts[0], Vector3.ZERO)
	for p: Vector3 in pts:
		box = box.expand(p)
	return box


func _entity_count(brushes: Array) -> int:
	var seen := {}
	for b: Brush in brushes:
		seen[b.ent] = true
	return seen.size()


## A Valve-220 .map, read for geometry only. Entity and brush numbering comes
## off the braces rather than the // comments, so a file that has been through
## TrenchBroom and lost them still reads the same way.
func _parse(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("FAIL  could not read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return []
	var out: Array = []
	var depth := 0
	var ent := -1
	var b_idx := 0
	var classname := ""
	var cur: Brush = null
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("//") or line == "":
			continue
		if line == "{":
			depth += 1
			if depth == 1:
				ent += 1
				b_idx = 0
				classname = ""
			elif depth == 2:
				cur = Brush.new()
				cur.ent = ent
				cur.idx = b_idx
			continue
		if line == "}":
			if depth == 2 and cur != null:
				cur.classname = classname
				_finish(cur)
				out.append(cur)
				cur = null
				b_idx += 1
			depth -= 1
			continue
		if depth == 1 and line.begins_with("\""):
			var parts := line.split("\" \"")
			if parts.size() == 2 and parts[0].trim_prefix("\"") == "classname":
				classname = parts[1].trim_suffix("\"")
				# The brushes already read were numbered before the classname
				# line turned up, so backfill them.
				for done: Brush in out:
					if done.ent == ent:
						done.classname = classname
			continue
		if depth == 2 and cur != null and line.begins_with("("):
			_face(cur, line)
	f.close()
	return out


## One face line: three points in parentheses, the texture, then the Valve
## axes, which this tool does not care about.
func _face(b: Brush, line: String) -> void:
	var pts: Array[Vector3] = []
	var at := 0
	for _i in 3:
		var open := line.find("(", at)
		var close := line.find(")", open)
		if open < 0 or close < 0:
			return
		var nums := line.substr(open + 1, close - open - 1).strip_edges().split(" ", false)
		if nums.size() < 3:
			return
		pts.append(Vector3(float(nums[0]), float(nums[1]), float(nums[2])))
		at = close + 1
	var rest := line.substr(at).strip_edges().split(" ", false)
	if rest.size() > 0:
		var t: String = rest[0]
		b.tex[t] = int(b.tex.get(t, 0)) + 1
	# Quake lists a face’s three points clockwise seen from OUTSIDE, so this
	# cross product is the outward normal and the solid is where n.x <= d.
	var n := (pts[2] - pts[0]).cross(pts[1] - pts[0])
	if n.length_squared() < 1e-9:
		return			# three collinear points: not a plane
	n = n.normalized()
	b.planes.append(Plane(n, n.dot(pts[0])))


func _finish(b: Brush) -> void:
	b.points = Geometry3D.compute_convex_mesh_points(b.planes)
	if b.points.size() == 0:
		return
	b.aabb = AABB(b.points[0], Vector3.ZERO)
	for p: Vector3 in b.points:
		b.aabb = b.aabb.expand(p)
