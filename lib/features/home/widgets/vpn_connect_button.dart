import 'package:flutter/material.dart';

/// What the big round button is currently showing.
enum VpnButtonPhase { idle, connecting, connected, error }

/// Big round connect / disconnect button:
/// soft halo disc -> thin ring -> dark core with a shield and a caption
/// ("TAP TO CONNECT" when off, "DISCONNECT" when on).
///
/// Everything is drawn from [color], so it follows the user's theme colour
/// (idle) and the status colours (connecting / connected / error) that the
/// home screen already uses.
class VpnConnectButton extends StatelessWidget {
  const VpnConnectButton({
    super.key,
    required this.phase,
    required this.color,
    required this.isDark,
    required this.label,
    required this.onTap,
    this.pulse = 1.0,
    this.size = 250,
  });

  final VpnButtonPhase phase;
  final Color color;
  final bool isDark;
  final String label;
  final VoidCallback onTap;

  /// Scale of the halo (1.0 = rest). Comes from the home screen's animation.
  final double pulse;

  /// Width and height of the whole button area.
  final double size;

  IconData get _icon {
    switch (phase) {
      case VpnButtonPhase.connected:
        return Icons.verified_user_rounded;
      case VpnButtonPhase.error:
        return Icons.gpp_bad_outlined;
      case VpnButtonPhase.idle:
      case VpnButtonPhase.connecting:
        return Icons.shield_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final halo = size * 0.80; // grows up to x1.2 -> stays inside [size]
    final ring = size * 0.656;
    final core = size * 0.528;

    final connected = phase == VpnButtonPhase.connected;
    final coreBg = isDark ? const Color(0xFF0B0B0B) : Colors.white;
    // Keep the caption readable on a white core in light mode.
    final textColor =
        isDark ? color : Color.alphaBlend(Colors.black.withValues(alpha: 0.35), color);

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. soft translucent halo (breathes with [pulse])
              Transform.scale(
                scale: pulse,
                child: Container(
                  width: halo,
                  height: halo,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        color.withValues(alpha: isDark ? 0.10 : 0.06),
                        color.withValues(alpha: isDark ? 0.34 : 0.22),
                      ],
                      stops: const [0.55, 1.0],
                    ),
                  ),
                ),
              ),

              // 2. thin ring
              Container(
                width: ring,
                height: ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
              ),

              // 3. spinner on the ring while connecting
              if (phase == VpnButtonPhase.connecting)
                SizedBox(
                  width: ring,
                  height: ring,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),

              // 4. dark (or white) core with a glow
              Container(
                width: core,
                height: core,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: coreBg,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: connected ? 0.55 : 0.30),
                      blurRadius: connected ? 30 : 20,
                      spreadRadius: connected ? 3 : 1,
                    ),
                  ],
                ),
              ),

              // 5. shield + caption
              SizedBox(
                width: core * 0.86,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon, size: size * 0.20, color: color),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
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
