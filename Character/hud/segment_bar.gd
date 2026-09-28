extends Control
class_name SegmentBar

# ─────────────────────────────────────────────
# SEGMENT BAR — health as blocks, one block per 20 HP, Far Cry style.
#
# WHY NOT A FRACTION. A bar that fills 0..1 says how much of its own health a
# robot has left and NOTHING about how much that is. A Rover carrying two
# armour plates has 330 HP and a Soldier has 60, and at full both drew one
# identical full bar — so the toughest machine in the squad and the flimsiest
# read the same on the roster, which is exactly backwards from what you need
# when you are deciding who to send through a door.
#
# So the block COUNT comes from max_health and the blocks are a fixed width:
# the Rover's bar is five times longer than the Soldier's because the Rover is
# five times tougher. Length is capacity, fill is what is left of it.
#
# One drawn Control rather than a row of ProgressBars — the roster redraws
# every member several times a second, and seventeen robots at up to sixteen
# blocks each is 270 nodes to keep in a tree for something that is a handful
# of rectangles.
#
# It matches the player's own strip (ui.gd, health_per_segment = 20) on
# purpose: the same 20 HP means the same block wherever you read it.
# ─────────────────────────────────────────────

## HP per block. The player's strip uses the same number; change both together.
const PER_SEGMENT := 20.0
const SEG_W := 5.0
const SEG_GAP := 1.0
## Past this the bar stops growing and the blocks get thinner instead, so one
## very heavy frame cannot push the roster off the side of the screen.
const MAX_SEGMENTS := 18

var health: float = 0.0
var max_health: float = 0.0
var full_color: Color = Color.WHITE
## Empty blocks are drawn faintly rather than left out: the gap between what a
## robot has and what it could have is the point.
var empty_alpha: float = 0.22
var bar_height: float = 11.0


func setup(hp: float, hp_max: float, col: Color) -> void:
	health = maxf(hp, 0.0)
	max_health = maxf(hp_max, 1.0)
	full_color = col
	var blocks := _blocks()
	custom_minimum_size = Vector2(blocks * SEG_W + maxf(0.0, blocks - 1.0) * SEG_GAP, bar_height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _blocks() -> float:
	return clampf(ceil(max_health / PER_SEGMENT), 1.0, float(MAX_SEGMENTS))


func _draw() -> void:
	var blocks := _blocks()
	# Over the cap the blocks share the width out instead of adding more.
	var per: float = max_health / blocks
	var w: float = SEG_W
	var faint := Color(full_color, empty_alpha)
	var left := health
	for i in int(blocks):
		var x: float = float(i) * (w + SEG_GAP)
		var box := Rect2(x, 0.0, w, bar_height)
		draw_rect(box, faint, true)
		if left <= 0.0:
			continue
		var fill: float = clampf(left / per, 0.0, 1.0)
		if fill > 0.0:
			draw_rect(Rect2(x, bar_height * (1.0 - fill), w, bar_height * fill), full_color, true)
		left -= per
