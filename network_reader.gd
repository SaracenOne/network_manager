extends Reference
tool

const entity_const = preload("res://addons/entity_manager/entity.gd")

var stream_peer_buffer : StreamPeerBuffer = null

func _init(p_buffer : PoolByteArray) -> void:
	assert(typeof(p_buffer) == TYPE_RAW_ARRAY)
	stream_peer_buffer = StreamPeerBuffer.new()
	stream_peer_buffer.data_array = p_buffer
	
func is_eof() -> bool:
	if get_position() >= get_size():
		return true
	
	return false

func get_position() -> int:
	return stream_peer_buffer.get_position()
	
func get_size() -> int:
	return stream_peer_buffer.get_size()

func seek(p_position : int) -> void:
	stream_peer_buffer.seek(p_position)

func get_8() -> int:
	return stream_peer_buffer.get_8()

func get_16() -> int:
	return stream_peer_buffer.get_16()
	
func get_32() -> int:
	return stream_peer_buffer.get_32()
	
func get_64() -> int:
	return stream_peer_buffer.get_64()
	
func get_u8() -> int:
	return stream_peer_buffer.get_u8()
	
func get_u16() -> int:
	return stream_peer_buffer.get_u16()
	
func get_u32() -> int:
	return stream_peer_buffer.get_u32()
	
func get_u64() -> int:
	return stream_peer_buffer.get_u64()
	
func get_float() -> float:
	return stream_peer_buffer.get_float()

func get_double() -> float:
	return stream_peer_buffer.get_double()
	
func get_vector2() -> Vector2:
	return Vector2(get_float(), get_float())
	
func get_vector3() -> Vector3:
	return Vector3(get_float(), get_float(), get_float())
	
func get_rect2() -> Rect2:
	return Rect2(get_float(), get_float(), get_float(), get_float())
	
func get_quat() -> Quat:
	return Quat(get_float(), get_float(), get_float(), get_float())
	
func get_basis() -> Basis:
	return Basis(get_vector3(), get_vector3(), get_vector3())
	
func get_transform() -> Transform:
	return Transform(get_basis(), get_vector3())
	
func get_entity_id() -> int:
	return get_u32()
	
func get_entity() -> entity_const:
	return null
