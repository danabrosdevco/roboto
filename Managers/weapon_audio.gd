class_name WeaponAudio

# ─────────────────────────────────────────────
# WHICH DISTANCE BAND A SHOT BELONGS TO, decided the moment it is fired.
#
# THE PROBLEM. Inverse-distance attenuation costs 6dB per doubling, so a rifle
# at 5m and the same rifle at 400m are about 38dB apart. Turn it down enough to
# be comfortable in your ear and the far one is gone; turn it up enough to hear
# the far one and the near one is deafening. Measured before any of this was
# written (tools/audit_audio.gd): the Ancient Machine Gun reached -40dB at
# 400m, which is silence in a firefight.
#
# WHAT THIS DOES. Near and mid keep Godot's own attenuation and differ only in
# how much top end the bus leaves on them. Past FAR_START the sound stops
# obeying inverse-distance at all: attenuation is switched off and the level is
# computed here, falling FAR_SLOPE_DB per doubling instead of 6. A shot at
# 200m and one at 800m are then four decibels apart rather than twelve, so
# distant fire stays present without ever getting loud.
#
# It is still the same recording. The far bus low-passes it to a thump, which
# is what a few hundred metres of air does to a rifle anyway — so no second
# set of samples is needed to make this work.
#
# THE AUTHORED VALUES ARE CACHED ON FIRST USE. This mutates unit_size,
# volume_db, attenuation_model and max_distance on a player that is reused for
# every shot, so the numbers the scene was authored with have to survive being
# overwritten by the previous shot's band.
# ─────────────────────────────────────────────

## NOTHING STARTS FALLING OFF CLOSER THAN THIS.
##
## unit_size is the range at which a sound still plays at its authored volume;
## past it, inverse-distance takes 6dB per doubling. It was authored per scene
## with no rule and ran from 10 to 46, so the Ancient MG (17) was down 22dB at
## 50m while the AI bolt rifle (46) was only down 3 — one gun died at the end of
## the street and the next carried across the valley.
##
## Raising the FLOOR costs nothing up close, which is the point: near the
## listener the gain is already pinned by max_db, so this only bites in the
## middle distance where the cap is not binding. It buys carry without making
## anything louder in your ear.
const MIN_UNIT_SIZE := 32.0

## Under this, the crack as authored.
const NEAR_END := 40.0
## Past this, the level is computed here rather than by the distance law.
const FAR_START := 150.0
## What a doubling costs beyond FAR_START, against inverse-distance's 6dB.
const FAR_SLOPE_DB := 2.0
## Never let a distant shot climb above this, whatever the authored volume.
const FAR_CEILING_DB := -8.0

# A NOTE ON max_polyphony, WHICH THIS DELIBERATELY DOES NOT TOUCH.
#
# AudioStreamPlayer3D.max_polyphony defaults to ONE, so a gun firing faster than
# its own sample is long cuts each report off to start the next. Measured:
#
#   Autocannon    1.07s sample at pitch 0.72 = 1.49s of audio, every 0.50s
#   Heavy MG      1.99s sample, every 0.12s
#   Machine Gun   1.99s sample, every 0.13s
#
# So the cannon was heard for a third of its length and the MGs for six per cent
# of theirs. It is only a PROBLEM on the cannon: at the MGs' cadence the cut is
# what makes a burst read as a burst, and letting seventeen two-second tails
# stack would be mud. The machine guns are right as they are, so the fix is one
# number on ai-wep_autocannon.tscn rather than a rule applied from here — a floor
# in stage() would have quietly re-voiced every weapon in the game.


## Point a shot's player at the right bus and level for where the listener is
## standing. Call it immediately before play().
static func stage(player: AudioStreamPlayer3D) -> void:
	if player == null or not player.is_inside_tree():
		return
	if not player.has_meta(&"wa_unit"):
		player.set_meta(&"wa_unit", player.unit_size)
		player.set_meta(&"wa_db", player.volume_db)
		player.set_meta(&"wa_max_distance", player.max_distance)
	var unit: float = maxf(float(player.get_meta(&"wa_unit")), MIN_UNIT_SIZE)
	var db: float = player.get_meta(&"wa_db")

	var distance := _to_listener(player)
	if distance < 0.0:
		# No camera yet — a lab run, or the frame the level loads on. Leave the
		# authored values alone rather than guess at a band.
		return

	if distance <= FAR_START:
		player.bus = AudioBuses.WEAPONS if distance <= NEAR_END else AudioBuses.WEAPONS_MID
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.unit_size = unit
		player.volume_db = db
		player.max_distance = float(player.get_meta(&"wa_max_distance"))
		return

	# FAR. Godot's attenuation is switched off and the level is ours: continuing
	# the distance law out here is exactly what made distant fire inaudible.
	#
	# max_distance goes with it. The mortar authored 250m and the launcher 200m,
	# which silenced the two things the player most needs to hear coming.
	player.bus = AudioBuses.WEAPONS_FAR
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_distance = 0.0
	player.volume_db = minf(FAR_CEILING_DB, far_db(unit, db, distance))


## The level a shot plays at beyond FAR_START. Continuous with the near curve
## at the boundary — a sound must not jump as the player walks across it.
static func far_db(unit_size: float, volume_db: float, distance: float) -> float:
	var at_boundary := volume_db + linear_to_db(unit_size / FAR_START)
	var doublings := log(maxf(distance, FAR_START) / FAR_START) / log(2.0)
	return at_boundary - FAR_SLOPE_DB * doublings


## Metres from the sound to whoever is listening, or -1 when nobody is.
static func _to_listener(player: Node3D) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return -1.0
	var cam := tree.root.get_camera_3d()
	if cam == null:
		return -1.0
	return cam.global_position.distance_to(player.global_position)
