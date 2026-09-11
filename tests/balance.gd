extends SceneTree
const Battle=preload("res://scripts/battle.gd")
const Cpu=preload("res://scripts/cpu.gd")
func _initialize() -> void: call_deferred("run")
# Optional full matches: --tournament [seeds per matchup/difficulty] [first seed].
# CPU results are a regression sample, not an estimate of human matchup odds.
func run() -> void:
	check_scenarios()
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if "--tournament" in args:
		var at: int=args.find("--tournament")
		tournament(int(args[at+1]) if args.size()>at+1 else 12,int(args[at+2]) if args.size()>at+2 else 0)
	quit()

func tournament(seeds: int, start_seed: int) -> void:
	assert(seeds>0 and start_seed>=0)
	for level in 3:
		for pair in [[0,1],[0,2],[1,2]]:
			var wins: Array=[0,0]
			var draws: int=0
			var timeouts: int=0
			var rounds: int=0
			var uses: Dictionary={}
			var damage: Dictionary={}
			var healing: int=0
			var max_uses: int=0
			for seed_id in range(start_seed,start_seed+seeds):
				for side in 2:
					var chars: Array=pair.duplicate()
					if side==1: chars.reverse()
					var b=Battle.new();b.reset(chars,73129+seed_id)
					var bots: Array=[Cpu.new(),Cpu.new()]
					for slot in 2:
						bots[slot].level=level
						bots[slot].seed_value=73129+seed_id*7919+pair.find(chars[slot])*100003
					for frame in 32000:
						for e in b.step([bots[0].sample(b,0),bots[1].sample(b,1)]):
							if e.kind in ["time","ko"]:
								rounds+=1
								if e.kind=="time": timeouts+=1
							if e.kind=="action": uses[e.move]=uses.get(e.move,0)+1
							if e.kind in ["hit","block"]: damage[e.move]=damage.get(e.move,0)+e.damage
							if e.kind=="pickup" and e.damage<0: healing-=e.damage
							if e.kind=="max": max_uses+=1
							if e.kind=="super": uses[e.text]=uses.get(e.text,0)+1
						if b.state.phase=="done": break
					assert(b.state.phase=="done")
					if b.state.winner<0: draws+=1
					else: wins[pair.find(chars[b.state.winner])]+=1
			print(JSON.stringify({"level":level,"pair":pair,"match_wins":wins,"draws":draws,"timeout_rounds":timeouts,"rounds":rounds,"uses":uses,"damage":damage,"healing":healing,"max_uses":max_uses}))

func fresh(chars: Array=[0,1], distance: int=50, face: int=1):
	var b=Battle.new();b.reset(chars);b.state.phase="fight"
	b.state.fighters[0].x=(260 if face==1 else 380)*Battle.FP
	b.state.fighters[1].x=b.state.fighters[0].x+face*distance*Battle.FP
	b.state.fighters[0].face=face;b.state.fighters[1].face=-face
	return b

func start(b, command: String) -> void:
	var f: Dictionary=b.state.fighters[0]
	f.input.buffer=command
	b.accept_input(f,b.state.fighters[1])

func check_scenarios() -> void:
	var max_burst: int=0
	for char_id in 3:
		for face in [1,-1]:
			var b=fresh([char_id,(char_id+1)%3],50,face)
			var cpu=Cpu.new();cpu.sequence([2],Battle.Commands.B,face)
			var attacks: Array=[]
			while not cpu.queue.is_empty():
				for e in b.step([cpu.queue.pop_front(),0]):
					if e.kind=="action": attacks.append(e.move)
			assert(attacks==[Battle.PREFIX[char_id]+"2B"],"CPU must retain crouch through the normal-button buffer")
			# A prepared MAX uses the same one stock as a normal super.
			b=fresh([char_id,(char_id+1)%3],50,face)
			var f: Dictionary=b.state.fighters[0]
			f.energy=200;start(b,"MAX")
			for i in 12: b.step([0,0])
			assert(f.max>0 and f.energy==100)
			start(b,"U1")
			assert(f.enhanced and f.energy==0 and f.max==0)
			b=fresh([char_id,(char_id+1)%3],50,face);f=b.state.fighters[0]
			f.energy=300;start(b,"C")
			for i in 12: b.step([0,0])
			assert(f.confirmed_hit)
			start(b,"MAX");assert(f.max>0 and f.energy==100)
			start(b,"U1");assert(f.enhanced and f.energy==0 and f.max==0)
			b=fresh([char_id,(char_id+1)%3],50,face);f=b.state.fighters[0]
			f.energy=99;f.max=300;start(b,"U1")
			assert(f.energy==99 and f.max==300 and f.mode=="idle")
			# Exercise actual contact cancels at mid-screen and the corner. This is
			# a frame-perfect route probe, not a claim to enumerate every human combo.
			for corner in [false,true]:
				for route in [["A","B","C","S1","S3" if char_id==0 else "S2","U1"],["C","MAX","A","S1","U1"]]:
					b=fresh([char_id,(char_id+1)%3],50,face);f=b.state.fighters[0]
					f.energy=300
					if corner:
						b.state.fighters[1].x=(600 if face==1 else 40)*Battle.FP
						f.x=b.state.fighters[1].x-face*50*Battle.FP
					if "MAX" not in route:
						start(b,"MAX")
						for i in 12: b.step([0,0])
					start(b,route[0]);var next: int=1
					for i in 360:
						if next<route.size() and ((f.mode=="attack" and f.contact) or b.is_free(f)):
							var old_move: String=f.move
							var old_meter: int=f.energy
							start(b,route[next])
							if f.move!=old_move or f.energy!=old_meter: next+=1
						b.step([0,0])
						assert(f.energy>=0 and f.energy<=300)
					var lost: int=1000-b.state.fighters[1].hp
					max_burst=maxi(max_burst,lost)
					assert(lost>0 and lost<=600,"sample full-meter routes must leave at least 40% life")
					assert(b.is_free(b.state.fighters[1]),"sample routes must eventually release the defender")
			# All projectiles must remain guardable, including crouched mirror targets.
			for foe in 3:
				b=fresh([char_id,foe],180,face);start(b,"S1")
				var guard: int=(Battle.Commands.RIGHT if face==1 else Battle.Commands.LEFT)|Battle.Commands.DOWN
				var blocks: int=0
				for i in 150:
					for e in b.step([0,guard]):
						if e.kind=="block": blocks+=1
				assert(blocks==1 and b.state.fighters[1].hp==1000-b.moves["P%d-S1" % (char_id+1)].damage/10)
	# Free close-range specials leave a punish window when fully blocked.
	for entry in [[1,"S2"],[2,"S2"],[2,"S3"],[2,"S4"]]:
		for face in [1,-1]:
			var b=fresh([entry[0],0],50,face);start(b,entry[1])
			var last_block: int=-1
			var defender_free: int=-1
			var attacker_free: int=-1
			var guard: int=Battle.Commands.RIGHT if face==1 else Battle.Commands.LEFT
			for tick in 180:
				for e in b.step([0,guard]):
					if e.kind=="block": last_block=b.state.world;defender_free=-1
				if last_block>=0 and defender_free<0 and b.is_free(b.state.fighters[1]): defender_free=b.state.world
				if attacker_free<0 and b.is_free(b.state.fighters[0]): attacker_free=b.state.world
			assert(last_block>=0 and defender_free>=0 and attacker_free-defender_free>=4,"blocked free special must not become safe pressure")
	# Each distinct free projectile can coexist with trousers, but neither can stack itself.
	var b=fresh([2,0],300);start(b,"S4")
	for i in 15: b.step([0,0])
	assert(not b.can_spawn(b.state.fighters[0],"P3-S4") and b.can_spawn(b.state.fighters[0],"P3-S1"))
	# Cheap food still requires meter, cannot stack, and preserves the 20% effect.
	b=fresh([0,1],300)
	var f: Dictionary=b.state.fighters[0];f.hp=500;f.energy=b.moves["P1-S2"].cost
	start(b,"S2")
	assert(f.energy==0 and f.move=="P1-S2")
	for i in 80: b.step([0,0])
	assert(not b.can_spawn(f,"P1-S2"))
	f.x=b.state.entities[0].x;b.step([0,0])
	assert(f.hp==700 and b.can_spawn(f,"P1-S2"))
	start(b,"S2");assert(f.mode=="idle" and f.energy==0)
	print("PASS balance scenarios: CPU crouch, MAX budgets, mirrored projectile guards, punish windows, food/projectile limits; sampled route max damage ",max_burst)
