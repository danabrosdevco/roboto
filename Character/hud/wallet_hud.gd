extends Control

# ─────────────────────────────────────────────
# WALLET — resources and compute, top right, at home base only.
#
# The objective list owns that corner in the field and hides at base, so the
# corner is free there — and base is where both numbers get spent. Updated on
# the ledger's own announcement rather than polled.
#
# Built in code and added to the HUD by the objective HUD.
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")

var _campaign: Node
var _resources: Label
var _compute: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	var row := Kit.hbox(18)
	row.anchor_left = 1.0
	row.anchor_right = 1.0
	row.offset_left = -420
	row.offset_right = -28
	row.offset_top = 22
	row.offset_bottom = 52
	row.alignment = BoxContainer.ALIGNMENT_END
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(row)
	_compute = Kit.label("", Kit.COMPUTE, 22, true)
	row.add_child(_compute)
	_resources = Kit.label("", Kit.MONEY, 22, true)
	row.add_child(_resources)

	_campaign = get_tree().get_first_node_in_group("campaign")
	if _campaign == null:
		push_warning("WalletHUD: no campaign in the scene; nothing to show.")
		visible = false
		return
	_campaign.deployed.connect(func(_m): _refresh())
	_campaign.returned_to_base.connect(_refresh)
	_campaign.state_loaded.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var state: CampaignState = _campaign.state if _campaign != null else null
	if state == null:
		visible = false
		return
	# The ledger announces every change; hooked on the current state, which a
	# reset replaces.
	if not state.ledger_changed.is_connected(_refresh):
		state.ledger_changed.connect(_refresh)
	visible = not bool(_campaign.get("in_mission"))
	_resources.text = "RESOURCES %d" % state.available()
	_compute.text = "COMPUTE %d" % state.compute_free()
