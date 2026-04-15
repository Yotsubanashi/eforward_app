import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/components/bottom_navigator.dart';
import 'package:eforward_app/pages/approvals/approval_details.dart';
import 'package:eforward_app/services/notifications_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with WidgetsBindingObserver {
  final int _selectedIndex = 2;
  static const String _baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  late NotificationsService _notificationsService;
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = false;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _totalPages = 1;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationsService = NotificationsService();
    _scrollController.addListener(_onScroll);
    _fetchNotifications();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[Notifications] App resumed — refreshing data...');
      setState(() {
        _notifications = [];
        _currentPage = 1;
        _hasMore = true;
      });
      _fetchNotifications();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isFetchingMore &&
        _hasMore) {
      _fetchMore();
    }
  }

  Future<void> _fetchMore() async {
    if (_currentPage >= _totalPages) return;
    setState(() => _isFetchingMore = true);
    await _fetchNotifications(page: _currentPage + 1, append: true);
    setState(() => _isFetchingMore = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchNotifications({int page = 1, bool append = false}) async {
    if (!append) setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/notifications?page=$page&limit=10'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final notificationsList =
            (decoded['data'] as List?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [];

        final pagination = decoded['pagination'] as Map<String, dynamic>? ?? {};
        final totalPages = pagination['totalPages'] as int? ?? 1;

        setState(() {
          if (append) {
            _notifications.addAll(notificationsList);
          } else {
            _notifications = notificationsList;
          }
          _currentPage = page;
          _totalPages = totalPages;
          _hasMore = page < totalPages;
          _isLoading = false;
          _lastUpdated = DateTime.now();
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Notifications fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    final success = await _notificationsService.markAsRead(notificationId);
    if (success) {
      setState(() {
        final index = _notifications.indexWhere(
          (n) => n['notification_id'] == notificationId,
        );
        if (index != -1) {
          _notifications[index]['is_read'] = true;
        }
      });
    }
  }

  Future<void> _markAllAsRead() async {
    final success = await _notificationsService.markAllAsRead();
    if (success && mounted) {
      setState(() {
        for (var notification in _notifications) {
          notification['is_read'] = true;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n['is_read']).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _notifications = [];
              _currentPage = 1;
              _hasMore = true;
            });
            await _fetchNotifications();
          },
          color: const Color(0xFFCC0000),
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                const Text(
                  "NOTIFICATIONS",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Color(0xFF1A1A1A),
                  ),
                ),

                const SizedBox(height: 12),

                // Unread count + Mark All Read
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      unreadCount > 0
                          ? '$unreadCount unread notification${unreadCount != 1 ? 's' : ''}'
                          : 'All caught up!',
                      style: TextStyle(
                        fontSize: 12,
                        color: unreadCount > 0
                            ? const Color(0xFFCC0000)
                            : Colors.black54,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (unreadCount > 0)
                      GestureDetector(
                        onTap: _markAllAsRead,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFCC0000),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            "MARK ALL READ",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                // Notifications list
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(
                        color: Color(0xFFCC0000),
                      ),
                    ),
                  )
                else if (_notifications.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE8E8E8)),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 48,
                          color: Colors.black12,
                        ),
                        SizedBox(height: 12),
                        Text(
                          "No notifications",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildNotificationCard(_notifications[index]),
                  ),

                // Bottom loader / end message
                if (_isFetchingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFCC0000),
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (!_hasMore && _notifications.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        "— You're all caught up —",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black38,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigator(
        selectedIndex: _selectedIndex,
        onTap: (_) {},
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = notification['is_read'] as bool? ?? true;
    final notificationId = notification['notification_id']?.toString() ?? '';
    final header = notification['header']?.toString() ?? '';
    final detail = notification['detail']?.toString() ?? '';
    final link = notification['link']?.toString() ?? '';

    return InkWell(
      onTap: () {
        if (!isRead) {
          _markAsRead(notificationId);
        }

        if (link.isNotEmpty) {
          final parts = link.split('/');
          if (parts.length >= 3 && parts[1] == 'approvals') {
            final tempItem = {
              'routing_id': parts[2],
              'header': header,
              'detail': detail,
            };
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ApprovalDetailPage(item: tempItem),
              ),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFFFF5F5),
          border: Border.all(
            color: isRead ? const Color(0xFFE8E8E8) : const Color(0xFFCC0000),
            width: isRead ? 1 : 2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread indicator
            if (!isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFFCC0000),
                  shape: BoxShape.circle,
                ),
              )
            else
              const SizedBox(width: 20),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    header,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Color(isRead ? 0xFF1A1A1A : 0xFFCC0000),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isRead)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GestureDetector(
                        onTap: () => _markAsRead(notificationId),
                        child: const Text(
                          "Mark as read",
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFFCC0000),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Chevron
            const Icon(Icons.chevron_right, color: Colors.black26, size: 18),
          ],
        ),
      ),
    );
  }
}