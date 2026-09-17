extends StaticBody3D

@export var faction = Enums.Factions.ENEMY
@export var health = 30
@export var obstacle = true
var alive: bool = true

# `_source` is unused but has to be ACCEPTED. Every damage source in the
# project passes an attributor — ai_weapon, hud_weapon_template, player_melee
# and Explosion all call apply_damage(amount, source) — so the old one-argument
# signature raised "too many arguments" instead of taking damage. Shooting a
# crate errored rather than breaking it.
func apply_damage(damage, _source = null):
	if alive == false:
		return
	health -= damage
	if health <= 0:
		alive = false
		die()
		print (name + (" has died!"))
	pass
func get_faction():
	return faction

func die():
	await get_tree().create_timer(0.25	).timeout
	queue_free()

func get_obstacle():
	return obstacle
