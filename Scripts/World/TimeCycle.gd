extends Node
class_name TimeCycle

@export var sun: DirectionalLight3D
@export var environment: WorldEnvironment
@export var day_length: float = 120.0 # Seconds for a full day

var time: float = 0.0

func _process(delta):
	time += delta
	if time > day_length:
		time -= day_length
		
	var time_percent = time / day_length
	# 0.0 = Noon, 0.5 = Midnight (or vice versa depending on rotation)
	# Rotation X: -90 is noon (straight down), 90 is midnight (straight up)
	# Let's say -90 at t=0
	
	var sun_angle = lerp(-90.0, 270.0, time_percent)
	
	if sun:
		sun.rotation_degrees.x = sun_angle
		
		# Simple day/night energy
		if sun_angle > 0 and sun_angle < 180:
			sun.light_energy = 0.0 # Night
		else:
			sun.light_energy = 1.0 # Day
