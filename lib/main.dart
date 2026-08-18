import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'shared/widgets/force_update_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeApp();

  UpdateInfo? forceUpdateInfo;

  try {
    final status =
    await UpdateService.checkForceUpdateStatus();

    if (status.isRequired) {
      forceUpdateInfo = status.updateInfo;
    }
  } catch (e) {
    debugPrint(
      'Force update check failed: $e',
    );
  }

  runApp(
    ProviderScope(
      child: VPNMasterApp(
        forceUpdateInfo: forceUpdateInfo,
      ),
    ),
  );

  try {
    OneSignal.Debug.setLogLevel(
      OSLogLevel.verbose,
    );

    OneSignal.initialize(
      '662ec5db-a9df-416a-8585-584d68ec9919',
    );

    OneSignal.Notifications.requestPermission(
      false,
    );
  } catch (e) {
    debugPrint(
      'OneSignal initialization failed: $e',
    );
  }
}

Future<void> _initializeApp() async {
  try {
    await dotenv
        .load(
      fileName: '.env',
    )
        .timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
  } catch (e) {
    debugPrint(
      'dotenv error: $e',
    );
  }

  try {
    await Hive.initFlutter();
  } catch (e) {
    debugPrint(
      'Hive error: $e',
    );
  }

  // Firebase is still used by your existing app.
  // It is NOT used for Force Update.
  try {
    await Firebase.initializeApp(
      options:
      DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint(
      'Firebase initialization error: $e',
    );
  }

  try {
    Stripe.publishableKey =
    'pk_test_TYooMQauvdEDgjgj00q54NiTphI7jx';

    await Stripe.instance.applySettings();
  } catch (e) {
    debugPrint(
      'Stripe initialization failed: $e',
    );
  }

  try {
    ApiService.instance.initialize();
  } catch (e) {
    debugPrint(
      'API initialization failed: $e',
    );
  }

  try {
    await VpnService.instance.initialize().timeout(
      const Duration(seconds: 3),
    );
  } catch (e) {
    debugPrint(
      'VPN service initialization failed: $e',
    );
  }

  try {
    await PurchaseService()
        .initialize()
        .timeout(
      const Duration(seconds: 5),
    );
  } catch (e) {
    debugPrint(
      'Purchase service initialization failed: $e',
    );
  }

  try {
    await LevelPlayService.instance
        .initialize(
        androidAppKey:
        dotenv.env['LEVELPLAY_ANDROID_APP_KEY'],
        iosAppKey:
        dotenv.env['LEVELPLAY_IOS_APP_KEY'],
        rewardedAdUnitId:
        dotenv.env['LEVELPLAY_REWARDED_AD_UNIT_ID'],
        interstitialAdUnitId:
        dotenv.env['LEVELPLAY_INTERSTITIAL_AD_UNIT_ID'],
      bannerAdUnitId:
      dotenv.env['LEVELPLAY_BANNER_AD_UNIT_ID'],
      nativeAdUnitId:
      dotenv.env['LEVELPLAY_NATIVE_AD_UNIT_ID'],
    )
        .timeout(
      const Duration(seconds: 5),
    );
  } catch (e) {
    debugPrint(
      'LevelPlay initialization failed: $e',
    );
  }

  try {
    await VpnNotificationService()
        .initialize()
        .timeout(
      const Duration(seconds: 3),
    );
  } catch (e) {
    debugPrint(
      'VPN notification initialization failed: $e',
    );
  }

  try {
    await NotificationService()
        .initialize()
        .timeout(
      const Duration(seconds: 3),
    );
  } catch (e) {
    debugPrint(
      'Notification initialization failed: $e',
    );
  }

  // Google Play update service.
  try {
    await UpdateService.instance
        .initialize()
        .timeout(
      const Duration(seconds: 3),
    );
  } catch (e) {
    debugPrint(
      'Update service initialization failed: $e',
    );
  }

  try {
    await _requestPermissions().timeout(
      const Duration(seconds: 2),
    );
  } catch (e) {
    debugPrint(
      'Permission request failed: $e',
    );
  }

  debugPrint(
    'App initialization completed',
  );
}

Future<void> _requestPermissions() async {
  if (await Permission
      .ignoreBatteryOptimizations
      .isDenied) {
    await Permission
        .ignoreBatteryOptimizations
        .request();
  }

  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
}

class VPNMasterApp extends ConsumerStatefulWidget {
  final UpdateInfo? forceUpdateInfo;

  const VPNMasterApp({
    super.key,
    this.forceUpdateInfo,
  });

  @override
  ConsumerState<VPNMasterApp> createState() =>
      _VPNMasterAppState();
}

class _VPNMasterAppState
    extends ConsumerState<VPNMasterApp>
    with WidgetsBindingObserver {
@override
void initState() {
super.initState();

WidgetsBinding.instance
.addObserver(this);
}

@override
void dispose() {
WidgetsBinding.instance
.removeObserver(this);

super.dispose();
}

@override
void didChangeAppLifecycleState(
AppLifecycleState state,
) {
super.didChangeAppLifecycleState(state);

if (state ==
AppLifecycleState.resumed) {
try {
ref
.read(vpnServiceProvider)
.resyncVpnState();
} catch (e) {
debugPrint(
'VPN resync failed: $e',
);
}

try {
LevelPlayService.instance
.refreshPremiumStatus();
} catch (e) {
debugPrint(
'Premium refresh failed: $e',
);
}
}
}

@override
Widget build(
BuildContext context,
) {
final themeMode =
ref.watch(themeModeProvider);

final lightTheme =
ref.watch(themeDataProvider);

final darkTheme =
ref.watch(darkThemeDataProvider);

final locale =
ref.watch(languageProvider);

ref.listen<AuthState>(
authStateProvider,
(previous, next) {
if (next.status ==
AuthStatus.unauthenticated &&
previous?.status ==
AuthStatus.authenticated) {
ref
.read(
premiumStatusProvider
.notifier,
)
.clearPremiumStatus();
}
},
);

return MaterialApp(
title: 'VPN MASTER',

debugShowCheckedModeBanner:
false,

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

  home: widget.forceUpdateInfo != null
      ? ForceUpdateScreen(
    updateInfo:
    widget.forceUpdateInfo!,
  )
      : null,

  initialRoute:
  widget.forceUpdateInfo == null
      ? '/splash'
      : null,

  onGenerateRoute:
  AppRouter.generateRoute,

  builder: (
      context,
      child,
      ) {
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(
        textScaler:
        const TextScaler.linear(
          1.0,
        ),
      ),
      child: child ??
          const SplashScreen(),
    );
  },
);
}
}