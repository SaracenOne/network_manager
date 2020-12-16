extends NetworkLogic
class_name NetworkTransform
tool

const network_hierarchy_const = preload("network_hierarchy.gd")
const network_entity_manager_const = preload("network_entity_manager.gd")
const math_funcs_const = preload("res://addons/math_util/math_funcs.gd")

var target_origin: Vector3 = Vector3()
var target_rotation: Quat = Quat()

var current_origin: Vector3 = Vector3()
var current_rotation: Quat = Quat()

var parent_entity_is_valid: bool = true

var parent_id: int = network_entity_manager_const.NULL_NETWORK_INSTANCE_ID
var attachment_id: int = 0

signal transform_updated(p_transform)

export (bool) var sync_parent: bool = false
export (bool) var sync_attachment: bool = false
export (float) var origin_interpolation_factor: float = 0.0
export (float) var rotation_interpolation_factor: float = 0.0
export (float) var snap_threshold: float = 0.0

static func write_transform(p_writer: network_writer_const, p_transform: Transform) -> void:
	p_writer.put_vector3(p_transform.origin)
	p_writer.put_quat(p_transform.basis.get_rotation_quat())

static func read_transform(p_reader: network_reader_const) -> Transform:
	var origin: Vector3 = math_funcs_const.sanitise_vec3(p_reader.get_vector3())
	var rotation: Quat = math_funcs_const.sanitise_quat(p_reader.get_quat())

	return Transform(Basis(rotation), origin)


func update_transform(p_transform: Transform) -> void:
	emit_signal("transform_updated", p_transform)

func serialize_hierarchy(p_writer: network_writer_const) -> network_writer_const:
	if sync_parent:
		p_writer = network_hierarchy_const.write_entity_parent_id(p_writer, entity_node)
		if sync_attachment:
			if entity_node.get_entity_parent():
				network_hierarchy_const.write_entity_attachment_id(p_writer, entity_node)
	return p_writer

func on_serialize(p_writer: network_writer_const, p_initial_state: bool) -> network_writer_const:
	if p_initial_state:
		pass
		
	# Hierarchy
	p_writer = serialize_hierarchy(p_writer)

	# Transform
	var transform: Transform = entity_node.simulation_logic_node.get_transform()
	write_transform(p_writer, transform)

	return p_writer

func deserialize_hierarchy(p_reader: network_reader_const, p_initial_state: bool) -> network_reader_const:
	if sync_parent:
		parent_id = network_hierarchy_const.read_entity_parent_id(p_reader)
		if sync_attachment:
			if parent_id != network_entity_manager_const.NULL_NETWORK_INSTANCE_ID:
				attachment_id = network_hierarchy_const.read_entity_attachment_id(p_reader)
			
		if ! p_initial_state:
			process_parenting()
	
	return p_reader

func on_deserialize(p_reader: network_reader_const, p_initial_state: bool) -> network_reader_const:
	received_data = true

	# Hierarchy
	p_reader = deserialize_hierarchy(p_reader, p_initial_state)
		
	# Transform
	var transform: Transform = read_transform(p_reader)

	var origin: Vector3 = transform.origin
	var rotation: Quat = transform.basis.get_rotation_quat()
	
	if p_initial_state or parent_entity_is_valid:
		target_origin = origin
		target_rotation = rotation
		if p_initial_state:
			var current_transform: Transform = Transform(Basis(rotation), origin)
			current_origin = current_transform.origin
			current_rotation = current_transform.basis.get_rotation_quat()
			update_transform(Transform(current_rotation, current_origin))
		
	return p_reader


func interpolate_transform(p_delta: float) -> void:
	if is_inside_tree() and ! is_network_master():
		if entity_node:
			var distance: float = current_origin.distance_to(target_origin)
			if (
				snap_threshold > 0.0
				and distance < snap_threshold
			):
				if origin_interpolation_factor > 0.0:
					current_origin = current_origin.linear_interpolate(
						target_origin, origin_interpolation_factor * p_delta
					)
				else:
					current_origin = target_origin
				if rotation_interpolation_factor > 0.0:
					current_rotation = current_rotation.slerp(
						target_rotation, rotation_interpolation_factor * p_delta
					)
				else:
					current_rotation = target_rotation
			else:
				current_origin = target_origin
				current_rotation = target_rotation
				
			call_deferred("update_transform", Transform(Basis(current_rotation), current_origin))


func process_parenting():
	if entity_node:
		parent_entity_is_valid = true
		if parent_id != network_entity_manager_const.NULL_NETWORK_INSTANCE_ID:
			if NetworkManager.network_entity_manager.network_instance_ids.has(parent_id):
				var network_identity: Node = NetworkManager.network_entity_manager.get_network_instance_identity(
					parent_id
				)
				if network_identity:
					var parent_instance: Node = network_identity.get_entity_node()
					entity_node.request_reparent_entity(parent_instance.get_entity_ref(), attachment_id)
			else:
				parent_entity_is_valid = false
				entity_node.request_reparent_entity(null, attachment_id)
		else:
			entity_node.request_reparent_entity(null, attachment_id)


func _entity_physics_process(_delta: float) -> void:
	._entity_physics_process(_delta)
	if received_data:
		if parent_entity_is_valid:
			interpolate_transform(_delta)
		received_data = false


func _entity_ready() -> void:
	._entity_ready()


func _entity_about_to_add() -> void:
	._entity_about_to_add()
	if ! Engine.is_editor_hint():
		if received_data:
			if ! is_network_master():
				process_parenting()
				if parent_entity_is_valid:
					update_transform(Transform(Basis(current_rotation), current_origin))
			received_data = false
