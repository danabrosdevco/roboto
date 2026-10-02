extends SceneTree
# Robots die and are freed all mission. If building them through CsgBake.make()
# and then freeing them is unsafe, the bake cannot ship — so churn it hard.
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const _CsgBake := preload("res://Character/characters/ai/csg_bake.gd")

func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 100:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	var scenes: Array = []
	var dir := DirAccess.open("res://Character/characters/ai")
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			var p := "res://Character/characters/ai/" + f
			if _CsgBake._cache.has(p):
				scenes.append(p)
	scenes.sort()

	print("")
	print("CHURN — one of EVERY baked chassis (%d), built and freed, one at a time." % scenes.size())
	for si in scenes.size():
		var sp: String = scenes[si]
		var made: Array = []
		for _i in 3:
			var b: Node3D = _CsgBake.make(load(sp))
			b.faction = Enums.Factions.ENEMY
			level.add_child(b)
			b.global_position = Vector3(randf_range(-20, 20), 2, randf_range(-20, 20))
			made.append(b)
		for _i in 12:
			await physics_frame
		for b in made:
			b.queue_free()
		for _i in 12:
			await physics_frame
		print("   %-32s survived" % sp.get_file())
	print("CHURN SURVIVED — every chassis built and freed")
	quit(0)
