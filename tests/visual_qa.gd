extends SceneTree
var main
var shots: int=0
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	shots+=1
	main.arena.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/qa/"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/qa")
	main=load("res://main.tscn").instantiate();main.tests_demo=true;root.add_child(main)
	main.set_physics_process(false)
	await shot("home")
	main.show_select();await shot("select")
	main.show_settings("home");await shot("settings")
	for page in 4:
		main.show_moves("home",page);await shot("moves_"+str(page))
	main.start_local();main.set_physics_process(false)
	main.battle.state.phase="fight"
	var test_fighter: Dictionary=main.battle.state.fighters[0]
	test_fighter.mode="attack";test_fighter.move="RW-5A"
	var move: Dictionary=main.battle.moves["RW-5A"]
	test_fighter.age=move.s
	assert(main.arena.animation(test_fighter)[1]==1,"contact must not precede active tick")
	test_fighter.age=move.s+1
	assert(main.arena.animation(test_fighter)[1]==3,"first active tick shows contact")
	test_fighter.age=move.s+move.a
	assert(main.arena.animation(test_fighter)[1]==3,"last active tick keeps contact")
	test_fighter.age+=1
	assert(main.arena.animation(test_fighter)[1]>=4,"recovery follows last active tick")
	for character in 3:
		for id in (["S1","S2","S3","S4","U1"] if character==2 else ["S1","S2","S3","U1"]):
			var b=main.battle
			b.reset([character,(character+1)%3]);b.state.phase="fight"
			var f: Dictionary=b.state.fighters[0]
			f.x=260*256;b.state.fighters[1].x=(310 if id=="S3" or id=="U1" else 420)*256
			f.mode="attack";f.move="P%d-%s" % [character+1,id];f.age=b.moves[f.move].s;f.energy=200;f.target_x=310*256;f.start_x=f.x
			main.arena.reset_effects()
			for i in (1 if character==2 else 42 if id=="U1" or (character==1 and id=="S3") else 15): main.arena.present(b.step([0,0]),main.audio)
			await shot("skill_%d_%s" % [character,id])
	for age in [14,30,46,60]:
		main.battle.reset([2,0]);main.battle.state.phase="fight"
		var f: Dictionary=main.battle.state.fighters[0]
		f.mode="attack";f.move="P3-S4";f.age=age+1
		await shot("littleblack_trousers_"+str(age))
	for character in 3:
		main.battle.reset([character,character]);main.battle.state.phase="fight"
		main.battle.state.fighters[0].x=250*256;main.battle.state.fighters[1].x=400*256
		await shot("mirror_"+str(character))
	# Each packed cell must contain a complete pose with transparent edge padding.
	var count: int=0
	for who in main.battle.ART:
		var frames: SpriteFrames=main.arena.framesets[who]
		for sequence in frames.get_animation_names():
			if sequence.ends_with("_alt"): continue
			for i in frames.get_frame_count(sequence):
				var tex: AtlasTexture=frames.get_frame_texture(sequence,i)
				var bounds: Rect2i=tex.get_image().get_used_rect()
				if not bounds.has_area() or bounds.position.x<2 or bounds.end.x>tex.region.size.x-2 or bounds.position.y<2 or bounds.end.y>tex.region.size.y-2:
					assert(false,"POSE BOUNDS %s %s %d %s" % [who,sequence,i,bounds])
				count+=1
	print("Visual QA rendered ",shots," screens; inspected ",count," base poses")
	main.queue_free()
	await process_frame
	quit()
