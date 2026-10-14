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


## A frame, optionally wearing a cosmetic.
##
## FALLS BACK TO THE BARE ICON when the variant has not been baked, rather than
## to nothing: a robot in a hat nobody has re-baked for should still draw as
## itself, not vanish off its own card. Passing NONE is exactly the lookup this
## always was, so every existing call keeps working unchanged.
static func chassis(frame: ChassisDefinition, size: String,
		cosmetic: StringName = &"") -> Texture2D:
	if frame == null:
		return null
	if cosmetic != &"":
		var worn := _load(path("chassis",
				StringName(str(frame.id) + Cosmetics.icon_suffix(cosmetic)), size))
		if worn != null:
			return worn
	if frame.icon != null:
		return frame.icon
	return _load(path("chassis", frame.id, size))


static func path(group: String, id: StringName, size: String) -> String:
	return "%s/%s/%s_%s.png" % [DIR, group, id, size]


static func _load(file: String) -> Texture2D:
	if not ResourceLoader.exists(file):
		return null
	return load(file) as Texture2D


## The picture for a frame's BUILT-IN tool — a Mechanic's welder, a Chaser's
## claws — which belongs to no catalogue entry because there is nothing to buy
## and nothing to take off. Named by ChassisDefinition.built_in, lowercased: a
## built-in sharing its name with an item (the Spotter's OPTICS) simply finds
## that item's icon, and one with no art at all comes back null like any other.
static func built_in(name: String, size: String) -> Texture2D:
	if name == "":
		return null
	return _load(path("items", StringName(name.to_lower()), size))
