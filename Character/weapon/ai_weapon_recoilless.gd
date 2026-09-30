extends AIWeapon
class_name AIWeaponRecoilless

# ─────────────────────────────────────────────
# AI RECOILLESS RIFLE — the enemy half of a weapon that only ever had a player
# half.
#
# `item_rocket.tres` (id `recoilless`) carries a `player_scene` and NO
# `ai_scene`. It has been that way since the item was added, which means no
# enemy has ever fired one and no squadmate you fit one to could hold it. The
# item was half a weapon; this is the other half.
#
# DIRECT FIRE, NOT AN ARC. The grenade launcher subclass lobs on a ballistic
# curve, in a salvo, on a fuse. A recoilless round goes where the barrel points,
# fast, and detonates on what it hits — sharing that script would have meant
# switching off everything it does.
#
# THE BLAST LIVES ON THE PROJECTILE, not here. `rocket_projectile.tscn` carries
# blast_damage and blast_radius, and the player's launcher fires the same scene,
# so the two cannot drift apart into "the AI rocket hits harder than yours".
#
# MINIMUM RANGE IS THE BALANCE, and it is set on the scene rather than here: the
# base refuses to fire inside `min_effective_range`, which is what stops a
# rocket trooper walking into your squad and killing itself and three of yours.
# ─────────────────────────────────────────────

## The round. Defaults ride on the projectile scene.
@export var rocket_scene: PackedScene
## Metres per second out of the tube.
@export var launch_speed: float = 34.0
## Pushed this far out of the muzzle before it is let go, so a round fired with
## the carrier's own hull in front of the mount does not arm against it.
@export var muzzle_push: float = 0.7
## For the playtest log, the way the grenade launcher labels its bombs.
@export var analytics_label: String = "Recoilless"


# The base calls this on the frame the shot goes off. A hitscan weapon traces a
# ray here; this puts a round in the air instead.
func check_damage(weapon_target: Vector3) -> void:
	if rocket_scene == null:
		push_warning("AIWeaponRecoilless on '%s' has no rocket_scene — it fires, makes noise, and nothing leaves the tube." % name)
		return
	var origin: Node3D = muzzle_origin if muzzle_origin != null else self
	var from: Vector3 = origin.global_position
	var dir := _aim(from, weapon_target)
	var rocket: Node3D = rocket_scene.instantiate()
	var host := _level_node()
	if host == null:
		rocket.queue_free()
		return   # nothing to parent a live round to; the level is going away
	host.add_child(rocket)
	rocket.global_position = from + dir * muzzle_push
	# Nose down the flight path from the first frame, so it reads as fired
	# rather than dropped.
	if dir.length_squared() > 0.0001 and absf(dir.dot(Vector3.UP)) < 0.99:
		rocket.look_at(rocket.global_position + dir, Vector3.UP)
	if rocket is RigidBody3D:
		(rocket as RigidBody3D).linear_velocity = dir * launch_speed
	# Keeps the firer off its own blast list and credits it with the kill.
	if rocket.has_method("setup"):
		rocket.setup(_owner_body())
	if "analytics_label" in rocket:
		rocket.analytics_label = analytics_label
	play_muzzle_flash()


## Where the tube is pointing, with the weapon's spread applied. Falls back to
## the mount's own forward if it was handed nowhere to shoot.
func _aim(from: Vector3, weapon_target: Vector3) -> Vector3:
	var to := get_forward_vector()
	var want := weapon_target - from
	if want.length_squared() > 0.01:
		to = want.normalized()
	if ai_spread_mrad > 0.0:
		var s := ai_spread_mrad * 0.001
		var side := to.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		to = to.rotated(Vector3.UP, randf_range(-s, s))
		to = to.rotated(side.normalized(), randf_range(-s, s))
	return to.normalized()
