extends RefCounted

# ─────────────────────────────────────────────
# ICONS — the baked line art, for the UI to show.
#
#   res://icons/items/<item id>_<s|m|l>.png
#   res://icons/chassis/<chassis id>_<s|m|l>.png
#
# White lines on transparent: tint them with modulate (bright for ready, dim
# for benched, red for wrecked). Sizes are in icon_art.gd; tools/bake_icons.gd
# makes the files. An icon that has not been baked comes back null, and the
# UI shows the name alone: a picture is never the only way to tell what
# something is.
# ─────────────────────────────────────────────

const DIR := "res://icons"


static func item(item_def: ItemDefinition, size: String) -> Texture2D:
	if item_def == null:
		return null
	# An icon set by hand on the item wins over the baked one.
	if item_def.icon != null:
		return item_def.icon
	return _load(path("items", item_def.id, size))


static func chassis(frame: ChassisDefinition, size: String) -> Texture2D:
	if frame == null:
		return null
	if frame.icon != null:
		return frame.icon
	return _load(path("chassis", frame.id, size))


static func path(group: String, id: StringName, size: String) -> String:
	return "%s/%s/%s_%s.png" % [DIR, group, id, size]


static func _load(file: String) -> Texture2D:
	if not ResourceLoader.exists(file):
		return null
	return load(file) as Texture2D
