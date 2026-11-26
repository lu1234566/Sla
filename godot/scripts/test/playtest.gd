class_name Playtest
extends Node
## Teste de jogabilidade com física real (--playtest[=velocidade]).
## Um piloto automático joga a campanha inteira como um jogador: anda, salta,
## plana, escaneia, segura a maré, envia Lume aos pilões, puxa alavancas, gira
## condutores, pisa nas placas, usa elevadores e portais, coleta os 18 ecos,
## instala melhorias e escolhe um final. Nada é teleportado entre trechos.
## Exceções explícitas: os guardiões ficam "cegos" depois de um teste de visão
## (furtividade por roteiro seria frágil) e a escolha final chama o mesmo
## callable do botão do menu.

var main
var speed = 3.0
var fails: Array = []
var lines: Array = []
var sec_name = ""
var sec_t0 = 0
var t0 = 0
var falls0 = 0

func _init(m, spd: float = 3.0) -> void:
	main = m
	speed = spd
	process_mode = Node.PROCESS_MODE_ALWAYS

# --- infraestrutura -------------------------------------------------------------

func dt_sim() -> float:
	return 1.0 / 60.0

func region():
	return main.region

func pos() -> Vector3:
	return main.player.global_position

func ix(uid: String):
	for i in region().interactables:
		if i.uid == uid:
			return i
	push_error("interativo não encontrado: " + uid)
	return null

func frame() -> void:
	await get_tree().physics_frame

func wait(sec: float) -> void:
	var n = int(ceil(sec / dt_sim()))
	for i in n:
		await frame()

func until(cond: Callable, timeout: float) -> bool:
	var t = 0.0
	while t < timeout:
		if cond.call():
			return true
		await frame()
		t += dt_sim()
	return cond.call()

func say(msg: String) -> void:
	var line = "PLAYTEST  %7.1fs  [%s] %s" % [(Time.get_ticks_msec() - t0) / 1000.0, sec_name, msg]
	print(line)
	lines.append(line)

func fail(msg: String) -> bool:
	say("FALHA: " + msg + "  (pos %s)" % str(pos().snapped(Vector3.ONE * 0.1)))
	fails.append("%s: %s" % [sec_name, msg])
	return false

func check(cond: bool, msg: String) -> bool:
	if not cond:
		return fail(msg)
	return true

func stop() -> void:
	main.player.autopilot = {"move": Vector2.ZERO, "jump_pressed": false, "jump_held": false, "dodge_pressed": false}

var cam_s = PI

## A câmera gira suavemente atrás de Íris; o movimento é convertido para o
## referencial dela (como um controle analógico), então a direção é exata.
func _steer(dir2: Vector2, mag: float, jp: bool, jh: bool) -> void:
	var desired = atan2(-dir2.x, -dir2.y)
	cam_s = lerp_angle(cam_s, desired, 1.0 - exp(-2.8 * dt_sim()))
	main.autopilot_keys["cam_yaw"] = cam_s
	main.player.cam_yaw = cam_s
	var fwd = Vector2(-sin(cam_s), -cos(cam_s))
	var right = Vector2(cos(cam_s), -sin(cam_s))
	var mv = Vector2(dir2.dot(right), -dir2.dot(fwd)) * mag
	main.player.autopilot = {"move": mv, "jump_pressed": jp, "jump_held": jh, "dodge_pressed": false}

## Precisa saltar? 0 = não, 1 = degrau alcançável à frente, 2 = beirada sem chão
## a `look` metros.
func _need_jump(p: Vector3, dir: Vector2, look: float = 0.6) -> int:
	var space = main.get_world_3d().direct_space_state
	var f = Vector3(dir.x, 0, dir.y)
	var ex = [main.player.get_rid()]
	var h = {}
	for hy in [0.22, 0.38, 0.55]:
		var q = PhysicsRayQueryParameters3D.create(p + Vector3(0, hy, 0), p + Vector3(0, hy, 0) + f * 0.75, 1, ex)
		h = space.intersect_ray(q)
		if not h.is_empty() and (h["normal"] as Vector3).y < 0.6:
			break
	if not h.is_empty() and (h["normal"] as Vector3).y < 0.6:
		var q2 = PhysicsRayQueryParameters3D.create(p + f * 1.0 + Vector3(0, 1.3, 0), p + f * 1.0 + Vector3(0, 0.25, 0), 1, ex)
		return 1 if not space.intersect_ray(q2).is_empty() else 0
	var q3 = PhysicsRayQueryParameters3D.create(p + f * look + Vector3(0, 0.9, 0), p + f * look + Vector3(0, -1.4, 0), 1, ex)
	return 2 if space.intersect_ray(q3).is_empty() else 0

func _await_respawn() -> void:
	if main.respawning:
		say("respawn em %s" % str(pos().snapped(Vector3.ONE * 0.1)))
		stop()
		await until(func(): return not main.respawning, 6.0)
		await wait(0.2)

## Vai até cada ponto. opts: jump ("auto"|"none"), glide (bool), tol, ytol, extra.
func go(points: Array, opts: Dictionary = {}) -> bool:
	for i in points.size():
		var p: Vector3 = points[i]
		if not await _leg(p, opts, i == points.size() - 1):
			stop()
			return fail("não alcançou %s" % str(p))
	stop()
	await wait(0.12)
	return true

func _leg(target: Vector3, opts: Dictionary, last: bool = true) -> bool:
	var tol = opts.get("tol", 0.45) if last else maxf(opts.get("tol", 0.45), 0.6)
	var ytol = opts.get("ytol", 1.0)
	var jump_mode = opts.get("jump", "auto")
	var glide = opts.get("glide", false)
	var start = pos()
	var limit = Vector2(target.x - start.x, target.z - start.z).length() / 2.2 + opts.get("extra", 6.0)
	var t = 0.0
	var holding = false
	var stuck = 0.0
	while t < limit:
		await _await_respawn()
		var p = pos()
		var d = Vector2(target.x - p.x, target.z - p.z)
		var on_floor = main.player.is_on_floor()
		if d.length() < tol and on_floor and absf(p.y - target.y) < ytol:
			return true
		var jp = false
		var grounded = on_floor or (main.player.coyote > 0.0 and main.player.velocity.y <= 0.0)
		if on_floor:
			holding = false
		if grounded and not holding and jump_mode == "auto" and d.length() > 0.6:
			var dn = d.normalized()
			var need = _need_jump(p, dn)
			var hv = Vector2(main.player.velocity.x, main.player.velocity.z).dot(dn)
			# como um jogador: na beirada, salta embalado (ou no último instante);
			# travado contra algo baixo, tenta um salto
			stuck = stuck + dt_sim() if (on_floor and hv < 0.6) else 0.0
			if need == 1 or stuck > 0.35 or (need == 2 and (hv > 3.6 or _need_jump(p, dn, 0.28) == 2 or not on_floor)):
				jp = true
				holding = true
				stuck = 0.0
		elif holding and not glide and not on_floor and main.player.velocity.y < 0.6:
			holding = false
		var mag = clampf(d.length() / 0.9, 0.3, 1.0) if (on_floor and last) else 1.0
		_steer(d.normalized() if d.length() > 0.01 else Vector2(0, -1), mag, jp, holding or jp)
		if opts.get("trace", false) and int(t * 60.0) % 4 == 0:
			var v: Vector3 = main.player.velocity
			print("TRACE t=%.2f p=%s v=(%.1f,%.1f,%.1f) floor=%s jp=%s hold=%s coy=%.2f" % [t, str(p.snapped(Vector3.ONE * 0.01)), v.x, v.y, v.z, on_floor, jp, holding, main.player.coyote])
		await frame()
		t += dt_sim()
	return false

## Anda numa direção até cair (para sair de rochas sem retorno).
func walk_off(dir: Vector2) -> bool:
	var t = 0.0
	while t < 6.0 and not main.respawning:
		_steer(dir.normalized(), 1.0, false, false)
		await frame()
		t += dt_sim()
	stop()
	await _await_respawn()
	return true

func press(action: String) -> void:
	main.autopilot_keys[action + "_pressed"] = true
	await wait(0.1)

func interact(times: int = 1) -> void:
	for i in times:
		await until(func(): return main.busy <= 0.0 and not main.respawning and main.player.locked <= 0.0, 10.0)
		await press("interact")
		await wait(0.5)

func scan() -> void:
	await until(func(): return main.scan_cd <= 0.0, 3.0)
	await press("scan")
	await wait(0.3)

## Segura a maré no nó mais próximo e espera os setores mudarem.
func tide(sids: Array) -> bool:
	var r = region()
	var before = r.high(sids[0])
	await until(func(): return r.tide_refusal(sids) == "", 9.0)
	main.autopilot_keys["tide"] = true
	var ok = await until(func(): return r.high(sids[0]) != before, 3.0)
	main.autopilot_keys["tide"] = false
	if not ok:
		return fail("maré %s não mudou (recusa: '%s')" % [str(sids), r.tide_refusal(sids)])
	await until(func(): return not r.sectors_moving(sids), 4.0)
	await wait(0.3)
	say("maré %s → %s" % [str(sids), "alta" if r.high(sids[0]) else "baixa"])
	return true

func relay(uid: String) -> bool:
	var py = ix(uid)
	if py.active:
		return true
	await scan()
	await interact()
	var ok = await until(func(): return py.active, 9.0)
	await until(func(): return main.busy <= 0.0, 6.0)
	if ok:
		say("relé " + uid)
	return ok or fail("relé %s não ligou" % uid)

func travel(dest: String) -> bool:
	await interact()
	var ok = await until(func(): return main.region != null and main.region.id == dest and not main.respawning and main.mode == "play", 14.0)
	await wait(0.5)
	if ok:
		say("viagem → " + dest)
		blind()
	return ok or fail("portal não levou a " + dest)

func echo(id: String) -> bool:
	await wait(0.1)
	if Game.has_echo(id):
		say("eco %s (%d/18)" % [id, Game.echo_count()])
		return true
	return fail("eco %s não coletado" % id)

func blind() -> void:
	for g in region().guardians:
		g["guard"].params["vision_range"] = 0.01
		g["guard"].params["hear_radius"] = 0.0

## O guardião enxerga Íris à frente (antes de ficar cego).
func guard_check() -> bool:
	var g: Guardian = region().guardians[0]["guard"]
	g.params["vision_range"] = 8.5
	g.params["hear_radius"] = 2.0
	if not await until(func(): return g.state == "patrol", 12.0):
		return fail("guardião não patrulhou (estado %s)" % g.state)
	var fwd = Vector3(sin(g.yaw), 0, cos(g.yaw))
	var spot = g.global_position + fwd * 3.2
	spot.y = g.floor_y
	var back = pos()
	main.player.teleport(spot + Vector3(0, 0.1, 0))
	var hits0 = Game.state["stats"]["hits"]
	var seen = await until(func(): return g.state in ["alert", "chase"] or Game.state["stats"]["hits"] > hits0, 3.0)
	await until(func(): return not main.respawning, 3.0)
	main.player.teleport(back + Vector3(0, 0.1, 0))
	Game.state["integrity"] = Game.max_integrity()
	blind()
	await wait(0.5)
	if seen:
		say("guardião viu Íris (estado %s)" % g.state)
	return seen or fail("guardião não reagiu a Íris à frente")

func _probe(dir: Vector3) -> void:
	var space = main.get_world_3d().direct_space_state
	var p = pos()
	for hy in [0.05, 0.3, 0.6, 1.0, 1.5]:
		var q = PhysicsRayQueryParameters3D.create(p + Vector3(0, hy, 0), p + Vector3(0, hy, 0) + dir * 6.0, 1, [main.player.get_rid()])
		var h = space.intersect_ray(q)
		if h.is_empty():
			print("PROBE y+%.2f: nada" % hy)
		else:
			var c = h["collider"]
			print("PROBE y+%.2f: %s em %s normal %s (%s pai=%s)" % [hy, c.name, str((h["position"] as Vector3).snapped(Vector3.ONE * 0.01)), str((h["normal"] as Vector3).snapped(Vector3.ONE * 0.01)), c.get_class(), c.get_parent().name])

# --- execução ---------------------------------------------------------------------

func run() -> void:
	t0 = Time.get_ticks_msec()
	Engine.physics_ticks_per_second = int(60 * speed)
	Engine.max_physics_steps_per_frame = 24
	Engine.time_scale = speed
	await until(func(): return main.region != null and main.region.id == "farol" and main.mode == "play", 20.0)
	main.ui.show_hud(true)
	await wait(0.5)
	var sections = [["farol_1", _farol_1], ["jardim", _jardim], ["farol_2", _farol_2], ["cidade", _cidade],
		["farol_3", _farol_3], ["jardim_2", _jardim_2], ["farol_4", _farol_4], ["coracao", _coracao], ["final", _final]]
	for s in sections:
		sec_name = s[0]
		sec_t0 = Time.get_ticks_msec()
		say("início")
		var ok = await s[1].call()
		if not ok:
			fail("seção interrompida")
			break
		say("ok (%.1f s reais)" % ((Time.get_ticks_msec() - sec_t0) / 1000.0))
	_report()

func _report() -> void:
	Engine.time_scale = 1.0
	sec_name = "resumo"
	var st: Dictionary = Game.state["stats"]
	say("ecos %d/18 · memórias %s · final '%s' · quedas %d · tempo de jogo %s" % [Game.echo_count(), str(Game.state["memories"]), Game.state.get("ending", ""), int(st.get("falls", 0)), Game.fmt_time(st.get("time", 0.0))])
	var res = "PASSOU" if fails.is_empty() else "FALHOU (%d)" % fails.size()
	say("RESULTADO: " + res)
	for f in fails:
		print("  - " + f)
	var out = FileAccess.open("user://playtest_report.txt", FileAccess.WRITE)
	if out:
		out.store_string("\n".join(lines) + "\n")
	get_tree().quit(0 if fails.is_empty() else 1)

# --- rotas -------------------------------------------------------------------------

func _farol_1() -> bool:
	if not await go([Vector3(0, 0, 30.6), Vector3(0, 0.5, 28.4), Vector3(0, 1.0, 25.7), Vector3(-1.4, 0.6, 22.4), Vector3(-2.0, 0.6, 20.5)]):
		return false
	if not await echo("farol_ilhota"):
		return false
	if not await go([Vector3(0.2, 0.6, 21.6)]):
		return false
	await scan()
	if not await tide(["farol"]):
		return false
	if not await go([Vector3(0, 0.6, 19.0), Vector3(0, -2.6, 14.2), Vector3(0, -2.6, 12.6), Vector3(0, 0, 8.4), Vector3(0, 0, 6.0)], {"jump": "none"}):
		return false
	if not check(Game.flag("farol.crossed", false), "não atravessou a bacia"):
		return false
	if not await go([Vector3(2.0, 0, -6.0), Vector3(-7.2, 0, -16.6)]):
		return false
	return await travel("jardim")

func _jardim() -> bool:
	var r = region()
	if not await go([Vector3(0, 0, 30.0), Vector3(0, 0, 22.0), Vector3(4.6, 0, 18.8)]):
		return false
	await scan()
	if not await tide(["jardim"]):
		return false
	# cisterna: pular no fundo, eco, condutor, subir pela escada de cristal
	if not await go([Vector3(2.2, -3.5, 16.2)]):
		return false
	if not await echo("jardim_cisterna"):
		return false
	if not await go([Vector3(1.1, -3.5, 15.1)]):
		return false
	await interact()
	if not check(r.conductor.aligned, "condutor não alinhou"):
		return false
	if not await go([Vector3(-2.38, -3.5, 16.5), Vector3(-2.38, 0, 10.6), Vector3(-2.4, 0, 9.6)], {"jump": "none"}):
		return false
	if not await go([Vector3(4.4, 0, 9.6), Vector3(4.8, 0, 16.6)]):
		return false
	if not await tide(["jardim"]):
		return false
	# plataformas de flutuação até o eco
	if not await go([Vector3(8.6, 0, 13.4), Vector3(11.9, 0.35, 13.0), Vector3(14.6, 1.1, 11.0), Vector3(17.0, 1.85, 8.6), Vector3(19.0, 2.55, 5.6)]):
		return false
	if not await echo("jardim_flutuante"):
		return false
	if not await go([Vector3(17.0, 1.85, 8.6), Vector3(14.6, 1.1, 11.0), Vector3(11.9, 0.35, 13.0), Vector3(8.4, 0, 13.0)]):
		return false
	# ponte líquida
	await until(func(): return not r.bridges[0].cs.disabled, 6.0)
	if not await go([Vector3(1.6, 0, 8.0), Vector3(0, 0, 5.2), Vector3(0, 0, -4.8)], {"jump": "none"}):
		return false
	if not await go([Vector3(1.8, 0, -5.6)]):
		return false
	await interact()
	if not check(Game.has_ability("glide"), "Asa de Vidro não obtida"):
		return false
	say("Asa de Vidro")
	# torre de pedra (maré alta) → planar até a ilhota → comporta
	if not await go([Vector3(-6.0, 0, -5.4), Vector3(-10.4, 0, -12.0), Vector3(-9.3, 0, -19.4), Vector3(-9.8, 0.8, -22.0), Vector3(-11.0, 1.5, -21.2), Vector3(-11.0, 2.2, -19.0)]):
		return false
	if not await go([Vector3(-19.6, 1.0, -19.0)], {"glide": true}):
		return false
	if not await go([Vector3(-21.2, 1.0, -18.3)]):
		return false
	if not await echo("jardim_ilhota"):
		return false
	if not await go([Vector3(-19.6, 1.0, -19.5)]):
		return false
	await interact()
	if not check(r.flag("sluice"), "comporta não abriu"):
		return false
	if not await go([Vector3(-11.2, 0, -16.6)], {"glide": true}):
		return false
	# nó da praça: maré baixa
	if not await go([Vector3(-10.4, 0, -12.0), Vector3(-5.8, 0, -6.0)]):
		return false
	await scan()
	if not await tide(["jardim"]):
		return false
	if not check(r.pillar.read, "pilar de leitura não lido pelo scan"):
		return false
	if not await go([Vector3(-4.4, 0, -4.4), Vector3(0, 0, -5.2), Vector3(0, 0, -7.2), Vector3(0, -2.2, -11.4)], {"jump": "none"}):
		return false
	if not await guard_check():
		return false
	# placas ● ▲ ■ e eco da praça
	if not await go([Vector3(-5.4, -2.2, -21.0)]):
		return false
	if not await echo("jardim_praca"):
		return false
	if not await go([Vector3(-4.2, -2.2, -18.6), Vector3(-6.2, -2.2, -15.2), Vector3(1.2, -2.2, -21.9), Vector3(5.6, -2.2, -11.7)], {"tol": 0.35}):
		return false
	if not check(r.flag("plates"), "circuito das placas não completou"):
		return false
	say("placas ● ▲ ■")
	if not await go([Vector3(4.6, -2.2, -16.0), Vector3(8.8, 0, -16.0), Vector3(7.9, 0, -20.0), Vector3(7.5, 0, -23.0), Vector3(4.6, 0, -24.4), Vector3(1.5, 0, -26.8), Vector3(0, 0, -28.2), Vector3(0, 0, -30.0)], {"jump": "none"}):
		return false
	# santuário: conduto A no parapeito (maré baixa)
	var zn = -16.0 - 14.0 * cos(PI / 8)
	var zl = (zn + r.z_south) * 0.5
	var dt = 3.3   # jardim.D_TOP
	var dz = -40.5  # jardim.D_Z
	if not await go([Vector3(0, 1.65, zl), Vector3(-2.4, 1.2, zl)], {"jump": "none", "ytol": 1.4}):
		return false
	await interact()
	if not check(r.conduit_a.lit, "conduto A não acendeu"):
		return false
	if not await go([Vector3(-0.2, 1.65, zl)], {"ytol": 1.4}):
		return false
	if not await go([Vector3(0, dt, r.z_south - 0.6)], {"jump": "none"}):
		return false
	# nó do santuário: maré alta → plataforma leste com o conduto B
	if not await go([Vector3(-1.6, dt, dz + 5.8), Vector3(-3.9, dt, dz + 4.4)]):
		return false
	await scan()
	if not await tide(["jardim"]):
		return false
	if not await go([Vector3(-1.6, dt, dz + 5.8), Vector3(1.6, dt, dz + 5.8), Vector3(4.6, dt, dz + 4.6), Vector3(5.8, dt, dz + 2.2), Vector3(8.0, dt, dz + 1.2)]):
		return false
	await interact()
	if not check(r.conduit_a.lit and r.conduit_b.lit, "conduto B não acendeu"):
		return false
	if not await go([Vector3(5.8, dt, dz + 2.2), Vector3(4.6, dt, dz + 4.6), Vector3(0.9, dt, dz + 5.6)]):
		return false
	await interact(2)
	if not check("jardim" in Game.state["memories"] and r.flag("rested"), "fonte: memória/descanso falhou"):
		return false
	say("memória do Jardim")
	if not await go([Vector3(4.0, dt, dz + 6.2)]):
		return false
	return await travel("farol")

func _farol_2() -> bool:
	if not await go([Vector3(2.5, 0, -17.8)]):
		return false
	return await travel("cidade")

func _cidade() -> bool:
	var r = region()
	if not await go([Vector3(3.6, 0, 31.6)]):
		return false
	await interact()
	if not check(Game.has_ability("relay"), "Relé remoto não obtido"):
		return false
	say("Relé remoto")
	# bonde (opcional)
	if not await go([Vector3(5.4, 0, 27.6)]):
		return false
	if not await relay("rele_bonde"):
		return false
	var tram = r.movers[1]
	var tram_a: Vector3 = tram.points[0]
	var tram_b: Vector3 = tram.points[1]
	if not await go([Vector3(8.4, 0, 33.0)]):
		return false
	await until(func(): return tram.position.distance_to(tram_a) < 0.05 and tram._wait > 2.2, 70.0)
	if not await go([Vector3(10.6, 0, 33.0)], {"jump": "none", "tol": 0.6}):
		return false
	if not await until(func(): return pos().x > 31.0 and tram._wait > 0.3, 20.0):
		return fail("bonde não chegou")
	if not await go([Vector3(35.0, 0, 35.4), Vector3(37.0, 0, 36.5)]):
		return false
	if not await echo("cidade_bonde"):
		return false
	if not await go([Vector3(34.4, 0, 34.6)]):
		return false
	await until(func(): return tram.position.distance_to(tram_b) < 0.05 and tram._wait > 2.2, 70.0)
	if not await go([Vector3(32.0, 0, 34.0)], {"jump": "none", "tol": 0.6}):
		return false
	if not await until(func(): return pos().x < 11.5 and tram._wait > 0.3, 20.0):
		return fail("bonde não voltou")
	if not await go([Vector3(7.6, 0, 32.4)]):
		return false
	# relé do elevador e descida
	if not await go([Vector3(-6.0, 0, 24.0)]):
		return false
	if not await relay("rele_elevador"):
		return false
	var lift = r.movers[0]
	await until(func(): return lift.position.y > -0.05 and lift._wait > 2.2, 70.0)
	if not await go([Vector3(0, 0, 21.6), Vector3(0, 0, 19.4)], {"jump": "none"}):
		return false
	if not await until(func(): return pos().y < -7.6, 14.0):
		return fail("elevador não desceu")
	await wait(0.3)
	if not await go([Vector3(0, -8, 16.4)], {"jump": "none"}):
		return false
	if not await go([Vector3(-5.0, -8, 15.2)]):
		return false
	if not await echo("cidade_mercado"):
		return false
	# rede de condutores
	for c in [[Vector3(-4.2, -8, 7.0), 1, 0], [Vector3(0, -8, 3.7), 2, 1], [Vector3(4.2, -8, 7.0), 3, 2]]:
		if not await go([c[0]]):
			return false
		await interact(c[1])
		if not check(r.conductors[c[2]].aligned, "junção %d não alinhou" % c[2]):
			return false
	if not check(r._network_ok(), "rede de energia incompleta"):
		return false
	say("rede de condutores")
	# torre pendurada (opcional): descer até a base e voltar de elevador
	if not await go([Vector3(8.4, -8, 10.0), Vector3(13.4, -8, 10.0)]):
		return false
	if not await go([Vector3(18.4, -14, 11.0)], {"ytol": 1.2, "extra": 8.0}):
		return false
	if not await echo("cidade_torre"):
		return false
	if not await relay("rele_torre"):
		return false
	var tl = r.movers[2]
	await until(func(): return tl.position.y < -13.9 and tl._wait > 2.2, 70.0)
	if not await go([Vector3(15.0, -14, 10.0)], {"jump": "none", "tol": 0.5}):
		return false
	if not await until(func(): return pos().y > -8.4, 14.0):
		return fail("elevador da torre não subiu")
	await wait(0.2)
	if not await go([Vector3(12.4, -8, 10.0), Vector3(8.0, -8, 10.0)], {"jump": "none"}):
		return false
	# para a Praça Alagada
	if not await go([Vector3(2.2, -8, 1.0), Vector3(0, -8, -1.8), Vector3(0, -8, -12.6), Vector3(-2.4, -8, -15.0)], {"jump": "none"}):
		return false
	await scan()
	if not await tide(["cidade"]):
		return false
	if not await go([Vector3(0, -8, -16.4), Vector3(0, -10.5, -20.8), Vector3(2.4, -10.5, -20.8)], {"jump": "none"}):
		return false
	if not await echo("cidade_praca"):
		return false
	if not await go([Vector3(-2.0, -10.5, -26.2)]):
		return false
	await interact()
	if not check(r.flag("dock"), "comporta da praça não abriu"):
		return false
	if not await go([Vector3(0, -10.5, -21.0), Vector3(0, -8, -16.6), Vector3(-2.4, -8, -15.0)], {"jump": "none"}):
		return false
	if not await tide(["cidade"]):
		return false
	await until(func(): return r.floaters[2].position.y > -5.8, 6.0)
	if not await go([Vector3(3.6, -8, -15.6), Vector3(8.2, -8, -20.6), Vector3(4.4, -7.2, -21.0), Vector3(4.4, -6.4, -23.6), Vector3(4.4, -5.6, -26.2), Vector3(7.2, -4.8, -27.4)]):
		return false
	if not await go([Vector3(9.4, -4.8, -29.0)]):
		return false
	if not await echo("cidade_varanda"):
		return false
	if not await go([Vector3(9.0, -4.8, -28.2)]):
		return false
	if not await relay("rele_portao"):
		return false
	# de volta ao nó: maré baixa para a rua
	if not await go([Vector3(8.4, -8, -24.6)], {"jump": "none", "ytol": 1.2}):
		return false
	if not await go([Vector3(8.2, -8, -20.6), Vector3(3.6, -8, -15.6), Vector3(-2.4, -8, -15.0)]):
		return false
	if not await tide(["cidade"]):
		return false
	if not await go([Vector3(-6.4, -8, -17.0), Vector3(-9.6, -8, -22.0), Vector3(-10.0, -8, -24.0), Vector3(-21.0, -8, -24.0), Vector3(-22.6, -8, -22.0)], {"jump": "none"}):
		return false
	# rua dos guardiões: dois pilões de curto alcance
	if not await go([Vector3(-22.6, -8, -20.0), Vector3(-27.2, -10, -20.0), Vector3(-33.0, -10, -20.5)], {"jump": "none"}):
		return false
	if not await relay("rele_rua_0"):
		return false
	if not await go([Vector3(-35.0, -10, -24.4)]):
		return false
	if not await relay("rele_rua_1"):
		return false
	if not check(r.flag("twins"), "guardiões gêmeos não pacificados"):
		return false
	var sp: Vector3 = r.spawns["santuario"]["pos"]
	if not await go([Vector3(-30, -10, -31.6), Vector3(-30, -8, -37.0), Vector3(-30, -8, -38.8), Vector3(-30, sp.y, sp.z)], {"jump": "none"}):
		return false
	await interact(2)
	if not check("cidade" in Game.state["memories"] and r.flag("rested"), "fonte da cidade falhou"):
		return false
	say("memória da Cidade")
	var bp: Vector3 = r.back_portal.global_position
	if not await go([Vector3(-32.6, sp.y, sp.z - 0.1), Vector3(bp.x + 0.2, sp.y, bp.z - 1.9)]):
		return false
	return await travel("farol")

func _farol_3() -> bool:
	# arquivo (relé) e eco do topo (planar)
	if not await go([Vector3(6.0, 0, -8.0), Vector3(13.0, 0, 0.0)]):
		return false
	if not await relay("rele_arquivo"):
		return false
	if not await go([Vector3(8.6, 0, -2.0), Vector3(0.8, 0, -1.2), Vector3(0.8, 0, 2.0), Vector3(5.8, 0, 2.0)]):
		return false
	if not await echo("farol_arquivo"):
		return false
	if not await go([Vector3(0.8, 0, 2.0), Vector3(-2.0, 0, -3.0), Vector3(-8.0, 0, -5.0), Vector3(-8.4, 0, -11.6), Vector3(-9.8, 1.0, -12.8), Vector3(-11.6, 2.0, -14.6), Vector3(-11.3, 3.0, -17.5)]):
		return false
	if not await go([Vector3(-21.0, 0.6, -23.6)], {"glide": true}):
		return false
	if not await echo("farol_topo"):
		return false
	await walk_off(Vector2(-1, -0.4))
	if not await go([Vector3(-9.0, 0, -15.8)], {"jump": "none", "ytol": 4.0}):
		return false
	if not await go([Vector3(-7.2, 0, -16.6)]):
		return false
	return await travel("jardim")

func _jardim_2() -> bool:
	if not await go([Vector3(-3.0, 0, 35.2), Vector3(-4.6, 0.9, 34.5)]):
		return false
	if not await go([Vector3(-13.8, -0.4, 34.5)], {"glide": true}):
		return false
	if not await echo("jardim_mirante"):
		return false
	await walk_off(Vector2(-1, 0))
	if not await go([Vector3(-3.4, 0, 38.2)], {"ytol": 2.0}):
		return false
	return await travel("farol")

func _farol_4() -> bool:
	# oficina: três melhorias e um visor
	if not await go([Vector3(2.0, 0, -8.0), Vector3(7.6, 0, -4.4)]):
		return false
	await interact()
	if not check(main.mode == "paused" and main.ui.menu_open, "oficina não abriu"):
		return false
	for u in ["lens", "core", "compass"]:
		main._install(u)
	main._set_visor("sal")
	main.resume()
	await wait(0.4)
	if not check(Game.state["upgrades"]["lens"] and Game.state["upgrades"]["core"] and Game.state["upgrades"]["compass"], "melhorias não instaladas"):
		return false
	say("melhorias instaladas (%d ecos)" % Game.echo_count())
	if not await go([Vector3(10.4, 0, -13.6)]):
		return false
	return await travel("coracao")

func _coracao() -> bool:
	var r = region()
	if not await go([Vector3(-3.6, 0, 33.4), Vector3(-3.6, 0, 31.6)]):
		return false
	await interact()
	if not check(Game.has_ability("dual"), "Ressonância dupla não obtida"):
		return false
	say("Ressonância dupla")
	if not await go([Vector3(-4.8, 0, 31.8)]):
		return false
	if not await echo("coracao_camara"):
		return false
	if not await go([Vector3(-0.4, 0, 30.0), Vector3(0.6, 0, 27.6)]):
		return false
	await scan()
	if not await tide(["oeste", "norte"]):
		return false
	if not check(r.high("oeste") and r.high("norte"), "nó duplo não ergueu Oeste e Norte"):
		return false
	if not await go([Vector3(2.4, 0, 34.6), Vector3(4.6, 0, 34.6), Vector3(4.6, 2.4, 29.4), Vector3(4.6, 2.4, 27.2)], {"jump": "none"}):
		return false
	if not await echo("coracao_mirante"):
		return false
	if not await go([Vector3(4.6, 2.4, 29.6), Vector3(4.6, 0, 34.2)], {"jump": "none"}):
		return false
	await until(func(): return not r.bridges[0].cs.disabled and not r.bridges[1].cs.disabled, 6.0)
	if not await go([Vector3(-1.0, 0, 26.2), Vector3(-3.4, 0, 25.2), Vector3(-11.4, 0, 5.6), Vector3(-12.4, 0, 3.0), Vector3(-11.4, 0, 0.4), Vector3(-3.4, 0, -24.2), Vector3(-2.2, 0, -26.4)], {"jump": "none"}):
		return false
	if not check(r.flag("crossed"), "ponte longa não atravessada"):
		return false
	# agulha (planar a partir da borda oeste)
	if not await go([Vector3(-6.6, 0, -33.6)]):
		return false
	if not await go([Vector3(-17.4, -2.0, -37.8)], {"glide": true}):
		return false
	if not await echo("coracao_agulha"):
		return false
	await walk_off(Vector2(-1, -0.3))
	# nó Norte+Leste, depois espiral
	if not await go([Vector3(-2.2, 0, -26.4), Vector3(2.0, 0, -28.0)], {"ytol": 2.0}):
		return false
	await scan()
	if not await tide(["norte", "leste"]):
		return false
	if not await go([Vector3(7.6, 0, -32.0), Vector3(10.3, -0.9, -32.0), Vector3(12.9, -1.8, -32.0), Vector3(15.5, -2.7, -32.0), Vector3(18.1, -3.6, -32.0), Vector3(21.8, -4.5, -32.0), Vector3(22.6, -4.5, -31.0)]):
		return false
	await scan()
	if not await tide(["norte"]):
		return false
	await until(func(): return not r.bridges[2].cs.disabled, 6.0)
	if not await go([Vector3(23.0, -4.5, -29.8), Vector3(23.4, -4.5, -14.4), Vector3(24.6, -4.5, -12.4)], {"jump": "none"}):
		return false
	if not await echo("coracao_espiral"):
		return false
	if not await go([Vector3(23.4, -4.5, -10.0), Vector3(23.4, -12, -0.6), Vector3(24.4, -12, 6.0)], {"jump": "none"}):
		return false
	if not await echo("coracao_leito"):
		return false
	var sp: Vector3 = r.spawns["santuario"]["pos"]
	if not await go([Vector3(23.4, -12, 10.6), Vector3(23.4, -10, 14.0), Vector3(23.4, sp.y, sp.z)], {"jump": "none"}):
		return false
	await interact()
	if not check(r.flag("rested"), "descanso no santuário 3 falhou"):
		return false
	# anel do Coração
	if not await go([Vector3(20.6, -10, sp.z + 0.2), Vector3(9.0, -10, 9.0), Vector3(11.0, -10, -6.0)], {"jump": "none"}):
		return false
	if not await relay("rele_leste"):
		return false
	if not await go([Vector3(10.4, -10, 1.0)]):
		return false
	if not await tide(["leste"]):
		return false
	if not await go([Vector3(7.6, -10, -7.0), Vector3(4.0, -10, -11.0)]):
		return false
	if not await relay("rele_norte"):
		return false
	if not await go([Vector3(-1.0, -10, -10.4)]):
		return false
	await scan()
	if not await tide(["norte"]):
		return false
	if not await go([Vector3(-7.6, -10, -7.0), Vector3(-10.6, -10, -1.0), Vector3(-10.0, -10, 5.0)]):
		return false
	if not await relay("rele_oeste"):
		return false
	if not check(r.flag("pylons"), "pilões do anel incompletos"):
		return false
	if not check(r._pattern_ok(), "padrão dos setores errado: O=%s N=%s L=%s" % [r.high("oeste"), r.high("norte"), r.high("leste")]):
		return false
	for p in r.pillars:
		if not check(p.read, "pilar %s não lido" % p.uid):
			return false
	if not await go([Vector3(-5.6, -10, 10.6), Vector3(0, -10, 10.0), Vector3(0, -10, 4.2)], {"jump": "none"}):
		return false
	await interact()
	if not check(r.flag("open") and "coracao" in Game.state["memories"], "o Coração não abriu"):
		return false
	say("Coração aberto")
	await wait(2.5)
	await interact()
	if not check(main.ui.menu_open, "menu da escolha não abriu"):
		return false
	r._choose_free()
	return true

func _final() -> bool:
	if not await until(func(): return main.mode == "ending", 40.0):
		return fail("epílogo não começou (modo %s)" % main.mode)
	var ok = check(Game.state["ending"] == "free" and Game.state["completed"], "final não registrado")
	ok = check(Game.echo_count() == 18, "ecos: %d/18" % Game.echo_count()) and ok
	ok = check(Game.state["memories"].size() == 3, "memórias: %s" % str(Game.state["memories"])) and ok
	# o save final recarrega igual
	Game.save_game()
	var snapshot = Game.state.duplicate(true)
	ok = check(Game.load_game(Game.slot), "save não recarregou") and ok
	var diff = _diff(snapshot, Game.state, "state")
	ok = check(diff == "", "save recarregado difere em " + diff) and ok
	if ok:
		say("save/recarga idênticos (%d chaves)" % snapshot.size())
	return ok

## "" se iguais (números com tolerância; JSON guarda inteiros como float).
func _diff(a: Variant, b: Variant, path: String) -> String:
	var na = typeof(a) in [TYPE_INT, TYPE_FLOAT]
	var nb = typeof(b) in [TYPE_INT, TYPE_FLOAT]
	if na and nb:
		return "" if absf(float(a) - float(b)) < 0.001 else path
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		for k in a:
			if not b.has(k):
				return path + "." + str(k) + " (ausente)"
			var d = _diff(a[k], b[k], path + "." + str(k))
			if d != "":
				return d
		return ""
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if a.size() != b.size():
			return path + " (tamanho)"
		for i in a.size():
			var d = _diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else path
