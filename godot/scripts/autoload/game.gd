extends Node
## Estado global: opções, mapa de entradas, progresso da campanha, saves.

signal options_changed
signal progress_changed
signal travel_requested(region: String, spawn: String)

const REGIONS := ["farol", "jardim", "cidade", "coracao"]
const ECHO_TOTAL := 18
const UPGRADE_COST := {"lens": 3, "core": 7, "compass": 12}
const VISOR_COST := {"turquesa": 0, "cobre": 5, "sal": 10, "ceramica": 15}
const VISOR_COLOR := {"turquesa": Color("#7CF4DC"), "cobre": Color("#F3AB63"), "sal": Color("#D36C55"), "ceramica": Color("#E9D8AC")}

const DEFAULT_OPTIONS := {
	"language": "pt", "sensitivity": 1.0, "invert_y": false, "text_scale": 1.0, "hints": true,
	"assisted": false, "reduce_motion": false, "glow": true, "contrast": false, "subtitles": true,
	"master": 0.85, "music": 0.6, "sfx": 0.8, "voice": 1.0, "cam_follow": true, "quality": "high", "fullscreen": false, "keys": {},
}

## ação -> [teclas físicas padrão, botões do controle]
const BINDINGS := {
	"move_left": [[KEY_A, KEY_LEFT], []], "move_right": [[KEY_D, KEY_RIGHT], []],
	"move_forward": [[KEY_W, KEY_UP], []], "move_back": [[KEY_S, KEY_DOWN], []],
	"jump": [[KEY_SPACE], [JOY_BUTTON_A]], "interact": [[KEY_E], [JOY_BUTTON_X]],
	"tide": [[KEY_Q], [JOY_BUTTON_Y]], "scan": [[KEY_R], [JOY_BUTTON_RIGHT_SHOULDER]],
	"dodge": [[KEY_SHIFT], [JOY_BUTTON_B]], "pause": [[KEY_ESCAPE, KEY_P], [JOY_BUTTON_START]],
}
const REMAPPABLE := ["move_forward", "move_back", "move_left", "move_right", "jump", "interact", "tide", "scan", "dodge"]

var options = DEFAULT_OPTIONS.duplicate(true)
var saves = SaveManager.new()
var slot = 1
var state = {}
var playing = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_options()
	_setup_input()
	new_state()

# --- entradas -------------------------------------------------------------------

func _setup_input() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.25)
		var keys: Array = options["keys"].get(action, BINDINGS[action][0])
		for k in keys:
			var ev = InputEventKey.new()
			ev.physical_keycode = int(k)
			InputMap.action_add_event(action, ev)
		for b in BINDINGS[action][1]:
			var jb = InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
	var axes = {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0]}
	for action in axes:
		var jm = InputEventJoypadMotion.new()
		jm.axis = axes[action][0]
		jm.axis_value = axes[action][1]
		InputMap.action_add_event(action, jm)
	for pair in [["cam_left", JOY_AXIS_RIGHT_X, -1.0], ["cam_right", JOY_AXIS_RIGHT_X, 1.0], ["cam_up", JOY_AXIS_RIGHT_Y, -1.0], ["cam_down", JOY_AXIS_RIGHT_Y, 1.0]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0], 0.15)
			var m = InputEventJoypadMotion.new()
			m.axis = pair[1]
			m.axis_value = pair[2]
			InputMap.action_add_event(pair[0], m)

## Remapeia a tecla principal de uma ação (acessibilidade, GDD 14).
func remap(action: String, keycode: int) -> void:
	var keys: Array = options["keys"].get(action, BINDINGS[action][0]).duplicate()
	keys[0] = keycode
	options["keys"][action] = keys
	save_options()
	_setup_input()

func reset_keys() -> void:
	options["keys"] = {}
	save_options()
	_setup_input()

# --- opções -----------------------------------------------------------------------

func _load_options() -> void:
	var cf = ConfigFile.new()
	if cf.load("user://options.cfg") == OK:
		for k in DEFAULT_OPTIONS:
			options[k] = cf.get_value("options", k, DEFAULT_OPTIONS[k])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			options["quality"] = a.split("=")[1]
		if a.begins_with("--lang="):
			options["language"] = a.split("=")[1]
	I18n.set_language(options["language"])

func save_options() -> void:
	var cf = ConfigFile.new()
	for k in options:
		cf.set_value("options", k, options[k])
	cf.save("user://options.cfg")

func set_option(key: String, value: Variant) -> void:
	options[key] = value
	if key == "language":
		I18n.set_language(value)
	save_options()
	options_changed.emit()

# --- progresso --------------------------------------------------------------------

func new_state() -> void:
	state = {
		"region": "farol", "spawn": "start",
		"abilities": {"glide": false, "relay": false, "dual": false},
		"echoes": [], "memories": [], "flags": {}, "sectors": {},
		"portals": {"jardim": false, "cidade": false, "coracao": false},
		"upgrades": {"lens": false, "core": false, "compass": false},
		"visor": "turquesa", "ending": "", "completed": false, "integrity": 3,
		"stats": {"time": 0.0, "falls": 0, "hits": 0, "hints": 0, "tides": 0},
	}

func flag(key: String, default: Variant = false) -> Variant:
	return state["flags"].get(key, default)

func set_flag(key: String, value: Variant = true) -> void:
	state["flags"][key] = value
	progress_changed.emit()

func has_ability(a: String) -> bool:
	return state["abilities"].get(a, false)

func grant_ability(a: String) -> void:
	state["abilities"][a] = true
	progress_changed.emit()

func has_echo(id: String) -> bool:
	return id in state["echoes"]

func add_echo(id: String) -> void:
	if not has_echo(id):
		state["echoes"].append(id)
		progress_changed.emit()

func echo_count() -> int:
	return state["echoes"].size()

func max_integrity() -> int:
	return 4 if state["upgrades"].get("core", false) else 3

func upgrade_available(u: String) -> bool:
	return not state["upgrades"].get(u, false) and echo_count() >= UPGRADE_COST[u]

func any_upgrade_ready() -> bool:
	for u in UPGRADE_COST:
		if upgrade_available(u):
			return true
	return false

func install_upgrade(u: String) -> bool:
	if not upgrade_available(u):
		return false
	state["upgrades"][u] = true
	progress_changed.emit()
	return true

func stat(key: String, add: float = 1.0) -> void:
	state["stats"][key] = state["stats"].get(key, 0) + add

func sector_high(region: String, sector: String, default: bool) -> bool:
	return state["sectors"].get(region + "." + sector, default)

func set_sector(region: String, sector: String, high: bool) -> void:
	state["sectors"][region + "." + sector] = high

# --- saves -------------------------------------------------------------------------

func save_game() -> bool:
	return saves.save(slot, state)

func load_game(s: int) -> bool:
	var r = saves.load_slot(s)
	if r.is_empty():
		return false
	slot = s
	new_state()
	for k in r["data"]:
		state[k] = r["data"][k]
	# JSON devolve números como float
	state["integrity"] = int(state.get("integrity", 3))
	state.erase("version")
	return true

func slot_summary(s: int) -> String:
	var r = saves.load_slot(s)
	if r.is_empty():
		return I18n.t("menu.slot_empty")
	var d: Dictionary = r["data"]
	var secs = int(d.get("stats", {}).get("time", 0))
	var txt = I18n.t("menu.slot_info", {"region": I18n.t("region." + str(d.get("region", "farol"))), "echoes": d.get("echoes", []).size(), "time": "%d:%02d" % [secs / 3600, (secs / 60) % 60] if secs >= 3600 else "%d:%02d" % [secs / 60, secs % 60]})
	if r["source"] == "backup":
		txt += " " + I18n.t("menu.backup")
	return txt

func latest_slot() -> int:
	var best = 0
	var best_t = -1.0
	for s in range(1, SaveManager.SLOTS + 1):
		var r = saves.load_slot(s)
		if not r.is_empty() and float(r["data"].get("saved_at", 0)) > best_t:
			best_t = float(r["data"].get("saved_at", 0))
			best = s
	return best

func travel(region: String, spawn: String = "portal") -> void:
	travel_requested.emit(region, spawn)

func fmt_time(seconds: float) -> String:
	var s = int(seconds)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]
