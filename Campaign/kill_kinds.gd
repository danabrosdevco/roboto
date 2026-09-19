extends RefCounted

# ─────────────────────────────────────────────
# KILL KINDS — what a robot killed, by frame, so the debrief can say
# "2 CHASERS, 1 RIFLE TROOPER" and draw them.
#
# A kind is a frame id. Robots from an EnemyForceSpawner carry theirs as meta
# (`chassis_id`); robots placed in a level by hand carry none, so their scene
# says what they are. Anything unknown falls back to its scene's name, which
# still reads, just without an icon.
# ─────────────────────────────────────────────

## Frame id -> the ChassisDefinition with its name and (baked) icon.
const FRAMES := {
	&"rifleman": "res://Campaign/chassis/chassis_rifleman.tres",
	&"shotgunner": "res://Campaign/chassis/chassis_shotgunner.tres",
	&"soldier": "res://Campaign/chassis/chassis_soldier.tres",
	&"chaser": "res://Campaign/chassis/chassis_chaser.tres",
	&"hopper": "res://Campaign/chassis/chassis_hopper.tres",
	&"gunship": "res://Campaign/chassis/chassis_helicopter.tres",
	&"rover": "res://Campaign/chassis/chassis_rover.tres",
}

## Scene file (no extension) -> frame id, for robots with no frame of record.
const SCENES := {
	"soldier_rifle": &"rifleman",
	"soldier_shotgun": &"shotgunner",
	"enemy_shotgun": &"shotgunner",
	"enemy_chaser": &"chaser",
	"enemy_nest-chaser": &"hopper",
	"enemy_helicopter": &"gunship",
	"vehicle_rover": &"rover",
	"soldier_chassis": &"soldier",
	"boss_guardian": &"guardian",
}


static func kind_of(body: Node) -> StringName:
	if body == null:
		return &"unknown"
	if body.has_meta(&"chassis_id"):
		return StringName(str(body.get_meta(&"chassis_id")))
	var base := body.scene_file_path.get_file().get_basename()
	if base == "":
		return &"unknown"
	return SCENES.get(base, StringName(base))


static func frame_of(kind: StringName) -> ChassisDefinition:
	var path: String = FRAMES.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as ChassisDefinition


## "CHASER", "RIFLE TROOPER" — the frame's name without the word "Chassis".
static func name_of(kind: StringName) -> String:
	var frame := frame_of(kind)
	var words := frame.display_name if frame != null else String(kind).replace("_", " ").replace("-", " ")
	return words.to_upper().trim_suffix(" CHASSIS")


## Adds one tally into another: career totals from a mission's.
static func merge(into: Dictionary, from: Dictionary) -> void:
	for kind in from:
		into[kind] = int(into.get(kind, 0)) + int(from[kind])
