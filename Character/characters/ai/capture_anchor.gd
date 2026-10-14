extends "res://Character/characters/ai/enemy_nest.gd"

# ─────────────────────────────────────────────
# CAPTURE ANCHOR — the thing a tap becomes when it lands.
#
# You hack a compute core and a drone comes and docks on it. THIS is what docks:
# a structure with health that sits there holding the core open, and the enemy
# takes the core back by destroying it.
#
# WHY IT IS A NEST. The first version was a StaticBody3D with apply_damage, and
# no AI would ever shoot it: AIManager.hostiles_for() only scans `all_ai`, and
# register_enemy() is typed `AI`. A thing has to BE one to be targeted.
#
# The Nest is already exactly this shape, and says so in its own header — "an
# enemy building that makes more enemies… it simply never moves and never
# shoots", and with no hatchlings listed it is, in its own words, "an ordinary
# building with health". So this extends it, drops the hatching, and flips the
# faction. Every road a hostile travels — spawned, counted, shot, downed,
# ground up by a Reclaimer — this travels too, for free.
#
# NOT A SOLDIER SUBCLASS DIRECTLY, because capture_anchor.tscn is a copy of
# enemy_nest.tscn and its node_paths name the nest's own exports (dish, flames,
# hatch_light, hatch_sound). Inheriting keeps those resolvable.
# ─────────────────────────────────────────────

signal anchor_lost(anchor)


func _ready() -> void:
	# ONE NULL ENTRY, not an empty list. The nest warns when hatchlings is empty
	# — correctly, for a nest — and an anchor would trip it on every capture.
	# Nothing ever reads this: _next_hatch is pushed out of reach below and
	# _hatch() is overridden to do nothing.
	hatchlings = [null]
	super()
	# Far out of reach rather than zero: the nest schedules its next hatch off
	# this and a zero would have it trying every frame.
	_next_hatch = 1.0e12


## Nothing comes out of an anchor. Belt and braces over the timer above.
func _hatch() -> void:
	pass


func die() -> void:
	anchor_lost.emit(self)
	super()
