extends SceneTree

# ─────────────────────────────────────────────
# MOTION SHOTS — camera MOVES, not stills, rendered to a numbered PNG sequence.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_shots_motion.gd
#
# Why this exists: tools/probe_shots_*.gd already hold ~107 hand-tuned camera
# positions across eight levels. Every one of them is a composition somebody
# already judged worth keeping. A move between two of them is footage, and it
# costs nothing to author — which is far cheaper than hunting for a good angle
# by flying around.
#
# TWO DIFFERENCES FROM probe_shots_*, and they are the point:
#
#   1. It renders into a SubViewport at an EXACT size, not the game window.
#      The existing scripts call root.get_texture(), which returns the window,
#      which is why everything came back 1152x648 — below Steam's 1920x1080
#      minimum and soft on itch. Size here is fixed and independent of the
#      desktop.
#   2. It interpolates between two camera states over N frames instead of
#      jumping, and writes 0001.png, 0002.png ... which CapCut and DaVinci
#      Resolve both import directly as an image sequence. No ffmpeg needed —
#      it is not on this machine.
#
# NOT headless: the dummy renderer returns blank images. Same as the other
# shot scripts. It opens a window and uses the GPU, so the machine is busy.
#
# The renderer needs warming up or the first frames come back blank, so there
# is a warm-up pass before anything is written. The existing scripts solve this
# by rendering every shot twice; a sequence cannot afford that, so it warms up
# once instead.
# ─────────────────────────────────────────────

const LEVEL := "res://maps/mutaha_wip_level.tscn"
const EYE := 1.7

## Output size. 1920x1080 is Steam's floor; 2560x1440 if the card is bored.
const SIZE := Vector2i(1920, 1080)
## Frames rendered per move. 90 at 30fps is three seconds.
const FRAMES := 90
## Frames to let the renderer settle on each step. 2 is usually enough once
## warm; raise it if the sequence flickers.
const SETTLE := 2

# name, from_pos, from_look, to_pos, to_look, fov
# Positions lifted from tools/probe_shots_mutaha_wip.gd, which already judged
# them worth keeping. The move is the only new authoring.
const MOVES: Array = [
	# Down the quarter's street, the way a squad would walk it. This is the
	# shot the wordless trailer opens on.
	["quarter_street_walk",
		Vector3(-208.5, EYE, 236.0), Vector3(-208.5, 1.4, 60.0),
		Vector3(-208.5, EYE, 150.0), Vector3(-208.5, 1.4, 20.0), 70.0],

	# Slow push onto the plaza and the obelisk.
	["plaza_push",
		Vector3(-44.5, EYE, 44.0), Vector3(-44.0, 9.0, -22.0),
		Vector3(-44.5, EYE, 2.0), Vector3(-44.0, 9.0, -22.0), 72.0],

	# Descending onto the island tip: wide establishing, loses altitude.
	["island_tip_descend",
		Vector3(-46.0, 118.0, 300.0), Vector3(-56.0, 0.0, 180.0),
		Vector3(-46.0, 44.0, 236.0), Vector3(-56.0, 2.0, 180.0), 62.0],
]


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)

	# Render target, sized explicitly. Everything the camera sees has to live
	# inside it, so the level goes in here rather than under root.
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	root.add_child(vp)

	var level: Node3D = (load(LEVEL) as PackedScene).instantiate()
	vp.add_child(level)

	var cam := Camera3D.new()
	cam.far = 1600.0
	vp.add_child(cam)
	cam.make_current()

	# Physics frames first so terrain, props and any spawners settle, then
	# render frames so the GPU has actually drawn something. Skipping this
	# gives a black first clip, which is easy to miss until the edit.
	for _i in 30:
		await physics_frame
	cam.position = MOVES[0][1]
	cam.look_at(MOVES[0][2], Vector3.UP)
	for _i in 20:
		await process_frame

	var total := 0
	for m: Array in MOVES:
		var name_: String = m[0]
		var dir := out.path_join(name_)
		DirAccess.make_dir_recursive_absolute(dir)
		cam.fov = float(m[5])

		for f in FRAMES:
			# smoothstep rather than linear: a camera that eases in and out
			# reads as a decision, a linear one reads as a machine.
			var t := float(f) / float(max(FRAMES - 1, 1))
			var e := t * t * (3.0 - 2.0 * t)
			cam.position = (m[1] as Vector3).lerp(m[3] as Vector3, e)
			cam.look_at((m[2] as Vector3).lerp(m[4] as Vector3, e), Vector3.UP)
			for _i in SETTLE:
				await process_frame
			var img := vp.get_texture().get_image()
			img.save_png(dir.path_join("%04d.png" % (f + 1)))
			total += 1

		print("   %s  %d frames" % [name_, FRAMES])

	print("   wrote %d frames (%s) to %s" % [total, SIZE, out])
	print("   import as an image sequence at 30fps in CapCut or Resolve")
	quit()
