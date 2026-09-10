extends SceneTree
const Battle=preload("res://scripts/battle.gd")
const C=preload("res://scripts/commands.gd")
func _initialize() -> void: call_deferred("run")
func fresh(chars: Array=[0,1]):
	var b=Battle.new();b.reset(chars);b.state.phase="fight"
	b.state.fighters[0].x=260*256;b.state.fighters[1].x=310*256
	return b
func action(b,id: String,age: int) -> void:
	var f: Dictionary=b.state.fighters[0]
	f.mode="attack";f.move=id;f.age=age;f.start_x=f.x;f.target_x=310*256
func run() -> void:
	var c: Dictionary=C.fresh()
	C.sample(c,C.B,1,0,false)
	for i in 10: C.sample(c,C.B,1,0,false)
	C.sample(c,C.B|C.C,1,0,false)
	assert(c.buffer!="MAX","held old key must not become a combo")
	c=C.fresh();C.sample(c,C.A,1,0,false);C.sample(c,0,1,0,false);C.sample(c,C.B,1,0,false)
	assert(c.buffer=="ROLL","2-frame combo leniency")
	var b=fresh()
	action(b,"RW-5A",4);b.step([0,0])
	var hp: int=b.state.fighters[1].hp
	for i in 20: b.step([0,0])
	assert(b.state.fighters[1].hp==hp,"one strike per action")
	b=fresh();action(b,"RW-THROW",4);b.step([0,0])
	assert(not b.state.cinema.is_empty())
	b.step([0,C.C]);assert(b.state.cinema.is_empty() and b.state.fighters[1].hp==1000,"throw break")
	b=fresh([1,0]);action(b,"P2-S3",7);b.step([0,0])
	for i in 37: b.step([0,C.C])
	assert(b.state.fighters[1].hp==870,"command grab cannot be broken; f36 damage")
	b=fresh();action(b,"RW-THROW",4)
	var foe: Dictionary=b.state.fighters[1];foe.mode="attack";foe.move="JG-5A";foe.age=4
	b.step([0,0]);assert(b.state.cinema.is_empty() and b.state.fighters[0].hp==965,"strike beats grab")
	b=fresh([1,0]);b.state.fighters[1].x=500*256;action(b,"P2-U1",18)
	var hits: int=0
	for i in 140:
		for e in b.step([0,0]):
			if e.kind=="hit" and e.move=="P2-U1": hits+=1
	assert(hits==5 and b.state.fighters[1].hp==800,"five document waves share combo scaling")
	b=fresh([1,0]);b.state.fighters[1].x=500*256;action(b,"P2-U1",18)
	b.step([0,0]);b.state.fighters[0].mode="hurt";b.state.fighters[0].move="";b.state.fighters[0].hitstun=80
	for i in 100: b.step([0,0])
	assert(b.state.fighters[1].hp==960,"interrupt cancels future waves")
	b=fresh();action(b,"P1-S3",28);b.step([0,0])
	assert(b.state.fighters[1].hp==880 and b.state.fighters[1].vy<0,"summon launches")
	b=fresh();b.state.fighters[0].hp=1
	b.food("burger",0,260*256,292*256,260*256,20);b.state.entities[0].age=50
	foe=b.state.fighters[1];foe.mode="attack";foe.move="JG-5A";foe.age=4
	b.step([0,0]);assert(b.state.fighters[0].hp==0,"food cannot resurrect same-frame KO")
	b=fresh([0,0]);b.state.fighters[1].hp=500
	b.food("pizza",0,310*256,292*256,310*256,24);b.state.entities[0].age=40
	b.step([0,0]);assert(b.state.fighters[1].hp==500,"enemy cannot take pizza")
	b=fresh();var f: Dictionary=b.state.fighters[0];f.energy=200
	action(b,"RW-5C",9);b.step([0,0])
	for i in 8: b.step([0,0])
	b.step([C.MAX,0]);assert(f.energy==12 and f.max<=360 and f.max>0,"quick MAX spends 200")
	b=fresh();f=b.state.fighters[0];f.max=120;action(b,"P1-S1",20);f.contact=true
	assert(not b.can_cancel(f,"P1-S3"),"exact 120 cannot MAX cancel")
	f.max=121;assert(b.can_cancel(f,"P1-S3"))
	f.chain=["P1-S3"];assert(not b.can_cancel(f,"P1-S3"),"no repeated special in chain")
	b=fresh();b.state.time=1
	b.start_cinema({"owner":0,"target":1,"kind":"room","move":"P1-U1"})
	for i in 72: b.step([0,0])
	assert(b.state.time==1 and b.state.fighters[1].hp==760)
	b.step([0,0]);assert(b.state.winner==0,"cinema finishes before timeout verdict")
	print("PASS advanced skills: combos, throw priority/breaks, five waves, interruption, summon, food/KO, MAX, cinema timeout")
	quit()
