enum TicketPriority { high, standard, low }

class TicketData {
  final String id;
  final String title;
  final String createdBy;
  final String dateTime;
  final double progress; // 0.0 – 1.0
  final TicketPriority priority;

  const TicketData({
    required this.id,
    required this.title,
    required this.createdBy,
    required this.dateTime,
    required this.progress,
    required this.priority,
  });
}