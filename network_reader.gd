extends Reference
tool

var stream_peer_buffer = null

func _init(p_buffer):
	assert(typeof(p_buffer) == TYPE_RAW_ARRAY)
	stream_peer_buffer = StreamPeerBuffer.new()
	stream_peer_buffer.data_array = p_buffer
	
func is_eof():
	if get_position() >= get_size():
		return true
	
	return false

func get_position():
	return stream_peer_buffer.get_position()
	
func get_size():
	return stream_peer_buffer.get_size()

func seek(p_position):
	return stream_peer_buffer.seek(p_position)

func get_8():
	return stream_peer_buffer.get_8()

func get_16():
	return stream_peer_buffer.get_16()
	
func get_32():
	return stream_peer_buffer.get_32()
	
func get_64():
	return stream_peer_buffer.get_64()
	
func get_u8():
	return stream_peer_buffer.get_u8()
	
func get_u16():
	return stream_peer_buffer.get_u16()
	
func get_u32():
	return stream_peer_buffer.get_u32()
	
func get_u64():
	return stream_peer_buffer.get_u64()
	
func get_float():
	return stream_peer_buffer.get_float()

func get_double():
	return stream_peer_buffer.get_double()
	
func get_vector2():
	return Vector2(get_float(), get_float())
	
func get_vector3():
	return Vector2(get_float(), get_float(), get_float())
	
func get_rect2():
	return Rect2(get_float(), get_float(), get_float(), get_float())
	
func get_quat():
	return Quat(get_float(), get_float(), get_float(), get_float())
	
func put_basis():
	return Basis(get_vector3(), get_vector3(), get_vector3())
	
func put_transform():
	return Transform(get_basis(), get_vector3())
	
func get_entity_id():
	return get_u32()
	
func get_entity():
	return null