extends Node
class_name SquadNew
@export var squad_members: Array[AI]

func _ready() -> void:
	for ai in squad_members:
		if ai == null:
			continue
		ai.connect("combat_triggered", combat_triggered)
		# CONNECT EACH AI's (combat_triggered(self)) signal to combat_triggered() function
		pass
func add_ai_to_squad(ai: AI):
	if ai:
		if squad_members.has(ai) == false:
			squad_members.append(ai)
			ai.connect("combat_triggered", combat_triggered)
		else:
			return

func remove_ai_from_squad(ai: AI):
	if ai:
		if squad_members.has(ai) == true:
			squad_members.erase(ai)
			ai.disconnect("combat_triggered", combat_triggered)
		else:
			return
func combat_triggered(triggered_ai: AI = null):
	if triggered_ai != null:
		for ai in squad_members:
			if ai == null:
				continue
			if ai.ai_state != Enemy.AIState.COMBAT:
				ai.trigger_combat(triggered_ai.combat_target)
		
