extends Node
class_name RankKit

# ─────────────────────────────────────────────
# RANK HEADGEAR, bolted to a frame at spawn.
#
# The hats are authored as CSG in tools/mockup_parts.gd, because eight rounds of
# iteration needed something editable, and BAKED TO MESHES by tools/bake_hats.gd
# into Character/characters/ai/hats/. Nothing here touches CSG, deliberately:
# Character/characters/ai/csg_bake.gd exists because a CSGShape3D rebuilds its
# geometry the first time it enters the tree, and a reserve wave of 40 robots
# cost 335.8 ms on that frame. Six to ten CSG shapes per robot for a hat would
# hand all of that back. A baked hat is one instantiate and some MeshInstance3D
# nodes sharing meshes that already exist.
#
# PARENTED TO THE TURRET, NOT THE BODY. The hat is placed in rig space in
# mockup_parts, and the turret sits at the origin of that space on all three
# frames — so the transforms carry over unchanged AND the hat traverses with the
# turret instead of staying square to the hull while the gun tracks.
#
# WHY IT REGISTERS WITH THE LIVERY BY HAND. FactionLivery.pieces is exported as
# node_paths, resolved to live node objects at instantiation. A hat added later
# is simply not in that list, so it renders in the stock material and a veteran
# enemy would wear a player-coloured cap. add_pieces() exists for this.
# ─────────────────────────────────────────────

## The baked hat. Leave null for a frame that earns no headgear.
@export var hat: PackedScene

## Where it hangs — the Turret on the rover and walker, the Rig on the
## reclaimer, whose cab does not rotate.
@export var mount: Node3D

## The space the hat's numbers were measured in: the Rig, which is identity on
## all three frames.
##
## THIS IS NOT OPTIONAL BOOKKEEPING. Every coordinate in mockup_parts is rig
## space — the walker's skull is at y 1.24 — but the Turret it hangs from sits
## at y 0.95, so parenting the hat there straight off would put the skull at
## 2.19 and float it a metre over the frame. The hat is placed by taking the
## mount's transform back out again, which is exact and survives anyone moving
## a turret later.
@export var authored_in: Node3D

## The frame's FactionLivery, so the hat takes the faction colour.
@export var livery: FactionLivery

## Whether the hat joins the livery at all.
##
## IT IS NOT FREE. FactionLivery hands every piece ONE shared material — that is
## the whole design, four materials for the game — so a hat that joins gives up
## its own surface and wears the body's. For the Tarleton and the beret that is
## what you want. For the RECLAIMER'S HARD HAT it is not: the point of that hat
## is that it is hi-vis orange, and joining the livery paints it the same
## concrete as the hull. Turn this off there to keep it, at the cost of the hat
## reading the same on both sides — which for a hard hat is arguably correct.
@export var join_livery: bool = true

## Rank at which the hat appears. SoldierRecord ranks run 0-5:
## Recruit, Regular, Veteran, Sergeant, Lieutenant, Captain.
##
## LEFT AT 0 FOR NOW, which means every frame of this type wears it. The rank is
## not plumbed through yet — SoldierRecord.write_to() does not copy `rank` onto
## the body, so there is nothing on a spawned robot to read. Raising this to 2
## is the whole change once it does.
@export var min_rank: int = 0

var _rig: Node3D = null

## What is actually on the robot right now, so a refit can tell whether the
## squad screen changed anything.
var _worn: StringName = &""

## The pauldrons, which are a second piece and not a hat — a Captain wears both,
## so they mount and unmount independently of whatever is on its head.
var _pads: Node3D = null
var _wearing_pads: bool = false


func _ready() -> void:
	if mount == null:
		push_warning("RankKit on %s has no mount; nothing will be worn." % get_path())
		return
	_wire_live_refit()
	if _rank() < min_rank:
		return
	# DEFERRED, AND IT HAS TO BE.
	#
	# RankKit is a child of the body, and on the soldier frames `mount` IS the
	# body. Adding a child to a node that is still setting its own children up
	# fails — "parent node is busy setting up children" — and the hat is left
	# orphaned: instantiated, 52 meshes allocated, attached to nothing. The
	# soldier shipped bare while the squad card showed a cap, because the card
	# reads the record and the record was right.
	#
	# The vehicles got away with it by accident: they mount on Rig/Turret, which
	# is not the node being iterated at that moment.
	_refit.call_deferred(_chosen_id())
	_refit_pads.call_deferred(_wants_pads())


## Hand the hat's pieces to the livery, grouped by surface.
##
## NOT IN ONE LUMP. Livery paints a whole robot with a single material, which is
## right for a hull and wrong for a hat: the beret would come out made of
## concrete. Each group goes in with its own base, so the hat takes the faction
## COLOUR on its OWN texture.
func _dress() -> void:
	_dress_rig(_rig)


## Hand one rig's pieces to the livery, grouped by surface.
func _dress_rig(rig: Node3D) -> void:
	if not join_livery or rig == null:
		return
	if livery == null:
		push_warning("RankKit on %s has no livery; the hat will not take faction colour." % get_path())
		return
	var groups: Dictionary = {}
	for n in rig.find_children("*", "MeshInstance3D", true, false):
		var surface: String = str(n.get_meta("surface", ""))
		if not groups.has(surface):
			groups[surface] = [] as Array[Node3D]
		(groups[surface] as Array[Node3D]).append(n as Node3D)
	for surface: String in groups:
		livery.add_pieces_with(groups[surface], Cosmetics.surface_base(surface))




## Which hat this particular robot wears.
##
## THE RECORD WINS WHERE THERE IS ONE. SoldierRecord.write_to stamps a
## `cosmetic_id` meta before the body is ever added to the tree, so a squad
## robot wears what you picked on its card — including NOTHING, when you picked
## nothing, which is why an empty meta is respected rather than falling through
## to the default.
##
## Everything with no record — every enemy in the game — has no meta at all and
## wears `hat`, the scene's own default. That is the difference between "chose
## none" and "was never asked".
func _chosen_hat() -> PackedScene:
	var p := get_parent()
	if p != null and p.has_meta("cosmetic_id"):
		return Cosmetics.scene(StringName(p.get_meta("cosmetic_id")))
	return hat


## The id behind _chosen_hat, so a refit can compare without loading a scene.
func _chosen_id() -> StringName:
	var p := get_parent()
	if p != null and p.has_meta("cosmetic_id"):
		return StringName(p.get_meta("cosmetic_id"))
	for id: StringName in Cosmetics.ENTRIES:
		if hat != null and Cosmetics.scene_path(id) == hat.resource_path:
			return id
	return Cosmetics.NONE


## The wearer's rank, or 0 while there is nothing to ask.
func _rank() -> int:
	var p := get_parent()
	if p == null:
		return 0
	if p.has_meta("rank"):
		return int(p.get_meta("rank"))
	if "rank" in p:
		return int(p.rank)
	return 0


## Put `hat` under `mount`, placed as though it were authored in
## `authored_in`'s space. Returns the instanced rig, or null.
##
## STATIC, AND ON LOCAL TRANSFORMS, because it has two callers and one of them
## is not in a tree. tools/bake_icons.gd has to fit the hat BEFORE the body is
## rendered, and icon_studio._strip() calls set_script(null) on every node first
## — so RankKit is not alive to do it there, and global_transform is not
## available either. Walking the local transforms up from the mount gives the
## same answer without needing the body to be anywhere.
##
## The alternative was a second placement implementation in the baker, and the
## day the two drifted the card would show a hat sitting somewhere the
## battlefield never puts it.
static func mount_hat(hat: PackedScene, mount: Node3D, authored_in: Node3D) -> Node3D:
	if hat == null or mount == null:
		return null
	var rig := hat.instantiate() as Node3D
	if rig == null:
		return null
	mount.add_child(rig)
	rig.transform = authored_offset(mount, authored_in)
	return rig


## The transform that cancels out everything between `authored_in` and `mount`.
##
## The hats are measured in rig space — the walker's skull is at y 1.24 — but
## the Turret they hang from sits at y 0.95, so hanging one straight off would
## put the skull at 2.19 and float it a metre over the frame.
static func authored_offset(mount: Node3D, authored_in: Node3D) -> Transform3D:
	if authored_in == null or mount == null or mount == authored_in:
		return Transform3D.IDENTITY
	var down := Transform3D.IDENTITY
	var n: Node3D = mount
	while n != null and n != authored_in:
		down = n.transform * down
		n = n.get_parent() as Node3D
	# Not an ancestor after all — place it where it was authored and let the
	# render say so, rather than silently applying a transform that means
	# nothing.
	if n == null:
		return Transform3D.IDENTITY
	return down.affine_inverse()


# ─────────────────────────────────────────────
# LIVE REFIT
# ─────────────────────────────────────────────
# Picking a hat on the squad screen changes the robot standing in front of you,
# rather than waiting for the next deploy.
#
# THROUGH roster_changed, found by GROUP. The campaign sits above World and this
# component must not assume a path into it — the same ready-order rule that
# CLAUDE.md spells out for HUD and test_character. A robot in a level with no
# campaign (every enemy, and the laboratory) simply finds nothing and wears what
# it was given.


func _wire_live_refit() -> void:
	var campaign := get_tree().get_first_node_in_group("campaign")
	var state = campaign.get("state") if campaign != null else null
	if state == null or not state.has_signal("roster_changed"):
		return
	if not state.roster_changed.is_connected(_on_roster_changed):
		state.roster_changed.connect(_on_roster_changed)


func _on_roster_changed() -> void:
	_refit_pads(_wants_pads())
	var want := _wanted_cosmetic()
	if want == _worn:
		return
	_refit(want)


## What the RECORD says now, re-read rather than trusted from the meta.
##
## The meta is a snapshot taken by write_to when the body was built; the record
## is what the squad screen edits. Looking the record up again by its id is the
## only way a change made after deploy reaches the model.
func _wanted_cosmetic() -> StringName:
	var p := get_parent()
	if p == null:
		return _worn
	var campaign := get_tree().get_first_node_in_group("campaign")
	var state = campaign.get("state") if campaign != null else null
	if state != null and p.has_meta("record_id"):
		var id = p.get_meta("record_id")
		for r in state.roster:
			if r != null and r.id == id:
				return r.cosmetic_id if Cosmetics.fits(r.chassis_id, r.cosmetic_id) else Cosmetics.NONE
	if p.has_meta("cosmetic_id"):
		return StringName(p.get_meta("cosmetic_id"))
	return _worn


## Swap the hat on a robot that is already standing.
func _refit(id: StringName) -> void:
	if _rig != null:
		# TOLD THE LIVERY FIRST, and removed from the tree BEFORE queue_free:
		# queue_free is deferred, so the node is still in `pieces` and still a
		# child for the rest of this frame, and a repaint in between would paint
		# a corpse.
		if livery != null and join_livery:
			var gone: Array[Node3D] = []
			for n in _rig.find_children("*", "MeshInstance3D", true, false):
				gone.append(n as Node3D)
			livery.remove_pieces(gone)
		var parent := _rig.get_parent()
		if parent != null:
			parent.remove_child(_rig)
		_rig.queue_free()
		_rig = null
	_worn = id
	var scene := Cosmetics.scene(id)
	if scene == null or mount == null:
		return
	_rig = mount_hat(scene, mount, authored_in)
	if _rig != null:
		_dress()


## Pauldrons on or off, independently of the hat.
func _refit_pads(on: bool) -> void:
	if on == _wearing_pads and (_pads != null) == on:
		return
	_wearing_pads = on
	if _pads != null:
		if livery != null and join_livery:
			var gone: Array[Node3D] = []
			for n in _pads.find_children("*", "MeshInstance3D", true, false):
				gone.append(n as Node3D)
			livery.remove_pieces(gone)
		var parent := _pads.get_parent()
		if parent != null:
			parent.remove_child(_pads)
		_pads.queue_free()
		_pads = null
	if not on:
		return
	var scene := Cosmetics.pauldrons_scene()
	if scene == null or mount == null:
		return
	_pads = mount_hat(scene, mount, authored_in)
	if _pads != null:
		_dress_rig(_pads)


## Whether this robot should be wearing pauldrons right now.
func _wants_pads() -> bool:
	var p := get_parent()
	if p == null:
		return false
	var campaign := get_tree().get_first_node_in_group("campaign")
	var state = campaign.get("state") if campaign != null else null
	if state != null and p.has_meta("record_id"):
		var id = p.get_meta("record_id")
		for r in state.roster:
			if r != null and r.id == id:
				return r.pauldrons and Cosmetics.pauldrons_fit(r.chassis_id)
	if p.has_meta("pauldrons"):
		return bool(p.get_meta("pauldrons"))
	return false
