class_name PowerUp
extends Area2D

enum Type { STAR = 0, HELMET = 1, BOMB = 2, CLOCK = 3, SHOVEL = 4, TANK = 5, BOAT = 6 }

@export var type: Type = Type.STAR

var _blink_timer: float = 0.0
var _lifetime: float = 0.0
const DESPAWN_TIME: float = 15.0

const TYPE_COLORS: Dictionary = {
	Type.STAR:    Color(1.0, 0.0, 0.0),     # Red
	Type.HELMET:  Color(1.0, 1.0, 1.0),     # White
	Type.BOMB:    Color(1.0, 0.5, 0.0),     # Orange
	Type.CLOCK:   Color(0.0, 0.8, 0.8),     # Cyan
	Type.SHOVEL:  Color(0.6, 0.4, 0.2),     # Brown
	Type.TANK:    Color(0.0, 1.0, 0.0),     # Green
	Type.BOAT:    Color(0.3, 0.3, 1.0),     # Blue
}

func _ready() -> void:
	type = randi() % Type.size() as Type
	add_to_group("powerups")
	body_entered.connect(_on_body_entered)
	# Set collision
	set_collision_layer_value(7, true)  # powerups layer
	set_collision_mask_value(3, true)   # player tanks
	# Update visual
	if has_node("Sprite2D"):
		$Sprite2D.modulate = TYPE_COLORS[type]

func _process(delta: float) -> void:
	_blink_timer += delta
	visible = fmod(_blink_timer, 0.3) < 0.2

	_lifetime += delta
	if _lifetime > DESPAWN_TIME:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerTank:
		Events.powerup_collected.emit(type, body.player_id)
		_apply_effect(body)
		queue_free()

func _apply_effect(player: PlayerTank) -> void:
	match type:
		Type.STAR:
			player.apply_powerup(Type.STAR)
		Type.HELMET:
			player.apply_powerup(Type.HELMET)
		Type.BOMB:
			Events.bomb_all_enemies.emit()
		Type.CLOCK:
			Events.freeze_enemies.emit(10.0)
		Type.SHOVEL:
			Events.fortify_base.emit(20.0)
		Type.TANK:
			player.apply_powerup(Type.TANK)
		Type.BOAT:
			player.apply_powerup(Type.BOAT)
