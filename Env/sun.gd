extends DirectionalLight3D

func kelvin_to_rgb(temp_kelvin: float) -> Color:
	var temperature = temp_kelvin / 100.0

	var red: float
	var green: float
	var blue: float

	# Calculate red
	if temperature <= 66.0:
		red = 255.0
	else:
		red = temperature - 60.0
		red = 329.698727446 * pow(red, -0.1332047592)
		red = clamp(red, 0.0, 255.0)

	# Calculate green
	if temperature <= 66.0:
		green = 99.4708025861 * log(temperature) - 161.1195681661
		green = clamp(green, 0.0, 255.0)
	else:
		green = temperature - 60.0
		green = 288.1221695283 * pow(green, -0.0755148492)
		green = clamp(green, 0.0, 255.0)

	# Calculate blue
	if temperature >= 66.0:
		blue = 255.0
	elif temperature <= 19.0:
		blue = 0.0
	else:
		blue = temperature - 10.0
		blue = 138.5177312231 * log(blue) - 305.0447927307
		blue = clamp(blue, 0.0, 255.0)

	# Convert to normalized RGB (0.0 to 1.0)
	return Color(red / 255.0, green / 255.0, blue / 255.0)

func sun_dir_ray() -> Vector3:
	return global_basis.z.normalized()

func _process(_delta: float) -> void:
	# Transform the light
	#rotate_y(delta * 0.002)
	#rotate_x(delta * 0.002)
	 #Update color
	var weight: float = sun_dir_ray().dot(Vector3.UP)
	var energy = smoothstep(-0.1, -0.05, weight)
	weight = pow(clamp(weight, 0.0, 1.0), 0.5)
	var sun_color = kelvin_to_rgb(lerpf(2000, 6500, weight))
	light_color = sun_color
	light_energy = energy
