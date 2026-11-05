class LiveKitToken {
  final String serverUrl;
  final String token;
  final String roomName;
  final String identity;
  final int conversationId;

  const LiveKitToken({
    required this.serverUrl,
    required this.token,
    required this.roomName,
    required this.identity,
    required this.conversationId,
  });

  factory LiveKitToken.fromJson(Map<String, dynamic> json) {
    return LiveKitToken(
      serverUrl: json['server_url'] as String,
      token: json['token'] as String,
      roomName: json['room_name'] as String,
      identity: json['identity'] as String,
      conversationId: (json['conversation_id'] as num).toInt(),
    );
  }
}
