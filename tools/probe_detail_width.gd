extends SceneTree

# ─────────────────────────────────────────────
# WHAT IS MAKING THE SQUAD DETAIL PANEL TOO WIDE.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_detail_width.gd
#
# Reported from play: selecting a DESTROYED robot pushes the detail column off
# the right of the screen — the SCRAP button, the last module tile and the
# stores list all run past the edge.
#
# squad_page sets `side.custom_minimum_size.x = DETAIL_WIDTH` (400), which is a
# MINIMUM. Any single child wider than that drags the whole column out with it,
# and every other child then stretches to match, so the thing that looks broken
# is rarely the thing that is too wide. This prints every child's combined
# minimum width for a destroyed robot and for a healthy one, so the culprit
# names itself instead of being guessed at.
# ─────────────────────────────────────────────

const CAT := "res://Campaign/items & catalogue/test_item_catalogue.tres"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cat: ItemCatalogue = load(CAT)
	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = cat
	state.award(5000)
	state.award_compute(10)
	state.supply_cap = 8
	var p := state.player_record
	p.display_name = "PLAYER"
	p.set_chassis(cat.chassis_def(&"soldier"), cat)
	p.weapon_ids[0] = &"m4"

	# The robot from the report: a captain with a full kit AND destroyed.
	var wreck := _robot(cat, state, &"soldier", "Bravo-4", &"bolt")
	wreck.status = SoldierRecord.Status.DESTROYED
	wreck.damage = wreck.max_health
	wreck.rank = 3
	_fit(wreck, cat, [&"cluster_launcher"], [&"smoke"], [&"optics", &"armor_plating"])

	# ...and the same robot alive, as the control.
	var alive := _robot(cat, state, &"soldier", "Bravo-5", &"bolt")
	alive.rank = 3
	_fit(alive, cat, [&"cluster_launcher"], [&"smoke"], [&"optics", &"armor_plating"])

	var s := GDScript.new()
	s.source_code = "extends Node\nvar state\nvar catalogue\nvar in_mission = false\nfunc selected_mission():\n\treturn null\n"
	s.reload()
	var campaign := Node.new()
	campaign.set_script(s)
	campaign.set("state", state)
	campaign.set("catalogue", cat)
	campaign.add_to_group("campaign")
	root.add_child(campaign)

	var ui := SquadManagerUI.new()
	root.add_child(ui)
	await process_frame
	ui.open()
	await process_frame
	var page: Control = ui._pages[&"squad"]

	for who in [wreck, alive]:
		# Set it directly as well as calling _select: _select refuses records it
		# does not consider listed, and a silent refusal would have both dumps
		# showing the player's panel — which is exactly what the first run did.
		page._select(who, false)
		page.selected = who
		page._rebuild_detail()
		await process_frame
		await process_frame
		_report(page, who)
		await _shoot(who.display_name)
	quit(0)


## A picture as well as a number: a panel can measure right and still read
## wrong, which is the whole reason this started as a screenshot.
func _shoot(name_text: String) -> void:
	var out := OS.get_environment("SHOT_DIR")
	if out == "":
		return
	DirAccess.make_dir_recursive_absolute(out)
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("%s/squad_%s.png" % [out, name_text.to_lower()])
	print("   shot: squad_%s.png" % name_text.to_lower())


func _report(page: Control, who: SoldierRecord) -> void:
	var detail: Control = page._detail
	var label := "DESTROYED" if who.status == SoldierRecord.Status.DESTROYED else "alive"
	print("")
	print("   selected is actually: %s" % [page.selected.display_name if page.selected != null else "<null>"])
	print("── %s (%s) ── detail min width %.0f, panel min %.0f, DETAIL_WIDTH %.0f" % [
		who.display_name, label,
		detail.get_combined_minimum_size().x,
		(detail.get_parent() as Control).get_combined_minimum_size().x,
		page.DETAIL_WIDTH])
	var i := 0
	for c in detail.get_children():
		var w: float = (c as Control).get_combined_minimum_size().x if c is Control else 0.0
		var over := "   <-- OVER" if w > page.DETAIL_WIDTH else ""
		print("   %2d  %-24s %6.0f%s" % [i, c.get_class(), w, over])
		# One level down, so an over-wide row names the child inside it.
		if w > page.DETAIL_WIDTH and c is Control:
			for g in (c as Control).get_children():
				if g is Control:
					print("        %-22s %6.0f  %s" % [
						g.get_class(), (g as Control).get_combined_minimum_size().x,
						_text_of(g)])
		i += 1


func _text_of(n: Node) -> String:
	if n is Label:
		return "\"%s\"" % (n as Label).text
	if n is Button:
		return "[%s]" % (n as Button).text
	return ""


func _robot(cat: ItemCatalogue, state: CampaignState, frame: StringName,
		name_text: String, weapon: StringName) -> SoldierRecord:
	var r := SoldierRecord.new()
	r.display_name = name_text
	r.set_chassis(cat.chassis_def(frame), cat)
	if weapon != &"" and not r.weapon_ids.is_empty():
		r.weapon_ids[0] = weapon
	state.roster.append(r)
	return r


func _fit(r: SoldierRecord, cat: ItemCatalogue, weapons: Array,
		equipment: Array, modules: Array) -> void:
	for i in weapons.size():
		if i < r.weapon_ids.size():
			r.weapon_ids[i] = weapons[i]
	for i in equipment.size():
		if i < r.equipment_ids.size():
			r.equipment_ids[i] = equipment[i]
	for i in modules.size():
		if i < r.module_ids.size():
			r.module_ids[i] = modules[i]
	r.recompute_stats(cat)
