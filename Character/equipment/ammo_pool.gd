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
# PER CARRIER. A stock's capacity is what ONE fitted item carries; the loadout
# says how many items draw on each type (set_carriers), and the real capacity
# is the product. Two frag slots used to share one three-grenade pouch, so the
# second slot added nothing but a second way to throw the same grenades.
var _base_capacities: Dictionary = {}  # StringName -> int
var _carriers: Dictionary = {}         # StringName -> int, at least 1


func _ready() -> void:
	reset()


func reset() -> void:
	_counts.clear()
	_capacities.clear()
	_base_capacities.clear()
	for stock in starting_ammo:
		if stock == null or stock.ammo_type == &"":
			continue
		var n := _carriers_of(stock.ammo_type)
		_base_capacities[stock.ammo_type] = stock.capacity
		_capacities[stock.ammo_type] = stock.capacity * n
		_counts[stock.ammo_type] = stock.amount * n
		ammo_changed.emit(stock.ammo_type, stock.amount * n)


func _carriers_of(ammo_type: StringName) -> int:
	return maxi(1, int(_carriers.get(ammo_type, 1)))


## How many fitted items draw on `ammo_type`. Capacity scales with it, and a
## newly fitted item brings its own load: fitting a second frag slot adds three
## grenades, it does not just raise the ceiling on the three you had. Removing
## one trims whatever no longer fits. Unlimited types (capacity 0) are left
## alone — there is no ceiling to scale.
func set_carriers(ammo_type: StringName, n: int) -> void:
	n = maxi(1, n)
	var old := _carriers_of(ammo_type)
	_carriers[ammo_type] = n
	if n == old or not _base_capacities.has(ammo_type):
		return
	var base := int(_base_capacities[ammo_type])
	if base <= 0:
		return
	_capacities[ammo_type] = base * n
	var have := get_count(ammo_type)
	var count := mini(have + base * (n - old), base * n) if n > old else mini(have, base * n)
	_counts[ammo_type] = count
	ammo_changed.emit(ammo_type, count)


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
# Back to carrying capacity. A capacity of 0 means "no limit", which has no
# ceiling to fill to — those were silently SKIPPED, so any ammo type you didn't
# give a cap never restocked. They restore their starting amount instead.
func refill_all() -> void:
	var starting := {}
	for stock in starting_ammo:
		if stock != null and stock.ammo_type != &"":
			starting[stock.ammo_type] = stock.amount
	for ammo_type in _capacities.keys():
		var cap := get_capacity(ammo_type)
		var amount: int = cap if cap > 0 else int(starting.get(ammo_type, get_count(ammo_type)))
		_counts[ammo_type] = amount
		ammo_changed.emit(ammo_type, amount)
