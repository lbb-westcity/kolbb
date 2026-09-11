extends SceneTree
const Battle=preload("res://scripts/battle.gd")
const C=preload("res://scripts/commands.gd")
func _initialize() -> void: call_deferred("run")
func fresh(foe: int=0, face: int=1):
	var b=Battle.new();b.reset([2,foe]);b.state.phase="fight"
	b.state.fighters[0].x=260*256 if face==1 else 380*256
	b.state.fighters[1].x=b.state.fighters[0].x+face*50*256
	b.state.fighters[0].face=face;b.state.fighters[1].face=-face
	return b
func action(b,id: String,age: int=0) -> void:
	var f: Dictionary=b.state.fighters[0]
	f.mode="attack";f.move=id;f.age=age;f.start_x=f.x;f.action_id=88
func advance(b,frames: int,guard: int=0) -> Array:
	var hits: Array=[]
	for i in frames:
		for e in b.step([0,guard]):
			if e.kind in ["hit","block"]: hits.append(e.duplicate())
	return hits
func run() -> void:
	for ch in 3:
		for face in [1,-1]:
			var b=fresh(ch,face)
			var f: Dictionary=b.state.fighters[0]
			var foe: Dictionary=b.state.fighters[1]
			var back: int=C.RIGHT if face==1 else C.LEFT
			var input: Dictionary=C.fresh()
			var command_back: int=C.LEFT if face==1 else C.RIGHT
			C.sample(input,C.DOWN,face,2,false);C.sample(input,command_back,face,2,false);C.sample(input,command_back|C.B,face,2,false)
			assert(input.buffer=="S4","24 kick selects trousers")
			action(b,"P3-S4")
			assert(advance(b,100).size()==2 and foe.hp==890,"trousers then kick share combo scaling")
			b=fresh(ch,face);action(b,"P3-S4",14)
			var cloth_hits: Array=advance(b,100,back)
			assert(cloth_hits.size()==2 and b.state.fighters[1].hp==989,"both trousers hits can be guarded")
			b=fresh(ch,face);action(b,"P3-S4",14);advance(b,1)
			f=b.state.fighters[0];f.mode="hurt";f.move="";f.hitstun=80
			assert(advance(b,100).is_empty() and b.state.fighters[1].hp==960,"interrupt stops follow-up kick")
			b=fresh(ch,face);f=b.state.fighters[0];foe=b.state.fighters[1]
			action(b,"P3-U1")
			var hits: Array=advance(b,120)
			assert(hits.size()==4 and foe.hp==760,"four dance hits share scaling")
			b=fresh(ch,face);action(b,"P3-U1");f=b.state.fighters[0];f.enhanced=true
			assert(advance(b,120).size()==4 and b.state.fighters[1].hp==680,"enhanced 320 damage")
			b=fresh(ch,face);action(b,"P3-U1")
			assert(advance(b,120,back).size()==4 and b.state.fighters[1].hp==976,"four guardable hits")
			b=fresh(ch,face);action(b,"P3-U1",18)
			assert(advance(b,1).size()==1)
			f=b.state.fighters[0];f.mode="hurt";f.move="";f.hitstun=80
			assert(advance(b,110).is_empty() and b.state.fighters[1].hp==960,"interruption cancels remaining hits")
			b=fresh(ch,face);action(b,"P3-U1",42);advance(b,1)
			assert(b.state.fighters[1].mode=="down" and b.state.fighters[1].hard,"last dance hit knocks down")
			b=fresh(ch,face);action(b,"P3-S2")
			assert(advance(b,85).size()==1 and b.state.fighters[1].hp==925,"shoulder one hit")
			b=fresh(ch,face);action(b,"P3-S2")
			assert(advance(b,85,back).size()==1 and b.state.fighters[1].hp==993,"shoulder can be blocked")
			b=fresh(ch,face);foe=b.state.fighters[1];foe.y-=100*256;foe.mode="air"
			action(b,"P3-S3",10);advance(b,1)
			assert(foe.hp==920 and foe.vy<0,"sonic hits airborne enemy")
			b=fresh(ch,face);action(b,"P3-S3",10);advance(b,1,back)
			assert(b.state.fighters[1].hp==992 and b.state.fighters[1].vy==0,"blocked sonic cannot launch")
			b=fresh(ch,face);action(b,"P3-S1",16);advance(b,15)
			assert(b.state.fighters[1].hp==950 and b.state.fighters[1].reaction=="" and b.state.fighters[1].stain==0,"basketball has ordinary hurt")
	# Active windows include their first/last frame, never startup/recovery or dance gaps.
	var b=fresh()
	for id in ["P3-S2","P3-S3","P3-U1"]:
		var m: Dictionary=b.moves[id]
		for age in [m.s-1,m.s,m.s+m.a-1,m.s+m.a]:
			action(b,id,age)
			assert(b.attackbox(b.state.fighters[0]).has_area()==(age>=m.s and age<m.s+m.a))
	for age in [22,23,24,25,30,31,32,33,38,39,40,41]:
		action(b,"P3-U1",age);assert(not b.attackbox(b.state.fighters[0]).has_area())
	b=fresh();var f: Dictionary=b.state.fighters[0]
	f.energy=99;f.input.buffer="U1";b.accept_input(f,b.state.fighters[1])
	assert(f.mode=="idle" and f.energy==99,"insufficient meter")
	f.energy=200;f.max=400;f.input.buffer="U1";b.accept_input(f,b.state.fighters[1])
	assert(f.move=="P3-U1" and f.energy==100 and f.max==0 and f.enhanced)
	b=fresh();f=b.state.fighters[0];f.contact=true;f.max=121;action(b,"P3-S1",17)
	assert(b.can_cancel(f,"P3-S2") and b.can_cancel(f,"P3-U1"))
	f.max=120;assert(not b.can_cancel(f,"P3-S2"))
	f.max=121;f.chain=["P3-S2"];assert(not b.can_cancel(f,"P3-S2"))
	f.chain=[];f.max=300;f.input.buffer="S2";b.accept_input(f,b.state.fighters[1])
	assert(f.move=="P3-S2" and f.max==180,"MAX cancel spends 120")
	b=fresh();f=b.state.fighters[0];b.state.fighters[1].x=570*256;action(b,"P3-S1",16);advance(b,1)
	assert(not b.can_spawn(f,"P3-S1"),"only one basketball per owner")
	var e: Dictionary=b.state.entities[0].duplicate(true);e.owner=1;e.id=99;e.face=-1;e.vx=-e.vx
	b.state.entities.append(e);b.cancel_projectiles()
	assert(b.state.entities[0].dead and b.state.entities[1].dead,"basketballs clash")
	for other in [0,1]:
		b=fresh();b.state.fighters[1].x=570*256;action(b,"P3-S1",16);advance(b,1)
		e=b.state.entities[0].duplicate(true);e.owner=1;e.char=other;e.y=(292-Battle.PROJECTILE_HEIGHT[other])*256
		b.state.entities.append(e);b.cancel_projectiles()
		assert(b.state.entities[0].dead and e.dead,"basketball clashes with existing projectiles")
	for face in [1,-1]:
		b=fresh(2,face);f=b.state.fighters[0]
		f.x=(580 if face==1 else 60)*256;b.state.fighters[1].x=(606 if face==1 else 34)*256
		action(b,"P3-S2");advance(b,100,C.RIGHT if face==1 else C.LEFT)
		for fighter in b.state.fighters: assert(fighter.x>=34*256 and fighter.x<=606*256,"wall collision remains bounded")
	b=fresh();f=b.state.fighters[0];b.state.fighters[1].x=550*256;action(b,"P3-S2");var start: int=f.x
	advance(b,70);assert(f.x-start==64*256 and f.mode=="idle","whiff travels 64px and recovers")
	# A normal strike during startup interrupts both specials; neither has armor/invulnerability.
	for id in ["P3-S2","P3-S3"]:
		b=fresh();action(b,id);var foe: Dictionary=b.state.fighters[1];foe.mode="attack";foe.move="RW-5C";foe.age=b.moves[foe.move].s
		advance(b,1);assert(b.state.fighters[0].mode=="hurt")
		assert(advance(b,70).is_empty())
	# All twelve LB normals match the approved RW tuning, including throw and movement.
	for id in b.moves:
		if id.begins_with("LB-"):
			var a: Dictionary=b.moves[id].duplicate();var old: Dictionary=b.moves[id.replace("LB-","RW-")].duplicate()
			a.erase("id");old.erase("id");assert(a==old)
	b=fresh();b.state.fighters[1].x=570*256;action(b,"P3-S4",14);advance(b,1)
	f=b.state.fighters[0]
	assert(not b.can_spawn(f,"P3-S4") and b.can_spawn(f,"P3-S1"),"trousers limit independent from ball")
	f.mode="hurt";f.move="";f.hitstun=100
	assert(advance(b,100).size()==1 and b.state.fighters[1].hp==960,"released trousers persist after interruption")
	for id in ["P3-S1","P3-S2","P3-S3","P3-S4","P3-U1"]:
		b=fresh();action(b,id,b.moves[id].s);advance(b,1)
		var replay=Battle.new();replay.restore(b.snapshot())
		for tick in 100:
			var inputs: Array=[C.RIGHT if tick%20<10 else 0,C.LEFT if tick%30<10 else 0]
			b.step(inputs);replay.step(inputs)
			assert(b.checksum()==replay.checksum(),"skill snapshots replay deterministically")
	print("PASS little black: five skills, blocks, interruption, air/wall, meter/MAX, projectile limits/clashes, normal tuning")
	quit()
