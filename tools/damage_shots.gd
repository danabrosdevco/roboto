extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH THE PLAYER TAKING DAMAGE.
#
#   godot --audio-driver Dummy --path . --script res://tools/damage_shots.gd -- <out dir> --no-save
#
# Stands up a real level and a real HUD, hits the player from eight bearings and
# at four states of health, and writes a PNG of each. The point is the same as
# tools/mockup_shots.gd: you cannot play this from here, but you can photograph
# it, and every damage effect so far has looked different photographed than it
# did reasoned about.
#
# IT NEEDS A WINDOW. signal_filter samples the screen texture, so there is
# nothing to sample headless — run it WITHOUT --headless.
#
# NOT THE REAL PLAYER'S SAVE. Nothing here touches campaign.json; the level is
# loaded on its own and the player is whatever the scene provides.
# ─────────────────────────────────────────────

## The real scene, which already wires player, HUD, managers and the base.
const WORLD := "res://Env/world.tscn"

## Bearings to be shot from, in degrees clockwise from dead ahead.
const BEARINGS := [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]

## Signal integrity levels to photograph the feed at.
##
## The game's own band edges plus a point inside each band, so every row of the
## contact sheet is a threshold the rest of the game already agrees is
## meaningful rather than a number picked to look like a ramp:
##   1.00 CLEAN  0.75 FUZZED edge  0.50 DEGRADED edge  0.25 CRITICAL edge
const STATES := [1.0, 0.85, 0.75, 0.6, 0.5, 0.35, 0.25, 0.1, 0.0]

var _player: Node3D = null
var _hud: Control = null
var _out: String = "."


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("damage_shots: signal_filter samples the screen, so this needs a window. Run it without --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 and args[0].strip_edges() != "" else "."
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

	# THE WHOLE WORLD, not a player and a HUD side by side.
	#
	# The first version instantiated the level, the player and the HUD
	# separately and wired them by hand. It got three errors in a row —
	# camera_switcher missing, the HUD is a Control and not a CanvasLayer, and
	# current_level on a null world — because test_character is built to live
	# inside world.tscn and reaches back into it for several things. Loading the
	# scene that already wires all of that is both less code and closer to what
	# the question was: show me the game.
	# The figures under the blue strip. Without them these are pictures of a
	# feeling; with them each one is a picture AT a number, which is the only
	# way to say "it starts to hurt at 0.4" and be believed.
	Settings.set_value("debug.signal_readout", true)
	if not Settings.debug_tools_enabled():
		printerr("damage_shots: debug tools are off, so the signal figures will not be drawn.")

	var world: Node = load(WORLD).instantiate()
	root.add_child(world)
	for _i in 40:
		await process_frame
	_player = world.get("player")
	_hud = world.get_node_or_null("HUD")
	if _player == null or _hud == null:
		printerr("damage_shots: world gave no player (%s) or HUD (%s)." % [_player, _hud])
		quit(1)
		return

	await _shoot("00_clean")
	await _bearings()
	await _states()

	print("damage_shots: written to %s" % ProjectSettings.globalize_path(_out))
	quit(0)


## One arc per compass point, each on its own frame so they do not stack.
func _bearings() -> void:
	for deg: float in BEARINGS:
		_clear_arcs()
		# PRIME FIRST, THEN HIT. Shooting the other way round photographed a
		# half-faded arc whenever a frame stalled — the 0° shot landed on a
		# 1 FPS frame and the arc had spent most of its 1.5 s life before the
		# capture. The arcs fade on wall time, so the slow frames have to be
		# spent BEFORE the hit is registered, not after.
		await _prime()
		_hit_from(deg, 18.0)
		await _capture("arc_%03d" % int(deg))
	# And what three at once looks like, which is the real case in a firefight
	# and the one that tells you whether the ring is readable or soup.
	_clear_arcs()
	await _prime()
	_hit_from(20.0, 18.0)
	_hit_from(150.0, 30.0)
	_hit_from(285.0, 8.0)
	await _capture("arc_three_at_once")


## The feed at each signal level, with no hit pulse on top.
##
## Signal is SET rather than suppressed into place. Walking it down with real
## near-misses would be the honest simulation, but it is also a race against
## the 0.08/s recovery and lands on a different value every run — and the whole
## point of these is to photograph a KNOWN figure.
func _states() -> void:
	_clear_arcs()
	for level: float in STATES:
		_player.signal_integrity = level
		_player._update_ekill_latch()
		# Hold it there. The player ticks its own recovery every physics frame,
		# so without a lock the number has climbed before the shutter opens.
		_player.lock_signal(30.0)
		_hud.set_signal(level)
		# Let the pulse from any earlier hit fall away, so this is the signal
		# on its own rather than the signal plus a fading punch.
		await _settle(1.2)
		_hud.set_signal(level)
		await _shoot("sig_%03d" % int(level * 100.0))
	# THE WORST CASE THE GAME CAN PRODUCE: signal almost gone and taking a
	# burst, which is both the most likely moment to be in and the one where
	# losing the picture costs the most. If anything here is unreadable, it is
	# this one.
	_player.signal_integrity = 0.1
	_player.lock_signal(30.0)
	_hud.set_signal(0.1)
	await _prime()
	_hit_from(200.0, 18.0)
	_hit_from(205.0, 18.0)
	_hit_from(210.0, 18.0)
	await _capture("worst_case")


## A hit from `deg` clockwise of the camera's facing, `amount` damage.
##
## Placed in the world rather than faked, because the indicator computes its own
## bearing from a world position — faking the angle would test the drawing and
## not the maths, and the maths is the part that is easy to get backwards.
func _hit_from(deg: float, amount: float) -> void:
	var cam := root.get_camera_3d()
	if cam == null or _hud == null:
		return
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var dir: Vector3 = fwd.rotated(Vector3.UP, -deg_to_rad(deg))
	var marker := Node3D.new()
	root.add_child(marker)
	marker.global_position = cam.global_position + dir * 12.0
	_hud.register_hit(amount, marker)


func _clear_arcs() -> void:
	var d = _hud.get_node_or_null("DamageDirections") if _hud != null else null
	if d != null and d.has_method("clear_hits"):
		d.clear_hits()


func _settle(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		t += 0.05
		await process_frame


## Spend the slow frames. Anything time-sensitive is set up after this.
func _prime() -> void:
	for _i in 8:
		await process_frame


func _shoot(name: String) -> void:
	await _prime()
	await _capture(name)


func _capture(name: String) -> void:
	# Two frames only: enough for the draw to land, short enough that a fading
	# effect is still close to the strength it was registered at.
	for _i in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var file := "%s/dmg_%s.png" % [_out, name]
	var err := img.save_png(file)
	if err != OK:
		printerr("damage_shots: could not write %s (%s)" % [file, error_string(err)])
	else:
		print("  %s" % file.get_file())
