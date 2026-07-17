extends Node
# Field Journal / Codex: static entry data for the naturalist-fantasy Field
# Journal (Scenes/FieldJournalUI.tscn). Two categories -- Plants and
# Minerals -- each entry keyed by a stable species key (not an item id,
# since e.g. the Berry Bush species is "discovered" via picking up its
# Berries, not the bush block itself).
#
# Discovery state (which species the player has found) lives on PlayerStats
# (a small persistent-for-the-session set), not here -- this autoload only
# holds the read-only reference data + the item-id -> species-key lookup
# used to trigger discovery (see Inventory.gd's item_picked_up signal and
# PlayerStats.discover_item()).

enum Category { PLANT, MINERAL }

var entries: Dictionary = {}          # species_key -> entry Dictionary
var item_to_species: Dictionary = {}  # trigger item id -> species_key

func _ready() -> void:
	# --- Plants ---------------------------------------------------------
	_register("berry_bush", Category.PLANT, "Berry Bush", 70, {
		"Family": "Rosaceae (rose family)",
		"Habitat": "Forest & Plains undergrowth, sun-dappled edges",
		"Edible?": "Yes -- the berries restore Hunger when eaten",
		"Note": "The fruit is harvested by breaking the bush; wild bushes like this one are the ancestors of most cultivated berry crops.",
	})
	_register("flower_blue", Category.PLANT, "Blue Flower", 53, {
		"Family": "Campanulaceae (bellflower family)",
		"Habitat": "Forest floor, scattered among grass",
		"Edible?": "No -- ornamental only",
		"Note": "Its blue pigment is anthocyanin, the same pigment class that colors blueberries and red cabbage.",
	})
	_register("flower_pink", Category.PLANT, "Pink Flower", 54, {
		"Family": "Caryophyllaceae (pink family)",
		"Habitat": "Forest floor, scattered among grass",
		"Edible?": "No -- ornamental only",
		"Note": "The family Caryophyllaceae is literally nicknamed 'the pinks' after this color.",
	})

	# --- Minerals ---------------------------------------------------------
	_register("copper_ore", Category.MINERAL, "Copper Ore", 80, {
		"Category": "Native element / sulfide ore",
		"Mohs hardness": "2.5 - 3",
		"Common use": "Electrical wiring, plumbing, alloys (bronze, brass)",
		"Note": "One of the first metals humans ever worked -- the Copper Age predates the Bronze Age.",
	})
	_register("gold_ore", Category.MINERAL, "Gold Ore", 81, {
		"Category": "Native element",
		"Mohs hardness": "2.5 - 3",
		"Common use": "Jewelry, electronics contacts, currency reserves",
		"Note": "So unreactive it occurs in nature as pure metal nuggets, without needing to be smelted from a compound.",
	})
	_register("quartz", Category.MINERAL, "Quartz", 82, {
		"Category": "Silicate mineral (SiO2)",
		"Mohs hardness": "7",
		"Common use": "Glassmaking, electronics oscillators, ornamental stone",
		"Note": "Hard enough to scratch steel -- it's the reference mineral for '7' on the Mohs hardness scale.",
	})
	_register("hematite", Category.MINERAL, "Hematite", 83, {
		"Category": "Iron oxide mineral (Fe2O3)",
		"Mohs hardness": "5.5 - 6.5",
		"Common use": "Primary iron ore, red pigment (ochre)",
		"Note": "The same iron oxide that colors Mars red also colors this mineral and rusting iron on Earth.",
	})
	_register("malachite_ore", Category.MINERAL, "Malachite Ore", 84, {
		"Category": "Copper carbonate mineral",
		"Mohs hardness": "3.5 - 4",
		"Common use": "Copper ore, green pigment, ornamental carving",
		"Note": "Its banded green pattern forms where copper deposits weather near the surface.",
	})

func _register(key: String, category: int, display_name: String, trigger_item_id: int, facts: Dictionary) -> void:
	entries[key] = {
		"key": key,
		"category": category,
		"name": display_name,
		"trigger_item_id": trigger_item_id,
		"facts": facts,
	}
	item_to_species[trigger_item_id] = key

# Returns the species key that `item_id` proves the player has found, or ""
# if that item isn't tied to a codex entry.
func get_species_for_item(item_id: int) -> String:
	return item_to_species.get(item_id, "")

func get_entry(species_key: String) -> Dictionary:
	return entries.get(species_key, {})

func get_entries_by_category(category: int) -> Array:
	var out: Array = []
	for key in entries:
		if entries[key].category == category:
			out.append(entries[key])
	# Stable, deterministic order for the UI (registration order via
	# item_to_species insertion isn't guaranteed by Dictionary iteration).
	out.sort_custom(func(a, b): return a.trigger_item_id < b.trigger_item_id)
	return out
