extends RefCounted
class_name EnemyLoadouts

# ─────────────────────────────────────────────
# WHAT A HOSTILE IS CARRYING, ROLLED PER BODY.
#
# Until this existed, every enemy of a given frame was identical: the spawner
# applied the chassis' `starting_weapon_id` and nothing else, so a rifleman was
# a rifleman was a rifleman and there was never a reason to look at one before
# shooting it. Composition per mission was the whole difficulty curve, and it
# was authored by hand one body at a time.
#
# Now each body draws from a pool for its frame. A rover might be carrying the
# Ancient MG it comes with, or a Heavy MG, or a grenade launcher; a rifleman
# might be plated twice over, or carrying frags, or neither.
#
# ── THREE RULES THESE TABLES OBEY ────────────
#
# 1. LEGAL BY THE CATALOGUE, NOT BY THIS FILE. Every draw is checked against
#    the item's own `chassis_whitelist`, `fits_vehicles`, `one_per_robot` and
#    `usable_by_ai`, and against the frame's slot counts. A table entry that
#    the catalogue refuses is dropped and warned about rather than fitted —
#    this file can go stale, item_*.tres is the authority.
#
# 2. THE POOLS ARE NARROWER THAN THE LAW ALLOWS. Overclock Servos legally fit a
#    rover (fits_vehicles is true) and a rover will never roll them, because a
#    faster rover is a different vehicle rather than a variation on one. Legality
#    says what CAN go on; these tables say what the faction actually fields.
#
# 3. SEEDED, NOT RANDOM. See roll_for(). A mission has to play the same way
#    twice or neither the player retrying it nor the Laboratory measuring it is
#    looking at the same fight.
# ─────────────────────────────────────────────

## Per chassis id. Every key is optional; a frame with no table keeps exactly
## what it is issued today, which is how every frame not listed here behaves.
##
##   weapons      main mount. Weighted; "" means "keep the frame's issued gun".
##   coax         second mount, for frames with weapon_slots >= 2. "" means none.
##   modules      weighted pool, drawn `module_draws` times
##   module_draws [min, max] draws, inclusive
##   caps         per-item ceiling beyond what one_per_robot already enforces
##   equipment    weighted pool, drawn `equipment_draws` times
##
## Weights are relative within their own pool and need not sum to anything.
const TABLES := {
	# ── INFANTRY ──────────────────────────────
	# 2 module slots, 2 equipment slots. The common body, so the pool is wide
	# and the common result is "nothing special" — a plated rifleman should be
	# a thing you notice, which it cannot be if every rifleman is plated.
	&"rifleman": {
		"modules": {&"armor_plating": 5, &"overclock_servos": 2},
		"module_draws": [0, 2],
		"caps": {&"overclock_servos": 1},
		"equipment": {&"frag": 5, &"smoke": 2, &"repair_kit": 2, &"drone_pack": 1},
		"equipment_draws": [0, 2],
	},
	&"soldier": {
		"modules": {&"armor_plating": 5, &"overclock_servos": 2},
		"module_draws": [0, 2],
		"caps": {&"overclock_servos": 1},
		"equipment": {&"frag": 5, &"smoke": 2, &"repair_kit": 2, &"drone_pack": 1},
		"equipment_draws": [0, 2],
	},
	# Already the armoured variant of a rifleman, so it does not also roll
	# plating — that is the frame's whole identity and doubling it makes a
	# body the player cannot read.
	&"rifleman_armoured": {
		"modules": {&"overclock_servos": 2, &"hardened_uplink": 2},
		"module_draws": [0, 1],
		"equipment": {&"frag": 4, &"smoke": 2},
		"equipment_draws": [0, 2],
	},
	&"shotgunner": {
		# Closes distance, so servos read on it more than on a rifleman.
		"modules": {&"armor_plating": 4, &"overclock_servos": 4},
		"module_draws": [0, 2],
		"caps": {&"overclock_servos": 1},
		"equipment": {&"frag": 4, &"smoke": 3},
		"equipment_draws": [0, 2],
	},
	&"marksman": {
		"modules": {&"optics": 5, &"armor_plating": 2},
		"module_draws": [0, 2],
		"equipment": {&"smoke": 3, &"frag": 1},
		"equipment_draws": [0, 1],
	},
	# No weapon slot, 1 equipment, 2 modules. A plated mechanic is the reason a
	# garrison stops dying on schedule, so it is worth rolling for.
	&"mechanic": {
		"modules": {&"armor_plating": 5, &"overclock_servos": 2},
		"module_draws": [0, 2],
		"caps": {&"overclock_servos": 1},
		"equipment": {&"repair_kit": 4, &"smoke": 2},
		"equipment_draws": [0, 1],
	},
	# One module slot and no equipment. Either it is faster or it is tougher.
	&"chaser": {
		"modules": {&"overclock_servos": 3, &"armor_plating": 3},
		"module_draws": [0, 1],
	},

	# ── EYES ──────────────────────────────────
	# A spotter is worth a seat because of what the contact system does with
	# what it sees: Enemy.note_seen writes into ITS OWN faction's table, and
	# _contact_assisted tightens the aim of everything shooting at a contact
	# somebody currently has eyes on. That machinery has always been
	# faction-generic; the enemy simply never fielded anything to use it.
	#
	# The counterplay to a spotter is to kill it or to e-kill it, so a Hardened
	# Uplink is the variation that matters most — a spotter that shrugs off the
	# EMP you threw at it is a different problem from one that does not.
	&"spotter": {
		"modules": {&"optics": 4, &"hardened_uplink": 4, &"armor_plating": 2},
		"module_draws": [0, 2],
		"equipment": {&"smoke": 3},
		"equipment_draws": [0, 1],
	},
	# Fixed mast, 350 hp, 170 m. It cannot run and it cannot shoot, so armour
	# and signal resistance are the only things that change how it dies.
	&"watcher": {
		"modules": {&"hardened_uplink": 5, &"armor_plating": 3, &"optics": 2},
		"module_draws": [0, 2],
	},

	# ── VEHICLES ──────────────────────────────
	# PLATING AND RELAY ONLY. Servos fit a rover by the catalogue's rules and
	# are deliberately not in this pool: see rule 2 at the top.
	#
	# The gun is the real variation. A rover is issued the Ancient MG, and the
	# table keeps that the common case so the uncommon ones mean something.
	&"rover": {
		"weapons": {&"": 5, &"heavy_mg": 3, &"grenade_launcher": 2, &"autocannon": 1},
		"modules": {&"armor_plating": 5, &"optics": 3},
		"module_draws": [0, 2],
		"caps": {&"armor_plating": 2},
	},
	# The GL variant is already defined by its gun, so it only rolls armour.
	&"rover_gl": {
		"modules": {&"armor_plating": 5, &"optics": 3},
		"module_draws": [0, 2],
		"caps": {&"armor_plating": 2},
	},
	# TWO MOUNTS. weapon_slots = 2, so a walker can come with a second gun on
	# the coax — including a second Heavy MG, which is the nastiest thing in
	# this file and should stay rare.
	&"walker": {
		"weapons": {&"": 4, &"heavy_mg": 3},
		"coax": {&"machine_gun": 4, &"": 3, &"heavy_mg": 2},
		"modules": {&"armor_plating": 4, &"optics": 3},
		"module_draws": [0, 2],
		"caps": {&"armor_plating": 2},
	},
	&"reclaimer": {
		"modules": {&"armor_plating": 4, &"optics": 2},
		"module_draws": [0, 2],
		"caps": {&"armor_plating": 2},
	},
	&"mortar_track": {
		# A mortar that can see for itself is worth more than a tougher one.
		"modules": {&"optics": 4, &"armor_plating": 3},
		"module_draws": [0, 2],
		"caps": {&"armor_plating": 2},
	},
}


## What one body is carrying. Pure data — no nodes, no catalogue lookups beyond
## legality — so the whole table is testable headless.
##
## SEEDED FROM THE BODY'S IDENTITY, not from the global RNG. A mission that
## rolls fresh kit every load cannot be retried, cannot be learned, and cannot
## be measured by the Laboratory — three runs of the same matchup would differ
## for a reason the report could not see. Same mission, same squad, same slot
## gives the same robot every time; change any of the three and it is a
## different robot.
static func roll_for(frame: ChassisDefinition, catalogue: ItemCatalogue,
		seed_text: String) -> Dictionary:
	var out := {"weapons": [], "equipment": [], "modules": []}
	if frame == null or catalogue == null:
		return out
	var table: Dictionary = TABLES.get(frame.id, {})
	if table.is_empty():
		return out

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)

	# ── main mount ────────────────────────────
	if table.has("weapons") and frame.weapon_slots >= 1:
		var pick: StringName = _draw(rng, table["weapons"])
		if pick != &"" and _legal(catalogue, pick, frame, ItemDefinition.Kind.WEAPON):
			out["weapons"].append(pick)

	# ── coax ──────────────────────────────────
	# Only for a frame that actually has a second mount. Fitting one to a
	# single-mount frame half-works: Enemy.equip_coax_scene drops it and warns,
	# which is a warning per body per mission for a thing this file could have
	# simply not asked for.
	if table.has("coax") and frame.weapon_slots >= 2:
		var coax: StringName = _draw(rng, table["coax"])
		if coax != &"" and _legal(catalogue, coax, frame, ItemDefinition.Kind.WEAPON):
			# Slot 0 must be filled for slot 1 to mean anything, so an empty
			# main mount is backfilled with what the frame is issued.
			if out["weapons"].is_empty():
				out["weapons"].append(frame.starting_weapon_id)
			out["weapons"].append(coax)

	out["modules"] = _draw_many(rng, table, "modules", "module_draws",
			frame.module_slots, catalogue, frame, ItemDefinition.Kind.MODULE)
	out["equipment"] = _draw_many(rng, table, "equipment", "equipment_draws",
			frame.equipment_slots, catalogue, frame, ItemDefinition.Kind.EQUIPMENT)
	return out


## Draws for one pool, respecting the frame's slot count, the table's caps and
## the item's own one_per_robot.
static func _draw_many(rng: RandomNumberGenerator, table: Dictionary,
		pool_key: String, draws_key: String, slots: int,
		catalogue: ItemCatalogue, frame: ChassisDefinition, kind: int) -> Array:
	var out: Array[StringName] = []
	if not table.has(pool_key) or slots <= 0:
		return out
	var range_spec: Array = table.get(draws_key, [0, slots])
	var lo: int = int(range_spec[0])
	var hi: int = mini(int(range_spec[1]), slots)
	if hi <= 0:
		return out
	var caps: Dictionary = table.get("caps", {})
	var taken: Dictionary = {}
	for _i in rng.randi_range(lo, hi):
		var pick: StringName = _draw(rng, table[pool_key])
		if pick == &"":
			continue
		var item := catalogue.item(pick)
		if item == null or not _legal(catalogue, pick, frame, kind):
			continue
		var have: int = int(taken.get(pick, 0))
		var ceiling: int = int(caps.get(pick, slots))
		if item.one_per_robot:
			ceiling = 1
		if have >= ceiling:
			continue   # rolled something it is already carrying its fill of
		taken[pick] = have + 1
		out.append(pick)
	return out


## One weighted pick. `{id: weight}`; a zero or negative weight never comes up.
static func _draw(rng: RandomNumberGenerator, pool: Dictionary) -> StringName:
	var total: float = 0.0
	for id_value in pool:
		total += maxf(float(pool[id_value]), 0.0)
	if total <= 0.0:
		return &""
	var roll: float = rng.randf() * total
	for id_value in pool:
		roll -= maxf(float(pool[id_value]), 0.0)
		if roll <= 0.0:
			return id_value
	return &""


## The catalogue has the final say, not this file. Warns rather than silently
## dropping, because a table entry that has gone stale is a content bug and the
## symptom — an enemy that is quietly plainer than intended — is invisible.
static func _legal(catalogue: ItemCatalogue, id_value: StringName,
		frame: ChassisDefinition, kind: int) -> bool:
	var item := catalogue.item(id_value)
	if item == null:
		push_warning("EnemyLoadouts: '%s' is in the table for '%s' and not in the catalogue." % [id_value, frame.id])
		return false
	if item.kind != kind:
		push_warning("EnemyLoadouts: '%s' is in the wrong pool for '%s' — it is a %s." % [id_value, frame.id, item.kind])
		return false
	if not item.fits_ai():
		push_warning("EnemyLoadouts: '%s' is in the table for '%s' and is not usable_by_ai." % [id_value, frame.id])
		return false
	if not item.fits_chassis(frame.id):
		push_warning("EnemyLoadouts: '%s' is in the table for '%s' and its whitelist refuses that frame." % [id_value, frame.id])
		return false
	if frame.drives and not item.fits_vehicles:
		push_warning("EnemyLoadouts: '%s' is in the table for '%s', which drives, and it does not fit vehicles." % [id_value, frame.id])
		return false
	return true


# ─────────────────────────────────────────────
# ROLLED KIT, APPLIED TO A LIVE BODY.
#
# Static and taking the catalogue as an argument, because there are two places
# that build a hostile and they share no base class: EnemyForceSpawner, which
# deploys a mission's force, and EnemyNest, which hatches bodies of its own on
# a timer. Every enemy in the game comes out of one of those two.
#
# NOT THROUGH SoldierRecord.recompute_stats(), which is how the player's squad
# does it, and the difference matters. recompute_stats starts from the
# ChassisDefinition's base_health / base_accuracy / base_sensor_range and
# returns an ABSOLUTE figure. Enemy frames routinely leave those at 0 so the
# scene's own authored values stand — see EnemyForceSpawner._apply_frame, which
# only assigns when the frame specifies something, and the legacy wrapper in
# _bodies_of, which sets all three to 0 on purpose. Running an absolute
# recompute over that would hand a 320 hp Walker whatever SoldierRecord's class
# default happens to be.
#
# So modules are applied here as DELTAS on top of whatever the scene and the
# frame already set, using the same per-module arithmetic recompute_stats uses,
# field for field.
# ─────────────────────────────────────────────
static func apply(soldier: Node, frame: ChassisDefinition,
		catalogue: ItemCatalogue, seed_text: String) -> Dictionary:
	var kit: Dictionary = {}
	if soldier == null or frame == null or catalogue == null:
		return kit
	kit = roll_for(frame, catalogue, seed_text)

	# ── guns ──────────────────────────────────
	# Slot 0 replaces whatever the frame was issued; slot 1 is the coax.
	var weapons: Array = kit.get("weapons", [])
	for i in weapons.size():
		var item := catalogue.item(weapons[i])
		if item == null or item.ai_scene == null:
			continue
		if i == 0:
			soldier.equip_weapon_scene(item.ai_scene)
		elif soldier.has_method("equip_coax_scene"):
			soldier.equip_coax_scene(item.ai_scene)

	# ── equipment ─────────────────────────────
	# Built fresh per body so two hostiles carrying frags do not share a count.
	var slots: Array[AIEquipmentSlot] = []
	for id_value in kit.get("equipment", []):
		var gear := catalogue.item(id_value)
		if gear == null or gear.ai_scene == null:
			continue
		var slot := AIEquipmentSlot.new()
		slot.equipment_scene = gear.ai_scene
		slot.quantity = gear.quantity
		slot.label = gear.short_label()
		slot.item_id = gear.id
		slots.append(slot)
	if not slots.is_empty():
		soldier.equipment_slots = slots

	# ── modules ───────────────────────────────
	var fitted: Array[StringName] = []
	for id_value in kit.get("modules", []):
		var module := catalogue.item(id_value)
		if module == null:
			continue
		soldier.max_health += module.health_bonus
		soldier.accuracy_skill += module.accuracy_bonus
		soldier.move_speed *= module.speed_multiplier
		soldier.sensor_range += module.sensor_bonus
		soldier.signal_resistance += module.signal_resistance_bonus
		soldier.self_revive_seconds = maxf(soldier.self_revive_seconds, module.self_revive_seconds)
		soldier.suppressive_fire = soldier.suppressive_fire or module.suppressive_fire
		if module.signal_bonus != 0.0:
			soldier.signal_integrity = clampf(
				soldier.signal_integrity + module.signal_bonus, 0.0, 1.0)
		fitted.append(module.id)
	# Health last: the bonuses above moved the ceiling, and a body that spawned
	# at its old maximum would otherwise start the mission already damaged.
	soldier.max_health = maxi(1, soldier.max_health)
	soldier.health = soldier.max_health

	# What it ended up with, for the debrief and for anything that wants to
	# explain why that rifleman took three magazines.
	if not fitted.is_empty():
		soldier.set_meta(&"fitted_modules", fitted)
	return kit
