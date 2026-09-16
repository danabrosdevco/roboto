extends Resource
class_name ItemCatalogue

# ─────────────────────────────────────────────
# ITEM CATALOGUE — every item and chassis the game knows about.
#
# Authored once as a .tres and handed to CampaignManager. Everything else
# references items by id and comes here to resolve them, so there's exactly one
# place a definition lives and ids in old saves keep resolving after a patch.
# ─────────────────────────────────────────────

@export var items: Array[ItemDefinition] = []
@export var chassis: Array[ChassisDefinition] = []

var _item_index: Dictionary = {}
var _chassis_index: Dictionary = {}


func _build_index() -> void:
	_item_index.clear()
	_chassis_index.clear()
	for i in items:
		if i != null and i.id != &"":
			_item_index[i.id] = i
	for c in chassis:
		if c != null and c.id != &"":
			_chassis_index[c.id] = c


func item(id: StringName) -> ItemDefinition:
	if _item_index.is_empty():
		_build_index()
	return _item_index.get(id)


func chassis_def(id: StringName) -> ChassisDefinition:
	if _chassis_index.is_empty():
		_build_index()
	return _chassis_index.get(id)


func items_of_kind(kind: int) -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	for i in items:
		if i != null and i.kind == kind:
			out.append(i)
	return out
