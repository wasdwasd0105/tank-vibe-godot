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
signal cookie_collected(type: int, player_id: int)  # -1: an enemy took it
signal freeze_enemies(duration: float)
signal bomb_all_enemies(player_id: int)  # -1: nobody's (the debug key)
signal fortify_base(duration: float)
# ...and the items an enemy took, turned against the players
signal freeze_players(duration: float)
signal bomb_all_players
signal base_guard_broken
signal enemy_reinforcements(taker_type: int)

# Level
signal brick_destroyed(tile_pos: Vector2i)
