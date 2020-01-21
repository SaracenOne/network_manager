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


func encode_voice_packet(
	p_packet_sender_id : int,
	p_network_writer : network_writer_const,
	p_index : int,
	p_voice_buffer : PoolByteArray,
	p_encode_id : bool) -> network_writer_const:
		
	var voice_buffer_size : int = p_voice_buffer.size()
	
	if p_encode_id:
		p_network_writer.put_u32(p_packet_sender_id)
	p_network_writer.put_u24(p_index)
	p_network_writer.put_u16(voice_buffer_size)
	if voice_buffer_size > 0:
		p_network_writer.put_data(p_voice_buffer)
	
	return p_network_writer
	
func decode_voice_command(
	p_packet_sender_id : int,
	p_network_reader : network_reader_const
	) -> network_reader_const:
		
	var encoded_voice : PoolByteArray = PoolByteArray()
	var encoded_index : int = -1
	var encoded_size : int = -1
	var sender_id : int = -1
	
	if p_network_reader.is_eof():
		return null
		
	if NetworkManager.is_server_authoritative() and p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
		sender_id = p_network_reader.get_u32()
		if p_network_reader.is_eof():
			return null
	else:
		sender_id = p_packet_sender_id
		
	encoded_index = p_network_reader.get_u24()
	if p_network_reader.is_eof():
		return null
	encoded_size = p_network_reader.get_u16()
	if p_network_reader.is_eof():
		return null
	
	if encoded_size > 0:
		encoded_voice = p_network_reader.get_buffer(encoded_size)
		if p_network_reader.is_eof():
			return null
	
	if encoded_size != encoded_voice.size():
		printerr("pool size mismatch!")
	
	# If you're the server, forward the packet to all the other peers
	if NetworkManager.is_server_authoritative() and NetworkManager.is_server():
		var synced_peers : Array = NetworkManager.get_synced_peers()
		for synced_peer in synced_peers:
			if synced_peer != sender_id:
				var unreliable_network_writer : network_writer_const = network_writer_const.new()
				
				# Voice commands
				unreliable_network_writer = encode_voice_buffer(sender_id,
				unreliable_network_writer,
				encoded_index,
				encoded_voice,
				true)
				
				NetworkManager.send_packet(unreliable_network_writer.get_raw_data(), synced_peer, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	
	NetworkManager.emit_signal("voice_packet_compressed", sender_id, encoded_index, encoded_voice)
	
	return p_network_reader
		
func _network_manager_process(p_id : int, p_delta : float) -> void:
	if p_delta > 0.0:
		var synced_peers : Array = NetworkManager.get_valid_send_peers(p_id)
		
		var voice_buffers : Array = GodotSpeech.copy_and_clear_buffers()
		for voice_buffer in voice_buffers:
			for synced_peer in synced_peers:
				var unreliable_network_writer : network_writer_const = network_writer_const.new()
				
				# Voice commands
				unreliable_network_writer = encode_voice_buffer(p_id,
				unreliable_network_writer,
				GodotSpeech.input_audio_sent_id,
				voice_buffer,
				NetworkManager.is_server_authoritative() and synced_peer != NetworkManager.SERVER_MASTER_PEER_ID)
				
				if unreliable_network_writer.get_size() > 0:
					NetworkManager.send_packet(unreliable_network_writer.get_raw_data(), synced_peer, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
			GodotSpeech.input_audio_sent_id += 1

func encode_voice_buffer(p_packet_sender_id : int,
	p_network_writer : network_writer_const,
	p_index : int,
	p_voice_buffer : PoolByteArray,
	p_encode_id : bool) -> network_writer_const:
	
	p_network_writer.put_u8(network_constants_const.VOICE_COMMAND)
	p_network_writer = encode_voice_packet(p_packet_sender_id,
	p_network_writer,
	p_index,
	p_voice_buffer,
	p_encode_id)
	
	return p_network_writer

func decode_voice_buffer(p_packet_sender_id : int, p_network_reader : network_reader_const, p_command : int) -> network_reader_const:
	match p_command:
		network_constants_const.VOICE_COMMAND:
			p_network_reader = decode_voice_command(p_packet_sender_id, p_network_reader)
	
	return p_network_reader
	
func _ready() -> void:
	if Engine.is_editor_hint() == false:
		ConnectionUtil.connect_signal_table(signal_table, self)
