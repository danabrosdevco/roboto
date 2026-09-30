extends Resource
class_name Armoury

# ─────────────────────────────────────────────
# ARMOURY — what you own, and the shop that fills it.
#
# THE STRUCTURAL DECISION: items are COUNTS, not instances. The pool is
# {item_id: how many spare}, and a soldier's slot holds an item id. Fitting one
# decrements the pool; removing it increments. Two identical modules genuinely
# are interchangeable, so tracking them individually would buy nothing and cost
# a lot — and it makes the save file trivial.
#
# Buying goes through CampaignState's allocation ledger rather than subtracting
# from a balance, which is what makes selling a true refund: erase the entry and
# the resources reappear. Nothing to keep in sync, nothing to drift.
# ─────────────────────────────────────────────

# item_id -> spare count (does NOT include items currently fitted to soldiers)
@export var stock: Dictionary = {}
# chassis_id -> spare count
@export var chassis_stock: Dictionary = {}

signal stock_changed


func spare(item_id: StringName) -> int:
	return int(stock.get(item_id, 0))


func spare_chassis(chassis_id: StringName) -> int:
	return int(chassis_stock.get(chassis_id, 0))


func add(item_id: StringName, amount: int = 1) -> void:
	if item_id == &"" or amount <= 0:
		return
	stock[item_id] = spare(item_id) + amount
	stock_changed.emit()


# Returns false when there's nothing spare, so callers can refuse cleanly rather
# than going negative.
func take(item_id: StringName, amount: int = 1) -> bool:
	if spare(item_id) < amount:
		return false
	var left := spare(item_id) - amount
	if left <= 0:
		stock.erase(item_id)
	else:
		stock[item_id] = left
	stock_changed.emit()
	return true


func add_chassis(chassis_id: StringName, amount: int = 1) -> void:
	if chassis_id == &"" or amount <= 0:
		return
	chassis_stock[chassis_id] = spare_chassis(chassis_id) + amount
	stock_changed.emit()


func take_chassis(chassis_id: StringName, amount: int = 1) -> bool:
	if spare_chassis(chassis_id) < amount:
		return false
	var left := spare_chassis(chassis_id) - amount
	if left <= 0:
		chassis_stock.erase(chassis_id)
	else:
		chassis_stock[chassis_id] = left
	stock_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"stock": stock, "chassis_stock": chassis_stock}


static func from_dict(data: Dictionary) -> Armoury:
	var a := Armoury.new()
	a.stock = data.get("stock", {})
	a.chassis_stock = data.get("chassis_stock", {})
	return a
