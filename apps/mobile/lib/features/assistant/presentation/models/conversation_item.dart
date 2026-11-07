class ConversationItem {
  final int id;
  final int? userId;
  final String title;
  final String? summary;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ConversationItem({
    required this.id,
    this.userId,
    required this.title,
    this.summary,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConversationItem.fromJson(Map<String, dynamic> json) {
    final rawSummary = json['summary'] as String?;
    final rawTitle = (json['title'] as String?)?.trim();
    final displayTitle = (rawTitle != null && rawTitle.isNotEmpty)
        ? rawTitle
        : 'Cuộc trò chuyện #${json['id']}';

    return ConversationItem(
      id: json['id'] as int,
      userId: json['user_id'] as int?,
      title: displayTitle,
      summary: rawSummary,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

