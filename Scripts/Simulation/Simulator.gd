extends Node

var nodes = {} # Vector3i -> { type: String, e: int, h: int, fixed: int, momentum: float, recombinations: int }

const TYPE_N = "n-type"
const TYPE_P = "p-type"
const TYPE_INDUCTOR = "inductor"
const TYPE_INSULATOR = "insulator"
const TYPE_WIRE = "wire"
const TYPE_SOURCE_POS = "source-pos"
const TYPE_SOURCE_NEG = "source-neg"

var tick_accumulator = 0.0
var tick_rate = 0.05 # 20 Hz simulation

func _process(delta):
	tick_accumulator += delta
	while tick_accumulator >= tick_rate:
		tick_accumulator -= tick_rate
		simulate_step()

func add_node(pos: Vector3i, type: String):
	var data = { "type": type, "e": 0, "h": 0, "fixed": 0, "momentum": 0.0, "recombinations": 0 }
	match type:
		TYPE_N:
			data.fixed = 100
			data.e = 100
		TYPE_P:
			data.fixed = -100
			data.h = 100
		TYPE_SOURCE_POS:
			data.fixed = -500
			data.h = 500
		TYPE_SOURCE_NEG:
			data.fixed = 500
			data.e = 500
	nodes[pos] = data

func remove_node(pos: Vector3i):
	if nodes.has(pos):
		nodes.erase(pos)

func simulate_step():
	# 1. Sources Replenish
	for pos in nodes.keys():
		var n = nodes[pos]
		if n.type == TYPE_SOURCE_POS:
			n.h = 500
		elif n.type == TYPE_SOURCE_NEG:
			n.e = 500
			
	# Snapshot
	var snap = {}
	for pos in nodes.keys():
		var n = nodes[pos]
		snap[pos] = { "e": n.e, "h": n.h, "net": n.fixed + n.h - n.e, "momentum": n.momentum }
		
	# 2. Random Walk / Physics
	for pos in nodes.keys():
		var n = nodes[pos]
		if n.type == TYPE_SOURCE_POS or n.type == TYPE_SOURCE_NEG: continue
		
		var neighbors = [
			pos + Vector3i.RIGHT, pos + Vector3i.LEFT,
			pos + Vector3i.UP, pos + Vector3i.DOWN,
			pos + Vector3i.FORWARD, pos + Vector3i.BACK
		]
		
		var valid_neighbors = []
		for np in neighbors:
			if snap.has(np) and nodes[np].type != TYPE_INSULATOR:
				valid_neighbors.append(np)
				
		if valid_neighbors.is_empty(): continue
		
		# Inductor Logic
		if n.type == TYPE_INDUCTOR:
			var max_pull = -999999.0
			var best_n = Vector3i.ZERO
			var found_pull = false
			var mutual = 0.0
			
			for np in valid_neighbors:
				var pull = snap[np].net - snap[pos].net
				if pull > max_pull:
					max_pull = pull
					best_n = np
					found_pull = true
				if nodes[np].type == TYPE_INDUCTOR:
					mutual += snap[np].momentum * 0.1
					
			n.momentum = (n.momentum + (max_pull * 0.05) + mutual) * 0.98
			
			if found_pull and abs(n.momentum) > 1.0:
				var transfer = int(min(n.e, abs(floor(n.momentum))))
				if transfer > 0 and n.momentum > 0:
					n.e -= transfer
					nodes[best_n].e += transfer
			continue
			
		# Normal Drift-Diffusion
		if n.e > 0:
			var best_e_n = valid_neighbors[0]
			var best_e_pull = snap[best_e_n].net - snap[pos].net
			for np in valid_neighbors:
				var pull = snap[np].net - snap[pos].net
				if pull > best_e_pull:
					best_e_pull = pull
					best_e_n = np
			if randf() < 0.5 or best_e_pull > 0:
				n.e -= 1
				nodes[best_e_n].e += 1
				
		if n.h > 0:
			var best_h_n = valid_neighbors[0]
			var best_h_pull = snap[pos].net - snap[best_h_n].net
			for np in valid_neighbors:
				var pull = snap[pos].net - snap[np].net
				if pull > best_h_pull:
					best_h_pull = pull
					best_h_n = np
			if randf() < 0.5 or best_h_pull > 0:
				n.h -= 1
				nodes[best_h_n].h += 1
				
	# 3. Recombination
	for pos in nodes.keys():
		var n = nodes[pos]
		if n.type == TYPE_SOURCE_POS or n.type == TYPE_SOURCE_NEG: continue
		var recomb = min(n.e, n.h)
		if recomb > 0:
			var amt = int(max(1, floor(recomb * 0.01)))
			n.e -= amt
			n.h -= amt
			n.recombinations += amt
