extends Node3D
## Orquestra a campanha: regiões, Íris, Lume, câmera, interação, perigos,
## guardiões, checkpoints, dicas, menus, travessias e finais.

const REGION_SCRIPTS := {
	"farol": preload("res://scripts/world/regions/farol.gd"),
	"jardim": preload("res://scripts/world/regions/jardim.gd"),
	"cidade": preload("res://scripts/world/regions/cidade.gd"),
	"coracao": preload("res://scripts/world/regions/coracao.gd"),
}
const IXS := preload("res://scripts/world/ix.gd")
const HINT_DELAY := 30.0
const HINT_STEP := 20.0

var ui: UI
var player: Player
var lume: Lume
var cam: CameraRig
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var region: Region
var decor: Node3D
var creatures: Array = []
var cloud_list: Array = []
var beam: MeshInstance3D
var beam_t = 0.0
var mode = "boot"
var respawning = false
var scan_cd = 0.0
var label_t = 0.0
var scan_radius = 18.0
var obj_id = ""
var obj_t = 0.0
var hint_level = 0
var said = {}
var mouse_delta = Vector2.ZERO
var wheel = 0.0
var touching = {}
var busy = 0.0
var time = 0.0
var menu_angle = 0.0
var autopilot_keys = {}  # testes: {"tide": true, "interact_pressed": true, ...}
var test_mode = false
var _remap_action = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world_env = WorldEnvironment.new()
	world_env.environment = Environment.new()
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	decor = Node3D.new()
	add_child(decor)
	cam = CameraRig.new()
	add_child(cam)
	player = Player.new()
	add_child(player)
	player.event.connect(_on_player_event)
	cam.exclude = [player.get_rid()]
	lume = Lume.new()
	add_child(lume)
	beam = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.45
	cyl.height = 14.0
	beam.mesh = cyl
	var bm = StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(Palette.RESSONANCIA, 0.3)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.visible = false
	add_child(beam)
	ui = UI.new()
	add_child(ui)
	Game.options_changed.connect(_apply_options)
	I18n.language_changed.connect(_on_language)
	_apply_options()
	test_mode = "--smoke" in OS.get_cmdline_user_args()
	var dbg = _debug_args()
	var playtest: Playtest = null
	if dbg.has("playtest") or "--playtest" in OS.get_cmdline_user_args():
		test_mode = true
		Game.slot = 3
		Game.new_state()
		playtest = Playtest.new(self, float(dbg.get("playtest", "3")))
		add_child(playtest)
	if dbg.has("region"):
		test_mode = true
		for k in dbg.get("flags", "").split(",", false):
			Game.set_flag(k)
		for a in dbg.get("abilities", "").split(",", false):
			Game.grant_ability(a)
		await load_region(dbg["region"], dbg.get("spawn", "portal"), false)
		mode = "play"
		ui.show_hud(true)
	else:
		load_region("farol", "start", false)
		if test_mode:
			mode = "play"
		else:
			show_main_menu()
	if dbg.has("intro"):
		_intro()
	if dbg.has("shot"):
		_debug_shot(dbg)
	if playtest:
		playtest.run()

## --region=jardim --spawn=portal --cam=x,y,z,lx,ly,lz --shot=caminho.png --frames=60 --flags=a,b --abilities=glide
func _debug_args() -> Dictionary:
	var out = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.find("=") > 0:
			var kv = a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out

func _debug_shot(dbg: Dictionary) -> void:
	var frames = int(dbg.get("frames", "45"))
	for i in frames:
		if dbg.has("cam"):
			var c = dbg["cam"].split(",")
			mode = "debugcam"
			cam.camera.global_position = Vector3(float(c[0]), float(c[1]), float(c[2]))
			cam.camera.look_at(Vector3(float(c[3]), float(c[4]), float(c[5])), Vector3.UP)
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dbg["shot"])
	print("captura: ", dbg["shot"])
	get_tree().quit()

func _on_language() -> void:
	if mode == "menu":
		show_main_menu()

func _apply_options() -> void:
	var o = Game.options
	ui.apply_options(o)
	cam.reduce_motion = o["reduce_motion"]
	player.set_assisted(o["assisted"])
	if not test_mode and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if o["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED)
	if region:
		Decor.apply_environment(world_env, sun, _env_preset(), o["glow"], o["quality"])
	get_viewport().msaa_3d = Viewport.MSAA_2X if o["quality"] == "high" else Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_scale = 1.0 if o["quality"] == "high" else 0.75

func _env_preset() -> String:
	if region and region.id == "farol" and Game.state.get("ending", "") != "":
		return "final_" + Game.state["ending"]
	return region.env.get("preset", region.id) if region else "farol"

# --- regiões -------------------------------------------------------------------------

func load_region(rid: String, spawn: String, with_fade: bool = true) -> void:
	if with_fade:
		await ui.fade_to(1.0, 0.45)
	if region:
		region.queue_free()
		await get_tree().process_frame
	for c in decor.get_children():
		c.queue_free()
	region = REGION_SCRIPTS[rid].new(rid)
	region.main = self
	add_child(region)
	region.build()
	region.settle()
	for g in region.guardians:
		var gd: Guardian = g["guard"]
		gd.guard_event.connect(func(type): _on_guard_event(type, g))
		gd.set_assisted(Game.options["assisted"])
		gd.reset(g["active"].call())
	var preset = _env_preset()
	Decor.apply_environment(world_env, sun, preset, Game.options["glow"], Game.options["quality"])
	Decor.ocean(decor, -34.0, preset)
	Decor.distant_islands(decor, hash(rid), 9, Color(region.env.get("distant", "#3B6B72")))
	cloud_list = Decor.clouds(decor, hash(rid) + 7, 10)
	creatures = Decor.sky_creatures(decor, region.env.get("creatures", [["manta", 3.0, 60, 90, -12, 8], ["whale", 9.0, 120, 160, -8, 20]]), hash(rid) + 3)
	Game.state["region"] = rid
	var sp: Dictionary = region.spawns.get(spawn, region.spawns.values()[0])
	Game.state["spawn"] = spawn if region.spawns.has(spawn) else region.spawns.keys()[0]
	place_player(sp["pos"], sp["yaw"])
	Sfx.music(region.music)
	obj_id = ""
	obj_t = 0.0
	if with_fade:
		await ui.fade_to(0.0, 0.6)

func place_player(pos: Vector3, yaw: float) -> void:
	player.teleport(pos + Vector3(0, 0.1, 0), yaw)
	player.safe_points = [{"pos": pos, "body": null}]
	cam.snap_behind(yaw, pos)
	lume.place(pos + Vector3(0.8, 1.9, 0.4))
	lume.follow()

func request_travel(dest: String, spawn: String) -> void:
	if respawning:
		return
	respawning = true
	Game.save_game()
	await load_region(dest, spawn)
	respawning = false
	ui.show_title(I18n.t("region." + dest), I18n.t("tagline") if dest == "farol" else "", 4.0)
	Game.save_game()

# --- menus ------------------------------------------------------------------------

func show_main_menu() -> void:
	mode = "menu"
	ui.show_hud(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.music("menu")
	var latest = Game.latest_slot()
	var items = []
	if latest > 0:
		items.append([I18n.t("menu.continue") + "  ·  " + Game.slot_summary(latest), func(): _continue(latest)])
	items.append([I18n.t("menu.new"), func(): show_slots()])
	if _any_completed():
		items.append([I18n.t("menu.chapters"), func(): show_chapters()])
	items.append([I18n.t("menu.options"), func(): show_options(show_main_menu)])
	items.append([I18n.t("menu.controls"), func(): show_controls(show_main_menu)])
	items.append([I18n.t("menu.credits"), func(): show_credits(show_main_menu)])
	items.append([I18n.t("menu.quit"), func(): get_tree().quit()])
	ui.open_menu(I18n.t("title"), items, {"eyebrow": I18n.t("region.farol").to_upper(), "subtitle": I18n.t("tagline"), "title_size": 56, "bg_alpha": 0.12, "width": 520, "left": true, "margin": 90})

func _any_completed() -> bool:
	for s in range(1, SaveManager.SLOTS + 1):
		var r = Game.saves.load_slot(s)
		if not r.is_empty() and r["data"].get("completed", false):
			return true
	return false

func show_slots() -> void:
	var items = []
	for s in range(1, SaveManager.SLOTS + 1):
		var slot = s
		items.append(["%s — %s" % [I18n.t("menu.slot", {"n": s}), Game.slot_summary(s)], func(): _new_game(slot)])
	items.append([I18n.t("menu.back"), show_main_menu])
	ui.open_menu(I18n.t("menu.slots"), items, {"width": 640})

func show_chapters() -> void:
	var items = []
	for rid in ["farol", "jardim", "cidade", "coracao"]:
		var r: String = rid
		items.append([I18n.t("region." + rid), func(): _chapter(r)])
	items.append([I18n.t("menu.back"), show_main_menu])
	ui.open_menu(I18n.t("chapter.pick"), items)

func _chapter(rid: String) -> void:
	var s = Game.latest_slot()
	Game.load_game(s)
	ui.close_menu()
	await load_region(rid, "portal" if rid != "farol" else "hub")
	_start_play()

func _continue(s: int) -> void:
	if not Game.load_game(s):
		return
	ui.close_menu()
	_apply_options()
	await load_region(Game.state["region"], Game.state["spawn"])
	_start_play()
	ui.show_title(I18n.t("region." + Game.state["region"]), "", 3.0)

func _new_game(s: int) -> void:
	Game.saves.clear(s)
	Game.slot = s
	Game.new_state()
	ui.close_menu()
	await load_region("farol", "start")
	Game.save_game()
	_intro()

func _intro() -> void:
	mode = "cutscene"
	ui.show_hud(false)
	var p = player.global_position
	ui.show_title(I18n.t("title"), I18n.t("tagline"), 6.0)
	if Game.options["reduce_motion"] or (test_mode and not _debug_args().has("intro")):
		_start_play()
		_lume_say("lume.wake", 6.0)
		return
	# a narradora conta o prólogo durante o voo de câmera (que dura o mesmo)
	var nar = narrate("intro.narration")
	cam.play([
		{"pos": Vector3(24, 22, -40), "look": Vector3(0, 6, -20)},
		{"pos": Vector3(18, 12, -6), "look": Vector3(0, 2, -8)},
		{"pos": Vector3(6, 6, p.z + 10), "look": p + Vector3(0, 1, 0)},
		{"pos": p + Vector3(0, 3.2, 5.8), "look": p + Vector3(0, 1.25, 0)},
	], maxf(9.0, nar + 0.8), _intro_done)

func _intro_done() -> void:
	stop_narration()
	_start_play()
	_lume_say("lume.wake", 6.0)

# --- narração ------------------------------------------------------------------------

var _caption_token = 0

## Voz da narradora + legenda em trechos proporcionais à duração da fala.
## Devolve a duração (estimada pelo texto quando não há gravação).
func narrate(key: String) -> float:
	var text = I18n.t(key)
	var vl = Sfx.voice(key)
	var total = vl if vl > 0.0 else text.length() / 14.0
	_caption_token += 1
	_caption_run(_chunks(text, 118), total, _caption_token)
	return total

func stop_narration() -> void:
	_caption_token += 1
	Sfx.stop_voice()

func _caption_run(chunks: Array, total: float, token: int) -> void:
	var n = 0
	for c in chunks:
		n += c.length()
	for c in chunks:
		if token != _caption_token:
			return
		var d = total * float(c.length()) / maxf(1.0, n)
		ui.say(c, d + 0.25, false, I18n.t("speaker.narrator"))
		await get_tree().create_timer(d).timeout

## Divide em frases (". ! ?" — reticências não encerram frase) e agrupa até
## `max_len` caracteres.
func _chunks(text: String, max_len: int) -> Array:
	var sentences = []
	var cur = ""
	for w in text.split(" ", false):
		cur = w if cur == "" else cur + " " + w
		var t = w.rstrip("”\"»)")
		if t.ends_with(".") or t.ends_with("!") or t.ends_with("?"):
			if not t.ends_with("…") and not t.ends_with("..."):
				sentences.append(cur)
				cur = ""
	if cur != "":
		sentences.append(cur)
	var out = []
	var acc = ""
	for snt in sentences:
		if acc != "" and acc.length() + snt.length() + 1 > max_len:
			out.append(acc)
			acc = snt
		else:
			acc = snt if acc == "" else acc + " " + snt
	if acc != "":
		out.append(acc)
	return out if not out.is_empty() else [text]

func _start_play() -> void:
	mode = "play"
	ui.close_menu()
	ui.show_hud(true)
	if not test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func pause() -> void:
	if mode != "play":
		return
	mode = "paused"
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_pause()

func show_pause() -> void:
	var items = [
		[I18n.t("menu.resume"), resume],
		[I18n.t("menu.journal"), show_journal],
		[I18n.t("menu.map"), show_map],
		[I18n.t("menu.options"), func(): show_options(show_pause)],
		[I18n.t("menu.controls"), func(): show_controls(show_pause)],
		[I18n.t("menu.checkpoint"), func(): resume(); reboot(false)],
	]
	if region.id != "farol":
		items.append([I18n.t("menu.to_hub"), func(): resume(); request_travel("farol", "portal_" + region.id)])
	items.append([I18n.t("menu.main"), func(): Game.save_game(); show_main_menu()])
	ui.open_menu(I18n.t("menu.paused"), items)

func resume() -> void:
	ui.close_menu()
	_start_play()

func show_options(back: Callable) -> void:
	var o = Game.options
	var controls = []
	var lang = OptionButton.new()
	for i in I18n.LANGS.size():
		lang.add_item(I18n.LANGS[i][1], i)
		if I18n.LANGS[i][0] == o["language"]:
			lang.select(i)
	lang.item_selected.connect(func(i): Game.set_option("language", I18n.LANGS[i][0]); show_options(back))
	controls.append(ui.row(I18n.t("opt.language"), lang))
	for pair in [["assisted", "opt.assisted", "opt.assisted_help"], ["cam_follow", "opt.cam_follow", "opt.cam_follow_help"], ["hints", "opt.hints", ""], ["subtitles", "opt.subtitles", ""], ["contrast", "opt.contrast", ""], ["reduce_motion", "opt.motion", ""], ["glow", "opt.glow", ""], ["invert_y", "opt.invert", ""], ["fullscreen", "opt.fullscreen", ""]]:
		var key: String = pair[0]
		var cb = CheckButton.new()
		cb.button_pressed = o.get(key, Game.DEFAULT_OPTIONS.get(key, false))
		cb.toggled.connect(func(v): Game.set_option(key, v))
		controls.append(ui.row(I18n.t(pair[1]), cb, I18n.t(pair[2]) if pair[2] != "" else ""))
	var ts = OptionButton.new()
	for i in 3:
		ts.add_item(["100%", "120%", "140%"][i], i)
	ts.select([1.0, 1.2, 1.4].find(o["text_scale"]) if [1.0, 1.2, 1.4].has(o["text_scale"]) else 0)
	ts.item_selected.connect(func(i): Game.set_option("text_scale", [1.0, 1.2, 1.4][i]); show_options(back))
	controls.append(ui.row(I18n.t("opt.text"), ts))
	var q = OptionButton.new()
	q.add_item(I18n.t("opt.q_high"), 0)
	q.add_item(I18n.t("opt.q_low"), 1)
	q.select(0 if o["quality"] == "high" else 1)
	q.item_selected.connect(func(i): Game.set_option("quality", "high" if i == 0 else "low"))
	controls.append(ui.row(I18n.t("opt.quality"), q))
	for pair in [["sensitivity", "opt.sens", 0.3, 2.5], ["master", "opt.master", 0.0, 1.0], ["music", "opt.music", 0.0, 1.0], ["sfx", "opt.sfx", 0.0, 1.0], ["voice", "opt.voice", 0.0, 1.0]]:
		var key: String = pair[0]
		var sl = HSlider.new()
		sl.min_value = pair[2]
		sl.max_value = pair[3]
		sl.step = 0.05
		sl.value = o.get(key, Game.DEFAULT_OPTIONS.get(key, 1.0))
		sl.custom_minimum_size.x = 200
		sl.value_changed.connect(func(v): Game.set_option(key, v))
		controls.append(ui.row(I18n.t(pair[1]), sl))
	controls.append([I18n.t("opt.remap"), func(): show_remap(back)])
	controls.append([I18n.t("menu.back"), back])
	ui.open_menu(I18n.t("menu.options"), controls, {"width": 640, "height": 620})

func show_remap(back: Callable) -> void:
	var items = []
	for a in Game.REMAPPABLE:
		var action: String = a
		var label = "%s — %s" % [I18n.t("ctl." + {"move_forward": "move", "move_back": "move", "move_left": "move", "move_right": "move"}.get(action, action)) + ({"move_forward": " ↑", "move_back": " ↓", "move_left": " ←", "move_right": " →"}.get(action, "")), I18n.key_name(action)]
		items.append([label, func(): _await_key(action, back)])
	items.append([I18n.t("opt.reset_keys"), func(): Game.reset_keys(); show_remap(back)])
	items.append([I18n.t("menu.back"), func(): show_options(back)])
	ui.open_menu(I18n.t("opt.remap"), items, {"width": 560})

func _await_key(action: String, back: Callable) -> void:
	_remap_action = action
	ui.open_menu(I18n.t("opt.press_key"), [], {"width": 420})
	set_meta("remap_back", back)

func show_controls(back: Callable) -> void:
	var rows = []
	for pair in [["ctl.move", "WASD"], ["ctl.camera", "Mouse / R-stick"], ["ctl.jump", I18n.key_name("jump") + " / A"], ["ctl.interact", I18n.key_name("interact") + " / X"], ["ctl.tide", I18n.key_name("tide") + " / Y"], ["ctl.scan", I18n.key_name("scan") + " / RB"], ["ctl.dodge", I18n.key_name("dodge") + " / B"], ["ctl.pause", "Esc / Start"]]:
		rows.append(ui.row(I18n.t(pair[0]), ui._label(pair[1], 18, UI.FONT_K, Palette.RESSONANCIA)))
	rows.append([I18n.t("menu.back"), back])
	ui.open_menu(I18n.t("menu.controls"), rows, {"width": 620})

func show_credits(back: Callable) -> void:
	ui.open_menu(I18n.t("menu.credits"), [[I18n.t("menu.back"), back]], {"body": I18n.t("credits.body"), "width": 640})

func show_journal() -> void:
	var items = []
	if Game.state["memories"].size() > 0:
		items.append(ui._label(I18n.t("journal.memories"), 16, UI.FONT_K, Palette.RESSONANCIA))
		for m in Game.state["memories"]:
			items.append(_journal_entry(I18n.t("mem.%s.title" % m), I18n.t("mem.%s.text" % m)))
	if Game.echo_count() > 0:
		items.append(ui._label(I18n.t("journal.echoes") + "  %d/%d" % [Game.echo_count(), Game.ECHO_TOTAL], 16, UI.FONT_K, Palette.RESSONANCIA))
		for e in Game.state["echoes"]:
			items.append(_journal_entry(I18n.t("region." + str(e).split("_")[0]), I18n.t("echo." + e)))
	if items.is_empty():
		items.append(ui._label(I18n.t("journal.empty"), 18))
	items.append([I18n.t("menu.back"), show_pause])
	Sfx.play("book_open")
	ui.open_menu(I18n.t("menu.journal"), items, {"width": 680, "height": 600})

func _journal_entry(title: String, text: String) -> Control:
	var v = VBoxContainer.new()
	v.add_child(ui._label(title, 15, UI.FONT_K, Palette.COBRE))
	var l = ui._label(text, 17, UI.FONT_I)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 600
	v.add_child(l)
	return v

func show_map() -> void:
	var mv = MapView.new()
	mv.custom_minimum_size = Vector2(600, 380)
	ui.open_menu(I18n.t("map.title"), [mv, [I18n.t("menu.back"), show_pause]], {"width": 660})

func open_workshop() -> void:
	mode = "paused"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var items = []
	items.append(ui._label(I18n.t("upg.abilities"), 16, UI.FONT_K, Palette.RESSONANCIA))
	for a in ["glide", "relay", "dual"]:
		items.append(ui.row(I18n.t("ability." + a), ui._label("✔" if Game.has_ability(a) else "—", 18, UI.FONT_K, Palette.RESSONANCIA if Game.has_ability(a) else Color(1, 1, 1, 0.4))))
	items.append(ui._label(I18n.t("hud.echoes", {"n": Game.echo_count(), "total": Game.ECHO_TOTAL}), 16, UI.FONT_K, Palette.COBRE))
	for u in ["lens", "core", "compass"]:
		var up: String = u
		var have: bool = Game.state["upgrades"].get(u, false)
		var label = "%s — %s" % [I18n.t("upg." + u), I18n.t("upg.on") if have else (I18n.t("upg.install") if Game.upgrade_available(u) else I18n.t("upg.need", {"n": Game.UPGRADE_COST[u]}))]
		items.append([label, func(): _install(up), {"disabled": have or not Game.upgrade_available(u)}])
		items.append(ui._label("   " + I18n.t("upg." + u + "_help"), 14, UI.FONT_R, Color(1, 1, 1, 0.6)))
	items.append(ui._label(I18n.t("upg.visor"), 16, UI.FONT_K, Palette.RESSONANCIA))
	for v in Game.VISOR_COST:
		var vv: String = v
		var ok = Game.echo_count() >= Game.VISOR_COST[v]
		items.append([("● " if Game.state["visor"] == v else "○ ") + I18n.t("visor." + v) + ("" if ok else "  (" + I18n.t("upg.need", {"n": Game.VISOR_COST[v]}) + ")"), func(): _set_visor(vv), {"disabled": not ok}])
	items.append([I18n.t("menu.back"), resume])
	Sfx.play("ui_open")
	ui.open_menu(I18n.t("upg.title"), items, {"width": 620, "height": 620})

func _install(u: String) -> void:
	if Game.install_upgrade(u):
		Sfx.play("unlock")
		Game.state["integrity"] = Game.max_integrity()
		Game.save_game()
	open_workshop()

func _set_visor(v: String) -> void:
	Game.state["visor"] = v
	player.rig.set_visor(Game.VISOR_COLOR[v])
	Game.save_game()
	open_workshop()

# --- entrada -------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _remap_action != "" and event is InputEventKey and event.pressed:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code != KEY_ESCAPE:
			Game.remap(_remap_action, code)
		_remap_action = ""
		get_viewport().set_input_as_handled()
		show_remap(get_meta("remap_back"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += event.relative
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel -= 1.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel += 1.0
		elif mode == "play" and not test_mode:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if mode == "cutscene" and (event is InputEventKey or event is InputEventJoypadButton) and event.pressed:
		cam.skip()
	if event.is_action_pressed("pause"):
		if mode == "play":
			pause()
		elif mode == "paused" and _remap_action == "":
			resume()

func _pressed(action: String) -> bool:
	if autopilot_keys.has(action + "_pressed"):
		var v: bool = autopilot_keys[action + "_pressed"]
		autopilot_keys.erase(action + "_pressed")
		return v
	return Input.is_action_just_pressed(action)

func _held(action: String) -> bool:
	return autopilot_keys.get(action, false) or Input.is_action_pressed(action)

# --- laço ------------------------------------------------------------------------------

func _process(dt: float) -> void:
	# simulação do mundo (marés, plataformas, portões) com o tempo real do quadro
	# (até 0,1 s): fica em sincronia com a física mesmo com FPS baixo
	if region and mode != "paused":
		region.tick(minf(dt, 0.1))
	dt = minf(dt, 0.05)
	time += dt
	I18n.pad_prompts = Input.get_connected_joypads().size() > 0 and Input.get_joy_axis(0, JOY_AXIS_LEFT_X) != 0.0
	ui.update_ui(dt)
	if region:
		Decor.animate_creatures(creatures, time)
		for c in cloud_list:
			c.position.x += c.get_meta("speed") * dt
			if c.position.x > 140:
				c.position.x = -140
	match mode:
		"menu":
			menu_angle += dt * 0.05
			# órbita lenta; a ilha fica à direita do painel do menu
			var center: Vector3 = region.env.get("center", Vector3.ZERO)
			var cpos = center + Vector3(sin(menu_angle) * 40, 15, cos(menu_angle) * 40)
			var right = (center - cpos).normalized().cross(Vector3.UP).normalized()
			cam.camera.global_position = cpos
			cam.camera.look_at(center + Vector3(0, -1, 0) - right * 13.0, Vector3.UP)
			player.active = false
			lume.update_lume(dt, player.global_position, player.facing, cam.camera.global_position)
			_update_guardians(dt, false)
		"cutscene":
			cam.update_camera(dt, Vector2.ZERO, 0.0, player.global_position, player.facing)
			lume.update_lume(dt, player.global_position, player.facing, cam.camera.global_position)
		"play":
			player.active = true
			_play(dt)
		"paused":
			player.active = false
	mouse_delta = Vector2.ZERO
	wheel = 0.0

func _play(dt: float) -> void:
	Game.stat("time", dt)
	scan_cd = maxf(0.0, scan_cd - dt)
	busy = maxf(0.0, busy - dt)
	var sens: float = Game.options["sensitivity"]
	var look = mouse_delta * 0.0022 * sens
	look.x += Input.get_axis("cam_left", "cam_right") * 2.6 * dt * sens
	look.y += Input.get_axis("cam_up", "cam_down") * 1.8 * dt * sens
	if Game.options["invert_y"]:
		look.y = -look.y
	if not autopilot_keys.has("cam_yaw"):
		var follow = player.speed_h if Game.options.get("cam_follow", true) else 0.0
		cam.update_camera(dt, look, wheel, player.global_position, player.facing, follow)
	else:
		cam.yaw = autopilot_keys["cam_yaw"]
		cam.update_camera(dt, Vector2.ZERO, 0.0, player.global_position, player.facing)
	player.cam_yaw = cam.yaw
	lume.update_lume(dt, player.global_position, player.facing, cam.camera.global_position)
	var p = player.global_position
	# perigos
	if not respawning:
		if p.y < region.kill_y:
			respawn("fall")
		elif p.y < region.water_level_at(p) - 0.55:
			respawn("drown")
	_update_guardians(dt, true)
	_interactions(dt)
	# checkpoints
	for c in region.checkpoints:
		if p.distance_to(c["pos"]) < c["radius"] and Game.state["spawn"] != c["id"]:
			Game.state["spawn"] = c["id"]
			Game.save_game()
			_lume_say("lume.checkpoint", 2.5)
	_objectives(dt)
	# HUD
	ui.set_integrity(Game.state["integrity"], Game.max_integrity())
	var secs = []
	for sid in region.sectors:
		var s: TideSector = region.sectors[sid]
		secs.append({"name": sid, "high": s.high, "moving": s.transitioning, "progress": s.progress, "cooldown": s.cooldown / TideSector.COOLDOWN})
	ui.set_tides(secs)
	ui.set_echoes(Game.echo_count(), Game.ECHO_TOTAL)
	_labels(dt)
	_effects(dt)
	var alert = 0.0
	for g in region.guardians:
		alert = maxf(alert, g["guard"].alert_level)
	Sfx.set_alert(alert)

func _update_guardians(dt: float, playing: bool) -> void:
	var p = player.global_position
	for g in region.guardians:
		var in_zone: bool = playing and Builder.inside(g["zone"], Vector2(p.x, p.z)) and p.y < g["zone_top"]
		g["guard"].update_guard(dt, {"active": g["active"].call(), "player_pos": p, "in_zone": in_zone, "dodging": player.dodging})

func _ctx() -> Dictionary:
	return {"main": self, "player": player, "player_pos": player.global_position, "region": region}

func _interactions(dt: float) -> void:
	var ctx = _ctx()
	var p = player.global_position
	var best: Interactable = null
	var best_prompt = {}
	var best_d = INF
	var now_touch = {}
	for ix in region.interactables:
		ix.tick(dt, ctx)
		if not ix.in_range(p):
			continue
		if ix.action == "touch":
			now_touch[ix] = true
			if not touching.has(ix):
				ix.activate(ctx)
			continue
		var pr: Dictionary = ix.prompt(ctx)
		if pr.is_empty():
			continue
		var d = Vector2(p.x - ix.global_position.x, p.z - ix.global_position.z).length()
		if ix.action == "relay":
			if not _line_of_sight(ix):
				continue
			d += 100.0
		if d < best_d:
			best_d = d
			best = ix
			best_prompt = pr
	touching = now_touch
	for ix in region.interactables:
		if ix.action == "tide" and ix != best:
			ix.hold.update(dt, false)
	var free = busy <= 0.0 and not respawning and player.locked <= 0.0
	if best:
		if best.action == "tide":
			best.hold_update(dt, free and _held("tide"))
			best_prompt = best.prompt(ctx)
		elif free and _pressed("interact") and not best_prompt.get("disabled", false):
			player.anim_flags["interacting"] = 0.7
			best.activate(ctx)
		elif _pressed("interact") and best_prompt.get("disabled", false):
			Sfx.play("fail")
	ui.set_prompt(best_prompt)
	if free and _pressed("scan"):
		scan()
	player.anim_flags["scanning"] = label_t > 4.4

func _line_of_sight(ix: Interactable) -> bool:
	var space = get_world_3d().direct_space_state
	var from = player.global_position + Vector3(0, 1.2, 0)
	var to = ix.global_position + Vector3(0, ix.label_height - 0.4, 0)
	var q = PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
	var hit = space.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < 1.2

func scan() -> void:
	if scan_cd > 0.0:
		return
	scan_cd = 1.2
	label_t = 5.0
	scan_radius = 36.0 if Game.state["upgrades"].get("lens", false) else 18.0
	lume.scan_pulse(scan_radius)
	Sfx.play("scan")
	var ctx = _ctx()
	var p = player.global_position
	for ix in region.interactables:
		if ix.enabled and ix.global_position.distance_to(p) < scan_radius:
			ix.on_scan(ctx)
	if Game.state["upgrades"].get("compass", false):
		var best: Interactable = null
		var bd = INF
		for ix in region.interactables:
			if ix is IXS.Echo and not ix.collected:
				var d = ix.global_position.distance_to(p)
				if d < bd:
					bd = d
					best = ix
		if best:
			mark(best.global_position, 5.0)
			_lume_say("lume.compass", 2.5)
	var o = region.current_objective()
	if not o.is_empty() and hint_level >= 1:
		mark(o["target"].call(), 4.0)

func mark(pos: Vector3, seconds: float) -> void:
	beam.global_position = pos + Vector3(0, 7, 0)
	beam_t = seconds

func _labels(dt: float) -> void:
	label_t = maxf(0.0, label_t - dt)
	if label_t <= 0.0:
		ui.set_labels([])
		return
	var p = player.global_position
	var out = []
	var c = cam.camera
	for ix in region.interactables:
		if not ix.visible or ix.global_position.distance_to(p) > scan_radius:
			continue
		if ix is IXS.Echo and not (Game.state["upgrades"].get("lens", false) or ix.global_position.distance_to(p) < 10.0):
			continue
		var txt: String = ix.scan_text()
		if txt == "":
			continue
		var wp = ix.global_position + Vector3(0, ix.label_height, 0)
		if c.is_position_behind(wp):
			continue
		out.append({"pos": c.unproject_position(wp), "text": txt, "kind": ix.scan_kind, "alpha": minf(1.0, label_t / 0.8), "d": wp.distance_to(p)})
	for g in region.guardians:
		var gd: Guardian = g["guard"]
		if gd.state != "pacified" and gd.global_position.distance_to(p) < scan_radius and not c.is_position_behind(gd.global_position):
			out.append({"pos": c.unproject_position(gd.global_position + Vector3(0, 2.2, 0)), "text": I18n.t("scan.guardian"), "kind": "threat", "alpha": minf(1.0, label_t / 0.8), "d": 0.0})
	out.sort_custom(func(a, b): return a["d"] < b["d"])
	var placed = []
	for l in out:
		var w = float(l["text"].length()) * 8.0 + 24.0
		for tries in 6:
			var hit = false
			for q in placed:
				if absf(q["pos"].x - l["pos"].x) < (q["w"] + w) / 2.0 and absf(q["pos"].y - l["pos"].y) < 30.0:
					l["pos"] = Vector2(l["pos"].x, q["pos"].y - 32.0)
					hit = true
			if not hit:
				break
		l["w"] = w
		placed.append(l)
	ui.set_labels(placed)

func _effects(dt: float) -> void:
	if beam_t > 0.0:
		beam_t -= dt
		beam.visible = true
		(beam.material_override as StandardMaterial3D).albedo_color.a = minf(0.35, beam_t * 0.3) * (0.75 + 0.25 * sin(time * 6.0))
	else:
		beam.visible = false

# --- objetivos e dicas --------------------------------------------------------------

func _objectives(dt: float) -> void:
	var o = region.current_objective()
	var oid: String = o.get("id", "")
	if oid != obj_id:
		if obj_id != "" and oid != "":
			Sfx.play("confirm", -6.0)
		obj_id = oid
		obj_t = 0.0
		hint_level = 0
	ui.set_objective(I18n.t("region." + region.id), I18n.t("obj." + oid) if oid != "" else "")
	if oid == "":
		return
	obj_t += dt
	var delay = HINT_DELAY / 2.0 if Game.options["assisted"] else HINT_DELAY
	if Game.options["hints"] and hint_level < 3 and obj_t > delay + hint_level * HINT_STEP:
		hint_level += 1
		Game.stat("hints")
		var key = "hint.%s.%d" % [oid, hint_level]
		if not I18n.has(key):
			key = "hint.generic.%d" % hint_level
		var vl = Sfx.voice(key)
		ui.say(I18n.t(key), maxf(7.0, vl + 0.6), true)
		if vl <= 0.0:
			Sfx.play("lume", -4.0)
		if hint_level >= 2:
			mark(o["target"].call(), 8.0)

func _lume_say(key: String, seconds: float = 4.5, params: Dictionary = {}) -> void:
	var vl = Sfx.voice(key)
	ui.say(I18n.t(key, params), maxf(seconds, vl + 0.6))
	if vl <= 0.0:
		Sfx.play("lume", -6.0)

func lume_once(key: String, seconds: float = 4.5, params: Dictionary = {}) -> void:
	var k = region.id + ":" + key if region else key
	if said.has(k):
		return
	said[k] = true
	_lume_say(key, seconds, params)

func say(key: String, seconds: float = 4.5, params: Dictionary = {}) -> void:
	_lume_say(key, seconds, params)

# --- eventos ---------------------------------------------------------------------

func _on_player_event(name: String) -> void:
	match name:
		"step":
			Sfx.play("step", -14.0, randf_range(0.9, 1.1))
		"jump":
			Sfx.play("jump", -6.0)
		"land":
			Sfx.play("land", -8.0)
		"glide":
			Sfx.play("glide", -4.0)
		"dodge":
			Sfx.play("dodge", -4.0)

func on_tide_started(_sid: String, _to_high: bool) -> void:
	cam.shake = 0.08

func on_tide_finished(_sid: String, _is_high: bool) -> void:
	pass

func _on_guard_event(type: String, g: Dictionary) -> void:
	match type:
		"alert":
			Sfx.play("alert")
			say("lume.guardian_saw", 3.5)
		"lost":
			lume_once("lume.guardian_lost", 4.0)
		"hit":
			on_hit(g)
		"state:waking":
			if mode == "play":
				lume_once("lume.guardian_wake", 4.5)

func on_hit(g: Dictionary) -> void:
	if respawning:
		return
	Game.state["integrity"] -= 1
	Game.stat("hits")
	Sfx.play("hit")
	cam.shake = 0.35
	player.anim_flags["hurt"] = 0.6
	player.locked = 0.4
	if Game.state["integrity"] <= 0:
		reboot(true)
		return
	respawning = true
	await ui.fade_to(1.0, 0.35)
	var exit: Vector3 = g.get("exit", region.spawns[Game.state["spawn"]]["pos"])
	player.teleport(exit + Vector3(0, 0.1, 0))
	lume.place(exit + Vector3(0.8, 1.9, 0))
	if Game.state["integrity"] == 1:
		say("lume.hit_low", 4.0)
	await ui.fade_to(0.0, 0.35)
	respawning = false

func reboot(from_damage: bool) -> void:
	respawning = true
	await ui.fade_to(1.0, 0.5)
	Game.state["integrity"] = Game.max_integrity()
	var sp: Dictionary = region.spawns.get(Game.state["spawn"], region.spawns.values()[0])
	place_player(sp["pos"], sp["yaw"])
	for g in region.guardians:
		g["guard"].reset(g["active"].call())
	if from_damage:
		say("lume.reboot", 3.0)
	await ui.fade_to(0.0, 0.5)
	respawning = false

func respawn(reason: String) -> void:
	if respawning:
		return
	respawning = true
	Game.stat("falls")
	Sfx.play("fall")
	await ui.fade_to(1.0, 0.3)
	var spot: Variant = null
	var pts: Array = player.safe_points
	for i in range(pts.size() - 1, -1, -1):
		var s: Dictionary = pts[i]
		var body: Variant = s["body"]
		if body != null and (not is_instance_valid(body) or (body is CollisionObject3D and body.collision_layer == 0)):
			continue
		var pos: Vector3 = s["pos"]
		if region.water_level_at(pos) > pos.y - 0.3:
			continue
		var space = get_world_3d().direct_space_state
		var q = PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -1.0, 0), 1)
		if space.intersect_ray(q).is_empty():
			continue
		var bad = false
		for g in region.guardians:
			if g["active"].call() and Builder.inside(g["zone"], Vector2(pos.x, pos.z)) and pos.y < g["zone_top"]:
				bad = true
		if bad:
			continue
		spot = pos
		break
	if spot == null:
		spot = region.spawns.get(Game.state["spawn"], region.spawns.values()[0])["pos"]
	player.teleport(spot + Vector3(0, 0.1, 0))
	lume.place(spot + Vector3(0.8, 1.9, 0))
	if Game.state["stats"]["falls"] <= 2 or reason == "drown":
		say("lume.fall", 2.5)
	await ui.fade_to(0.0, 0.35)
	respawning = false

func send_lume(target: Vector3, on_arrive: Callable) -> void:
	busy = 99.0
	player.locked = 0.6
	say("lume.relay_go", 2.5)
	_lume_arrive_cb = on_arrive
	lume.fly_to(target, _lume_arrived)

var _lume_arrive_cb: Callable

func _lume_arrived() -> void:
	if _lume_arrive_cb.is_valid():
		_lume_arrive_cb.call()
	say("lume.relay_on", 3.0)
	await get_tree().create_timer(1.4).timeout
	lume.follow()
	busy = 0.0

func on_echo(id: String) -> void:
	Sfx.play("echo")
	# a narradora lê o eco; sem gravação, a Lume comenta como antes
	var vl = Sfx.voice("echo." + id)
	ui.show_toast(I18n.t("region." + id.split("_")[0]), I18n.t("echo." + id), maxf(8.0, vl + 1.5))
	if vl <= 0.0:
		lume_once("lume.echo", 3.5)
	if Game.any_upgrade_ready():
		if vl > 0.0:
			get_tree().create_timer(vl + 0.4).timeout.connect(_say_upgrade)
		else:
			_say_upgrade()
	Game.save_game()

func _say_upgrade() -> void:
	if mode == "play":
		say("lume.upgrade", 4.0)

func on_ability(a: String) -> void:
	Sfx.play("unlock")
	ui.show_toast(I18n.t("hud.ability") + " — " + I18n.t("ability." + a), I18n.t("ability." + a + "_help"), 9.0)
	Game.save_game()

func on_memory(rid: String) -> void:
	if rid in Game.state["memories"]:
		return
	Game.state["memories"].append(rid)
	Sfx.play("echo")
	var vl = Sfx.voice("mem.%s.text" % rid)
	ui.show_toast(I18n.t("mem.%s.title" % rid), I18n.t("mem.%s.text" % rid), maxf(10.0, vl + 1.5))
	Game.save_game()

func rest_at(checkpoint_id: String) -> void:
	Game.state["integrity"] = Game.max_integrity()
	Game.state["spawn"] = checkpoint_id
	Sfx.play("success")
	say("lume.rest", 3.5)
	Game.save_game()
	ui.show_toast(I18n.t("saved"), "", 2.5)

# --- final -------------------------------------------------------------------------------

func finish(choice: String) -> void:
	Game.state["ending"] = choice
	Game.state["completed"] = true
	Game.save_game()
	mode = "cutscene"
	ui.show_hud(false)
	Sfx.music("final_liberar" if choice == "free" else "final_manter", 3.0)
	var c: Vector3 = region.env.get("center", Vector3.ZERO)
	cam.play([
		{"pos": c + Vector3(16, 6, 16), "look": c},
		{"pos": c + Vector3(-18, 12, 10), "look": c},
		{"pos": c + Vector3(-8, 26, -20), "look": c},
	], 10.0, func(): _epilogue(choice))
	ui.show_title(I18n.t("final.%s.title" % choice), "", 8.0)

func _epilogue(choice: String) -> void:
	await load_region("farol", "hub")
	mode = "ending"
	Sfx.voice("final.%s.text" % choice)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var st: Dictionary = Game.state["stats"]
	var stats = I18n.t("end.stats", {"time": Game.fmt_time(st["time"]), "echoes": Game.echo_count(), "falls": int(st["falls"]), "hits": int(st["hits"]), "hints": int(st["hints"])})
	ui.open_menu(I18n.t("final.%s.title" % choice), [
		[I18n.t("end.continue"), func(): _start_play()],
		[I18n.t("end.credits"), func(): show_credits(func(): _epilogue_menu(choice))],
		[I18n.t("menu.main"), show_main_menu],
	], {"body": I18n.t("final.%s.text" % choice) + "\n\n" + stats, "width": 680, "bg_alpha": 0.45})

func _epilogue_menu(choice: String) -> void:
	_epilogue_menu_only(choice)

func _epilogue_menu_only(choice: String) -> void:
	mode = "ending"
	var st: Dictionary = Game.state["stats"]
	var stats = I18n.t("end.stats", {"time": Game.fmt_time(st["time"]), "echoes": Game.echo_count(), "falls": int(st["falls"]), "hits": int(st["hits"]), "hints": int(st["hints"])})
	ui.open_menu(I18n.t("final.%s.title" % choice), [[I18n.t("end.continue"), func(): _start_play()], [I18n.t("menu.main"), show_main_menu]], {"body": I18n.t("final.%s.text" % choice) + "\n\n" + stats, "width": 680, "bg_alpha": 0.45})


## Mapa esquemático do arquipélago (GDD 06): Farol, Jardim, Cidade, Coração.
class MapView extends Control:
	func _draw() -> void:
		var pos = {"farol": Vector2(110, 210), "jardim": Vector2(300, 70), "cidade": Vector2(480, 200), "coracao": Vector2(300, 320)}
		var main_links = [["farol", "jardim"], ["jardim", "cidade"], ["cidade", "coracao"]]
		var short = [["farol", "cidade"], ["farol", "coracao"]]
		for l in short:
			draw_line(pos[l[0]], pos[l[1]], Color(0.6, 0.7, 0.7, 0.35), 2.0)
		for l in main_links:
			draw_line(pos[l[0]], pos[l[1]], Color(0.49, 0.96, 0.86, 0.7), 4.0)
		var font = ThemeDB.fallback_font
		for k in pos:
			var open: bool = k == "farol" or Game.state["portals"].get(k, false) or (k == "jardim" and Game.flag("farol.crossed", false))
			var done: bool = k in Game.state["memories"] or (k == "farol" and Game.flag("farol.crossed", false))
			var col = Palette.RESSONANCIA if done else (Palette.COBRE if open else Color(0.5, 0.55, 0.6))
			draw_circle(pos[k], 34, Palette.ABISMO)
			draw_arc(pos[k], 34, 0, TAU, 40, col, 4.0)
			draw_circle(pos[k], 12, col)
			if Game.state["region"] == k:
				draw_arc(pos[k], 44, 0, TAU, 40, Palette.CERAMICA, 2.0)
			var label = I18n.t("region." + k)
			draw_string(font, pos[k] + Vector2(-60, 56), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Palette.CERAMICA)
			var status = I18n.t("map.done") if done else (I18n.t("map.open") if open else I18n.t("map.locked"))
			draw_string(font, pos[k] + Vector2(-60, 74), status, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, col)
