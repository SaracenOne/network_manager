extends Node
tool

const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_constants_const = preload("network_constants.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")


var signal_table : Array = [
	{"singleton":"NetworkManager", "signal":"network_process", "method":"_network_manager_process"},
]


"""

"""


"""
Server
"""
	
func create_entity_update_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()

	network_writer = NetworkManager.network_entity_manager.write_entity_instance_id(p_entity, network_writer)
	var entity_state : network_writer_const = p_entity.get_network_identity_node().get_state(network_writer_const.new(), false)
	network_writer.put_u32(entity_state.get_size())
	network_writer.put_writer(entity_state)

	return network_writer
	
func create_entity_command(p_command : int, p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()
	match p_command:
		network_constants_const.UPDATE_ENTITY_COMMAND:
			network_writer.put_u8(network_constants_const.UPDATE_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_update_command(p_entity))
		_:
			ErrorManager.error("Unknown entity message")

	return network_writer
		
func _network_manager_process(p_id : int, p_delta : float) -> void:
	if p_delta > 0.0:
		var synced_peers : Array = []
		if p_id == NetworkManager.SERVER_MASTER_PEER_ID:
			synced_peers = NetworkManager.get_synced_peers()
		else:
			synced_peers = [NetworkManager.SERVER_MASTER_PEER_ID]
			
		for synced_peer in synced_peers:
			var unreliable_network_writer : network_writer_const = network_writer_const.new()

			# Update commands
			var entities : Array = get_tree().get_nodes_in_group("NetworkedEntities")
			var entity_update_writers : Array = []
			for entity in entities:
				if entity.is_inside_tree():
					### get this working
					if p_id == NetworkManager.SERVER_MASTER_PEER_ID:
						entity_update_writers.append(create_entity_command(network_constants_const.UPDATE_ENTITY_COMMAND, entity))
					else:
						if (entity.get_network_master() == p_id):
							entity_update_writers.append(create_entity_command(network_constants_const.UPDATE_ENTITY_COMMAND, entity))
							
			# Put the update commands into the unreliable channel
			for entity_update_writer in entity_update_writers:
				unreliable_network_writer.put_writer(entity_update_writer)
					
			if unreliable_network_writer.get_size() > 0:
				NetworkManager.send_packet(unreliable_network_writer.get_raw_data(), synced_peer, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
"""
Client
"""
func decode_entity_update_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_update_command: eof!")
		return null
		
	var instance_id : int = network_entity_manager.read_entity_instance_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_update_command: eof!")
		return null
	
	var entity_state_size : int = p_network_reader.get_u32()
	if network_entity_manager.network_instance_ids.has(instance_id):
		var network_identity_instance : Node = network_entity_manager.network_instance_ids[instance_id]
		if (NetworkManager.is_server() and network_identity_instance.get_network_master() == p_packet_sender_id) or p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
			network_identity_instance.update_state(p_network_reader, false)
	else:
		p_network_reader.seek(p_network_reader.get_position() + entity_state_size)
	
	return p_network_reader

func decode_state_buffer(p_packet_sender_id : int, p_network_reader : network_reader_const, p_command : int) -> network_reader_const:
	match p_command:
		network_constants_const.UPDATE_ENTITY_COMMAND:
			p_network_reader = decode_entity_update_command(p_packet_sender_id, p_network_reader)
	
	return p_network_reader
	
func _ready() -> void:
	if Engine.is_editor_hint() == false:
		ConnectionUtil.connect_signal_table(signal_table, self)
