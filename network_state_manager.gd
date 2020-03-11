extends Node
tool

const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_constants_const = preload("network_constants.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")

const SERVER_PACKET_SEND_RATE = 1.0 / 30.0
const CLIENT_PACKET_SEND_RATE = 1.0 / 30.0
const MAXIMUM_STATE_PACKET_SIZE = 1024
var time_passed = 0.0
var time_until_next_send = 0.0

var state_writers = {}

var signal_table : Array = [
	{"singleton":"NetworkManager", "signal":"network_process", "method":"_network_manager_process"},
	{"singleton":"NetworkManager", "signal":"reset_timers", "method":"_reset_internal_timer"},
	{"singleton":"NetworkManager", "signal":"game_hosted", "method":"_game_hosted"},
	{"singleton":"NetworkManager", "signal":"connection_succeeded", "method":"_connected_to_server"},
	
	{"singleton":"NetworkManager", "signal":"server_peer_connected", "method":"_server_peer_connected"},
	{"singleton":"NetworkManager", "signal":"server_peer_disconnected", "method":"_server_peer_disconnected"},
]


"""

"""


"""
Server
"""
	
func create_entity_update_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()

	network_writer = NetworkManager.network_entity_manager.write_entity_instance_id(p_entity, network_writer)
	var entity_state : network_writer_const = p_entity.get_network_identity_node().get_state(null, false)
	var entity_state_size = entity_state.get_position()
	if entity_state_size >= 0xffff:
		ErrorManager.error("State data exceeds 16 bits!")
	else:
		entity_state_size = 0
	network_writer.put_u16(entity_state.get_position())
	network_writer.put_writer(entity_state, entity_state.get_position())

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
		time_passed += p_delta
		if time_passed > time_until_next_send:
			var synced_peers : Array = NetworkManager.get_valid_send_peers(p_id)
				
			for synced_peer in synced_peers:
				var network_writer_state : network_writer_const = state_writers[synced_peer]
				network_writer_state.seek(0)
				
				# Update commands
				var entities : Array = get_tree().get_nodes_in_group("NetworkedEntities")
				var entity_update_writers : Array = []
				for entity in entities:
					if entity.is_inside_tree():
						var entity_master : int = entity.get_network_master()
						if synced_peer != entity_master:
							if p_id == NetworkManager.SERVER_MASTER_PEER_ID:
								entity_update_writers.append(create_entity_command(network_constants_const.UPDATE_ENTITY_COMMAND, entity))
							else:
								if (entity_master == p_id):
									entity_update_writers.append(create_entity_command(network_constants_const.UPDATE_ENTITY_COMMAND, entity))
								
				# Put the update commands into the unreliable channel
				for entity_update_writer in entity_update_writers:
					network_writer_state.put_writer(entity_update_writer)
						
				var raw_data : PoolByteArray = network_writer_state.get_raw_data(network_writer_state.get_position())
				
				if network_writer_state.get_position() > 0:
					NetworkManager.send_packet(raw_data, synced_peer, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
			if NetworkManager.is_server():
				time_until_next_send = time_passed + SERVER_PACKET_SEND_RATE
			else:
				time_until_next_send = time_passed + CLIENT_PACKET_SEND_RATE
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
	
	var entity_state_size : int = p_network_reader.get_u16()
	if network_entity_manager.network_instance_ids.has(instance_id):
		var network_identity_instance : Node = network_entity_manager.network_instance_ids[instance_id]
		var network_instance_master : int = network_identity_instance.get_network_master()
		var invalid_sender_id = false
		if NetworkManager.is_server_authoritative():
			# Only the server will accept state updates for entities directly and other clients will accept them from the host
			if(NetworkManager.is_server() and network_instance_master == p_packet_sender_id) or (p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID and network_instance_master != NetworkManager.get_current_peer_id()):
				network_identity_instance.update_state(p_network_reader, false)
			else:
				invalid_sender_id = true
		else:
			# In a non-authoritive context, everyone is responsible for their own state updates, though the server can override
			if network_instance_master == p_packet_sender_id or p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
				network_identity_instance.update_state(p_network_reader, false)
			else:
				invalid_sender_id = true
			
		#if invalid_sender_id == true:
		#	ErrorManager.error("Invalid state update sender id {packet_sender_id}!".format({"packet_sender_id":str(p_packet_sender_id)}))
	else:
		p_network_reader.seek(p_network_reader.get_position() + entity_state_size)
	
	return p_network_reader

func decode_state_buffer(p_packet_sender_id : int, p_network_reader : network_reader_const, p_command : int) -> network_reader_const:
	match p_command:
		network_constants_const.UPDATE_ENTITY_COMMAND:
			p_network_reader = decode_entity_update_command(p_packet_sender_id, p_network_reader)
	
	return p_network_reader
	
func _game_hosted() -> void:
	state_writers = {}
	
func _connected_to_server() -> void:
	state_writers = {}
	var network_writer : network_writer_const = network_writer_const.new(MAXIMUM_STATE_PACKET_SIZE)
	state_writers[NetworkManager.SERVER_MASTER_PEER_ID] = network_writer
	
func _server_peer_connected(p_id : int) -> void:
	var network_writer : network_writer_const = network_writer_const.new(MAXIMUM_STATE_PACKET_SIZE)
	state_writers[p_id] = network_writer

func _server_peer_disconnected(p_id : int) -> void:
	if state_writers.erase(p_id) == false:
		printerr("network_state_manager: attempted disconnect invalid peer!")
	
func _reset_internal_timer() -> void:
	time_passed = 0.0
	time_until_next_send = 0.0
	
func _ready() -> void:
	if Engine.is_editor_hint() == false:
		ConnectionUtil.connect_signal_table(signal_table, self)
