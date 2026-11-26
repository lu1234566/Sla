# Prancha de modelos: godot --path godot res://tools/contact_sheet.tscn -- <saida.png> <glob1> [glob2...]
extends Node3D

func _ready() -> void:
	var args = OS.get_cmdline_user_args()
	var out = args[0]
	var files: Array[String] = []
	for pattern in args.slice(1):
		var dir = pattern.get_base_dir()
		var mask = pattern.get_file()
		for f in DirAccess.get_files_at(dir):
			if f.matchn(mask) and f.ends_with(".glb"):
				files.append(dir.path_join(f))
	var cols = 6
	var cell = 3.2
	var i = 0
	for f in files:
		var ps: PackedScene = load(f)
		var n: Node3D = ps.instantiate()
		add_child(n)
		var aabb = _aabb(n)
		var s = 1.8 / maxf(0.001, maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)))
		n.scale = Vector3.ONE * s
		var cx = (i % cols) * cell
		var cz = (i / cols) * cell * 1.15
		n.position = Vector3(cx, 0, cz) - (aabb.get_center() * s) + Vector3(0, aabb.size.y * s * 0.5, 0)
		var lb = Label3D.new()
		lb.text = f.get_file().get_basename()
		lb.font_size = 40
		lb.pixel_size = 0.004
		lb.position = Vector3(cx, -0.25, cz + 1.0)
		lb.rotation_degrees = Vector3(-60, 0, 0)
		add_child(lb)
		i += 1
	var rows = int(ceil(float(i) / cols))
	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(rows * cell * 1.15, cols * cell * 0.5625) + 1.0
	add_child(cam)
	var center = Vector3((cols - 1) * cell * 0.5, 0, (rows - 1) * cell * 1.15 * 0.5)
	cam.position = center + Vector3(0, 30, 20)
	cam.look_at(center)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	add_child(sun)
	var we = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1b3442")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9fc6d0")
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)
	for _f in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("prancha: ", i, " modelos -> ", out)
	get_tree().quit()

func _aabb(n: Node) -> AABB:
	var box = AABB()
	var first = true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi = m as MeshInstance3D
		var b: AABB = (mi.global_transform if mi.is_inside_tree() else Transform3D.IDENTITY) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
