extends RefCounted
const Commands=preload("res://scripts/commands.gd")
var guard: bool=false
var refill: bool=true
var history: Array[String]=[]
var command: String="等待出招"
var previous: int=0

func reset(battle) -> void:
	var characters: Array=battle.state.fighters.map(func(f): return f.char)
	battle.reset(characters)
	battle.state.phase="fight"
	for f in battle.state.fighters: f.energy=300
	history.clear();command="等待出招";previous=0

func step(battle, bits: int) -> Array:
	var player: Dictionary=battle.state.fighters[0]
	if bits!=previous:
		var token: String=["↙","↓","↘","←","·","→","↖","↑","↗"][Commands.direction(bits,player.face)-1]
		for i in 6:
			if bits&(1<<(i+4)): token+=["轻拳","轻脚","重拳","重脚","翻滚","MAX"][i]
		history.append(token)
		if history.size()>6: history.pop_front()
		previous=bits
	var dummy: Dictionary=battle.state.fighters[1]
	var defense: int=0
	if guard:
		defense=Commands.LEFT if dummy.face==1 else Commands.RIGHT
		if battle.moves.get(player.move,{}).get("level","")=="low": defense|=Commands.DOWN
	var dummy_x: int=dummy.x
	battle.state.time=5940
	var events: Array=battle.step([bits,defense]).duplicate(true)
	if guard and dummy.mode=="walk":
		dummy.x=dummy_x;dummy.vx=0;dummy.mode="idle"
		battle.push_fighters()
	for event in events:
		if event.slot==0:
			if event.kind=="action": command=battle.moves[event.move].name
			elif event.kind=="denied": command=event.text
	if battle.state.phase=="result":
		reset(battle);return []
	elif refill:
		for f in battle.state.fighters:
			f.energy=300
			if battle.is_free(f) and f.combo_age==0 and battle.state.cinema.is_empty(): f.hp=1000
	return events
