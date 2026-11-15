class_name Sfx
extends RefCounted
## A tiny synthesizer. Every sound effect is generated at startup, so the
## project needs no audio files.

const RATE := 22050
const KINDS := [
	"sidearm", "rifle", "rotary", "shiv", "enemy_shot", "bite", "door", "push",
	"pickup", "weapon", "key", "hurt", "alert", "hound", "die", "denied",
	"exit", "secret", "player_die", "boss_alert", "launch", "blast",
	"slugger", "nail", "arc", "baton", "alarm", "vent",
	"chime_r", "chime_b", "chime_g",
	"chime_rbg", "chime_rgb", "chime_brg", "chime_bgr", "chime_grb", "chime_gbr",
]
const CHIME_HZ := {"r": 523.0, "b": 659.0, "g": 880.0}


static func make(kind: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var s := PackedFloat32Array()
	match kind:
		"sidearm": s = _shot(rng, 0.22, 110.0, 0.9, false)
		"rifle": s = _shot(rng, 0.14, 130.0, 0.8, false)
		"rotary": s = _shot(rng, 0.09, 150.0, 0.7, false)
		"enemy_shot": s = _shot(rng, 0.2, 80.0, 0.7, true)
		"bite": s = _shot(rng, 0.1, 300.0, 0.5, true)
		"shiv": s = _swish(rng)
		"door": s = _rumble(rng, 0.45, 55.0, 0.45)
		"push": s = _rumble(rng, 1.4, 38.0, 0.55)
		"pickup": s = _sweep(500.0, 1100.0, 0.1, 0.3, true)
		"weapon": s = _arp([392.0, 523.0, 659.0, 784.0], 0.06, 0.3)
		"key": s = _arp([660.0, 990.0], 0.08, 0.3)
		"hurt": s = _sweep(150.0, 60.0, 0.2, 0.5, false)
		"alert": s = _arp([880.0, 587.0], 0.09, 0.25)
		"hound": s = _arp([1200.0, 900.0, 1200.0], 0.05, 0.22)
		"die": s = _die(rng)
		"denied": s = _sweep(95.0, 85.0, 0.3, 0.35, true)
		"exit": s = _arp([523.0, 659.0, 784.0, 1046.0], 0.1, 0.3)
		"secret": s = _arp([440.0, 554.0, 659.0, 880.0, 1108.0], 0.07, 0.28)
		"player_die": s = _sweep(320.0, 40.0, 0.9, 0.5, false)
		"boss_alert": s = _sweep(90.0, 38.0, 1.1, 0.7, true)
		"launch": s = _shot(rng, 0.4, 55.0, 0.6, true)
		"blast": s = _rumble(rng, 0.9, 28.0, 0.9)
		"slugger": s = _shot(rng, 0.32, 70.0, 1.0, false)
		"nail": s = _shot(rng, 0.07, 420.0, 0.45, true)
		"arc": s = _sweep(1900.0, 500.0, 0.12, 0.3, true)
		"baton": s = _rumble(rng, 0.16, 120.0, 0.6)
		"alarm": s = _arp([880.0, 660.0, 880.0, 660.0, 880.0, 660.0], 0.12, 0.3)
		"vent": s = _rumble(rng, 1.3, 260.0, 0.35)
		_:
			if kind.begins_with("chime_"):
				var notes := []
				for ch in kind.substr(6):
					notes.append(CHIME_HZ[ch])
				s = _arp(notes, 0.32, 0.3)
			else:
				s = _sweep(440.0, 440.0, 0.1, 0.3, true)
	return _to_wav(s)


static func _to_wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


static func _shot(rng: RandomNumberGenerator, dur: float, thump_hz: float, vol: float, muffled: bool) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := pow(1.0 - float(i) / n, 2.5)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.25 if muffled else 0.6)
		var thump := sin(TAU * thump_hz * t) * exp(-t * 30.0)
		out[i] = (lp * 0.8 + thump * 0.7) * env * vol
	return out


static func _swish(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.16)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var k := float(i) / n
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.05 + 0.3 * k)
		out[i] = lp * sin(PI * k) * 0.9
	return out


static func _rumble(rng: RandomNumberGenerator, dur: float, hz: float, vol: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		var sq := signf(sin(TAU * hz * t)) * 0.35
		var env := minf(1.0, t * 25.0) * minf(1.0, (dur - t) * 5.0)
		out[i] = (sq + lp * 2.0) * env * vol
	return out


static func _sweep(f0: float, f1: float, dur: float, vol: float, square: bool) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * lerpf(f0, f1, k) / RATE
		var v := signf(sin(phase)) * 0.6 if square else sin(phase)
		out[i] = v * (1.0 - k) * minf(1.0, i / 80.0) * vol
	return out


static func _arp(freqs: Array, note: float, vol: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var m := int(RATE * note)
	for f in freqs:
		for i in m:
			var k := float(i) / m
			out.append(signf(sin(TAU * float(f) * i / RATE)) * 0.6 * (1.0 - k * 0.7) * vol)
	return out


static func _die(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * lerpf(420.0, 50.0, k) / RATE
		var v := signf(sin(phase)) * 0.5 + rng.randf_range(-0.4, 0.4)
		out[i] = v * (1.0 - k) * 0.45
	return out
