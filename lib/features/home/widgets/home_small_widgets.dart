import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A label/value row with a leading icon, used in the server details bottom
/// sheet on the Home screen.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, this.icon, {super.key});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }
}

/// A single stat tile (icon + value + label) used in the connection stats
/// row on the Home screen.
class StatItem extends StatelessWidget {
  const StatItem({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small decorative wave graph painted under a speed stat card, matching
/// the "VPN Master" style reference design (download = green, upload =
/// orange). Purely visual — not plotted from live samples.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final points = <Offset>[];
    const steps = 5;
    for (int i = 0; i <= steps; i++) {
      final x = size.width * (i / steps);
      final baseline = size.height * 0.55;
      final wobble = (rnd.nextDouble() - 0.3) * size.height * 0.6;
      final y = (baseline - wobble).clamp(size.height * 0.08, size.height);
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}

/// A rounded card showing one speed metric (Download / Upload) with a
/// direction arrow, a big value + unit, and a small wave graph beneath —
/// mirrors the reference "VPN Master" home screen design.
class SpeedStatCard extends StatelessWidget {
  const SpeedStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.isDownload,
    required this.isDarkMode,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final bool isDownload;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF111318) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isDownload
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: isDarkMode ? Colors.white : const Color(0xFF111827),
                    height: 1.0,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 28,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(
                color: color,
                seed: isDownload ? 7 : 19,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat download/upload stat used on the reference-style stats row — an
/// arrow + label on top and a big bold value below, no card or graph.
class SpeedStat extends StatelessWidget {
  const SpeedStat({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.isDownload,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final bool isDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDownload
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              size: 15,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small 4-bar signal-strength glyph shown next to the ping value on the
/// location pill, matching the reference design.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.color, this.activeBars = 3});

  final Color color;
  final int activeBars;

  @override
  Widget build(BuildContext context) {
    const heights = [6.0, 10.0, 14.0, 18.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final active = i < activeBars;
        return Container(
          width: 3,
          height: heights[i],
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: active ? color : color.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }
}

/// Small green "Connected" pill badge shown above the session timer.
class ConnectedPill extends StatelessWidget {
  const ConnectedPill({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Fast & Secure Connection" info banner shown near the bottom of the
/// Home screen, matching the reference design's shield card.
class SecureConnectionBanner extends StatelessWidget {
  const SecureConnectionBanner({
    super.key,
    required this.isDarkMode,
    required this.accentColor,
    this.onTap,
  });

  final bool isDarkMode;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF111318) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE5E7EB),
          ),
        ),

      ),
    );
  }
}

/// Rounded "pill" server/location selector shown at the top of the Home
/// screen connection section — flag, name, subtitle, ping, chevron.
class LocationSelectorPill extends StatelessWidget {
  const LocationSelectorPill({
    super.key,
    required this.flag,
    required this.title,
    required this.subtitle,
    required this.isDarkMode,
    required this.accentColor,
    this.pingText,
    this.onTap,
  });

  final Widget flag;
  final String title;
  final String subtitle;
  final bool isDarkMode;
  final Color accentColor;
  final String? pingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF111318) : Colors.white,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.45),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(width: 34, height: 34, child: flag),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode ? Colors.white : const Color(0xFF111827),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (pingText != null) ...[
              SignalBars(color: accentColor),
              const SizedBox(width: 8),
              Text(
                pingText!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              Icons.chevron_right_rounded,
              color: isDarkMode ? Colors.grey[500] : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}
