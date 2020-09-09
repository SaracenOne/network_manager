extends Node
tool

const ref_pool_const = preload("res://addons/gdutil/ref_pool.gd")

const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_constants_const = preload("network_constants.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")

const MAXIMUM_RPC_PACKET_SIZE = 1024

var dummy_rpc_reliable_writer = network_writer_const.new(MAXIMUM_RPC_PACKET_SIZE)  # For debugging purposes
var rpc_reliable_writers = {}
var dummy_rpc_unreliable_writer = network_writer_const.new(MAXIMUM_RPC_PACKET_SIZE)  # For debugging purposes
var rpc_unreliable_writers = {}

var signal_table: Array = []

var pending_rpc_reliable_calls: Array = []
var pending_rpc_unreliable_calls: Array = []
var pending_rset_reliable_calls: Array = []
var pending_rset_unreliable_calls: Array = []

"""

"""


func queue_reliable_rpc_call(p_entity: Node, p_method_id: int, p_args: Array):
	pending_rpc_reliable_calls.push_back(
		{"entity": p_entity, "method_id": p_method_id, "args": p_args}
	)


func queue_reliable_rset_call(p_entity: Node, p_property_id: int, p_value):
	pending_rset_reliable_calls.push_back(
		{"entity": p_entity, "property_id": p_property_id, "value": p_value}
	)


func queue_unreliable_rpc_call(p_entity: Node, p_method_id: int, p_args: Array):
	pending_rpc_unreliable_calls.push_back(
		{"entity": p_entity, "method_id": p_method_id, "args": p_args}
	)


func queue_unreliable_rset_call(p_entity: Node, p_property_id: int, p_value):
	pending_rset_unreliable_calls.push_back(
		{"entity": p_entity, "property_id": p_property_id, "value": p_value}
	)


func get_entity_root_node() -> Node:
	return NetworkManager.get_entity_root_node()


func write_entity_rpc_command(p_call: Dictionary, p_network_writer: network_writer_const) -> network_writer_const:
	var network_entity_manager: Node = NetworkManager.network_entity_manager

	p_network_writer = network_entity_manager.write_entity_instance_id(
		p_call["entity"], p_network_writer
	)
	p_network_writer.put_16(p_call["method_id"])
	p_network_writer.put_8(p_call["args"].size())
	for arg in p_call["args"]:
		p_network_writer.put_var(arg)

	return p_network_writer


func write_entity_rset_command(p_call: Dictionary, p_network_writer: network_writer_const) -> network_writer_const:
	var network_entity_manager: Node = NetworkManager.network_entity_manager

	p_network_writer = network_entity_manager.write_entity_instance_id(
		p_call.entity, p_network_writer
	)
	p_network_writer.put_16(p_call["method_id"])
	p_network_writer.put_var(p_call["value"])

	return p_network_writer


func create_rpc_command(p_command: int, p_rpc_call: Dictionary) -> network_writer_const:
	var network_writer: network_writer_const = NetworkManager.network_entity_command_writer_cache
	network_writer.seek(0)

	match p_command:
		network_constants_const.ENTITY_RPC_COMMAND:
			network_writer.put_u8(network_constants_const.ENTITY_RPC_COMMAND)
			network_writer = write_entity_rpc_command(p_rpc_call, network_writer)
		network_constants_const.ENTITY_RSET_COMMAND:
			network_writer.put_u8(network_constants_const.ENTITY_RSET_COMMAND)
			network_writer = write_entity_rset_command(p_rpc_call, network_writer)
		_:
			NetworkLogger.error("Unknown entity message")

	return network_writer


func flush() -> void:
	pending_rpc_reliable_calls = []
	pending_rpc_unreliable_calls = []
	pending_rset_reliable_calls = []
	pending_rset_unreliable_calls = []


func _network_manager_flush() -> void:
	flush()


func _network_manager_process(p_id: int, _delta: float) -> void:
	if (
		pending_rpc_reliable_calls.size() > 0
		or pending_rpc_unreliable_calls.size() > 0
		or pending_rset_reliable_calls.size() > 0
		or pending_rset_unreliable_calls.size() > 0
	):
		# Debugging information
		# Debugging end

		var synced_peers: Array = NetworkManager.copy_valid_send_peers(p_id, false)

		for synced_peer in synced_peers:
			var network_reliable_writer_state: network_writer_const = null
			var network_unreliable_writer_state: network_writer_const = null

			if synced_peer != -1:
				network_reliable_writer_state = rpc_reliable_writers[synced_peer]
				network_unreliable_writer_state = rpc_unreliable_writers[synced_peer]
			else:
				network_reliable_writer_state = dummy_rpc_reliable_writer
				network_unreliable_writer_state = dummy_rpc_unreliable_writer

			network_reliable_writer_state.seek(0)
			network_unreliable_writer_state.seek(0)

			for call in pending_rpc_reliable_calls:
				var rpc_command_network_writer: network_writer_const = create_rpc_command(
					network_constants_const.ENTITY_RPC_COMMAND, call
				)
				network_reliable_writer_state.put_writer(
					rpc_command_network_writer, rpc_command_network_writer.get_position()
				)

			for call in pending_rset_reliable_calls:
				var rset_command_network_writer: network_writer_const = create_rpc_command(
					network_constants_const.ENTITY_RSET_COMMAND, call
				)
				network_reliable_writer_state.put_writer(
					rset_command_network_writer, rset_command_network_writer.get_position()
				)

			for call in pending_rpc_unreliable_calls:
				var rpc_command_network_writer: network_writer_const = create_rpc_command(
					network_constants_const.ENTITY_RPC_COMMAND, call
				)
				network_reliable_writer_state.put_writer(
					rpc_command_network_writer, rpc_command_network_writer.get_position()
				)

			for call in pending_rset_unreliable_calls:
				var rset_command_network_writer: network_writer_const = create_rpc_command(
					network_constants_const.ENTITY_RSET_COMMAND, call
				)
				network_reliable_writer_state.put_writer(
					rset_command_network_writer, rset_command_network_writer.get_position()
				)

			if network_reliable_writer_state.get_position() > 0:
				var raw_data: PoolByteArray = network_reliable_writer_state.get_raw_data(
					network_reliable_writer_state.get_position()
				)
				NetworkManager.network_flow_manager.queue_packet_for_send(
					ref_pool_const.new(raw_data),
					synced_peer,
					NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE
				)

			if network_unreliable_writer_state.get_position() > 0:
				var raw_data: PoolByteArray = network_unreliable_writer_state.get_raw_data(
					network_unreliable_writer_state.get_position()
				)
				NetworkManager.network_flow_manager.queue_packet_for_send(
					ref_pool_const.new(raw_data),
					synced_peer,
					NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE
				)

		# Flush the pending spawn, parenting, and destruction queues
		flush()


func decode_entity_rpc_command(p_packet_sender_id: int, p_network_reader: network_reader_const) -> network_reader_const:
	var network_entity_manager: Node = NetworkManager.network_entity_manager

	if p_network_reader.is_eof():
		NetworkLogger.error("decode_entity_rpc_command: eof!")
		return null

	var instance_id: int = network_entity_manager.read_entity_instance_id(p_network_reader)
	if instance_id <= network_entity_manager.NULL_NETWORK_INSTANCE_ID:
		NetworkLogger.error("decode_entity_rpc_command: eof!")
		return null

	if network_entity_manager.network_instance_ids.has(instance_id):
		var entity_instance: Node = network_entity_manager.network_instance_ids[instance_id].get_entity_node()
		if entity_instance:
			var method_id: int = p_network_reader.get_16()

			if p_network_reader.is_eof():
				NetworkLogger.error("decode_entity_rpc_command: eof!")
				return null

			var arg_count: int = p_network_reader.get_8()

			if p_network_reader.is_eof():
				NetworkLogger.error("decode_entity_rpc_command: eof!")
				return null

			var args: Array = []
			for i in range(0, arg_count):
				var arg = p_network_reader.get_var()

				if p_network_reader.is_eof():
					NetworkLogger.error("decode_entity_rpc_command: eof!")
					return null

				args.push_back(arg)

			var rpc_table: Node = entity_instance.get_rpc_table()
			if rpc_table:
				rpc_table.nm_rpc_called(p_packet_sender_id, method_id, args)

	return p_network_reader


func decode_entity_rset_command(p_packet_sender_id: int, p_network_reader: network_reader_const) -> network_reader_const:
	var network_entity_manager: Node = NetworkManager.network_entity_manager

	if p_network_reader.is_eof():
		NetworkLogger.error("decode_entity_rpc_command: eof!")
		return null

	var instance_id: int = network_entity_manager.read_entity_instance_id(p_network_reader)
	if instance_id <= network_entity_manager.NULL_NETWORK_INSTANCE_ID:
		NetworkLogger.error("decode_entity_rpc_command: eof!")
		return null

	if network_entity_manager.network_instance_ids.has(instance_id):
		var entity_instance: Node = network_entity_manager.network_instance_ids[instance_id].get_entity_node()
		if entity_instance:
			var property_id: int = p_network_reader.get_16()

			if p_network_reader.is_eof():
				NetworkLogger.error("decode_entity_rpc_command: eof!")
				return null

			var value = p_network_reader.get_var()

			if p_network_reader.is_eof():
				NetworkLogger.error("decode_entity_rpc_command: eof!")
				return null

			var rpc_table: Node = entity_instance.get_rpc_table()
			if rpc_table:
				rpc_table.nm_rset_called(p_packet_sender_id, property_id, value)

	return p_network_reader


func decode_rpc_buffer(
	p_packet_sender_id: int, p_network_reader: network_reader_const, p_command: int
) -> network_reader_const:
	match p_command:
		network_constants_const.ENTITY_RPC_COMMAND:
			p_network_reader = decode_entity_rpc_command(p_packet_sender_id, p_network_reader)
		network_constants_const.ENTITY_RSET_COMMAND:
			p_network_reader = decode_entity_rset_command(p_packet_sender_id, p_network_reader)
		_:
			NetworkLogger.error("Unknown Entity replication command")

	return p_network_reader


func _game_hosted() -> void:
	rpc_reliable_writers = {}
	rpc_unreliable_writers = {}


func _connected_to_server() -> void:
	rpc_reliable_writers = {}
	var network_reliable_writer: network_writer_const = network_writer_const.new(
		MAXIMUM_RPC_PACKET_SIZE
	)
	rpc_reliable_writers[NetworkManager.network_constants_const.SERVER_MASTER_PEER_ID] = network_reliable_writer

	rpc_unreliable_writers = {}
	var network_unreliable_writer: network_writer_const = network_writer_const.new(
		MAXIMUM_RPC_PACKET_SIZE
	)
	rpc_unreliable_writers[NetworkManager.network_constants_const.SERVER_MASTER_PEER_ID] = network_unreliable_writer


func _server_peer_connected(p_id: int) -> void:
	var rpc_reliable_writer: network_writer_const = network_writer_const.new(
		MAXIMUM_RPC_PACKET_SIZE
	)
	rpc_reliable_writers[p_id] = rpc_reliable_writer
	var rpc_unreliable_writer: network_writer_const = network_writer_const.new(
		MAXIMUM_RPC_PACKET_SIZE
	)
	rpc_unreliable_writers[p_id] = rpc_unreliable_writer


func _server_peer_disconnected(p_id: int) -> void:
	if ! rpc_reliable_writers.erase(p_id):
		NetworkLogger.error("network_rpc_manager: attempted disconnect invalid peer!")
	if ! rpc_unreliable_writers.erase(p_id):
		NetworkLogger.error("network_rpc_manager: attempted disconnect invalid peer!")


func is_command_valid(p_command: int) -> bool:
	if (
		p_command == network_constants_const.ENTITY_RPC_COMMAND
		or p_command == network_constants_const.ENTITY_RSET_COMMAND
	):
		return true
	else:
		return false


func _ready() -> void:
	if ! Engine.is_editor_hint():
		ConnectionUtil.connect_signal_table(signal_table, self)
