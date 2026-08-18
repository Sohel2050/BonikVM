import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const Color _background = Color(0xFFF7F9FC);
  static const Color _primary = Color(0xFF2563EB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

  static const List<_OnboardingData> _pages = [
    _OnboardingData(
      icon: Icons.shield_rounded,
      accent: Color(0xFF2563EB),
      soft: Color(0xFFEAF2FF),
      title: 'Your Privacy,\nAlways Protected',
      subtitle:
      'Keep your online activity private with secure encryption and trusted VPN protection.',
    ),
    _OnboardingData(
      icon: Icons.speed_rounded,
      accent: Color(0xFF10B981),
      soft: Color(0xFFEAFBF5),
      title: 'Fast & Reliable\nConnections',
      subtitle:
      'Choose from global servers and enjoy a smooth connection for browsing, streaming and more.',
    ),
    _OnboardingData(
      icon: Icons.public_rounded,
      accent: Color(0xFF7C3AED),
      soft: Color(0xFFF3EEFF),
      title: 'Explore The Internet\nWithout Limits',
      subtitle:
      'Connect securely from anywhere and enjoy a safer, more private online experience.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 18, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 14,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/icon/icon.png',
                      width: 22,
                      height: 22,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'VPN MASTER',
                    style: TextStyle(
                      color: _text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  if (!isLast)
                    TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: _muted,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Main pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  if (mounted) {
                    setState(() => _currentPage = index);
                  }
                },
                itemBuilder: (context, index) {
                  return _OnboardingPage(data: _pages[index]);
                },
              ),
            ),

            // Bottom controls
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                          (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                        width: index == _currentPage ? 28 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: index == _currentPage
                              ? page.accent
                              : const Color(0xFFD9DEE8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Main CTA
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(17),
                        boxShadow: [
                          BoxShadow(
                            color: page.accent.withValues(alpha: 0.24),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: page.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isLast ? 'Get Started' : 'Continue',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Icon(
                              isLast
                                  ? Icons.arrow_forward_rounded
                                  : Icons.chevron_right_rounded,
                              size: 21,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_currentPage + 1} of ${_pages.length}',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});

  final _OnboardingData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Decorative illustration area
          SizedBox(
            width: 250,
            height: 250,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: data.soft,
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 172,
                  height: 172,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: data.accent.withValues(alpha: 0.12),
                        blurRadius: 28,
                        spreadRadius: 2,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    color: data.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: data.accent.withValues(alpha: 0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    data.icon,
                    color: Colors.white,
                    size: 58,
                  ),
                ),
                Positioned(
                  top: 24,
                  right: 27,
                  child: _Dot(
                    color: data.accent,
                    size: 11,
                  ),
                ),
                Positioned(
                  bottom: 30,
                  left: 24,
                  child: _Dot(
                    color: data.accent.withValues(alpha: 0.55),
                    size: 7,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _OnboardingScreenState._text,
              fontSize: 29,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 16),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 355),
            child: Text(
              data.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _OnboardingScreenState._muted,
                fontSize: 15.5,
                fontWeight: FontWeight.w400,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _OnboardingData {
  const _OnboardingData({
    required this.icon,
    required this.accent,
    required this.soft,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color accent;
  final Color soft;
  final String title;
  final String subtitle;
}
