import 'package:flutter/material.dart';

import 'status_pill.dart';

/// Approval row shown in lists across the app (approvals pending/history
/// tabs, dashboard recent activity) — previously the dashboard hand-rolled
/// its own near-identical copy of this card instead of reusing it.
class ApprovalCard extends StatelessWidget {
  const ApprovalCard({
    super.key,
    required this.item,
    required this.isPending,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final bool isPending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = item['status']?.toString() ?? 'PND';
    final refNo = item['referenceNo']?.toString().isNotEmpty == true
        ? item['referenceNo'].toString()
        : item['id']?.toString() ?? '—';
    final particulars = item['particulars']?.toString().isNotEmpty == true
        ? item['particulars'].toString()
        : '—';
    final requester = item['requester']?.toString() ?? '—';
    final dateSent = item['dateSent']?.toString().isNotEmpty == true
        ? item['dateSent'].toString()
        : '—';

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: status == 'CNL' ? 0.5 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                  border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCC0000),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        refNo,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Color(0xFFCC0000),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(status: status),
                  ],
                ),
              ),

              // ── Body ───────────────────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      particulars,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: 0.2,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Requester
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFEEEEEE),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.person_outline,
                                  size: 13,
                                  color: Color(0xFF999999),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  requester,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF555555),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Date
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 11,
                              color: Color(0xFFAAAAAA),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dateSent,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFAAAAAA),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Footer ─────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(8),
                  ),
                  border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isPending
                          ? 'Tap to review & take action'
                          : 'Tap to view details',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFBBBBBB),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Color(0xFFCC0000),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
