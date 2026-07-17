extends Node
class_name PlayerStats

signal health_changed(value, max_value)
signal hunger_changed(value, max_value)
signal died

# Field Journal discovery: a small persistent-for-the-session set of codex
# species keys the player has found (see CodexDatabase.gd for the entry
# data). Session-persistent by design -- not written to SaveSystem -- once
# discovered, an entry stays unlocked for the rest of this play session.
signal species_discovered(species_key, entry)
var discovered_species: Dictionary = {} # species_key -> true

# Called whenever the player picks up an item (see Inventory.gd's
# item_picked_up signal, wired up in Player.gd). If that item id is the
# discovery trigger for a codex species that hasn't been found yet, unlock
# it and notify listeners (Player.gd shows a toast; FieldJournalUI
# re-renders next time it's opened).
func discover_item(item_id: int) -> void:
	var species_key: String = CodexDatabase.get_species_for_item(item_id)
	if species_key == "" or discovered_species.has(species_key):
		return
	discovered_species[species_key] = true
	species_discovered.emit(species_key, CodexDatabase.get_entry(species_key))

func is_discovered(species_key: String) -> bool:
	return discovered_species.has(species_key)

@export var max_health: float = 100.0
@export var max_hunger: float = 100.0
@export var hunger_decay_rate: float = 0.5 # Units per second

signal armor_changed(value)
var armor: float = 0.0

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
	# Apply armor reduction (simple linear reduction for now)
	var reduction = armor * 0.1 # Each armor point reduces 10%? No, let's say armor is percentage.
	# Let's say armor is a flat value that reduces damage but has a cap.
	var final_damage = amount * (1.0 - (armor / (armor + 50.0))) # Diminishing returns formula
	
	health -= final_damage
	if health <= 0:
		health = 0
		emit_signal("died")
	emit_signal("health_changed", health, max_health)

func set_armor(value: float):
	armor = value
	emit_signal("armor_changed", armor)

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
