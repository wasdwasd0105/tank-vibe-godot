# Theme sounds

Drop a `.wav` here whose filename matches one in `res://assets/sounds/` and this
theme will use it instead. Anything you do not provide falls back to the shared
default set, so a theme can override one sound or all of them.

Available names: fire_primary, fire_rapid, fire_fire, fire_ap, fire_explosion,
lay_mine, explode_1, explode_2, mine_explode_1, mine_explode_2, tank_hit,
shield_absorb, bullet_clink, powerup_appear, powerup_pickup, extra_life,
bonus_reward, ui_select, player_join, stage_win, stage_lose.

For finer control, map a logical sound to arbitrary files in `theme.cfg`:

    [sounds]
    dir="sounds/"
    tank_destroyed="sounds/my_boom_a.wav,sounds/my_boom_b.wav"   ; comma = pick at random
