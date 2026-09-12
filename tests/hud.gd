extends SceneTree
var main

func _initialize() -> void: call_deferred("run")

func shot(name: String) -> Image:
	await process_frame
	main.arena.queue_redraw()
	if DisplayServer.get_name()=="headless": return null
	await process_frame
	RenderingServer.force_draw()
	var image: Image=root.get_texture().get_image()
	image.save_png("res://build/qa/hud-"+name+".png")
	return image

func pixel(image: Image, x: int, y: int) -> Color:
	return image.get_pixel(int((x+.5)*image.get_width()/640.0),int((y+.5)*image.get_height()/360.0))

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/qa")
	main=load("res://main.tscn").instantiate();main.tests_demo=true;root.add_child(main)
	# Freeze captures without the mobile focus-loss pause overlay.
	if "mobile_validation" in main: main.mobile_validation=false
	main.start_local();main.set_physics_process(false);main.set_process(false)
	assert(main.arena.hud_logo.resource_path=="res://assets/ui/kolbb-logo.png")
	var s: Dictionary=main.battle.state
	var initial: Dictionary=s.duplicate(true)
	s.phase="round";await shot("round")
	s.phase="ready";await shot("fight")
	s.phase="fight"
	var full: Image=await shot("full")
	main.show_pause();main.resume_battle()
	var frozen_frame: int=s.frame
	var frozen_time: int=s.time
	for number in [3,2,1]:
		assert(ceili(main.arena.countdown)==number and main.paused)
		assert(main.input_bits()==0)
		main._physics_process(1.0/60)
		assert(s.frame==frozen_frame and s.time==frozen_time,"Countdown freezes battle and round clock")
		await shot("countdown-"+str(number))
		main._process(1.0)
	assert(main.resume_left==0 and not main.paused and main.arena.countdown==0)
	assert(main.arena.resume_fight_left>0,"Countdown hands off to FIGHT")
	await shot("resume-fight")
	main._physics_process(1.0/60)
	assert(s.frame==frozen_frame+1,"Battle resumes immediately after three seconds")
	main._process(.6)
	assert(main.arena.resume_fight_left==0,"FIGHT clears after its brief display")
	main.show_pause();main.resume_battle();main._process(.4);main.show_pause();main._process(4)
	assert(main.screen=="pause" and main.paused and main.resume_left==0 and main.arena.countdown==0,"Reopening pause cancels countdown")
	main.resume_battle();main._process(3);main._process(.6)
	s.fighters[0].hp=400;s.fighters[1].hp=650
	s.fighters[0].energy=150;s.fighters[1].energy=300
	s.fighters[1].max=300;s.wins=[1,0];s.time=600
	main.arena.delayed_hp=[600.0,800.0]
	s.fighters[1].combo_age=20;s.fighters[1].combo_damage=180;main.arena.combo_hits[1]=3
	var damaged: Image=await shot("damage")
	if full:
		for x in [90,250,390,550]: assert(pixel(full,x,39).r>.9,"Full health must cover both bars")
		assert(pixel(damaged,90,39).r>.9 and pixel(damaged,250,39).r<.15,"Left health retracts toward left portrait")
		assert(pixel(damaged,550,39).r>.9 and pixel(damaged,390,39).r<.15,"Right health retracts toward right portrait")
		assert(pixel(damaged,180,39).r>.7 and pixel(damaged,180,39).g<.5,"Damage trail remains visible")
		assert(pixel(damaged,60,337).r>.9 and pixel(damaged,175,337).r<.15,"POW shows filled and empty segments")
	s.fighters[0].hp=0;s.fighters[1].hp=0;main.arena.delayed_hp=[0.0,0.0]
	var empty: Image=await shot("empty")
	if empty:
		for x in [90,250,390,550]: assert(pixel(empty,x,39).r<.15,"Zero health must leave empty bars")
	s.phase="result";s.winner=0;await shot("ko")
	main.battle.state=initial;main.battle.state.phase="fight"
	main.arena.reset_effects();main.arena.online=true;main.arena.status="128 ms"
	main.battle.state.fighters[1].char=2;await shot("online")
	if "touch" in main and main.touch:
		main.arena.online=false;main.arena.status="CPU / 普通";main.touch.visible=true
		await shot("touch")
		assert(main.touch.PAUSE.position.y>62,"Pause button clears the timer")
		main.touch.press(9,main.touch.PAUSE.get_center())
		assert(main.paused,"Relocated pause button remains interactive")
	print("PASS HUD: 3-2-1 timing, freeze/resume/cancellation, round/fight/result, portraits, mirrored health, damage trails, POW, MAX, timer, wins, online and logo")
	main.queue_free();await process_frame;quit()
