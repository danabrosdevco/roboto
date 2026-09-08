extends Node
class_name PossessionController

# ─────────────────────────────────────────────
# POSSESSION / ASSUME CONTROL
# Child of Player.
#
# THE MODEL
# The camera moves; the body doesn't. Your original chassis stays exactly where
# you left it — solid, gravity-bound and shootable — while the camera reparents
# to the robot you took over. Assuming control costs you something.
#
# The robot keeps its own collider and does its own move_and_slide(); we hand it
# an intent each frame via Soldier.drive().
#
# THE THINGS THAT WOULD OTHERWISE BREAK
#
#  1. Every Enemy culls itself on distance to the player. With the player body
#     parked at the far end of the map, AI around the robot you're driving would
#     all go passive. Player.get_focus_position() returns the possessed body's
#     position instead, and Enemy._physics_process uses that.
#  2. Squad keeps issuing order_move_to and assign_role to its members. A
#     possessed body is excluded from get_orderable_members(), or the squad
#     fights your input for control of the same CharacterBody3D.
#  3. Enemy.die() disables physics and the collider. If that fires while you're
#     inside, you're a camera welded to a corpse. We poll alive and eject.
#  4. Your own body can die while you're away. We poll that too and snap back,
#     so World's death/respawn path isn't running under a hijacked camera.
# ─────────────────────────────────────────────

@export var player: Player
@export var cam: Camera3D
@export var possess_range: float = 60.0
@export var eye_height: float = 1.6        # camera height above the robot's origin
@export var possess_keycode: int = KEY_G

var possessed: Soldier = null
var _home_faction: Enums.Factions
var _cam_home_transform: Transform3D
var _cam_home_parent: Node = null

signal possessed_body(soldier: Soldier)
signal released_body(soldier: Soldier)
signal possession_failed(reason: String)


func is_possessing() -> bool:
	return possessed != null and is_instance_valid(possessed)


# This node extends Node, which has no get_world_3d(). Borrow the player's —
# it's a CharacterBody3D and always lives in the same 3D world we care about.
func _space() -> PhysicsDirectSpaceState3D:
	return player.get_world_3d().direct_space_state


func _ready() -> void:
	if player == null:
		push_warning("PossessionController: player not assigned, disabling.")
		set_physics_process(false)
		return


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var pressed := false
	if InputMap.has_action("possess"):
		pressed = event.is_action_pressed("possess")
	else:
		pressed = event.keycode == possess_keycode
	if not pressed:
		return

	if is_possessing():
		release()
	else:
		var candidate := _find_possession_target()
		if candidate == null:
			possession_failed.emit("NO VALID BODY")
			return
		possess(candidate)


# ─────────────────────────────────────────────
# TARGET SELECTION — friendly robot under the crosshair
# ─────────────────────────────────────────────
func _find_possession_target() -> Soldier:
	if player == null or cam == null:
		return null
	var origin := cam.global_position
	var end := origin + (-cam.global_transform.basis.z * possess_range)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	var hit: Dictionary = _space().intersect_ray(query)
	if hit.is_empty():
		return null
	var c = hit.get("collider")
	if not c is Soldier:
		return null
	var s := c as Soldier
	if not s.alive:
		return null
	if Enums.are_hostile(Enums.Factions.PLAYER, s.faction):
		return null
	# An e-killed body has no working command link. Refusing here is what makes
	# the e-warfare system bite: jam a squad and you can't hop into it either.
	if s.get_signal_state() == Enemy.SignalState.EKILL:
		possession_failed.emit("SIGNAL LOST")
		return null
	return s


# ─────────────────────────────────────────────
# POSSESS
# ─────────────────────────────────────────────
func possess(target: Soldier) -> void:
	if is_possessing() or target == null or not target.alive:
		return

	possessed = target
	_home_faction = player.faction

	target.enter_player_control()

	# The camera travels; the body does not. Your original chassis stays exactly
	# where you left it — still solid, still gravity-bound, still shootable.
	# That's the point of the mechanic: assuming control costs you something.
	_cam_home_parent = cam.get_parent()
	_cam_home_transform = cam.transform
	cam.reparent(target, false)
	cam.transform = Transform3D(Basis(), Vector3(0.0, eye_height, 0.0))

	player.velocity = Vector3.ZERO
	if player.hud_weapon:
		player.hud_weapon.visible = false

	# Adopt the body's facing so the camera doesn't whip on entry.
	player.look_direction.y = target.rotation.y

	possessed_body.emit(target)


# ─────────────────────────────────────────────
# RELEASE
# ─────────────────────────────────────────────
func release() -> void:
	if not is_possessing():
		return
	var body := possessed
	possessed = null

	if is_instance_valid(body):
		body.exit_player_control()

	# Camera goes home to the body you left behind.
	if is_instance_valid(cam):
		if _cam_home_parent != null and is_instance_valid(_cam_home_parent):
			cam.reparent(_cam_home_parent, false)
		else:
			cam.reparent(player, false)
		cam.transform = _cam_home_transform

	player.faction = _home_faction
	player.velocity = Vector3.ZERO
	# Facing follows the look direction you were using, so the view is continuous.
	player.rotation.y = player.look_direction.y
	if player.hud_weapon:
		player.hud_weapon.visible = true

	released_body.emit(body)


# Call this from World before a level transition — load_next_level sets
# player.global_transform directly, and a live possession would drag the player
# straight back to the old body on the next frame.
func force_release() -> void:
	if is_possessing():
		release()


# ─────────────────────────────────────────────
# DRIVE
# Runs in place of the Player's own movement while possessing. Everything for
# one frame happens here in order — body moves, ghost follows, camera applies —
# so there is no frame of camera lag behind the body.
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_possessing():
		return

	# Your own chassis was destroyed while you were away — snap back so the
	# normal death/respawn path in World isn't running under a hijacked camera.
	if not player.alive:
		release()
		return

	# The body died under us. Eject before Enemy.die() finishes disabling its
	# collider, or the player is left as a camera welded to a corpse.
	if not possessed.alive or possessed.ai_state == Enemy.AIState.DEAD:
		release()
		return

	# E-kill mid-possession: the link drops and you're thrown out.
	if possessed.get_signal_state() == Enemy.SignalState.EKILL:
		possession_failed.emit("SIGNAL LOST")
		release()
		return

	var input2 := Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	var basis := Basis(Vector3.UP, player.look_direction.y)
	var move_dir := basis.x * input2.x - basis.z * input2.y
	var want_jump := Input.is_action_just_pressed("jump")

	possessed.drive(move_dir, player.look_direction.y, want_jump, delta)

	# Camera is parented to the body now, so it inherits the body's yaw from
	# drive(). Only pitch is applied locally.
	cam.rotation.x = player.look_direction.x
	cam.rotation.y = 0.0
	cam.rotation.z = 0.0

	if Input.is_action_pressed("fire"):
		var aim := _aim_point()
		possessed.fire_as_player(aim)

	if Input.is_action_just_pressed("reload") and possessed.weapon != null:
		possessed.weapon.start_reload()


func _aim_point() -> Vector3:
	var origin := cam.global_position
	var end := origin + (-cam.global_transform.basis.z * 300.0)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [player.get_rid(), possessed.get_rid()]
	var hit: Dictionary = _space().intersect_ray(query)
	if hit.is_empty():
		return end
	return hit.position
