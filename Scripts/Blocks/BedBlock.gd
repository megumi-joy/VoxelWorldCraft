extends Node3D

func interact(player):
	var time_cycle = get_node_or_null("/root/World/TimeCycle") # Adjust path if needed
	# Or find by type
	if not time_cycle:
		time_cycle = find_time_cycle(get_tree().root)
		
	if time_cycle:
		# Check if night
		# Night is roughly 0.25 to 0.75 (Sunset to Sunrise)
		var t = time_cycle.time / time_cycle.day_length
		if t > 0.25 and t < 0.75:
			player.show_message("Sleeping...")
			await get_tree().create_timer(1.0).timeout
			time_cycle.skip_to_morning()
			player.show_message("Woke up!")
		else:
			player.show_message("You can only sleep at night.")
	else:
		print("TimeCycle not found!")

func find_time_cycle(node):
	if node is TimeCycle: return node
	for child in node.get_children():
		var res = find_time_cycle(child)
		if res: return res
	return null
