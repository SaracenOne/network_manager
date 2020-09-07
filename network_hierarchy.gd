extends NetworkLogic
class_name NetworkHierarchy

const network_entity_manager_const = preload("res://addons/network_manager/network_entity_manager.gd")

var parent_id: int = network_entity_manager_const.NULL_NETWORK_INSTANCE_ID
var attachment_id: int = 0


func _reparent_entity_instance(p_instance: Node, p_parent: Node, p_attachment_id: int = 0) -> void:
	p_instance.set_entity_parent(p_parent, p_attachment_id)


static func encode_parent_id(p_writer: network_writer_const, p_id: int) -> network_writer_const:
	p_writer.put_u32(p_id)

	return p_writer

static func decode_parent_id(p_reader: network_reader_const) -> int:
	return p_reader.get_u32()

static func encode_attachment_id(p_writer: network_writer_const, p_id: int) -> network_writer_const:
	p_writer.put_u8(p_id)

	return p_writer

static func decode_attachment_id(p_reader: network_reader_const) -> int:
	return p_reader.get_u8()

static func write_entity_parent_id(p_writer: network_writer_const, p_entity: Node) -> network_writer_const:
	if p_entity.entity_parent:
		encode_parent_id(p_writer, p_entity.entity_parent.network_identity_node.network_instance_id)
	else:
		p_writer.put_u32(NetworkManager.network_entity_manager.NULL_NETWORK_INSTANCE_ID)

	return p_writer

static func write_entity_attachment_id(p_writer: network_writer_const, p_entity: Node) -> network_writer_const:
	encode_attachment_id(p_writer, p_entity.attachment_id)
	return p_writer

static func read_entity_parent_id(p_reader: network_reader_const) -> int:
	return decode_parent_id(p_reader)

static func read_entity_attachment_id(p_reader: network_reader_const) -> int:
	return decode_attachment_id(p_reader)


func on_serialize(p_writer: network_writer_const, p_initial_state: bool) -> network_writer_const:
	p_writer = write_entity_parent_id(p_writer, entity_node)
	if entity_node.entity_parent:
		write_entity_attachment_id(p_writer, entity_node)

	return p_writer


func on_deserialize(p_reader: network_reader_const, p_initial_state: bool) -> network_reader_const:
	received_data = true

	parent_id = read_entity_parent_id(p_reader)
	if parent_id != network_entity_manager_const.NULL_NETWORK_INSTANCE_ID:
		attachment_id = read_entity_attachment_id(p_reader)

	return p_reader


func process_parenting():
	if entity_node:
		var entity_parent = entity_node.entity_parent

		var last_parent_id = network_entity_manager_const.NULL_NETWORK_INSTANCE_ID
		var last_attachment_id = entity_node.attachment_id

		if entity_parent:
			last_parent_id = entity_parent.network_identity_node.network_instance_id

		if parent_id != last_parent_id or attachment_id != last_attachment_id:
			if parent_id != network_entity_manager_const.NULL_NETWORK_INSTANCE_ID:
				if NetworkManager.network_entity_manager.network_instance_ids.has(parent_id):
					var network_identity: Node = NetworkManager.network_entity_manager.get_network_instance_identity(
						parent_id
					)
					if network_identity:
						var parent_instance: Node = network_identity.get_entity_node()
						entity_node.entity_parent_state = entity_node.ENTITY_PARENT_STATE_CHANGED
						_reparent_entity_instance(entity_node, parent_instance, attachment_id)
				else:
					entity_node.entity_parent_state = entity_node.ENTITY_PARENT_STATE_INVALID
					_reparent_entity_instance(entity_node, null, attachment_id)
			else:
				entity_node.entity_parent_state = entity_node.ENTITY_PARENT_STATE_CHANGED
				_reparent_entity_instance(entity_node, null, attachment_id)
	received_data = false


func _network_process(_delta: float) -> void:
	._network_process(_delta)
	if received_data:
		process_parenting()


func _entity_ready() -> void:
	._entity_ready()
	if ! Engine.is_editor_hint():
		if received_data:
			call_deferred("process_parenting")
