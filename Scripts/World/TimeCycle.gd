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
		# Render-step-2: daytime energy bumped 1.0 -> 1.5. Under the new
		# atmosphere_sky.gdshader (Shaders/atmosphere_sky.gdshader) + the
		# Environment's ACES-ish tonemapping, the old value of 1.0 read as
		# noticeably flatter/darker than the pre-Lague ProceduralSkyMaterial
		# look. This raises the SAME single day value TimeCycle already
		# owns (still fully day/night-driven, not overridden per-frame by
		# a second script) rather than fighting it -- night stays 0.0.
		if sun_angle > 0 and sun_angle < 180:
			sun.light_energy = 0.0 # Night
		else:
			sun.light_energy = 1.5 # Day

func skip_to_morning():
	# Skip to Sunrise (Approx 0.75 of cycle if 0 is Noon (-90 deg), 0.5 is Midnight (90 deg), 0.75 is Sunrise (180 deg))
	# Actually wait:
	# 0.0 = -90 (Noon)
	# 0.25 = 0 (Sunset)
	# 0.5 = 90 (Midnight)
	# 0.75 = 180 (Sunrise)
	# 1.0 = 270 (Noon)
	# So Morning is 0.75.
	time = day_length * 0.75
	print("Skipped to morning!")
