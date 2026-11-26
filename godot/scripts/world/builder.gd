class_name Builder
## Construção procedural de geometria low-poly (ilhas facetadas, lajes,
## rampas, água) com colisão. Polígonos são PackedVector2Array em (x, z).

const WATER_SHADER := preload("res://assets/shaders/water.gdshader")

# --- polígonos ---------------------------------------------------------------------

static func octagon(r: float, cx: float = 0.0, cz: float = 0.0) -> PackedVector2Array:
	return ngon(r, 8, cx, cz, PI / 8.0)

static func ngon(r: float, n: int, cx: float = 0.0, cz: float = 0.0, rot: float = 0.0) -> PackedVector2Array:
	var out = PackedVector2Array()
	for i in n:
		var a = rot + TAU * i / n
		out.append(Vector2(cx + cos(a) * r, cz + sin(a) * r))
	return out

static func rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])

static func rect_c(cx: float, cz: float, w: float, d: float, rot: float = 0.0) -> PackedVector2Array:
	var out = PackedVector2Array()
	for p in [Vector2(-w, -d), Vector2(w, -d), Vector2(w, d), Vector2(-w, d)]:
		out.append(Vector2(cx, cz) + (p * 0.5).rotated(rot))
	return out

## Sutherland–Hodgman: mantém a parte com dot(n, p) <= d.
static func clip(poly: PackedVector2Array, n: Vector2, d: float) -> PackedVector2Array:
	var out = PackedVector2Array()
	for i in poly.size():
		var a = poly[i]
		var b = poly[(i + 1) % poly.size()]
		var da = n.dot(a) - d
		var db = n.dot(b) - d
		if da <= 0.0:
			out.append(a)
		if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out

## Polígono convexo menos um retângulo -> peças convexas.
static func minus_rect(poly: PackedVector2Array, x0: float, z0: float, x1: float, z1: float) -> Array:
	var pieces = []
	pieces.append(clip(poly, Vector2(0, 1), z0))
	pieces.append(clip(poly, Vector2(0, -1), -z1))
	var mid = clip(clip(poly, Vector2(0, -1), -z0), Vector2(0, 1), z1)
	pieces.append(clip(mid, Vector2(1, 0), x0))
	pieces.append(clip(mid, Vector2(-1, 0), -x1))
	return pieces.filter(func(p): return p.size() >= 3)

## Anel entre dois polígonos com mesma contagem/orientação.
static func ring(outer: PackedVector2Array, inner: PackedVector2Array) -> Array:
	var out = []
	for i in outer.size():
		var j = (i + 1) % outer.size()
		out.append(PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]))
	return out

static func inside(poly: PackedVector2Array, p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly)

static func centroid(poly: PackedVector2Array) -> Vector2:
	var c = Vector2.ZERO
	for p in poly:
		c += p
	return c / poly.size()

# --- malhas -----------------------------------------------------------------------

## Adiciona um triângulo com a face voltada para n (o Godot usa ordem
## horária como frente: o produto vetorial fica oposto à normal desejada).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp = b
		b = c
		c = tmp
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x, v.z) * 0.25)
		st.add_vertex(v)

## Prisma vertical: tampa superior (top_mat) + lados (side_mat), faces planas.
static func prism_mesh(poly: PackedVector2Array, y_top: float, y_bottom: float, top_mat: Material, side_mat: Material, bottom: bool = false) -> ArrayMesh:
	var pts = poly
	var c2 = centroid(pts)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri = Geometry2D.triangulate_polygon(pts)
	for i in range(0, tri.size(), 3):
		var a: Vector2 = pts[tri[i]]
		var b: Vector2 = pts[tri[i + 1]]
		var c: Vector2 = pts[tri[i + 2]]
		_tri(st, Vector3(a.x, y_top, a.y), Vector3(b.x, y_top, b.y), Vector3(c.x, y_top, c.y), Vector3.UP)
		if bottom:
			_tri(st, Vector3(a.x, y_bottom, a.y), Vector3(b.x, y_bottom, b.y), Vector3(c.x, y_bottom, c.y), Vector3.DOWN)
	var mesh = st.commit()
	mesh.surface_set_material(0, top_mat)
	var st2 = SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var mid = (a + b) * 0.5
		var n2 = Vector2(b.y - a.y, -(b.x - a.x)).normalized()
		if n2.dot(mid - c2) < 0.0:
			n2 = -n2
		var n = Vector3(n2.x, 0, n2.y)
		var v0 = Vector3(a.x, y_top, a.y)
		var v1 = Vector3(b.x, y_top, b.y)
		var v2 = Vector3(b.x, y_bottom, b.y)
		var v3 = Vector3(a.x, y_bottom, a.y)
		_tri(st2, v0, v1, v2, n)
		_tri(st2, v0, v2, v3, n)
	st2.commit(mesh)
	mesh.surface_set_material(1, side_mat)
	return mesh

## Raiz rochosa invertida, facetada, sob uma ilha.
static func root_mesh(radius: float, depth: float, sides: int, seed: int, mat: Material) -> ArrayMesh:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed
	var rings = 3
	var verts = []
	for r in rings + 1:
		var t = float(r) / rings
		var row = []
		for i in sides:
			var a = TAU * i / sides + PI / sides
			var rr = radius * (1.0 - t) * (0.85 + rng.randf() * 0.3) if r < rings else 0.0
			var jit = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * radius * 0.08 * (1.0 - t)
			var yj = rng.randf_range(-0.1, 0.1) * depth if (r > 0 and r < rings) else 0.0
			row.append(Vector3(cos(a) * rr, -depth * t + yj, sin(a) * rr) + jit)
		verts.append(row)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings:
		for i in sides:
			var j = (i + 1) % sides
			var a: Vector3 = verts[r][i]
			var b: Vector3 = verts[r][j]
			var c: Vector3 = verts[r + 1][j]
			var d: Vector3 = verts[r + 1][i]
			for tri in [[a, b, c], [a, c, d]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				var center: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				if n.dot(Vector3(center.x, 0.0, center.z)) < 0.0:
					n = -n
				_tri(st, tri[0], tri[1], tri[2], n)
	var m = st.commit()
	m.surface_set_material(0, mat)
	return m

# --- nós com colisão --------------------------------------------------------------

## Laje/prisma com colisão (ConvexPolygonShape3D). Devolve o StaticBody3D.
static func slab(parent: Node3D, poly: PackedVector2Array, y_top: float, y_bottom: float, top_mat: Material, side_mat: Material, groups: Array = ["safe"], visible: bool = true) -> StaticBody3D:
	var c = centroid(poly)
	var local = PackedVector2Array()
	for p in poly:
		local.append(p - c)
	var body = StaticBody3D.new()
	body.position = Vector3(c.x, 0, c.y)
	for g in groups:
		body.add_to_group(g)
	if visible:
		var mi = MeshInstance3D.new()
		mi.mesh = prism_mesh(local, y_top, y_bottom, top_mat, side_mat)
		body.add_child(mi)
	var shape = ConvexPolygonShape3D.new()
	var pts = PackedVector3Array()
	for p in local:
		pts.append(Vector3(p.x, y_top, p.y))
		pts.append(Vector3(p.x, y_bottom, p.y))
	shape.points = pts
	var cs = CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body

## Ilha flutuante: peças convexas (colisão) + raiz rochosa.
static func island(parent: Node3D, outline: PackedVector2Array, pieces: Array, top: float, thickness: float, seed: int, mats: Dictionary = {}) -> Node3D:
	var node = Node3D.new()
	parent.add_child(node)
	var top_mat: Material = mats.get("top", Palette.mat(Palette.AREIA))
	var side_mat: Material = mats.get("side", Palette.mat(Palette.ROCHA))
	for piece in pieces:
		slab(node, piece, top, top - thickness, top_mat, side_mat, mats.get("groups", ["safe"]))
	var c = centroid(outline)
	var r = 0.0
	for p in outline:
		r = maxf(r, p.distance_to(c))
	var mi = MeshInstance3D.new()
	mi.mesh = root_mesh(r * 0.96, mats.get("root_depth", r * 1.0), maxi(7, outline.size()), seed, mats.get("root", Palette.mat(Palette.ROCHA_ESCURA)))
	mi.position = Vector3(c.x, top - thickness + 0.02, c.y)
	node.add_child(mi)
	return node

## Rampa invisível (colisão) para escadas: de a até b (Vector3 nos pés), largura w.
static func ramp(parent: Node3D, a: Vector3, b: Vector3, w: float, groups: Array = ["safe"]) -> StaticBody3D:
	var body = StaticBody3D.new()
	for g in groups:
		body.add_to_group(g)
	parent.add_child(body)
	var hi = a if a.y >= b.y else b
	var lo = b if a.y >= b.y else a
	# 6 cm acima do piso de cima: a quina do piso fica sob a rampa (sem
	# beirada que trave a cápsula); o degrau de 6 cm é vencido sem salto
	hi += Vector3(0, 0.06, 0)
	var d = hi - lo
	var flat = Vector3(d.x, 0, d.z)
	if d.length() < 0.01 or flat.length() < 0.01:
		return body
	# a ponta de baixo entra no piso inferior (sem degrau ao subir) ...
	var lo2 = lo - d.normalized() * 0.45
	var box = BoxShape3D.new()
	box.size = Vector3(w, 0.2, (hi - lo2).length())
	var cs = CollisionShape3D.new()
	cs.shape = box
	body.add_child(cs)
	cs.global_transform = Transform3D(Basis.looking_at((hi - lo2).normalized(), Vector3.UP), (hi + lo2) * 0.5 - Vector3(0, 0.1, 0))
	# ... e um patamar plano no topo cobre a emenda com o piso de cima
	var land = BoxShape3D.new()
	land.size = Vector3(w, 0.2, 0.9)
	var cs2 = CollisionShape3D.new()
	cs2.shape = land
	body.add_child(cs2)
	cs2.global_transform = Transform3D(Basis.looking_at(flat.normalized(), Vector3.UP), hi + flat.normalized() * 0.47 - Vector3(0, 0.1, 0))
	return body

## Escada visual (degraus) + rampa de colisão.
static func stairs(parent: Node3D, a: Vector3, b: Vector3, w: float, steps: int, mat_top: Material, mat_side: Material) -> void:
	var d = b - a
	var flat = Vector2(d.x, d.z)
	var dir = flat.normalized()
	var side = Vector2(-dir.y, dir.x)
	var step_len = flat.length() / steps
	for i in steps:
		var t0 = float(i) / steps
		var h = a.y + d.y * (i + 1) / steps
		var p0 = Vector2(a.x, a.z) + flat * t0
		var p1 = p0 + dir * step_len
		var poly = PackedVector2Array([p0 - side * w / 2, p1 - side * w / 2, p1 + side * w / 2, p0 + side * w / 2])
		var holder = Node3D.new()
		parent.add_child(holder)
		var mi = MeshInstance3D.new()
		mi.mesh = prism_mesh(poly, h, minf(a.y, b.y) - 0.6, mat_top, mat_side)
		holder.add_child(mi)
	ramp(parent, a, b, w)

## Superfície de água luminosa sobre um polígono.
static func water(parent: Node3D, poly: PackedVector2Array, y: float, params: Dictionary = {}) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var c = centroid(poly)
	var local = PackedVector2Array()
	for p in poly:
		local.append(p - c)
	var mesh = prism_mesh(local, 0.0, -0.01, water_material(params), water_material(params))
	mi.mesh = mesh
	mi.position = Vector3(c.x, y, c.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func water_material(params: Dictionary = {}) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = WATER_SHADER
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

## Prop do catálogo posicionado.
static func prop(parent: Node3D, name: String, pos: Vector3, opts: Dictionary = {}) -> Node3D:
	var p = Props.make(name, opts)
	p.position = pos
	p.rotation.y = opts.get("rot", 0.0)
	parent.add_child(p)
	if opts.has("collide"):
		var size: Vector3 = p.get_meta("size")
		var body = StaticBody3D.new()
		var shape = CylinderShape3D.new()
		shape.radius = float(opts["collide"]) if typeof(opts["collide"]) == TYPE_FLOAT else maxf(size.x, size.z) * 0.42
		shape.height = size.y
		var cs = CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = size.y * 0.5
		body.add_child(cs)
		if opts.get("cover", false):
			body.add_to_group("cover")
		p.add_child(body)
	return p

## Rótulo 3D simples (placas, glifos).
static func glyph_label(parent: Node3D, text: String, pos: Vector3, size: int = 96, color: Color = Palette.RESSONANCIA) -> Label3D:
	var l = Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.rotation_degrees = Vector3(-90, 0, 0)
	parent.add_child(l)
	return l
