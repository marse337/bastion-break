class_name Door
extends Node3D
## A sliding door occupying one tile. It slides sideways into the wall that
## frames it and closes on its own after a few seconds unless something is
## standing in the doorway.

enum { CLOSED, OPENING, OPEN, CLOSING }

const SPEED := 1.6
const STAY_OPEN := 4.0

var tile := Vector2i.ZERO
var spans_x := true
var key := ""
var unlocked := true
var openness := 0.0
var state := CLOSED
var open_timer := 0.0
var slab: MeshInstance3D


func setup(t: Vector2i, along_x: bool, key_name: String, mesh: Mesh, mat: Material) -> void:
	tile = t
	spans_x = along_x
	key = key_name
	unlocked = key == ""
	position = Vector3(t.x, 0, t.y)
	slab = MeshInstance3D.new()
	slab.mesh = mesh
	slab.material_override = mat
	add_child(slab)


func passable() -> bool:
	return openness > 0.75


func blocks_sight() -> bool:
	return openness < 0.5


## Returns true when the door actually starts moving (so the caller can play a sound).
func open() -> bool:
	if state == CLOSED or state == CLOSING:
		state = OPENING
		return true
	if state == OPEN:
		open_timer = 0.0
	return false


func close() -> bool:
	if state == OPEN or state == OPENING:
		state = CLOSING
		return true
	return false


## Returns true when the door starts closing by itself.
func tick(delta: float, occupied: bool) -> bool:
	var started_closing := false
	match state:
		OPENING:
			openness = minf(1.0, openness + delta * SPEED)
			if openness >= 1.0:
				state = OPEN
				open_timer = 0.0
		OPEN:
			open_timer += delta
			if open_timer > STAY_OPEN and not occupied:
				state = CLOSING
				started_closing = true
		CLOSING:
			if occupied:
				state = OPENING
			else:
				openness = maxf(0.0, openness - delta * SPEED)
				if openness <= 0.0:
					state = CLOSED
	var slide := openness * 0.98
	slab.position = Vector3(slide, 0, 0) if spans_x else Vector3(0, 0, slide)
	return started_closing
