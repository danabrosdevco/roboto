extends Interactible
class_name PlayerCorpse

func activate(bits: int):
	value = bits
	used = false
	visible = true
	monitoring = true
	monitorable = true
	if collision_body:
		collision_body.disabled = false

	if static_body:
		static_body.disabled = false
