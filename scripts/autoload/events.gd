extends Node

# Tank events
signal player_hit(player_id: int)
signal player_died(player_id: int)
signal enemy_destroyed(enemy: Node2D, points: int)
signal all_enemies_defeated

# Game flow
signal stage_started(stage_num: int)
signal stage_cleared
signal game_over
signal base_destroyed
signal player_joined(player_id: int)

# Cookies
signal cookie_spawned(cookie: Node2D)
signal cookie_collected(type: int, player_id: int)
signal freeze_enemies(duration: float)
signal bomb_all_enemies
signal fortify_base(duration: float)

# Level
signal brick_destroyed(tile_pos: Vector2i)
