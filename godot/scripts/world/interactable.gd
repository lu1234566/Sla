class_name Interactable
extends Node3D
## Base dos objetos com que Íris interage. A região registra cada um; o Main
## escolhe o mais próximo, mostra o prompt e chama activate().
## action: "interact" (E), "tide" (segurar Q), "touch" (ao tocar), "relay" (E à distância), "scan" (só escaneável)

var region: Node
var uid = ""
var radius = 2.0
var action = "interact"
var scan_kind = "energy"  # energy | interact | threat | muted
var label_height = 1.6
var scanned = false
var enabled = true

func _init(id: String = "") -> void:
	uid = id

func persist_key() -> String:
	return "%s.%s" % [region.id if region else "?", uid]

## Distância horizontal e vertical de alcance.
func in_range(p: Vector3) -> bool:
	return enabled and Vector2(p.x - global_position.x, p.z - global_position.z).length() < radius and absf(p.y - global_position.y) < 2.2

## {} para nenhum prompt, ou {"text": String, "action": String, "disabled": bool}
func prompt(_ctx: Dictionary) -> Dictionary:
	return {}

func activate(_ctx: Dictionary) -> void:
	pass

func scan_text() -> String:
	return ""

func on_scan(_ctx: Dictionary) -> void:
	scanned = true

func tick(_dt: float, _ctx: Dictionary) -> void:
	pass

## Utilitário: material único com brilho controlável.
static func glow_mat(color: Color = Palette.RESSONANCIA, energy: float = 1.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m

static func ring_mesh(r: float, thickness: float) -> TorusMesh:
	var t = TorusMesh.new()
	t.inner_radius = r - thickness
	t.outer_radius = r + thickness
	t.rings = 24
	t.ring_segments = 6
	return t

static func floor_circle(r: float, color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var t = TorusMesh.new()
	t.inner_radius = r - 0.06
	t.outer_radius = r + 0.06
	t.rings = 40
	t.ring_segments = 3
	mi.mesh = t
	mi.scale = Vector3(1, 0.05, 1)
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color, 0.45)
	mi.material_override = m
	mi.position.y = 0.04
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
