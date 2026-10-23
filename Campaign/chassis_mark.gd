class_name ChassisMark
extends Resource

# ─────────────────────────────────────────────
# ONE TIER OF A PRODUCTION LINE'S SPECIFICATION.
#
# A Mark is what the line BUILDS, not what one robot happens to be carrying.
# Adopting Mk 1 on the Rover line rewrites every Rover in service and every
# Rover built afterwards — see docs/briefs/archive/MARK_SYSTEM_SPEC.md §3.
#
# MK 0 IS NOT ONE OF THESE. Every ChassisDefinition already carries
# `starting_weapon_id` and `coax_weapon_id`, which already describe what the
# line builds today: the Walker is a 20 mm Autocannon with a coaxial Ancient
# MG and the Rover is an Ancient Machine Gun. Authoring Mk 0 here as well
# would be a second source of truth for the same fact, and the two will
# disagree inside a month. `ChassisDefinition.mark_spec(0)` synthesises it.
#
# MODULES ARE NOT HERE EITHER. A line adopts ONE module as a capstone, stored
# per line on CampaignState rather than per tier — the Marks are the ladder and
# the module is the single choice at the top of it.
# ─────────────────────────────────────────────

## What the line's robots carry, in mount order. The first entry is the main
## weapon and the second — on a frame with two mounts — is the coax.
##
## HONOURS THE FRAME'S OWN SLOT COUNT. A Mark listing two weapons on a
## one-mount chassis is an authoring error, not a second mount: `verify()`
## says so rather than letting the extra silently vanish at apply time.
@export var weapon_ids: Array[StringName] = []
## Equipment the line is built carrying. Refilled free between missions — this
## is part of what the frame IS, not something the player shops for.
@export var equipment_ids: Array[StringName] = []

# ── TUNING ────────────────────────────────────
# Applied ON TOP of the chassis base, the same way a module's bonuses are, so
# a Mark can advance a line that has nothing to upgrade but itself. Mechanic
# and Spotter have no weapon mount at all; without this their rails would be
# empty and those two lines could not progress.
#
# Every one of these shows on a bar in the Factory. That is a requirement
# rather than a nicety: a tier whose only effect is a sentence of prose is a
# tier the player cannot judge before paying for it.
@export var health_bonus: int = 0
@export var speed_multiplier: float = 1.0
@export var sensor_bonus: float = 0.0
@export var accuracy_bonus: float = 0.0

## Role tuning that is not one of the four above — repair rate, salvage rate,
## reload speed. Named rather than typed because what a frame has to tune
## depends on what the frame does, and a column per role on every Mark would
## be mostly zeroes.
##
## Keys are read by whatever owns that behaviour. An unknown key is ignored by
## everything, which is why `verify()` checks them against a known list: a
## typo here is silent and this is the only place it can be caught.
@export var tuning: Dictionary = {}

## Every `tuning` key anything actually reads. Add here and in the reader.
const TUNING_KEYS := [&"repair_rate", &"salvage_rate", &"reload_rate"]


## A one-line summary for the Factory rail and for the probes.
func summary() -> String:
	var parts: Array = []
	if not weapon_ids.is_empty():
		parts.append(", ".join(weapon_ids.map(func(v): return String(v))))
	if not equipment_ids.is_empty():
		parts.append("+ " + ", ".join(equipment_ids.map(func(v): return String(v))))
	if health_bonus != 0:
		parts.append("%+d hp" % health_bonus)
	if not is_equal_approx(speed_multiplier, 1.0):
		parts.append("x%.2f spd" % speed_multiplier)
	if not is_equal_approx(sensor_bonus, 0.0):
		parts.append("%+.0fm sensor" % sensor_bonus)
	if not is_equal_approx(accuracy_bonus, 0.0):
		parts.append("%+.2f acc" % accuracy_bonus)
	for k in tuning:
		parts.append("%s x%.2f" % [String(k), float(tuning[k])])
	return " · ".join(parts) if not parts.is_empty() else "(no change)"


## What is wrong with this Mark on `frame`, as readable lines. Empty is good.
##
## EXISTS BECAUSE EVERY FAULT HERE IS SILENT. An extra weapon on a one-mount
## frame is dropped, equipment on a frame with no equipment slots is dropped,
## and a mistyped tuning key is read by nobody — none of which errors, and all
## of which look like the Mark simply not being worth its price.
func verify(frame) -> Array[String]:
	var bad: Array[String] = []
	if frame == null:
		bad.append("no chassis to check against")
		return bad
	if weapon_ids.size() > frame.weapon_slots:
		bad.append("%d weapons on a frame with %d mount(s)"
			% [weapon_ids.size(), frame.weapon_slots])
	if equipment_ids.size() > frame.equipment_slots:
		bad.append("%d equipment on a frame with %d slot(s)"
			% [equipment_ids.size(), frame.equipment_slots])
	for k in tuning:
		if not TUNING_KEYS.has(StringName(k)):
			bad.append("'%s' is not a tuning key anything reads" % String(k))
	return bad
