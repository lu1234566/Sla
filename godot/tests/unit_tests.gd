extends SceneTree
## Testes de unidade sem janela (godot --headless --script res://tests/unit_tests.gd).
## Regras de maré, confirmação por segurar, saves (atômico, backup, checksum,
## migração), custos de melhorias e cobertura de textos PT/EN.

var passed = 0
var failed: Array = []

func ok(cond: bool, name: String) -> void:
	if cond:
		passed += 1
	else:
		failed.append(name)
		print("  FALHOU: ", name)

func _init() -> void:
	_tide()
	_hold()
	_save()
	_texts()
	print("UNIT: %d ok, %d falhas" % [passed, failed.size()])
	quit(0 if failed.is_empty() else 1)

func _tide() -> void:
	var s = TideSector.new("x", true)
	ok(s.high and s.level == 1.0 and not s.transitioning, "maré começa alta e parada")
	ok(s.refusal(true) == "", "maré alta pode baixar mesmo com Íris na bacia")
	ok(s.toggle(), "alternar")
	ok(s.transitioning and not s.high, "transição para baixa")
	ok(s.refusal() == "transitioning", "recusa durante a transição")
	s.update(TideSector.TRANSITION_TIME * 0.5)
	ok(s.level > 0.2 and s.level < 0.8, "nível intermediário no meio da transição")
	s.update(TideSector.TRANSITION_TIME)
	ok(not s.transitioning and s.level == 0.0, "transição completa em 2,5 s")
	ok(s.refusal() == "cooldown", "cooldown após a transição")
	s.update(TideSector.COOLDOWN + 0.01)
	ok(s.refusal() == "", "cooldown de 5 s termina")
	ok(s.refusal(true) == "unsafe", "subir a maré com Íris na bacia é recusado")
	var got = []
	s.refused.connect(func(r): got.append(r))
	ok(not s.toggle(true) and got == ["unsafe"], "sinal de recusa")
	s.set_state(true)
	ok(s.high and s.level == 1.0 and s.cooldown == 0.0, "set_state imediato")
	s.force_toggle()
	ok(s.transitioning and not s.high, "nó duplo força a mudança")

func _hold() -> void:
	var h = TideSector.HoldConfirm.new()
	ok(not h.update(0.5, true), "segurar 0,5 s não confirma")
	ok(h.update(0.6, true), "segurar 1 s confirma")
	ok(not h.update(1.0, true), "dispara uma vez por pressão")
	h.update(0.1, false)
	ok(h.ratio == 0.0, "soltar zera")

func _save() -> void:
	var dir = "user://test_saves_%d" % Time.get_ticks_usec()
	var sm = SaveManager.new(dir)
	var data = {"region": "cidade", "echoes": ["a", "b"], "flags": {"x": true}, "integrity": 3}
	ok(sm.save(1, data), "salvar")
	var r = sm.load_slot(1)
	ok(r.get("source", "") == "main" and r["data"]["region"] == "cidade" and r["data"]["echoes"].size() == 2, "carregar")
	data["region"] = "coracao"
	ok(sm.save(1, data), "salvar de novo (anterior vira backup)")
	var f = FileAccess.open(dir + "/slot1.main.json", FileAccess.WRITE)
	f.store_string("{corrompido")
	f.close()
	r = sm.load_slot(1)
	ok(r.get("source", "") == "backup" and r["data"]["region"] == "cidade", "save corrompido cai no backup")
	# checksum adulterado
	sm.save(2, data)
	var txt = FileAccess.get_file_as_string(dir + "/slot2.main.json")
	var outer = JSON.parse_string(txt)
	outer["payload"] = (outer["payload"] as String).replace("coracao", "jardim")
	f = FileAccess.open(dir + "/slot2.main.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(outer))
	f.close()
	ok(sm.load_slot(2).is_empty(), "checksum inválido é rejeitado")
	# migração v2 -> v3
	var old = {"region": "jardim", "version": 2}
	var payload = JSON.stringify(old)
	f = FileAccess.open(dir + "/slot3.main.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"sum": SaveManager.checksum(payload), "payload": payload}))
	f.close()
	r = sm.load_slot(3)
	ok(not r.is_empty() and r["data"]["visor"] == "turquesa" and r["data"].has("upgrades"), "migração v2 → v3")
	ok(not FileAccess.file_exists(dir + "/slot1.tmp.json"), "arquivo temporário removido")
	for s in [1, 2, 3]:
		sm.clear(s)
	ok(not sm.has_slot(1), "apagar espaço")
	DirAccess.remove_absolute(dir)

func _texts() -> void:
	var i18n = load("res://scripts/autoload/i18n.gd").new()
	var pt: Dictionary = i18n.PT
	var en: Dictionary = i18n.EN
	var missing = []
	for k in pt:
		if not en.has(k):
			missing.append("en:" + k)
	for k in en:
		if not pt.has(k):
			missing.append("pt:" + k)
	ok(missing.is_empty(), "PT e EN com as mesmas chaves %s" % str(missing.slice(0, 6)))
	# toda chave literal usada no código existe
	var used = {}
	var re = RegEx.create_from_string("I18n\\.t\\(\"([a-z_.0-9]+)\"")
	for path in _scripts("res://scripts"):
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			used[m.get_string(1)] = path
	var absent = []
	for k in used:
		if not k.ends_with(".") and not pt.has(k):
			absent.append(k)
	ok(absent.is_empty(), "chaves usadas no código existem %s" % str(absent.slice(0, 8)))
	# objetivos, ecos e memórias
	var obj_re = RegEx.create_from_string("add_objective\\(\"([a-z_0-9]+)\"")
	var echo_re = RegEx.create_from_string("IX\\.Echo\\.new\\(\"([a-z_]+)\"")
	var echoes = {}
	var no_text = []
	for path in _scripts("res://scripts/world/regions"):
		var src = FileAccess.get_file_as_string(path)
		for m in obj_re.search_all(src):
			if not pt.has("obj." + m.get_string(1)):
				no_text.append("obj." + m.get_string(1))
		for m in echo_re.search_all(src):
			echoes[m.get_string(1)] = true
			if not pt.has("echo." + m.get_string(1)):
				no_text.append("echo." + m.get_string(1))
	ok(no_text.is_empty(), "objetivos e ecos têm texto %s" % str(no_text))
	ok(echoes.size() == 18, "18 ecos únicos nas regiões (%d)" % echoes.size())
	for rid in ["jardim", "cidade", "coracao"]:
		ok(pt.has("mem.%s.title" % rid) and pt.has("mem.%s.text" % rid), "memória " + rid)
	i18n.free()

func _scripts(dir: String) -> Array:
	var out = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out += _scripts(dir + "/" + d)
	return out
