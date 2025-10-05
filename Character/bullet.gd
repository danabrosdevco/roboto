extends CSGSphere3D
var velocity: Vector3
const speed = 200

func initiate(new_number):
	velocity = new_number
	pass

func _physics_process(delta: float) -> void:
	position += velocity * speed * delta
