extends NetworkLogic

const math_funcs_const = preload("res://addons/math_util/math_funcs.gd")

var bits : int = 0
var transforms : Array = []

# Degrees
const FINGER_BASE_MIN_PITCH = -90
const FINGER_BASE_MAX_PITCH = 90
const FINGER_BASE_MIN_YAW = -20
const FINGER_BASE_MAX_YAW = 20

const DIGIT_CHAIN_MIN_PITCH = 0
const DIGIT_CHAIN_MAX_PITCH = 90

func on_serialize(p_writer : network_writer_const, _p_initial_state : bool) -> network_writer_const:
	bits = 0
	

	
	return p_writer
	
func on_deserialize(p_reader : network_reader_const, _p_initial_state : bool) -> network_reader_const:
	received_data = true
	
	
	return p_reader

func _ready() -> void:
	if Engine.is_editor_hint() == false:
		if received_data:
			pass
