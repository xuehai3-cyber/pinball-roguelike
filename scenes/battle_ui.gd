extends Control

@onready var label: Label = $Label
@onready var atk_btn: Button = $AttackBtn
@onready var blk_btn: Button = $BlockBtn
@onready var p1_sprite: AnimatedSprite2D = $P1Sprite
@onready var p2_sprite: AnimatedSprite2D = $P2Sprite
@onready var p1_status_label: Label = $"P1Status"
@onready var p2_status_label: Label = $"P2Status"

var p1_hp_segs: Array[TextureRect] = []
var p2_hp_segs: Array[TextureRect] = []
var hp_full_tex: Texture2D
var hp_empty_tex: Texture2D

const P1_FAR_X := 640.0
const P1_CLOSE_X := 1100.0
const P2_FAR_X := 1920.0
const P2_CLOSE_X := 1460.0
const Y_POS := 900.0
const COUNTDOWN_SECS := 5.0
const FADE_TIME := 0.08
const HITSTOP_DURATION := 0.06
const SHAKE_INTENSITY := 24.0
const SHAKE_STEPS := 10
const LABEL_FONT_SIZE := 48
const P1_IMPACT := 28   # 链女命中帧 (27-30取中)
const P2_IMPACT := 14   # 棒球男命中帧 (12-17取中)
const HURT_FPS := 14.0
const P1_SCALE := 1.0
const P2_SCALE := 1.3
const P2_HURT_SCALE := 1.0
const HP_BAR_W := 1050
const HP_BAR_H := 150
const FONT_CN := preload("res://assets/simhei.ttf")
const PORT := 9000
var is_host: bool = false
var is_networked: bool = false
var my_role: int = 0  # 1 or 2, assigned on connect
var local_ready: bool = false
var remote_ready: bool = false

enum State { WAITING, COUNTDOWN, TELEPORT_IN, IMPACT, ANIMATE, SHOWING, TELEPORT_OUT, GAME_OVER }

var state: State = State.WAITING
var countdown: float = COUNTDOWN_SECS
var p1_choice: String = ""
var p2_choice: String = ""
var p1_press_time: float = 0.0
var p2_press_time: float = 0.0
var p1_anim_done: bool = false
var p2_anim_done: bool = false

# 对战状态
const MAX_HP := 3
const MAX_BLOCKS := 3
const MAX_ROUNDS := 5
const BASE_DAMAGE: float = 1.0

var p1_hp: int = MAX_HP
var p2_hp: int = MAX_HP
var p1_blocks: int = MAX_BLOCKS
var p2_blocks: int = MAX_BLOCKS
var round_num: int = 1
var result_text: String = ""


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)

	_setup_sprite(p1_sprite, "res://assets/p1_idle/", 20, "res://assets/p1_attack/", 34, 48.0, "res://assets/p1_hurt/", 26, true, P1_SCALE)
	_setup_sprite(p2_sprite, "res://assets/p2_idle/", 20, "res://assets/p2_attack/", 20, 24.0, "res://assets/p2_hurt/", 20, false, P2_SCALE)

	p1_sprite.position = Vector2(P1_FAR_X, Y_POS)
	p2_sprite.position = Vector2(P2_FAR_X, Y_POS)

	p1_sprite.animation_finished.connect(_on_p1_anim_finished)
	p2_sprite.animation_finished.connect(_on_p2_anim_finished)

	atk_btn.text = "Q\n攻击"
	blk_btn.text = "W\n格挡"

	_add_breathe(atk_btn, -8)
	_add_breathe(blk_btn, -8)

	label.text = "按空格开始"

	# 加载中文字体
	label.add_theme_font_override("font", FONT_CN)
	atk_btn.add_theme_font_override("font", FONT_CN)
	atk_btn.add_theme_font_size_override("font_size", 32)
	blk_btn.add_theme_font_override("font", FONT_CN)
	blk_btn.add_theme_font_size_override("font_size", 32)

	_create_hp_bars()
	_auto_host()


func _create_hp_bars() -> void:
	hp_full_tex = load("res://assets/hp_full.png") as Texture2D
	hp_empty_tex = load("res://assets/hp_empty.png") as Texture2D

	const BAR_Y := 100.0
	p1_hp_segs = _build_hp_bar(Vector2(80, BAR_Y))
	p2_hp_segs = _build_hp_bar(Vector2(2560 - 80 - HP_BAR_W, BAR_Y))
	_update_status_labels()
	_update_hp_segments(p1_hp_segs, p1_hp)
	_update_hp_segments(p2_hp_segs, p2_hp)



# ========== 联网函数 ==========

func _auto_host() -> void:
	# 检查 URL 参数 ?join=IP:PORT，有就自动加入
	var join_arg := OS.get_cmdline_user_args()
	for arg in join_arg:
		if arg.begins_with("--join=") or arg.begins_with("-j="):
			var ip := arg.split("=")[1]
			_join_game(ip)
			return
	# 网页版从 URL 参数读取
	if OS.has_feature("web"):
		var js_join: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('join')", true)
		if js_join and str(js_join) != "null" and str(js_join) != "":
			_join_game(str(js_join))
			return
	# 默认：创建房间
	if OS.has_feature("web"):
		_join_game()
		return
	_host_game()

func _show_setup_screen() -> void:
	pass

func _hide_battle_ui() -> void:
	pass

func _show_battle_ui() -> void:
	pass

func _host_game() -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		label.text = "创建房间失败"
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	is_host = true
	is_networked = true
	my_role = 1  # 房主固定 P1
	_update_button_labels()
	var ip_list := IP.get_local_addresses()
	var local_ip := "127.0.0.1"
	for ip in ip_list:
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			local_ip = ip
			break
	label.text = "等待对手加入...
本机 IP: %s" % local_ip

func _join_game(addr: String = "127.0.0.1:9000") -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var url := "ws://" + addr
	var err := peer.create_client(url)
	if err != OK:
		label.text = "连接失败"
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	label.text = "正在连接..."

func _on_peer_connected(id: int) -> void:
	label.text = "你是 P%d
%s

按空格准备" % [my_role, _role_keys()]
	_show_battle_ui_impl()

func _on_connected_ok() -> void:
	is_networked = true
	my_role = 2
	_update_button_labels()
	label.text = "你是 P%d
%s

按空格准备" % [my_role, _role_keys()]
	_show_battle_ui_impl()

func _on_connection_failed() -> void:
	is_networked = false
	multiplayer.multiplayer_peer = null
	label.text = "连接失败"

func _on_peer_disconnected(id: int) -> void:
	is_networked = false
	multiplayer.multiplayer_peer = null
	label.text = "对手断开连接"

func _role_keys() -> String:
	return "Q/W = 攻击/格挡" if my_role == 1 else "O/P = 攻击/格挡"

func _update_button_labels() -> void:
	if my_role == 1:
		atk_btn.text = "Q
攻击"
		blk_btn.text = "W
格挡"
	else:
		atk_btn.text = "O
攻击"
		blk_btn.text = "P
格挡"

@rpc("authority", "reliable")
func _rpc_assign_role(role: int) -> void:
	my_role = role
	_update_button_labels()

func _ready_up() -> void:
	if local_ready:
		return
	local_ready = true
	rpc("_rpc_ready")
	if remote_ready:
		_start_round()
		if is_host:
			rpc("_rpc_start_round")
	else:
		label.text = "等待对手准备..."

@rpc("any_peer", "reliable")
func _rpc_ready() -> void:
	remote_ready = true
	if local_ready:
		_start_round()
		if is_host:
			rpc("_rpc_start_round")

func _reset_network() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_host = false
	is_networked = false
	my_role = 0
	local_ready = false
	remote_ready = false
	_auto_host()

func _show_battle_ui_impl() -> void:
	atk_btn.visible = true
	blk_btn.visible = true


func _update_status_labels() -> void:
	var sudden := round_num >= 4
	var b1 := "%d" % p1_blocks if not sudden else "—"
	var b2 := "%d" % p2_blocks if not sudden else "—"
	p1_status_label.text = "P1  HP:%d  格挡:%s" % [p1_hp, b1]
	p2_status_label.text = "HP:%d  格挡:%s  P2" % [p2_hp, b2]

func _build_hp_bar(pos: Vector2) -> Array[TextureRect]:
	var segs: Array[TextureRect] = []
	var seg_w := HP_BAR_W / 3.0
	for i in 3:
		var seg := TextureRect.new()
		seg.size = Vector2(seg_w, HP_BAR_H)
		seg.position = Vector2(pos.x + i * seg_w, pos.y)
		seg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		seg.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(seg)
		segs.append(seg)
	return segs


func _make_atlas(tex: Texture2D, i: int) -> AtlasTexture:
	var seg_w := float(tex.get_width()) / 3.0
	var seg_h := float(tex.get_height())
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(i * seg_w, 0, seg_w, seg_h)
	return atlas


func _update_hp_segments(segs: Array[TextureRect], hp: int) -> void:
	var red_count := ceili(float(hp) / MAX_HP * 3)
	for i in 3:
		if i < red_count:
			segs[i].texture = _make_atlas(hp_full_tex, i)
		else:
			segs[i].texture = _make_atlas(hp_empty_tex, i)


func _setup_sprite(sprite: AnimatedSprite2D,
		idle_dir: String, idle_count: int,
		atk_dir: String, atk_count: int, atk_spd: float,
		hurt_dir: String, hurt_count: int,
		flip: bool, scl: float) -> void:
	var frames := SpriteFrames.new()

	_load_frames(frames, "idle", idle_dir, idle_count, 10.0, true)
	_load_frames(frames, "attack", atk_dir, atk_count, atk_spd, false)
	_load_frames(frames, "hurt", hurt_dir, hurt_count, HURT_FPS, false)

	sprite.sprite_frames = frames
	sprite.flip_h = flip
	sprite.scale = Vector2(scl, scl)
	sprite.play("idle")


func _load_frames(frames: SpriteFrames, anim_name: String, dir: String, count: int, spd: float, loop: bool) -> void:
	frames.add_animation(anim_name)
	for i in range(1, count + 1):
		var tex := load(dir + "%03d.png" % i) as Texture2D
		frames.add_frame(anim_name, tex)
	frames.set_animation_speed(anim_name, spd)
	frames.set_animation_loop(anim_name, loop)


func _start_round() -> void:
	if round_num > MAX_ROUNDS or p1_hp <= 0 or p2_hp <= 0:
		_show_game_over()
		return

	local_ready = false
	remote_ready = false
	state = State.COUNTDOWN
	countdown = COUNTDOWN_SECS
	p1_choice = ""
	p2_choice = ""
	p1_press_time = 0.0
	p2_press_time = 0.0
	p1_anim_done = false
	p2_anim_done = false

	p1_sprite.stop()
	p2_sprite.stop()
	p1_sprite.play("idle")
	p2_sprite.play("idle")
	p1_sprite.scale = Vector2(P1_SCALE, P1_SCALE)
	p2_sprite.scale = Vector2(P2_SCALE, P2_SCALE)
	p1_sprite.position.x = P1_FAR_X
	p2_sprite.position.x = P2_FAR_X
	p1_sprite.modulate.a = 1.0
	p2_sprite.modulate.a = 1.0

	label.text = "第%d/%d回合\n5.000" % [round_num, MAX_ROUNDS]


func _hp_text() -> String:
	var sudden := round_num >= 4
	var b1 := "%d" % p1_blocks if not sudden else "—"
	var b2 := "%d" % p2_blocks if not sudden else "—"
	return "P1 HP:%d 格挡:%s    P2 HP:%d 格挡:%s" % [p1_hp, b1, p2_hp, b2]


func _reset_game() -> void:
	p1_hp = MAX_HP
	p2_hp = MAX_HP
	p1_blocks = MAX_BLOCKS
	p2_blocks = MAX_BLOCKS
	round_num = 1
	result_text = ""
	_update_hp_segments(p1_hp_segs, p1_hp)
	_update_hp_segments(p2_hp_segs, p2_hp)
	_update_status_labels()
	_start_round()


func _show_game_over() -> void:
	state = State.GAME_OVER
	var winner := ""
	if p1_hp <= 0:
		winner = "P2 获胜！"
	elif p2_hp <= 0:
		winner = "P1 获胜！"
	elif p1_hp > p2_hp:
		winner = "P1 获胜！"
	elif p2_hp > p1_hp:
		winner = "P2 获胜！"
	else:
		winner = "平局！"
	label.text = "%s\n按空格重新开始" % winner


func _process(delta: float) -> void:
	if state != State.COUNTDOWN:
		return

	countdown -= delta
	if countdown <= 0:
		countdown = 0
		label.text = "第%d/%d回合\n0" % [round_num, MAX_ROUNDS]
		_resolve_round()
		return

	var sec := int(countdown)
	var frac := int((countdown - sec) * 1000)
	label.text = "第%d/%d回合\n%d.%03d" % [round_num, MAX_ROUNDS, sec, frac]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
			return

		if state == State.GAME_OVER:
			if event.keycode == KEY_SPACE:
				if is_networked and is_host:
					_reset_game()
					rpc("_rpc_start_round")
				elif not is_networked:
					_reset_game()
			return

		if state == State.SHOWING:
			if event.keycode == KEY_SPACE:
				_teleport_back()
			return

		if state == State.WAITING:
			if event.keycode == KEY_SPACE:
				if is_networked:
					_ready_up()
				else:
					_start_round()
			return

	if state != State.COUNTDOWN or countdown <= 0:
		return

	if event is InputEventKey and event.pressed:
		var can_block := countdown > 2.0 and round_num < 4

		# 联网模式：按键由 my_role 决定
		if is_networked:
			var atk_key := KEY_Q if my_role == 1 else KEY_O
			var blk_key := KEY_W if my_role == 1 else KEY_P
			if event.keycode == atk_key:
				_player_choose(0, "攻击")
			elif event.keycode == blk_key and can_block:
				var ok := (my_role == 1 and p1_blocks > 0) or (my_role == 2 and p2_blocks > 0)
				if ok:
					_player_choose(0, "格挡")
		else:
			# 本地双人
			if p1_choice == "":
				if event.keycode == KEY_Q:
					_player_choose(1, "攻击")
				elif event.keycode == KEY_W and can_block and p1_blocks > 0:
					_player_choose(1, "格挡")
			if p2_choice == "":
				if event.keycode == KEY_O:
					_player_choose(2, "攻击")
				elif event.keycode == KEY_P and can_block and p2_blocks > 0:
					_player_choose(2, "格挡")

		if event.keycode == KEY_SPACE:
			_start_round()


func _player_choose(player: int, choice: String) -> void:
	if is_networked:
		if my_role == 1:
			p1_choice = choice
			p1_press_time = countdown
		else:
			p2_choice = choice
			p2_press_time = countdown
		rpc("_rpc_send_choice", choice, countdown)
		if p1_choice != "" and p2_choice != "":
			countdown = 0
			_resolve_round()
	else:
		if player == 1:
			p1_choice = choice
			p1_press_time = countdown
		else:
			p2_choice = choice
			p2_press_time = countdown
		if p1_choice != "" and p2_choice != "":
			countdown = 0
			_resolve_round()


func _resolve_round() -> void:
	state = State.TELEPORT_IN
	label.text = ""

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p1_sprite, "modulate:a", 0.0, FADE_TIME)
	tw.tween_property(p2_sprite, "modulate:a", 0.0, FADE_TIME)
	tw.chain().tween_callback(_on_fade_out_done)


func _on_fade_out_done() -> void:
	p1_sprite.position.x = P1_CLOSE_X
	p2_sprite.position.x = P2_CLOSE_X

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p1_sprite, "modulate:a", 1.0, FADE_TIME)
	tw.tween_property(p2_sprite, "modulate:a", 1.0, FADE_TIME)
	tw.chain().tween_callback(_on_fade_in_done)


func _on_fade_in_done() -> void:
	_do_impact()


func _do_impact() -> void:
	state = State.IMPACT

	# 顿帧：冻结画面
	Engine.time_scale = 0.0
	await get_tree().create_timer(HITSTOP_DURATION, true, false, true).timeout
	Engine.time_scale = 1.0

	# 先播攻击动画，让挥刀动作跑起来
	_play_anims()

	# 按各自帧率算延迟，等命中帧到了再震屏
	if p1_choice == "攻击" or p2_choice == "攻击":
		var delay := 0.0
		if p1_choice == "攻击":
			delay = max(delay, P1_IMPACT / 48.0)
		if p2_choice == "攻击":
			delay = max(delay, P2_IMPACT / 24.0)
		await get_tree().create_timer(delay).timeout

		# 对攻 = 重击震（闷响），其他 = 普通屏震
		if p1_choice == "攻击" and p2_choice == "攻击":
			_heavy_shake()
		else:
			_screen_shake()

		# 挨打闪白+抖动
		if p1_choice == "攻击" and p2_choice != "格挡" and p2_choice != "攻击":
			_flash_sprite(p2_sprite, Color(4, 4, 4))
			_shake_sprite(p2_sprite)
		if p2_choice == "攻击" and p1_choice != "格挡" and p1_choice != "攻击":
			_flash_sprite(p1_sprite, Color(4, 4, 4))
			_shake_sprite(p1_sprite)

		# 格挡闪蓝
		if p1_choice == "攻击" and p2_choice == "格挡":
			_flash_sprite(p2_sprite, Color(2, 2, 5))
		if p2_choice == "攻击" and p1_choice == "格挡":
			_flash_sprite(p1_sprite, Color(2, 2, 5))


func _flash_sprite(sprite: AnimatedSprite2D, flash_color: Color) -> void:
	var tw := create_tween()
	for _i in 3:
		tw.tween_property(sprite, "modulate", flash_color, 0.06)
		tw.tween_property(sprite, "modulate", Color.WHITE, 0.08)


func _shake_sprite(sprite: AnimatedSprite2D) -> void:
	var orig := sprite.position
	var tw := create_tween()
	for i in 6:
		var decay := 1.0 - float(i) / 6
		var offset := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0 * decay
		tw.tween_property(sprite, "position", orig + offset, 0.02)
	tw.tween_property(sprite, "position", orig, 0.04)


func _heavy_shake() -> void:
	var orig := position
	var tw := create_tween()
	# 单次大冲撞 + 快速衰减
	tw.tween_property(self, "position", orig + Vector2(0, -18), 0.03)
	tw.tween_property(self, "position", orig + Vector2(0, 10), 0.05)
	tw.tween_property(self, "position", orig + Vector2(0, -6), 0.06)
	tw.tween_property(self, "position", orig + Vector2(0, 3), 0.08)
	tw.tween_property(self, "position", orig, 0.10)


func _screen_shake() -> void:
	var orig := position
	var tw := create_tween()
	for i in SHAKE_STEPS:
		var decay := 1.0 - float(i) / SHAKE_STEPS
		var offset := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * SHAKE_INTENSITY * decay
		tw.tween_property(self, "position", orig + offset, 0.02)
	tw.tween_property(self, "position", orig, 0.04)


func _play_anims() -> void:
	state = State.ANIMATE
	p1_anim_done = false
	p2_anim_done = false

	var p1_anim := "idle"
	var p2_anim := "idle"

	# P1 攻击：对方不格挡不对攻就挨打
	if p1_choice == "攻击":
		p1_anim = "attack"
		if p2_choice != "格挡" and p2_choice != "攻击":
			p2_anim = "hurt"

	# P2 攻击：对方不格挡不对攻就挨打
	if p2_choice == "攻击":
		p2_anim = "attack"
		if p1_choice != "格挡" and p1_choice != "攻击":
			p1_anim = "hurt"

	p1_sprite.stop()
	p2_sprite.stop()
	p1_sprite.play(p1_anim)
	p2_sprite.play(p2_anim)

	# P2 挨打时缩小
	if p2_anim == "hurt":
		p2_sprite.scale = Vector2(P2_HURT_SCALE, P2_HURT_SCALE)
	else:
		p2_sprite.scale = Vector2(P2_SCALE, P2_SCALE)

	if p1_anim == "idle":
		p1_anim_done = true
	if p2_anim == "idle":
		p2_anim_done = true

	if p1_anim_done and p2_anim_done:
		_on_both_anims_done()


func _on_both_anims_done() -> void:
	_judge_round()
	if state == State.GAME_OVER:
		return
	state = State.SHOWING
	label.text = "%s\n按空格继续" % result_text


func _on_p1_anim_finished() -> void:
	p1_anim_done = true
	if p2_anim_done:
		_on_both_anims_done()


func _on_p2_anim_finished() -> void:
	p2_anim_done = true
	if p1_anim_done:
		_on_both_anims_done()


func _teleport_back() -> void:
	state = State.TELEPORT_OUT

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p1_sprite, "modulate:a", 0.0, FADE_TIME)
	tw.tween_property(p2_sprite, "modulate:a", 0.0, FADE_TIME)
	tw.chain().tween_callback(_on_teleport_back_done)


func _on_teleport_back_done() -> void:
	p1_sprite.position.x = P1_FAR_X
	p2_sprite.position.x = P2_FAR_X
	p1_sprite.modulate.a = 1.0
	p2_sprite.modulate.a = 1.0
	p1_sprite.stop()
	p2_sprite.stop()
	p1_sprite.play("idle")
	p2_sprite.play("idle")
	p1_sprite.scale = Vector2(P1_SCALE, P1_SCALE)
	p2_sprite.scale = Vector2(P2_SCALE, P2_SCALE)
	state = State.WAITING
	if is_networked and is_host:
		label.text = "按空格开始"
	elif is_networked:
		label.text = "等待房主开始..."
	else:
		label.text = "按空格开始"


func _calc_mult(press_time: float) -> float:
	if press_time <= 0:
		return 2.0
	return lerpf(0.3, 2.0, 1.0 - press_time / COUNTDOWN_SECS)


func _judge_round() -> void:
	var p1m := _calc_mult(p1_press_time) if p1_choice != "" else 0.0
	var p2m := _calc_mult(p2_press_time) if p2_choice != "" else 0.0
	var d1 := 0.0
	var d2 := 0.0

	if p1_choice == "攻击" and p2_choice == "攻击":
		if p1_press_time <= p2_press_time:
			d1 = BASE_DAMAGE * p1m * 1.3
			d2 = BASE_DAMAGE * p2m * 0.7
		else:
			d1 = BASE_DAMAGE * p1m * 0.7
			d2 = BASE_DAMAGE * p2m * 1.3
		result_text = "双方对攻！"

	elif p1_choice == "攻击" and p2_choice == "格挡":
		d1 = BASE_DAMAGE * p1m * 0.5
		d2 = 0.0
		p2_blocks -= 1
		result_text = "P2 格挡反弹！"

	elif p1_choice == "攻击" and p2_choice == "":
		d2 = BASE_DAMAGE * p1m
		result_text = "P1 攻击命中！"

	elif p1_choice == "格挡" and p2_choice == "攻击":
		d2 = BASE_DAMAGE * p2m * 0.5
		d1 = 0.0
		p1_blocks -= 1
		result_text = "P1 格挡反弹！"

	elif p1_choice == "" and p2_choice == "攻击":
		d1 = BASE_DAMAGE * p2m
		result_text = "P2 攻击命中！"

	elif p1_choice == "" and p2_choice == "":
		result_text = "双方观望…"

	else:
		result_text = "双方防守"

	p1_hp -= ceili(d1)
	p2_hp -= ceili(d2)
	p1_hp = max(p1_hp, 0)
	p2_hp = max(p2_hp, 0)
	_update_hp_segments(p1_hp_segs, p1_hp)
	_update_hp_segments(p2_hp_segs, p2_hp)
	_update_status_labels()
	round_num += 1

	if p1_hp <= 0 or p2_hp <= 0 or round_num > MAX_ROUNDS:
		_show_game_over()


func _add_breathe(btn: Button, offset_y: float) -> void:
	var tw := create_tween()
	tw.set_loops()
	var base_y := btn.position.y
	tw.tween_property(btn, "position:y", base_y + offset_y, 0.8) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(btn, "position:y", base_y, 0.8) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


# ========== RPC 函数 ==========

@rpc("any_peer", "reliable")
func _rpc_send_choice(choice: String, press_time: float) -> void:
	var slot := 2 if my_role == 1 else 1
	if slot == 1:
		p1_choice = choice
		p1_press_time = press_time
	else:
		p2_choice = choice
		p2_press_time = press_time
	if p1_choice != "" and p2_choice != "":
		countdown = 0
		_resolve_round()

@rpc("authority", "reliable")
func _rpc_start_round() -> void:
	if not is_host:
		_start_round()
