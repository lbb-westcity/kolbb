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
	ok(C.direction(C.LEFT|C.RIGHT,1)==5,"SOCD horizontal")
	ok(C.direction(C.UP|C.DOWN,-1)==5,"SOCD vertical")
	ok(C.direction(C.RIGHT|C.DOWN,-1)==1,"relative facing")
	var cmd: Dictionary = C.fresh()
	for bits in [C.DOWN,C.DOWN|C.RIGHT,C.RIGHT|C.A]: C.sample(cmd,bits,1,0,false)
	ok(cmd.buffer=="S1","236 punch recognition")
	cmd=C.fresh()
	for bits in [C.DOWN,C.DOWN|C.LEFT,C.LEFT|C.A]: C.sample(cmd,bits,-1,0,false)
	ok(cmd.buffer=="S1","mirrored 236 recognition")
	cmd=C.fresh()
	for bits in [C.DOWN,C.DOWN|C.RIGHT,C.RIGHT,C.DOWN,C.DOWN|C.RIGHT,C.RIGHT|C.C]: C.sample(cmd,bits,1,0,false)
	ok(cmd.buffer=="U1","super priority")
	var b=fresh()
	for id in b.moves:
		var m: Dictionary=b.moves[id]
		if m.kind!="normal": continue
		var f: Dictionary=b.state.fighters[0]
		f.char=0 if id.begins_with("RW") else 1
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
