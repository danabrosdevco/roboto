extends Node3D

@export var scan_radius: float = 30.0
@export var scan_duration: float = 3.5   # same length as your scan animation
@export var target_mark_duration: float = 5
signal highlight_target(target: Node3D)
@export var sound: AudioStreamPlayer3D
@export var ping: AudioStreamPlayer3D
@export var fail: AudioStreamPlayer3D
var scanning: bool = false
func activate_scan():
	if scanning == true:
		return
	scanning = true
	sound.play()
	await get_tree().create_timer(scan_duration).timeout
	sound.stop()
	await get_tree().physics_frame
	_scan_for_enemies()
	scanning = false
	
func _scan_for_enemies():
	var space_state = get_world_3d().direct_space_state
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = scan_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere_shape
	query.transform = Transform3D(Basis(), global_transform.origin)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 0xFFFFFFFF
	query.margin = 0.0
	query.exclude = [self, get_parent()]  # optional: don't hit self
	var results = space_state.intersect_shape(query, 64)
	var play_ping = 0
	for result in results:
		var obj = result.get("collider")
		print (obj.name)
		if obj:
			if obj.has_method("get_faction"):
				print ("HAS FACTION!")
				if obj.get_faction() == Enums.Factions.ENEMY:
					highlight_target.emit(obj, target_mark_duration)
					play_ping += 1
	if play_ping >= 1:
		ping.play()
	else:
		fail.play()
