extends SceneTree
const Battle = preload("res://scripts/battle.gd")
const C = preload("res://scripts/commands.gd")
var checks: int = 0
func ok(value: bool, title: String) -> void:
	if not value:
		printerr("FAIL: ",title)
		quit(1)
		assert(value,title)
	checks += 1
func fresh(chars: Array = [0,1]):
	var b = Battle.new()
	b.reset(chars)
	b.state.phase="fight"
	b.state.fighters[0].x=260*256
	b.state.fighters[1].x=310*256
	return b
func action(b, slot: int, id: String, age: int = 0) -> void:
	var f: Dictionary = b.state.fighters[slot]
	f.mode="attack";f.move=id;f.age=age;f.start_x=f.x;f.target_x=f.x+144*256
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var serializer=Battle.new()
	var named: Dictionary={&"mode":&"idle",&"hp":1000,&"id":2}
	var textual: Dictionary={"id":2,"hp":1000,"mode":"idle"}
	ok(serializer.canonical(named,PackedByteArray())==serializer.canonical(textual,PackedByteArray()),"StringName keys and values hash as text regardless of insertion order")
	ok(C.direction(C.LEFT|C.RIGHT,1)==5,"SOCD horizontal")
	ok(C.direction(C.UP|C.DOWN,-1)==5,"SOCD vertical")
	ok(C.direction(C.RIGHT|C.DOWN,-1)==1,"relative facing")
	var cmd: Dictionary = C.fresh()
	for face in [1,-1]:
		var forward: int = C.RIGHT if face==1 else C.LEFT
		var back: int = C.LEFT if face==1 else C.RIGHT
		for ch in Battle.NAMES.size():
			for attack in [C.A,C.C,C.B,C.D]:
				var cases: Array = [[[C.DOWN,forward],"S1"],[[C.DOWN,back],"S2"],[[C.DOWN,forward,C.DOWN,forward],"U1"]] if attack in [C.A,C.C] else [[[forward,C.DOWN,back] if ch==1 else [forward,C.DOWN],"S3"]]
				for entry in cases:
					for held in [false,true]:
						var trial = fresh([ch,(ch+1)%Battle.NAMES.size()])
						trial.state.fighters[0].x=(260 if face==1 else 400)*256
						trial.state.fighters[1].x=(400 if face==1 else 260)*256
						trial.state.fighters[0].energy=300
						var held_bits: int = 0
						for key in entry[0]:
							held_bits = (held_bits & ~int(key)) if held else 0
							trial.step([held_bits,0]) # Repeated keys must be released before pressing again.
							held_bits |= key
							for i in 12: trial.step([held_bits,0])
						trial.step([held_bits|attack,0])
						ok(trial.state.fighters[0].move=="P%d-%s" % [ch+1,entry[1]],"special char=%d face=%d attack=%d held=%s %s" % [ch,face,attack,held,entry[1]])
	cmd=C.fresh()
	for bits in [C.DOWN,C.LEFT|C.RIGHT,C.LEFT|C.RIGHT|C.A]: C.sample(cmd,bits,1,0,false)
	ok(cmd.buffer=="" and cmd.dir==5,"simultaneous opposing keys stay neutral")
	cmd=C.fresh()
	for bits in [C.DOWN,C.DOWN|C.RIGHT,C.RIGHT|C.A]: C.sample(cmd,bits,1,0,false)
	ok(cmd.buffer=="S1","26 tolerates overlapping keys")
	cmd=C.fresh()
	for bits in [C.DOWN,C.DOWN|C.LEFT,C.LEFT|C.A]: C.sample(cmd,bits,-1,0,false)
	ok(cmd.buffer=="S1","mirrored 26 tolerates overlapping keys")
	cmd=C.fresh()
	for bits in [C.DOWN,C.DOWN|C.RIGHT,C.RIGHT,C.DOWN,C.DOWN|C.RIGHT,C.RIGHT|C.C]: C.sample(cmd,bits,1,0,false)
	ok(cmd.buffer=="U1","super priority")
	cmd=C.fresh()
	for bits in [C.DOWN,C.LEFT,C.RIGHT|C.A]: C.sample(cmd,bits,1,0,false)
	ok(cmd.buffer!="S1","opposite cardinal interrupts command")
	cmd=C.fresh();C.sample(cmd,C.DOWN,1,0,false)
	for i in 21: C.sample(cmd,0,1,0,false)
	C.sample(cmd,C.RIGHT|C.A,1,0,false)
	ok(cmd.buffer!="S1","expired direction cannot trigger special")
	var b=fresh()
	for face in [1,-1]:
		var forward: int = C.RIGHT if face==1 else C.LEFT
		for ch in Battle.NAMES.size():
			for held in [false,true]:
				b=fresh([ch,(ch+1)%Battle.NAMES.size()])
				b.state.fighters[0].x=(260 if face==1 else 400)*256
				b.state.fighters[1].x=(400 if face==1 else 260)*256
				b.step([0,0])
				for bits in [C.DOWN,(C.DOWN|forward) if held else forward]:
					for i in 12: b.step([bits,0])
				b.step([((C.DOWN|forward) if held else forward)|C.A,0])
				ok(b.state.fighters[0].move=="P%d-S1" % (ch+1),"SDJ with 0.2s steps held=%s face=%d char=%d" % [held,face,ch])
				ok(b.state.fighters[0].input.dir==(3 if held else 6),"command input preserves movement direction")
				for i in 20: b.step([0,0])
				ok(not b.state.entities.is_empty(),"SDJ spawns projectile in battle")
	b=fresh()
	for id in b.moves:
		var m: Dictionary=b.moves[id]
		if m.kind!="normal": continue
		var f: Dictionary=b.state.fighters[0]
		f.char=Battle.PREFIX.find(id.split("-")[0]+"-")
		action(b,0,id,m.s-1)
		ok(not b.attackbox(f).has_area(),id+" startup")
		f.age=m.s
		ok(b.attackbox(f).has_area(),id+" first active")
		f.age=m.s+m.a-1
		ok(b.attackbox(f).has_area(),id+" last active")
		f.age=m.s+m.a
		ok(not b.attackbox(f).has_area(),id+" recovery")
	b=fresh()
	action(b,0,"RW-5A",4)
	action(b,1,"JG-5A",4)
	b.step([0,0])
	ok(b.state.fighters[0].hp==965 and b.state.fighters[1].hp==970,"simultaneous trade")
	b=fresh()
	action(b,0,"RW-5A",4)
	b.step([0,C.RIGHT])
	ok(b.state.fighters[1].hp==1000 and b.state.fighters[1].mode=="guard","standing guard")
	b=fresh()
	action(b,0,"RW-2B",5)
	b.step([0,C.RIGHT])
	ok(b.state.fighters[1].hp==970,"low breaks stand guard")
	b=fresh()
	action(b,0,"RW-2B",5)
	b.step([0,C.DOWN|C.RIGHT])
	ok(b.state.fighters[1].hp==1000,"crouch guard low")
	b=fresh()
	b.state.fighters[1].mode="roll";b.state.fighters[1].age=6
	action(b,0,"RW-5A",4)
	b.step([0,0])
	ok(b.state.fighters[1].hp==1000,"roll strike immunity")
	ok(b.throwable(b.state.fighters[1]),"roll is throwable")
	b=fresh([0,0])
	b.state.fighters[0].hp=500
	b.food("burger",0,260*256,292*256,260*256,20)
	b.state.entities[0].age=50
	b.step([0,0])
	ok(b.state.fighters[0].hp==700,"own burger heals 200")
	b=fresh([0,0])
	b.food("burger",0,310*256,292*256,310*256,20)
	b.state.entities[0].age=50
	b.step([0,0])
	ok(b.state.fighters[1].hp==800,"mirror enemy burger damages 200")
	b=fresh()
	b.food("burger",0,260*256,292*256,260*256,20)
	b.state.entities[0].age=50
	b.step([0,0])
	ok(b.state.entities.size()==1,"full hp preserves burger")
	b=fresh()
	action(b,0,"P1-S3",28)
	b.state.fighters[1].x=570*256
	for i in 5: b.step([0,0])
	var pizzas: int=0
	for e in b.state.entities:
		if e.kind=="pizza": pizzas+=1
	ok(pizzas==3,"summon creates exactly three pizzas")
	ok(not b.can_spawn(b.state.fighters[0],"P1-S3"),"pizza locks next summon")
	b=fresh()
	b.state.fighters[0].energy=100
	b.step([C.MAX,0])
	for i in 11: b.step([0,0])
	ok(b.state.fighters[0].energy==0 and b.state.fighters[0].max==600,"normal MAX cost and duration")
	b=fresh()
	b.state.fighters[1].hp=1
	action(b,0,"P1-S1",16)
	b.step([0,C.RIGHT])
	for i in 12: b.step([0,C.RIGHT])
	ok(b.state.fighters[1].hp==1,"chip cannot KO")
	b=fresh()
	b.start_cinema({"owner":0,"target":1,"kind":"room","move":"P1-U1"})
	var initial: int=b.state.time
	for i in 60: b.step([0,0])
	ok(b.state.fighters[1].hp==1000,"room no premature damage")
	b.step([0,0])
	ok(b.state.fighters[1].hp==760,"room one f60 damage")
	for i in 11: b.step([0,0])
	ok(b.state.fighters[1].hp==760 and b.state.time==initial,"cinema freezes clock and no double damage")
	b=fresh()
	for i in 3:
		b.state.phase="fight";b.state.time=0
		b.state.fighters[0].hp=500;b.state.fighters[1].hp=500
		b.check_end()
		for j in 180: b.step([0,0])
	ok(b.state.phase=="done" and b.state.draws==3,"third draw ends match")
	b=fresh()
	var saved: Dictionary=b.snapshot()
	for i in 1000: b.step([C.RIGHT if i%60<20 else C.A if i%60==20 else 0,C.LEFT if i%70<18 else C.C if i%70==18 else 0])
	var checksum: int=b.checksum()
	b.restore(saved)
	for i in 1000: b.step([C.RIGHT if i%60<20 else C.A if i%60==20 else 0,C.LEFT if i%70<18 else C.C if i%70==18 else 0])
	ok(b.checksum()==checksum,"1000 frame restore replay deterministic")
	print("PASS ",checks," rule checks; replay CRC32 ",checksum)
	quit()
