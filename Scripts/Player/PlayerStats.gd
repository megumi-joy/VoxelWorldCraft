extends Node
class_name PlayerStats

signal health_changed(value, max_value)
signal hunger_changed(value, max_value)
signal died

@export var max_health: float = 100.0
@export var max_hunger: float = 100.0
@export var hunger_decay_rate: float = 0.5 # Units per second

signal gold_changed(value)
var gold: int = 0

var health: float
var hunger: float

func _ready():
	health = max_health
	hunger = max_hunger
	emit_stats()

func _process(delta):
	# Hunger decay
	if hunger > 0:
		hunger -= hunger_decay_rate * delta
		if hunger < 0:
			hunger = 0
			take_damage(5.0) # Starvation damage
		emit_signal("hunger_changed", hunger, max_hunger)

func take_damage(amount: float):
	health -= amount
	if health <= 0:
		health = 0
		emit_signal("died")
	emit_signal("health_changed", health, max_health)

func heal(amount: float):
	health += amount
	if health > max_health:
		health = max_health
	emit_signal("health_changed", health, max_health)

func eat(amount: float):
	hunger += amount
	if hunger > max_hunger:
		hunger = max_hunger
	emit_signal("hunger_changed", hunger, max_hunger)

func add_gold(amount: int):
	gold += amount
	emit_signal("gold_changed", gold)

func emit_stats():
	emit_signal("health_changed", health, max_health)
	emit_signal("hunger_changed", hunger, max_hunger)
