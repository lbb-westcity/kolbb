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
		var valid: bool=audio.clips.size()==42 and arena.textures.size()==56 and arena.portrait.size()==Battle.NAMES.size() and arena.framesets.size()==Battle.NAMES.size() and arena.animated_props!=null and arena.littleblack_fx.size()==4
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
	resume_left=0;arena.countdown=0;arena.resume_fight_left=0
	for child in ui.get_children(): ui.remove_child(child);child.queue_free()
	arena.bg=load("res://assets/stage/menu-office.png" if screen in ["home","select"] else "res://assets/stage/office.png")
	arena.character_select=screen=="select"
	rebind=-1
func text_label(text: String,pos: Vector2,size: int=16,color: Color=Color("f0e7d5"),width: int=580) -> Label:
	var l=Label.new();l.text=text;l.position=pos;l.add_theme_font_size_override("font_size",size);l.add_theme_color_override("font_color",color);ui.add_child(l);l.reset_size();l.size.x=width;return l
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

func home_button(title: String,index: int,callback: Callable) -> Button:
	var b=button(title,Vector2(30,156+index*29),callback,186)
	b.size.y=27;b.add_theme_font_size_override("font_size",16)
	var font=FontVariation.new();font.base_font=theme.default_font;font.variation_embolden=.6;b.add_theme_font_override("font",font)
	var empty=StyleBoxEmpty.new();empty.content_margin_left=26;empty.content_margin_right=24
	for state in ["normal","hover","pressed","focus"]: b.add_theme_stylebox_override(state,empty)
	b.add_theme_color_override("font_color",Color("899ba8") if index==4 else Color("fff3d9"))
	for state in ["font_focus_color","font_hover_color","font_pressed_color"]: b.add_theme_color_override(state,Color("071827"))
	var highlight=Polygon2D.new();highlight.color=Color("22d9ee");highlight.show_behind_parent=true
	highlight.polygon=PackedVector2Array([Vector2(0,0),Vector2(174,0),Vector2(186,12),Vector2(186,27),Vector2(0,27)])
	highlight.visible=false;b.add_child(highlight)
	var accent=Polygon2D.new();accent.color=Color("ff791f")
	accent.polygon=PackedVector2Array([Vector2(178,0),Vector2(183,0),Vector2(194,11),Vector2(189,11)])
	highlight.add_child(accent)
	var arrow=Polygon2D.new();arrow.color=Color("ff791f")
	arrow.polygon=PackedVector2Array([Vector2(8,8),Vector2(17,13),Vector2(8,19)])
	highlight.add_child(arrow)
	var number=Label.new();number.text="%02d" % (index+1);number.position=Vector2(159,5)
	number.add_theme_font_size_override("font_size",11);number.add_theme_color_override("font_color",Color("899ba8"))
	number.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(number)
	b.focus_entered.connect(func(): highlight.show();number.add_theme_color_override("font_color",Color("071827")))
	b.focus_exited.connect(func(): highlight.hide();number.add_theme_color_override("font_color",Color("899ba8")))
	b.mouse_entered.connect(b.grab_focus)
	return b

func show_home() -> void:
	if Net.connected or Net.connecting: Net.disconnect_room()
	screen="home";paused=false;online=false;arena.online=false;arena.hud=false;arena.demo=true
	battle.reset();battle.state.phase="fight"
	battle.state.fighters[0].x=358*256;battle.state.fighters[1].x=531*256
	arena.reset_effects();clear_ui();audio.pause_music(false);audio.play_music("menu")
	text_label("A F T E R  H O U R S  /  01",Vector2(30,24),9,Color("66e4e9"),190)
	var rule=ColorRect.new();rule.position=Vector2(181,32);rule.size=Vector2(43,1);rule.color=Color("66e4e9")
	rule.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(rule)
	var logo=TextureRect.new();logo.name="Logo";logo.texture=preload("res://assets/ui/kolbb-logo.png")
	logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position=Vector2(13,29);logo.size=Vector2(280,112);logo.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(logo)
	text_label("今天的班，就上到这里。",Vector2(30,123),15,Color("fff3d9"),260)
	var buttons: Array[Button]=[
		home_button("单机对战",0,show_select),
		home_button("互联网对战",1,show_network),
		home_button("出招表",2,func(): show_moves("home")),
		home_button("设置",3,func(): show_settings("home")),
		home_button("退出",4,func(): get_tree().quit())]
	for i in buttons.size():
		var previous: NodePath=buttons[i].get_path_to(buttons[posmod(i-1,buttons.size())])
		var next: NodePath=buttons[i].get_path_to(buttons[(i+1)%buttons.size()])
		buttons[i].focus_neighbor_top=previous;buttons[i].focus_neighbor_left=previous;buttons[i].focus_previous=previous
		buttons[i].focus_neighbor_bottom=next;buttons[i].focus_neighbor_right=next;buttons[i].focus_next=next
	text_label("—  RajerWei  —",Vector2(302,306),11,Color("45cbd1"),130).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	text_label("—  JU GUAI  —",Vector2(478,306),11,Color("ff791f"),120).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	focus_first()
func select_card(slot: int,character: int) -> Button:
	var accent=Color("22d9ee") if slot==0 else Color("ff791f")
	var chosen: bool=character==(selected if slot==0 else opponent)
	var b=button(Battle.NAMES[character],Vector2(76+slot*288+character*65,237),func():
		if slot==0: selected=character
		else: opponent=character
		show_select(slot*3+character),60)
	b.name="Character%d_%d" % [slot,character];b.toggle_mode=true;b.button_pressed=chosen
	b.alignment=HORIZONTAL_ALIGNMENT_CENTER;b.add_theme_font_size_override("font_size",9)
	b.tooltip_text=("你的角色：" if slot==0 else "对手角色：")+Battle.NAMES[character]
	var normal=StyleBoxFlat.new();normal.bg_color=Color("091b29");normal.border_color=Color("4b738a");normal.set_border_width_all(1)
	normal.content_margin_left=1;normal.content_margin_right=1;normal.content_margin_top=40;normal.content_margin_bottom=2
	var active=normal.duplicate();active.bg_color=Color("123347");active.border_color=accent;active.set_border_width_all(2)
	var focus=StyleBoxFlat.new();focus.draw_center=false;focus.border_color=Color("fff3d9");focus.set_border_width_all(1);focus.expand_margin_left=2;focus.expand_margin_right=2;focus.expand_margin_top=2;focus.expand_margin_bottom=2
	b.add_theme_stylebox_override("normal",normal);b.add_theme_stylebox_override("hover",active)
	b.add_theme_stylebox_override("pressed",active);b.add_theme_stylebox_override("hover_pressed",active);b.add_theme_stylebox_override("focus",focus)
	b.size=Vector2(60,54)
	var portrait=TextureRect.new();portrait.texture=arena.portrait[character];portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.position=Vector2(3,3);portrait.size=Vector2(54,36)
	portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(portrait)
	if chosen:
		var badge=Label.new();badge.text="1P" if slot==0 else "CPU";badge.position=Vector2(2,1);badge.add_theme_font_size_override("font_size",8)
		badge.add_theme_color_override("font_color",Color("061522"));badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var fill=StyleBoxFlat.new();fill.bg_color=accent;fill.content_margin_left=3;fill.content_margin_right=3
		badge.add_theme_stylebox_override("normal",fill);b.add_child(badge)
	return b

func show_select(focus_card: int=-1) -> void:
	screen="select";paused=false;online=false;clear_ui()
	battle.reset([selected,opponent]);battle.state.phase="fight"
	arena.hud=false;arena.demo=true;arena.online=false;arena.reset_effects();audio.play_music("menu");audio.pause_music(false)
	var ivory=Color("fff3d9");var orange=Color("ff791f");var cyan=Color("22d9ee")
	var bold=FontVariation.new();bold.base_font=theme.default_font;bold.variation_embolden=1.2
	var logo=TextureRect.new();logo.texture=preload("res://assets/ui/kolbb-logo.png")
	logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position=Vector2(16,6);logo.size=Vector2(110,48);logo.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(logo)
	text_label("选择你的下班方式",Vector2(173,21),32,orange,300).add_theme_font_override("font",bold)
	text_label("选择你的下班方式",Vector2(172,19),32,ivory,300).add_theme_font_override("font",bold)
	text_label("C H A R A C T E R   S E L E C T",Vector2(242,62),8,ivory,200)
	moves_panel(Rect2(214,68,22,1),orange,orange);moves_panel(Rect2(414,68,22,1),orange,orange)
	text_label("允许镜像 / 99 秒 / 三局两胜",Vector2(488,29),9,ivory,146)
	moves_panel(Rect2(488,44,126,1),orange,orange)
	for slot in 2:
		var character: int=selected if slot==0 else opponent
		var accent: Color=cyan if slot==0 else orange
		var x: int=64 if slot==0 else 475
		moves_panel(Rect2(x,91,101,17),accent,accent)
		text_label("1P / 你的角色" if slot==0 else "CPU / 对手角色",Vector2(x+6,91),11,Color("061522"),99).add_theme_font_override("font",bold)
		var name_label=text_label(Battle.NAMES[character],Vector2(x,113),22 if character!=2 else 20,ivory,158)
		name_label.add_theme_font_override("font",bold)
		var role_label=text_label(["远程控场","近身压制","节奏突进"][character],Vector2(x+7,143),12,accent,105)
		for label in [name_label,role_label]:
			label.add_theme_color_override("font_shadow_color",Color("061522"));label.add_theme_constant_override("shadow_offset_x",1);label.add_theme_constant_override("shadow_offset_y",1)
		moves_panel(Rect2(x,164,90,1),accent,accent)
	text_label("VS",Vector2(300,148),40,orange,80).add_theme_font_override("font",bold)
	text_label("VS",Vector2(298,145),40,ivory,80).add_theme_font_override("font",bold)
	moves_panel(Rect2(72,233,198,62),Color("081724"),Color("081724"))
	moves_panel(Rect2(360,233,198,62),Color("081724"),Color("081724"))
	var cards: Array[Button]=[]
	for slot in 2:
		for character in Battle.NAMES.size(): cards.append(select_card(slot,character))
	text_label("CPU 难度",Vector2(74,308),11,ivory,56)
	var level=OptionButton.new();level.name="Difficulty";level.position=Vector2(130,303);level.add_theme_font_size_override("font_size",11)
	for title in ["简单 · 慢半拍的同事","普通 · 正常营业","困难 · 下班阻击战"]: level.add_item(title)
	level.fit_to_longest_item=false;level.selected=difficulty;ui.add_child(level);level.size=Vector2(137,26)
	level.item_selected.connect(func(i): difficulty=i)
	var moves=button("出招表",Vector2(278,303),func(): show_moves("select"),80);moves.name="SelectMoves"
	moves.add_theme_font_size_override("font_size",13);moves.size.y=26;moves.alignment=HORIZONTAL_ALIGNMENT_CENTER
	var start=button("开始对战  →",Vector2(372,300),start_local,194);start.name="StartBattle"
	start.add_theme_font_override("font",bold);start.add_theme_font_size_override("font_size",19);start.size.y=31;start.alignment=HORIZONTAL_ALIGNMENT_CENTER
	var active=StyleBoxFlat.new();active.bg_color=orange;active.border_color=Color("ffba80");active.set_border_width_all(1)
	start.add_theme_stylebox_override("normal",active)
	var focused=active.duplicate();focused.bg_color=Color("ff9b50");focused.border_color=ivory;focused.set_border_width_all(2)
	for state in ["hover","pressed","focus"]: start.add_theme_stylebox_override(state,focused)
	for state in ["font_color","font_focus_color","font_hover_color","font_pressed_color"]: start.add_theme_color_override(state,Color("061522"))
	var back=button("← 返回",Vector2(24,333),show_home,70);back.add_theme_font_size_override("font_size",11);back.size.y=20
	back.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	for i in cards.size():
		cards[i].focus_neighbor_left=cards[i].get_path_to(cards[posmod(i-1,cards.size())])
		cards[i].focus_neighbor_right=cards[i].get_path_to(cards[(i+1)%cards.size()])
		cards[i].focus_neighbor_bottom=cards[i].get_path_to(level if i<3 else start)
	level.focus_neighbor_top=level.get_path_to(cards[selected]);moves.focus_neighbor_top=moves.get_path_to(cards[selected])
	start.focus_neighbor_top=start.get_path_to(cards[3+opponent])
	cards[selected if focus_card<0 else focus_card].grab_focus()
func start_local() -> void:
	online=false;paused=false;resume_left=0;screen="fight";clear_ui()
	battle.reset([selected,opponent],randi_range(1,2147483646))
	cpu=Cpu.new();cpu.level=difficulty;cpu.seed_value=battle.state.rng
	auto_cpu=Cpu.new();auto_cpu.level=2
	arena.battle=battle;arena.hud=true;arena.demo=false;arena.online=false;arena.reset_effects();arena.status="CPU / "+["简单","普通","困难"][difficulty]
	audio.play_music("battle");audio.pause_music(false)

func moves_panel(rect: Rect2,fill: Color,border: Color) -> Panel:
	var panel=Panel.new();panel.position=rect.position;panel.size=rect.size
	var style=StyleBoxFlat.new();style.bg_color=fill;style.border_color=border;style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel",style);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(panel)
	return panel

func moves_keycap(text: String,pos: Vector2,width: int=24,color: Color=Color("f0e7d5"),height: int=20,font_size: int=12) -> Label:
	var key=text_label(text,pos,font_size,color,width)
	key.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;key.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var style=StyleBoxFlat.new();style.bg_color=Color("081a29");style.border_color=color.darkened(.35)
	style.set_border_width_all(1);style.set_corner_radius_all(2)
	key.add_theme_stylebox_override("normal",style);key.reset_size();key.size=Vector2(width,height)
	return key

func show_moves(origin: String, page: int = -1) -> void:
	return_screen=origin;screen="moves";clear_ui()
	moves_page=page if page>=0 else selected
	if page<0 and origin=="pause":
		moves_page=battle.state.fighters[Net.slot if online else 0].char
	var cyan=Color("35d8eb");var gold=Color("ffd166");var muted=Color("9dbed5")
	var bold=FontVariation.new();bold.base_font=theme.default_font;bold.variation_embolden=.5
	shade(Rect2(0,0,640,360),.28)
	moves_panel(Rect2(24,8,592,344),Color("061522"),Color("3c617c"))
	var logo=TextureRect.new();logo.texture=preload("res://assets/ui/kolbb-logo.png")
	logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position=Vector2(32,17);logo.size=Vector2(84,28);logo.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(logo)
	text_label("出招表",Vector2(137,9),28,Color("fff3d9"),114).add_theme_font_override("font",bold)
	text_label("MOVE LIST",Vector2(253,27),13,Color("668eac"),115)
	text_label("← → 切换角色",Vector2(435,24),11,muted,105)
	text_label("%02d / 04" % (moves_page+1),Vector2(545,19),17,Color("ff791f"),62)
	var tabs: Array=[]
	for i in Battle.NAMES.size()+1:
		var tab=button((Battle.NAMES+["共通操作"])[i],Vector2(34+i*145,51),func(): show_moves(origin,i),137)
		tab.size.y=24;tab.add_theme_font_size_override("font_size",13);tab.alignment=HORIZONTAL_ALIGNMENT_CENTER
		var style=StyleBoxFlat.new();style.bg_color=Color("ff791f") if i==moves_page else Color("0c2032")
		style.border_color=Color("ffb16c") if i==moves_page else Color("416781");style.set_border_width_all(1)
		tab.add_theme_stylebox_override("normal",style)
		var focused=style.duplicate();focused.border_color=Color("fff3d9");focused.set_border_width_all(1)
		for state in ["hover","focus","pressed"]: tab.add_theme_stylebox_override(state,focused)
		for state in ["font_color","font_focus_color","font_hover_color","font_pressed_color"]:
			tab.add_theme_color_override(state,Color("071827") if i==moves_page else muted)
		tabs.append(tab)
	if moves_page<Battle.NAMES.size():
		moves_panel(Rect2(34,83,136,234),Color("081b2a"),Color("294b63"))
		var portrait=TextureRect.new();portrait.name="MovePortrait"
		portrait.texture=load("res://assets/ui/%s-movelist-v2.png" % Battle.ART[moves_page])
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.position=Vector2(35,84);portrait.size=Vector2(134,123)
		portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(portrait)
		text_label(Battle.NAMES[moves_page],Vector2(39,207),21 if moves_page!=2 else 19,Color("fff3d9"),128)
		text_label(["远程控场 / 食物博弈","近身压制 / 指令抓取","篮球牵制 / 节奏突进"][moves_page],Vector2(39,234),11,cyan,128)
		text_label(["用飞行道具控制距离，\n召唤落地，抢回主动。","用积分逼近对手，\n面谈压制，近身抓取。","投球牵制，肩撞逼近，\n音爆拦截空中对手。"][moves_page],Vector2(39,250),10,Color("f0e7d5"),128)
		moves_panel(Rect2(37,283,130,32),Color("091a27"),Color("a98131"))
		text_label("✦ MAX 接触取消",Vector2(43,284),10,gold,120)
		text_label(["大便投掷 ↔ 肯德基挚友","积分投掷 ↔ 绩效面谈","篮球 ↔ 铁山靠"][moves_page],Vector2(43,300),9,Color("f0e7d5"),120)
		moves_panel(Rect2(182,83,424,22),Color("0b1d2d"),Color("365b75"))
		text_label("招式 / 指令",Vector2(194,83),12,muted,200)
		text_label("招式效果",Vector2(416,83),12,muted,130)
		text_label("能量",Vector2(563,83),12,muted,38)
		var inputs: Array=["↓ → A/C","↓ ← A/C","→ ↓ ← B/D" if moves_page==1 else "→ ↓ B/D","↓ → ↓ → A/C"]
		var notes: Array=["飞行道具 · 命中糊脸","汉堡：自己 +200\n对手 −200","召唤击飞 · 三片披萨\n自己每片 +50","超必杀 · 前冲抓取"] if moves_page==0 else ["飞行道具 · 命中大笑","气泡 + 文件夹\n两段打击","近身指令投 · 不可拆投","超必杀 · 五波文件\n可防御"] if moves_page==1 else ["直线投球 · 可抵消","向前肩撞 · 可防御","向上音波 · 对空击飞","舞步四连击 · 末段倒地"]
		var ids: Array=["S1","S2","S3","U1"]
		if moves_page==2:
			ids.insert(3,"S4");inputs.insert(3,"↓ ← B/D");notes.insert(3,"甩长裤 → 短裤踢击")
		var spacing: int=40 if moves_page==2 else 49
		for i in ids.size():
			var ultimate: bool=ids[i]=="U1"
			var move: Dictionary=battle.moves["P%d-%s" % [moves_page+1,ids[i]]]
			var y: int=106+i*spacing;var height: int=spacing-4
			var row=moves_panel(Rect2(182,y,424,height),Color("2b261a") if ultimate else Color("0b2031"),Color("a98131") if ultimate else Color("25465e"))
			row.name="MoveRow"+ids[i]
			moves_panel(Rect2(182,y,3,height),gold if ultimate else cyan,gold if ultimate else cyan)
			moves_panel(Rect2(405,y+4,1,height-8),Color("365168"),Color("365168"))
			text_label(move.name,Vector2(194,y-1),11 if moves_page==2 else 14,gold if ultimate else Color("fff3e3"),204).add_theme_font_override("font",bold)
			var tokens: PackedStringArray=inputs[i].split(" ");var x: int=194
			for token in tokens:
				var attack: bool=token.contains("/")
				if attack:
					text_label("+",Vector2(x,y+height-21),12,Color("f0e7d5"),12);x+=15
				moves_keycap(token.replace("/"," / "),Vector2(x,y+height-(18 if moves_page==2 else 21)),44 if attack else 24,Color("ff791f") if token=="B/D" else cyan if attack else Color("c8ddec"),17 if moves_page==2 else 20,10 if moves_page==2 else 12)
				x+=29
			var note=text_label(notes[i],Vector2(416,y),11,Color("e1e8eb"),137)
			note.size.y=height;note.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			var cost=text_label(str(move.cost) if move.cost>0 else "无消耗",Vector2(557,y+13 if ultimate else y),15 if ultimate else 17 if move.cost>0 else 11,gold if move.cost>0 else Color("e1e8eb"),43)
			cost.size.y=height-13 if ultimate else height;cost.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;cost.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			if ultimate:
				var badge=moves_keycap("SUPER",Vector2(558,y+1),40,Color("071827"),11,7)
				var badge_style=StyleBoxFlat.new();badge_style.bg_color=gold;badge_style.set_corner_radius_all(2)
				badge.add_theme_stylebox_override("normal",badge_style);badge.reset_size();badge.size=Vector2(40,11)
		text_label("方向依次按，可按住再加键；朝左时左右反转。",Vector2(188,303),10,muted,414)
	else:
		moves_common()
	moves_panel(Rect2(34,320,572,1),Color("416781"),Color("416781"))
	var back=button("ESC  返回",Vector2(39,325),func(): return_to(origin),97)
	back.size.y=21;back.add_theme_font_size_override("font_size",12)
	for i in 4:
		var x: int=163+i*112
		moves_panel(Rect2(x-13,328,1,16),Color("294b63"),Color("294b63"))
		moves_keycap(["A","B","C","D"][i],Vector2(x,326),19,[Color("47a9ee"),Color("ff791f"),cyan,Color("f06455")][i],20)
		text_label(["轻拳","轻脚","重拳","重脚"][i],Vector2(x+25,326),11,Color("f0e7d5"),28)
		moves_keycap(OS.get_keycode_string(settings.keys[4+i]),Vector2(x+58,327),38,muted,18,10)
	tabs[moves_page].grab_focus()

func moves_common() -> void:
	var roll_key: String=OS.get_keycode_string(settings.keys[8])
	var max_key: String=OS.get_keycode_string(settings.keys[9])
	var titles=["01  移动与防守","02  攻击与普通投","03  翻滚与 MAX","04  实战提示"]
	var descriptions=["后：站防   /   下后：蹲防\n上轻点 / 按住：小跳 / 普通跳\n前前：跑   /   后后：后撤\n跑中上 / 下后上：大跳", "下 + 攻击：蹲攻击\n空中 + 攻击：跳攻击\n近身前 / 后 + C：普通投\n受抓 7 帧内 C / D：拆普通投", "%s 或 A+B：翻滚，仍会被抓\n%s 或 B+C：MAX，消耗 100 能量\n重拳 / 重脚命中后快速 MAX：200 能量\nMAX 内超必杀：本次 100，清空 MAX" % [roll_key,max_key], "先用轻拳确认命中，再试 下、前 + 重拳。\n普通攻击无防御削血。\n必杀削血不会 KO。\n食物只由物主获益，别误吃对手的汉堡。"]
	for i in 4:
		var x: int=34+(i%2)*292;var y: int=83+(i/2)*117
		var accent=Color("35d8eb") if i<2 else Color("ffd166")
		moves_panel(Rect2(x,y,280,109),Color("0b2031"),Color("294b63"))
		moves_panel(Rect2(x,y,3,23),accent,accent)
		text_label(titles[i],Vector2(x+12,y+2),14,accent,256)
		text_label(descriptions[i],Vector2(x+12,y+30),11,Color("e1e8eb"),256)
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
	arena.countdown=3;arena.queue_redraw()
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
	button("切换角色",Vector2(32,225),func(): Net.set_character((r.chars[Net.slot]+1)%Battle.NAMES.size()),265)
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
		arena.countdown=resume_left
		if resume_left==0:
			paused=false;clear_ui();audio.pause_music(false)
			arena.resume_fight_left=.5+dt
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
			audio.sound("move");show_moves(return_screen,posmod(moves_page+direction,Battle.NAMES.size()+1))
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
