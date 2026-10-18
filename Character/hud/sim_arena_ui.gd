extends Control
class_name SimArenaUI

# ─────────────────────────────────────────────
# THE SIM ARENA — free actions, and the only place practising happens.
#
# docs/briefs/SIM_ARENA_MODE.md. Phase 6.4 made a `sim` mission cost nothing:
# no turn, no pay, no ground, no enemy move, repeatable. What it did not do was
# take the arenas OFF the operations table, where they were offered as the same
# kind of choice as a war — one that costs a turn and can lose you a site, and
# one that cannot, in the same place with the same furniture.
#
# A FREE ACTION MUST NOT LOOK LIKE A COSTLY ONE. That is the whole reason this
# is a screen rather than three more pins.
#
# TWO HALVES, BECAUSE THEY ARE TWO DIFFERENT THINGS:
#
#   TRAINING  the three authored arenas, in order. The campaign's on-ramp, and
#             what gates Hillfort — eight lessons in the depot, three here,
#             then the war.
#   THE LAB   pick two sides and run them at each other. WATCH it, or LEAD one.
#             Teaches nothing and is not meant to; it is a toy, and it is the
#             place you find out what a frame does before paying to open it.
#
# THE LAB IS NOT NEW. Managers/lab.gd already runs AI-vs-AI matchups, already
# knows how to seat two sides facing each other, and already has a spectator.
# This is a front end for it, not a second implementation — a LabMatchup is
# exactly "two rosters, two orders and a distance", which is exactly what the
# player is choosing here.
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const Icons := preload("res://Character/hud/icons/icons.gd")
const _Matchup := preload("res://Campaign/lab/lab_matchup.gd")
const _Plan := preload("res://Campaign/lab/lab_plan.gd")
## Both sides' rosters — the player catalogue has none of the Swarm's frames.
const _Gen := preload("res://Campaign/force_generator.gd")
const DETAIL_WIDTH := 420.0

signal closed
## The player chose a training run. The campaign deploys it like any mission —
## it is still a mission, it just costs nothing.
signal training_chosen(mission_id: StringName)
## The player built a fight. `lead` false watches it, true fights in it.
signal fight_requested(matchup: Resource, lead: bool)

var campaign: Node
var catalogue: ItemCatalogue

var _tab: StringName = &"training"
var _tab_buttons := {}
var _body: VBoxContainer
var _detail: VBoxContainer
## The right-hand column ITSELF, so it can be hidden. It carries a fixed
## minimum width, and TRAINING now puts nothing in it — left visible it is a
## 260px empty gutter taking that width off the exercise list for nothing.
var _detail_pane: ScrollContainer
## The two sides being built, as chassis ids. Ids rather than definitions so a
## rebuild does not hold references to resources the catalogue may re-index.
var _side_a: Array[StringName] = []
var _side_b: Array[StringName] = []
var _picking: StringName = &"a"


func _ready() -> void:
	# ANCHORS AND OFFSETS. set_anchors_preset alone leaves the offsets where
	# they were, so the panel kept its zero size and collapsed to its header —
	# the body drew nothing and the screen looked empty.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Kit.box(Kit.LINE, Kit.PANEL, 1, 16.0))
	add_child(panel)

	var column := Kit.vbox(10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(column)

	var head := Kit.hbox(14)
	head.add_child(Kit.label("SIM ARENA", Kit.BRIGHT, 28, true))
	head.add_child(Kit.fill())
	var shut := Kit.button("CLOSE", Kit.DIM, Kit.SMALL)
	shut.pressed.connect(func(): closed.emit())
	head.add_child(shut)
	column.add_child(head)

	# THE TRAINING TAB GOES AWAY ONCE TRAINING IS OVER.
	#
	# Both exercises completed means there is nothing on that tab you can press
	# — every row says COMPLETED and none of them has an ENTER. A tab that
	# cannot be acted on is a tab that teaches the player to ignore tabs, and
	# the arena's whole second life is free play. So the sim collapses to THE
	# LAB and stops asking which half you wanted.
	var tabs := Kit.hbox(6)
	var specs: Array = [[&"training", "TRAINING"], [&"lab", "THE LAB"]]
	if _training_over():
		specs = [[&"lab", "THE LAB"]]
		_tab = &"lab"
	for spec in specs:
		var id: StringName = spec[0]
		var b := Kit.button(String(spec[1]), Kit.DIM, Kit.BODY)
		b.pressed.connect(func(): _show(id))
		tabs.add_child(b)
		_tab_buttons[id] = b
	column.add_child(tabs)

	var row := Kit.hbox(14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	var left := ScrollContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(left)
	_body = Kit.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_body)
	_detail_pane = ScrollContainer.new()
	_detail_pane.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	_detail_pane.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(_detail_pane)
	_detail = Kit.vbox(6)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_pane.add_child(_detail)
	rebuild()


func _show(tab: StringName) -> void:
	_tab = tab
	rebuild()


# ── Drawing ──────────────────────────────────────────────────────────────────

func rebuild() -> void:
	if _body == null:
		push_warning("SimArenaUI: rebuild before _ready, so the arena draws nothing.")
		return
	Kit.clear(_body)
	Kit.clear(_detail)
	for id in _tab_buttons:
		_tab_buttons[id].add_theme_color_override("font_color",
			Kit.BRIGHT if id == _tab else Kit.DIM)
	if _tab == &"training":
		_draw_training()
	else:
		_draw_lab()
	# NOTHING ON THE RIGHT MEANS NO RIGHT. Only THE LAB fills the detail panel;
	# see _detail_pane.
	_detail_pane.visible = _detail.get_child_count() > 0


## ONE EXERCISE AT A TIME, which is what makes it read as a sequence.
##
## It used to list every arena at once, each a small heading over a clipped
## line of briefing. Two problems with that: a list invites you to pick, and
## there is nothing to pick — they are meant to be run in order — and the
## thing you actually need to read, the NAME, was the smallest part of the row.
##
## So: the next uncleared one, on its own, large. The ones behind you are gone
## rather than greyed, because a finished exercise is not a choice either. The
## step counter is what keeps it from looking like the only one there has ever
## been, and `_training_over()` drops the whole tab once both are done.
func _draw_training() -> void:
	var all := _sim_missions()
	var next = null
	var step := 0
	for i in all.size():
		if not _is_cleared(all[i]):
			next = all[i]
			step = i + 1
			break
	if next == null:
		# Every exercise cleared. _training_over() normally collapses the tab
		# before this can be seen, so reaching here means the tab was forced.
		_body.add_child(Kit.label("TRAINING COMPLETE", HUDPalette.HELD, Kit.BODY, true))
		return
	if all.is_empty():
		_body.add_child(Kit.label("NO TRAINING AVAILABLE", Kit.PROBLEM, Kit.BODY, true))
		return
	_body.add_child(_training_row(next, step, all.size()))


## One exercise, as a row.
##
## A CLEARED ONE SAYS COMPLETED AND CANNOT BE RE-ENTERED. It used to say
## "RUN x1" and keep its ENTER button, which made the training track read as a
## list of things you could grind rather than a sequence you finish. There is
## nothing to gain from a second run — an exercise pays nothing and costs no
## turn — so offering it is offering busywork.
## THE NAME IS THE BIGGEST THING ON IT.
##
## FIRST CONTACT and TAKE AND HOLD are the whole content of this screen, and
## they used to be set at BODY — the same size as everything else — with a
## clipped line of briefing under them taking up more room than they did. The
## briefing is gone: the exercise opens with it anyway, and a sentence cut off
## at 110 characters taught nobody anything.
func _training_row(m, step: int, of: int) -> Control:
	var card := Kit.card(Kit.LINE,
		func(): training_chosen.emit(m.id), func(): pass, 14.0)
	var col := Kit.vbox(6)
	card.add_child(col)
	# EXERCISE 1 OF 2 — small, above, so the big line underneath is the name
	# and nothing else. This is what says "sequence" now that only one shows.
	col.add_child(Kit.label("EXERCISE %d OF %d" % [step, of], Kit.DIM, Kit.SMALL, true))
	col.add_child(Kit.label(m.display_name.to_upper(), Kit.BRIGHT, TITLE, true))
	var row := Kit.hbox(10)
	col.add_child(row)
	var go := Kit.button("ENTER", Kit.BRIGHT, Kit.BODY)
	go.pressed.connect(func(): training_chosen.emit(m.id))
	row.add_child(go)
	return card


## Big enough that the exercise name is the first thing read, and the only
## thing at this size anywhere in the arena. Kit tops out at HEADING 16, which
## is a heading among body text rather than a title.
const TITLE := 30


## Has this exercise been run? One place, because _draw_training asks it per
## mission to find the next one and nothing else should re-derive it.
func _is_cleared(m) -> bool:
	var state = campaign.state if campaign != null and "state" in campaign else null
	if state == null or not state.has_method("clears_of"):
		return false
	return state.clears_of(m.id) > 0


## Two sides, built from the catalogue, and a choice about who holds the gun.
func _draw_lab() -> void:
	_body.add_child(Kit.text_block(
		"Put two forces on the proving ground and see what happens. Watch it, or"
		+ " fight in it. Nothing here is bought, spent or kept.", Kit.DIM, Kit.SMALL))

	var sides := Kit.hbox(10)
	sides.add_child(_side_box("a", "YOUR SIDE", _side_a))
	sides.add_child(_side_box("b", "THEIRS", _side_b))
	_body.add_child(sides)

	_body.add_child(Kit.spacer(0, 6))
	_body.add_child(Kit.label("ADD TO %s" % ("YOUR SIDE" if _picking == &"a" else "THEIRS"),
		Kit.DIM, Kit.SMALL, true))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	# EVERY FRAME, OPENED OR NOT. The sim is where you find out what a thing
	# does; the Tooling Fabricator is where you pay for having found out. A
	# practice track that only lets you practise with what you already bought
	# teaches you nothing about what to buy next.
	for f in _all_frames():
		grid.add_child(_frame_chip(f))
	_body.add_child(grid)

	_detail.add_child(Kit.heading("THE FIGHT"))
	_detail.add_child(Kit.label("%d v %d" % [_side_a.size(), _side_b.size()],
		Kit.BRIGHT, 24, true))
	if _side_a.is_empty() or _side_b.is_empty():
		_detail.add_child(Kit.label("BOTH SIDES NEED SOMEBODY", Kit.PROBLEM, Kit.SMALL, true))
		return
	_detail.add_child(Kit.spacer(0, 6))
	var watch := Kit.button("WATCH", Kit.BRIGHT, 18)
	watch.tooltip_text = "Spectate. You cannot be hit and cannot interfere."
	watch.pressed.connect(func(): fight_requested.emit(_matchup(), false))
	_detail.add_child(watch)
	var lead := Kit.button("LEAD", Kit.MONEY, 18)
	lead.tooltip_text = "Fight on your side, with the force above."
	lead.pressed.connect(func(): fight_requested.emit(_matchup(), true))
	_detail.add_child(lead)


## A SANITY CEILING, and the only reason a frame cannot be added. Twelve a side
## is already a large fight. It used to be enforced by a silent `return` in
## _add, so the twelfth chip you clicked simply did nothing and the thirteenth
## looked like a dead button — reported as "you can't select the chassis you've
## clicked on".
const PER_SIDE := 12


## ONE PLACE THAT TURNS AN ID INTO A FRAME, and it has to try both rosters.
##
## The player catalogue holds what YOU can build. The adversary's frames —
## marksman, chaser, rifleman, mortar_track, rover_gl, bastion and the rest,
## eleven of the twenty-three this screen offers — are not in it; they load
## through the force generator. _frames() already knew that. _side_box did not,
## so every adversary frame you added was listed by its raw id: "MORTAR_TRACK",
## "ROVER_GL", "RIFLEMAN_ARMOURED", in a column next to "Spotter Drone".
func _def(id: StringName):
	var f = catalogue.chassis_def(id) if catalogue != null else null
	if f == null:
		f = _Gen.swarm_frame(id)
	return f


## One side's list, with repeats COLLAPSED.
##
## Five Lances used to be five identical rows with five identical X buttons,
## which reads as a bug and costs the panel its whole height on one frame. It
## is now one row saying x5. The X takes one off, so the row counts back down
## rather than vanishing.
##
## ORDER OF FIRST APPEARANCE, not sorted: the list is something you built, and
## having it reshuffle itself when you add a second of something you already
## had would lose your place in it.
func _side_box(which: String, title: String, ids: Array) -> Control:
	var on: bool = String(_picking) == which
	var card := Kit.card(Kit.BRIGHT if on else Kit.LINE,
		func(): _picking = StringName(which); rebuild(), func(): pass, 8.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := Kit.vbox(4)
	card.add_child(col)
	var head := Kit.hbox(6)
	head.add_child(Kit.label(title, Kit.BRIGHT if on else Kit.DIM, Kit.BODY, true))
	head.add_child(Kit.fill())
	head.add_child(Kit.label("%d/%d" % [ids.size(), PER_SIDE],
		Kit.PROBLEM if ids.size() >= PER_SIDE else Kit.DIM, Kit.SMALL, true))
	col.add_child(head)
	if ids.is_empty():
		col.add_child(Kit.label("EMPTY", Kit.DIM, Kit.SMALL))

	var order: Array = []
	var count := {}
	for id in ids:
		if not count.has(id):
			count[id] = 0
			order.append(id)
		count[id] += 1

	for id in order:
		var the_id: StringName = id
		var f = _def(the_id)
		var line := Kit.hbox(6)
		line.add_child(Kit.label(f.display_name.to_upper() if f != null
			else String(the_id).to_upper().replace("_", " "), Kit.DIM, Kit.SMALL))
		if int(count[the_id]) > 1:
			line.add_child(Kit.label("x%d" % int(count[the_id]), Kit.BRIGHT, Kit.SMALL, true))
		line.add_child(Kit.fill())
		var drop := Kit.button("X", Kit.PROBLEM, Kit.SMALL)
		# ONE OFF, not the whole stack: the stack is a tally of a list, and
		# losing five Lances to one misclick is not a thing to design in.
		drop.pressed.connect(func():
			var at: int = ids.rfind(the_id)
			if at >= 0:
				ids.remove_at(at)
			rebuild())
		line.add_child(drop)
		col.add_child(line)
	return card


## One frame you can put on a side.
##
## GREYED WHEN IT CANNOT BE TAKEN, rather than clickable and inert. Two reasons
## it cannot: the side you are adding to is full, or the id resolves to no
## frame in either roster. Both used to be a silent `return` in _add — the chip
## lit up, took the click and did nothing.
func _frame_chip(f) -> Control:
	var why := _refuse(f)
	var ok: bool = why == ""
	var tint: Color = Kit.BRIGHT if ok else Kit.FAINT
	var card := Kit.card(Kit.LINE if ok else Kit.FAINT,
		func(): if ok: _add(f.id), func(): pass, 4.0)
	card.custom_minimum_size = Vector2(96, 76)
	card.tooltip_text = "%s · supply %d" % [f.display_name, f.supply] if ok else why
	# NOT JUST THE COLOUR. A tint alone is a thing you have to compare against
	# its neighbours to read; dimming the whole chip reads on its own.
	card.modulate.a = 1.0 if ok else 0.45
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ok \
		else Control.CURSOR_FORBIDDEN
	var col := Kit.vbox(2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)
	col.add_child(Kit.icon(Icons.chassis(f, "m"), tint, Vector2(72, 32)))
	var t := Kit.label(f.display_name.to_upper().left(12), tint, Kit.SMALL, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.clip_text = true
	col.add_child(t)
	return card


## Why this frame cannot be added right now, or "" when it can. The message is
## what the chip's tooltip says, so it has to read as an answer to "why did
## nothing happen when I clicked that".
func _refuse(f) -> String:
	if f == null:
		return "This frame is in neither roster, so there is nothing to field."
	var side: Array = _side_a if _picking == &"a" else _side_b
	if side.size() >= PER_SIDE:
		return "%s is full at %d. Take something off it first." % [
			"YOUR SIDE" if _picking == &"a" else "THEIRS", PER_SIDE]
	return ""


func _add(id: StringName) -> void:
	var side: Array = _side_a if _picking == &"a" else _side_b
	if side.size() >= PER_SIDE:
		# NOT SILENT. The chip is greyed and will not call this, so arriving
		# here means something else did — and a side that quietly stops growing
		# is the bug this whole pass was about.
		push_warning("SimArenaUI: %s already holds %d frames, so '%s' was not added." % [
			"your side" if _picking == &"a" else "theirs", PER_SIDE, String(id)])
		return
	side.append(id)
	rebuild()


# ── What the Lab needs ───────────────────────────────────────────────────────

## A LabMatchup is exactly what the player just built: two rosters, two orders
## and a distance. One repeat, because this is a thing you watch rather than a
## measurement.
func _matchup() -> Resource:
	var m = _Matchup.new()
	m.label = "%d v %d" % [_side_a.size(), _side_b.size()]
	m.allies = _frames(_side_a)
	m.hostiles = _frames(_side_b)
	m.repeats = 1
	m.swap_sides = false
	return m


## Resolve chosen ids to definitions, from EITHER roster. _frames is given ids
## rather than definitions so a rebuild never holds a stale resource, and the
## id may belong to the player's catalogue or the Swarm's.
func _frames(ids: Array) -> Array[ChassisDefinition]:
	var out: Array[ChassisDefinition] = []
	for id in ids:
		var f = catalogue.chassis_def(id) if catalogue != null else null
		if f == null:
			f = _Gen.swarm_frame(id)
		if f != null:
			out.append(f)
		else:
			push_warning("SimArenaUI: no frame '%s' in either roster, so it is left out of the fight." % id)
	return out


## Every frame worth fielding, BOTH SIDES' ROSTERS.
##
## The player catalogue is only what YOU can build — the Swarm's riflemen,
## chasers, leapers and shotgunners are not in it. A sim arena that could only
## field your own frames could not answer the question people actually bring to
## one: what does a Walker do against six chasers.
##
## Structures are left out. A fight between two Nests is not a fight.
func _all_frames() -> Array:
	var out: Array = []
	var seen := {}
	if catalogue != null:
		for f in catalogue.chassis:
			if f != null and f.supply > 0 and not seen.has(f.id):
				seen[f.id] = true
				out.append(f)
	for id in _Gen.SWARM_PATHS:
		if seen.has(id):
			continue
		var f = _Gen.swarm_frame(id)
		if f != null and f.supply > 0:
			seen[id] = true
			out.append(f)
	out.sort_custom(func(a, b): return a.supply < b.supply)
	return out


func _sim_missions() -> Array:
	var out: Array = []
	if campaign == null or not ("missions" in campaign):
		push_warning("SimArenaUI: no campaign, so there is no training to list.")
		return out
	for m in campaign.missions:
		if m != null and m.sim:
			out.append(m)
	return out


## Both exercises run at least once.
##
## ASKED OF THE SIM MISSIONS THEMSELVES rather than counted, so a third
## exercise added later is included without anyone remembering to change a
## number here. Same rule OpsTable._training_done() uses to open the war.
func _training_over() -> bool:
	var state = campaign.state if campaign != null and "state" in campaign else null
	if state == null:
		push_warning("SimArenaUI: no campaign state, so whether training is finished cannot be read. Showing both tabs.")
		return false
	var any := false
	for m in _sim_missions():
		any = true
		if state.clears_of(m.id) <= 0:
			return false
	return any
