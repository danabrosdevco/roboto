extends MissionObjective
class_name TrainingCore

# ─────────────────────────────────────────────
# THE LAST EXERCISE TEACHES THE THING THE CAMPAIGN IS MADE OF.
#
# The three sim arenas teach shooting, then a squad in a fight. Neither of them
# teaches CAPTURING — and capturing is the entire campaign: every site is its
# cores, holding them is what pays, and losing one is how you lose ground.
# A player arriving at Hillfort having never worked a core is meeting the verb
# the whole game is built on for the first time, under fire.
#
# So the Proving Ground gets one. Same HoldableCore the real sites use, same
# channel, same drone, same anchor, same beacon — in a place where nothing is
# at stake and it can be done twice.
#
# IT IS A MissionObjective, which is what gates it to the LAST arena. The
# Proving Ground level is shared by all three, and MissionObjective._ready
# frees any objective whose id the current operation did not ask for — so
# listing `proving_capture` in arena_5_proving's active_objectives, and nowhere
# else, is the whole of the gating. No mission check in here.
#
# BUILT RATHER THAN AUTHORED, because the arena has no capture point to borrow:
# this makes its own pad, post and interactible the way SiteSlice makes the
# bunker's.
# ─────────────────────────────────────────────

const _Core := preload("res://Env/world_objects/holdable_core.gd")
const _Signal := preload("res://Env/world_objects/core_signal.gd")
const INTERACTIBLE := preload("res://Env/world_objects/components/template_interactible.tscn")

## Where it stands. SET IN THE SCENE, not here — see the two nodes in
## maps/proving_level.tscn, which is the only thing that reads this default.
##
## THE CORE IS ON THE MAIN FLOOR AND THE BUNKER IS IN THE BAY, which is the
## 30 x 30 m floor at Godot z 59..89 behind the enemy blockhouse. The core
## stands at z 8 and the bunker at z 80.
##
## THEY USED TO BE 15 m APART IN THE SAME BAY — tools/build_proving.gd built
## it that way and said so, "a capture node and an extraction point in the
## same bay is what the bunker is". That was right while First Contact walked
## the floor first. With First Contact cut on 2026-10-22 this became the
## OPENING operation, and its first objective sat 93 m from the spawn behind
## the enemy position: the player's first act in the campaign was a two-minute
## walk. The core moved to the floor so the first fight happens on it.
##
## z 8, NOT z 0. There is a cross-wall over the whole centreline at z 0 whose
## deck is 4.59 m up — placing on the nominal centre buries the pad in it, and
## probe_arena_cores.gd says so by name. z 8 is the first flat open floor past
## it, which also makes the wall the cover you cross to reach the core.
##
## THE OLD NUMBERS WERE z 30 AND 37, against the 88 x 54 m arena. The rebuild
## on 2026-10-13 made that ground the enemy blockhouse, so the core would have
## been placed inside a building. tools/probe_arena_cores.gd now casts for the
## floor, asks the navmesh, checks all four pad corners and walks a path from
## the spawn — RUN IT IF THESE MOVE AGAIN; it is what caught z 0. The floor is
## at y 0, NOT the 0.5 the navmesh bakes at; placing at 0.5 floats the pad.
@export var place: Vector3 = Vector3(0.0, 0.0, 8.0)
@export var tier: int = 0
## What it is called on the beacon and in the prompt. A bunker is a core in
## everything but name — §12.7 makes taking it the thing that ends an
## operation, and the training arena teaches both verbs with one node.
@export var noun: String = "CORE"

var core: Node3D = null
## The adopted art's own landing pad, found by _dock_at() and handed to the
## HoldableCore in _wire_core. Empty when the art carries no Dock marker.
var _dock_path: NodePath


## THE REAL ART, instead of the generated placeholder.
##
## WHY THIS EXISTS. The whole argument for teaching capture in the arena is at
## the top of this file: "whatever it teaches has to be what the campaign then
## asks for". That was true of the MECHANISM from the start — same HoldableCore,
## same channel, same drone — and false of everything the player looks at. They
## learned the verb against a grey box and then met a 7 m compute core, and
## learned the way out against a second grey box and then met a tunnel mouth
## with doors.
##
## `core_scene` instances a compute_core_point prefab and takes its own
## Interactible. `bunker_mount` instead raises the entrance kit by mounting
## name, exactly as SiteSlice does on a real site. Neither set keeps the old
## placeholder, which is still the right answer for anything without art yet.
@export var core_scene: PackedScene
## One of SiteSlice's mountings: open, cliff or wall. Set INSTEAD of core_scene.
@export var bunker_mount: StringName = &""
## Tier of the prefab in `core_scene`, for sizing the interact volume. Small 0,
## standard 1, large 2 — a mismatch puts the player inside the volume, where
## the ray reports nothing to press.
@export var core_tier: int = 1

const BUNKER_MOUNTS := {
	&"open": preload("res://maps/blocks/bunker/bunker_entrance_open.tscn"),
	&"cliff": preload("res://maps/blocks/bunker/bunker_entrance_cliff.tscn"),
	&"wall": preload("res://maps/blocks/bunker/bunker_entrance_wall.tscn"),
}


func _on_objective_ready() -> void:
	position = place
	if bunker_mount != &"":
		_build_from_kit()
	elif core_scene != null:
		_build_from_prefab()
	else:
		_build()


## A real compute core, seated the way SiteSlice seats one: instance the
## prefab, find the Interactible it already carries, hang a HoldableCore off
## that. Nothing is generated and nothing is doubled.
func _build_from_prefab() -> void:
	var art := core_scene.instantiate()
	art.name = "Art"
	add_child(art)
	var inter := _interactible_in(art)
	if inter == null:
		push_warning("TrainingCore '%s': the core prefab has no Interactible, so the exercise has nothing to press. Falling back to the placeholder." % name)
		art.queue_free()
		_build()
		return
	# THE PREFAB IS AN OBJECTIVE IN ITS OWN RIGHT, AND WE ONLY WANT ITS ART.
	#
	# compute_core_point.tscn's ROOT NODE is an InteractObjective carrying no
	# id — a real site authors one on each instance (see hillfort_wip_slice),
	# and this one cannot, because TrainingCore is already the objective for
	# this capture. Left alone it joined the tracker as a FOURTH, id-less,
	# always-live line: the HUD counted 0/3 and listed four, and the extra one
	# said CAPTURE THE OBJECTIVE and could never be ticked, because
	# HoldableCore._take_terminal() had just disconnected it from the one
	# terminal that would have done it.
	#
	# It survived the prune in MissionObjective._ready because that exempts a
	# blank id, and it cannot simply be freed: the objective script is on the
	# ROOT, so freeing it takes the whole core with it. So it stands down.
	_stand_down(art)
	_dock_at(_named_in(art, "Dock"))
	_wire_core(inter, core_tier)


## Take an adopted prefab's own objective out of the mission without freeing
## the node it is standing on. Leaving the group is what matters —
## ObjectiveTracker.refresh() reads `mission_objectives` and nothing else —
## and this runs during our own _ready, which is before the tracker is asked.
func _stand_down(n: Node) -> void:
	if n is MissionObjective:
		var o := n as MissionObjective
		o.remove_from_group("mission_objectives")
		o.starts_active = false
		o.active = false
	for c in n.get_children():
		_stand_down(c)


## Point the capture at the landing pad the ART already carries.
##
## THE PREFAB SHIPS A `Dock` MARKER — Core/Dock on every compute_core_point —
## and HoldableCore looks for one under itself and under its parent. Ours is
## neither: _wire_core hangs a bare Hold node off TrainingCore while the
## marker is several levels down inside Art, so the search missed it and the
## dock fell all the way through to the tier table, warning by name every run
## that the drone was landing on the axis at a height from a table.
##
## On a real site the HoldableCore is seated ON the prefab and the search
## finds the marker for free. This is the adoption case saying where it went.
func _dock_at(marker: Node3D) -> void:
	if marker == null:
		return   # no pad on this art: HoldableCore's table still applies, loudly
	# Relative to the Hold node, which _wire_core is about to add beside Art.
	_dock_path = NodePath("../" + String(get_path_to(marker)))


## The bunker entrance kit, which is what the way out looks like on every real
## site since §12.7 replaced the extraction pad with the doors.
func _build_from_kit() -> void:
	var mount: PackedScene = BUNKER_MOUNTS.get(bunker_mount, null)
	if mount == null:
		push_warning("TrainingCore '%s': '%s' is not a bunker mounting; expected one of %s. Falling back to the placeholder." % [
			name, String(bunker_mount), str(BUNKER_MOUNTS.keys())])
		_build()
		return
	var kit := mount.instantiate()
	kit.name = "Entrance"
	add_child(kit)
	# F GOES ON THE TERMINAL FACE, not in the middle of the doorway — the same
	# handle SiteSlice uses, and a rename upstream has to be loud rather than
	# quietly leaving an exercise with nothing to interact with.
	var face := _named_in(kit, "TerminalFace")
	if face == null:
		push_warning("TrainingCore '%s': the bunker kit has no TerminalFace, so there is nowhere to put the prompt." % name)
	var inter: Interactible = INTERACTIBLE.instantiate()
	inter.name = "Interactible"
	add_child(inter)
	inter.collision_layer = 3
	inter.type = Enums.InteractTypes.OBJECTIVE
	inter.destroy_on_use = false
	inter.disable_on_use = false
	inter.global_position = (face as Node3D).global_position if face != null \
		else global_position + Vector3(0.0, 1.0, 0.0)
	var ics := CollisionShape3D.new()
	var ibox := BoxShape3D.new()
	ibox.size = Vector3(3.0, 2.6, 3.0)
	ics.shape = ibox
	inter.add_child(ics)
	_wire_core(inter, 1)


## The half both real-art paths share: the HoldableCore and its signal, which
## are the part that was always real.
func _wire_core(inter: Interactible, tier: int) -> void:
	core = Node3D.new()
	core.set_script(_Core)
	core.name = "Hold"
	core.size_tier = tier
	core.mark_noun = noun
	core.interactible = inter
	if not _dock_path.is_empty():
		core.dock_marker = _dock_path
	add_child(core)
	var fx := Node3D.new()
	fx.set_script(_Signal)
	fx.name = "Signal"
	fx.core = core
	add_child(fx)
	# SHUT UNTIL ITS TURN, same rule and same reason as the placeholder path:
	# HoldableCore.complete()s on capture without consulting `active`, so the
	# bunker could be taken before the core and tick a line never shown.
	if not active:
		inter.collision_layer = 0
		objective_activated.connect(_on_turn_came)


func _interactible_in(n: Node) -> Interactible:
	if n is Interactible:
		return n as Interactible
	for c in n.get_children():
		var f := _interactible_in(c)
		if f != null:
			return f
	return null


func _named_in(n: Node, named: String) -> Node:
	if String(n.name) == named:
		return n
	for c in n.get_children():
		var f := _named_in(c, named)
		if f != null:
			return f
	return null


func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.19, 0.20)
	mat.emission_enabled = true
	mat.emission = HUDPalette.FAC_ADVERSARY
	mat.emission_energy_multiplier = 0.55

	# A pad, so it reads as installed rather than dropped on the floor.
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var pm := BoxMesh.new()
	pm.size = Vector3(3.4, 0.4, 3.4)
	pad.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.14, 0.15, 0.14)
	pad.material_override = pmat
	pad.position = Vector3(0.0, 0.2, 0.0)
	add_child(pad)

	var body := MeshInstance3D.new()
	body.name = "CoreBody"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 4.2, 1.0)
	body.mesh = bm
	body.material_override = mat
	body.position = Vector3(0.0, 2.1, 0.0)
	add_child(body)

	# COLLISION ON ITS OWN BODY. The interact volume is an Area3D on layer 3
	# and has to stay separate, or the player's ray stops on the pillar before
	# it reaches the thing it is trying to press.
	var solid := StaticBody3D.new()
	solid.name = "CoreSolid"
	var scs := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = bm.size
	scs.shape = sbox
	solid.add_child(scs)
	solid.position = body.position
	add_child(solid)

	var inter: Interactible = INTERACTIBLE.instantiate()
	inter.name = "Interactible"
	add_child(inter)
	# LAYER 3, not the template's 1 — the player's InteractRaycast is mask 2
	# and layer 1 never meets it. Cost a session on the operations table.
	inter.collision_layer = 3
	inter.type = Enums.InteractTypes.OBJECTIVE
	inter.destroy_on_use = false
	inter.disable_on_use = false
	inter.position = Vector3(0.0, 1.0, 0.0)
	var ics := CollisionShape3D.new()
	var ibox := BoxShape3D.new()
	ibox.size = Vector3(3.0, 2.6, 3.0)
	ics.shape = ibox
	inter.add_child(ics)



	# THE SAME CORE THE REAL SITES USE. Not a simplified teaching version:
	# whatever it teaches has to be what the campaign then asks for.
	core = Node3D.new()
	core.set_script(_Core)
	core.name = "Hold"
	core.size_tier = tier
	core.mark_noun = noun
	# THE TOP OF THIS POST, read off the box above rather than left to the tier
	# table. The two agreed by coincidence — a 4.2 m body against tier 0's 4.2 —
	# and holdable_core's table is now the last-resort fallback that WARNS,
	# because the relay cores' pad is off-axis and no height can describe it.
	# This core really is a centred cap on a mast, so an axis dock is correct
	# here; saying so is what stops the warning being noise.
	core.dock_height = bm.size.y
	core.interactible = inter
	add_child(core)

	# The light and the sound, same as a real one. `core` is set BEFORE
	# add_child because CoreSignal reads it in _ready, and _ready fires the
	# instant it is parented.
	var fx := Node3D.new()
	fx.set_script(_Signal)
	fx.name = "Signal"
	fx.core = core
	add_child(fx)

	# SHUT UNTIL IT IS THIS ONE'S TURN. The bunker waits on the core — that is
	# the lesson, core then bunker then out — but nothing enforced the order:
	# HoldableCore._drive_authored calls complete() on capture without looking
	# at `active`, so walking past the core and pressing F on the bunker ticked
	# an objective the HUD had never shown.
	#
	# THE LAYER, not a `disabled` flag: the player's InteractRaycast is mask 2,
	# so layer 0 is simply not there to be hit and no prompt appears. Restored
	# to 3 when the prerequisite completes — 3 and not 1 for the reason above.
	#
	# _ready activates before it calls _on_objective_ready, so `active` is
	# already right here and the signal has already fired for anything that
	# starts open.
	if not active:
		inter.collision_layer = 0   # AFTER HoldableCore._wire_interactible, which sets 3
		objective_activated.connect(_on_turn_came)


## The objective ticks when the core is held — HoldableCore drives the
## MissionObjective it is parented to, both ways, exactly as it does on a site.
## Nothing extra is wired here; that is the point of using the real one.
func progress() -> Array:
	if core == null or not is_instance_valid(core):
		return [0, 1]
	return [1 if core.is_held_by_player() else 0, 1]


## Its prerequisite finished, so open it. See the lock in _build().
func _on_turn_came(_o = null) -> void:
	var inter := get_node_or_null("Interactible")
	if inter == null:
		push_warning("TrainingCore '%s': activated with no Interactible, so there is nothing to open and this capture cannot be worked." % name)
		return
	inter.collision_layer = 3


## CAPTURE THE CORE / CAPTURE THE BUNKER, built the way every other objective
## builds its line: display_name names the THING and verb() supplies the action
## — see the labelling note in mission_objective.gd.
##
## The scene used to author the whole phrase instead ("WORK THE CORE"), which
## both read badly and sidestepped the one rule the rest of the game follows.
func verb() -> String:
	return "Capture the"
