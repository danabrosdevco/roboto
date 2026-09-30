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
	var null_items := 0
	var null_chassis := 0

	for i in items:
		if i == null:
			null_items += 1
			continue
		if i.id == &"":
			push_warning("ItemCatalogue: an item has a blank id and was skipped.")
			continue
		_item_index[i.id] = i

	for c in chassis:
		if c == null:
			null_chassis += 1
			continue
		if c.id == &"":
			push_warning("ItemCatalogue: a chassis has a blank id and was skipped.")
			continue
		_chassis_index[c.id] = c

	# A renamed or moved .tres leaves a NULL in the array — the catalogue still
	# loads, the entry is just gone. That reads downstream as "this soldier has
	# no chassis", which points nowhere near the actual cause. Say it plainly.
	if null_items > 0:
		push_error("ItemCatalogue: %d item entr%s could not be loaded (renamed or moved .tres?). Re-pick them in the inspector." % [
			null_items, "y" if null_items == 1 else "ies"])
	if null_chassis > 0:
		push_error("ItemCatalogue: %d chassis entr%s could not be loaded (renamed or moved .tres?). Soldiers will have NO CHASSIS and no slots until this is fixed." % [
			null_chassis, "y" if null_chassis == 1 else "ies"])
	if _chassis_index.is_empty():
		push_error("ItemCatalogue: no usable chassis at all. Every soldier will show 'no chassis'.")
	else:
		print("[Catalogue] %d items, %d chassis: %s" % [
			_item_index.size(), _chassis_index.size(), _chassis_index.keys()])


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
