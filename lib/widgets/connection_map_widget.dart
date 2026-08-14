import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:country_flags/country_flags.dart';
import '../core/services/vpn_state.dart';
import '../shared/providers/app_providers.dart';
import '../shared/providers/theme_provider.dart';
import '../providers/ip_address_provider.dart';

class ConnectionMapWidget extends ConsumerStatefulWidget {
  const ConnectionMapWidget({super.key});

  @override
  ConsumerState<ConnectionMapWidget> createState() => _ConnectionMapWidgetState();
}

class _ConnectionMapWidgetState extends ConsumerState<ConnectionMapWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pathAnimationController;

  @override
  void initState() {
    super.initState();
    _pathAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // Run animation continuously to animate the connection flow
    _pathAnimationController.repeat();
  }

  @override
  void dispose() {
    _pathAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vpnStateAsync = ref.watch(vpnStateProvider);
    final vpnState = vpnStateAsync.value ?? VpnState.disconnected;
    final currentServer = ref.watch(currentServerProvider);
    final ipAddressAsync = ref.watch(ipAddressProvider);
    final themeColor = ref.watch(themeColorProvider);

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final isConnecting = vpnState == VpnState.connecting ||
        vpnState == VpnState.waitConnection ||
        vpnState == VpnState.authenticating ||
        vpnState == VpnState.preparing;
    final isConnected = vpnState == VpnState.connected;

    // ipAddressProvider always reflects the current public IP — while
    // connected that's the VPN server's own exit IP, not the user's real
    // location. Cache it whenever we observe it outside an active VPN
    // session so the "Your Location" card keeps showing where the user
    // actually is instead of drifting to match the destination card.
    if (!isConnected && !isConnecting && ipAddressAsync.hasValue) {
      final observed = ipAddressAsync.value!;
      if (ref.read(originalLocationProvider) != observed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(originalLocationProvider.notifier).state = observed;
        });
      }
    }

    // Get source info: prefer the cached real (pre-VPN) location; fall
    // back to the live lookup only if we've never captured one yet.
    String sourceCountry = 'My Location';
    String sourceCountryCode = '';
    String sourceIp = '...';

    final info = ref.watch(originalLocationProvider) ?? ipAddressAsync.value;
    if (info != null) {
      sourceIp = info.ip;
      sourceCountry = info.country ?? 'My Location';
      sourceCountryCode = info.countryCode ?? '';
    }

    // Get destination info
    String destName = currentServer?.name ?? 'Not Selected';
    String destCountry = currentServer?.country ?? 'Select Server';
    String destCountryCode = currentServer?.countryCode ?? '';
    String destIp = currentServer?.ip ?? '';

    return Container(
      height: 190,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        children: [
          // Programmatic globe / grid map background + animated connection curve
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pathAnimationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _TechMapPainter(
                    isDarkMode: isDarkMode,
                    themeColor: themeColor,
                    isConnecting: isConnecting,
                    isConnected: isConnected,
                    animationValue: _pathAnimationController.value,
                  ),
                );
              },
            ),
          ),

          // Layout the source (left) and destination (right) cards
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Source Card (User Node)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildNodeCard(
                      title: 'Your Location',
                      subtitle: sourceCountry,
                      ip: sourceIp,
                      flagCode: sourceCountryCode,
                      isSource: true,
                      isConnected: isConnected || isConnecting,
                      isDarkMode: isDarkMode,
                      themeColor: themeColor,
                    ),
                  ),
                ),

                const SizedBox(width: 60), // Space for connection arc

                // Destination Card (Server Node)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildNodeCard(
                      title: isConnected ? 'Connected' : 'VPN Location',
                      subtitle: destCountry,
                      ip: destIp.isNotEmpty ? destIp : 'Not Connected',
                      flagCode: destCountryCode,
                      isSource: false,
                      isConnected: isConnected,
                      isDarkMode: isDarkMode,
                      themeColor: themeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard({
    required String title,
    required String subtitle,
    required String ip,
    required String flagCode,
    required bool isSource,
    required bool isConnected,
    required bool isDarkMode,
    required Color themeColor,
  }) {
    final activeColor = isConnected
        ? (isSource ? themeColor : const Color(0xFF10B981))
        : Colors.grey;

    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1E293B).withOpacity(0.85)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? activeColor.withOpacity(0.4)
              : (isDarkMode ? const Color(0xFF334155) : const Color(0xFFE5E7EB)),
          width: isConnected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isConnected
                ? activeColor.withOpacity(0.12)
                : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Flag representation
              Container(
                width: 26,
                height: 26,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF3F4F6),
                  shape: BoxShape.circle,
                ),
                child: flagCode.trim().length == 2
                    ? CountryFlag.fromCountryCode(
                        flagCode,
                        theme: const ImageTheme(shape: Circle()),
                      )
                    : const Icon(Icons.location_on, size: 15, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: activeColor,
                    letterSpacing: 0.2,
                    height: 1.15,
                  ),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? Colors.white : const Color(0xFF1F2937),
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            ip,
            style: TextStyle(
              fontSize: 10,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TechMapPainter extends CustomPainter {
  final bool isDarkMode;
  final Color themeColor;
  final bool isConnecting;
  final bool isConnected;
  final double animationValue;

  _TechMapPainter({
    required this.isDarkMode,
    required this.themeColor,
    required this.isConnecting,
    required this.isConnected,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = isDarkMode
          ? Colors.blueGrey.withOpacity(0.08)
          : Colors.grey.withOpacity(0.12)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw tech background ovals / global coordinates
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 1; i <= 3; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: size.width * (0.3 * i),
          height: size.height * (0.45 * i),
        ),
        gridPaint,
      );
    }

    // Draw simple latitude / longitude grid lines
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      gridPaint,
    );

    // Source and Destination positions for connection line
    final startPoint = Offset(70, size.height / 2);
    final endPoint = Offset(size.width - 70, size.height / 2);

    // Control point for curved bezier line
    final controlPoint = Offset(size.width / 2, size.height / 2 - 60);

    final path = Path()
      ..moveTo(startPoint.dx, startPoint.dy)
      ..quadraticBezierTo(controlPoint.dx, controlPoint.dy, endPoint.dx, endPoint.dy);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (isConnected) {
      // Solid/Glow curve when connected
      linePaint.color = const Color(0xFF10B981).withOpacity(0.8);
      linePaint.strokeWidth = 2.5;

      // Draw subtle glow behind active line
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF10B981).withOpacity(0.15)
        ..strokeWidth = 7.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, linePaint);

      // Animate flowing pulses along the path
      _drawPulseOnPath(canvas, startPoint, controlPoint, endPoint, const Color(0xFF10B981));
    } else if (isConnecting) {
      // Dashed moving line during connection
      linePaint.color = themeColor.withOpacity(0.8);
      linePaint.strokeWidth = 2.0;

      // Draw dashes programmatically using interpolation
      _drawDashedBezier(canvas, startPoint, controlPoint, endPoint, linePaint, dashLength: 6, spaceLength: 4);

      // Pulse traveling fast
      _drawPulseOnPath(canvas, startPoint, controlPoint, endPoint, themeColor, speedMultiplier: 1.5);
    } else {
      // Faded thin dashed curve when disconnected
      linePaint.color = isDarkMode ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08);
      linePaint.strokeWidth = 1.5;
      _drawDashedBezier(canvas, startPoint, controlPoint, endPoint, linePaint, dashLength: 4, spaceLength: 6);
    }
  }

  void _drawDashedBezier(
    Canvas canvas,
    Offset start,
    Offset control,
    Offset end,
    Paint paint, {
    required double dashLength,
    required double spaceLength,
  }) {
    // Total segments approximation
    const int segments = 100;
    double accumulatedLength = 0;
    bool draw = true;

    Offset previousPoint = start;

    for (int i = 1; i <= segments; i++) {
      final double t = i / segments;
      // Quadratic Bezier interpolation formula: B(t) = (1-t)^2 * P0 + 2*(1-t)*t * P1 + t^2 * P2
      final double x = pow(1 - t, 2) * start.dx + 2 * (1 - t) * t * control.dx + pow(t, 2) * end.dx;
      final double y = pow(1 - t, 2) * start.dy + 2 * (1 - t) * t * control.dy + pow(t, 2) * end.dy;
      final currentPoint = Offset(x, y);

      final distance = (currentPoint - previousPoint).distance;
      accumulatedLength += distance;

      if (draw) {
        if (accumulatedLength >= dashLength) {
          canvas.drawLine(previousPoint, currentPoint, paint);
          accumulatedLength = 0;
          draw = false;
        } else {
          canvas.drawLine(previousPoint, currentPoint, paint);
        }
      } else {
        if (accumulatedLength >= spaceLength) {
          accumulatedLength = 0;
          draw = true;
        }
      }
      previousPoint = currentPoint;
    }
  }

  void _drawPulseOnPath(
    Canvas canvas,
    Offset start,
    Offset control,
    Offset end,
    Color color, {
    double speedMultiplier = 1.0,
  }) {
    // Determine target location along bezier using animation value
    final double t = (animationValue * speedMultiplier) % 1.0;

    // Quadratic Bezier interpolation point
    final double x = pow(1 - t, 2) * start.dx + 2 * (1 - t) * t * control.dx + pow(t, 2) * end.dx;
    final double y = pow(1 - t, 2) * start.dy + 2 * (1 - t) * t * control.dy + pow(t, 2) * end.dy;
    final pulsePoint = Offset(x, y);

    // Glowing active particle
    final pulsePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);

    canvas.drawCircle(pulsePoint, 8.0, glowPaint);
    canvas.drawCircle(pulsePoint, 3.5, pulsePaint);
  }

  @override
  bool shouldRepaint(covariant _TechMapPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.themeColor != themeColor ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.isConnecting != isConnecting;
  }
}
