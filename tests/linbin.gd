extends SceneTree
const Battle=preload("res://scripts/battle.gd")
const C=preload("res://scripts/commands.gd")
const Cpu=preload("res://scripts/cpu.gd")

func _initialize() -> void: call_deferred("run")
func fresh(face: int=1, foe: int=0):
	var b=Battle.new();b.reset([3,foe]);b.state.phase="fight"
	b.state.fighters[0].x=(240 if face==1 else 400)*256
	b.state.fighters[1].x=b.state.fighters[0].x+face*110*256
	b.state.fighters[0].face=face;b.state.fighters[1].face=-face
	return b
func action(b, id: String, age: int=0, slot: int=0) -> void:
	var f: Dictionary=b.state.fighters[slot]
	f.mode="attack";f.move=id;f.age=age;f.action_id=b.state.next_id;b.state.next_id+=1
	f.start_x=f.x;f.contact=false;f.hits.clear()
func ticks(b,n: int,buttons: Array=[0,0]) -> Array:
	var hits: Array=[]
	for i in n:
		for e in b.step(buttons):
			if e.kind in ["hit","block"]: hits.append(e.duplicate())
	return hits
func shot(b, id: String, owner: int, x: int=320, reflected: bool=false) -> Dictionary:
	var ch: int=int(id.substr(1,1))-1
	b.entity({"kind":"projectile","owner":owner,"x":x*256,"y":204*256,"vx":(1 if owner==0 else -1)*4*256,"face":1 if owner==0 else -1,"life":80,"age":0,"char":ch,"move":id,"hits":[],"source_frame":71,"reflected":reflected})
	return b.state.entities[-1]
func marked(b, slot: int=1, left: int=180) -> void:
	b.state.fighters[slot].deadline={"owner":1-slot,"left":left,"damage":200,"source":"test"}

func run() -> void:
	for face in [1,-1]:
		var forward: int=C.RIGHT if face==1 else C.LEFT
		var back: int=C.LEFT if face==1 else C.RIGHT
		for entry in [[[C.DOWN,forward],C.A,"S1"],[[C.DOWN,back],C.C,"S2"],[[forward,C.DOWN],C.B,"S3"],[[forward,C.DOWN],C.D,"S3"],[[C.DOWN,forward,C.DOWN,forward],C.C,"U1"]]:
			var input: Dictionary=C.fresh()
			for bits in entry[0]: C.sample(input,bits,face,3,false)
			C.sample(input,entry[0][-1]|entry[1],face,3,false)
			assert(input.buffer==entry[2],"both facing command recognition")
		var b=fresh(face);var f: Dictionary=b.state.fighters[0];var foe: Dictionary=b.state.fighters[1]
		action(b,"P4-S1");var x: int=f.x
		assert(ticks(b,85).size()==1 and foe.hp==925,"pat hits exactly once")
		assert(absi(f.x-x)<=80*256 and absi(f.x-x)>0,"pat advances at most 80 pixels")
		b=fresh(face);action(b,"P4-S1")
		assert(ticks(b,85,[0,forward]).size()==1 and b.state.fighters[1].hp==993,"pat guarded")
		b=fresh(face);b.state.fighters[1].x=(600 if face==1 else 40)*256
		action(b,"P4-S1",12);x=b.state.fighters[0].x;ticks(b,8)
		assert(absi(b.state.fighters[0].x-x)==80*256,"whiff dash has fixed 80 pixel ceiling")
		b=fresh(face);action(b,"P4-S2",18);ticks(b,1)
		assert(b.state.entities.size()==1 and not b.can_spawn(b.state.fighters[0],"P4-S2"))
		assert(b.can_spawn(b.state.fighters[0],"P4-S3"),"tea and words coexist")
		ticks(b,60);assert(b.state.fighters[1].hp==940,"tea damage")
		b=fresh(face);action(b,"P4-S2",18);ticks(b,1)
		b.state.entities[0].move="P1-S1"
		assert(b.can_spawn(b.state.fighters[0],"P4-S2"),"reflected other projectile does not consume tea limit")
		b=fresh(face);action(b,"P4-S3",22);ticks(b,1)
		assert(absi(b.state.entities[0].vx)==3*256 and b.state.entities[0].life==99)
		ticks(b,70);assert(b.state.fighters[1].hp==950,"words are also a ranged hit")
		b=fresh(face);action(b,"P4-U1",24);ticks(b,1)
		foe=b.state.fighters[1]
		assert(foe.hp==980 and foe.deadline.left==180)
		var world: int=b.state.world
		while b.state.world<world+179: b.step([0,0])
		assert(foe.hp==980 and foe.deadline.left==1)
		b.step([0,forward]);assert(foe.hp==780 and foe.deadline.is_empty() and foe.hitstun==30,"deadline ignores guarding at expiry")
		b=fresh(face);action(b,"P4-U1",24);ticks(b,1,[0,forward])
		assert(b.state.fighters[1].deadline.is_empty() and b.state.fighters[1].hp==998,"blocked notice never marks")
		for evade in ["roll","air"]:
			b=fresh(face);foe=b.state.fighters[1];foe.mode=evade;foe.age=8
			if evade=="air": foe.y-=160*256
			action(b,"P4-U1",24);ticks(b,1)
			assert(foe.hp==1000 and foe.deadline.is_empty(),"notice can be evaded")
	# Every ordinary projectile keeps its identity and lifetime, with new ownership.
	for id in ["P1-S1","P2-S1","P3-S1","P3-S4","P4-S2"]:
		for reverse in [false,true]:
			var b=fresh();var projectile: Dictionary
			if reverse:
				projectile=shot(b,id,1);shot(b,"P4-S3",0)
			else:
				shot(b,"P4-S3",0);projectile=shot(b,id,1)
			b.cancel_projectiles()
			assert(projectile.owner==0 and projectile.vx==4*256 and projectile.face==1 and projectile.reflected and not projectile.dead)
			assert(projectile.move==id and projectile.life==80 and projectile.hits.is_empty())
			projectile.x=b.state.fighters[1].x
			var contacts: Array=[];b.collect_entity(projectile,contacts)
			assert(contacts.size()==1);b.apply_hit(contacts[0])
			assert(b.report[0].damage==b.moves[id].damage and b.report[1].damage==0,"reflector gets damage credit")
			assert(b.state.fighters[1].reaction==("poop" if id=="P1-S1" else "laugh" if id=="P2-S1" else ""),"origin reaction preserved")
	for id in ["P4-S3","P1-S1"]:
		var b=fresh();var a=shot(b,"P4-S3",0);var p=shot(b,id,1,320,true)
		b.cancel_projectiles();assert(a.dead and p.dead,"words and already reflected shots cancel")
	var b=fresh();var wave=shot(b,"P4-S3",0)
	b.entity({"kind":"papers","owner":1,"x":wave.x,"y":wave.y})
	b.cancel_projectiles();assert(not wave.dead and not b.state.entities[1].dead,"super is not reflected")
	# Expiring status is cancelled by a same-tick hit, including a previously fired shot.
	b=fresh();marked(b,1,1)
	var p=shot(b,"P1-S1",1);p.x=b.state.fighters[0].x+4*256
	b.step([0,0]);assert(b.state.fighters[1].deadline.is_empty() and b.state.fighters[1].hp==1000)
	b=fresh();marked(b,1,1);p=shot(b,"P1-S1",1);p.x=b.state.fighters[0].x+4*256
	b.step([C.LEFT,0]);assert(b.state.fighters[1].hp==800,"chip does not clear deadline")
	b=fresh();marked(b);b.state.freeze=5;ticks(b,5)
	assert(b.state.fighters[1].deadline.left==180,"freeze pauses deadline")
	b.start_cinema({"owner":0,"target":1,"kind":"throw","move":"LN-THROW"});ticks(b,10)
	assert(b.state.fighters[1].deadline.left==180,"cinema pauses deadline")
	b=fresh();marked(b);action(b,"P4-U1",24);b.step([0,0])
	assert(b.state.fighters[1].deadline.left==179,"repeat cannot refresh or stack")
	b=fresh();action(b,"P4-U1",24);b.state.fighters[0].enhanced=true;b.step([0,0])
	assert(b.state.fighters[1].deadline.damage==260)
	b=fresh();marked(b,1,1);b.state.fighters[1].mode="down";b.step([0,0])
	assert(b.state.fighters[1].hp==800,"expiry cannot be dodged on ground")
	b=fresh(1,3);marked(b,0,1);marked(b,1,1);b.step([0,0])
	assert(b.state.fighters[0].hp==800 and b.state.fighters[1].hp==800,"mirror expirations simultaneous")
	b=fresh();marked(b);b.state.time=0;b.check_end()
	assert(b.state.fighters[1].deadline.is_empty(),"round result clears status")
	# Snapshot replay includes reflected provenance, deadline and reported damage.
	b=fresh(1,3);marked(b,1,24);shot(b,"P4-S3",0);shot(b,"P4-S2",1)
	var saved: Dictionary=b.snapshot();ticks(b,280);var crc: int=b.checksum();var report: Array=b.report.duplicate(true)
	b.restore(saved);ticks(b,280)
	assert(b.checksum()==crc and b.report==report,"deterministic reflection and deadline replay")
	for level in 3:
		for foe in 4:
			for side in 2:
				b=Battle.new();b.reset([3,foe] if side==0 else [foe,3],73129+foe*31+level)
				var bots: Array=[Cpu.new(),Cpu.new()]
				for i in 2: bots[i].level=level;bots[i].seed_value=12345+i*9127+foe
				for i in 32000:
					b.step([bots[0].sample(b,0),bots[1].sample(b,1)])
					for f in b.state.fighters: assert(f.hp>=0 and f.hp<=1000 and f.energy>=0 and f.energy<=300)
					if b.state.phase=="done": break
				assert(b.state.phase=="done","CPU match must finish")
	print("PASS Linbin: four skills, reflection, deadlines, snapshot replay and 24 CPU matches")
	quit()
