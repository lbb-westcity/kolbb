extends SceneTree
var main

func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	main.arena.queue_redraw()
	await process_frame
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/qa/linbin_"+name+".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/qa")
	main=load("res://main.tscn").instantiate();root.add_child(main)
	main.set_physics_process(false)
	main.selected=3;main.opponent=3;main.show_select();await capture("select")
	for slot in 2:
		for ch in 4:
			assert(Rect2(0,0,640,360).encloses(main.ui.get_node("Character%d_%d" % [slot,ch]).get_rect()))
	main.show_moves("select",3);await capture("moves")
	main.start_local();main.set_physics_process(false)
	for face in [1,-1]:
		for id in ["S1","S2","S3","U1"]:
			var b=main.battle;b.reset([3,3]);b.state.phase="fight"
			var f: Dictionary=b.state.fighters[0];var foe: Dictionary=b.state.fighters[1]
			f.x=(240 if face==1 else 400)*256;foe.x=f.x+face*160*256
			f.face=face;foe.face=-face;f.mode="attack";f.move="P4-"+id;f.age=b.moves[f.move].s;f.energy=200
			main.arena.reset_effects()
			for i in (15 if id=="S3" else 1): main.arena.present(b.step([0,0]),main.audio)
			await capture(id+"_"+str(face))
			if id=="U1":
				main.settings.flash=true;await capture("reduced_flash_"+str(face))
				for i in 230: main.arena.present(b.step([0,0]),main.audio)
				await capture("deadline_burst_"+str(face));main.settings.flash=false
	var frames: SpriteFrames=main.arena.framesets.linbin
	var count: int=0
	for animation in frames.get_animation_names():
		assert(frames.get_frame_count(animation)==24)
		for i in 24:
			var tex: AtlasTexture=frames.get_frame_texture(animation,i)
			var bounds: Rect2i=tex.get_image().get_used_rect()
			assert(bounds.has_area() and bounds.position.x>=2 and bounds.position.y>=2 and bounds.end.x<=382 and bounds.end.y<=222,"complete pose inside atlas cell")
			count+=1
	assert(main.arena.linbin_fx.size()==3)
	print("PASS Linbin visual: ",count," poses, four-character UI, both facings and reduced flash")
	main.queue_free();await process_frame;quit()
