# Localization

The menus come in English and Simplified Chinese. The in-game screens (the HUD, the stage screens, the pickup and kill words) stay English, with one exception Sean asked for: the results box's header and total read 战斗成绩 and 总计 in Chinese, the original panel's own words.

## How it works

- **Languages:** `Localization` (scripts/autoload/localization.gd) holds the list and applies the player's pick, saved in the settings file (`[game] language`, via `InputSettings`).
  - Until the player picks one, the system's language decides (`pick_language`): any Chinese system (`OS.get_locale_language()` = "zh", Traditional included) gets 简体中文, anything else English. Nothing is saved until the player picks, so the game keeps following the system until then.
  - A test run always starts in English, whatever the machine speaks, so the tests' English checks hold anywhere.
- **Choosing:** the LANGUAGE row in the settings (title and pause menu, `CommonSettings`) steps through the languages. Each language's name is written in itself.
- **The game's name** is 坦克决战 in Chinese (Sean's choice): the title screen's logo ("BATTLE TANK" is a key), and the window's title, which `Localization` sets to `tr()` of the project's name ("Battle Tank") whenever the language changes.
- **Translations:** localization/translations.csv, one row per string: the key is the English text itself, and the `zh_CN` column holds the Chinese.
  - Line breaks are written `\n`; the import unescapes both keys and values (`translations.csv.import`: `unescape_keys=true`).
  - project.godot lists the imported `translations.zh_CN.translation`.
- **Plain text translates itself.** A label or button showing a key shows its translation (Godot's auto-translation), including text set from code.
- **Text built from parts** must translate its template with `tr()`, e.g. `tr("Stage %d   ·   Difficulty %d   ·   %d stages cleared") % [...]`.
  - When the languages order the parts differently, use named fields: `tr("{who} plays on controller {pad}:  {name}").format({...})`.
  - Plurals are separate whole-sentence keys (`"... %d stage"` / `"... %d stages"`).
  - Static code uses `TranslationServer.translate()`.
  - Screens rebuild such text on `NOTIFICATION_TRANSLATION_CHANGED` (title screen, pause menu).
- **Staying English:**
  - game.tscn's HUD has `auto_translate_mode = 2` (disabled). Without it, a sitting-out player's "OFF" would read 关.
  - StageOverlay, PickupText and KillText draw their own text, which is never translated, except StageOverlay's `box_words()`: `tr("RESULTS")` and `tr("TOTAL")`.

## Fonts

The bitmap fonts are ASCII only. tools/make_fonts.py adds the Chinese from Fusion Pixel Font 12 px, zh_hans (SIL OFL 1.1; the BDF source is in assets/ui/fonts/src, and the licences are in assets/ui/fonts/licenses). It bakes only the CJK characters found in localization/*.csv and scripts/:

- **gold_font** gets them at 2×, in its gold with a 1 px bevel. A 2 px bevel would fill the 2 px gaps between an ideograph's strokes. This covers the menus' big text: buttons, headers and row names.
- **cjk_font** has only them, in plain white, so each label's colour tints them.
  - It is the fallback of the default font (`Localization` adds it to `ThemeDB.fallback_font`), which the rest of the menus' text uses.
  - Its size is 12 and it scales by whole steps only (`scaling_mode=1`), so the menus' 18–29 px text draws it at exactly 2×, crisp.

## Adding or changing text

1. Add the row to localization/translations.csv: the English exactly as the code or scene has it, then the Chinese. Keep the `%s`/`%d` fields in the same order, and the `{names}`.
2. Run `python3 tools/make_fonts.py`, so any new characters get baked.
3. Import (open the editor, or `Godot --headless --path . --import`).
4. Run scenes/test/localization_test.tscn. It checks that every row is translated, keeps its fields and reads back from the game, and that every Chinese character is in both fonts.

A new language needs a column in the CSV, its `.translation` in project.godot, an entry in `Localization.LANGUAGES`, and glyphs if its script isn't covered.
