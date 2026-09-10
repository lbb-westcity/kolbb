extends Node2D
const Battle = preload("res://scripts/battle.gd")
const Cpu = preload("res://scripts/cpu.gd")
const Arena = preload("res://scripts/arena.gd")
const Sound = preload("res://scripts/audio.gd")
const Rollback = preload("res://scripts/rollback.gd")
const DEFAULT_KEYS = [KEY_W,KEY_S,KEY_A,KEY_D,KEY_J,KEY_K,KEY_U,KEY_I,KEY_SPACE,KEY_O]
const WINDOW_SIZES = [Vector2i(1920,1080),Vector2i(2560,1440)]
const KEY_NAMES = ["上","下","左","右","轻拳 A","轻脚 B","重拳 C","重脚 D","翻滚","MAX"]
var battle = Battle.new()
var cpu = Cpu.new()
var arena
var audio
var rollback
var ui: Control
var theme: Theme
var screen: String = "home"
var return_screen: String = "home"
var moves_page: int = 0
var selected: int = 0
var opponent: int = 1
var difficulty: int = 1
var settings: Dictionary = {"master":80,"music":60,"sfx":80,"shake":true,"flash":false,"fullscreen":false,"window_size":0,"server":"49.235.23.27","keys":DEFAULT_KEYS.duplicate()}
var config = ConfigFile.new()
var rebind: int = -1
var key_button: Button
var paused: bool = false
var resume_left: float = 0
var online: bool = false
var waiting: float = 0
var gap_ticks: int = 0
var result_sent: bool = false
var result_wait: float = 0
var verified_result: bool = false
var tests_demo: bool = false
var auto_cpu = Cpu.new()
var notice: String = ""
var stats: Dictionary = {"wins":0,"matches":0,"best_combo":0,"perfect":0}
var deferred_events: Array = []
var quit_after: int = -1

func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		var result: Error=Net.host()
		if result!=OK: printerr("Cannot bind UDP 7000: ",result);get_tree().quit(1)
		set_process(false);set_physics_process(false)
		return
	load_settings()
	setup_menu_input()
	theme=Theme.new();theme.default_font=load("res://assets/ui/NotoSansCJKsc-Regular.otf");theme.default_font_size=16
	var normal=StyleBoxFlat.new();normal.bg_color=Color("172735");normal.border_color=Color("46616a");normal.set_border_width_all(1);normal.content_margin_left=12;normal.content_margin_right=12
	var focus=StyleBoxFlat.new();focus.bg_color=Color("233d4c");focus.border_color=Color("45cbd1");focus.set_border_width_all(2)
	for type in ["Button","OptionButton","LineEdit"]:
		theme.set_stylebox("normal",type,normal)
		theme.set_stylebox("hover",type,focus)
		theme.set_stylebox("focus",type,focus)
		theme.set_stylebox("pressed",type,focus)
		theme.set_color("font_color",type,Color("f0e7d5"))
		theme.set_color("font_hover_color",type,Color("ffd166"))
	arena=Arena.new();arena.battle=battle;arena.settings=settings;add_child(arena)
	audio=Sound.new();add_child(audio);audio.configure(settings)
	ui=Control.new();ui.size=Vector2(640,360);ui.theme=theme;add_child(ui)
	Net.room_changed.connect(_room_changed)
	Net.match_started.connect(_online_start)
	Net.input_received.connect(_remote_input)
	Net.failed.connect(_network_failed)
	Net.result_confirmed.connect(func(_data): verified_result=true)
	var args=OS.get_cmdline_user_args()
	if "--verify-assets" in args:
		var valid: bool=audio.clips.size()==39 and arena.textures.size()==36 and arena.portrait.size()==2 and arena.framesets.size()==2 and arena.animated_props!=null
		print("Asset check: ","PASS" if valid else "FAIL"," / audio ",audio.clips.size()," / atlases ",arena.textures.size())
		get_tree().quit(0 if valid else 1)
		return
	show_home()
	if "--demo" in args:
		tests_demo=true;start_local()
	if "--capture" in args:
		var k: int=args.find("--capture")
		capture_later(args[k+1] if k+1<args.size() else "res://build/screenshot.png")

func load_settings() -> void:
	config.load("user://settings.cfg")
	for key in settings:
		var value=config.get_value("settings",key,settings[key])
		if key in ["master","music","sfx"]: settings[key]=clampi(int(value),0,100)
		elif key=="window_size": settings[key]=clampi(int(value),0,WINDOW_SIZES.size()-1)
		elif key=="keys":
			if value is Array and value.size()==10:
				var valid: bool=true
				var unique: Array=[]
				for code in value:
					if code in unique or not valid_key(int(code)): valid=false
					unique.append(code)
				if valid: settings.keys=value
		else: settings[key]=value
	for key in stats: stats[key]=int(config.get_value("stats",key,0))
	apply_display()
func save_settings() -> void:
	for key in settings: config.set_value("settings",key,settings[key])
	for key in stats: config.set_value("stats",key,stats[key])
	var err: Error=config.save("user://settings.cfg")
	if err!=OK: notice="设置保存失败：%s" % error_string(err)
func setup_menu_input() -> void:
	for action in ["ui_up","ui_down","ui_left","ui_right"]:
		var index: int=["ui_up","ui_down","ui_left","ui_right"].find(action)
		var event=InputEventKey.new();event.physical_keycode=[KEY_W,KEY_S,KEY_A,KEY_D][index]
		InputMap.action_add_event(action,event)
func valid_key(code: int) -> bool:
	return (code>=KEY_SPACE and code<=KEY_ASCIITILDE) or code in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_SHIFT,KEY_TAB]

func clear_ui() -> void:
	for child in ui.get_children(): ui.remove_child(child);child.queue_free()
	rebind=-1
func text_label(text: String,pos: Vector2,size: int=16,color: Color=Color("f0e7d5"),width: int=580) -> Label:
	var l=Label.new();l.text=text;l.position=pos;l.size.x=width;l.add_theme_font_size_override("font_size",size);l.add_theme_color_override("font_color",color);ui.add_child(l);return l
func shade(rect: Rect2,alpha: float=.96) -> void:
	var p=ColorRect.new();p.color=Color(.035,.065,.095,alpha);p.position=rect.position;p.size=rect.size;p.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(p)
func button(text: String,pos: Vector2,callback: Callable,width: int=240) -> Button:
	var b=Button.new();b.text=text;b.position=pos;b.size=Vector2(width,34);b.alignment=HORIZONTAL_ALIGNMENT_LEFT;b.add_theme_font_size_override("font_size",18);ui.add_child(b)
	b.pressed.connect(func(): audio.sound("confirm");callback.call())
	b.focus_entered.connect(func(): audio.sound("move"))
	return b
func focus_first() -> void:
	for child in ui.get_children():
		if child is Button or child is OptionButton or child is LineEdit: child.grab_focus();return
func header(title: String,subtitle: String="") -> void:
	shade(Rect2(16,12,608,336),.97)
	text_label(title,Vector2(32,21),24)
	if subtitle!="": text_label(subtitle,Vector2(32,58),12,Color("8b9a9f"))
func back_button(callback: Callable) -> void:
	button("← 返回",Vector2(32,301),callback,120)

func show_home() -> void:
	if Net.connected or Net.connecting: Net.disconnect_room()
	screen="home";paused=false;online=false;arena.online=false;arena.hud=false;arena.demo=true
	battle.reset();battle.state.phase="fight"
	battle.state.fighters[0].x=392*256;battle.state.fighters[1].x=538*256
	arena.reset_effects();clear_ui();audio.pause_music(false);audio.play_music("menu")
	shade(Rect2(0,0,317,360),.95)
	text_label("AFTER HOURS / 01",Vector2(30,24),12,Color("45cbd1"))
	text_label("KOLBB",Vector2(26,42),48)
	text_label("今天的班，就上到这里。",Vector2(30,112),16,Color("8b9a9f"))
	button("单机对战",Vector2(30,153),show_select)
	button("互联网对战",Vector2(30,193),show_network)
	button("出招表",Vector2(30,233),func(): show_moves("home"),113)
	button("设置",Vector2(155,233),func(): show_settings("home"),115)
	button("退出",Vector2(30,273),func(): get_tree().quit())
	text_label("WASD / 方向键选择    ENTER 确认",Vector2(30,326),11,Color("8b9a9f"))
	text_label("RajerWei",Vector2(338,313),14,Color("45cbd1"),140)
	text_label("JU GUAI",Vector2(509,313),14,Color("f29646"),125)
	focus_first()
func show_select() -> void:
	screen="select";clear_ui();header("选择你的下班方式","两名角色 · 允许镜像 · 99 秒 · 三局两胜")
	text_label("你的角色",Vector2(34,86),16)
	var p=OptionButton.new();p.position=Vector2(32,116);p.size=Vector2(270,34);p.add_item("RajerWei · 远程控场");p.add_item("JU GUAI · 近身压制");p.selected=selected;ui.add_child(p);p.item_selected.connect(func(i): selected=i)
	text_label("CPU 角色",Vector2(332,86),16)
	var enemy=OptionButton.new();enemy.position=Vector2(332,116);enemy.size=Vector2(270,34);enemy.add_item("RajerWei");enemy.add_item("JU GUAI");enemy.selected=opponent;ui.add_child(enemy);enemy.item_selected.connect(func(i): opponent=i)
	text_label("难度",Vector2(34,169),16)
	var level=OptionButton.new();level.position=Vector2(106,165);level.size=Vector2(196,34)
	for title in ["简单 · 慢半拍的同事","普通 · 正常营业","困难 · 下班阻击战"]: level.add_item(title)
	level.selected=difficulty;ui.add_child(level);level.item_selected.connect(func(i): difficulty=i)
	text_label("移动 WASD   拳 J / U   脚 K / I\n按后防御 · 空格翻滚 · O 爆气\n必杀需要方向指令，出招表可随时查阅。",Vector2(34,214),14,Color("8b9a9f"))
	button("出招表",Vector2(332,165),func(): show_moves("select"),270)
	back_button(show_home)
	button("开始对战 →",Vector2(332,295),start_local,270)
	p.grab_focus()
func start_local() -> void:
	online=false;paused=false;resume_left=0;screen="fight";clear_ui()
	battle.reset([selected,opponent],randi_range(1,2147483646))
	cpu=Cpu.new();cpu.level=difficulty;cpu.seed_value=battle.state.rng
	auto_cpu=Cpu.new();auto_cpu.level=2
	arena.battle=battle;arena.hud=true;arena.demo=false;arena.online=false;arena.reset_effects();arena.status="CPU / "+["简单","普通","困难"][difficulty]
	audio.play_music("battle");audio.pause_music(false)

func show_moves(origin: String, page: int = -1) -> void:
	return_screen=origin;screen="moves";clear_ui()
	moves_page=page if page>=0 else selected
	if page<0 and origin=="pause":
		moves_page=battle.state.fighters[Net.slot if online else 0].char
	var accent: Color=[Color("45cbd1"),Color("f29646"),Color("ffd166")][moves_page]
	shade(Rect2(16,10,608,340),.99)
	text_label("出招表",Vector2(30,14),24)
	text_label("← → 切页  /  %02d · 03" % (moves_page+1),Vector2(421,25),12,Color("8b9a9f"),190)
	var tabs: Array=[]
	for i in 3:
		var tab=button(["RajerWei","JU GUAI","共通操作"][i],Vector2(30+i*196,51),func(): show_moves(origin,i),188)
		tab.add_theme_font_size_override("font_size",14)
		tab.alignment=HORIZONTAL_ALIGNMENT_CENTER
		if i==moves_page:
			var active=StyleBoxFlat.new();active.bg_color=Color("233d4c");active.border_color=accent
			active.border_width_bottom=3
			tab.add_theme_stylebox_override("normal",active)
			tab.add_theme_color_override("font_color",accent)
		tabs.append(tab)
	if moves_page<2:
		var portrait=TextureRect.new();portrait.texture=arena.portrait[moves_page]
		portrait.position=Vector2(70,94);portrait.size=Vector2(72,72)
		portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(portrait)
		text_label(["远程控场 / 食物博弈","近身压制 / 指令抓取"][moves_page],Vector2(30,174),12,accent,162)
		text_label(["用飞行道具控制距离，\n召唤落地，抢回主动。","用积分逼近对手，\n面谈压制，近身抓取。"][moves_page],Vector2(30,197),11,Color("f0e7d5"),162)
		text_label("MAX 接触取消",Vector2(30,240),11,Color("ffd166"),162)
		text_label(["大便投掷 ↔ 肯德基挚友","积分投掷 ↔ 绩效面谈"][moves_page],Vector2(30,258),11,Color("f0e7d5"),162)
		var inputs: Array=["↓ →  + A/C","↓ ←  + A/C","→ ↓  + B/D" if moves_page==0 else "→ ↓ ←  + B/D","↓ → ↓ →  + A/C"]
		var notes: Array=["飞行道具 · 命中糊脸","汉堡：自己 +200\n对手 −200","召唤击飞 · 三片披萨\n自己每片 +50","超必杀 · 前冲抓取"] if moves_page==0 else ["飞行道具 · 命中大笑","气泡 + 文件夹 · 两段打击","近身指令投 · 不可拆投","超必杀 · 五波文件，可防御"]
		for i in 4:
			var move: Dictionary=battle.moves["P%d-%s" % [moves_page+1,["S1","S2","S3","U1"][i]]]
			var y: int=94+i*48
			var card=ColorRect.new();card.position=Vector2(202,y);card.size=Vector2(408,44)
			card.color=Color("10202b");card.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(card)
			var stripe=ColorRect.new();stripe.position=Vector2(202,y);stripe.size=Vector2(2,44)
			stripe.color=Color("ffd166") if i==3 else accent;stripe.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(stripe)
			text_label(move.name,Vector2(214,y+1),15,Color("ffd166") if i==3 else Color("f0e7d5"),190)
			var cost=text_label("%d 能量" % move.cost if move.cost>0 else "无消耗",Vector2(535,y+3),11,Color("ffd166") if move.cost>0 else Color("8b9a9f"),64)
			cost.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
			text_label(inputs[i],Vector2(214,y+23),12,accent,196)
			var note=text_label(notes[i],Vector2(412,y+5),10,Color("aab5b7"),120)
			note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			note.size=Vector2(120,34)
	else:
		moves_common()
	text_label("方向依次按，可按住再加键；朝左时左右反转。  A / C = 轻拳 / 重拳    B / D = 轻脚 / 重脚",Vector2(30,291),11,Color("8b9a9f"),580)
	button("← 返回",Vector2(30,313),func(): return_to(origin),120)
	for i in 4:
		var key: String=OS.get_keycode_string(settings.keys[4+i])
		text_label(["A 轻拳","B 轻脚","C 重拳","D 重脚"][i]+"  ["+key+"]",Vector2(166+i*112,322),11,Color("f0e7d5"),110)
	tabs[moves_page].grab_focus()

func moves_common() -> void:
	text_label("01  移动与防守",Vector2(30,95),14,Color("45cbd1"),280)
	text_label("后：站防   /   下后：蹲防\n上轻点 / 按住：小跳 / 普通跳\n前前：跑   /   后后：后撤\n跑中上 / 下后上：大跳",Vector2(30,119),12,Color("f0e7d5"),280)
	text_label("02  攻击与普通投",Vector2(30,207),14,Color("45cbd1"),280)
	text_label("下 + 攻击：蹲攻击；空中 + 攻击：跳攻击\n近身前 / 后 + C：普通投\n受抓 7 帧内 C / D：拆普通投",Vector2(30,231),12,Color("f0e7d5"),280)
	text_label("03  翻滚与 MAX",Vector2(330,95),14,Color("ffd166"),280)
	var roll_key: String=OS.get_keycode_string(settings.keys[8])
	var max_key: String=OS.get_keycode_string(settings.keys[9])
	text_label("%s 或 A+B：翻滚，仍会被抓\n%s 或 B+C：MAX，消耗 100 能量\n重拳 / 重脚命中后快速 MAX：200 能量\nMAX 内超必杀：再花 100 并清空 MAX" % [roll_key,max_key],Vector2(330,119),12,Color("f0e7d5"),280)
	text_label("04  实战提示",Vector2(330,207),14,Color("ffd166"),280)
	text_label("先用轻拳确认命中，再试 下、前 + 重拳。\n普通攻击无防御削血；必杀削血不会 KO。\n食物只由物主获益，别误吃对手的汉堡。",Vector2(330,231),12,Color("f0e7d5"),280)
func return_to(origin: String) -> void:
	match origin:
		"select": show_select()
		"pause": show_pause()
		"room": show_room()
		_: show_home()

func show_settings(origin: String) -> void:
	return_screen=origin;screen="settings";clear_ui();header("设置","音量、显示与按键自动保存；按键冲突时交换绑定")
	var scroll=ScrollContainer.new();scroll.position=Vector2(32,80);scroll.size=Vector2(570,210);ui.add_child(scroll)
	var rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",10);scroll.add_child(rows)
	for pair in [["主音量","master"],["音乐","music"],["音效","sfx"]]:
		var row=HBoxContainer.new();rows.add_child(row)
		var name_label=Label.new();name_label.text=pair[0];name_label.custom_minimum_size.x=105;row.add_child(name_label)
		var slider=HSlider.new();slider.min_value=0;slider.max_value=100;slider.step=5;slider.value=settings[pair[1]];slider.custom_minimum_size=Vector2(310,24);row.add_child(slider)
		var value_label=Label.new();value_label.text=str(slider.value);row.add_child(value_label)
		slider.value_changed.connect(func(v): settings[pair[1]]=int(v);value_label.text=str(int(v));audio.configure(settings);save_settings())
	var display_row=HBoxContainer.new();rows.add_child(display_row)
	var display_label=Label.new();display_label.text="窗口分辨率";display_label.custom_minimum_size.x=105;display_row.add_child(display_label)
	var resolution=OptionButton.new();resolution.custom_minimum_size=Vector2(350,30)
	resolution.add_item("1920 × 1080  ·  Full HD");resolution.add_item("2560 × 1440  ·  2K")
	resolution.selected=settings.window_size;resolution.disabled=settings.fullscreen;display_row.add_child(resolution)
	resolution.item_selected.connect(func(index): settings.window_size=index;apply_display();save_settings())
	var display_hint=Label.new();display_hint.text="全屏使用屏幕原生分辨率；画面保持整数缩放。";display_hint.add_theme_font_size_override("font_size",12);rows.add_child(display_hint)
	for pair in [["全屏","fullscreen"],["震屏","shake"],["减少闪光","flash"]]:
		var check=CheckButton.new();check.text=pair[0];check.button_pressed=settings[pair[1]];rows.add_child(check)
		check.toggled.connect(func(value): settings[pair[1]]=value;apply_display();resolution.disabled=settings.fullscreen;save_settings())
	for i in 10:
		var key=Button.new();key.text=KEY_NAMES[i]+"    "+OS.get_keycode_string(settings.keys[i]);key.alignment=HORIZONTAL_ALIGNMENT_LEFT;rows.add_child(key)
		key.pressed.connect(func(): rebind=i;key_button=key;key.text=KEY_NAMES[i]+"    请按新键（Esc 取消）")
	var defaults=Button.new();defaults.text="恢复默认键位";rows.add_child(defaults)
	defaults.pressed.connect(func(): settings.keys=DEFAULT_KEYS.duplicate();save_settings();show_settings(origin))
	back_button(func(): return_to(origin));focus_first()
func apply_display() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not settings.fullscreen:
		DisplayServer.window_set_size(WINDOW_SIZES[settings.window_size])

func show_pause() -> void:
	if not online: paused=true;audio.pause_music(true)
	screen="pause";clear_ui();header("对局菜单" if online else "暂停","对局仍在继续；菜单打开时你的输入保持中立。" if online else "准备好后继续，恢复前有 3 秒倒计时。")
	button("继续对战",Vector2(196,100),resume_battle)
	button("出招表",Vector2(196,147),func(): show_moves("pause"))
	button("设置",Vector2(196,194),func(): show_settings("pause"))
	button("退出对局",Vector2(196,241),func():
		if online: Net.disconnect_room()
		show_home())
	focus_first()
func resume_battle() -> void:
	clear_ui();screen="fight"
	if online: return
	resume_left=3;paused=true
	text_label("3",Vector2(299,150),40)
func show_result() -> void:
	if screen=="result": return
	screen="result";clear_ui()
	var winner: int=battle.state.winner
	var title: String="DRAW" if winner<0 else Battle.NAMES[battle.state.fighters[winner].char]+" 获胜"
	header(title,"%d : %d   ·   %s" % [battle.state.wins[0],battle.state.wins[1],"好友对战" if online else "单机对战"])
	if not online:
		stats.matches+=1
		if winner==0:
			stats.wins+=1
			if battle.state.fighters[0].hp==1000: stats.perfect+=1
		save_settings()
	text_label("下班成功。" if winner==(Net.slot if online else 0) else "再来一局，把场子找回来。",Vector2(32,110),20,Color("ffd166"))
	text_label("累计胜场 %d   最佳连击 %d   完美终局 %d" % [stats.wins,stats.best_combo,stats.perfect],Vector2(32,156),16)
	button("再战",Vector2(196,208),func():
		if online: show_room();Net.set_ready(true)
		else: start_local())
	button("重新选人",Vector2(196,249),func():
		if online: show_room()
		else: show_select())
	back_button(func():
		if online: Net.disconnect_room()
		show_home())
	focus_first()

func show_network() -> void:
	screen="network";clear_ui();header("互联网好友对战","无需账号 · 六位房间码 · 通过房间服务器连接")
	text_label("服务器地址",Vector2(32,91),16)
	var host=LineEdit.new();host.position=Vector2(180,86);host.size=Vector2(410,34);host.text=settings.server;host.placeholder_text="公网 IP 或域名（本机测试用 127.0.0.1）";ui.add_child(host)
	text_label("房间码",Vector2(32,147),16)
	var code=LineEdit.new();code.position=Vector2(180,142);code.size=Vector2(410,34);code.max_length=6;code.placeholder_text="输入好友的六位房间码";ui.add_child(code)
	code.text_changed.connect(func(value):
		var cleaned: String=""
		for c in value.to_upper():
			if c in Net.ALPHABET: cleaned+=c
		if code.text!=cleaned: code.text=cleaned;code.caret_column=cleaned.length())
	button("创建房间",Vector2(32,202),func(): settings.server=host.text.strip_edges();save_settings();notice="正在连接服务器…";Net.connect_room(settings.server);show_connecting(),265)
	button("加入房间",Vector2(327,202),func():
		if code.text.length()!=6: code.placeholder_text="需要六位房间码";code.grab_focus();return
		settings.server=host.text.strip_edges();save_settings();notice="正在连接服务器…";Net.connect_room(settings.server,code.text);show_connecting(),265)
	if notice!="":
		var l=text_label(notice,Vector2(32,248),14,Color("f29646"),555);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	back_button(show_home);host.grab_focus()
func show_connecting() -> void:
	clear_ui();header("连接中",notice);back_button(func(): Net.disconnect_room();show_network())
func _room_changed(_data: Dictionary) -> void:
	if screen!="fight" and screen!="pause" and screen!="result": show_room()
func show_room() -> void:
	screen="room";clear_ui();header("房间  "+Net.room_code,"将房间码发给好友。双方准备后进入对战。")
	var r: Dictionary=Net.room
	for i in 2:
		var x: int=32+i*300
		text_label("玩家 %d%s" % [i+1," · 你" if i==Net.slot else ""],Vector2(x,93),18)
		if i<r.get("chars",[]).size():
			text_label(Battle.NAMES[r.chars[i]],Vector2(x,129),22,Color("45cbd1") if i==0 else Color("f29646"))
			text_label("已准备" if r.ready[i] else "未准备",Vector2(x,172),16)
		else: text_label("等待好友加入…",Vector2(x,135),16,Color("8b9a9f"))
	button("切换角色",Vector2(32,225),func(): Net.set_character(1-r.chars[Net.slot]),265)
	button("取消准备" if r.ready[Net.slot] else "准备",Vector2(332,225),func(): Net.set_ready(not r.ready[Net.slot]),265)
	back_button(func(): Net.disconnect_room();show_network());focus_first()
func _online_start(info: Dictionary) -> void:
	online=true;paused=false;screen="fight";clear_ui();waiting=0;result_wait=0;result_sent=false;verified_result=false;deferred_events.clear()
	rollback=Rollback.new();rollback.start(info.chars,info.seed,info.match,info.slot);battle=rollback.battle
	arena.battle=battle;arena.hud=true;arena.demo=false;arena.online=true;arena.reset_effects();audio.play_music("battle");audio.pause_music(false)
func _remote_input(pairs: Array, ack: int) -> void:
	if online and rollback:
		var before: int=rollback.rollback_count
		rollback.receive(pairs,ack)
		if rollback.rollback_count!=before:
			arena.fx.clear();deferred_events.clear()
func _network_failed(reason: String) -> void:
	online=false;paused=false;notice=reason;arena.hud=false;arena.online=false;audio.play_music("menu");show_network()

func input_bits() -> int:
	if screen!="fight" or resume_left>0: return 0
	var bits: int=0
	for i in 10:
		if Input.is_physical_key_pressed(settings.keys[i]): bits|=1<<i
	return bits
func _physics_process(dt: float) -> void:
	if not arena: return
	if online:
		if rollback.error!="": Net.abort(rollback.error);return
		arena.confirmed=rollback.confirmed
		arena.status="等待网络" if not rollback.can_advance() else str(Net.ping_ms)+" ms"
		if not rollback.can_advance():
			waiting+=dt
			if waiting>5: Net.abort("连接中断，本场无结果");return
		else: waiting=0
		var start: int=Time.get_ticks_usec()
		var ev: Array=rollback.tick(input_bits()) if battle.state.phase!="done" else []
		arena.performance_us=Time.get_ticks_usec()-start
		for e in ev:
			if e.kind in ["ko","time","victory","round","fight"]: deferred_events.append(e)
			else: arena.present([e],audio)
		for e in deferred_events.duplicate():
			if int(e.id.split("/")[1])-1<=rollback.confirmed:
				arena.present([e],audio);deferred_events.erase(e)
		Net.send_inputs(rollback.batch(),rollback.remote_high)
		gap_ticks+=1
		if gap_ticks>=3 and rollback.remote_high<rollback.cursor+2:
			Net.request_gap(rollback.remote_high+1,rollback.cursor+2);gap_ticks=0
		for n in rollback.checksums:
			if n<=rollback.confirmed and (n+1)%60==0: Net.report_hash(n,rollback.checksums[n])
		if battle.state.phase=="done":
			if not result_sent and rollback.confirmed>=rollback.cursor-1:
				Net.report_result(rollback.cursor-1,battle.checksum(),battle.state.wins,battle.state.winner);result_sent=true
			result_wait+=dt
			if verified_result: show_result()
			elif result_wait>5: Net.abort("结果确认超时，本场无结果")
	elif screen=="fight" and not paused:
		var start: int=Time.get_ticks_usec()
		var bits: int=auto_cpu.sample(battle,0) if tests_demo else input_bits()
		var ev: Array=battle.step([bits,cpu.sample(battle,1)])
		arena.performance_us=Time.get_ticks_usec()-start
		arena.present(ev,audio)
		stats.best_combo=maxi(stats.best_combo,arena.combo_hits[1])
		if battle.state.phase=="done": show_result()
	if screen=="fight" or online: audio.urgent(battle.state.time<=1200 and battle.state.phase=="fight")
func _process(dt: float) -> void:
	if not arena: return
	if resume_left>0:
		resume_left=maxf(0,resume_left-dt)
		for child in ui.get_children():
			if child is Label: child.text=str(ceili(resume_left))
		if resume_left==0: paused=false;clear_ui();audio.pause_music(false)
	arena.animate(dt,paused and not online)
func _input(event: InputEvent) -> void:
	if not arena: return
	if event is InputEventKey and event.pressed and not event.echo:
		if rebind>=0:
			if event.keycode==KEY_ESCAPE: key_button.text=KEY_NAMES[rebind]+"    "+OS.get_keycode_string(settings.keys[rebind]);rebind=-1
			elif not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and valid_key(event.physical_keycode):
				var old: int=settings.keys[rebind]
				var conflict: int=settings.keys.find(event.physical_keycode)
				if conflict>=0: settings.keys[conflict]=old
				settings.keys[rebind]=event.physical_keycode;save_settings();show_settings(return_screen)
			get_viewport().set_input_as_handled();return
		if screen=="moves" and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
			var direction: int=1 if event.is_action_pressed("ui_right") else -1
			audio.sound("move");show_moves(return_screen,posmod(moves_page+direction,3))
			get_viewport().set_input_as_handled();return
		if event.keycode==KEY_F3: arena.debug=not arena.debug
		if event.keycode==KEY_ESCAPE:
			if screen=="fight": show_pause()
			elif screen=="pause": resume_battle()
			elif screen in ["moves","settings"]: return_to(return_screen)
			elif screen=="room": Net.disconnect_room();show_network()
			elif screen!="home": show_home()
			get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and arena and screen=="fight" and not tests_demo:
		resume_left=0;show_pause()
func capture_later(path: String) -> void:
	await get_tree().create_timer(4).timeout
	await RenderingServer.frame_post_draw
	var image: Image=get_viewport().get_texture().get_image()
	image.save_png(path)
	print("Captured ",path)
