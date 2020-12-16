extends Reference
tool

const network_reader_const = preload("res://addons/network_manager/network_reader.gd")
const network_writer_const = preload("res://addons/network_manager/network_writer.gd")

const network_entity_manager_const = preload("res://addons/network_manager/network_entity_manager.gd")

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
	if p_entity.get_entity_parent():
		encode_parent_id(p_writer, p_entity.get_entity_parent().network_identity_node.network_instance_id)
	else:
		p_writer.put_u32(NetworkManager.network_entity_manager.NULL_NETWORK_INSTANCE_ID)

	return p_writer

static func write_entity_attachment_id(p_writer: network_writer_const, p_entity: Node) -> network_writer_const:
	encode_attachment_id(p_writer, p_entity.cached_entity_attachment_id)
	return p_writer

static func read_entity_parent_id(p_reader: network_reader_const) -> int:
	return decode_parent_id(p_reader)

static func read_entity_attachment_id(p_reader: network_reader_const) -> int:
	return decode_attachment_id(p_reader)


"""
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
					entity_node.reparent_entity(parent_instance.get_entity_ref(), attachment_id)
			else:
				parent_entity_is_valid = false
				entity_node.reparent_entity(null, attachment_id)
		else:
			entity_node.reparent_entity(null, attachment_id)
	received_data = false

func _entity_ready() -> void:
	._entity_ready()
	if ! Engine.is_editor_hint():
		if received_data:
			process_parenting()
"""
