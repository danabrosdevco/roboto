extends HUDWeapon
class_name PlayerClusterLauncher

# ─────────────────────────────────────────────
# CLUSTER LAUNCHER, in the player's hands.
#
# Extends HUDWeapon rather than PlayerEquipment, because it is a WEAPON: a
# six-round drum with a magazine, a reload, iron sights and recoil, all of
# which the template already does. The rocket is equipment — two shots, a
# decision, then it goes away. This is something you carry and work with.
#
# Only _fire_shot() is overridden. The template's comment above it says exactly
# what that means: the cooldown, the empty click and the ammo decrement happen
# in PlayerWeapon.try_fire(), and this is only what leaves the barrel. So the
# shell replaces the hitscan and nothing else changes.
#
# IT ARCS, AND THAT IS THE WEAPON. The shell leaves at launch_speed along the
# camera and falls the whole way, so at any useful distance you are holding
# over. The ladder on the rear sight exists to say so before the player has
# fired it. A flat-shooting version of this would just be a worse rifle; the
# arc is what lets it reach behind cover, and what makes a miss land somewhere
# rather than nowhere.
# ─────────────────────────────────────────────

## The carrier round. Without it the gun clicks, kicks and produces nothing, so
## it says so rather than failing quietly.
@export var shell_scene: PackedScene
## Muzzle velocity, and the number the SIGHT IS CUT FOR. The ladder's detents
## are solved from this and gravity — change it and every range mark on the
## rear leaf becomes a lie. cluster_launcher_model.tscn carries the table.
@export var launch_speed: float = 55.0
## Kept at zero. Elevation comes from the GUN being pitched nose-up by the ADS
## pose, which is how a real launcher does it; a separate upward nudge here
## would add angle the sight knows nothing about and break the 25m zero.
@export var launch_lift: float = 0.0
## How far in front of the eye the shell appears. Far enough to clear the
## player's own collider — a round spawned inside it is shoved sideways by the
## physics server before it has any velocity of its own.
@export var spawn_forward: float = 0.9
@export var spawn_drop: float = 0.12
## What the playtest log files the shell AND its bomblets under. Without it the
## bomblets score as Frag, because the round they are built from is the hand
## grenade's — the same trap ai_weapon_grenade_launcher.gd documents.
@export var analytics_label: String = "Cluster Launcher"


func _fire_shot() -> void:
	# The kick is the template's, not a copy of it: see HUDWeapon.arm_recoil().
	arm_recoil()

	if cam == null or tracer_origin == null:
		push_warning("PlayerClusterLauncher '%s' has no camera or muzzle — the trigger works and nothing is launched." % name)
		return
	if shell_scene == null:
		push_warning("PlayerClusterLauncher '%s' has no shell_scene — it fires, kicks, makes noise, and nothing comes out." % name)
		return

	# ALONG THE BORE, NOT THE CAMERA. This is the whole reason the sight works:
	# the ADS pose pitches the gun nose-up by 3.99 degrees, which is the
	# elevation that puts a 42 m/s shell on the ground at 25m — the range the
	# rear leaf's bottom detent is cut for. Launching down the camera's forward
	# instead would throw the round flat and make every mark on that ladder
	# decorative. Same axis the hitscan weapons trace down, for the same reason
	# (hud_weapon_template.gd's _fire_shot).
	var bore := tracer_origin.global_transform.basis.x.normalized()
	var origin := cam.global_position + bore * spawn_forward + Vector3.DOWN * spawn_drop

	var shell := shell_scene.instantiate()
	# setup() BEFORE the tree. The blast reads its owner on the frame it is
	# added, so a shell that entered first credited its kills to nobody and
	# skipped the friendly-fire multiplier — the bug ai_grenade_projectile.gd
	# already carries a comment about.
	if shell.has_method("setup"):
		shell.setup(player)
	if "analytics_label" in shell:
		shell.analytics_label = analytics_label
	level_node().add_child(shell)
	shell.global_position = origin

	if shell is RigidBody3D:
		var body := shell as RigidBody3D
		# The arc is meant to be predictable, so the round carries no drag —
		# the project default would pull it short of wherever the player
		# learned to hold, and a launcher you cannot learn is a random number.
		body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		body.linear_damp = 0.0
		body.linear_velocity = bore * launch_speed + Vector3.UP * launch_lift
		body.angular_velocity = Vector3(
			randf_range(-5.0, 5.0), randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
		# A round must never collide with whoever fired it. It spawns less than
		# a metre from the player's own collider and at this speed one bad
		# physics tick puts it inside.
		if player is PhysicsBody3D:
			body.add_collision_exception_with(player)

	if rifle_stream_player != null:
		_WeaponAudio.stage(rifle_stream_player)
		rifle_stream_player.play()
	if muzzle_flash != null:
		muzzle_flash.play_flash()
	# You are still giving away where you are, same as any other weapon.
	if player != null and player.has_method("emit_noise"):
		player.emit_noise(StimulusManager.StimulusType.GUNSHOT_HEARD, noise_radius)
	request_status.emit()
