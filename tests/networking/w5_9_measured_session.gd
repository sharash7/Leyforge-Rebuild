extends "res://tests/networking/w5_8_delayed_session.gd"

# Test-only post-authentication gameplay sends and bounded application receives.
# Existing lifecycle counters separately record control sends/receives.
var gameplay_metrics: Dictionary={"sent_packets":0,"sent_bytes":0,"received_packets_including_control":0,"received_bytes_including_control":0}
func send_packet(peer: int, bytes: PackedByteArray, transfer_mode: int, channel: int) -> Error:
	var result: Error=super.send_packet(peer,bytes,transfer_mode,channel)
	if result==OK:
		gameplay_metrics["sent_packets"]+=1;gameplay_metrics["sent_bytes"]+=bytes.size()
	return result

func _receive_packet(peer: int, bytes: PackedByteArray) -> void:
	if not bytes.is_empty() and bytes.size()<=8192:
		gameplay_metrics["received_packets_including_control"]+=1
		gameplay_metrics["received_bytes_including_control"]+=bytes.size()
	super._receive_packet(peer,bytes)
