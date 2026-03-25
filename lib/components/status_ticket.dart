import 'package:flutter/material.dart';
import 'ticket_model.dart';

// ─── Recent Tickets Section ───────────────────────────────────────────────────

class RecentTicketsSection extends StatelessWidget {
  final List<TicketData> tickets;
  

  const RecentTicketsSection({
    super.key,
    required this.tickets,
    
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Documents',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
            
          ],
        ),
        const SizedBox(height: 16),

        // Ticket Cards
        ...tickets.map(
          (ticket) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TicketCard(ticket: ticket),
          ),
        ),
      ],
    );
  }
}

// ─── Ticket Card ──────────────────────────────────────────────────────────────

class TicketCard extends StatelessWidget {
  final TicketData ticket;

  const TicketCard({super.key, required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF242736),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ID + Priority Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                ticket.id,
                style: const TextStyle(
                  color: Color(0xFF6B7CFF),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              _PriorityBadge(priority: ticket.priority),
            ],
          ),
          const SizedBox(height: 6),

          // Title
          Text(
            ticket.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),

          // Created By / Date
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MetaColumn(label: 'CREATED BY', value: ticket.createdBy),
              _MetaColumn(
                label: 'DATE/TIME',
                value: ticket.dateTime,
                align: CrossAxisAlignment.end,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'PROGRESS',
                style: TextStyle(
                  color: Color(0xFF8A8FAD),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${(ticket.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: ticket.progress == 0
                      ? Colors.white
                      : const Color(0xFF4FC3F7),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Progress Bar
          _ProgressBar(value: ticket.progress),
        ],
      ),
    );
  }
}

// ─── Priority Badge ───────────────────────────────────────────────────────────

class _PriorityBadge extends StatelessWidget {
  final TicketPriority priority;

  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (priority) {
      TicketPriority.high => (
          'PRIORITY HIGH',
          const Color(0xFFB03030),
          Colors.white,
        ),
      TicketPriority.standard => (
          'STANDARD',
          const Color(0xFF2A4A6B),
          const Color(0xFF4FC3F7),
        ),
      TicketPriority.low => (
          'LOW',
          const Color(0xFF2A5A3A),
          const Color(0xFF4CAF50),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Meta Column ──────────────────────────────────────────────────────────────

class _MetaColumn extends StatelessWidget {
  final String label;
  final String value;
  final CrossAxisAlignment align;

  const _MetaColumn({
    required this.label,
    required this.value,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8A8FAD),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Progress Bar ─────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final double value;

  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 5,
        backgroundColor: const Color(0xFF3A3D52),
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4FC3F7)),
      ),
    );
  }
}