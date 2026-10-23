extends RefCounted
class_name Cosmetics

# ─────────────────────────────────────────────
# COSMETICS — which hats a frame can wear, and where to find them.
#
# One table, read by four things that must not disagree:
#   Character/components/rank_kit.gd   puts the hat on the robot
#   Character/hud/squad/squad_page.gd  lets you pick it
#   Character/hud/icons/icons.gd       finds the card icon for the choice
#   tools/bake_icons.gd                bakes one icon per choice
#
# The scenes are MESHES, not CSG — tools/bake_hats.gd writes them from the CSG
# in tools/mockup_parts.gd. See the note at the top of rank_kit.gd for why that
# matters (a reserve wave of 40 robots cost 335.8 ms rebuilding CSG).
#
# COSMETICS ARE COSMETIC. Nothing here touches stats, kills or loadout, and
# nothing reads this table to make a gameplay decision. The only thing a hat
# changes is what you see.
# ─────────────────────────────────────────────

const DIR := "res://Character/characters/ai/hats"

## No hat. The id a record carries until someone picks something.
const NONE := &""

## Every soldier-type frame is the same capsule underneath, so they share kit.
const SOLDIER_FRAMES: Array[StringName] = [
	&"soldier", &"rifleman", &"rifleman_armoured", &"marksman", &"shotgunner",
]
const ROVER_FRAMES: Array[StringName] = [&"rover", &"rover_gl"]
const WALKER_FRAMES: Array[StringName] = [&"walker"]
const RECLAIMER_FRAMES: Array[StringName] = [&"reclaimer"]

## id -> { name, file, frames }. `file` is the basename under DIR.
## `rank` is the lowest SoldierRecord.rank that may wear it, and it doubles as
## the ORDER: a promotion takes the highest-ranked thing the frame can now wear.
## Ranks run 0-5 — Recruit, Regular, Veteran, Sergeant, Lieutenant, Captain.
##
## EVERY VEHICLE HAS SOMETHING AT RANK 0, because these frames wore a hat from
## the scene before records had a say and taking it away made them look broken.
## The soldier starts bare: pauldrons and a cap are earned, and a Recruit has
## not earned them.
const ENTRIES := {
	&"soldier_brodie": {"name": "BRODIE", "file": "soldier_brodie", "frames": SOLDIER_FRAMES, "rank": 2},
	&"soldier_pickelhaube": {"name": "PICKELHAUBE", "file": "soldier_pickelhaube", "frames": SOLDIER_FRAMES, "rank": 3},
	&"soldier_cap": {"name": "PEAKED CAP", "file": "soldier_cap", "frames": SOLDIER_FRAMES, "rank": 1},
	&"rover_beret": {"name": "BERET", "file": "rover_beret", "frames": ROVER_FRAMES, "rank": 1},
	&"rover_slouch": {"name": "SLOUCH HAT", "file": "rover_slouch", "frames": ROVER_FRAMES, "rank": 4},
	&"walker_tarleton": {"name": "TARLETON", "file": "walker_tarleton", "frames": WALKER_FRAMES, "rank": 3},
	&"walker_peaked_cap": {"name": "PEAKED CAP", "file": "walker_peaked_cap", "frames": WALKER_FRAMES, "rank": 1},
	&"walker_bearskin": {"name": "BEARSKIN", "file": "walker_bearskin", "frames": WALKER_FRAMES, "rank": 5},
	&"reclaimer_hardhat": {"name": "HARD HAT", "file": "reclaimer_hardhat", "frames": RECLAIMER_FRAMES, "rank": 3},
	&"reclaimer_flatcap": {"name": "FLAT CAP", "file": "reclaimer_flatcap", "frames": RECLAIMER_FRAMES, "rank": 1},
}


## The lowest rank that may wear it. NONE is free to everybody.
static func rank_for(id: StringName) -> int:
	if id == NONE or not ENTRIES.has(id):
		return 0
	return int(ENTRIES[id].get("rank", 0))


## The best thing this frame can wear at this rank — "best" meaning the one with
## the highest rank requirement it has earned. What a promotion jumps to.
static func best_for(chassis_id: StringName, rank: int) -> StringName:
	var best := NONE
	var best_rank := -1
	for id: StringName in ENTRIES:
		if not (ENTRIES[id]["frames"] as Array).has(chassis_id):
			continue
		var need := rank_for(id)
		if need <= rank and need > best_rank:
			best = id
			best_rank = need
	return best


## Everything this frame can wear, NONE first, in table order.
##
## NONE is always offered and always first, so a frame with no kit at all still
## gets a working cycle control rather than an empty one.
static func for_frame(chassis_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = [NONE]
	for id: StringName in ENTRIES:
		var frames: Array = ENTRIES[id]["frames"]
		if frames.has(chassis_id):
			out.append(id)
	return out


## The next one round the ring, so a single button can cycle. Wraps.
static func next_for_frame(chassis_id: StringName, current: StringName) -> StringName:
	var all := for_frame(chassis_id)
	var i := all.find(current)
	if i < 0:
		return NONE
	return all[(i + 1) % all.size()]


static func display_name(id: StringName) -> String:
	if id == NONE or not ENTRIES.has(id):
		return "NONE"
	return str(ENTRIES[id]["name"])


## True when this frame can actually wear this id. A record keeps its hat when
## it is benched and re-fitted, but NOT when it is rebuilt on another chassis —
## a beret has nowhere to sit on a walker.
static func fits(chassis_id: StringName, id: StringName) -> bool:
	if id == NONE:
		return true
	if not ENTRIES.has(id):
		return false
	return (ENTRIES[id]["frames"] as Array).has(chassis_id)


static func scene_path(id: StringName) -> String:
	if id == NONE or not ENTRIES.has(id):
		return ""
	return "%s/hat_%s.tscn" % [DIR, ENTRIES[id]["file"]]


## The hat scene, or null. A cosmetic that has not been baked comes back null
## and the robot simply wears nothing — the same contract Icons uses, where a
## missing picture is never an error, just an absence.
static func scene(id: StringName) -> PackedScene:
	var p := scene_path(id)
	if p == "" or not ResourceLoader.exists(p):
		return null
	return load(p) as PackedScene


## What gets appended to a chassis icon's name for this choice. Empty for NONE,
## so an un-hatted frame keeps using the icon that is already baked and nothing
## has to be re-baked to keep working.
static func icon_suffix(id: StringName) -> String:
	if id == NONE or not ENTRIES.has(id):
		return ""
	return "__" + str(ENTRIES[id]["file"])


# ─────────────────────────────────────────────
# SURFACES — the faction colour, on the hat's OWN texture
# ─────────────────────────────────────────────
# FactionLivery hands a whole robot ONE material, which is what keeps four
# materials covering the game and is exactly right for a hull: every panel of it
# is the same steel. It is wrong for headgear. A beret painted with the hull's
# albedo is a beret made of concrete.
#
# So each surface gets its own faction_metal material — same shader, same
# faction colour, different albedo — and the baked hats carry a `surface` meta
# per piece saying which. Four factions times five surfaces is twenty materials
# in the worst case, and only for frames that actually wear something.
#
# TWO OF THESE TEXTURES DO NOT EXIST YET. beret_wool and bearskin_fur are
# briefed in docs/briefs/ and unbuilt; until they land those surfaces fall back
# to a flat tone, which still takes the faction colour correctly — it is the
# detail that is missing, not the paint.

const SHADER := "res://Character/faction_metal.gdshader"

## surface meta -> [texture path, metallic, roughness, tint]
##
## THE TINT IS NOT DECORATION, it is the fallback. With no albedo_tex the shader
## samples white, and the first render came back with a blazing white turban —
## so each surface names the tone it should hold until its texture exists.
##
## Those tones are chosen against the shader paint band (centre 0.45, width
## 0.425, so 0.24 to 0.66 takes the faction colour), to match what each brief
## asks for: wool lands INSIDE it, because a beret is regimental identity and
## should read cyan or amber across a valley; fur sits well BELOW it, because a
## cyan bearskin is a novelty hat and that silhouette carries on its own.
const SURFACES := {
	"wool": ["res://textures/PSX_Textures/beret_wool.png", 0.0, 0.95, Color(0.44, 0.46, 0.43)],
	"fur": ["res://textures/PSX_Textures/bearskin_fur.png", 0.0, 1.0, Color(0.13, 0.13, 0.14)],
	"plate": ["res://textures/PSX_Textures/pauldron_plate.png", 0.70, 0.45, Color(1, 1, 1)],
	"lame": ["res://textures/PSX_Textures/pauldron_lame.png", 0.70, 0.45, Color(1, 1, 1)],
	"hivis": ["", 0.05, 0.62, Color(0.62, 0.30, 0.03)],
}

static var _bases: Dictionary = {}


## The base material for a surface, or null to fall back to the frame's own.
##
## Cached on the class, so every robot in the game shares one base per surface
## and FactionLivery's own cache then shares one PAINTED material per faction
## from it. Nothing here is per-robot.
static func surface_base(surface: String) -> ShaderMaterial:
	if surface == "" or not SURFACES.has(surface):
		return null
	if _bases.has(surface):
		return _bases[surface]
	var shader := load(SHADER) as Shader
	if shader == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = shader
	var spec: Array = SURFACES[surface]
	var tex_path: String = spec[0]
	if tex_path != "" and ResourceLoader.exists(tex_path):
		m.set_shader_parameter("albedo_tex", load(tex_path))
	m.set_shader_parameter("metallic", float(spec[1]))
	m.set_shader_parameter("roughness", float(spec[2]))
	# Derived from the albedo, as every other faction material in the game does
	# it — there are no hand-painted masks for headgear and a flat white mask
	# would repaint the rolled edges and rivets the brief deliberately holds out.
	m.set_shader_parameter("derive_mask_from_albedo", true)
	m.set_shader_parameter("use_normal_map", false)
	m.set_shader_parameter("base_tint", spec[3] as Color)
	_bases[surface] = m
	return m


## PAULDRONS, which are not a hat.
##
## They sit beside headgear rather than competing with it: a Captain wears both,
## and the squad screen gives them their own tick. FULL DRESS — the hat and the
## pauldrons baked into one cosmetic — is gone, because it was a third entry
## saying what two independent things already say.
const PAULDRONS_RANK := 5
const PAULDRONS_FILE := "soldier_pads"


## Only the soldier frames have shoulders to hang them on.
static func pauldrons_fit(chassis_id: StringName) -> bool:
	return SOLDIER_FRAMES.has(chassis_id)


static func pauldrons_scene() -> PackedScene:
	var p := "%s/hat_%s.tscn" % [DIR, PAULDRONS_FILE]
	if not ResourceLoader.exists(p):
		return null
	return load(p) as PackedScene


## What a frame wears when nobody has chosen for it: the best it has EARNED.
##
## This used to be a fixed table, because every vehicle had something at rank 0
## and a bare frame looked broken. Nothing is free any more — the first unlock
## on every frame is rank 1 — so the default is simply the rank-aware answer and
## a Recruit goes out bare, which is the point of a rank mark.
static func default_for(chassis_id: StringName, rank: int = 0) -> StringName:
	return best_for(chassis_id, rank)
