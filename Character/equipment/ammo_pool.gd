extends Node
class_name AmmoPool

# ─────────────────────────────────────────────
# AMMO POOL — the player's carried reserves, keyed by ammo type.
#
# Weapons hold what's in the magazine; this holds everything else. Reloading is
# a transfer from here into the magazine, so running dry is a real state instead
# of the old start_reload() that just assigned magazine_capacity = magazine_size
# and let you shoot forever.
#
# Grenades and repair charges live here too. They have no magazine, so their
# count IS their reserve and they simply never call take() with a magazine in
# mind. Don't give them a fake magazine to make them fit the gun shape.
# ─────────────────────────────────────────────

signal ammo_changed(ammo_type: StringName, count: int)

@export var starting_ammo: Array[AmmoStock] = []

var _counts: Dictionary = {}      # StringName -> int
var _capacities: Dictionary = {}  # StringName -> int (0 = unlimited)


func _ready() -> void:
	reset()


func reset() -> void:
	_counts.clear()
	_capacities.clear()
	for stock in starting_ammo:
		if stock == null or stock.ammo_type == &"":
			continue
		_capacities[stock.ammo_type] = stock.capacity
		_counts[stock.ammo_type] = stock.amount
		ammo_changed.emit(stock.ammo_type, stock.amount)


func get_count(ammo_type: StringName) -> int:
	return int(_counts.get(ammo_type, 0))


func get_capacity(ammo_type: StringName) -> int:
	return int(_capacities.get(ammo_type, 0))


func has(ammo_type: StringName, amount: int = 1) -> bool:
	return get_count(ammo_type) >= amount


# Take up to `amount`. Returns how much was actually granted, which is the whole
# point — a reload asks for a full magazine and takes what it can get, so the
# last reload in the game gives you a partial mag rather than nothing.
func take(ammo_type: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	var have := get_count(ammo_type)
	var granted: int = mini(have, amount)
	if granted <= 0:
		return 0
	_counts[ammo_type] = have - granted
	ammo_changed.emit(ammo_type, have - granted)
	return granted


# Returns how much was actually stored. The remainder is overflow — pickups
# should use it to decide whether to consume themselves or stay in the world.
func add(ammo_type: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	var have := get_count(ammo_type)
	var cap := get_capacity(ammo_type)
	var stored := amount
	if cap > 0:
		stored = mini(amount, maxi(0, cap - have))
	if stored <= 0:
		return 0
	_counts[ammo_type] = have + stored
	ammo_changed.emit(ammo_type, have + stored)
	return stored


# For a resupply crate that tops everything up to capacity.
func refill_all() -> void:
	for ammo_type in _capacities.keys():
		var cap := get_capacity(ammo_type)
		if cap > 0:
			_counts[ammo_type] = cap
			ammo_changed.emit(ammo_type, cap)
