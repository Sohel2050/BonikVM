import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import '../../providers/ip_address_provider.dart';

class IpAddressWidget extends ConsumerWidget {
  const IpAddressWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ipAddressAsync = ref.watch(ipAddressProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return FadeInUp(
      delay: const Duration(milliseconds: 300),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode
                ? const Color(0xFF334155)
                : const Color(0xFFE5E7EB),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.06),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ipAddressAsync.when(
          data: (ipData) => Column(
            children: [
              // IP Row
              _InfoRow(
                icon: Icons.language,
                iconColor: const Color(0xFF2563EB),
                label: ipData.ip,
                isDarkMode: isDarkMode,
                trailing: GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: ipData.ip));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('IP address copied'),
                        backgroundColor: const Color(0xFF2563EB),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                  child: Icon(
                    Icons.copy_outlined,
                    size: 16,
                    color: isDarkMode
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ),

              if (ipData.country != null || ipData.city != null) ...[
                Divider(
                  height: 1,
                  color: isDarkMode
                      ? const Color(0xFF334155)
                      : const Color(0xFFF3F4F6),
                ),
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  iconColor: const Color(0xFF10B981),
                  label: [
                    if (ipData.city != null) ipData.city!,
                    if (ipData.country != null) ipData.country!,
                  ].join(', '),
                  isDarkMode: isDarkMode,
                  trailing: ipData.countryCode != null
                      ? Text(
                          _getCountryFlag(ipData.countryCode!),
                          style: const TextStyle(fontSize: 18),
                        )
                      : null,
                ),
              ],

              if (ipData.isp != null) ...[
                Divider(
                  height: 1,
                  color: isDarkMode
                      ? const Color(0xFF334155)
                      : const Color(0xFFF3F4F6),
                ),
                _InfoRow(
                  icon: Icons.business_outlined,
                  iconColor: const Color(0xFF8B5CF6),
                  label: ipData.isp!,
                  isDarkMode: isDarkMode,
                ),
              ],
            ],
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                ),
              ),
            ),
          ),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Failed to load IP',
                    style: TextStyle(fontSize: 13, color: Colors.red),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(ipAddressProvider),
                  child: const Text('Retry', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getCountryFlag(String countryCode) {
    final code = countryCode.toUpperCase();
    return String.fromCharCode(code.codeUnitAt(0) + 127397) +
        String.fromCharCode(code.codeUnitAt(1) + 127397);
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isDarkMode;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isDarkMode,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white : const Color(0xFF111827),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

@override
Widget build(BuildContext context, WidgetRef ref) {
  final ipAddressAsync = ref.watch(ipAddressProvider);
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;

  return FadeInUp(
    delay: const Duration(milliseconds: 300),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1E293B).withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              const Icon(Icons.public, color: Color(0xFF3B82F6), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your IP Address',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                color: const Color(0xFF3B82F6),
                onPressed: () {
                  ref.invalidate(ipAddressProvider);
                },
                tooltip: 'Refresh',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // IP Address Display
          ipAddressAsync.when(
            data: (ipData) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // IP Address
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          ipData.ip,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3B82F6),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        color: const Color(0xFF3B82F6),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: ipData.ip));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('IP copied'),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        },
                        tooltip: 'Copy',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Location Info
                if (ipData.country != null || ipData.city != null)
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            if (ipData.city != null) ipData.city!,
                            if (ipData.country != null) ipData.country!,
                          ].join(', '),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ),
                      ),
                      if (ipData.countryCode != null)
                        Text(
                          _getCountryFlag(ipData.countryCode!),
                          style: const TextStyle(fontSize: 16),
                        ),
                    ],
                  ),

                // ISP Info
                if (ipData.isp != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.business_outlined,
                        size: 14,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ipData.isp!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            loading: () => Container(
              padding: const EdgeInsets.all(16),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF3B82F6),
                    ),
                  ),
                ),
              ),
            ),
            error: (error, stack) => Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Failed to load IP',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(ipAddressProvider),
                    child: const Text('Retry', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _getCountryFlag(String countryCode) {
  final code = countryCode.toUpperCase();
  return String.fromCharCode(code.codeUnitAt(0) + 127397) +
      String.fromCharCode(code.codeUnitAt(1) + 127397);
}
