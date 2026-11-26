class_name SaveManager
extends RefCounted
## Save local versionado (GDD 13): gravação atômica (tmp -> valida -> main,
## anterior vira backup), checksum, migração e 3 espaços separados.

const VERSION := 3
const SLOTS := 3

var dir = "user://saves"

func _init(base_dir: String = "user://saves") -> void:
	dir = base_dir
	DirAccess.make_dir_recursive_absolute(dir)

func _path(slot: int, kind: String) -> String:
	return "%s/slot%d.%s.json" % [dir, slot, kind]

static func checksum(text: String) -> String:
	return text.sha256_text().substr(0, 16)

func _wrap(data: Dictionary) -> String:
	var d = data.duplicate(true)
	d["version"] = VERSION
	d["saved_at"] = Time.get_unix_time_from_system()
	var payload = JSON.stringify(d)
	return JSON.stringify({"sum": checksum(payload), "payload": payload})

func _unwrap(text: String) -> Variant:
	if text.is_empty():
		return null
	var outer: Variant = JSON.parse_string(text)
	if typeof(outer) != TYPE_DICTIONARY or not outer.has("payload") or not outer.has("sum"):
		return null
	if checksum(outer["payload"]) != outer["sum"]:
		return null
	var data: Variant = JSON.parse_string(outer["payload"])
	if typeof(data) != TYPE_DICTIONARY:
		return null
	data = _migrate(data)
	return data if int(data.get("version", 0)) == VERSION else null

func _migrate(d: Dictionary) -> Dictionary:
	var v = int(d.get("version", 0))
	if v == 2:
		d["upgrades"] = d.get("upgrades", {})
		d["visor"] = d.get("visor", "turquesa")
		d["version"] = 3
	return d

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f = FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""

func _write(path: String, text: String) -> bool:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true

func save(slot: int, data: Dictionary) -> bool:
	var wrapped = _wrap(data)
	var tmp = _path(slot, "tmp")
	if not _write(tmp, wrapped) or _unwrap(_read(tmp)) == null:
		push_warning("SaveManager: falha ao validar o save temporário")
		return false
	var current = _read(_path(slot, "main"))
	if not current.is_empty() and _unwrap(current) != null:
		_write(_path(slot, "bak"), current)
	_write(_path(slot, "main"), wrapped)
	DirAccess.remove_absolute(tmp)
	return true

## {"data": Dictionary, "source": "main"|"backup"} ou {}.
func load_slot(slot: int) -> Dictionary:
	var main: Variant = _unwrap(_read(_path(slot, "main")))
	if main != null:
		return {"data": main, "source": "main"}
	var bak: Variant = _unwrap(_read(_path(slot, "bak")))
	if bak != null:
		return {"data": bak, "source": "backup"}
	return {}

func has_slot(slot: int) -> bool:
	return not load_slot(slot).is_empty()

func clear(slot: int) -> void:
	for k in ["main", "bak", "tmp"]:
		if FileAccess.file_exists(_path(slot, k)):
			DirAccess.remove_absolute(_path(slot, k))
