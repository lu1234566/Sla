extends Node
## Áudio: efeitos (gerados + Kenney CC0), trilhas por região com crossfade e
## camada de alerta do guardião (GDD 14: camadas mudam com maré/alerta).

const GEN := "res://assets/audio/sfx/"
const KEN := "res://assets/audio/kenney/"
const MUS := "res://assets/audio/music/"
const VOICE := "res://assets/audio/voice/"

const MAP := {
	"step": ["k:footstep_concrete_000", "k:footstep_concrete_001", "k:footstep_concrete_002", "k:footstep_concrete_003", "k:footstep_concrete_004"],
	"land": ["k:impactSoft_medium_000", "k:impactSoft_medium_001"],
	"crystal": ["k:impactGlass_light_000", "k:impactGlass_light_001", "k:impactGlass_light_002"],
	"ui": ["k:click_001"], "ui_select": ["k:select_001"], "ui_back": ["k:back_001"], "ui_open": ["k:maximize_001"],
	"journal": ["k:bookFlip1", "k:bookFlip2"], "book_open": ["k:bookOpen"], "lever": ["k:metalLatch", "g:lever_mix"],
	"door": ["g:door"], "door_tech": ["k:doorOpen_000"], "relay": ["g:relay"], "terminal": ["k:computerNoise_000"],
	"portal": ["g:portal"], "rotate": ["g:rotate"], "metal": ["k:impactMetal_light_000", "k:impactMetal_light_001"],
}

var _players: Array[AudioStreamPlayer] = []
var _cache = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _alert: AudioStreamPlayer
var _current_track = ""
var _alert_level = 0.0
var _voice: AudioStreamPlayer
var _duck = 0.0
var voices_played: Array = []  # chaves narradas nesta sessão (teste/diagnóstico)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	var verb = AudioEffectReverb.new()
	verb.room_size = 0.55
	verb.wet = 0.18
	verb.dry = 0.9
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SFX"), verb)
	for i in 14:
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	add_child(_voice)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_alert = _make_music_player()
	_alert.stream = _load_music("alert")
	_alert.volume_db = -60
	_alert.play()
	apply_volumes()
	Game.options_changed.connect(apply_volumes)

func _make_music_player() -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.bus = "Music"
	add_child(p)
	return p

func apply_volumes() -> void:
	var o: Dictionary = Game.options
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, o["master"])))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.0001, o["music"])))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(0.0001, o["sfx"])))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear_to_db(maxf(0.0001, o.get("voice", 1.0))))
	_apply_music_volume()

func _apply_music_volume() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.0001, Game.options["music"])) + _duck)

## Narração gravada (ElevenLabs) da fala `key` no idioma atual, se existir.
## Devolve a duração em segundos (0 = sem voz: fica só a legenda).
func voice(key: String) -> float:
	if Game.options.get("voice", 1.0) <= 0.0:
		return 0.0
	var path = VOICE + I18n.lang + "/" + key + ".ogg"
	if not ResourceLoader.exists(path):
		return 0.0
	var s = _load(path)
	if s == null:
		return 0.0
	_voice.stream = s
	_voice.play()
	voices_played.append(key)
	return s.get_length()

func stop_voice() -> void:
	_voice.stop()

func voice_playing() -> bool:
	return _voice.playing

func _process(dt: float) -> void:
	# a música abaixa enquanto alguém fala
	var target = -8.0 if _voice.playing else 0.0
	var nd = move_toward(_duck, target, dt * (30.0 if target < _duck else 6.0))
	if not is_equal_approx(nd, _duck):
		_duck = nd
		_apply_music_volume()

func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]

func _load_music(name: String) -> AudioStream:
	var s = _load(MUS + name + ".ogg") as AudioStreamOggVorbis
	if s:
		s.loop = true
	return s

func _stream_for(name: String) -> AudioStream:
	var choices: Array = MAP.get(name, ["g:" + name])
	var pick: String = choices[randi() % choices.size()]
	if pick.begins_with("k:"):
		return _load(KEN + pick.substr(2) + ".ogg")
	var g = pick.substr(2)
	if g == "lever_mix":
		g = "rotate"
	return _load(GEN + g + ".wav")

## Toca um efeito. vol: dB extra; pitch: variação.
func play(name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s = _stream_for(name)
	if s == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = s
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return
	_players[0].stream = s
	_players[0].play()

func music(track: String, fade: float = 2.0) -> void:
	if track == _current_track:
		return
	_current_track = track
	var incoming = _music_b if _music_a.playing else _music_a
	var outgoing = _music_a if incoming == _music_b else _music_b
	incoming.stream = _load_music(track)
	incoming.volume_db = -40
	incoming.play()
	var tw = create_tween().set_parallel(true)
	tw.tween_property(incoming, "volume_db", 0.0, fade)
	if outgoing.playing:
		tw.tween_property(outgoing, "volume_db", -60.0, fade)
		tw.chain().tween_callback(outgoing.stop)

## 0..1 — intensidade da camada de alerta.
func set_alert(level: float) -> void:
	_alert_level = lerpf(_alert_level, level, 0.1)
	_alert.volume_db = linear_to_db(maxf(0.0005, _alert_level * 0.8))
