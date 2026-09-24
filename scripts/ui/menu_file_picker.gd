class_name MenuFilePicker
extends RefCounted
## File picker shared by the menu screens: the operating system's own dialog
## when the display server offers one, otherwise Godot's in-game FileDialog.
## Opens a file, or in save mode names one to write. Remembers the last folder
## used per purpose (see InputSettings.save_import_dir).

signal file_picked(path: String)

const EMBEDDED_NOTE := "No system file picker while the game runs in the editor's Game tab. Run it in its own window to use the macOS picker."

var _host: Node
var _title: String
var _filters: PackedStringArray
var _purpose: String
var _save_mode: bool
var _dialog: FileDialog  # in-game fallback, created on first use


## [param save_mode] names a file to write instead of picking one to open.
func _init(host: Node, title: String, filters: PackedStringArray, purpose: String, save_mode := false) -> void:
	_host = host
	_title = title
	_filters = filters
	_purpose = purpose
	_save_mode = save_mode
	host.tree_exiting.connect(_free_dialog)


## Opens the picker, in save mode suggesting [param file_name]; [signal
## file_picked] fires with the chosen absolute path.
func open(file_name := "") -> void:
	var dir := start_dir()
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var mode := DisplayServer.FILE_DIALOG_MODE_SAVE_FILE if _save_mode else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
		var err := DisplayServer.file_dialog_show(_title, dir, file_name, false, mode, _filters, _on_native_picked)
		if err == OK:
			return
		push_warning("MenuFilePicker: system file picker failed (%s), using the in-game dialog" % error_string(err))
	var dialog := fallback_dialog()
	dialog.current_dir = dir
	if _save_mode:
		dialog.current_file = file_name
	dialog.popup_centered()


## Folder the picker opens in: the last one used for this purpose, else Documents.
func start_dir() -> String:
	var saved: String = InputSettings.get_saved_import_dir(_purpose)
	if not saved.is_empty() and DirAccess.dir_exists_absolute(saved):
		return saved
	var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	return documents if not documents.is_empty() else OS.get_environment("HOME")


## The in-game dialog, created on first use. It lives under the root window so
## it keeps the default theme at a readable size instead of inheriting the
## menu's large fonts, and is freed when the host leaves the tree.
func fallback_dialog() -> FileDialog:
	if _dialog == null:
		_dialog = make_fallback_dialog(is_embedded_run())
		_dialog.file_selected.connect(_on_picked)
		_host.get_tree().root.add_child(_dialog)
	return _dialog


func make_fallback_dialog(embedded_run: bool) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = _title
	dialog.mode_overrides_title = false
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if _save_mode else FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = _filters
	dialog.use_native_dialog = false
	dialog.size = Vector2i(1100, 720)
	if embedded_run:
		# Single line, clipped: an autowrapping label would inflate the dialog's
		# minimum height before its width is known.
		var note := Label.new()
		note.name = "EmbeddedNote"
		note.text = EMBEDDED_NOTE
		note.clip_text = true
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dialog.get_vbox().add_child(note)
	return dialog


## True when the editor launched the game embedded in its Game tab, whose
## display server has no native dialogs.
static func is_embedded_run() -> bool:
	return DisplayServer.get_name() == "embedded" or OS.get_cmdline_args().has("--embedded")


func _on_native_picked(status: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if status and not paths.is_empty():
		_on_picked(paths[0])


func _on_picked(path: String) -> void:
	InputSettings.save_import_dir(_purpose, path.get_base_dir())
	file_picked.emit(path)


func _free_dialog() -> void:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null
