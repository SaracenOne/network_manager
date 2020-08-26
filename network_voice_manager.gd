extends Node
tool

var get_voice_buffers: FuncRef = FuncRef.new()
var get_sequence_id: FuncRef = FuncRef.new()
var should_send_audio: FuncRef = FuncRef.new()

const ref_pool_const = preload("res://addons/gdutil/ref_pool.gd")

const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_constants_const = preload("network_constants.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")

const MAXIMUM_VOICE_PACKET_SIZE = 1024

var dummy_voice_writer = network_writer_const.new(MAXIMUM_VOICE_PACKET_SIZE)  # For debugging purposes
var voice_writers = {}

var signal_table: Array = [
	{
		"singleton": "NetworkManager",
		"signal": "network_process",
		"method": "_network_manager_process"
	},
	{"singleton": "NetworkManager", "signal": "game_hosted", "method": "_game_hosted"},
	{
		"singleton": "NetworkManager",
		"signal": "connection_succeeded",
		"method": "_connected_to_server"
	},
	{
		"singleton": "NetworkManager",
		"signal": "server_peer_connected",
		"method": "_server_peer_connected"
	},
	{
		"singleton": "NetworkManager",
		"signal": "server_peer_disconnected",
		"method": "_server_peer_disconnected"
	},
]

"""

"""


func encode_voice_packet(
	p_packet_sender_id: int,
	p_network_writer: network_writer_const,
	p_sequence_id: int,
	p_voice_buffer: Dictionary,
	p_encode_id: bool
) -> network_writer_const:
	var voice_buffer_size: int = p_voice_buffer["buffer_size"]

	if p_encode_id:
		p_network_writer.put_u32(p_packet_sender_id)
	p_network_writer.put_u24(p_sequence_id)
	p_network_writer.put_u16(voice_buffer_size)
	if voice_buffer_size > 0:
		p_network_writer.put_ranged_data(p_voice_buffer["byte_array"], 0, voice_buffer_size)

	return p_network_writer


func decode_voice_command(p_packet_sender_id: int, p_network_reader: network_reader_const) -> network_reader_const:
	var encoded_voice_byte_array: PoolByteArray = PoolByteArray()
	var encoded_sequence_id: int = -1
	var encoded_size: int = -1
	var sender_id: int = -1

	if p_network_reader.is_eof():
		return null

	if (
		! NetworkManager.is_relay()
		and p_packet_sender_id == NetworkManager.network_constants_const.SERVER_MASTER_PEER_ID
	):
		sender_id = p_network_reader.get_u32()
		if p_network_reader.is_eof():
			return null
	else:
		sender_id = p_packet_sender_id

	encoded_sequence_id = p_network_reader.get_u24()
	if p_network_reader.is_eof():
		return null
	encoded_size = p_network_reader.get_u16()
	if p_network_reader.is_eof():
		return null

	if encoded_size > 0:
		encoded_voice_byte_array = p_network_reader.get_buffer(encoded_size)
		if p_network_reader.is_eof():
			return null

	if encoded_size != encoded_voice_byte_array.size():
		NetworkLogger.error("pool size mismatch!")

	# If you're the server, forward the packet to all the other peers
	if ! NetworkManager.is_relay() and NetworkManager.is_server():
		var synced_peers: Array = NetworkManager.copy_active_peers()
		for synced_peer in synced_peers:
			if synced_peer != sender_id:
				var network_writer_state: network_writer_const = null

				if synced_peer != -1:
					network_writer_state = voice_writers[synced_peer]
				else:
					network_writer_state = dummy_voice_writer

				network_writer_state.seek(0)

				var encoded_voice: Dictionary = Dictionary()
				encoded_voice["byte_array"] = encoded_voice_byte_array
				encoded_voice["buffer_size"] = encoded_voice_byte_array.size()

				# Voice commands
				network_writer_state = encode_voice_buffer(
					sender_id, network_writer_state, encoded_sequence_id, encoded_voice, true
				)

				if network_writer_state.get_position() > 0:
					var raw_data: PoolByteArray = network_writer_state.get_raw_data(
						network_writer_state.get_position()
					)
					NetworkManager.network_flow_manager.queue_packet_for_send(
						ref_pool_const.new(raw_data),
						synced_peer,
						NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE
					)

	if ! NetworkManager.server_dedicated:
		NetworkManager.emit_signal(
			"voice_packet_compressed", sender_id, encoded_sequence_id, encoded_voice_byte_array
		)

	return p_network_reader


func _network_manager_process(p_id: int, p_delta: float) -> void:
	if p_delta > 0.0:
		var synced_peers: Array = NetworkManager.copy_valid_send_peers(p_id, false)

		if get_voice_buffers.is_valid() and get_sequence_id.is_valid():
			
			var sequence_id: int = get_sequence_id.call_func()
			var voice_buffers: Array = get_voice_buffers.call_func()
			
			for voice_buffer in voice_buffers:
				# If muted or gated, give it an empty array
				if ! should_send_audio.is_valid():
					voice_buffer = {"byte_array": PoolByteArray(), "buffer_size": 0}
				else:
					if ! should_send_audio.call_func():
						voice_buffer = {"byte_array": PoolByteArray(), "buffer_size": 0}

				for synced_peer in synced_peers:
					var network_writer_state: network_writer_const = null

					if synced_peer != -1:
						network_writer_state = voice_writers[synced_peer]
					else:
						network_writer_state = dummy_voice_writer

					network_writer_state.seek(0)

					# Voice commands
					network_writer_state = encode_voice_buffer(
						p_id,
						network_writer_state,
						sequence_id,
						voice_buffer,
						(
							! NetworkManager.is_relay()
							and (
								synced_peer
								!= NetworkManager.network_constants_const.SERVER_MASTER_PEER_ID
							)
						)
					)

					if network_writer_state.get_position() > 0:
						var raw_data: PoolByteArray = network_writer_state.get_raw_data(
							network_writer_state.get_position()
						)
						NetworkManager.network_flow_manager.queue_packet_for_send(
							ref_pool_const.new(raw_data),
							synced_peer,
							NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE
						)
				sequence_id += 1
				

func encode_voice_buffer(
	p_packet_sender_id: int,
	p_network_writer: network_writer_const,
	p_index: int,
	p_voice_buffer: Dictionary,
	p_encode_id: bool
) -> network_writer_const:
	p_network_writer.put_u8(network_constants_const.VOICE_COMMAND)
	p_network_writer = encode_voice_packet(
		p_packet_sender_id, p_network_writer, p_index, p_voice_buffer, p_encode_id
	)

	return p_network_writer


func decode_voice_buffer(
	p_packet_sender_id: int, p_network_reader: network_reader_const, p_command: int
) -> network_reader_const:
	match p_command:
		network_constants_const.VOICE_COMMAND:
			p_network_reader = decode_voice_command(p_packet_sender_id, p_network_reader)

	return p_network_reader


func _game_hosted() -> void:
	voice_writers = {}


func _connected_to_server() -> void:
	voice_writers = {}
	var network_writer: network_writer_const = network_writer_const.new(MAXIMUM_VOICE_PACKET_SIZE)
	voice_writers[NetworkManager.network_constants_const.SERVER_MASTER_PEER_ID] = network_writer


func _server_peer_connected(p_id: int) -> void:
	var network_writer: network_writer_const = network_writer_const.new(MAXIMUM_VOICE_PACKET_SIZE)
	voice_writers[p_id] = network_writer


func _server_peer_disconnected(p_id: int) -> void:
	if ! voice_writers.erase(p_id):
		NetworkLogger.error("network_state_manager: attempted disconnect invalid peer!")


func is_command_valid(p_command: int) -> bool:
	if p_command == network_constants_const.VOICE_COMMAND:
		return true
	else:
		return false


func _ready() -> void:
	if ! Engine.is_editor_hint():
		ConnectionUtil.connect_signal_table(signal_table, self)
