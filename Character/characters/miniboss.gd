extends Enemy
class_name Boss
enum BossPhases {INTRO, PHASE_1, PHASE_2, PHASE_3, DEAD}
@export var phase_thresholds := {
	BossPhases.PHASE_2: 0.35,
}
var boss_phase: BossPhases = BossPhases.INTRO

#COMBAT RECON TIME
#COMBAT TIME

func set_phase(new_phase):
	if boss_phase == new_phase:
		return
	boss_phase = new_phase

	match boss_phase:
		BossPhases.PHASE_2:
			combat_recon_time = 1.5
			move_speed *= 1.1
