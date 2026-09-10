extends SceneTree
const Rollback=preload("res://scripts/rollback.gd")
const Cpu=preload("res://scripts/cpu.gd")
var rng=RandomNumberGenerator.new()
func _initialize() -> void:
	call_deferred("run")
func repair(sender, first: int) -> Array:
	var pairs: Array=[]
	for n in range(first,first+16):
		if sender.local_inputs.has(n): pairs.append([n,sender.local_inputs[n]])
	return pairs
func run() -> void:
	var peak: int=0
	var corrections: int=0
	for profile in [0,2,4,6]:
		for game in (10 if profile<6 else 2):
			rng.seed=500+profile*30+game
			var a=Rollback.new();var b=Rollback.new()
			var chars: Array=[game%2,(game/2)%2]
			a.start(chars,game+21,55,0);b.start(chars,game+21,55,1)
			var cpus: Array=[Cpu.new(),Cpu.new()]
			cpus[0].level=2;cpus[1].level=2;cpus[0].seed_value=game+523;cpus[1].seed_value=game+215
			var packets: Array=[]
			var complete: bool=false
			for tick in 30000:
				for i in 2:
					var sender=a if i==0 else b
					var receiver=b if i==0 else a
					if sender.battle.state.phase!="done" and sender.can_advance(): sender.tick(cpus[i].sample(sender.battle,i))
					var blackout: bool=profile==6 and tick%1800>=900 and tick%1800<930
					if not blackout and rng.randf()>=.05:
						packets.append([tick+maxi(0,profile+rng.randi_range(-2,2)),receiver,sender.batch(),sender.remote_high])
					if not blackout and tick%3==0 and receiver.remote_high<sender.cursor:
						packets.append([tick+profile+2,receiver,repair(sender,receiver.remote_high+1),sender.remote_high])
				for packet in packets.duplicate():
					if packet[0]<=tick:
						packet[1].receive(packet[2],packet[3]);packets.erase(packet)
				if a.error!="" or b.error!="": printerr("FAIL chaos ",profile," ",game," ",a.error," ",b.error);quit(1);return
				if a.battle.state.phase=="done" and b.battle.state.phase=="done" and a.confirmed>=a.cursor-1 and b.confirmed>=b.cursor-1:
					if a.cursor!=b.cursor or a.battle.checksum()!=b.battle.checksum(): printerr("FAIL final convergence");quit(1);return
					complete=true;break
			if not complete: printerr("FAIL chaos match timeout");quit(1);return
			peak=maxi(peak,maxi(a.max_replay_us,b.max_replay_us));corrections+=a.rollback_count+b.rollback_count
			print("PASS chaos one-way ticks ",profile," game ",game," frame ",a.cursor," CRC ",a.battle.checksum())
	print("PASS 32 complete network simulations; 5% loss, ±2 ticks jitter, 500ms blackout; peak replay µs ",peak," corrections ",corrections)
	quit()
