import 'package:flutter/material.dart';

class FlagIcon extends StatelessWidget {
  final String countryCode;
  final double size;

  const FlagIcon({super.key, required this.countryCode, this.size = 24.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: _buildFlag(countryCode),
      ),
    );
  }

  Widget _buildFlag(String code) {
    // Using emoji flags with gradient backgrounds
    final flagData = _getFlagData(code);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: flagData['colors'] as List<Color>,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Text(
          flagData['emoji'] as String,
          style: TextStyle(fontSize: size * 0.7),
        ),
      ),
    );
  }

  Map<String, dynamic> _getFlagData(String code) {
    switch (code.toLowerCase()) {
      case 'us':
        return {
          'emoji': '🇺🇸',
          'colors': [const Color(0xFFB22234), const Color(0xFFFFFFFF)],
        };
      case 'es':
        return {
          'emoji': '🇪🇸',
          'colors': [const Color(0xFFC60B1E), const Color(0xFFFFC400)],
        };
      case 'fr':
        return {
          'emoji': '🇫🇷',
          'colors': [const Color(0xFF002395), const Color(0xFFED2939)],
        };
      case 'de':
        return {
          'emoji': '🇩🇪',
          'colors': [
            const Color(0xFF000000),
            const Color(0xFFDD0000),
            const Color(0xFFFFCE00),
          ],
        };
      case 'pt':
        return {
          'emoji': '🇵🇹',
          'colors': [const Color(0xFF046A38), const Color(0xFFDA291C)],
        };
      case 'it':
        return {
          'emoji': '🇮🇹',
          'colors': [const Color(0xFF009246), const Color(0xFFCE2B37)],
        };
      default:
        return {
          'emoji': '🏳️',
          'colors': [Colors.grey, Colors.white],
        };
    }
  }
}
