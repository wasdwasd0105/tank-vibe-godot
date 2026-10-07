class_name DebugFreeze
extends Node
## Debug toggle bound to "\" (see Game._unhandled_key_input): stops the whole
## enemy side and every loose object in place, while the players keep playing.
##
## Frozen: enemy tanks, the enemy spawner, enemy shots, mines, fire and blasts,
## power-ups, and short-lived explosion/spawn effects.
## Left running: player tanks and anything a player fired, laid or lit. Anything
## created while frozen can only have been caused by a player, so it runs too.
##
## Frozen objects stay in the physics world: frozen tanks are still solid and
## can be shot, frozen shots can still be hit or driven into, and frozen
## power-ups can still be collected. They just stop acting on their own.

const FROZEN_TINT := Color(0.62, 0.82, 1.0)
const BANNER_TEXT := "DEBUG FREEZE   ·   press \\ to resume"
const BANNER_LAYER := 50  # under the pause menu (layer 100)

## Effects with no owner that are frozen as part of the scene snapshot.
const EFFECT_SCRIPTS: PackedStringArray = [
	"res://scripts/effects/explosion.gd",
	"res://scripts/effects/spawn_effect.gd",
]

var frozen: bool = false

var _level_manager: LevelManager
var _saved: Dictionary = {}  # frozen Node -> the state _thaw puts back
var _banner: CanvasLayer


func setup(level_manager: LevelManager) -> void:
	_level_manager = level_manager


func _ready() -> void:
	_banner = _build_banner()
	add_child(_banner)


func _exit_tree() -> void:
	# The scene is going away with everything in it, so there is nothing to thaw.
	_saved.clear()


func toggle() -> void:
	set_frozen(not frozen)


func set_frozen(value: bool) -> void:
	if value == frozen:
		return
	frozen = value
	if frozen:
		_freeze_tree(get_parent())
	else:
		# Untyped on purpose: a player may have destroyed some of these while they
		# were frozen, and a freed object cannot even be assigned to a Node variable.
		for node in _saved:
			if is_instance_valid(node):
				_thaw(node, _saved[node])
		_saved.clear()
	_banner.visible = frozen


# =====================================================================
# Freezing
# =====================================================================

func _freeze_tree(node: Node) -> void:
	for child: Node in node.get_children():
		if child == self or child is PlayerTank:
			continue
		if _should_freeze(child):
			_freeze(child)  # its children stop with it
		else:
			_freeze_tree(child)


func _should_freeze(node: Node) -> bool:
	if node is EnemyTank or node is EnemySpawner or node is Cookie or node is SpawnBurst or node is HitEffect:
		return true
	if node is Bullet:
		return not node.is_player_bullet
	if node is GroundFire:
		return node.side == 0  # the enemies' fire; burning grass is nobody's
	if node is Mine or node is ExplosionBlast:
		return not node.from_player
	var script: Script = node.get_script()
	return script != null and script.resource_path in EFFECT_SCRIPTS


func _freeze(node: Node) -> void:
	var state := {"process_mode": node.process_mode}
	if node is CollisionObject2D:
		state["disable_mode"] = node.disable_mode
		# Must be set before disabling: the default would pull the body out of
		# the physics world, letting tanks and shots pass straight through it.
		node.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	if node is CanvasItem:
		state["modulate"] = node.modulate
		node.modulate = node.modulate * FROZEN_TINT
	# Disabling also stops the node's Timers, animations and bound tweens.
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_saved[node] = state


func _thaw(node: Node, state: Dictionary) -> void:
	node.process_mode = state["process_mode"]
	if state.has("disable_mode"):
		node.disable_mode = state["disable_mode"]
	if state.has("modulate"):
		node.modulate = state["modulate"]


# =====================================================================
# Banner
# =====================================================================

func _build_banner() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "DebugFreezeBanner"
	layer.layer = BANNER_LAYER
	layer.visible = false

	var anchor := CenterContainer.new()
	anchor.set_anchors_preset(Control.PRESET_TOP_WIDE)
	anchor.offset_top = 22.0
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(anchor)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.07, 0.12, 0.82)
	style.border_color = Color(0.45, 0.8, 1.0, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(panel)

	var label := Label.new()
	label.name = "Text"
	label.text = BANNER_TEXT
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.72, 0.9, 1.0))
	panel.add_child(label)
	return layer
