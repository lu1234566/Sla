class_name Palette
## Paleta da bíblia de arte (GDD 09) e fábrica de materiais compartilhados.

const ABISMO := Color("#102331")
const PETROLEO := Color("#297D83")
const CERAMICA := Color("#E9D8AC")
const COBRE := Color("#F3AB63")
const RESSONANCIA := Color("#7CF4DC")
const SAL := Color("#D36C55")
const AREIA := Color("#C79C76")
const AREIA_CLARA := Color("#D9B892")
const ROCHA := Color("#3E6672")
const ROCHA_ESCURA := Color("#1C3A46")
const NOITE := Color("#0B1A24")

static var _cache = {}

## Material fosco "cerâmico" low-poly.
static func mat(color: Color, opts: Dictionary = {}) -> StandardMaterial3D:
	var key = "%s|%s" % [color.to_html(), str(opts)]
	if _cache.has(key):
		return _cache[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = opts.get("roughness", 0.88)
	m.metallic = opts.get("metallic", 0.0)
	if opts.has("emission"):
		m.emission_enabled = true
		m.emission = opts["emission"]
		m.emission_energy_multiplier = opts.get("energy", 1.0)
	if opts.get("unshaded", false):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if opts.has("alpha"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = opts["alpha"]
	if opts.get("double", false):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m

static func glow(energy: float = 1.6, color: Color = RESSONANCIA) -> StandardMaterial3D:
	return mat(color, {"emission": color, "energy": energy, "roughness": 0.4})

static func crystal(variant: int = 0) -> StandardMaterial3D:
	var tones = [[Color("#2FA3A0"), RESSONANCIA, 0.45], [Color("#58D6C4"), RESSONANCIA, 0.7], [Color("#1F6E78"), Color("#2FA3A0"), 0.4]]
	var t: Array = tones[variant % tones.size()]
	return mat(t[0], {"emission": t[1], "energy": t[2], "roughness": 0.35, "metallic": 0.05})

static func copper() -> StandardMaterial3D:
	return mat(COBRE, {"metallic": 0.35, "roughness": 0.45})

## Cópia única (para materiais que mudam em tempo de execução).
static func unique(color: Color, opts: Dictionary = {}) -> StandardMaterial3D:
	return mat(color, opts).duplicate()
