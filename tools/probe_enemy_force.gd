extends SceneTree

# ─────────────────────────────────────────────
# EVERY ENEMY SQUAD IN THE PROJECT, BODY BY BODY.
#
# WHAT IT ANSWERS: "what does this spec actually put on the map." Not how many
# — WHICH FRAMES, in order. measure_resistance.gd sums supply and spawn_check.gd
# counts landed bodies; neither prints the identities, so neither can tell a
# squad of four shotgunners from a squad of four riflemen.
#
# WHY IT EXISTS: H9 migrated the legacy `count` + `chassis` one-type form over
# to `roster`, and the only honest proof of that migration is the body list
# before and after being the same list. A count that matches is not enough: the
# legacy form named a PackedScene and roster names a ChassisDefinition, so it is
# entirely possible to keep the number and change every robot in it.
#
# IT READS BOTH FORMS, DEFENSIVELY. `"count" in spec` rather than `spec.count`,
# so the same probe runs on the build before the fields were removed and the
# build after. That is the whole point — a probe that only compiles against one
# side of the change cannot compare the two sides.
#
# IT ALSO WALKS THE APPENDIX AND THE LOOSE SPECS. The live campaign is
# world.tscn's `missions` array, but `Campaign/missions/appendix/` and
# `Campaign/squad_specs/` hold authored content too, and every legacy-form spec
# in the project was in exactly those places.
#
# This is a probe, not a suite: it REPORTS. Diff two runs of it.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_enemy_force.gd -- --no-save
#
# REPORTS: prints every spec's resolved body list; asserts nothing by design
# ─────────────────────────────────────────────

const MISSION_DIRS := [
	"res://Campaign/missions/",
	"res://Campaign/missions/appendix/",
]
const SPEC_DIR := "res://Campaign/squad_specs/"

# What world.tscn's EnemyForceSpawner has in `default_chassis`. The legacy form
# fell back to it when `chassis` was null, so a faithful before/after comparison
# has to resolve the same fallback the spawner did. Scene values beat script
# defaults, so this is read off the scene rather than guessed.
const DEFAULT_CHASSIS := "res://Character/characters/ai/soldier_shotgun.tscn"

const POSTURES := ["PATROL", "GARRISON", "ADVANCE", "RESERVE"]


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var total_specs := 0
	var total_bodies := 0
	var legacy_specs := 0

	for dir_path in MISSION_DIRS:
		var d := DirAccess.open(dir_path)
		if d == null:
			printerr("probe_enemy_force: cannot read %s" % dir_path)
			continue
		var names := d.get_files()
		names.sort()
		for f in names:
			if not f.ends_with(".tres"):
				continue
			var m = load(dir_path + f)
			if m == null:
				push_warning("probe_enemy_force: %s did not load." % f)
				continue
			if not ("enemy_force" in m):
				continue
			print("")
			print("== %s%s   id=%s" % [dir_path, f, m.id])
			for spec in m.enemy_force:
				if spec == null:
					print("   (null spec)")
					continue
				var line := _describe(spec)
				print("   %s" % line["text"])
				total_specs += 1
				total_bodies += int(line["bodies"])
				if bool(line["legacy"]):
					legacy_specs += 1

	# The loose specs. Two of them are ext_resources of the appendix valley
	# missions, so they are reported twice on purpose — once as a file and once
	# inside each mission that uses them, which is how you see the sharing.
	var sd := DirAccess.open(SPEC_DIR)
	if sd != null:
		var snames := sd.get_files()
		snames.sort()
		for f in snames:
			if not f.ends_with(".tres"):
				continue
			var s = load(SPEC_DIR + f)
			if s == null:
				push_warning("probe_enemy_force: %s did not load." % f)
				continue
			print("")
			print("== %s%s   (loose spec)" % [SPEC_DIR, f])
			var line := _describe(s)
			print("   %s" % line["text"])
			if bool(line["legacy"]):
				legacy_specs += 1

	print("")
	print("%s" % "-".repeat(78))
	print("specs in missions: %d    bodies on those specs: %d    legacy-form: %d"
			% [total_specs, total_bodies, legacy_specs])
	print("%s" % "-".repeat(78))
	print("")
	quit(0)


## One spec, as a line that is stable enough to diff.
##
## The body list is SCENE PATHS, not chassis ids: the scene is what gets
## instantiated, and it is the only thing the two authoring forms have in
## common — the legacy form never named a ChassisDefinition at all.
func _describe(spec) -> Dictionary:
	var bodies := _bodies_of(spec)
	var scenes: Array[String] = []
	for frame in bodies:
		if frame == null:
			scenes.append("<null frame>")
		elif frame is PackedScene:
			scenes.append(_leaf(frame.resource_path))
		elif frame.scene == null:
			scenes.append("<%s: no scene>" % _leaf(frame.resource_path))
		else:
			scenes.append(_leaf(frame.scene.resource_path))
	scenes.sort()   # order is not authored meaning; the multiset is

	var legacy: bool = spec.roster.is_empty()
	var posture: int = int(spec.posture)
	return {
		"text": "%-14s %-9s n=%-3d %s%s" % [
			spec.callsign,
			POSTURES[posture] if posture >= 0 and posture < POSTURES.size() else str(posture),
			bodies.size(),
			", ".join(scenes),
			"   [LEGACY FORM]" if legacy else "",
		],
		"bodies": bodies.size(),
		"legacy": legacy,
	}


## The same resolution EnemyForceSpawner._bodies_of() does, in both forms.
##
## Returns ChassisDefinitions for a roster spec and PackedScenes for a legacy
## one, because that is literally what each form holds — _describe reduces both
## to a scene path so the two are comparable.
func _bodies_of(spec) -> Array:
	var out: Array = []
	if not spec.roster.is_empty():
		for frame in spec.roster:
			if frame != null:
				out.append(frame)
		return out

	# Legacy one-type form. Guarded with `in` rather than read directly so this
	# probe still compiles and runs once the fields are gone.
	if not ("count" in spec):
		# Not legacy at all — an empty roster on a build with no legacy fields
		# left. An authoring mistake, and the thing H9's removal would expose.
		push_warning("probe_enemy_force: '%s' has an empty roster and no legacy fields: it describes no bodies." % spec.callsign)
		return out
	var n := int(spec.get("count"))
	var scene = spec.get("chassis") if "chassis" in spec else null
	if scene == null:
		scene = load(DEFAULT_CHASSIS)
	for _i in n:
		out.append(scene)
	return out


func _leaf(path: String) -> String:
	return path.get_file() if path != "" else "<unsaved>"
