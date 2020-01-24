extends NetworkLogic
class_name NetworkTransform

var target_origin : Vector3 = Vector3()
var target_rotation : Quat = Quat()

var current_origin : Vector3 = Vector3()
var current_rotation : Quat = Quat()

export(float) var origin_interpolation_factor : float = 0.0
export(float) var rotation_interpolation_factor : float = 0.0
export(float) var snap_threshold : float = 0.0

static func write_transform(p_writer : network_writer_const, p_transform : Transform) -> network_writer_const:
	p_writer.put_vector3(p_transform.origin)
	p_writer.put_quat(Quat(p_transform.basis))
	
	return p_writer

func on_serialize(p_writer : network_writer_const, p_initial_state : bool) -> network_writer_const:
	if entity_node.get_logic_node() == null:
		entity_node._ready()
		
	if p_initial_state:
		pass
		
	var transform : Transform = entity_node.get_logic_node().get_transform()
	p_writer = write_transform(p_writer, transform)
	
	return p_writer
	
func on_deserialize(p_reader : network_reader_const, p_initial_state : bool) -> network_reader_const:
	var origin : Vector3 = p_reader.get_vector3()
	var rotation : Quat = p_reader.get_quat()
	
	target_origin = origin
	target_rotation = rotation
	
	if p_initial_state or origin_interpolation_factor == 0.0:
		var current_transform : Transform = Transform(Basis(rotation), origin)
		current_origin = current_transform.origin
		current_rotation = Quat(current_transform.basis)
		if entity_node:
			entity_node.get_logic_node().set_transform(current_transform)
	
	return p_reader
	
func _process(p_delta : float) -> void:
	if is_inside_tree() and !is_network_master():
		var distance : float = current_origin.distance_to(target_origin)
		
		if snap_threshold > 0.0 and distance < snap_threshold:
			if origin_interpolation_factor > 0.0:
				current_origin = current_origin.linear_interpolate(target_origin, origin_interpolation_factor * p_delta)
			else:
				current_origin = target_origin
				
			if rotation_interpolation_factor > 0.0:
				current_rotation = current_rotation.slerp(target_rotation, rotation_interpolation_factor * p_delta)
			else:
				current_rotation = target_rotation
		else:
			current_origin = target_origin
			current_rotation = target_rotation
			
		if entity_node:
			entity_node.get_logic_node().set_transform(Transform(Basis(current_rotation), current_origin))
