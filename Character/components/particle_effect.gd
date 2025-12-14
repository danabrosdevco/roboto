extends Node3D
class_name ParticleEffect
@export var particles: CPUParticles3D

func activate():
	particles.emitting = true
