class_name TideSector
extends RefCounted
## Estado binário da maré de um setor (GDD 05): confirmação de 1 s no nó,
## transição de 2,5 s, cooldown de 5 s, recusa em volume inseguro.

signal started(to_high: bool)
signal finished(is_high: bool)
signal refused(reason: String)

const CONFIRM_TIME := 1.0
const TRANSITION_TIME := 2.5
const COOLDOWN := 5.0

var id: String
var high: bool
var _from: bool
var progress = 1.0
var cooldown = 0.0

func _init(sector_id: String, start_high: bool = true) -> void:
	id = sector_id
	high = start_high
	_from = start_high

var transitioning: bool:
	get: return progress < 1.0

## 0 = maré baixa, 1 = maré alta (contínuo durante a transição).
var level: float:
	get:
		var a = 1.0 if _from else 0.0
		var b = 1.0 if high else 0.0
		var t = clampf(progress, 0.0, 1.0)
		return lerpf(a, b, t * t * (3.0 - 2.0 * t))

## "" se pode alternar, ou o motivo da recusa.
func refusal(player_unsafe: bool = false) -> String:
	if transitioning:
		return "transitioning"
	if cooldown > 0.0:
		return "cooldown"
	if player_unsafe and not high:
		return "unsafe"
	return ""

func toggle(player_unsafe: bool = false) -> bool:
	var r = refusal(player_unsafe)
	if r != "":
		refused.emit(r)
		return false
	_from = high
	high = not high
	progress = 0.0
	started.emit(high)
	return true

## Força a mudança (nó duplo já validou os dois setores).
func force_toggle() -> void:
	_from = high
	high = not high
	progress = 0.0
	started.emit(high)

func set_state(is_high: bool) -> void:
	high = is_high
	_from = is_high
	progress = 1.0
	cooldown = 0.0

func update(dt: float) -> void:
	if transitioning:
		progress = minf(1.0, progress + dt / TRANSITION_TIME)
		if not transitioning:
			cooldown = COOLDOWN
			finished.emit(high)
	elif cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - dt)


## Confirmação por segurar o botão (dispara uma vez por pressão).
class HoldConfirm:
	var duration = 1.0
	var t = 0.0
	var fired = false

	func update(dt: float, holding: bool) -> bool:
		if not holding:
			t = 0.0
			fired = false
			return false
		if fired:
			return false
		t += dt
		if t >= duration:
			fired = true
			return true
		return false

	var ratio: float:
		get: return 1.0 if fired else clampf(t / duration, 0.0, 1.0)
