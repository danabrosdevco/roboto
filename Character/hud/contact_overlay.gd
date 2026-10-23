extends Control
class_name ContactOverlay

# ─────────────────────────────────────────────
# VIEW CONTACT / TARGETING
#
# What each side knows, drawn on screen: every live contact, how many robots are
# shooting it, the damage per second already committed against it, and how long
# since anyone last saw it.
#
# WHY IT IS NOT OPTIONAL GARNISH. The contact system landed in one pass rather
# than in phases, which means several behaviours changed at once — distribution,
# freshness, the mortar's dependency, the aim bonus. When a firefight looks
# wrong, this is the only thing that can say WHICH of them did it. Without it
# the switches on the DEBUG tab are guesses.
#
# IT BUILDS ITSELF. AIManager creates it when debug.contact_overlay goes on and
# frees it when that goes off, so nothing has to be wired into hud.tscn — which
# matters because three lanes share this checkout and that scene is busy. The
# layering is a little upside down (a manager making UI), and it is deliberate:
# a debug readout that needs a scene edit to exist is a debug readout nobody
# turns on.
# ─────────────────────────────────────────────

const ROW_H := 15.0
const PAD := 8.0
const WIDTH := 430.0

var manager: AIManager

var _font: Font
var _rows: Array = []
var _timer: float = 0.0
const REFRESH := 0.2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(-WIDTH - 12.0, 64.0)
	custom_minimum_size = Vector2(WIDTH, 0)
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	# A FIFTH OF A SECOND, not every frame. This reads a dictionary and formats
	# strings; doing that at 60 Hz to watch numbers that change on a 0.4 s cache
	# would be the overlay costing more than the system it is measuring.
	_timer = REFRESH
	_gather()
	queue_redraw()


func _gather() -> void:
	_rows.clear()
	if manager == null or not is_instance_valid(manager):
		return
	# Both sides, because the interesting question is usually whether THEY are
	# spreading fire, not whether you are.
	# All four hostile tables, not just ENEMY: SWARM/HOME/ARGUS were appended
	# 2026-10-10 and each keeps its own contact table (AIManager._contacts is
	# keyed by faction), so a missing row here is a frame whose sensor work is
	# invisible to the only panel that reads it.
	for faction in [Enums.Factions.ALLIED, Enums.Factions.ENEMY,
			Enums.Factions.SWARM, Enums.Factions.HOME, Enums.Factions.ARGUS]:
		var snapshot: Array = manager.contacts_snapshot(faction)
		if snapshot.is_empty():
			continue
		_rows.append({"head": "%s KNOWS OF %d" % [
				Enums.Factions.keys()[faction], snapshot.size()]})
		snapshot.sort_custom(func(a, b): return float(a["incoming"]) > float(b["incoming"]))
		for row in snapshot:
			var body = row["body"]
			var age: float = manager._now() - float(row["seen_at"])
			_rows.append({
				"name": str(body.soldier_name) if "soldier_name" in body else str(body.name),
				"by": int(row["by"]),
				"incoming": float(row["incoming"]),
				"age": age,
				"fresh": age <= manager.contact_fresh_seconds,
				"designated": manager._now() < float(row["designated_to"]),
				"hp": int(body.health) if "health" in body else 0,
			})


func _draw() -> void:
	if _rows.is_empty():
		return
	var h: float = PAD * 2.0 + ROW_H * float(_rows.size())
	draw_rect(Rect2(Vector2.ZERO, Vector2(WIDTH, h)), Color(0.02, 0.04, 0.04, 0.82))
	draw_rect(Rect2(Vector2.ZERO, Vector2(WIDTH, h)), Color(0.35, 0.95, 0.70, 0.35), false, 1.0)

	var y: float = PAD + ROW_H - 3.0
	for row in _rows:
		if row.has("head"):
			draw_string(_font, Vector2(PAD, y), str(row["head"]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.78, 0.64, 0.29))
			y += ROW_H
			continue
		# STALE IS THE INTERESTING STATE, so it is the one that is coloured.
		# A fresh contact is the normal case and should not shout.
		var tint: Color = Color(0.62, 0.95, 0.66) if row["fresh"] else Color(0.55, 0.58, 0.60)
		if row["designated"]:
			tint = Color(0.55, 0.90, 0.95)
		var line := "%-14s %3d hp   by %d   %6.1f dps   %4.1fs%s" % [
				str(row["name"]).left(14), row["hp"], row["by"],
				row["incoming"], row["age"],
				"  DESIG" if row["designated"] else ("" if row["fresh"] else "  STALE")]
		draw_string(_font, Vector2(PAD, y), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)
		y += ROW_H
