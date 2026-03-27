/// Per-participant connection quality indicator.
///
/// Derived from RTCStats (packet loss, jitter, RTT) by the protocol adapter.
enum VoiceConnectionQuality {
  good,
  fair,
  poor,
  unknown,
}
