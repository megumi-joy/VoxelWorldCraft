class_name ChangelogFeed
extends RefCounted
# Player-facing "what's new" feed for MainMenu's version label + changelog
# panel ("Что новое" / owner's "стриминг обновлений"). Short, Russian,
# summarized -- deliberately separate from the root CHANGELOG.md, which is
# the developer-facing changelog (English, PR-level detail, written by
# whoever lands each feature branch).
#
# ENTRIES[0] is also the single source MainMenu.gd reads its displayed
# "vX.Y.Z · обновлено <date>" label from (the date only -- the version
# number itself comes from project.godot's config/version, which the
# player already sees in the OS title bar / Steam page, so it stays the
# one canonical version string). See RELEASING.md for the release
# checklist that keeps project.godot, this file, and CHANGELOG.md in sync;
# MainMenu.gd pushes a console warning if project.godot's version and this
# file's newest entry ever disagree.
#
# Dates below are real (matched against `git log --date=short` for the
# commits that landed each batch of work), not placeholders.

const ENTRIES: Array[Dictionary] = [
	{
		"version": "0.3.0",
		"date": "2026-07-19",
		"lines": [
			"Новое стартовое меню: цветные кнопки, версия сборки и лента обновлений с кнопкой «Проверить обновления».",
			"Экран загрузки при запуске новой игры.",
			"Игрок больше не застревает в блоках; понятный экран смерти и возрождения.",
			"Мир теперь сохраняется и загружается между сессиями.",
			"Мелкие правки: захват мыши в оконном режиме, порядок отрисовки соседних чанков, дубли при крафте.",
		],
	},
	{
		"version": "0.2.0",
		"date": "2026-07-17",
		"lines": [
			"Яркий HUD: полоски здоровья и голода с иконками, хотбар, прицел.",
			"Новый биом «Равнины», ягодный куст и цветы, крафт деревянных инструментов.",
			"Более отзывчивое управление: разгон/торможение, прыжок, спринт.",
			"Полевой журнал: минералы и находки, которые можно каталогизировать.",
		],
	},
	{
		"version": "0.1.0",
		"date": "2026-01-30",
		"lines": [
			"Первый прототип: генерация мира по биомам (лес, пустыня, тундра).",
			"Добыча и постройка блоков, простой инвентарь и крафт.",
			"Мобы, жители и первое сохранение мира.",
		],
	},
]
