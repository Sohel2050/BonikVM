import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';

/// Renders a real flag image (bundled SVGs via `country_flags`) rather than
/// the regional-indicator emoji pair — Windows' default emoji font (Segoe UI
/// Emoji) doesn't compose those into a flag glyph, so on Windows this used
/// to render as two boxed letters (e.g. "DE") instead of an actual flag.
class FlagIcon extends StatelessWidget {
  final String countryCode;
  final double size;

  const FlagIcon({super.key, required this.countryCode, this.size = 24.0});

  @override
  Widget build(BuildContext context) {
    if (countryCode.trim().length != 2) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Colors.grey.shade300,
        ),
        child: Icon(Icons.public, size: size * 0.7, color: Colors.grey.shade600),
      );
    }
    return CountryFlag.fromCountryCode(
      countryCode,
      theme: ImageTheme(
        shape: const RoundedRectangle(4),
        width: size,
        height: size,
      ),
    );
  }
}
