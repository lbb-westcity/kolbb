extends SceneTree
# Production import: chroma key, fixed-grid slicing and native-size nearest sampling.
const GROUPS=["core","normals","specials","air","locomotion","reaction","performance","normals2","specials2"]
const CELL=Vector2i(384,224)
const ANCHOR=Vector2i(192,208)
# Generated sheets have uneven whitespace. Find true empty gutters before packing.
func bands(image: Image, horizontal: bool, count: int) -> Array:
	var length: int=image.get_height() if horizontal else image.get_width()
	var breadth: int=image.get_width() if horizontal else image.get_height()
	var gaps: Array=[]
	var begin: int=-1
	for a in length:
		var empty: bool=true
		for b in breadth:
			if image.get_pixel(b if horizontal else a,a if horizontal else b).a>0:
				empty=false;break
		if empty and begin<0: begin=a
		elif not empty and begin>=0:
			if a-begin>=4: gaps.append(Vector2i(begin,a))
			begin=-1
	var result: Array=[0]
	for i in range(1,count):
		var ideal: float=float(length)*i/count
		var best: float=INF
		var boundary: int=roundi(ideal)
		for gap in gaps:
			var mid: int=(gap.x+gap.y)/2
			if absf(mid-ideal)>float(length)/count*.42: continue
			var score: float=absf(mid-ideal)-(gap.y-gap.x)*.2
			if score<best: best=score;boundary=mid
		result.append(boundary)
	result.append(length)
	return result

func _initialize() -> void:
	for who in ["rajer","juguai"]:
		var packed_groups: Array=[]
		var logos: Dictionary={}
		for group in GROUPS:
			var source: String = "res://design/generated/%s_%s.png" % [who,group]
			if not FileAccess.file_exists(source): continue
			var image: Image = Image.load_from_file(source)
			image.convert(Image.FORMAT_RGBA8)
			for y in image.get_height():
				for x in image.get_width():
					var c: Color = image.get_pixel(x,y)
					if c.r>0.48 and c.b>0.45 and c.g<minf(c.r,c.b)*0.63:
						image.set_pixel(x,y,Color.TRANSPARENT)
			var atlas: Image = Image.create(CELL.x*4,CELL.y*6,false,Image.FORMAT_RGBA8)
			var rows: Array=bands(image,true,4)
			var cells: Array=[]
			for row in 4:
				var strip: Image=image.get_region(Rect2i(0,rows[row],image.get_width(),rows[row+1]-rows[row]))
				var columns: Array=bands(strip,false,6)
				for col in 6: cells.append(strip.get_region(Rect2i(columns[col],0,columns[col+1]-columns[col],strip.get_height())))
			var standing: int=cells[0].get_used_rect().size.y
			var scale_value: float=(148.0 if who=="rajer" else 144.0)/maxi(1,standing)
			if group=="air": scale_value*=0.75
			# One consistent scale per atlas, stable cell foot anchor.
			for i in 24:
				var cell: Image = cells[i]
				var used: Rect2i = cell.get_used_rect()
				if not used.has_area(): continue
				var cut: Image = cell.get_region(used)
				cut.resize(maxi(1,roundi(used.size.x*scale_value)),maxi(1,roundi(used.size.y*scale_value)),Image.INTERPOLATE_NEAREST)
				# Center base stays common; attack reach is preserved relative to source cell.
				var bottom: Image=cell.get_region(Rect2i(0,used.end.y-mini(12,used.size.y),cell.get_width(),mini(12,used.size.y)))
				var foot_x: float=bottom.get_used_rect().get_center().x
				var dx: int = ANCHOR.x+roundi((used.position.x-foot_x)*scale_value)
				var dy: int = ANCHOR.y-cut.get_height()
				assert(dx>=2 and dx+cut.get_width()<=CELL.x-2 and dy>=2,"Pose exceeds expanded cell: "+who+" "+group+" "+str(i))
				atlas.blit_rect(cut,Rect2i(Vector2i.ZERO,cut.get_size()),Vector2i((i%4)*CELL.x+dx,(i/4)*CELL.y+dy))
			atlas.save_png("res://assets/fighters/%s_%s.png" % [who,group])
			if who=="juguai":
				logos[group]=[]
				for i in 24: logos[group].append(find_logo(atlas.get_region(Rect2i(Vector2i((i%4)*CELL.x,(i/4)*CELL.y),CELL))))
			if group=="core":
				var first: Image=atlas.get_region(Rect2i(Vector2i.ZERO,CELL))
				var bounds: Rect2i=first.get_used_rect()
				var top: Image=first.get_region(Rect2i(0,bounds.position.y,CELL.x,38))
				var head: Rect2i=top.get_used_rect()
				var portrait: Image=first.get_region(Rect2i(head.get_center().x-18,bounds.position.y+3,36,36))
				portrait.save_png("res://assets/ui/%s_portrait.png" % who)
			var alternate: Image=atlas.duplicate()
			for y in alternate.get_height():
				for x in alternate.get_width():
					var c: Color=alternate.get_pixel(x,y)
					var py: int=y%CELL.y
					if c.a==0: continue
					if who=="rajer" and c.b>c.r*1.25 and c.b>c.g*1.1 and c.b<0.65:
						alternate.set_pixel(x,y,Color(c.r*.8,c.g*1.8,c.b*1.3,c.a))
					elif who=="juguai" and py>97 and py<167 and maxf(c.r,maxf(c.g,c.b))<.24 and c.r>.035 and absf(c.r-c.g)<.05:
						alternate.set_pixel(x,y,Color(c.r*1.9,c.g*.78,c.b*1.1,c.a))
			alternate.save_png("res://assets/fighters/%s_%s_alt.png" % [who,group])
			packed_groups.append(group)
			print("Prepared ",who," ",group)
		write_frames(who,packed_groups,logos)
	var bg: Image = Image.load_from_file("res://design/generated/office.png")
	bg.resize(640,360,Image.INTERPOLATE_NEAREST)
	bg.save_png("res://assets/stage/office.png")

	var source: Image=Image.load_from_file("res://design/generated/props.png")
	source.convert(Image.FORMAT_RGBA8)
	for y in source.get_height():
		for x in source.get_width():
			var color: Color=source.get_pixel(x,y)
			if color.r>0.48 and color.b>0.45 and color.g<minf(color.r,color.b)*0.63: source.set_pixel(x,y,Color.TRANSPARENT)
	var output: Image=Image.create(1024,768,false,Image.FORMAT_RGBA8)
	for i in 12:
		var cell: Image=source.get_region(Rect2i((i%4)*source.get_width()/4,(i/4)*source.get_height()/3,source.get_width()/4,source.get_height()/3))
		var used: Rect2i=cell.get_used_rect()
		var cut: Image=cell.get_region(used)
		var scale_value: float=232.0/maxi(used.size.x,used.size.y)
		cut.resize(roundi(used.size.x*scale_value),roundi(used.size.y*scale_value),Image.INTERPOLATE_NEAREST)
		output.blit_rect(cut,Rect2i(Vector2i.ZERO,cut.get_size()),Vector2i((i%4)*256+(256-cut.get_width())/2,(i/4)*256+244-cut.get_height()))
	output.save_png("res://assets/props/props.png")
	prepare_animated_props()
	quit()

func prepare_animated_props() -> void:
	var path: String="res://design/generated/props_animated.png"
	if not FileAccess.file_exists(path): return
	var source: Image=Image.load_from_file(path)
	source.convert(Image.FORMAT_RGBA8)
	for y in source.get_height():
		for x in source.get_width():
			var c: Color=source.get_pixel(x,y)
			if c.r>.48 and c.b>.45 and c.g<minf(c.r,c.b)*.63: source.set_pixel(x,y,Color.TRANSPARENT)
	var rows: Array=bands(source,true,4)
	var cells: Array=[]
	for row in 4:
		var strip: Image=source.get_region(Rect2i(0,rows[row],source.get_width(),rows[row+1]-rows[row]))
		var columns: Array=bands(strip,false,6)
		for col in 6: cells.append(strip.get_region(Rect2i(columns[col],0,columns[col+1]-columns[col],strip.get_height())))
	var result: Image=Image.create(1536,1024,false,Image.FORMAT_RGBA8)
	for i in 24:
		var r: Rect2i=cells[i].get_used_rect()
		if not r.has_area(): continue
		var family: Array=range(0,8) if i<8 else range(8,12) if i<12 else range(12,16) if i<18 else range(18,22) if i<22 else range(22,24)
		var height: int=1
		for k in family:
			var bounds: Rect2i=cells[k].get_used_rect()
			height=maxi(height,maxi(bounds.size.x,bounds.size.y))
		var scale_value: float=232.0/height
		var cut: Image=cells[i].get_region(r)
		cut.resize(maxi(1,roundi(r.size.x*scale_value)),maxi(1,roundi(r.size.y*scale_value)),Image.INTERPOLATE_NEAREST)
		result.blit_rect(cut,Rect2i(Vector2i.ZERO,cut.get_size()),Vector2i((i%6)*256+128-cut.get_width()/2,(i/6)*256+244-cut.get_height()))
	result.save_png("res://assets/props/animated.png")

func find_logo(cell: Image) -> Rect2i:
	var best: int=3
	var region: Rect2i=Rect2i()
	var bounds: Rect2i=cell.get_used_rect()
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var c: Color=cell.get_pixel(x,y)
			if c.a==0 or c.g<.28 or c.g<c.r*1.2 or c.b>c.g*.85: continue
			var count: int=0
			var left: int=x;var right: int=x;var top: int=y;var bottom: int=y
			for py in range(maxi(0,y-5),mini(cell.get_height(),y+9)):
				for px in range(maxi(0,x-18),mini(cell.get_width(),x+3)):
					var a: Color=cell.get_pixel(px,py)
					if a.a>0 and a.r>.6 and a.g>.55 and a.b>.45 and absf(a.r-a.g)<.1 and a.g-a.b<.2:
						count+=1;left=mini(left,px);right=maxi(right,px);top=mini(top,py);bottom=maxi(bottom,py)
			if count>best:
				best=count;region=Rect2i(left-1,top-1,right-left+3,bottom-top+3)
	return region

func write_frames(who: String, groups: Array, logos: Dictionary) -> void:
	var out: String='[gd_resource type="SpriteFrames" format=3]\n\n'
	var names: Array=[]
	for group in groups:
		for suffix in ["","_alt"]:
			var key: String=group+suffix
			names.append(key)
			out+='[ext_resource type="Texture2D" path="res://assets/fighters/%s_%s.png" id="%s"]\n' % [who,key,key]
	for key in names:
		for i in 24:
			out+='\n[sub_resource type="AtlasTexture" id="%s_%d"]\natlas = ExtResource("%s")\nregion = Rect2(%d, %d, %d, %d)\n' % [key,i,key,(i%4)*CELL.x,(i/4)*CELL.y,CELL.x,CELL.y]
	out+='\n[resource]\nanimations = [\n'
	for key in names:
		out+='{ "name": &"%s", "speed": 60.0, "loop": true, "frames": [' % key
		for i in 24: out+='{ "duration": 1.0, "texture": SubResource("%s_%d") },' % [key,i]
		out+='] },\n'
	out+=']\nmetadata/foot_anchor = Vector2(%d, %d)\n' % [ANCHOR.x,ANCHOR.y]
	for group in logos:
		out+='metadata/logo_%s = [' % group
		for r in logos[group]: out+='Rect2(%d, %d, %d, %d),' % [r.position.x,r.position.y,r.size.x,r.size.y]
		out+=']\n'
	FileAccess.open("res://assets/fighters/%s_frames.tres" % who,FileAccess.WRITE).store_string(out)
