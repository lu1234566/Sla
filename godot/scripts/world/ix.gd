extends RefCounted
## Interativos concretos. Uso: const IX := preload("res://scripts/world/ix.gd"); IX.TideNode.new(...)


## Nó de ressonância (simples ou duplo). Segurar a maré por 1 s alterna o(s) setor(es).
class TideNode extends Interactable:
	var sectors: Array
	var needs_scan = true
	var hold = TideSector.HoldConfirm.new()
	var inner: MeshInstance3D
	var inner2: MeshInstance3D
	var ring_mat: StandardMaterial3D
	var circle: MeshInstance3D

	func _init(id: String, sector_ids: Array, scan_required: bool = true) -> void:
		super(id)
		sectors = sector_ids
		needs_scan = scan_required
		action = "tide"
		radius = 2.4
		label_height = 2.3

	var dual: bool:
		get: return sectors.size() > 1

	func _ready() -> void:
		var ped = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.75
		cyl.bottom_radius = 0.95
		cyl.height = 0.45
		cyl.radial_segments = 8
		ped.mesh = cyl
		ped.material_override = Palette.mat(Palette.CERAMICA)
		ped.position.y = 0.22
		add_child(ped)
		var support = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.18, 0.7, 0.18)
		support.mesh = box
		support.material_override = Palette.copper()
		support.position.y = 0.8
		add_child(support)
		var outer = MeshInstance3D.new()
		outer.mesh = Interactable.ring_mesh(0.85, 0.16)
		outer.material_override = Palette.mat(Palette.COBRE if dual else Palette.CERAMICA)
		outer.position.y = 1.55
		outer.rotation.x = PI / 2
		add_child(outer)
		ring_mat = Interactable.glow_mat(Palette.RESSONANCIA, 0.8)
		inner = MeshInstance3D.new()
		inner.mesh = Interactable.ring_mesh(0.62, 0.05)
		inner.material_override = ring_mat
		inner.position.y = 1.55
		add_child(inner)
		if dual:
			inner2 = MeshInstance3D.new()
			inner2.mesh = Interactable.ring_mesh(0.45, 0.05)
			inner2.material_override = Interactable.glow_mat(Palette.COBRE, 1.0)
			inner2.position.y = 1.55
			add_child(inner2)
		var core = Props.make("crystal3", {"height": 0.55})
		core.position.y = 1.28
		add_child(core)
		circle = Interactable.floor_circle(2.25, Palette.COBRE if dual else Palette.RESSONANCIA)
		add_child(circle)
		var body = StaticBody3D.new()
		body.add_to_group("safe")
		var cs = CollisionShape3D.new()
		var sh = CylinderShape3D.new()
		sh.radius = 0.9
		sh.height = 0.5
		cs.shape = sh
		cs.position.y = 0.25
		body.add_child(cs)
		add_child(body)

	func is_scanned() -> bool:
		return not needs_scan or Game.flag(persist_key() + ".scan", false)

	func prompt(_ctx: Dictionary) -> Dictionary:
		if dual and not Game.has_ability("dual"):
			return {"text": I18n.t("refuse.need_dual"), "action": "tide", "disabled": true}
		if not is_scanned():
			return {"text": I18n.t("prompt.scan_first"), "action": "scan", "disabled": true}
		var reason: String = region.tide_refusal(sectors)
		if reason != "":
			return {"text": I18n.t("refuse." + reason), "action": "tide", "disabled": true}
		var txt = I18n.t("prompt.tide_dual", {"a": I18n.t("sector." + sectors[0]), "b": I18n.t("sector." + sectors[1])}) if dual else I18n.t("prompt.tide")
		return {"text": txt, "action": "tide", "hold": hold.ratio}

	func hold_update(dt: float, holding: bool) -> void:
		var p = prompt({})
		if p.get("disabled", false):
			hold.update(dt, false)
			return
		if hold.update(dt, holding):
			region.toggle_sectors(sectors)

	func on_scan(ctx: Dictionary) -> void:
		super(ctx)
		if not Game.flag(persist_key() + ".scan", false):
			Game.set_flag(persist_key() + ".scan")
			region.on_node_scanned(self)

	func scan_text() -> String:
		if dual:
			return "%s · %s + %s" % [I18n.t("scan.node_dual"), I18n.t("sector." + sectors[0]), I18n.t("sector." + sectors[1])]
		return "%s · %s" % [I18n.t("scan.node"), I18n.t("sector." + sectors[0])]

	func tick(dt: float, _ctx: Dictionary) -> void:
		var moving: bool = region.sectors_moving(sectors)
		inner.rotation.z += dt * (0.6 + (4.0 if moving else 0.0))
		inner.rotation.x = PI / 2 + sin(Time.get_ticks_msec() * 0.0008) * 0.2
		if inner2:
			inner2.rotation.z -= dt * (0.9 + (4.0 if moving else 0.0))
			inner2.rotation.x = PI / 2
		ring_mat.emission_energy_multiplier = 0.7 + hold.ratio * 2.5 + (1.5 if moving else 0.0)
		circle.scale = Vector3(1.0 - hold.ratio * 0.15, 0.05, 1.0 - hold.ratio * 0.15)


## Condutor giratório (junção de cobre). Cada E gira 90°.
class Conductor extends Interactable:
	var target_steps = 1
	var cond: Callable
	var on_change: Callable
	var rotor: Node3D
	var shape = "t"

	func _init(id: String, target: int, condition: Callable = Callable(), kind: String = "t") -> void:
		super(id)
		target_steps = target
		cond = condition
		shape = kind
		radius = 1.9
		scan_kind = "interact"
		label_height = 1.3

	var steps: int:
		get: return int(Game.flag(persist_key() + ".steps", 0))

	var aligned: bool:
		get: return steps == target_steps

	func _ready() -> void:
		var base = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.9
		cyl.bottom_radius = 1.05
		cyl.height = 0.3
		cyl.radial_segments = 8
		base.mesh = cyl
		base.material_override = Palette.mat(Palette.ROCHA_ESCURA)
		base.position.y = 0.15
		add_child(base)
		rotor = Node3D.new()
		rotor.position.y = 0.3
		add_child(rotor)
		var pipe = Props.make("pipe_t" if shape == "t" else "pipe_90", {"height": 0.8})
		pipe.rotation.x = PI / 2
		pipe.position = Vector3(0, 0.45, -0.1)
		rotor.add_child(pipe)
		var ring = MeshInstance3D.new()
		ring.mesh = Interactable.ring_mesh(0.75, 0.08)
		ring.material_override = Palette.copper()
		ring.position.y = 0.12
		rotor.add_child(ring)
		var arrow = MeshInstance3D.new()
		var pm = PrismMesh.new()
		pm.size = Vector3(0.4, 0.4, 0.08)
		arrow.mesh = pm
		arrow.material_override = Interactable.glow_mat(Palette.RESSONANCIA, 1.2)
		arrow.rotation.x = -PI / 2
		arrow.position = Vector3(0, 0.2, -0.75)
		rotor.add_child(arrow)
		var body = StaticBody3D.new()
		body.add_to_group("safe")
		var cs = CollisionShape3D.new()
		var sh = CylinderShape3D.new()
		sh.radius = 0.95
		sh.height = 0.3
		cs.shape = sh
		cs.position.y = 0.15
		body.add_child(cs)
		add_child(body)
		rotor.rotation.y = -steps * PI / 2

	func prompt(_ctx: Dictionary) -> Dictionary:
		if cond.is_valid() and not cond.call():
			return {"text": I18n.t("refuse.submerged"), "action": "interact", "disabled": true}
		return {"text": I18n.t("prompt.conductor"), "action": "interact"}

	func activate(_ctx: Dictionary) -> void:
		if cond.is_valid() and not cond.call():
			Sfx.play("fail")
			return
		Game.set_flag(persist_key() + ".steps", (steps + 1) % 4)
		Sfx.play("rotate")
		if on_change.is_valid():
			on_change.call(self)

	func scan_text() -> String:
		return I18n.t("scan.conductor_ok" if aligned else "scan.conductor")

	func tick(dt: float, _ctx: Dictionary) -> void:
		rotor.rotation.y = lerp_angle(rotor.rotation.y, -steps * PI / 2, 1.0 - exp(-4 * dt))


## Placa de circuito em que se pisa (ordem revelada por um pilar de leitura).
class Plate extends Interactable:
	var glyph = "▲"
	var cond: Callable
	var on_step: Callable
	var lit = false
	var glyph_label: Label3D
	var base_mat: StandardMaterial3D
	var _inside = false

	func _init(id: String, g: String, condition: Callable, stepped: Callable) -> void:
		super(id)
		glyph = g
		cond = condition
		on_step = stepped
		action = "touch"
		radius = 1.0
		label_height = 0.9

	func _ready() -> void:
		var disc = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.9
		cyl.bottom_radius = 0.95
		cyl.height = 0.06
		cyl.radial_segments = 8
		disc.mesh = cyl
		base_mat = Palette.unique(Palette.COBRE, {"metallic": 0.35, "roughness": 0.5})
		disc.material_override = base_mat
		disc.position.y = 0.03
		add_child(disc)
		glyph_label = Builder.glyph_label(self, glyph, Vector3(0, 0.08, 0), 140, Color("#2A4F57"))

	func prompt(_ctx: Dictionary) -> Dictionary:
		return {}

	func activate(_ctx: Dictionary) -> void:
		if lit or (cond.is_valid() and not cond.call()):
			return
		on_step.call(self)

	func set_lit(v: bool) -> void:
		lit = v
		glyph_label.modulate = Palette.RESSONANCIA if v else Color("#2A4F57")
		base_mat.emission_enabled = v
		base_mat.emission = Palette.RESSONANCIA
		base_mat.emission_energy_multiplier = 0.6

	func scan_text() -> String:
		if cond.is_valid() and not cond.call():
			return I18n.t("scan.plate_sub")
		return I18n.t("scan.plate", {"glyph": glyph})


## Pilão de relé: com o Relé remoto, escanear e enviar Lume liga o circuito à distância.
class RelayPylon extends Interactable:
	var on_active: Callable
	var reach = 26.0
	var crystal: MeshInstance3D
	var cmat: StandardMaterial3D

	func _init(id: String, activated: Callable = Callable()) -> void:
		super(id)
		on_active = activated
		action = "relay"
		radius = reach
		scan_kind = "interact"
		label_height = 3.0

	var active: bool:
		get: return Game.flag(persist_key() + ".on", false)

	func _ready() -> void:
		var v = Props.make("vessel_tall", {"height": 2.2})
		add_child(v)
		crystal = MeshInstance3D.new()
		var pm = PrismMesh.new()
		pm.size = Vector3(0.45, 0.8, 0.45)
		crystal.mesh = pm
		cmat = Interactable.glow_mat(Palette.COBRE, 0.4)
		crystal.material_override = cmat
		crystal.position.y = 2.7
		add_child(crystal)
		var body = StaticBody3D.new()
		var cs = CollisionShape3D.new()
		var sh = CylinderShape3D.new()
		sh.radius = 0.55
		sh.height = 2.2
		cs.shape = sh
		cs.position.y = 1.1
		body.add_child(cs)
		add_child(body)
		_refresh()

	func in_range(p: Vector3) -> bool:
		return enabled and not active and p.distance_to(global_position) < reach

	func prompt(_ctx: Dictionary) -> Dictionary:
		if active:
			return {}
		if not Game.has_ability("relay"):
			if global_position.distance_to(_ctx["player_pos"]) < 4.0:
				return {"text": I18n.t("refuse.need_relay"), "action": "interact", "disabled": true}
			return {}
		if not scanned and not Game.flag(persist_key() + ".scan", false):
			return {"text": I18n.t("prompt.scan_first"), "action": "scan", "disabled": true}
		return {"text": I18n.t("prompt.relay"), "action": "interact"}

	func on_scan(ctx: Dictionary) -> void:
		super(ctx)
		Game.set_flag(persist_key() + ".scan")

	func activate(ctx: Dictionary) -> void:
		ctx["main"].send_lume(crystal.global_position + Vector3(0, 0.6, 0.6), func(): set_active())

	func set_active() -> void:
		if active:
			return
		Game.set_flag(persist_key() + ".on")
		Sfx.play("relay")
		_refresh()
		if on_active.is_valid():
			on_active.call(self)

	func _refresh() -> void:
		cmat.emission = Palette.RESSONANCIA if active else Palette.COBRE
		cmat.albedo_color = cmat.emission
		cmat.emission_energy_multiplier = 2.0 if active else 0.4

	func scan_text() -> String:
		return I18n.t("scan.relay_on" if active else "scan.relay")

	func tick(dt: float, _ctx: Dictionary) -> void:
		crystal.rotation.y += dt * (1.5 if active else 0.3)


## Eco colecionável (18 no total). Coleta ao tocar.
class Echo extends Interactable:
	var cond: Callable
	var holder: Node3D
	var light: OmniLight3D

	func _init(id: String, condition: Callable = Callable()) -> void:
		super(id)
		cond = condition
		action = "touch"
		radius = 1.5
		label_height = 1.2

	func _ready() -> void:
		holder = Props.make("gem_pink", {"height": 0.7})
		add_child(holder)
		light = OmniLight3D.new()
		light.light_color = Palette.RESSONANCIA
		light.omni_range = 5.0
		light.light_energy = 1.4
		light.position.y = 0.4
		add_child(light)

	var collected: bool:
		get: return Game.has_echo(uid)

	func in_range(p: Vector3) -> bool:
		return not collected and (not cond.is_valid() or cond.call()) and p.distance_to(global_position + Vector3(0, 0.3, 0)) < radius + 0.3

	func activate(ctx: Dictionary) -> void:
		if collected:
			return
		Game.add_echo(uid)
		ctx["main"].on_echo(uid)

	func scan_text() -> String:
		return I18n.t("scan.echo")

	func tick(_dt: float, _ctx: Dictionary) -> void:
		var show = not collected and (not cond.is_valid() or cond.call())
		visible = show
		enabled = show
		if show:
			holder.rotation.y += _dt * 1.2
			holder.position.y = sin(Time.get_ticks_msec() * 0.002 + global_position.x) * 0.12


## Alavanca (Quaternius, com animação Off/On).
class Lever extends Interactable:
	var on_pull: Callable
	var model: Node3D

	func _init(id: String, pulled: Callable) -> void:
		super(id)
		on_pull = pulled
		radius = 1.8
		scan_kind = "interact"
		label_height = 1.3

	var pulled: bool:
		get: return Game.flag(persist_key() + ".pulled", false)

	func _ready() -> void:
		model = Props.make("lever", {"height": 0.9, "anim": "Lever_On" if pulled else ""})
		add_child(model)

	func prompt(_ctx: Dictionary) -> Dictionary:
		return {} if pulled else {"text": I18n.t("prompt.lever"), "action": "interact"}

	func activate(_ctx: Dictionary) -> void:
		if pulled:
			return
		Game.set_flag(persist_key() + ".pulled")
		Sfx.play("lever")
		var ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			for a in ap.get_animation_list():
				if a.ends_with("Lever_On"):
					ap.play(a)
					break
		if on_pull.is_valid():
			on_pull.call(self)

	func scan_text() -> String:
		return I18n.t("scan.lever")


## Módulo de habilidade num pedestal (Asa de Vidro, Relé remoto, Ressonância dupla).
class Pedestal extends Interactable:
	var ability = "glide"
	var gem: Node3D
	var terminal = false

	func _init(id: String, ab: String, as_terminal: bool = false) -> void:
		super(id)
		ability = ab
		terminal = as_terminal
		radius = 2.0
		label_height = 2.0

	func _ready() -> void:
		if terminal:
			add_child(Props.make("pod", {"height": 2.0}))
		else:
			add_child(Props.make("pedestal", {"height": 1.0}))
		gem = Props.make("gem_blue", {"height": 0.6})
		gem.position.y = 2.2 if terminal else 1.25
		add_child(gem)
		var body = StaticBody3D.new()
		var cs = CollisionShape3D.new()
		var sh = CylinderShape3D.new()
		sh.radius = 0.55
		sh.height = 1.0
		cs.shape = sh
		cs.position.y = 0.5
		body.add_child(cs)
		add_child(body)

	func prompt(_ctx: Dictionary) -> Dictionary:
		if Game.has_ability(ability):
			return {}
		return {"text": I18n.t("prompt.terminal" if terminal else "prompt.pedestal"), "action": "interact"}

	func activate(ctx: Dictionary) -> void:
		if Game.has_ability(ability):
			return
		Game.grant_ability(ability)
		ctx["main"].on_ability(ability)

	func scan_text() -> String:
		return I18n.t("scan.terminal" if terminal else "scan.pedestal")

	func tick(dt: float, _ctx: Dictionary) -> void:
		gem.visible = not Game.has_ability(ability)
		gem.rotation.y += dt


## Portal de travessia entre o Farol e as regiões.
class Portal extends Interactable:
	var dest = "jardim"
	var spawn = "portal"
	var unlocked: Callable
	var core: MeshInstance3D
	var cmat: StandardMaterial3D

	func _init(id: String, destination: String, dest_spawn: String, is_open: Callable) -> void:
		super(id)
		dest = destination
		spawn = dest_spawn
		unlocked = is_open
		radius = 2.4
		label_height = 3.2

	func _ready() -> void:
		add_child(Props.make("teleporter1", {"height": 1.6}))
		core = MeshInstance3D.new()
		var ring = Interactable.ring_mesh(1.25, 0.12)
		core.mesh = ring
		cmat = Interactable.glow_mat(Palette.RESSONANCIA, 0.3)
		core.material_override = cmat
		core.position.y = 2.6
		add_child(core)
		var disc = MeshInstance3D.new()
		var q = CylinderMesh.new()
		q.top_radius = 1.1
		q.bottom_radius = 1.1
		q.height = 0.02
		disc.mesh = q
		disc.rotation.x = PI / 2
		disc.position.y = 2.6
		var dm = StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.albedo_color = Color(Palette.RESSONANCIA, 0.25)
		dm.cull_mode = BaseMaterial3D.CULL_DISABLED
		disc.material_override = dm
		disc.name = "Disc"
		add_child(disc)
		var body = StaticBody3D.new()
		body.add_to_group("safe")
		var cs = CollisionShape3D.new()
		var sh = CylinderShape3D.new()
		sh.radius = 1.2
		sh.height = 0.5
		cs.shape = sh
		cs.position.y = 0.25
		body.add_child(cs)
		add_child(body)

	var is_open: bool:
		get: return unlocked.call() if unlocked.is_valid() else true

	func prompt(_ctx: Dictionary) -> Dictionary:
		if not is_open:
			return {"text": I18n.t("prompt.portal_locked"), "action": "interact", "disabled": true}
		return {"text": I18n.t("prompt.portal", {"dest": I18n.t("region." + dest)}), "action": "interact"}

	func activate(ctx: Dictionary) -> void:
		if is_open:
			Sfx.play("portal")
			ctx["main"].request_travel(dest, spawn)

	func scan_text() -> String:
		return I18n.t("scan.portal", {"dest": I18n.t("region." + dest)})

	func tick(dt: float, _ctx: Dictionary) -> void:
		var open = is_open
		cmat.emission_energy_multiplier = (1.6 + sin(Time.get_ticks_msec() * 0.003) * 0.4) if open else 0.2
		core.rotation.z += dt * (1.0 if open else 0.1)
		(get_node("Disc") as MeshInstance3D).visible = open


## Oficina do Farol (abre o menu de melhorias).
class Workshop extends Interactable:
	func _init(id: String) -> void:
		super(id)
		radius = 2.4
		label_height = 2.0

	func prompt(_ctx: Dictionary) -> Dictionary:
		return {"text": I18n.t("prompt.workshop"), "action": "interact"}

	func activate(ctx: Dictionary) -> void:
		ctx["main"].open_workshop()

	func scan_text() -> String:
		return I18n.t("scan.workshop")


## Conduto que só pode ser aceso sob uma condição (ex.: maré baixa).
class Conduit extends Interactable:
	var cond: Callable
	var on_lit: Callable
	var cmat: StandardMaterial3D

	func _init(id: String, condition: Callable, lit_cb: Callable) -> void:
		super(id)
		cond = condition
		on_lit = lit_cb
		radius = 1.8
		scan_kind = "interact"
		label_height = 1.6

	var lit: bool:
		get: return Game.flag(persist_key() + ".lit", false)

	func _ready() -> void:
		add_child(Props.make("vessel_short", {"height": 1.1}))
		var orb = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		orb.mesh = sm
		cmat = Interactable.glow_mat(Palette.COBRE, 0.3)
		orb.material_override = cmat
		orb.position.y = 1.35
		add_child(orb)

	func prompt(_ctx: Dictionary) -> Dictionary:
		if lit:
			return {}
		if cond.is_valid() and not cond.call():
			return {"text": I18n.t("refuse.not_now"), "action": "interact", "disabled": true}
		return {"text": I18n.t("prompt.conduit"), "action": "interact"}

	func activate(_ctx: Dictionary) -> void:
		if lit or (cond.is_valid() and not cond.call()):
			return
		Game.set_flag(persist_key() + ".lit")
		Sfx.play("activate")
		if on_lit.is_valid():
			on_lit.call(self)

	func scan_text() -> String:
		return I18n.t("scan.conduit")

	func tick(_dt: float, _ctx: Dictionary) -> void:
		cmat.emission = Palette.RESSONANCIA if lit else Palette.COBRE
		cmat.emission_energy_multiplier = 2.2 if lit else 0.3


## Pilar de leitura: só escaneável; revela uma informação (ordem, padrão).
class ReadingPillar extends Interactable:
	var text_key = "scan.pillar"
	var params = {}
	var on_read: Callable

	func _init(id: String, key: String, p: Dictionary, read_cb: Callable = Callable()) -> void:
		super(id)
		text_key = key
		params = p
		on_read = read_cb
		action = "scan"
		radius = 6.0
		label_height = 2.8

	func _ready() -> void:
		add_child(Props.make("column_broken2", {"height": 2.4}))
		var body = StaticBody3D.new()
		var cs = CollisionShape3D.new()
		var sh = CylinderShape3D.new()
		sh.radius = 0.6
		sh.height = 2.4
		cs.shape = sh
		cs.position.y = 1.2
		body.add_child(cs)
		add_child(body)

	func on_scan(ctx: Dictionary) -> void:
		super(ctx)
		if not Game.flag(persist_key() + ".read", false):
			Game.set_flag(persist_key() + ".read")
			if on_read.is_valid():
				on_read.call(self)

	var read: bool:
		get: return Game.flag(persist_key() + ".read", false)

	func scan_text() -> String:
		return I18n.t(text_key, params)


## Ponto de interação genérico com callbacks (santuário, coração, escolhas).
class Action extends Interactable:
	var prompt_fn: Callable  # (ctx) -> Dictionary
	var act_fn: Callable  # (ctx) -> void
	var scan_key = ""

	func _init(id: String, p_fn: Callable, a_fn: Callable, r: float = 2.4, scan: String = "") -> void:
		super(id)
		prompt_fn = p_fn
		act_fn = a_fn
		radius = r
		scan_key = scan

	func prompt(ctx: Dictionary) -> Dictionary:
		return prompt_fn.call(ctx)

	func activate(ctx: Dictionary) -> void:
		act_fn.call(ctx)

	func scan_text() -> String:
		return I18n.t(scan_key) if scan_key != "" else ""
