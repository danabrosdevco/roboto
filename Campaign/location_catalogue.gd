extends Resource
class_name LocationCatalogue

# ─────────────────────────────────────────────
# LOCATION CATALOGUE — every place on the board.
#
# The same shape as ItemCatalogue and for the same reason: authored once as a
# .tres, handed to CampaignManager, and everything else references a place by
# id and comes here to resolve it. One place a definition lives, and ids in old
# saves keep resolving after a patch.
#
# NOT DirAccess over res://. enemy_commander.gd indexes Campaign/chassis/ that
# way and says in its own comment why that is a development-only path: a
# directory listing does not enumerate in an exported build. A catalogue
# resource is the shape that ships.
# ─────────────────────────────────────────────

## Array[Resource], not Array[Location]. A brand-new `class_name` is not
## visible to another script until the editor rescans, and this project cannot
## run --import — so naming the type here fails the parse check outright. The
## .tres is authored the same way. Same reason holdable_core.gd types its tap
## as Node3D.
@export var locations: Array[Resource] = []

var _index: Dictionary = {}
var _by_mission: Dictionary = {}


func _build_index() -> void:
	_index.clear()
	_by_mission.clear()
	var blanks := 0
	for l in locations:
		if l == null:
			blanks += 1
			continue
		if l.id == &"":
			push_warning("LocationCatalogue: a location has a blank id and was skipped.")
			continue
		if _index.has(l.id):
			push_warning("LocationCatalogue: two locations share the id '%s'; the second is ignored." % l.id)
			continue
		_index[l.id] = l
		if l.mission_id != &"":
			_by_mission[l.mission_id] = l
		# The defence of the same ground resolves here too — see Location.
		if "defend_mission_id" in l and l.defend_mission_id != &"":
			_by_mission[l.defend_mission_id] = l
	if blanks > 0:
		# A null slot is an array entry somebody cleared in the inspector, and
		# it means a place silently stopped existing — which reads in play as a
		# site that pays nothing and cannot be taken.
		push_warning("LocationCatalogue: %d empty slot(s) in `locations`." % blanks)


## The place with this id, or null.
func of(id: StringName) -> Resource:
	if _index.is_empty():
		_build_index()
	return _index.get(id)


## The place an operation is fought over. The mission knows its own id, so this
## is how a debrief turns "you cleared basin_1_anchor" into "you now hold
## Valley Basin".
func for_mission(mission_id: StringName) -> Resource:
	if _by_mission.is_empty():
		_build_index()
	return _by_mission.get(mission_id)


## Every place, index built. Used by the income walk, so it must not be the
## raw array — a null in there would be a null in the sum.
func all() -> Array[Resource]:
	if _index.is_empty():
		_build_index()
	var out: Array[Resource] = []
	for l in _index.values():
		out.append(l)
	return out
