extends AIGrenadeProjectile
class_name ClusterShell

# ─────────────────────────────────────────────
# THE CLUSTER ROUND — one shell in, a handful of bomblets out.
#
# Extends the frag round rather than replacing it, so the fuse, the bounce
# arming, the blast ownership and the analytics label all stay in one place and
# keep working. The only thing added is what happens at the moment it goes off:
# before the shell's own blast, it throws `submunitions` bomblets outward and
# upward, each on a short fuse of its own.
#
# THE SHELL'S OWN BLAST IS SMALL ON PURPOSE. The weapon is not a bigger
# grenade; it is area denial. What makes it worth a slot is that one pull
# covers ground, over a second, in a pattern you cannot aim precisely — so it
# is the wrong answer to one target in the open and the right answer to a
# doorway, a trench, or anything you want to make expensive to stand in.
#
# Bomblets are the SAME SCENE as the frag round. They inherit the thrower, so
# the kills score to whoever fired the shell, and they carry their own
# analytics label so the log reads "Cluster Launcher" for all of it rather than
# filing the shell under the weapon and the bomblets under Frag.
# ─────────────────────────────────────────────

## What comes out. Left null, the shell is just a small grenade and says so.
@export var submunition_scene: PackedScene
@export var submunitions: int = 6
## Outward shove, in metres per second, in the horizontal plane.
@export var scatter_speed: float = 5.5
## And upward, which is what turns a ring into a pattern with depth — they land
## over about half a second rather than all at once on one circle.
@export var scatter_lift: float = 4.0
## Spread of the fuses, so the crumps overlap instead of landing on one beat.
@export var submunition_fuse_min: float = 0.55
@export var submunition_fuse_max: float = 0.95
@export var submunition_damage: int = 26
@export var submunition_radius: float = 3.4


func _explode() -> void:
	# The parent sets _exploded inside its own _explode(); checking it here
	# first is what stops a shell that is hit by its own first bomblet from
	# scattering a second pattern.
	if _exploded:
		return
	_scatter()
	super()


func _scatter() -> void:
	if submunition_scene == null:
		push_warning("ClusterShell '%s' has no submunition_scene — it goes off as a plain grenade and the weapon's whole point is missing." % name)
		return
	var here := global_position
	var level := _level()
	var made: Array = []
	for i in maxi(submunitions, 1):
		var bomblet := submunition_scene.instantiate()
		# setup() BEFORE the tree, the same contract the frag round expects —
		# the blast reads its owner on the frame it is added, and a bomblet
		# that entered the tree first credited its kills to nobody.
		if bomblet.has_method("setup") and _thrower != null and is_instance_valid(_thrower):
			bomblet.setup(_thrower)
		if "fuse_time" in bomblet:
			bomblet.fuse_time = randf_range(submunition_fuse_min, submunition_fuse_max)
		if "blast_damage" in bomblet:
			bomblet.blast_damage = submunition_damage
		if "blast_radius" in bomblet:
			bomblet.blast_radius = submunition_radius
		# Time-fused, not impact-fused. Impact-fused bomblets thrown from a
		# burst detonate on the floor they are already touching, all six inside
		# a metre, which is one big explosion wearing six explosions' cost.
		if "explode_on_bounce" in bomblet:
			bomblet.explode_on_bounce = false
		if "analytics_label" in bomblet:
			bomblet.analytics_label = analytics_label if analytics_label != "" else "Cluster Launcher"
		level.add_child(bomblet)
		# Half a metre up, because the burst happens ON something — spawned at
		# the shell's own position they start inside the floor and the physics
		# server pushes them out in whatever direction it likes.
		bomblet.global_position = here + Vector3.UP * 0.5

		if bomblet is RigidBody3D:
			var body := bomblet as RigidBody3D
			var angle: float = TAU * (float(i) + randf_range(-0.25, 0.25)) / float(maxi(submunitions, 1))
			var out := Vector3(cos(angle), 0.0, sin(angle))
			body.linear_velocity = out * scatter_speed * randf_range(0.6, 1.25) \
				+ Vector3.UP * scatter_lift * randf_range(0.7, 1.15)
			body.angular_velocity = Vector3(
				randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
			# THEY MUST NOT SHOVE EACH OTHER. Six bodies spawned inside half a
			# metre of one another resolve their overlap before they resolve
			# their velocity, and the pattern came out as a scatter of whatever
			# the physics server decided rather than the ring that was asked
			# for. Excepted against the shell too, which is still there.
			for other in made:
				body.add_collision_exception_with(other)
			if self is PhysicsBody3D:
				body.add_collision_exception_with(self)
			made.append(body)
