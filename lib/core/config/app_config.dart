import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // API Configuration
  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'https://your-domain.com'; // Default to local server for development
  static String get baseUrl => apiBaseUrl; // Alias for compatibility
  static String get apiVersion => 'v1'; // API version
  // No hardcoded fallback — set API_TOKEN_MOBILE in .env (see .env.example).
  // A bundled default here would ship as a plaintext string in the compiled
  // app binary, defeating the purpose of keeping it out of source control.
  static String get apiKey => dotenv.env['API_TOKEN_MOBILE'] ?? '';

  // AdMob Configuration
  static String get admobAppIdAndroid =>
      dotenv.env['ADMOB_APP_ID_ANDROID'] ?? '';
  static String get admobAppIdIOS => dotenv.env['ADMOB_APP_ID_IOS'] ?? '';
  static String get admobBannerIdAndroid =>
      dotenv.env['ADMOB_BANNER_ID_ANDROID'] ?? '';
  static String get admobBannerIdIOS => dotenv.env['ADMOB_BANNER_ID_IOS'] ?? '';
  static String get admobInterstitialIdAndroid =>
      dotenv.env['ADMOB_INTERSTITIAL_ID_ANDROID'] ?? '';
  static String get admobInterstitialIdIOS =>
      dotenv.env['ADMOB_INTERSTITIAL_ID_IOS'] ?? '';
  static String get admobRewardedIdAndroid =>
      dotenv.env['ADMOB_REWARDED_ID_ANDROID'] ?? '';
  static String get admobRewardedIdIOS =>
      dotenv.env['ADMOB_REWARDED_ID_IOS'] ?? '';
  static String get admobAppOpenIdAndroid =>
      dotenv.env['ADMOB_APP_OPEN_ID_ANDROID'] ?? '';
  static String get admobAppOpenIdIOS =>
      dotenv.env['ADMOB_APP_OPEN_ID_IOS'] ?? '';
  static String get admobNativeIdAndroid =>
      dotenv.env['ADMOB_NATIVE_ID_ANDROID'] ?? '';
  static String get admobNativeIdIOS => dotenv.env['ADMOB_NATIVE_ID_IOS'] ?? '';

  // Firebase Configuration
  static String get firebaseProjectId =>
      dotenv.env['FIREBASE_PROJECT_ID'] ?? '';

  // App Configuration
  static String get appVersion => dotenv.env['APP_VERSION'] ?? '8.3.0';
  static bool get isDebugMode =>
      dotenv.env['DEBUG_MODE']?.toLowerCase() == 'false' ? false : true;

  // API Endpoints - Using correct v1 endpoints from admin panel
  static String get serversEndpoint => '$apiBaseUrl/api/v1/list';
  static String get bestServerEndpoint => '$apiBaseUrl/api/v1/best';
  static String get settingsEndpoint => '$apiBaseUrl/api/v1/get-setting';
  static String get adIdsEndpoint => '$apiBaseUrl/api/v1/get-ad-ids';
  static String get downloadConfigEndpoint => '$apiBaseUrl/api/v1/get';
  static String get requestIpEndpoint => '$apiBaseUrl/api/v1/request-ip';
  static String get logConnectEndpoint => '$apiBaseUrl/api/v1/log-connect';
  static String get logDisconnectEndpoint =>
      '$apiBaseUrl/api/v1/log-disconnect';

  // Payment Endpoints
  static String get paymentsEndpoint => '$apiBaseUrl/api/v1/payments';
  static String get stripePaymentEndpoint =>
      '$apiBaseUrl/api/v1/payments/stripe/create-intent';
  static String get paypalPaymentEndpoint =>
      '$apiBaseUrl/api/v1/payments/paypal/create-order';
  static String get paymentReceiptsEndpoint =>
      '$apiBaseUrl/api/v1/payments/receipts';
}
