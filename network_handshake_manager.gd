extends Node
tool

const ref_pool_const = preload("res://addons/gdutil/ref_pool.gd")

const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_constants_const = preload("network_constants.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")

var signal_table: Array = []

"""

"""

var network_handshake_command_writer_cache: network_writer_const = network_writer_const.new(1024)


func current_master_id():
	pass


func ready_command(p_id: int) -> void:
	var network_writer: network_writer_const = network_handshake_command_writer_cache
	network_writer.seek(0)

	network_writer.put_u8(network_constants_const.READY_COMMAND)

	if network_writer.get_position() > 0:
		var raw_data: PoolByteArray = network_writer.get_raw_data(network_writer.get_position())
		NetworkManager.network_flow_manager.queue_packet_for_send(
			ref_pool_const.new(raw_data), p_id, NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE
		)


func disconnect_command(p_disconnected_peer_id: int) -> void:
	var synced_peers: Array = NetworkManager.copy_active_peers()
	for synced_peer in synced_peers:
		if synced_peer == p_disconnected_peer_id:
			continue

		var network_writer: network_writer_const = network_handshake_command_writer_cache
		network_writer.seek(0)

		network_writer.put_u8(network_constants_const.DISCONNECT_COMMAND)
		network_writer.put_u32(p_disconnected_peer_id)

		if network_writer.get_position() > 0:
			var raw_data: PoolByteArray = network_writer.get_raw_data(network_writer.get_position())
			NetworkManager.network_flow_manager.queue_packet_for_send(
				ref_pool_const.new(raw_data),
				synced_peer,
				NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE
			)


func session_master_command(p_id: int, p_new_master: int) -> void:
	var network_writer: network_writer_const = network_handshake_command_writer_cache
	network_writer.seek(0)

	network_writer.put_u8(network_constants_const.MASTER_COMMAND)
	network_writer.put_u32(p_new_master)

	if network_writer.get_position() > 0:
		var raw_data: PoolByteArray = network_writer.get_raw_data(network_writer.get_position())
		NetworkManager.network_flow_manager.queue_packet_for_send(
			ref_pool_const.new(raw_data), p_id, NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE
		)


# Called by the client once the server has confirmed they have been validated
master func requested_server_info(p_client_info: Dictionary) -> void:
	NetworkLogger.printl("requested_server_info...")
	var rpc_sender_id: int = get_tree().multiplayer.get_rpc_sender_id()

	NetworkManager.peer_data[rpc_sender_id].validation_state = NetworkManager.network_constants_const.validation_state_enum.VALIDATION_STATE_INFO_SENT
	NetworkManager.peer_data[rpc_sender_id].time_since_last_update = 0.0
	NetworkManager.emit_signal("requested_server_info", rpc_sender_id, p_client_info)

# Called by the server 
puppet func received_server_info(p_server_info: Dictionary) -> void:
	NetworkLogger.printl("received_server_info...")

	if p_server_info.has("server_type"):
		var server_type = p_server_info["server_type"]
		if server_type is String:
			match p_server_info["server_type"]:
				NetworkManager.network_constants_const.RELAY_SERVER_NAME:
					NetworkLogger.printl("Connected to a relay server...")
					NetworkManager.set_relay(true)
					NetworkManager.emit_signal("received_server_info", p_server_info)
					return
				NetworkManager.network_constants_const.AUTHORITATIVE_SERVER_NAME:
					NetworkLogger.printl("Connected to a authoritative server...")
					NetworkManager.set_relay(false)
					NetworkManager.emit_signal("received_server_info", p_server_info)
					return
				_:
					NetworkLogger.error("Unknown server type")
		else:
			NetworkLogger.error("Server type is not a string")

	NetworkManager.request_network_kill()

# Called by client after the basic scene state for the client has been loaded and set up
master func requested_server_state(p_client_info: Dictionary) -> void:
	NetworkLogger.printl("requested_server_state...")
	var rpc_sender_id: int = get_tree().multiplayer.get_rpc_sender_id()

	NetworkManager.peer_data[rpc_sender_id]["validation_state"] = NetworkManager.network_constants_const.validation_state_enum.VALIDATION_STATE_STATE_SENT
	NetworkManager.peer_data[rpc_sender_id]["time_since_last_update"] = 0.0
	NetworkManager.emit_signal("requested_server_state", rpc_sender_id, p_client_info)

puppet func received_server_state(p_server_state: Dictionary) -> void:
	NetworkLogger.printl("received_server_state...")
	NetworkManager.emit_signal("received_server_state", p_server_state)


func create_handshake_command(p_command: int) -> network_writer_const:
	var network_writer: network_writer_const = NetworkManager.network_entity_command_writer_cache
	network_writer.seek(0)

	return network_writer


func decode_handshake_buffer(
	p_packet_sender_id: int, p_network_reader: network_reader_const, p_command: int
) -> network_reader_const:
	match p_command:
		network_constants_const.INFO_REQUEST_COMMAND:
			pass
		network_constants_const.STATE_REQUEST_COMMAND:
			pass
		network_constants_const.READY_COMMAND:
			NetworkManager.peer_data[p_packet_sender_id].validation_state = NetworkManager.VALIDATION_STATE_SYNCED
		network_constants_const.DISCONNECT_COMMAND:
			if p_network_reader.is_eof():
				NetworkLogger.error("decode_handshake_buffer: eof!")
				return p_network_reader

			var id: int = p_network_reader.get_u32()

			if p_network_reader.is_eof():
				NetworkLogger.error("decode_handshake_buffer: eof!")
				return p_network_reader

			disconnect_peer(p_packet_sender_id, id)
		network_constants_const.MAP_CHANGING_COMMAND:
			pass

	return p_network_reader


# Called after all other clients have been registered to the new client
puppet func peer_registration_complete() -> void:
	# Client does not have direct permission to access this method
	if not NetworkManager.is_server() and not NetworkManager.is_rpc_sender_id_server():
		return

	emit_signal("peer_registration_complete")


func is_command_valid(p_command: int) -> bool:
	if (
		p_command == network_constants_const.INFO_REQUEST_COMMAND
		or p_command == network_constants_const.STATE_REQUEST_COMMAND
		or p_command == network_constants_const.READY_COMMAND
		or p_command == network_constants_const.DISCONNECT_COMMAND
		or p_command == network_constants_const.MAP_CHANGING_COMMAND
	):
		return true
	else:
		return false


func disconnect_peer(p_packet_sender_id: int, p_id: int) -> void:
	# Client does not have direct permission to access this method
	if p_packet_sender_id == network_constants_const.SERVER_MASTER_PEER_ID:
		NetworkManager.unregister_peer(p_id)


func _ready() -> void:
	if ! Engine.is_editor_hint():
		ConnectionUtil.connect_signal_table(signal_table, self)
