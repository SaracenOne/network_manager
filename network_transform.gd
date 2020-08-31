extends NetworkLogic
class_name NetworkTransform

const math_funcs_const = preload("res://addons/math_util/math_funcs.gd")

var target_origin: Vector3 = Vector3()
var target_rotation: Quat = Quat()

var current_origin: Vector3 = Vector3()
var current_rotation: Quat = Quat()

signal transform_updated(p_transform)

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


func on_serialize(p_writer: network_writer_const, p_initial_state: bool) -> network_writer_const:
	if p_initial_state:
		pass

	var transform: Transform = entity_node.simulation_logic_node.get_transform()
	write_transform(p_writer, transform)

	return p_writer


func on_deserialize(p_reader: network_reader_const, p_initial_state: bool) -> network_reader_const:
	received_data = true

	var transform: Transform = read_transform(p_reader)

	var origin: Vector3 = transform.origin
	var rotation: Quat = transform.basis.get_rotation_quat()

	target_origin = origin
	target_rotation = rotation

	if p_initial_state or origin_interpolation_factor == 0.0:
		var current_transform: Transform = Transform(Basis(rotation), origin)
		current_origin = current_transform.origin
		current_rotation = current_transform.basis.get_rotation_quat()

	return p_reader


func interpolate_transform(p_delta: float) -> void:
	if is_inside_tree() and ! is_network_master():
		if entity_node:
			var distance: float = current_origin.distance_to(target_origin)
			if (
				entity_node.entity_parent_state != entity_node.ENTITY_PARENT_STATE_INVALID
				and snap_threshold > 0.0
				and distance < snap_threshold
			):
				# If the parent has changed in the last frame, current origin and rotation from the entity
				if entity_node.entity_parent_state == entity_node.ENTITY_PARENT_STATE_CHANGED:
					var entity_local_transform: Transform = entity_node.get_transform()
					current_origin = entity_local_transform.origin
					current_rotation = entity_local_transform.basis.get_rotation_quat()

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

			if entity_node.entity_parent_state == entity_node.ENTITY_PARENT_STATE_CHANGED:
				entity_node.entity_parent_state = entity_node.ENTITY_PARENT_STATE_OK

			call_deferred("update_transform", Transform(Basis(current_rotation), current_origin))


func _network_process(_delta: float) -> void:
	._network_process(_delta)
	if received_data:
		interpolate_transform(_delta)


func _ready():
	if ! Engine.is_editor_hint():
		if received_data:
			call_deferred("update_transform", Transform(Basis(current_rotation), current_origin))
