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
	_register("berry_bush", Category.PLANT, "Ягодный куст", 70, {
		"Семейство": "Розовые (Rosaceae)",
		"Среда обитания": "Подлесок лесов и равнин, солнечные опушки",
		"Съедобно?": "Да -- ягоды восстанавливают голод при употреблении",
		"Заметка": "Плоды собирают, ломая куст; такие дикие кусты -- предки большинства культурных ягодных культур.",
	})
	_register("flower_blue", Category.PLANT, "Синий цветок", 53, {
		"Семейство": "Колокольчиковые (Campanulaceae)",
		"Среда обитания": "Лесная подстилка, среди травы",
		"Съедобно?": "Нет -- только декоративный",
		"Заметка": "Синий пигмент -- антоциан, тот же класс пигментов, что окрашивает чернику и краснокочанную капусту.",
	})
	_register("flower_pink", Category.PLANT, "Розовый цветок", 54, {
		"Семейство": "Гвоздичные (Caryophyllaceae)",
		"Среда обитания": "Лесная подстилка, среди травы",
		"Съедобно?": "Нет -- только декоративный",
		"Заметка": "Семейство Caryophyllaceae в народе называют «гвоздичными» именно за этот цвет.",
	})

	# --- Minerals ---------------------------------------------------------
	_register("copper_ore", Category.MINERAL, "Медная руда", 80, {
		"Категория": "Самородный элемент / сульфидная руда",
		"Твёрдость по Моосу": "2.5 - 3",
		"Применение": "Электропроводка, сантехника, сплавы (бронза, латунь)",
		"Заметка": "Один из первых металлов, освоенных человеком -- медный век предшествовал бронзовому.",
	})
	_register("gold_ore", Category.MINERAL, "Золотая руда", 81, {
		"Категория": "Самородный элемент",
		"Твёрдость по Моосу": "2.5 - 3",
		"Применение": "Ювелирные изделия, контакты в электронике, валютные резервы",
		"Заметка": "Настолько инертно, что встречается в природе в виде чистых самородков, без выплавки из соединений.",
	})
	_register("quartz", Category.MINERAL, "Кварц", 82, {
		"Категория": "Силикатный минерал (SiO2)",
		"Твёрдость по Моосу": "7",
		"Применение": "Производство стекла, кварцевые генераторы в электронике, декоративный камень",
		"Заметка": "Достаточно твёрд, чтобы царапать сталь -- эталонный минерал для отметки «7» по шкале твёрдости Мооса.",
	})
	_register("hematite", Category.MINERAL, "Гематит", 83, {
		"Категория": "Минерал оксида железа (Fe2O3)",
		"Твёрдость по Моосу": "5.5 - 6.5",
		"Применение": "Основная железная руда, красный пигмент (охра)",
		"Заметка": "Тот же оксид железа, что окрашивает Марс в красный цвет, окрашивает и этот минерал, и ржавеющее железо на Земле.",
	})
	_register("malachite_ore", Category.MINERAL, "Малахитовая руда", 84, {
		"Категория": "Минерал карбоната меди",
		"Твёрдость по Моосу": "3.5 - 4",
		"Применение": "Медная руда, зелёный пигмент, декоративная резьба",
		"Заметка": "Полосчатый зелёный узор образуется там, где медные залежи выветриваются у поверхности.",
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
