extends SceneTree

var main
var capture: bool=false
var shots: int=0
var impacts: bool=false

func _initialize() -> void: call_deferred("run")

func shot(name: String) -> void:
	main.arena.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://build/vfx/"+name+".png")==OK)
	shots+=1

func run() -> void:
	impacts="--capture-impacts" in OS.get_cmdline_user_args()
	capture=(impacts or "--capture-vfx" in OS.get_cmdline_user_args()) and DisplayServer.get_name()!="headless"
	if capture: DirAccess.make_dir_recursive_absolute("res://build/vfx")
	main=load("res://main.tscn").instantiate();main.tests_demo=true;root.add_child(main)
	main.start_local();main.set_physics_process(false);main.set_process(false)
	main.audio.silent=true;main.audio.pause_music(true)
	var b=main.battle
	var arena=main.arena
	for reduced in [false,true]:
		arena.settings={"shake":not reduced,"flash":reduced}
		for face in [1,-1]:
			for character in 3:
				for skill in (["S1","S2","S3","S4","U1"] if character==2 else ["S1","S2","S3","U1"]):
					b.reset([character,character]);b.state.phase="fight"
					arena.reset_effects()
					var f: Dictionary=b.state.fighters[0]
					f.x=(240 if face==1 else 400)*256;f.face=face;f.energy=300
					var distance: int=180 if skill=="S1" else 144 if character==0 and skill=="S3" else 54
					b.state.fighters[1].x=f.x+face*distance*256
					b.state.fighters[1].face=-face
					f.input.buffer=skill;b.accept_input(f,b.state.fighters[1])
					assert(f.move=="P%d-%s" % [character+1,skill])
					arena.present(b.events,main.audio)
					var captured: Dictionary={}
					for tick in 150:
						var events: Array=b.step([0,0])
						var original: Array=events.duplicate(true)
						var checksum: int=b.checksum()
						arena.present(events,main.audio)
						var count: int=arena.fx.size()
						arena.present(events,main.audio)
						assert(arena.fx.size()==count,"replayed events must not duplicate effects")
						assert(events==original,"presentation must not mutate replay events")
						arena.animate(1.0/60,false)
						assert(b.checksum()==checksum,"VFX must not mutate simulation or RNG")
						assert(arena.fx.size()<=40,"effect budget")
						if capture and not impacts and tick in [8,24,48,72,104] and (not reduced or face==-1 and tick==24):
							await shot("%d_%s_%s_%03d%s" % [character,skill,"right" if face==1 else "left",tick,"_reduced" if reduced else ""])
						elif capture and impacts:
							for e in events:
								if e.kind not in ["hit","projectile","summon","slam","whip","papers"] or captured.has(e.kind): continue
								captured[e.kind]=true
								await shot("%d_%s_%s_%s%s" % [character,skill,"right" if face==1 else "left",e.kind,"_reduced" if reduced else ""])
					var remaining: Array=arena.fx.duplicate(true)
					arena.animate(.25,true)
					assert(arena.fx==remaining,"paused effects must stay paused")
					arena.animate(1,false)
					assert(arena.fx.is_empty() and arena.trauma==0,"effects must expire")
	# Wave bursts are bounded even when a batch arrives together after a delay.
	var burst: Array=[]
	for i in 70: burst.append({"id":"stress/%d/0" % i,"kind":"papers","slot":0,"x":240,"y":200})
	arena.present(burst,main.audio);assert(arena.fx.size()==40)
	arena.reset_effects();assert(arena.fx.is_empty() and arena.seen.is_empty())
	print("PASS VFX: 13 skills, both facings, mirrors, reduced effects, event deduplication, simulation isolation, pause/expiry/budget; screenshots: ",shots)
	main.queue_free();await process_frame;quit()
