extends AIGrenadeProjectile

# ─────────────────────────────────────────────
# MORTAR ROUND — the launcher's grenade as a finned bomb. It flies nose first
# down its own flight path instead of tumbling like a thrown frag, and it
# whistles on the way down, so whoever is under it hears it coming.
#
# Everything else — the impact fuse, the blast, who it is credited to — is the
# grenade's, set by the launcher that fires it. So is continuous collision,
# which a round this fast cannot land without (AIGrenadeProjectile._ready).
# ─────────────────────────────────────────────

## Seconds of whistle before it lands; the sound is made to this length.
const WHISTLE := 1.3
const _RATE := 22050

## Plays the whistle. Its stream is made in code (_whistle_sound), not a file.
@export var whistle: AudioStreamPlayer3D

## How long this round will be in the air, from the launcher as it fires. Zero
## — fired by something that does not say — and it comes down in silence.
var flight_time: float = 0.0

static var _whistle_stream: AudioStreamWAV

var _t := 0.0
var _whistled := false


func _ready() -> void:
	super()
	# Pointed by hand every tick instead (_physics_process). The launcher gives
	# each round a random spin, which is right for a grenade and wrong here.
	lock_rotation = true
	if whistle != null:
		whistle.stream = _whistle_sound()


func _physics_process(delta: float) -> void:
	super(delta)
	if _exploded:
		return   # gone off: nothing left to point or to hear
	_t += delta
	var v := linear_velocity
	if mesh != null and v.length_squared() > 0.01:
		var up := Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.FORWARD
		mesh.global_basis = Basis.looking_at(v.normalized(), up)
	if not _whistled and whistle != null and flight_time > WHISTLE and _t >= flight_time - WHISTLE:
		_whistled = true
		whistle.play()


func _explode() -> void:
	super()
	if whistle != null:
		whistle.stop()


# A falling shell, made rather than recorded: a tone sliding down across the
# whistle and swelling as it comes, with a slow wobble so it is not a test
# tone. Built once and shared by every round.
static func _whistle_sound() -> AudioStreamWAV:
	if _whistle_stream != null:
		return _whistle_stream
	var n := int(WHISTLE * _RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var hz := lerpf(1650.0, 820.0, t * t) + sin(t * 70.0) * 18.0
		phase += TAU * hz / _RATE
		var swell := 0.15 + 0.85 * smoothstep(0.0, 0.85, t)
		var s := (sin(phase) * 0.8 + sin(phase * 2.0) * 0.12) * swell * 0.6
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _RATE
	wav.stereo = false
	wav.data = data
	_whistle_stream = wav
	return wav
