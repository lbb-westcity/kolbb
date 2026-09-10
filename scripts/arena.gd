extends Node2D
const Battle = preload("res://scripts/battle.gd")
const INK = Color("0d1721")
const IVORY = Color("f0e7d5")
const CYAN = Color("45cbd1")
const ORANGE = Color("f29646")
const GOLD = Color("ffd166")
const RED = Color("e55661")
var battle
var textures: Dictionary = {}
var framesets: Dictionary = {}
var font: Font
var bg: Texture2D
var props: Texture2D
var animated_props: Texture2D
var fx: Array = []
var seen: Dictionary = {}
var time: float = 0
var trauma: float = 0
var settings: Dictionary = {}
var hud: bool = false
var demo: bool = true
var debug: bool = false
var status: String = ""
var delayed_hp: Array = [1000.0,1000.0]
var damage_wait: Array = [0.0,0.0]
var combo_hits: Array = [0,0]
var message: String = ""
var message_age: float = 0
var performance_us: int = 0
var online: bool = false
var world_offset: Vector2 = Vector2.ZERO
var confirmed: int = -1
var portrait: Array = []

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	font=load("res://assets/ui/NotoSansCJKsc-Regular.otf")
	bg=load("res://assets/stage/office.png")
	if ResourceLoader.exists("res://assets/props/props.png"): props=load("res://assets/props/props.png")
	if ResourceLoader.exists("res://assets/props/animated.png"): animated_props=load("res://assets/props/animated.png")
	for who in ["rajer","juguai"]:
		if ResourceLoader.exists("res://assets/fighters/%s_frames.tres" % who): framesets[who]=load("res://assets/fighters/%s_frames.tres" % who)
		for group in ["core","normals","specials","air","locomotion","reaction","performance","normals2","specials2"]:
			var path: String="res://assets/fighters/%s_%s.png" % [who,group]
			if ResourceLoader.exists(path):
				textures[who+"_"+group]=load(path)
				var alternate: String=path.replace(".png","_alt.png")
				if ResourceLoader.exists(alternate): textures[who+"_"+group+"_alt"]=load(alternate)
	for who in ["rajer","juguai"]:
		portrait.append(load("res://assets/ui/"+who+"_portrait.png") if ResourceLoader.exists("res://assets/ui/"+who+"_portrait.png") else null)

func reset_effects() -> void:
	seen.clear();fx.clear();trauma=0;delayed_hp=[1000.0,1000.0];damage_wait=[0.0,0.0];combo_hits=[0,0];message_age=0

func present(events: Array, audio) -> void:
	for e in events:
		if seen.has(e.id): continue
		if online and e.kind in ["ko","time","victory","round","fight"] and int(e.id.split("/")[1])-1>confirmed: continue
		seen[e.id]=battle.state.frame
		var sound: String=e.kind
		match e.kind:
			"hit": sound="heavy" if e.heavy else "light"
			"action":
				var id: String=e.move
				if id.ends_with("S1"): sound="poop" if id.begins_with("P1") else "coin"
				elif id.ends_with("S2"): sound="burger" if id.begins_with("P1") else "talk"
				elif id.ends_with("S3"): sound="summon" if id.begins_with("P1") else "capture"
				else: sound="kick" if id.ends_with("B") or id.ends_with("D") else "punch"
			"projectile": sound="poop" if battle.state.fighters[e.slot].char==0 else "coin"
		if e.kind=="victory": audio.play_music("victory")
		else: audio.sound(sound,1.0+(int(e.get("slot",0))*0.025))
		if e.kind in ["hit","block","pickup","clash","land","max","summon","slam","whip","break","stock"]:
			var effect: Dictionary=e.duplicate()
			effect.life=0.55 if e.kind in ["pickup","stock"] else 0.28
			if not settings.get("shake",true) and e.kind in ["hit","block","clash"]: effect.life+=2.0/60.0
			effect.total=effect.life
			fx.append(effect)
		if e.kind=="hit":
			combo_hits[e.target]=1 if e.get("combo_start",false) else combo_hits[e.target]+1
			damage_wait[e.target]=0.3
			if e.heavy: trauma=minf(1,trauma+0.38)
		if e.kind in ["slam","summon","super","ko"]: trauma=minf(1,trauma+0.7)
		if e.kind in ["super","capture"] or (e.kind=="denied" and e.slot==(Net.slot if online else 0)):
			message=e.get("text","");message_age=1.4
	while fx.size()>40: fx.pop_front()
	if seen.size()>500:
		for key in seen.keys():
			if battle.state.frame-seen[key]>240: seen.erase(key)

func animate(dt: float, paused: bool) -> void:
	if paused: return
	time+=dt
	trauma=maxf(0,trauma-dt*4)
	message_age=maxf(0,message_age-dt)
	for e in fx: e.life-=dt
	fx=fx.filter(func(e): return e.life>0)
	if battle:
		for i in 2:
			damage_wait[i]=maxf(0,damage_wait[i]-dt)
			var hp: float=battle.state.fighters[i].hp
			if hp>delayed_hp[i]: delayed_hp[i]=hp
			if damage_wait[i]==0: delayed_hp[i]=move_toward(delayed_hp[i],hp,dt*3500)
	queue_redraw()

func label(text: String, p: Vector2, size: int = 12, color: Color = IVORY, width: float = -1) -> void:
	draw_string(font,p+Vector2(1,1),text,HORIZONTAL_ALIGNMENT_LEFT,width,size,Color(0.02,0.04,0.07,0.9))
	draw_string(font,p,text,HORIZONTAL_ALIGNMENT_LEFT,width,size,color)
func centered(text: String,y: float,size: int=24,color: Color=IVORY) -> void:
	var w: float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	label(text,Vector2((640-w)/2,y),size,color)
func box(r: Rect2, fill: Color, edge: Color = Color.TRANSPARENT) -> void:
	draw_rect(r,fill)
	if edge.a>0: draw_rect(r,edge,false,1)
func marker(p: Vector2,slot: int,color: Color) -> void:
	if slot==0:
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(4,0),p+Vector2(0,4),p+Vector2(-4,0)]),color)
	else: draw_circle(p,4,color)

func _draw() -> void:
	if not bg or not battle: return
	var offset: Vector2=Vector2.ZERO
	if settings.get("shake",true): offset=Vector2(roundf(sin(time*93)*trauma*trauma*5),roundf(sin(time*71)*trauma*trauma*3))
	world_offset=offset
	draw_set_transform(offset)
	draw_texture_rect(bg,Rect2(0,0,640,360),false)
	# Low-frequency office lights; never consume the battle RNG.
	var phase: int=int(time*60)
	if phase%180<60: box(Rect2(194,160,20,2),Color(0.35,0.8,0.9,0.17))
	if phase%360<60: box(Rect2(379,214+(phase%60)/15,7,2),Color(0.7,0.77,0.78,0.3))
	if battle.state.freeze>=10:
		box(Rect2(0,56,640,264),Color(0,0,0,0.15 if settings.get("flash",false) else 0.35))
	for f in battle.state.fighters:
		var height: float=(Battle.GROUND-f.y)/256.0
		draw_set_transform(offset+Vector2(f.x/256.0,293),0,Vector2(1,0.18))
		draw_circle(Vector2.ZERO,maxf(12,22+f.char*3-height*.06),Color(0,0,0,.28))
	draw_set_transform(offset)
	for f in battle.state.fighters:
		var action_age: int=maxi(0,f.age-1)
		if f.move=="P1-S3" and action_age<28:
			var x: float=f.target_x/256.0
			draw_arc(Vector2(x,292),56,0,TAU,32,Color(CYAN,0.6),1)
			box(Rect2(x-56,289,112,2),Color(CYAN,0.25))
			label("!",Vector2(x-3,281),12,GOLD)
			if action_age>=24: draw_animated_prop(1 if action_age>=26 else 0,Vector2(x,292-(28-action_age)*38),Vector2(256,256))
	for e in battle.state.entities: draw_entity(e)
	if battle.state.cinema.is_empty():
		for f in battle.state.fighters: draw_fighter(f)
	else: draw_cinema()
	draw_set_transform(offset)
	for e in fx: draw_effect(e)
	draw_set_transform(Vector2.ZERO)
	if hud: draw_hud()
	if not demo: draw_round_text()
	if message_age>0 and hud:
		box(Rect2(170,65,300,24),Color(INK,0.92))
		centered(message,83,14,GOLD)
	if debug:
		for f in battle.state.fighters:
			for pair in [[battle.hurtbox(f),Color(0,1,0,.35)],[battle.attackbox(f),Color(1,0,0,.5)]]:
				var r: Rect2i=pair[0]
				draw_rect(Rect2(Vector2(r.position)/256.0,Vector2(r.size)/256.0),pair[1],false)
		label("%d FPS  sim %d µs  frame %d  entities %d" % [Engine.get_frames_per_second(),performance_us,battle.state.frame,battle.state.entities.size()],Vector2(10,315),10,CYAN)

func animation(f: Dictionary) -> Array:
	# Stored fighter age points at the next simulation tick; render the tick just resolved.
	f=f.duplicate();f.age=maxi(0,f.age-1)
	var group: String="core"
	var frame: int=(int(time*60)/8)%6
	var mode: String=f.mode
	if mode=="walk":
		group="locomotion" if f.input.dir==4 else "core";frame=(0 if f.input.dir==4 else 6)+(f.age/6)%6
	elif mode=="run": group="locomotion";frame=6+(f.age/4)%6
	elif mode=="backstep": group="locomotion";frame=12+mini(3,f.age/6)
	elif mode=="crouch": group="locomotion";frame=16+mini(2,f.age/2)
	elif mode=="jump_prepare": group="locomotion";frame=16 if f.age<2 else 19
	elif mode=="land": group="locomotion";frame=22+mini(1,f.age/2)
	elif mode=="air": group="locomotion";frame=20 if f.vy<0 else 21
	elif mode=="guard": group="reaction";frame=(2 if f.input.dir==1 else 0)+mini(1,f.age/3)
	elif mode=="hurt":
		if f.y<Battle.GROUND: group="reaction";frame=7+mini(1,f.age/5)
		else: frame=21
	elif mode=="down": group="reaction";frame=9+mini(2,f.age/4)
	elif mode=="getup": group="reaction";frame=12+mini(2,f.age/4)
	elif mode=="roll": group="reaction";frame=15+(f.age/2 if f.age<4 else 2+mini(2,(f.age-4)/4) if f.age<16 else 5+mini(1,(f.age-16)/7))
	elif mode=="max_start": group="performance";frame=12+mini(3,f.age/3)
	elif mode=="cinema": frame=18
	elif mode=="attack":
		var m: Dictionary=battle.moves[f.move]
		var phase_frame: int=mini(1,f.age*2/maxi(1,m.s)) if f.age<m.s else 3 if f.age<m.s+m.a else 4+mini(1,(f.age-m.s-m.a)*2/maxi(1,m.r))
		if m.kind=="normal":
			if f.move.contains("-j"):
				group="air";frame="ABCD".find(f.move.right(1))*6+phase_frame
			else:
				group="normals"
				var row: int=0
				if f.move.contains("-2"):
					row=3 if f.move.ends_with("B") or f.move.ends_with("D") else 2
				elif f.move.ends_with("B") or f.move.ends_with("D"): row=1
				frame=row*6+phase_frame
				if f.move.ends_with("2A"):
					group="normals2";frame=12+phase_frame
				elif f.move.ends_with("2B"): group="normals2";frame=18+phase_frame
				elif f.move.ends_with("5C"): group="normals2";frame=phase_frame
				elif f.move.ends_with("5D"): group="normals2";frame=6+phase_frame
		else:
			group="specials"
			var row: int=0
			if f.char==0:
				row=1 if m.kind=="summon" else 2 if m.kind in ["room","throw"] else 0
			else:
				row=1 if m.kind=="talk" else 2 if m.kind in ["grab","throw"] else 3 if m.kind=="papers" else 0
			frame=row*6+phase_frame
			if f.char==0:
				if m.kind=="burger": group="specials2";frame=phase_frame
				elif m.kind=="room": group="specials2";frame=6+mini(1,f.age/8)
				elif m.kind=="throw": group="specials2";frame=14+mini(1,f.age/2)
			else:
				if m.kind=="talk":
					group="specials2"
					frame=mini(1,f.age/5) if f.age<10 else 2 if f.age<13 else 3 if f.age<20 else 4+mini(1,(f.age-20)/2) if f.age<24 else 6+mini(1,(f.age-24)/11)
				elif m.kind=="grab": group="specials2";frame=8+mini(1,f.age/4)
				elif m.kind=="papers": group="specials2";frame=16+(mini(1,f.age/9) if f.age<18 else 2+mini(3,(f.age-18)/9) if f.age<54 else 6+mini(1,(f.age-54)/15))
	if f.reaction!="" and f.reaction_time>0:
		group="performance"
		frame=18+mini(2,(18-f.reaction_time)/6) if f.reaction=="poop" else 21+mini(2,(24-f.reaction_time)/8)
	elif f.pickup>6 and battle.is_free(f): group="performance";frame=16+int(f.pickup<9)
	if battle.state.phase=="intro": group="performance";frame=mini(5,(120-battle.state.phase_time)/20)
	if battle.state.phase in ["result","done"] and f.slot==battle.state.winner: group="performance";frame=6+mini(5,(180-battle.state.phase_time)/10)
	return [group,clampi(frame,0,23)]

func draw_fighter(f: Dictionary,override_pos: Vector2=Vector2.INF,override_frame: int=-1,shadow: bool=false,override_anim: Array=[],render_scale: float=1.0) -> void:
	var anim: Array=animation(f)
	if override_frame>=0: anim=["core",override_frame]
	if not override_anim.is_empty(): anim=override_anim
	var who: String="rajer" if f.char==0 else "juguai"
	var key: String=who+"_"+anim[0]
	if not textures.has(key): key=who+"_core";anim=["core",19]
	var tex: Texture2D=textures[key]
	var p: Vector2=Vector2(roundf(f.x/256.0),roundf(f.y/256.0)) if override_pos==Vector2.INF else override_pos
	var frame: int=anim[1]
	var squash: Vector2=Vector2.ONE
	if f.mode=="max_start": squash=Vector2(1.05,.95)
	if f.mode=="hurt" and f.age<=4: squash=Vector2(.93,1.04)
	squash*=render_scale
	var color: Color=Color(0.06,0.09,0.14) if shadow else Color.WHITE
	if battle.state.fighters[0].char==battle.state.fighters[1].char and f.slot==1 and not shadow:
		var alt_key: String=key+"_alt"
		if textures.has(alt_key): tex=textures[alt_key]
	var rot: float=0
	draw_set_transform(p+world_offset,rot,Vector2(f.face,1)*squash)
	if f.max>0 and int(time*10)%2==0:
		draw_arc(Vector2(0,-2),32,PI,TAU,16,GOLD,1)
		draw_line(Vector2(-25,-105),Vector2(-25,-85),GOLD,1)
	var sequence: String=anim[0]+("_alt" if battle.state.fighters[0].char==battle.state.fighters[1].char and f.slot==1 and not shadow else "")
	var anchor: Vector2=framesets[who].get_meta("foot_anchor",Vector2(128,176)) if framesets.has(who) else Vector2(128,176)
	if framesets.has(who) and framesets[who].has_animation(sequence):
		draw_texture(framesets[who].get_frame_texture(sequence,frame),-anchor,color)
	else: draw_texture_rect_region(tex,Rect2(-128,-176,256,192),Rect2((frame%6)*256,(frame/6)*192,256,192),color)
	# The chest print faces the reader even when the body faces left.
	if f.char==1 and f.face<0 and not shadow and framesets.has(who):
		var logos: Array=framesets[who].get_meta("logo_"+anim[0],[])
		if logos.size()>frame:
			var r: Rect2=logos[frame]
			if r.has_area():
				draw_set_transform(p+world_offset,rot,squash)
				var frame_tex: AtlasTexture=framesets[who].get_frame_texture(sequence,frame)
				draw_texture_rect_region(tex,Rect2(anchor.x-r.end.x,r.position.y-anchor.y,r.size.x,r.size.y),Rect2(r.position+frame_tex.region.position,r.size))
	draw_set_transform(Vector2.ZERO)
	if not shadow:
		marker(p+Vector2(0,8),f.slot,CYAN if f.slot==0 else ORANGE)
		if f.stain>0: box(Rect2(p+Vector2(f.face*4-5,-132),Vector2(10,6)),Color("79442b"))
	if f.mode=="attack" and f.move=="P2-S2" and f.age>=9 and f.age<=20:
		var x: float=p.x+f.face*60
		box(Rect2(x-28,p.y-143,56,24),IVORY,INK)
		label("绩效？",Vector2(x-23,p.y-125),14,INK)

func draw_prop(index: int,p: Vector2,size: Vector2,tint: Color=Color.WHITE) -> void:
	if props:
		draw_texture_rect_region(props,Rect2(p.x-size.x/2,p.y-size.y*244/256,size.x,size.y),Rect2((index%4)*256,(index/4)*256,256,256),tint)

func draw_animated_prop(index: int,p: Vector2,size: Vector2) -> void:
	if animated_props: draw_texture_rect_region(animated_props,Rect2(p.x-size.x/2,p.y-size.y*244/256,size.x,size.y),Rect2((index%6)*256,(index/6)*256,256,256))

func draw_entity(e: Dictionary) -> void:
	var p: Vector2=Vector2(e.x/256.0,e.y/256.0)
	if e.kind=="projectile":
		var color: Color=Color("9d7040") if e.char==0 else GOLD
		for i in 3: draw_line(p-Vector2(e.face*(8+i*5),0),p-Vector2(e.face*(13+i*5),0),Color(color,0.5-i*.1),2)
		if animated_props: draw_animated_prop(18+(e.age/4)%4 if e.char==0 else 22+(e.age/4)%2,p+Vector2(0,10),Vector2(22,22))
		else: draw_prop(2 if e.char==0 else 3,p+Vector2(0,10),Vector2(25,25))
	elif e.kind in ["burger","pizza"]:
		if e.life<=30 and not settings.get("flash",false) and (e.life/4)%2==0: return
		draw_prop(0 if e.kind=="burger" else 1,p,Vector2(28,24),Color(1,1,1,.5 if e.life<=30 and settings.get("flash",false) else 1))
		var ready: bool=e.age>=e.travel+(30 if e.kind=="burger" else 12)
		var color: Color=CYAN if e.owner==0 else ORANGE
		if ready: marker(p+Vector2(0,-29),e.owner,color)
		elif e.owner==0: draw_polyline(PackedVector2Array([p+Vector2(0,-33),p+Vector2(4,-29),p+Vector2(0,-25),p+Vector2(-4,-29),p+Vector2(0,-33)]),color,1)
		else: draw_arc(p+Vector2(0,-29),4,0,TAU,12,color,1)
		label(str(e.owner+1),p+Vector2(7,-25),8,color)
		if ready:
			var friendly: bool=e.owner==(Net.slot if online else 0)
			if friendly or e.kind=="burger": label("+" if friendly else "−",p+Vector2(-15,-25),10,Color("79c878") if friendly else RED)
	elif e.kind=="summon":
		if animated_props: draw_animated_prop(2+e.age if e.age<4 else 7,p-Vector2(0,maxi(0,e.age-4)*12),Vector2(256,256))
		else: draw_prop(4 if e.age<8 else 5,p,Vector2(214,214))
	elif e.kind=="papers":
		for i in 18:
			var x: float=e.x/256.0+e.face*(40+(i*31+e.age*15)%530)
			var y: float=275-((i*19)%100)
			if x>16 and x<624: draw_prop(10,Vector2(x,y),Vector2(18,23))

func draw_cinema() -> void:
	var c: Dictionary=battle.state.cinema.duplicate()
	c.age=maxi(0,c.age-1)
	var a: Dictionary=battle.state.fighters[c.owner]
	var b: Dictionary=battle.state.fighters[c.target]
	var x: float=clampf(a.x/256.0+a.face*42,120,520)
	if c.kind=="room":
		box(Rect2(0,56,640,264),Color(0,0,0,.3))
		if animated_props: draw_animated_prop(8 if c.age<6 else 9 if c.age<12 else 10 if c.age<60 else 11,Vector2(x,292),Vector2(215,215))
		else: draw_prop(7 if c.age<12 or c.age>60 else 6,Vector2(x,292),Vector2(195,205))
		if c.age>=12 and c.age<=60:
			draw_fighter(a,Vector2(x-28,258),-1,true,["specials2",9+(c.age/4)%3],.42)
			draw_fighter(b,Vector2(x+28,258),21,true,[],.42)
		elif c.age>60:
			draw_fighter(a,Vector2(x-28,292),-1,false,["specials2",12])
			draw_fighter(b,Vector2(x+30+(c.age-60)*4,292),22)
		label("小黑屋",Vector2(x-23,132),14,GOLD)
	elif c.kind=="grab":
		var pose: int=8 if c.age<4 else 9 if c.age<8 else 10 if c.age<24 else 11 if c.age<36 else 12 if c.age<38 else 13 if c.age<44 else 14 if c.age<50 else 15
		draw_fighter(a,Vector2(x-a.face*43,292),-1,false,["specials2",pose])
		draw_fighter(b,Vector2(x+a.face*30,292),21)
		if animated_props: draw_animated_prop(12 if c.age<6 else 13 if c.age<36 else 14 if c.age<48 else 15,Vector2(x,292),Vector2(170,125))
		else: draw_prop(8,Vector2(x,292),Vector2(150,106))
		if c.age>=36: label("加班",Vector2(x-18,222),18,RED)
	else:
		draw_fighter(a,Vector2(x-a.face*25,292),-1,false,["specials2",14+mini(5,c.age/5)] if a.char==0 else ["specials",12+mini(5,c.age/5)])
		draw_fighter(b,Vector2(x+a.face*40,292-mini(c.age,15)*2),21 if c.age<18 else 22)

func draw_effect(e: Dictionary) -> void:
	var p: Vector2=Vector2(e.x,e.y)
	var k: float=e.life/e.total
	var color: Color=CYAN if e.slot==0 else ORANGE
	if e.kind=="block":
		draw_arc(p,18+(1-k)*8,-PI*.6,PI*.6,12,Color(CYAN,k),2)
	elif e.kind in ["hit","slam","whip","clash"]:
		var radius: float=maxf(1,(24 if e.get("heavy",false) else 15)*k)
		var points=PackedVector2Array()
		for i in 16:
			var r: float=radius if i%2==0 else radius*.32
			points.append(p+Vector2(cos(i*TAU/16),sin(i*TAU/16))*r)
		draw_colored_polygon(points,Color(IVORY,k))
		for i in 7:
			var v=Vector2(cos(i*2.4),sin(i*2.4))
			draw_line(p+v*(12+(1-k)*20),p+v*(17+(1-k)*24),Color(color,k),2)
		if e.get("damage",0)>0: label(str(e.damage),p+Vector2(14,-20-(1-k)*15),12,Color(IVORY,k))
	elif e.kind=="pickup": label(e.text,p+Vector2(-15,-(1-k)*15),16,Color("79c878") if e.damage<0 else RED)
	elif e.kind in ["max","stock"]:
		draw_arc(Vector2(e.x,289),24+(1-k)*30,PI,TAU,20,Color(GOLD,k),2)
		if e.kind=="max": label("MAX",Vector2(e.x-20,210-(1-k)*20),18,GOLD)
	else:
		for i in 5: box(Rect2(e.x-22+i*10,290-(1-k)*10,5*k,3*k),Color(IVORY,k*.4))

func draw_hud() -> void:
	box(Rect2(0,0,640,57),Color(INK,.96))
	box(Rect2(0,320,640,40),Color(INK,.95))
	for i in 2:
		var f: Dictionary=battle.state.fighters[i]
		var color: Color=CYAN if i==0 else ORANGE
		var x: int=50 if i==0 else 362
		var headx: int=8 if i==0 else 596
		box(Rect2(headx,8,36,36),Color("293d50"),color)
		var tex: Texture2D=portrait[f.char]
		if tex: draw_texture_rect(tex,Rect2(headx,8,36,36),false)
		label(Battle.NAMES[f.char],Vector2(x,19),12,IVORY)
		label("1P" if i==0 else "2P",Vector2(x+201,18),10,color)
		box(Rect2(x,24,228,12),Color("172735"),Color("8b9a9f"))
		var w: float=226*f.hp/1000.0
		var trail: float=226*delayed_hp[i]/1000.0
		box(Rect2(x+1 if i==0 else x+227-trail,25,trail,10),RED)
		box(Rect2(x+1 if i==0 else x+227-w,25,w,10),IVORY)
		for j in 2: marker(Vector2(x+6+j*13 if i==0 else x+222-j*13,45),i,GOLD if battle.state.wins[i]>j else Color("46616a"))
		var ex: int=16 if i==0 else 408
		label("POW",Vector2(ex,334),10,color)
		for j in 3:
			var amount: float=clampf(f.energy-j*100,0,100)/100.0
			box(Rect2(ex+j*73,339,70,12),Color("172735"),GOLD if amount==1 else Color("46616a"))
			box(Rect2(ex+j*73+1,340,68*amount,10),RED if f.flash_meter>0 else GOLD if amount==1 else color)
		if f.max>0:
			label("MAX",Vector2(ex+48,333),10,GOLD)
			box(Rect2(ex+76,325,140,5),Color("293d50"))
			box(Rect2(ex+76,325,140.0*f.max/f.max_total,5),GOLD)
		var target: Dictionary=battle.state.fighters[1-i]
		if target.combo_age>0 and combo_hits[1-i]>=2:
			label("%d HITS" % combo_hits[1-i],Vector2(16 if i==0 else 536,110),18,color)
			label("%d DAMAGE" % target.combo_damage,Vector2(16 if i==0 else 536,125),10,IVORY)
	centered("%02d" % ceili(battle.state.time/60.0),34,28,RED if battle.state.time<=1200 else IVORY)
	if status!="": centered(status,49,10,CYAN)
	centered("KOLBB",348,12,Color("8b9a9f"))

func draw_round_text() -> void:
	var s: Dictionary=battle.state
	var text: String=""
	if s.phase=="intro": text="下班之前，分个胜负。"
	elif s.phase=="round": text="ROUND %d" % s.round
	elif s.phase=="ready": text="FIGHT!"
	elif s.phase=="result":
		if online and s.frame-1>confirmed: text="确认对局结果…"
		else: text="DRAW" if s.winner<0 else "K.O." if s.time>0 else "TIME OVER"
	if text!="":
		box(Rect2(0,142,640,63),Color(INK,.8))
		centered(text,186,30 if s.phase!="intro" else 20,GOLD if s.phase=="ready" else IVORY)
