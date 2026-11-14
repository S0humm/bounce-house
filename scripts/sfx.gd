extends Node
## Procedural sound: every effect is synthesized in code at startup, so there are no audio files.

const RATE := 22050
const POOL := 16
const PENTATONIC := [0, 2, 4, 7, 9]

const SINE := 0
const SQUARE := 1
const TRI := 2
const SAW := 3

var samples := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var muted := false
var pending: Array = []   # [name, Callable] pairs still waiting to be synthesized

func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = -3.0
		add_child(p)
		players.append(p)
	_build()

# Synthesize one sound per frame so startup (especially in a browser) never stalls.
func _process(_delta: float) -> void:
	if pending.is_empty():
		set_process(false)
		return
	var job: Array = pending.pop_front()
	samples[job[0]] = _wav(job[1].call())

# ---------- Playback ----------

func play(sound: String, pitch := 1.0, db := 0.0) -> void:
	if muted or not samples.has(sound):
		return
	var p := players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = samples[sound]
	p.pitch_scale = maxf(pitch, 0.05)
	p.volume_db = -3.0 + db
	p.play()

# Pitch for the Nth hit in a row: climbs a pentatonic scale (about an octave and a sixth),
# so a long chain of hits sounds like a rising melody instead of noise.
func ladder(step: int) -> float:
	var s := clampi(step, 0, 9)
	var semis: int = PENTATONIC[s % 5] + 12 * (s / 5)
	return pow(2.0, semis / 12.0)

func toggle_mute() -> bool:
	muted = not muted
	return muted

# ---------- Sound design ----------

func _build() -> void:
	# Chip hits
	_queue("blip", func(): return _tone(659.25, 659.25, 0.13, SINE, 0.5, 6.0, 0.35))
	_queue("ding_red", func(): return _mix([
		_tone(987.8, 987.8, 0.35, TRI, 0.4, 4.5, 0.4),
		_tone(1975.5, 1975.5, 0.2, SINE, 0.15, 8.0)]))
	_queue("ding_blue", func(): return _tone(1318.5, 1318.5, 0.28, SINE, 0.45, 5.0, 0.3))
	_queue("chime", func(): return _notes([
		[1174.7, 0.0, 0.3], [1568.0, 0.07, 0.3], [1975.5, 0.14, 0.4]], TRI, 0.35, 5.0, 0.3))
	_queue("womp", func(): return _mix([
		_tone(200.0, 55.0, 0.4, SAW, 0.45, 3.0),
		_tone(90.0, 40.0, 0.4, SINE, 0.5, 3.0)]))

	# Ball and board
	_queue("drop", func(): return _mix([
		_tone(200.0, 70.0, 0.16, SINE, 0.7, 5.0),
		_noise(0.03, 0.25, 0.0)]))
	_queue("tick", func(): return _tone(1400.0, 1400.0, 0.02, SQUARE, 0.22, 1.0))
	_queue("pop", func(): return _tone(500.0, 1000.0, 0.06, SINE, 0.3, 6.0))
	_queue("tier", func(): return _mix([
		_tone(600.0, 1500.0, 0.18, TRI, 0.35, 3.0),
		_place(PackedFloat32Array(), _tone(1500.0, 1500.0, 0.2, SINE, 0.25, 6.0), 0.12)]))

	# Payouts
	_queue("coin", func(): return _notes([[988.0, 0.0, 0.06], [1319.0, 0.06, 0.34]], SQUARE, 0.2, 5.0))
	_queue("lose", func(): return _tone(330.0, 200.0, 0.22, SINE, 0.35, 5.0))
	_queue("win_small", func(): return _arp([523.25, 659.25, 783.99, 1046.5], 0.07, 0.25, TRI, 0.4, 3.0, 0.3))
	_queue("win_big", func(): return _win_big(false))
	_queue("mega", func(): return _win_big(true))
	_queue("goal", func(): return _arp([1046.5, 1318.5, 1568.0], 0.06, 0.4, TRI, 0.4, 3.5, 0.3))

	# Run flow
	_queue("ante", func(): return _notes([
		[392.0, 0.0, 0.12], [392.0, 0.14, 0.12], [392.0, 0.28, 0.12], [523.25, 0.42, 0.35],
		[659.25, 0.8, 0.15], [783.99, 0.95, 0.15], [1046.5, 1.1, 0.7]], TRI, 0.42, 2.5, 0.35))
	_queue("bust", func(): return _mix([
		_notes([[329.6, 0.0, 0.4], [261.6, 0.35, 0.4], [220.0, 0.7, 0.8]], SAW, 0.25, 2.5),
		_tone(110.0, 35.0, 1.4, SINE, 0.5, 2.0)]))
	_queue("whoosh", func(): return _noise(0.45, 0.3, 0.5))

func _queue(sound: String, job: Callable) -> void:
	pending.append([sound, job])

func _win_big(mega: bool) -> PackedFloat32Array:
	var out := _arp([523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0, 2093.0], 0.06, 0.3, TRI, 0.4, 3.0, 0.3)
	var chord := _mix([
		_tone(1046.5, 1046.5, 0.7, SINE, 0.3, 3.0),
		_tone(1318.5, 1318.5, 0.7, SINE, 0.3, 3.0),
		_tone(1568.0, 1568.0, 0.7, SINE, 0.3, 3.0)])
	out = _place(out, chord, 0.42)
	if mega:
		out = _place(out, _tone(110.0, 110.0, 0.6, SINE, 0.55, 2.0), 0.0)
		out = _place(out, _tone(300.0, 1800.0, 0.5, SAW, 0.12, 1.5), 0.0)
		out = _place(out, chord, 0.7)
	return out

# ---------- Synth building blocks ----------

func _osc(kind: int, ph: float) -> float:
	var p := ph - floorf(ph)
	if kind == SINE:
		return sin(TAU * p)
	if kind == SQUARE:
		return 1.0 if p < 0.5 else -1.0
	if kind == TRI:
		return 4.0 * absf(p - 0.5) - 1.0
	return 2.0 * p - 1.0

# One note: gliding from f0 to f1, exponential decay, optional octave harmonic.
func _tone(f0: float, f1: float, dur: float, kind: int, vol := 0.5, decay := 5.0, harm := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var attack := 0.004 * RATE
	for i in n:
		var t := float(i) / n
		phase += f0 * pow(f1 / f0, t) / RATE
		var env := exp(-decay * t) * minf(1.0, i / attack)
		var s := _osc(kind, phase)
		if harm > 0.0:
			s += harm * sin(TAU * phase * 2.0)
		out[i] = s * env * vol
	return out

# Lowpassed noise: `soft` 0 is harsh, toward 1 is a dull whoosh that swells then fades.
func _noise(dur: float, vol: float, soft: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var k := 1.0 - soft * 0.92
	for i in n:
		var t := float(i) / n
		lp += (randf_range(-1.0, 1.0) - lp) * k
		var env := sin(PI * t) if soft > 0.0 else exp(-8.0 * t)
		out[i] = lp * env * vol
	return out

# Sum several sounds starting together.
func _mix(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part in parts:
		out = _place(out, part, 0.0)
	return out

# Add `snd` into `out` starting `at` seconds in (grows `out` if needed).
func _place(out: PackedFloat32Array, snd: PackedFloat32Array, at: float) -> PackedFloat32Array:
	var start := int(at * RATE)
	if out.size() < start + snd.size():
		out.resize(start + snd.size())
	for i in snd.size():
		out[start + i] += snd[i]
	return out

# Notes as [freq, start_seconds, duration].
func _notes(list: Array, kind: int, vol: float, decay: float, harm := 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n in list:
		out = _place(out, _tone(n[0], n[0], n[2], kind, vol, decay, harm), n[1])
	return out

# Evenly spaced notes.
func _arp(freqs: Array, step: float, dur: float, kind: int, vol: float, decay: float, harm := 0.0) -> PackedFloat32Array:
	var list := []
	for i in freqs.size():
		list.append([freqs[i], i * step, dur])
	return _notes(list, kind, vol, decay, harm)

func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
