extends Control

@onready var stage_label: Label = $LeftPanel/StageLabel
@onready var games_played_label: Label = $LeftPanel/GamesPlayed
@onready var p1_lives_label: Label = $LeftPanel/P1Lives
@onready var p1_score_label: Label = $LeftPanel/P1Score

@onready var enemy_count_label: Label = $RightPanel/EnemyCount
@onready var credit_label: Label = $RightPanel/CreditLabel
@onready var p2_header: Label = $RightPanel/P2Header
@onready var p2_lives_label: Label = $RightPanel/P2Lives
@onready var p2_score_label: Label = $RightPanel/P2Score
@onready var countdown_label: Label = $CountdownLabel
@onready var p1_header: Label = $LeftPanel/P1Header

# P1 stat icons + value labels
@onready var p1_hp_icon: TextureRect = $LeftPanel/P1HpIcon
@onready var p1_hp_val: Label = $LeftPanel/P1HpVal
@onready var p1_spd_icon: TextureRect = $LeftPanel/P1SpdIcon
@onready var p1_spd_val: Label = $LeftPanel/P1SpdVal
@onready var p1_wpn_icon: TextureRect = $LeftPanel/P1WpnIcon
@onready var p1_wpn_val: Label = $LeftPanel/P1WpnVal
@onready var p1_cookie_icon: TextureRect = $LeftPanel/P1CookieIcon
@onready var p1_cookie_count: Label = $LeftPanel/P1CookieCount
@onready var p1_addon_0: TextureRect = $LeftPanel/P1Addon0
@onready var p1_addon_1: TextureRect = $LeftPanel/P1Addon1

# P2 stat icons + value labels
@onready var p2_hp_icon: TextureRect = $RightPanel/P2HpIcon
@onready var p2_hp_val: Label = $RightPanel/P2HpVal
@onready var p2_spd_icon: TextureRect = $RightPanel/P2SpdIcon
@onready var p2_spd_val: Label = $RightPanel/P2SpdVal
@onready var p2_wpn_icon: TextureRect = $RightPanel/P2WpnIcon
@onready var p2_wpn_val: Label = $RightPanel/P2WpnVal
@onready var p2_cookie_icon: TextureRect = $RightPanel/P2CookieIcon
@onready var p2_cookie_count: Label = $RightPanel/P2CookieCount
@onready var p2_addon_0: TextureRect = $RightPanel/P2Addon0
@onready var p2_addon_1: TextureRect = $RightPanel/P2Addon1

var _cached_p1_weapon: String = ""
var _cached_p2_weapon: String = ""

func _ready() -> void:
	# Set static cookie icons for HP, Speed, Weapons (these never change)
	var hp_tex := CookieData.get_cookie_texture(CookieData.CookieType.HP_UP)
	var spd_tex := CookieData.get_cookie_texture(CookieData.CookieType.SPEED_UP)
	var wpn_tex := CookieData.get_cookie_texture(CookieData.CookieType.WEAPONS_UP)
	if p1_hp_icon: p1_hp_icon.texture = hp_tex
	if p1_spd_icon: p1_spd_icon.texture = spd_tex
	if p1_wpn_icon: p1_wpn_icon.texture = wpn_tex
	if p2_hp_icon: p2_hp_icon.texture = hp_tex
	if p2_spd_icon: p2_spd_icon.texture = spd_tex
	if p2_wpn_icon: p2_wpn_icon.texture = wpn_tex
	update_display()

func _process(_delta: float) -> void:
	if not is_inside_tree():
		return
	update_display()

func _get_player_hp(pid: int) -> int:
	var tree := get_tree()
	if not tree:
		return 0
	for tank in tree.get_nodes_in_group("players"):
		if tank is PlayerTank and tank.player_id == pid:
			return tank.health
	return 0  # Dead / not spawned

func _get_player_addons(pid: int) -> Array:
	var tree := get_tree()
	if not tree:
		return GameManager.player_addons[pid]
	for tank in tree.get_nodes_in_group("players"):
		if tank is PlayerTank and tank.player_id == pid:
			var addons: Array = []
			if tank.has_moon_shield:
				addons.append("moon-shield")
			if tank._current_utility_addon != "":
				addons.append(tank._current_utility_addon)
			return addons
	return GameManager.player_addons[pid]  # Fallback when tank not spawned

func _is_player_hud_hidden(pid: int) -> bool:
	if not GameManager.player_active[pid]:
		return true
	var tree := get_tree()
	if not tree:
		return true
	var game_node = tree.get_first_node_in_group("game")
	if game_node and game_node.has_method("get_player_dead_timer"):
		if game_node.get_player_dead_timer(pid) >= 15.0:
			return true
	return false

func _get_cookie_texture(weapon_type: String) -> Texture2D:
	var cookie_type: int = CookieData.WEAPON_TO_COOKIE.get(weapon_type, -1)
	if cookie_type >= 0:
		return CookieData.get_cookie_texture(cookie_type)
	return null

func _get_addon_texture(addon_name: String) -> Texture2D:
	var cookie_type: int = CookieData.ADDON_TO_COOKIE.get(addon_name, -1)
	if cookie_type >= 0:
		return CookieData.get_cookie_texture(cookie_type)
	return null

func _set_stat_row_visible(icon: TextureRect, val: Label, vis: bool) -> void:
	if icon: icon.visible = vis
	if val: val.visible = vis

func _update_player_stats(pid: int, hidden: bool,
		hp_icon: TextureRect, hp_val: Label,
		spd_icon: TextureRect, spd_val: Label,
		wpn_icon: TextureRect, wpn_val: Label,
		cookie_icon: TextureRect, cookie_count: Label,
		addon_0: TextureRect, addon_1: TextureRect,
		cached_weapon: String) -> String:
	var vis := not hidden
	# HP
	if hp_val: hp_val.text = ": " + str(_get_player_hp(pid))
	_set_stat_row_visible(hp_icon, hp_val, vis)
	# Speed
	if spd_val: spd_val.text = ": " + str(GameManager.player_speed_levels[pid])
	_set_stat_row_visible(spd_icon, spd_val, vis)
	# Weapons
	if wpn_val: wpn_val.text = ": " + str(GameManager.player_weapon_levels[pid])
	_set_stat_row_visible(wpn_icon, wpn_val, vis)
	# 2nd weapon cookie
	var wtype := GameManager.player_secondary_weapon_types[pid]
	if cookie_icon:
		if wtype != cached_weapon:
			cookie_icon.texture = _get_cookie_texture(wtype)
		cookie_icon.visible = vis
	if cookie_count:
		cookie_count.text = ": " + str(GameManager.player_secondary_weapon_counts[pid])
		cookie_count.visible = vis
	# Addon cookies (read live from tank, fallback to GameManager)
	var addons: Array = _get_player_addons(pid)
	var addon_count := addons.size() if vis else 0
	if addon_0:
		if addon_count >= 1:
			addon_0.texture = _get_addon_texture(addons[0])
			# Center: 1 icon → x=64, 2 icons → x=44
			addon_0.offset_left = 64.0 if addon_count == 1 else 44.0
			addon_0.offset_right = addon_0.offset_left + 32.0
			addon_0.visible = true
		else:
			addon_0.visible = false
	if addon_1:
		if addon_count >= 2:
			addon_1.texture = _get_addon_texture(addons[1])
			addon_1.offset_left = 84.0
			addon_1.offset_right = 116.0
			addon_1.visible = true
		else:
			addon_1.visible = false
	return wtype

func update_display() -> void:
	if stage_label:
		stage_label.text = str(GameManager.current_stage)
	if games_played_label:
		games_played_label.text = "Played: " + str(InputSettings.get_games_played())
	if enemy_count_label:
		enemy_count_label.text = str(GameManager.enemies_remaining)
	if credit_label:
		credit_label.text = "Credit: " + str(maxi(GameManager.credits, 0))

	# Player 1 info (left panel)
	var p1_hidden := _is_player_hud_hidden(0)
	if p1_header:
		p1_header.visible = not p1_hidden
	if p1_lives_label:
		p1_lives_label.text = "Lives: " + str(maxi(GameManager.player_lives[0], 0))
		p1_lives_label.visible = not p1_hidden
	_cached_p1_weapon = _update_player_stats(0, p1_hidden,
		p1_hp_icon, p1_hp_val, p1_spd_icon, p1_spd_val,
		p1_wpn_icon, p1_wpn_val, p1_cookie_icon, p1_cookie_count,
		p1_addon_0, p1_addon_1, _cached_p1_weapon)
	if p1_score_label:
		p1_score_label.text = str(GameManager.player_scores[0])
		p1_score_label.visible = not p1_hidden

	# Player 2 info (right panel)
	var p2_hidden := _is_player_hud_hidden(1)
	if p2_header:
		p2_header.visible = not p2_hidden
	if p2_lives_label:
		p2_lives_label.text = "Lives: " + str(maxi(GameManager.player_lives[1], 0))
		p2_lives_label.visible = not p2_hidden
	_cached_p2_weapon = _update_player_stats(1, p2_hidden,
		p2_hp_icon, p2_hp_val, p2_spd_icon, p2_spd_val,
		p2_wpn_icon, p2_wpn_val, p2_cookie_icon, p2_cookie_count,
		p2_addon_0, p2_addon_1, _cached_p2_weapon)
	if p2_score_label:
		p2_score_label.text = str(GameManager.player_scores[1])
		p2_score_label.visible = not p2_hidden

	# Game over countdown
	if countdown_label and get_tree():
		var game_node = get_tree().get_first_node_in_group("game")
		if game_node and game_node.has_method("get_game_over_countdown"):
			var countdown: float = game_node.get_game_over_countdown()
			if countdown >= 0:
				countdown_label.text = "REJOIN: %ds" % ceili(countdown)
				countdown_label.visible = true
			else:
				countdown_label.visible = false
		else:
			countdown_label.visible = false
