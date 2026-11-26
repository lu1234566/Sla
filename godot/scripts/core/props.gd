class_name Props
## Instancia modelos GLB (originais do kit e CC0 baixados) recoloridos com a
## paleta. Os modelos são apoiados no chão (base em y = 0) e centralizados.

const Q := "res://assets/models/quaternius/"
const O := "res://assets/models/originais/"

## nome -> [arquivo, modo de recoloração]
const CATALOG := {
	"crystal1": ["rpg_items_pack/Crystal1.glb", "crystal"], "crystal1b": ["rpg_items_pack/Crystal1_Damaged.glb", "crystal"],
	"crystal2": ["rpg_items_pack/Crystal2.glb", "crystal"], "crystal2b": ["rpg_items_pack/Crystal2_Damaged.glb", "crystal"],
	"crystal3": ["rpg_items_pack/Crystal3.glb", "crystal"], "crystal5": ["rpg_items_pack/Crystal5.glb", "crystal"],
	"gem_blue": ["platformer_game_pack/Gem_Blue.glb", "crystal"], "gem_pink": ["platformer_game_pack/Gem_Pink.glb", "glow"],
	"rock1": ["nature_pack/Rock_1.glb", "rock"], "rock2": ["nature_pack/Rock_2.glb", "rock"], "rock3": ["nature_pack/Rock_3.glb", "rock"],
	"rock4": ["nature_pack/Rock_4.glb", "rock"], "rock5": ["nature_pack/Rock_5.glb", "rock"], "rock6": ["nature_pack/Rock_6.glb", "rock"],
	"rock7": ["nature_pack/Rock_7.glb", "rock"], "stone1": ["modular_dungeon_pack/Rock1.glb", "rock"], "stone2": ["modular_dungeon_pack/Rock2.glb", "rock"],
	"stone3": ["modular_dungeon_pack/Rock3.glb", "rock"], "stone4": ["modular_dungeon_pack/Rock4.glb", "rock"], "stone5": ["modular_dungeon_pack/Rock5.glb", "rock"],
	"rock_cluster1": ["real_time_strategy_pack/Resource_Rock_1.glb", "rock"], "rock_cluster2": ["real_time_strategy_pack/Resource_Rock_2.glb", "rock"],
	"column": ["modular_dungeon_pack/Column.glb", "ceramic"], "column_broken": ["modular_dungeon_pack/Column_Broken.glb", "ceramic"],
	"column_broken2": ["modular_dungeon_pack/Column_Broken2.glb", "ceramic"],
	"pipe_t": ["platformer_game_pack/Pipe_T.glb", "copper"], "pipe_straight": ["platformer_game_pack/Pipe_Straight.glb", "copper"],
	"pipe_90": ["platformer_game_pack/Pipe_90.glb", "copper"], "lever": ["platformer_game_pack/Lever.glb", "lever"],
	"plant1": ["nature_pack/Plant_1.glb", "flora"], "plant2": ["nature_pack/Plant_2.glb", "coral"], "plant3": ["nature_pack/Plant_3.glb", "flora"],
	"plant5": ["nature_pack/Plant_5.glb", "flora"],
	# Cidade Invertida
	"bld_2story": ["buildings_pack_3/2Story_Mat.glb", "city"], "bld_2story_wide": ["buildings_pack_3/2Story_Wide_Mat.glb", "city"],
	"bld_3story": ["buildings_pack_3/3Story_Small_Mat.glb", "city"], "bld_3story_slim": ["buildings_pack_3/3Story_Slim_Mat.glb", "city"],
	"bld_4story": ["buildings_pack_3/4Story_Mat.glb", "city"], "bld_4story_center": ["buildings_pack_3/4Story_Center_Mat.glb", "city"],
	"bld_6story": ["buildings_pack_3/6Story_Stack_Mat.glb", "city"], "bld_round": ["buildings_pack_3/2Story_RoundRoof_Mat.glb", "city"],
	"bld_balcony": ["buildings_pack_3/3Story_Balcony_Mat.glb", "city"], "bld_columns": ["buildings_pack_3/2Story_Columns_Mat.glb", "city"],
	"bld_gable": ["buildings_pack_3/2Story_GableRoof_Mat.glb", "city"], "bld_1story": ["buildings_pack_3/1Story_Mat.glb", "city"],
	"bell_tower": ["medieval_village_pack/Bell_Tower.glb", "city"], "market1": ["medieval_village_pack/MarketStand_1.glb", "city"],
	"market2": ["medieval_village_pack/MarketStand_2.glb", "city"], "well": ["medieval_village_pack/Well.glb", "city"],
	"gazebo": ["medieval_village_pack/Gazebo.glb", "city"], "bench": ["medieval_village_pack/Bench_1.glb", "city"],
	"barrel": ["medieval_village_pack/Barrel.glb", "city"], "crate": ["medieval_village_pack/Crate.glb", "city"],
	"cart": ["medieval_village_pack/Cart.glb", "city"], "bell": ["medieval_village_pack/Bell.glb", "copper"],
	"streetlight": ["street_pack/Streetlight_Single.glb", "lamp"], "streetlight2": ["street_pack/Streetlight_Double.glb", "lamp"],
	"lamp_city": ["cyberpunk_pack/Light_Street_1.glb", "lamp"], "antenna": ["cyberpunk_pack/Antenna_1.glb", "copper"],
	"support": ["cyberpunk_pack/Support.glb", "metal"], "support_long": ["cyberpunk_pack/Support_Long.glb", "metal"],
	"cable": ["cyberpunk_pack/Cable_Long.glb", "metal"],
	# tecnologia antiga (relés, portais, terminais)
	"teleporter1": ["modular_sci_fi/Props_Teleporter_1.glb", "tech"], "teleporter2": ["modular_sci_fi/Props_Teleporter_2.glb", "tech"],
	"pod": ["modular_sci_fi/Props_Pod.glb", "tech"], "vessel": ["modular_sci_fi/Props_Vessel.glb", "tech"],
	"vessel_tall": ["modular_sci_fi/Props_Vessel_Tall.glb", "tech"], "vessel_short": ["modular_sci_fi/Props_Vessel_Short.glb", "tech"],
	"base_pad": ["modular_sci_fi/Props_Base.glb", "tech"], "capsule": ["modular_sci_fi/Props_Capsule.glb", "tech"],
	"computer": ["modular_sci_fi/Props_Computer.glb", "tech"], "statue": ["modular_sci_fi/Props_Statue.glb", "tech"],
	"door_double": ["modular_sci_fi/Door_Double.glb", "tech"], "door_single": ["modular_sci_fi/Door_Single.glb", "tech"],
	"tech_column": ["modular_sci_fi/Column_1.glb", "tech"], "tech_column2": ["modular_sci_fi/Column_2.glb", "tech"],
	"hexagon": ["modular_sci_fi/Details_Hexagon.glb", "tech"], "staircase": ["modular_sci_fi/Staircase.glb", "tech"],
	# oficina
	"bookshelf": ["house_interior_pack/Bookshelf.glb", "wood"], "table_round": ["house_interior_pack/Table_RoundLarge.glb", "wood"],
	"lamp_floor": ["house_interior_pack/Light_Floor1.glb", "lamp"], "lamp_stand": ["house_interior_pack/Light_Stand1.glb", "lamp"],
	"lamp_ico": ["house_interior_pack/Light_Icosahedron.glb", "lamp"], "shelf": ["house_interior_pack/Shelf_Large.glb", "wood"],
	"pedestal": ["modular_dungeon_1/Pedestal.glb", "ceramic"], "pedestal2": ["modular_dungeon_1/Pedestal2.glb", "ceramic"],
	"arch": ["modular_dungeon_1/Arch.glb", "ceramic"],
	# Coração Abissal e oceano
	"mushroom1": ["crops_pack/Mushroom_1.glb", "biolum"], "mushroom2": ["crops_pack/Mushroom_2.glb", "biolum"],
	"mushroom3": ["crops_pack/Mushroom_3.glb", "biolum"], "mushroom4": ["crops_pack/Mushroom_4.glb", "biolum"],
	"raft": ["survival_pack/Raft.glb", "wood"], "cloud1": ["platformer_pack/Cloud1.glb", "cloud"], "cloud2": ["platformer_pack/Cloud2.glb", "cloud"],
	"cloud3": ["platformer_pack/Cloud3.glb", "cloud"],
	"manta": ["fish_pack/Manta_ray.glb", "keep"], "whale": ["fish_pack/Whale.glb", "keep"], "fish1": ["fish_pack/Fish1.glb", "keep"],
	"fish2": ["fish_pack/Fish2.glb", "keep"], "fish3": ["fish_pack/Fish3.glb", "keep"], "anglerfish": ["cute_fish_pack/Anglerfish.glb", "keep"],
	"dolphin": ["fish_pack/Dolphin.glb", "keep"],
}

static var _scenes = {}
static var _bounds = {}

static func scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		var path: String = (O + name) if name.ends_with(".glb") else (Q + CATALOG[name][0])
		_scenes[name] = load(path)
	return _scenes[name]

static func original(file: String) -> Node3D:
	return scene(file).instantiate()

## AABB local de uma cena instanciada (malhas, sem escala do pai).
static func aabb_of(root: Node3D) -> AABB:
	var box = AABB()
	var first = true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi = n as MeshInstance3D
		var xf = Transform3D.IDENTITY
		var p: Node = mi
		while p != root and p != null:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## Instância de um modelo do catálogo.
## opts: height (altura-alvo em m) | scale, tone, variant, keep_anim (bool)
static func make(name: String, opts: Dictionary = {}) -> Node3D:
	var inner: Node3D = scene(name).instantiate()
	if not _bounds.has(name):
		_bounds[name] = aabb_of(inner)
	var box: AABB = _bounds[name]
	var s: float = opts.get("scale", 1.0)
	if opts.has("height"):
		s = float(opts["height"]) / maxf(box.size.y, 0.001)
	recolor(inner, CATALOG[name][1], opts)
	var holder = Node3D.new()
	holder.name = name
	inner.scale = Vector3.ONE * s
	var c = box.get_center()
	inner.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	holder.add_child(inner)
	holder.set_meta("size", box.size * s)
	if opts.get("anim", ""):
		var ap = inner.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			var list = ap.get_animation_list()
			var want: String = opts["anim"]
			for a in list:
				if a.findn(want) >= 0:
					ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
					ap.play(a)
					break
	return holder

static func _pick(mode: String, mat_name: String, i: int, opts: Dictionary) -> Material:
	var n = mat_name.to_lower()
	match mode:
		"crystal":
			return Palette.crystal(opts.get("variant", i))
		"glow":
			return Palette.glow(1.8)
		"rock":
			var tone: String = opts.get("tone", "rocha")
			var c = {"rocha": Palette.ROCHA, "escura": Palette.ROCHA_ESCURA, "areia": Palette.AREIA, "ceramica": Palette.CERAMICA, "petroleo": Palette.PETROLEO}.get(tone, Palette.ROCHA)
			return Palette.mat(c)
		"ceramic":
			return Palette.mat(Palette.AREIA_CLARA if opts.get("tone", "") == "areia" else Palette.CERAMICA)
		"copper":
			return Palette.copper()
		"lever":
			if n.contains("dark"):
				return Palette.mat(Palette.ROCHA_ESCURA)
			if n.contains("lever"):
				return Palette.copper()
			return Palette.mat(Palette.PETROLEO)
		"coral":
			return Palette.mat(Palette.SAL if n.contains("wood") else Palette.COBRE)
		"flora":
			if n.contains("yellow"):
				return Palette.mat(Palette.COBRE)
			if n.contains("pink"):
				return Palette.mat(Palette.SAL)
			if n.contains("dark"):
				return Palette.mat(Color("#1F5D66"))
			return Palette.mat(Color("#2F8C8A") if i % 2 else Palette.PETROLEO)
		"city":
			# fachadas em cerâmica, telhados em petróleo, janelas acesas em cobre
			if n.contains("window") or n.contains("glass") or n.contains("light"):
				return Palette.mat(Palette.COBRE, {"emission": Palette.COBRE, "energy": 0.6})
			if n.contains("roof") or n.contains("dark") or n.contains("black"):
				return Palette.mat(Palette.PETROLEO)
			if n.contains("wood") or n.contains("door") or n.contains("brown"):
				return Palette.mat(Color("#8A5A3C"))
			if n.contains("stone") or n.contains("grey") or n.contains("gray") or n.contains("concrete"):
				return Palette.mat(Color("#B8A88A"))
			return Palette.mat(Palette.CERAMICA if i % 3 else Color("#D8C49A"))
		"lamp":
			if n.contains("light") or n.contains("bulb") or n.contains("emission") or n.contains("yellow") or n.contains("white"):
				return Palette.glow(2.2, Palette.COBRE)
			return Palette.mat(Palette.ROCHA_ESCURA)
		"metal":
			return Palette.mat(Color("#2C4E58"), {"metallic": 0.3, "roughness": 0.6})
		"tech":
			if n.contains("light") or n.contains("emission") or n.contains("glow") or n.contains("blue") or n.contains("screen"):
				return Palette.glow(1.6)
			if n.contains("gold") or n.contains("orange") or n.contains("yellow"):
				return Palette.copper()
			if n.contains("dark") or n.contains("black"):
				return Palette.mat(Palette.ROCHA_ESCURA)
			return Palette.mat(Palette.CERAMICA if i % 2 == 0 else Color("#C9B88F"))
		"wood":
			return Palette.mat(Color("#8A5A3C") if i % 2 == 0 else Color("#A87452"))
		"biolum":
			if n.contains("red") or n.contains("brown") or n.contains("cap") or i == 0:
				return Palette.mat(Color("#2A5F7A"), {"emission": Palette.RESSONANCIA, "energy": 0.5})
			return Palette.mat(Palette.CERAMICA, {"emission": Palette.RESSONANCIA, "energy": 0.15})
		"cloud":
			return Palette.mat(Color("#9CC3C9"), {"alpha": 0.55, "unshaded": false})
	return null

static func recolor(root: Node, mode: String, opts: Dictionary = {}) -> void:
	if mode == "keep":
		for n in root.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var i = 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi = n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src = mi.get_active_material(s)
			var m = _pick(mode, src.resource_name if src else "", i, opts)
			if m:
				mi.set_surface_override_material(s, m)
			i += 1
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
