extends SceneTree
var main

func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	main.arena.queue_redraw()
	await process_frame;await process_frame;RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("res://build/qa")
	root.get_texture().get_image().save_png("res://build/qa/improved-"+name+".png")

func run() -> void:
	var script=GDScript.new();script.source_code='extends "res://scripts/main.gd"\nfunc save_settings() -> void: pass\n'
	assert(script.reload()==OK)
	main=script.new();main.tests_demo=true
	if "mobile_validation" in main: main.mobile_validation=true
	root.add_child(main);main.set_physics_process(false);main.set_process(false)
	var b=main.battle
	assert(main.arena.textures.size()==4 and main.arena.props==null,"Menu only keeps preview atlases")
	for frames in main.arena.framesets.values(): assert(frames.get_animation_names().size()==2)
	await capture("home")
	for cost in [50,100,200]:
		b.events.clear();b.state.fighters[0].energy=0
		assert(not b.pay(b.state.fighters[0],cost))
		assert(b.events.back().text=={50:"需要 半格能量",100:"需要 1 格能量",200:"需要 2 格能量"}[cost])
	main.training=true;main.selected=2;main.opponent=2;main.start_local()
	assert(main.arena.framesets.keys()==["littleblack"] and main.arena.textures.keys().all(func(k): return k.begins_with("littleblack_")))
	assert(main.arena.littleblack_fx.size()==4)
	assert(main.battle.state.phase=="fight" and main.ui.has_node("TrainingReset"))
	assert(main.ui.get_node("TrainingReset").focus_mode==Control.FOCUS_NONE,"Attack A cannot activate the reset button")
	var record: Dictionary=main.stats.duplicate()
	b.state.fighters[0].hp=300;b.state.fighters[0].energy=0
	main.practice.step(b,0)
	assert(b.state.fighters[0].hp==1000 and b.state.fighters[0].energy==300)
	main.practice.refill=false;b.state.fighters[0].hp=300;b.state.fighters[0].energy=0
	main.practice.step(b,0);assert(b.state.fighters[0].hp==300 and b.state.fighters[0].energy==0)
	main.reset_training();main.practice.guard=true
	main.practice.step(b,0);assert(b.state.fighters[1].input.prev&8,"Guard dummy holds back")
	assert(b.state.fighters[1].x==480*256,"Guard dummy does not walk away")
	for bits in [2,0,8|16,0,0]: main.practice.step(b,bits)
	assert(main.practice.command=="篮球" and main.practice.history.size()<=6)
	main.update_training_text();await capture("training")
	for i in 6200: main.practice.step(b,0)
	assert(b.state.phase=="fight" and b.state.time>=5939,"Training never times out")
	assert(main.stats==record,"Training does not record match wins")
	b.state.fighters[1].hp=0;main.arena.seen["old"]=1
	main._physics_process(1.0/60)
	assert(b.state.frame==0 and b.state.phase=="fight" and main.arena.seen.is_empty(),"KO reset clears old feedback IDs")
	main.show_pause();assert(main.ui.get_children().any(func(n): return n is Button and n.text.begins_with("木桩：")))
	await capture("training-menu")
	main.resume_battle();main._process(3.1)
	assert(main.ui.has_node("TrainingReset") and not main.paused)
	main.reset_training();assert(b.state.fighters[0].x==160*256 and main.practice.history.is_empty())
	# Native joypad actions work for face buttons, shoulder buttons and analog deadzones.
	for pair in [[JOY_BUTTON_X,16],[JOY_BUTTON_LEFT_SHOULDER,512],[JOY_BUTTON_DPAD_DOWN,2]]:
		var event=InputEventJoypadButton.new();event.button_index=pair[0];event.pressed=true
		Input.parse_input_event(event.duplicate());Input.flush_buffered_events()
		assert(main.input_bits()&pair[1])
		event.pressed=false;Input.parse_input_event(event.duplicate());Input.flush_buffered_events()
	var stick=InputEventJoypadMotion.new();stick.axis=JOY_AXIS_LEFT_X;stick.axis_value=.2
	Input.parse_input_event(stick.duplicate());Input.flush_buffered_events();assert(main.input_bits()==0)
	stick.axis_value=.8;Input.parse_input_event(stick.duplicate());Input.flush_buffered_events();assert(main.input_bits()==8)
	stick.axis_value=0;Input.parse_input_event(stick.duplicate());Input.flush_buffered_events()
	var start=InputEventJoypadButton.new();start.button_index=JOY_BUTTON_START;start.pressed=true
	main._input(start);await process_frame;assert(main.screen=="pause")
	main._input(start);await process_frame;assert(main.screen=="fight")
	main._process(3.1);main.show_moves("pause",0)
	assert(main.input_name(4)=="X" and main.input_name(9)=="LB")
	await capture("gamepad-moves")
	# Reports are replayable but do not change the combat checksum.
	b.reset();var crc: int=b.checksum()
	b.event("hit",0,{"target":1,"damage":100,"dealt":80,"combo_start":true})
	b.event("hit",0,{"target":1,"damage":60,"combo_start":false})
	assert(b.report[0].damage==140 and b.report[0].best_combo==2)
	assert(b.checksum()==crc)
	var snapshot: Dictionary=b.snapshot()
	b.event("hit",0,{"target":1,"damage":60,"combo_start":false})
	b.restore(snapshot);assert(b.report[0].damage==140 and b.report[0].best_combo==2 and b.checksum()==crc)
	main.training=false;b.state.winner=0;b.state.phase="done";b.state.wins=[2,1]
	main.show_result();await capture("result")
	assert(main.ui.get_children().any(func(n): return n is Label and n.text.contains("本局最高连击 2") and n.text.contains("140")))
	b.reset();b.state.phase="fight";b.state.fighters[1].hp=80
	b.food("burger",0,480*256,292*256,480*256,0);b.state.entities[0].age=40;b.pick_food()
	assert(b.report[0].damage==80,"Enemy food damage is credited without counting overkill")
	# Saturated channels cannot replace KO with menu noise; lower priority/older voices yield first.
	for player in main.audio.voices:
		player.stream=AudioStreamGenerator.new();player.play();player.set_meta("priority",3);player.set_meta("started",10)
	assert(main.audio.voice_for("move")==null)
	main.audio.voices[2].set_meta("priority",0)
	assert(main.audio.voice_for("heavy")==main.audio.voices[2])
	for player in main.audio.voices: player.stop()
	if not "mobile_validation" in main:
		main.show_network()
		for node in main.ui.get_children():
			if node is LineEdit: node.text=""
		for node in main.ui.get_children():
			if node is Button and node.text=="创建房间": node.pressed.emit();break
		assert(main.screen=="network" and not root.get_node("Net").connecting)
		assert(main.ui.get_children().any(func(n): return n is Label and n.text=="请填写服务器地址"))
	main.show_home();assert(main.arena.textures.size()==4 and main.arena.props==null)
	print("PASS improvements: half-stock costs, lazy assets, training, gamepad, replayable reports, sound priority and connection errors")
	main.queue_free();await process_frame;quit()
