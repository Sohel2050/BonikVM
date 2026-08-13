import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/theme_provider.dart';
import '../../core/services/notification_service.dart';
import '../../core/models/app_notification.dart';

class AdminNotificationsScreen extends ConsumerStatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  ConsumerState<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState
    extends ConsumerState<AdminNotificationsScreen> {
  final NotificationService _notificationService = NotificationService();
  List<AppNotification> _notifications = [];
  bool _isLoading = true;
  late StreamSubscription<List<AppNotification>> _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _loadNotifications();

    // Listen to notification stream for real-time updates
    _notificationSubscription = _notificationService.notificationStream.listen((
      notifications,
    ) {
      if (mounted) {
        setState(() {
          _notifications = notifications;
        });
      }
    });
  }

  Future<void> _loadNotifications() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final notifications = await _notificationService.getNotifications();
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load notifications: $e')),
        );
      }
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await _notificationService.deleteNotification(notificationId);
      setState(() {
        _notifications.removeWhere((n) => n.id == notificationId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete notification: $e')),
        );
      }
    }
  }

  Future<void> _deleteAllNotifications() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Notifications'),
        content: const Text(
          'Are you sure you want to delete all notifications? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _notificationService.deleteAllNotifications();
        setState(() {
          _notifications.clear();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All notifications deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete notifications: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider) == ThemeMode.dark;
    final themeColor = ref.watch(themeColorProvider);

    return Scaffold(
      backgroundColor: isDarkMode
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('App Notifications'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDarkMode ? Colors.white : Colors.black,
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _deleteAllNotifications,
              tooltip: 'Delete All',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? _buildEmptyState(isDarkMode)
          : _buildNotificationsList(isDarkMode, themeColor),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off,
            size: 80,
            color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Notifications',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You don\'t have any notifications yet.',
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadNotifications,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ref.watch(themeColorProvider),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsList(bool isDarkMode, Color themeColor) {
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      color: themeColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          return _buildNotificationCard(notification, isDarkMode, themeColor);
        },
      ),
    );
  }

  Widget _buildNotificationCard(
    AppNotification notification,
    bool isDarkMode,
    Color themeColor,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: isDarkMode ? 4 : 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            _showNotificationDetail(notification, isDarkMode, themeColor),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getNotificationIcon(notification.type),
                      color: themeColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        if (notification.type.isNotEmpty)
                          Text(
                            notification.type.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              color: themeColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!notification.isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: themeColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                    onPressed: () => _deleteNotification(notification.id),
                    tooltip: 'Delete',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                notification.body,
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: isDarkMode ? Colors.grey[500] : Colors.grey[400],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDateTime(notification.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? Colors.grey[500] : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationDetail(
    AppNotification notification,
    bool isDarkMode,
    Color themeColor,
  ) {
    // Mark as read when opened
    if (!notification.isRead) {
      _notificationService.markNotificationAsRead(notification.id).then((_) {
        if (mounted) {
          setState(() {
            final idx = _notifications.indexWhere(
              (n) => n.id == notification.id,
            );
            if (idx != -1) {
              _notifications[idx] = _notifications[idx].copyWith(isRead: true);
            }
          });
        }
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationDetailSheet(
        notification: notification,
        isDarkMode: isDarkMode,
        themeColor: themeColor,
        getIcon: _getNotificationIcon,
        formatDateTime: _formatDateTime,
        onDelete: () {
          Navigator.pop(context);
          _deleteNotification(notification.id);
        },
      ),
    );
  }

  IconData _getNotificationIcon(String type) {
    switch (type.toLowerCase()) {
      case 'vpn':
        return Icons.vpn_key;
      case 'security':
        return Icons.security;
      case 'update':
        return Icons.system_update;
      case 'promotion':
        return Icons.local_offer;
      case 'maintenance':
        return Icons.build;
      default:
        return Icons.notifications;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  @override
  void dispose() {
    _notificationSubscription.cancel();
    super.dispose();
  }
}

// ─── Notification Detail Bottom Sheet ─────────────────────────────────────────

class _NotificationDetailSheet extends StatelessWidget {
  const _NotificationDetailSheet({
    required this.notification,
    required this.isDarkMode,
    required this.themeColor,
    required this.getIcon,
    required this.formatDateTime,
    required this.onDelete,
  });

  final AppNotification notification;
  final bool isDarkMode;
  final Color themeColor;
  final IconData Function(String) getIcon;
  final String Function(DateTime) formatDateTime;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
    final titleColor = isDarkMode ? Colors.white : const Color(0xFF111827);
    final bodyColor = isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700;
    final mutedColor = isDarkMode ? Colors.grey.shade500 : Colors.grey.shade500;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? Colors.grey.shade600
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      getIcon(notification.type),
                      color: themeColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          notification.type.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: themeColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: mutedColor,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Divider(
              color: isDarkMode
                  ? const Color(0xFF334155)
                  : Colors.grey.shade200,
              height: 1,
            ),
            // Scrollable body
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                children: [
                  // Message body
                  Text(
                    notification.body,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: bodyColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Meta info
                  _MetaRow(
                    icon: Icons.access_time_rounded,
                    label: 'Received',
                    value: formatDateTime(notification.createdAt),
                    isDarkMode: isDarkMode,
                    themeColor: themeColor,
                  ),
                  const SizedBox(height: 10),
                  _MetaRow(
                    icon: notification.isRead
                        ? Icons.mark_email_read_outlined
                        : Icons.mark_email_unread_outlined,
                    label: 'Status',
                    value: notification.isRead ? 'Read' : 'Unread',
                    isDarkMode: isDarkMode,
                    themeColor: themeColor,
                    valueColor: notification.isRead
                        ? Colors.green
                        : Colors.orange,
                  ),
                  if (notification.data != null &&
                      notification.data!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: mutedColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDarkMode
                              ? const Color(0xFF334155)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Text(
                        notification.data!.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join('\n'),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          fontFamily: 'monospace',
                          color: mutedColor,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Delete button
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete Notification'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      side: BorderSide(color: Colors.red.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDarkMode,
    required this.themeColor,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDarkMode;
  final Color themeColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final mutedColor = isDarkMode ? Colors.grey.shade500 : Colors.grey.shade500;
    return Row(
      children: [
        Icon(icon, size: 16, color: themeColor),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontSize: 13, color: mutedColor)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color:
                valueColor ??
                (isDarkMode ? Colors.white70 : const Color(0xFF374151)),
          ),
        ),
      ],
    );
  }
}
