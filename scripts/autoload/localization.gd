extends Node
## The menus' languages: English, and Simplified Chinese. Until the player picks
## one on the LANGUAGE row, the system's decides: Chinese on a Chinese system,
## English otherwise.
##
## The menus translate through localization/translations.csv, keyed by their own
## English text, so a label or button showing "NEW GAME" shows "新游戏" in Chinese
## by itself; text built from parts calls tr() on each part. The in-game screens
## stay English: the HUD has auto-translation off, and the stage screens and the
## words over the field draw their own text.
##
## The Chinese glyphs are tools/make_fonts.py's: baked into gold_font for the
## menus' big text, and cjk_font, a plain white set the default font falls back
## on for the rest, so each label's own colour tints them. Rerun the tool after
## adding translations.

signal language_changed

## Each language: its locale and its name, written in itself.
const LANGUAGES: Array = [["en", "English"], ["zh_CN", "简体中文"]]
const DEFAULT_LANGUAGE := "en"
const CJK_FONT: FontFile = preload("res://assets/ui/fonts/cjk_font.fnt")

var _language: String = DEFAULT_LANGUAGE


func _ready() -> void:
	_add_cjk_fallback(ThemeDB.fallback_font)
	# A test run shows English whatever the machine speaks, so its checks hold
	# anywhere (as it keeps its own settings file).
	var system := "" if InputSettings.is_test_run() else OS.get_locale_language()
	_apply(pick_language(InputSettings.get_saved_language(), system))


## The language to show: [param saved], the player's pick, when there is one;
## else the one for the system's [param system_language] ("zh" for any Chinese,
## which gets 简体中文); else English.
static func pick_language(saved: String, system_language: String) -> String:
	if _index_of(saved) >= 0:
		return saved
	for language: Array in LANGUAGES:
		if language[0].get_slice("_", 0) == system_language:
			return language[0]
	return DEFAULT_LANGUAGE


## The language shown now: a locale from LANGUAGES.
func get_language() -> String:
	return _language


## [param code]'s name, in its own language ("简体中文").
func get_language_name(code: String) -> String:
	var index := _index_of(code)
	return LANGUAGES[index][1] if index >= 0 else code


## Shows the menus in [param code] and keeps it for next time.
func set_language(code: String) -> void:
	if _index_of(code) < 0 or code == _language:
		return
	_apply(code)
	InputSettings.save_language(code)
	language_changed.emit()


## The next language along LANGUAGES ([param direction] 1) or the previous (-1).
func step_language(direction: int) -> void:
	set_language(LANGUAGES[wrapi(_index_of(_language) + direction, 0, LANGUAGES.size())][0])


func _apply(code: String) -> void:
	_language = code
	TranslationServer.set_locale(code)
	# The window's title is the game's name, in the language shown (坦克决战).
	get_tree().root.title = tr(ProjectSettings.get_setting("application/config/name"))


static func _index_of(code: String) -> int:
	for i in LANGUAGES.size():
		if LANGUAGES[i][0] == code:
			return i
	return -1


## Lets [param font] draw Chinese: CJK_FONT behind it, for the glyphs it lacks.
func _add_cjk_fallback(font: Font) -> void:
	if font == null or font.fallbacks.has(CJK_FONT):
		return
	var fallbacks := font.fallbacks
	fallbacks.append(CJK_FONT)
	font.fallbacks = fallbacks
