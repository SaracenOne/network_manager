extends Node
tool

const ref_pool_const = preload("res://addons/gdutil/ref_pool.gd")

const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_constants_const = preload("network_constants.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")

var signal_table : Array = [
]


"""

"""

var network_handshake_command_writer_cache : network_writer_const = network_writer_const.new(1024)

func current_master_id():
	pass

func ready_command(p_id : int) -> void:
	var network_writer : network_writer_const = NetworkManager.network_handshake_command_writer_cache
	network_writer.seek(0)
	
	network_writer.put_u8(network_constants_const.READY_COMMAND)

	if network_writer.get_position() > 0:
		var raw_data : PoolByteArray = network_writer.get_raw_data(network_writer.get_position())
		NetworkManager.network_flow_manager.queue_packet_for_send(ref_pool_const.new(raw_data), p_id, NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE)

func session_master_command(p_id : int, p_new_master : int) -> void:
	var network_writer : network_writer_const = NetworkManager.network_handshake_command_writer_cache
	network_writer.seek(0)
	
	network_writer.put_u8(network_constants_const.MASTER_COMMAND)
	network_writer.put_u32(p_new_master)

	if network_writer.get_position() > 0:
		var raw_data : PoolByteArray = network_writer.get_raw_data(network_writer.get_position())
		NetworkManager.network_flow_manager.queue_packet_for_send(ref_pool_const.new(raw_data), p_id, NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE)

# Called by the client once the server has confirmed they have been validated
master func requested_server_info(p_client_info: Dictionary) -> void:
	print("requested_server_info...")
	var rpc_sender_id : int = get_tree().multiplayer.get_rpc_sender_id()
	
	NetworkManager.peer_data[rpc_sender_id].validation_state = NetworkManager.validation_state_enum.VALIDATION_STATE_INFO_SENT
	NetworkManager.peer_data[rpc_sender_id].time_since_last_update = 0.0
	NetworkManager.emit_signal("requested_server_info", rpc_sender_id, p_client_info)
	
# Called by the server 
puppet func received_server_info(p_server_info : Dictionary) -> void:
	print("received_server_info...")
	
	if p_server_info:
		if p_server_info.has("server_type"):
			match p_server_info.server_type:
				"relay":
					NetworkManager.set_relay(true)
					print("Connected to a relay server...")
				"authoritative":
					NetworkManager.set_relay(false)
					print("Connected to a authoritative server...")
	
	NetworkManager.emit_signal("received_server_info", p_server_info)
		
# Called by client after the basic scene state for the client has been loaded and set up
master func requested_server_state(p_client_info: Dictionary) -> void:
	print("requested_server_state...")
	var rpc_sender_id : int = get_tree().multiplayer.get_rpc_sender_id()
	
	NetworkManager.peer_data[rpc_sender_id].validation_state = NetworkManager.validation_state_enum.VALIDATION_STATE_STATE_SENT
	NetworkManager.peer_data[rpc_sender_id].time_since_last_update = 0.0
	NetworkManager.emit_signal("requested_server_state", rpc_sender_id, p_client_info)
		
puppet func received_server_state(p_server_state : Dictionary) -> void:
	print("received_server_state...")
	NetworkManager.emit_signal("received_server_state", p_server_state)

func create_handshake_command(p_command : int) -> network_writer_const:
	var network_writer : network_writer_const = NetworkManager.network_entity_command_writer_cache
	network_writer.seek(0)

	return network_writer

func decode_handshake_buffer(p_packet_sender_id : int, p_network_reader : network_reader_const, p_command : int) -> network_reader_const:
	match p_command:
		network_constants_const.SERVER_INFO_REQUEST:
			pass
		network_constants_const.SERVER_STATE_REQUEST:
			pass
		network_constants_const.READY_COMMAND:
			NetworkManager.peer_data[p_packet_sender_id].validation_state = NetworkManager.VALIDATION_STATE_SYNCED
		network_constants_const.MAP_CHANGING_COMMAND:
			pass
	
	return p_network_reader
	
# Called after all other clients have been registered to the new client
puppet func peer_registration_complete() -> void:
	# Client does not have direct permission to access this method
	if not NetworkManager.is_server() and not NetworkManager.is_rpc_sender_id_server():
		return
	
	emit_signal("peer_registration_complete")
	
func is_command_valid(p_command : int) -> bool:
	if p_command == network_constants_const.INFO_REQUEST_COMMAND or \
		p_command == network_constants_const.STATE_REQUEST_COMMAND or \
		p_command == network_constants_const.READY_COMMAND or \
		p_command == network_constants_const.MAP_CHANGING_COMMAND:
		return true
	else:
		return false
	
func _ready() -> void:
	if !Engine.is_editor_hint():
		ConnectionUtil.connect_signal_table(signal_table, self)
