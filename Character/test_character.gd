extends CharacterBody3D

const SPEED := 6.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.002
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var pitch := 0.0
@onready var cam: Camera3D = $Camera3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		pitch = clamp(pitch - event.relative.y * MOUSE_SENS, -1.5, 1.5)
		rotation.x = pitch
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input2 := Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	var dir := (transform.basis.x * input2.x) + (-transform.basis.z * input2.y)
	if dir.length() > 0.001:
		dir = dir.normalized() * SPEED
		velocity.x = dir.x
		velocity.z = dir.z
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
