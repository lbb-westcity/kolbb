extends SceneTree
const Battle=preload("res://scripts/battle.gd")
const Cpu=preload("res://scripts/cpu.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var samples: Array=[]
	var move_ids: Dictionary={}
	var wins: Array=[0,0,0]
	for game in 27:
		var b=Battle.new();b.reset([game%3,(game/3)%3],73129+game)
		var a=Cpu.new();var c=Cpu.new();a.level=game/9;c.level=game/9;c.seed_value+=game
		for frame in 24000:
			var start: int=Time.get_ticks_usec()
			var ev: Array=b.step([a.sample(b,0),c.sample(b,1)])
			samples.append(Time.get_ticks_usec()-start)
			for e in ev:
				if e.has("move"): move_ids[e.move]=true
			for f in b.state.fighters:
				assert(f.hp>=0 and f.hp<=1000)
				assert(f.energy>=0 and f.energy<=300)
				assert(f.y<=292*256)
				assert(f.x>=16*256 and f.x<=624*256)
			assert(b.state.entities.size()<=20)
			if b.state.phase=="done":
				wins[b.state.winner+1]+=1
				break
		assert(b.state.phase=="done","CPU match must terminate")
		print("Match ",game," finished frame ",b.state.frame," score ",b.state.wins)
	samples.sort()
	print("PASS CPU soak: 27 complete matches, ",samples.size()," ticks; p95 µs ",samples[int(samples.size()*.95)]," max µs ",samples[-1]," moves observed ",move_ids.keys())
	quit()
