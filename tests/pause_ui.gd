extends SceneTree
var main
var mobile: bool=false

func _initialize() -> void: call_deferred("run")

func activate(title: String) -> void:
	var target: Button
	for child in main.ui.get_children():
		if child is Button and child.text==title: target=child
	assert(target!=null,"Missing pause action: "+title)
	var point: Vector2=main.position+target.get_rect().get_center()
	for pressed in [true,false]:
		if mobile:
			var event=InputEventScreenTouch.new();event.index=0;event.pressed=pressed;event.position=root.get_final_transform()*point
			Input.parse_input_event(event);Input.flush_buffered_events()
		else:
			var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point
			root.push_input(event,true)
	await process_frame;await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	main.arena.queue_redraw();await process_frame;RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("res://build/qa")
	root.get_texture().get_image().save_png("res://build/qa/pause-"+("wechat-" if mobile else "desktop-")+name+".png")

func run() -> void:
	main=load("res://main.tscn").instantiate();main.tests_demo=true
	mobile="--touch" in OS.get_cmdline_user_args()
	if mobile: main.mobile_validation=true
	root.add_child(main);main.start_local();main.set_physics_process(false);main.set_process(false)
	main.battle.state.phase="fight";main.battle.state.fighters[0].x=135*256;main.battle.state.fighters[1].x=505*256
	main.show_pause();await process_frame
	var snapshot: int=main.battle.checksum()
	assert(main.paused and main.screen=="pause" and main.ui.get_node("PausePanel").size.x==224)
	var buttons: Array=[]
	for child in main.ui.get_children():
		if child is Button:
			buttons.append(child)
			assert(main.ui.get_node("PausePanel").get_rect().encloses(child.get_rect()))
		if mobile and child is Label: assert(child.text not in ["ENTER","ESC","↑","↓"])
	assert(buttons.size()==4 and buttons[0].has_focus())
	for i in 4:
		assert(buttons[i].has_focus())
		var event=InputEventKey.new();event.keycode=KEY_DOWN;event.pressed=true;root.push_input(event)
		event=event.duplicate();event.pressed=false;root.push_input(event);await process_frame
	assert(buttons[0].has_focus())
	main._physics_process(1.0/60);assert(main.battle.checksum()==snapshot)
	if mobile: assert(not main.touch.visible and main.touch.bits==0)
	await capture("local")
	for pair in [["出招表","moves"],["设置","settings"]]:
		await activate(pair[0]);assert(main.screen==pair[1] and main.paused)
		await activate("ESC  返回" if pair[1]=="moves" else "← 返回");assert(main.screen=="pause" and main.paused and main.battle.checksum()==snapshot)
	await activate("继续对战")
	assert(main.screen=="fight" and main.paused and main.resume_left==3)
	for i in 3:
		main._physics_process(1.0/60);assert(main.battle.checksum()==snapshot and main.input_bits()==0)
		main._process(1)
	assert(not main.paused and main.resume_left==0)
	main._process(.016)
	if mobile: assert(main.touch.visible)
	main._physics_process(1.0/60);assert(main.battle.checksum()!=snapshot)
	main.online=true;main.arena.online=true;main.show_pause()
	assert(not main.paused and main.input_bits()==0)
	await capture("online")
	await activate("继续对战");assert(main.screen=="fight" and not main.paused and main.resume_left==0)
	main.online=false;main.show_pause();await activate("退出对局")
	assert(main.screen=="home" and not main.paused)
	print("PASS pause UI: layout, focus, mouse/touch actions, frozen state, submenu returns, 3-second resume, online menu and exit")
	main.queue_free();await process_frame;quit()
