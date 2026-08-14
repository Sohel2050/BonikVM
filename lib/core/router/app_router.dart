import 'package:flutter/material.dart';

import '../../shared/widgets/splash_screen.dart';
import '../../shared/widgets/main_shell.dart';
import '../../features/about/about_screen.dart';
import '../../features/support/support_screen.dart';
import '../../features/debug/vpn_debug_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/settings/admin_notifications_screen.dart';
import '../../features/privacy/privacy_policy_screen.dart';
import '../../features/terms/terms_of_service_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
      case '/splash':
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
      case '/home':
        return MaterialPageRoute(
          builder: (_) => const MainShell(),
          settings: settings,
        );
      case '/servers':
        return MaterialPageRoute(
          builder: (_) => const MainShell(initialIndex: 1),
          settings: settings,
        );
      case '/premium':
        return MaterialPageRoute(
          builder: (_) => const MainShell(initialIndex: 2),
          settings: settings,
        );
      case '/settings':
        return MaterialPageRoute(
          builder: (_) => const MainShell(initialIndex: 3),
          settings: settings,
        );
      case '/about':
        return MaterialPageRoute(
          builder: (_) => const AboutScreen(),
          settings: settings,
        );
      case '/privacy':
        return MaterialPageRoute(
          builder: (_) => const PrivacyPolicyScreen(),
          settings: settings,
        );
      case '/terms':
        return MaterialPageRoute(
          builder: (_) => const TermsOfServiceScreen(),
          settings: settings,
        );
      case '/support':
        return MaterialPageRoute(
          builder: (_) => const SupportScreen(),
          settings: settings,
        );
      case '/debug':
        return MaterialPageRoute(
          builder: (_) => const VpnDebugScreen(),
          settings: settings,
        );
      case '/onboarding':
        return MaterialPageRoute(
          builder: (_) => const OnboardingScreen(),
          settings: settings,
        );
      case '/notifications':
        return MaterialPageRoute(
          builder: (_) => const AdminNotificationsScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Page not found'))),
        );
    }
  }
}
