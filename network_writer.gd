extends Reference
tool

var stream_peer_buffer : StreamPeerBuffer = StreamPeerBuffer.new()

func get_raw_data() -> PoolByteArray:
	return stream_peer_buffer.data_array

func clear() -> void:
	stream_peer_buffer.clear()

func get_position() -> int:
	return stream_peer_buffer.get_position()
	
func get_size() -> int:
	return stream_peer_buffer.get_size()

func seek(p_position : int) -> void:
	stream_peer_buffer.seek(p_position)

func put_data(p_data : PoolByteArray) -> void:
	stream_peer_buffer.put_data(p_data)

func put_writer(p_writer) -> void:
	put_data(p_writer.stream_peer_buffer.data_array)
	
func put_8(p_value : int) -> void:
	stream_peer_buffer.put_8(p_value)

func put_16(p_value : int) -> void:
	stream_peer_buffer.put_16(p_value)
	
func put_32(p_value : int) -> void:
	stream_peer_buffer.put_32(p_value)
	
func put_64(p_value) -> void:
	stream_peer_buffer.put_64(p_value)
	
func put_u8(p_value : int) -> void:
	stream_peer_buffer.put_u8(p_value)
	
func put_u16(p_value : int) -> void:
	stream_peer_buffer.put_u16(p_value)
	
func put_u32(p_value : int) -> void:
	stream_peer_buffer.put_u32(p_value)
	
func put_u64(p_value : int) -> void:
	stream_peer_buffer.put_u64(p_value)
	
func put_float(p_float : float) -> void:
	stream_peer_buffer.put_float(p_float)

func put_double(p_double : float) -> void:
	stream_peer_buffer.put_double(p_double)
	
func put_vector2(p_vector : Vector2) -> void:
	put_float(p_vector.x)
	put_float(p_vector.y)
	
func put_vector3(p_vector : Vector3) -> void:
	put_float(p_vector.x)
	put_float(p_vector.y)
	put_float(p_vector.z)
	
func put_rect2(p_rect : Rect2) -> void:
	put_float(p_rect.position.x)
	put_float(p_rect.position.y)
	put_float(p_rect.size.x)
	put_float(p_rect.size.y)
	
func put_quat(p_quat : Quat) -> void:
	put_float(p_quat.x)
	put_float(p_quat.y)
	put_float(p_quat.z)
	put_float(p_quat.w)
	
func put_basis(p_basis : Basis) -> void:
	put_vector3(p_basis.x)
	put_vector3(p_basis.y)
	put_vector3(p_basis.z)
	
func put_transform(p_transform : Transform) -> void:
	put_basis(p_transform.basis)
	put_vector3(p_transform.origin)
