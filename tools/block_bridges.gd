extends "res://tools/block_industrial.gd"

# ─────────────────────────────────────────────
# BLOCK BRIDGES — variations on long_bridge.map, the hand-built bridge that
# concrete_bridge.tscn is made from: the same concrete deck between side
# girders under a parapet, with an earth ramp at each end, in other lengths,
# widths and heights, and a few other kinds of crossing, as TrenchBroom blocks:
#
#   maps/blocks/bridges/bridge_*.map — short, medium, long and very long road
#       bridges; a two-lane bridge and a four-lane highway bridge; a steel
#       footbridge; a steel truss bridge; a low causeway; a shelled bridge
#       that can still be crossed on one side; a gorge bridge on tall piers;
#       and an old stone humpback arch.
#
#   godot --headless --path . --script res://tools/block_bridges.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_bridges.gd -- maps/blocks --force [piece names]
#
# Every bridge runs along the prefab's Z (TrenchBroom's X), with its origin in
# the middle of the span at the height of the ground at the ramp feet. The
# squad has to be able to walk over every one, so:
#   - the ramps climb at 1 in 3 at most and meet the deck level with it;
#   - their surfaces run on to TOE below the origin before they stop, so a
#     bank anywhere from TOE under the origin upward buries the foot with no
#     lip to climb. long_bridge.map's ramps stop 0.5 m above its origin, which
#     is why that one has to be sunk into its banks;
#   - tools/test_bridges.gd bakes a navmesh round each prefab and walks onto
#     the deck from both ends.
#
# Built on block_industrial.gd, which this extends: the same brush kit,
# conventions and no-overwrite rule. Build prefabs with block_prefabs.gd.
# ─────────────────────────────────────────────

const BRIDGES := {
	"bridge_short": "_bridge_short",
	"bridge_medium": "_bridge_medium",
	"bridge_long": "_bridge_long",
	"bridge_very_long": "_bridge_very_long",
	"bridge_wide": "_bridge_wide",
	"bridge_highway": "_bridge_highway",
	"bridge_foot": "_bridge_foot",
	"bridge_truss": "_bridge_truss",
	"bridge_truss_long": "_bridge_truss_long",
	"bridge_causeway": "_bridge_causeway",
	"bridge_damaged": "_bridge_damaged",
	"bridge_gorge": "_bridge_gorge",
	"bridge_arch": "_bridge_arch",
}

## Ramps climb 1 in RAMP_RUN: the original's 3 m in 9 m.
const RAMP_RUN := 3.0
## How far below the origin a ramp's surface runs on before it stops.
const TOE := 0.5
## The bottom of the earth under the ramps.
const EARTH_BASE := -1.0
## Embankment sides fall 1 in SIDE_RUN, about 34°: under the navmesh's 45°,
## so the squad can walk up them as well as up the ramp.
const SIDE_RUN := 1.5
const ROAD := DECK
const SETTS := "PSX_Textures/tile_floor_tx_3@0.5"
const ARCH_STONE := "PSX_Textures/concrete_7"


func _initialize() -> void:
	var base := ""
	var force := false
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
		else:
			only.append(a)
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_bridges.gd -- maps/blocks [--force] [piece names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("bridges")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var skipped := 0
	var written := 0
	for name: String in BRIDGES:
		if not only.is_empty() and not only.has(name):
			continue
		var path := dir.path_join(name + ".map")
		if FileAccess.file_exists(path) and not force:
			print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
			skipped += 1
			continue
		_brushes = []
		call(BRIDGES[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		var heavy := "   WARNING over the brush budget" if _brushes.size() > 200 else ""
		print("      %-20s %3d brushes  %s%s" % [name, _brushes.size(), _extent_text(), heavy])
	for n: String in only:
		if not BRIDGES.has(n):
			print("WARNING  no bridge called '%s' — nothing written for it" % n)
	print("BLOCK BRIDGES DONE: %d written%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else ""])
	quit()


# ── Parts ────────────────────────────────────────────────────────────────────
# x runs along the bridge, y across it, z up. The span runs from -span/2 to
# span/2, the deck's top is `h` up and its roadway `w` wide between the side
# walls. Sizes stay on the 1/32 m grid: a hull whose corners have to be
# rounded can come out with two faces a hair apart in angle, and FuncGodot
# drops the corner between them.

## The earth ramp off the end of the deck at x = dir * x0: 0.5 m level with the
## deck, then down at 1 in RAMP_RUN to TOE below the origin, its sides falling
## away 1 in SIDE_RUN to EARTH_BASE. One brush, as the original's ramps are.
func _embankment(x0: float, dir: float, w: float, h: float) -> void:
	var land := x0 + 0.5
	var foot := land + (h + TOE) * RAMP_RUN
	var pts: Array = []
	for s: float in [-1.0, 1.0]:
		var edge := s * w * 0.5
		var toe_top := s * (w * 0.5 + (h - EARTH_BASE) * SIDE_RUN)
		var toe_foot := s * (w * 0.5 + (-TOE - EARTH_BASE) * SIDE_RUN)
		pts.append_array([Vector3(dir * x0, edge, h), Vector3(dir * land, edge, h), Vector3(dir * foot, edge, -TOE),
				Vector3(dir * x0, toe_top, EARTH_BASE), Vector3(dir * land, toe_top, EARTH_BASE), Vector3(dir * foot, toe_foot, EARTH_BASE)])
	solid(pts, SPOIL)


## The abutment under the end of the deck at x = dir * x0: a concrete wall 1 m
## thick, flush with the embankment's slopes behind it, from under the deck
## down to `bottom`.
func _abutment(x0: float, dir: float, w: float, h: float, bottom: float = -6.0) -> void:
	var pts: Array = []
	for x: float in [x0 - 1.0, x0]:
		for s: float in [-1.0, 1.0]:
			var toe := s * (w * 0.5 + (h - EARTH_BASE) * SIDE_RUN)
			pts.append_array([Vector3(dir * x, s * (w * 0.5 + SIDE_RUN), h - 1.0), Vector3(dir * x, toe, EARTH_BASE), Vector3(dir * x, toe, bottom)])
	solid(pts, CONCRETE)


## The deck, 1 m thick, and on each edge the original's side wall, 1 m thick:
## the girder `depth` below the deck's top and the parapet `par` above it.
func _deck(span: float, w: float, h: float, depth: float, par: float = 1.0) -> void:
	box(Vector3(-span * 0.5, -w * 0.5, h - 1.0), Vector3(span * 0.5, w * 0.5, h), ROAD)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-span * 0.5, minf(s * w * 0.5, s * (w * 0.5 + 1.0)), h - depth),
				Vector3(span * 0.5, maxf(s * w * 0.5, s * (w * 0.5 + 1.0)), h + par), ROAD)


## A wall pier across the bridge at x, one brush from `bottom` up to the
## deck's underside, with cutwaters pointing up- and downstream. `flare` > 1
## widens it toward its foot, scaled evenly so its faces stay flat.
##
## No separate cap on top of it. The navmesh baker sees surfaces, not solids:
## the top of a pier with a 3 m cap resting on it baked as a floor inside the
## cap, 3 m clear. Stacked pieces meet at the deck's underside instead, where
## the 1 m of deck above leaves no room to stand.
func _wall_pier(x: float, w: float, h: float, bottom: float, flare: float = 1.0) -> void:
	var half := w * 0.5 + 0.5
	var pts: Array = []
	for lvl: Array in [[bottom, flare], [h - 1.0, 1.0]]:
		var z: float = lvl[0]
		var k: float = lvl[1]
		pts.append_array([Vector3(x - 0.75 * k, -half * k, z), Vector3(x + 0.75 * k, -half * k, z), Vector3(x + 0.75 * k, half * k, z),
				Vector3(x - 0.75 * k, half * k, z), Vector3(x, -(half + 1.25) * k, z), Vector3(x, (half + 1.25) * k, z)])
	solid(pts, CONCRETE)


## A highway pier: round columns at `ys` under a crosshead the girders sit on.
## The columns run up through the crosshead to the deck, for the reason in
## _wall_pier: stopped under it, each column top baked as a floor inside it.
func _column_pier(x: float, w: float, h: float, depth: float, bottom: float, ys: Array) -> void:
	for y: float in ys:
		cylinder(Vector3(x, y, bottom), 1.0, h - 1.0 - bottom, 12, CONCRETE)
	box(Vector3(x - 1.25, -w * 0.5 - 1.0, h - depth - 1.0), Vector3(x + 1.25, w * 0.5 + 1.0, h - 1.0), CONCRETE)


## A road bridge in the original's manner: the deck and its side walls on
## `piers` evenly spaced piers of `kind`, an abutment and an embankment at
## each end. The girders deepen with the distance between supports, as the
## original's 50 m span has side walls 5 m deep. Returns that depth.
func _road_bridge(span: float, w: float, h: float, piers: int, kind: String = "wall", bottom: float = -8.0, par: float = 1.0) -> float:
	var sub := span / (piers + 1)
	var depth := clampf(snappedf(sub / 12.0 + 0.5, 0.25), 1.25, 3.5)
	_deck(span, w, h, depth, par)
	for i in piers:
		var x := -span * 0.5 + sub * (i + 1)
		match kind:
			"wall":
				_wall_pier(x, w, h, bottom)
			"tapered":
				_wall_pier(x, w, h, bottom, 1.5)
			"columns":
				_column_pier(x, w, h, depth, bottom, [-w * 0.3, w * 0.3])
			"culvert":
				box(Vector3(x - 0.375, -w * 0.5 - 1.0, bottom), Vector3(x + 0.375, w * 0.5 + 1.0, h - 1.0), CONCRETE)
			_:
				push_warning("block_bridges: no pier kind '%s' — pier at x %.1f left out" % [kind, x])
	for dir: float in [-1.0, 1.0]:
		_abutment(span * 0.5, dir, w, h)
		_embankment(span * 0.5, dir, w, h)
	return depth


## Road paint along x at y: dashes `dash` long with `gap` between, or one
## solid line when gap is 0. Two units thick, a step the squad never notices.
func _paint(x0: float, x1: float, y: float, h: float, dash: float = 0.0, gap: float = 0.0) -> void:
	if gap <= 0.0:
		box(Vector3(x0, y - 0.0625, h), Vector3(x1, y + 0.0625, h + 0.0625), PAINT)
		return
	var x := x0 + gap * 0.5
	while x + dash <= x1:
		box(Vector3(x, y - 0.0625, h), Vector3(x + dash, y + 0.0625, h + 0.0625), PAINT)
		x += dash + gap


## Lamp standards on both parapets at each of `xs`, arms reaching over the road.
func _parapet_lamps(xs: Array, w: float, h: float, par: float = 1.0) -> void:
	for x: float in xs:
		for s: float in [-1.0, 1.0]:
			lamp_at(Vector3(x, s * (w * 0.5 + 0.5), h + par), -90.0 * s)


# ── Road bridges ─────────────────────────────────────────────────────────────

## A 12 m culvert bridge for a creek or a ditch, 8 m wide and 2.25 m up.
func _bridge_short() -> void:
	_road_bridge(12.0, 8.0, 2.25, 0)


## The original's section over 30 m in one span.
func _bridge_medium() -> void:
	_road_bridge(30.0, 10.0, 3.5, 0)


## 72 m in three spans on two wall piers, 4 m up.
func _bridge_long() -> void:
	_road_bridge(72.0, 10.0, 4.0, 2)


## 128 m in four spans on three wall piers, 5 m up: for the widest rivers.
func _bridge_very_long() -> void:
	_road_bridge(128.0, 10.0, 5.0, 3)


## Two lanes, 16 m between the parapets and 36 m in one span, with a dashed
## centre line, edge lines and four lamps.
func _bridge_wide() -> void:
	var span := 36.0
	var w := 16.0
	var h := 3.5
	_road_bridge(span, w, h, 0)
	_paint(-span * 0.5, span * 0.5, 0.0, h, 3.0, 3.0)
	for s: float in [-1.0, 1.0]:
		_paint(-span * 0.5, span * 0.5, s * (w * 0.5 - 0.5), h)
	_parapet_lamps([-9.0, 9.0], w, h)


## A four-lane highway, 24 m between the parapets and 84 m long on two
## column piers: two carriageways either side of a median barrier, which
## stops short of the ramps so the lanes join there. Lane lines and lamps.
func _bridge_highway() -> void:
	var span := 84.0
	var w := 24.0
	var h := 5.5
	_road_bridge(span, w, h, 2, "columns")
	for prof: Array in [[Vector2(-0.3125, 0.0), Vector2(0.3125, 0.0), Vector2(0.3125, 0.125), Vector2(0.15625, 0.3125), Vector2(-0.15625, 0.3125), Vector2(-0.3125, 0.125)],
			[Vector2(-0.15625, 0.3125), Vector2(0.15625, 0.3125), Vector2(0.09375, 0.8125), Vector2(-0.09375, 0.8125)]]:
		var pts: Array = []
		for x: float in [-span * 0.5, span * 0.5]:
			for q: Vector2 in prof:
				pts.append(Vector3(x, q.x, h + q.y))
		solid(pts, FRAME)
	for s: float in [-1.0, 1.0]:
		_paint(-span * 0.5, span * 0.5, s * 1.0, h)
		_paint(-span * 0.5, span * 0.5, s * (w * 0.5 - 0.5), h)
		_paint(-span * 0.5, span * 0.5, s * 6.5, h, 3.0, 6.0)
	_parapet_lamps([-31.5, -10.5, 10.5, 31.5], w, h)


## A low causeway, 48 m on culvert walls every 6 m: a slab 1.25 m up with a
## kerb instead of a parapet and bollards along it, and short ramps.
func _bridge_causeway() -> void:
	var span := 48.0
	var w := 8.0
	var h := 1.25
	_road_bridge(span, w, h, 7, "culvert", -3.0, 0.25)
	for i in 13:
		var x := -24.0 + i * 4.0
		for s: float in [-1.0, 1.0]:
			post(x, s * (w * 0.5 + 0.5), h + 0.25, h + 1.0, 0.25, FRAME)


## A deck across a gorge: level with the rims but for a 0.75 m hump at each
## end, in three spans on two tapered piers standing from 18 m down.
func _bridge_gorge() -> void:
	_road_bridge(48.0, 8.0, 0.75, 2, "tapered", -18.0)


## The medium bridge's section over 40 m after a shell hit: a hole through
## the deck on one side, the parapet gone above it and slabs hanging into it,
## rubble and scorching, a burnt car and a barrier knocked askew. The other
## side is left clear, 5.5 m wide past the hole, so the bridge still carries
## the squad across.
func _bridge_damaged() -> void:
	var span := 40.0
	var w := 10.0
	var h := 3.5
	var depth := 3.5
	# The deck in three pieces round a hole at x -3..4, y 0.5..5.
	box(Vector3(-20.0, -5.0, h - 1.0), Vector3(-3.0, 5.0, h), ROAD)
	box(Vector3(4.0, -5.0, h - 1.0), Vector3(20.0, 5.0, h), ROAD)
	box(Vector3(-3.0, -5.0, h - 1.0), Vector3(4.0, 0.5, h), ROAD)
	# The side walls: the far one whole; the near one with its parapet broken
	# off over the hole, jagged at the ends, and the girder bitten below it.
	box(Vector3(-20.0, -6.0, h - depth), Vector3(20.0, -5.0, h + 1.0), ROAD)
	box(Vector3(-20.0, 5.0, h - depth), Vector3(-4.5, 6.0, h + 1.0), ROAD)
	box(Vector3(5.5, 5.0, h - depth), Vector3(20.0, 6.0, h + 1.0), ROAD)
	box(Vector3(-4.5, 5.0, h - depth), Vector3(5.5, 6.0, h - 1.5), ROAD)
	solid([Vector3(-4.5, 5.0, h - 1.5), Vector3(-4.5, 6.0, h - 1.5), Vector3(-4.5, 5.0, h + 1.0), Vector3(-4.5, 6.0, h + 1.0),
			Vector3(-3.0, 5.0, h - 1.5), Vector3(-3.0, 6.0, h - 1.5), Vector3(-3.75, 5.0, h + 0.25), Vector3(-3.75, 6.0, h + 0.25)], ROAD)
	solid([Vector3(5.5, 5.0, h - 1.5), Vector3(5.5, 6.0, h - 1.5), Vector3(5.5, 5.0, h + 1.0), Vector3(5.5, 6.0, h + 1.0),
			Vector3(4.0, 5.0, h - 1.5), Vector3(4.0, 6.0, h - 1.5), Vector3(4.75, 5.0, h), Vector3(4.75, 6.0, h)], ROAD)
	tipped_box(Vector3(-1.5, 2.75, h - 1.75), Vector3(2.75, 3.0, 0.75), Vector3(40.0, 0.0, 10.0), ROAD)
	tipped_box(Vector3(2.5, 3.5, h - 1.5), Vector3(2.0, 2.5, 0.75), Vector3(-32.0, 12.0, -6.0), ROAD)
	box(Vector3(-6.0, -1.5, h), Vector3(7.0, 0.5, h + 0.0625), SCORCH)
	heap(Vector3(-6.5, 2.75, h), 2.0, 1.5, 0.625, 7, RUBBLE)
	heap(Vector3(7.5, 3.0, h), 1.625, 1.375, 0.5, 11, RUBBLE)
	car_at(Vector3(10.0, -2.5, h), 12.0, SCORCH)
	jersey_at(Vector3(-11.0, 1.5, h), 70.0)
	for dir: float in [-1.0, 1.0]:
		_abutment(span * 0.5, dir, w, h)
		_embankment(span * 0.5, dir, w, h)


# ── Steel ────────────────────────────────────────────────────────────────────

## A steel footbridge, 30 m over two spans: a grated deck 3 m wide on two box
## girders and one column, railed both sides, with a concrete ramp at each
## end at 1 in RAMP_RUN, railed too, from a landing on its own pier.
func _bridge_foot() -> void:
	var span := 30.0
	var w := 3.0
	var h := 3.5
	var steel := {"top": GRATING, "side": BLUE, "bottom": METAL}
	box(Vector3(-span * 0.5, -w * 0.5, h - 0.25), Vector3(span * 0.5, w * 0.5, h), steel)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-span * 0.5, minf(s * 1.0, s * 1.5), h - 1.25), Vector3(span * 0.5, maxf(s * 1.0, s * 1.5), h - 0.25), BLUE)
		rail("y", s * 1.375, -span * 0.5, span * 0.5, h, h)
	cylinder(Vector3(0.0, 0.0, -6.0), 0.375, h - 1.75 + 6.0, 10, BLUE)
	box(Vector3(-0.375, -1.75, h - 1.75), Vector3(0.375, 1.75, h - 1.25), BLUE)
	for dir: float in [-1.0, 1.0]:
		var x0 := span * 0.5
		var land := x0 + 1.0
		var foot := land + (h + TOE) * RAMP_RUN
		# Railings stop where the ramp is down to 0.25 m off the ground.
		var rail_end := land + (h - 0.25) * RAMP_RUN
		box(Vector3(minf(dir * x0, dir * land), -w * 0.5, EARTH_BASE - 1.0), Vector3(maxf(dir * x0, dir * land), w * 0.5, h), {"top": DECK, "side": CONCRETE, "bottom": CONCRETE})
		ramp(minf(dir * land, dir * foot), -w * 0.5, maxf(dir * land, dir * foot), w * 0.5, EARTH_BASE, -TOE, h, "-x" if dir > 0.0 else "+x", {"top": DECK, "side": CONCRETE, "bottom": CONCRETE})
		for s: float in [-1.0, 1.0]:
			rail("y", s * 1.375, minf(dir * x0, dir * land), maxf(dir * x0, dir * land), h, h)
			rail("y", s * 1.375, minf(dir * land, dir * rail_end), maxf(dir * land, dir * rail_end), 0.25, h, dir < 0.0)


## A steel through-truss, 48 m in one span: two Pratt trusses 7 m tall in
## eight panels, braced overhead well above the squad's heads, with a
## concrete deck 8 m wide hung between their bottom chords.
func _bridge_truss() -> void:
	_truss(48.0, 8.0, 3.0, 7.0, 6.0)


## The same truss over 72 m in twelve panels, 9 m wide and a metre deeper in
## the chord, for a river the 48 m one cannot reach across.
func _bridge_truss_long() -> void:
	_truss(72.0, 9.0, 3.0, 8.0, 6.0)


## A steel through-truss `span` long in bays of `bay`, its trusses `tall`
## above a deck `w` wide whose top is `h` up, on an abutment and an
## embankment at each end.
func _truss(span: float, w: float, h: float, tall: float, bay: float) -> void:
	var bays := int(roundf(span / bay))
	var zt := h + tall
	box(Vector3(-span * 0.5, -w * 0.5, h - 1.0), Vector3(span * 0.5, w * 0.5, h), ROAD)
	for s: float in [-1.0, 1.0]:
		var y := s * (w * 0.5 + 0.5)
		# The bottom chord stands 0.5 m proud of the deck as a kerb.
		box(Vector3(-span * 0.5, minf(s * w * 0.5, s * (w * 0.5 + 1.0)), h - 1.5), Vector3(span * 0.5, maxf(s * w * 0.5, s * (w * 0.5 + 1.0)), h + 0.5), RUST)
		box(Vector3(-span * 0.5 + bay, y - 0.375, zt - 0.375), Vector3(span * 0.5 - bay, y + 0.375, zt + 0.375), RUST)
		for e: float in [-1.0, 1.0]:
			beam(Vector3(e * span * 0.5, y, h + 0.5), Vector3(e * (span * 0.5 - bay), y, zt), 0.75, RUST)
		for i in range(1, bays):
			var x := -span * 0.5 + bay * i
			box(Vector3(x - 0.1875, y - 0.1875, h + 0.5), Vector3(x + 0.1875, y + 0.1875, zt - 0.375), RUST)
		# Pratt diagonals, each sloping down toward the middle of the span.
		for i in range(1, bays - 1):
			var xa := -span * 0.5 + bay * i
			var xb := xa + bay
			if xb <= 0.0:
				beam(Vector3(xa, y, zt - 0.375), Vector3(xb, y, h + 0.5), 0.375, RUST)
			else:
				beam(Vector3(xb, y, zt - 0.375), Vector3(xa, y, h + 0.5), 0.375, RUST)
	for i in range(1, bays):
		var x := -span * 0.5 + bay * i
		box(Vector3(x - 0.1875, -(w * 0.5 + 0.5), zt - 0.25), Vector3(x + 0.1875, w * 0.5 + 0.5, zt + 0.125), RUST)
	for dir: float in [-1.0, 1.0]:
		_abutment(span * 0.5, dir, w, h)
		_embankment(span * 0.5, dir, w, h)


# ── Stone ────────────────────────────────────────────────────────────────────

## An old stone humpback bridge, 30 m end to end: one segmental arch 12 m
## across, the road climbing 1 in 4 to a crown 3.25 m up between brick
## parapets, and the arch ring picked out in stone on both faces. The road
## runs on to TOE below the origin at each end, like the ramps of the others.
func _bridge_arch() -> void:
	var w := 6.0
	var hw := w * 0.5 + 0.375
	var crown := 3.25
	var rise := 2.25
	var r := (36.0 + rise * rise) / (2.0 * rise)
	var cz := rise - r
	var body := {"top": SETTS, "side": BRICK, "bottom": ARCH_STONE}
	# Six courses across the arch, each from the soffit up to the road.
	for i in 6:
		var xa := -6.0 + 2.0 * i
		var xb := xa + 2.0
		var pts: Array = []
		for x: float in [xa, xb]:
			for s: float in [-1.0, 1.0]:
				pts.append(Vector3(x, s * hw, cz + sqrt(r * r - x * x)))
				pts.append(Vector3(x, s * hw, crown - absf(x) / 4.0))
		solid(pts, body)
		# The arch ring, 0.625 m deep and proud of each face.
		for s: float in [-1.0, 1.0]:
			var ring: Array = []
			for x: float in [xa, xb]:
				var z := cz + sqrt(r * r - x * x)
				for y: float in [s * (hw - 0.125), s * (hw + 0.125)]:
					ring.append(Vector3(x, y, z))
					ring.append(Vector3(x, y, z + 0.625))
			solid(ring, ARCH_STONE)
	# The approaches, from the springing out past where the road meets the
	# ground.
	var end := (crown + TOE) * 4.0
	for dir: float in [-1.0, 1.0]:
		var pts: Array = []
		for s: float in [-1.0, 1.0]:
			pts.append_array([Vector3(dir * 6.0, s * hw, crown - 1.5), Vector3(dir * 6.0, s * hw, -3.0),
					Vector3(dir * end, s * hw, -TOE), Vector3(dir * end, s * hw, -3.0)])
		solid(pts, body)
		# A parapet each side from the crown down to the ground, 0.875 m high,
		# ending on a pillar.
		for s: float in [-1.0, 1.0]:
			var par: Array = []
			for x: float in [0.0, dir * crown * 4.0]:
				for y: float in [s * w * 0.5, s * hw]:
					par.append(Vector3(x, y, crown - absf(x) / 4.0))
					par.append(Vector3(x, y, crown - absf(x) / 4.0 + 0.875))
			solid(par, BRICK)
			var px := dir * crown * 4.0
			box(Vector3(px - 0.375, minf(s * (w * 0.5 - 0.125), s * (hw + 0.125)), -0.5), Vector3(px + 0.375, maxf(s * (w * 0.5 - 0.125), s * (hw + 0.125)), 1.25), ARCH_STONE)
