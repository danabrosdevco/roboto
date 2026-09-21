extends RefCounted

# ─────────────────────────────────────────────
# ICON ART — what each icon is drawn from, and the sizes it is baked at.
#
# Anything with a model is drawn from it: an item from the model inside its
# AI (or HUD) scene, a frame from its robot scene. Things with no model at all
# — modules, the repair kit — are line drawings here, in a 32x32 box, rendered
# with the same line weight so the two kinds sit together.
# ─────────────────────────────────────────────

## Size classes, in real pixels. The UI is a fixed 1152x648 canvas, so these
## are the sizes icons are shown at, and each is baked on its own so the line
## is the same weight in a slot tile as in the shop.
const SIZES := {
	"wide": {"s": Vector2i(40, 15), "m": Vector2i(96, 36), "l": Vector2i(256, 96)},
	"square": {"s": Vector2i(16, 16), "m": Vector2i(36, 36), "l": Vector2i(96, 96)},
	"frame": {"s": Vector2i(40, 40), "m": Vector2i(64, 64), "l": Vector2i(128, 128)},
}

## Icons drawn from a different model than the item uses in the game. The EMP
## reuses the frag's model when thrown, and two identical grenades in a list say
## nothing, so it borrows the flashbang from the same pack.
const MODEL_OVERRIDES := {
	&"emp": "res://3d_assets/Flat Grenades_FBX/Flashbang_West.fbx",
	# Built from primitives, so there is no model file in their scenes for
	# model_in() to find.
	&"machine_gun": "res://Character/weapon/models/machine_gun_model.tscn",
	&"grenade_launcher": "res://Character/weapon/models/grenade_launcher_model.tscn",
	&"shotgun": "res://Character/weapon/models/pump_shotgun_model.tscn",
	&"hatchling": "res://Character/weapon/models/hatchling_canister_model.tscn",
	&"recoilless": "res://Character/weapon/models/recoilless_model.tscn",
	# The tube on the Reclaimer's boom is a pipe with rings on it; drawn on a
	# baseplate and bipod at 45 degrees, it reads as a mortar at 15 pixels.
	&"mortar": "res://Character/weapon/models/mortar_icon_model.tscn",
}

## Orientation fixes, found by looking: [mirror left-right, mirror up-down].
## A gun should point right.
const FLIPS := {}

## How an item is framed when it is not the default for its kind (weapons are
## "side", everything else "upright"). The repair tool is held like a gun. The
## hatchling canister is seen from above a little ("three_quarter"): side on,
## its pull ring is edge-on and the pod reads as a bell with a T on top.
const FRAMINGS := {
	&"repair_tool": "side",
	# A launcher reads as a tube, which means lengthways like a gun, not
	# stood on end like a canister.
	&"recoilless": "side",
	&"hatchling": "three_quarter",
}

const MODEL_EXTENSIONS := ["blend", "glb", "gltf", "fbx", "dae"]

## Drawings for things with no model: SVG path data in a 32x32 box.
const DRAWINGS := {
	&"repair_kit": "M5 11H27V26H5Z M12 11V8H20V11 M16 14V23 M11.5 18.5H20.5",
	&"scanner": "M6 16a10 10 0 1 0 20 0a10 10 0 1 0 -20 0 M11 16a5 5 0 1 0 10 0a5 5 0 1 0 -10 0 M16 16L24 8",
	&"armor_plating": "M8 6H24L27 11L24 27H8L5 11Z M5 11H27 M11 16H21 M12 21H20",
	&"overclock_servos": "M9 16a7 7 0 1 0 14 0a7 7 0 1 0 -14 0 M16 5V9 M16 23V27 M5 16H9 M23 16H27 M8.2 8.2L11 11 M21 21L23.8 23.8 M8.2 23.8L11 21 M21 11L23.8 8.2 M17 11.5L14.5 16H17.5L15 20.5",
	&"hardened_uplink": "M16 28V13 M11 28H21 M14.5 11.5a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0 M11 7Q8 11.5 11 16 M21 7Q24 11.5 21 16 M8 4Q3 11.5 8 19 M24 4Q29 11.5 24 19",
	&"nanite_reboot": "M11 11L13.5 6.7H18.5L21 11L18.5 15.3H13.5Z M5.5 21L8 16.7H13L15.5 21L13 25.3H8Z M16.5 21L19 16.7H24L26.5 21L24 25.3H19Z",
	# The Sensor Relay. Its id is still &"optics" and stays that way: ids are
	# keys into saved allocations, fitted module_ids and unlock lists, and only
	# the first of those has a rename table. Renaming it would strand a bought
	# one and its 70 resources in every campaign in progress.
	&"optics": "M6 13H26V19H6Z M26 12H29V20H26 M3 14H6V18H3 M11 13V10H15V13 M17 13V10H21V13",
	&"utility_harness": "M9 4L23 28 M23 4L9 28 M4 13H10V20H4Z M22 13H28V20H22Z M13 24H19V29H13Z",
	# Cyclic Feed: a belt of rounds running into a feed throat. The rounds are
	# the point — this is the module that decides you would rather spend them.
	&"cyclic_feed": "M4 12H20V20H4Z M20 11L28 8V24L20 21Z M8 12V20 M12 12V20 M16 12V20 M6 24H18",
}

## Anything without a model or a drawing gets a plain crate.
const FALLBACK_DRAWING := "M6 9H26V25H6Z M6 9L10 5H30L26 9 M30 5V21L26 25"


## Which size class an item's icons are baked in: THE SLOT DECIDES, not the
## shape of the thing.
##
## This used to bake anything side-framed wide, which put a 96x36 recoilless
## into the 36x36 gear tile — and Kit.icon draws at native size, so it simply
## hung out over both sides of the card. Framing and size class are separate
## questions: the tube is still drawn lengthways, it is just drawn lengthways
## inside a square. Only a weapon gets a wide slot, so only a weapon is wide.
static func size_class(item: ItemDefinition) -> String:
	if item.kind == ItemDefinition.Kind.WEAPON:
		return "wide"
	return "square"


## The model an item's icon is drawn from, or null if it has none.
static func model_for(item: ItemDefinition) -> PackedScene:
	if MODEL_OVERRIDES.has(item.id) and ResourceLoader.exists(MODEL_OVERRIDES[item.id]):
		return load(MODEL_OVERRIDES[item.id]) as PackedScene
	# A drawing wins over a scene with nothing modelled in it (the squad's
	# repair kit is a bare Node3D).
	if DRAWINGS.has(item.id):
		return null
	for scene in [item.ai_scene, item.player_scene]:
		if scene == null:
			continue
		var found := model_in(scene)
		if found != null:
			return found
	return null


## The first imported model instanced anywhere inside `scene`: the rifle in an
## AI weapon, not the muzzle flash parented under it. Follows instanced scenes
## down; an inherited scene shows up as its root's instance.
static func model_in(scene: PackedScene) -> PackedScene:
	if scene == null:
		return null
	if MODEL_EXTENSIONS.has(scene.resource_path.get_extension().to_lower()):
		return scene
	return _model_in_state(scene.get_state())


static func _model_in_state(state: SceneState) -> PackedScene:
	if state == null:
		return null
	for i in state.get_node_count():
		var inst := state.get_node_instance(i)
		if inst == null:
			continue
		if MODEL_EXTENSIONS.has(inst.resource_path.get_extension().to_lower()):
			return inst
		var deeper := _model_in_state(inst.get_state())
		if deeper != null:
			return deeper
	return null
