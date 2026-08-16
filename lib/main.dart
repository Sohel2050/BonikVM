import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/router/app_router.dart';
import 'core/navigation/app_navigator.dart';
import 'core/services/vpn_notification_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/admob_service.dart';
import 'core/services/level_play_service.dart';
import 'core/services/vpn_service.dart';
import 'core/services/purchase_service.dart';
import 'core/services/update_service.dart';
import 'core/api/api_service.dart';
import 'core/localization/app_localizations.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/providers/app_providers.dart';
import 'providers/auth_providers.dart';
import 'shared/widgets/splash_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize dependencies
  await _initializeApp();

  runApp(const ProviderScope(child: AxeVPNApp()));
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  // Initialize with your OneSignal App ID
  OneSignal.initialize("662ec5db-a9df-416a-8585-584d68ec9919");
  // Use this method to prompt for push notifications.
  // We recommend removing this method after testing and instead use In-App Messages to prompt for notification permission.
  OneSignal.Notifications.requestPermission(false);

}

Future<void> _initializeApp() async {
  try {
    // Load environment variables with timeout
    await dotenv
        .load(fileName: ".env")
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('⚠️ Environment variables loading timed out');
          },
        );

    // Initialize Hive for local storage
    await Hive.initFlutter();

    // Initialize Firebase with error handling
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // Continue without Firebase - app can still work
      debugPrint('Firebase initialization error: $e');
    }
    // Initialize Mobile Ads with timeout.
    //
    // 3 seconds was too tight: on a cold start (especially on emulators)
    // MobileAds.instance.initialize() routinely hadn't finished by then, so
    // this timeout fired on essentially every launch, we moved on assuming
    // ads were ready, and every AdMob request made afterward (banner,
    // native, interstitial, rewarded, app open) failed with error code 1
    // (invalid request) because the native SDK genuinely wasn't done
    // initializing yet. 10s gives it a real chance to finish first.
    try {
      final initFuture = MobileAds.instance.initialize();
      await initFuture.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint(
            '⚠️ Mobile Ads initialization timed out - continuing without ads',
          );
          return Future.value(InitializationStatus({}));
        },
      );
      debugPrint('✅ Mobile Ads initialized');
    } catch (e) {
      debugPrint(
        '⚠️ Mobile Ads initialization failed: $e - continuing without ads',
      );
    }

    // Initialize Stripe
    try {
      Stripe.publishableKey = "pk_test_TYooMQauvdEDgjgj00q54NiTphI7jx";
      await Stripe.instance.applySettings();
    } catch (e) {
      debugPrint('⚠️ Stripe initialization failed: $e');
    }

    // Initialize API service (synchronous)
    ApiService.instance.initialize();

    // Initialize VPN service with timeout
    try {
      await VpnService.instance.initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ VPN service initialization timed out');
        },
      );
    } catch (e) {
      debugPrint('⚠️ VPN service initialization failed: $e');
    }

    // Initialize purchase service with timeout
    try {
      await PurchaseService().initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ Purchase service initialization timed out');
        },
      );
    } catch (e) {
      debugPrint('⚠️ Purchase service initialization failed: $e');
    }

    // Initialize AdMob service with timeout
    try {
      await AdMobService.instance.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⚠️ AdMob service initialization timed out');
        },
      );
    } catch (e) {
      debugPrint('⚠️ AdMob service initialization failed: $e');
    }

    // Initialize Unity LevelPlay service with timeout
    try {
      await LevelPlayService.instance
          .initialize(
            androidAppKey: dotenv.env['LEVELPLAY_ANDROID_APP_KEY'],
            iosAppKey: dotenv.env['LEVELPLAY_IOS_APP_KEY'],
            rewardedAdUnitId: dotenv.env['LEVELPLAY_REWARDED_AD_UNIT_ID'],
            interstitialAdUnitId:
                dotenv.env['LEVELPLAY_INTERSTITIAL_AD_UNIT_ID'],
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⚠️ LevelPlay service initialization timed out');
            },
          );
    } catch (e) {
      debugPrint('⚠️ LevelPlay service initialization failed: $e');
    }

    // Initialize VPN notification service
    try {
      await VpnNotificationService().initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ VPN notification service initialization timed out');
        },
      );
    } catch (e) {
      debugPrint('⚠️ VPN notification service initialization failed: $e');
    }

    // Initialize Firebase notification service
    try {
      await NotificationService().initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ Notification service initialization timed out');
        },
      );
    } catch (e) {
      debugPrint('⚠️ Notification service initialization failed: $e');
    }

    // Initialize update service
    try {
      await UpdateService.instance.initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ Update service initialization timed out');
        },
      );
    } catch (e) {
      debugPrint('⚠️ Update service initialization failed: $e');
    }

    // Request permissions with timeout
    try {
      await _requestPermissions().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('⚠️ Permission requests timed out');
        },
      );
    } catch (e) {
      debugPrint('⚠️ Permission requests failed: $e');
    }

    debugPrint('✅ App initialization completed');
  } catch (e) {
    debugPrint('❌ App initialization error: $e');
  }
}

Future<void> _requestPermissions() async {
  // Request VPN permission for Android
  if (await Permission.ignoreBatteryOptimizations.isDenied) {
    await Permission.ignoreBatteryOptimizations.request();
  }

  // Request notification permission
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
}

class AxeVPNApp extends ConsumerStatefulWidget {
  const AxeVPNApp({super.key});

  @override
  ConsumerState<AxeVPNApp> createState() => _AxeVPNAppState();
}

class _AxeVPNAppState extends ConsumerState<AxeVPNApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Show app open ad when user returns to the app
    if (state == AppLifecycleState.resumed) {
      // Re-sync VPN state in case it changed while app was in background
      // (e.g. user tapped Disconnect in notification, or OC/OpenVPN service
      // was killed by the OS).
      ref.read(vpnServiceProvider).resyncVpnState();

      // Re-check ad settings when app resumes
      AdMobService.instance.refreshAdSettings();
      LevelPlayService.instance.refreshPremiumStatus();

      // Show app open ad with a small delay (only if ads are enabled)
      Future.delayed(const Duration(milliseconds: 500), () {
        AdMobService.instance.showAppOpenAd();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final lightTheme = ref.watch(themeDataProvider);
    final darkTheme = ref.watch(darkThemeDataProvider);
    final locale = ref.watch(languageProvider);

    // Listen to auth state changes to clear premium status on logout
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      if (next.status == AuthStatus.unauthenticated &&
          previous?.status == AuthStatus.authenticated) {
        // User logged out - clear premium status
        ref.read(premiumStatusProvider.notifier).clearPremiumStatus();
      }
    });

    return MaterialApp(
      title: 'VPN MASTER',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      themeMode: themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('es', 'ES'),
        Locale('fr', 'FR'),
        Locale('de', 'DE'),
        Locale('pt', 'PT'),
        Locale('it', 'IT'),
      ],
      initialRoute: '/splash',
      onGenerateRoute: AppRouter.generateRoute,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child ?? const SplashScreen(),
        );
      },
    );
  }
}
