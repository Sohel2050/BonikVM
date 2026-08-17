import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Language model
class AppLanguage {
  final String code;
  final String name;
  final String nativeName;
  final String flagCode;

  const AppLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flagCode,
  });

  static const List<AppLanguage> supportedLanguages = [
    AppLanguage(
      code: 'en',
      name: 'English',
      nativeName: 'English',
      flagCode: 'us',
    ),
    AppLanguage(
      code: 'es',
      name: 'Spanish',
      nativeName: 'Español',
      flagCode: 'es',
    ),
    AppLanguage(
      code: 'fr',
      name: 'French',
      nativeName: 'Français',
      flagCode: 'fr',
    ),
    AppLanguage(
      code: 'de',
      name: 'German',
      nativeName: 'Deutsch',
      flagCode: 'de',
    ),
    AppLanguage(
      code: 'pt',
      name: 'Portuguese',
      nativeName: 'Português',
      flagCode: 'pt',
    ),
    AppLanguage(
      code: 'it',
      name: 'Italian',
      nativeName: 'Italiano',
      flagCode: 'it',
    ),
  ];

  static AppLanguage getByCode(String code) {
    try {
      return supportedLanguages.firstWhere((lang) => lang.code == code);
    } catch (e) {
      return supportedLanguages.first; // Default to English
    }
  }
}

// Language Provider
class LanguageNotifier extends StateNotifier<Locale> {
  LanguageNotifier() : super(const Locale('en', 'US')) {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString('language_code') ?? 'en';
      state = Locale(languageCode);
    } catch (e) {
      state = const Locale('en', 'US');
    }
  }

  Future<void> setLanguage(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language_code', languageCode);
      state = Locale(languageCode);
    } catch (e) {
      debugPrint('Error setting language: $e');
    }
  }

  String get currentLanguageCode => state.languageCode;
}

final languageProvider = StateNotifierProvider<LanguageNotifier, Locale>((ref) {
  return LanguageNotifier();
});

// App Localizations
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': _enTranslations,
    'es': _esTranslations,
    'fr': _frTranslations,
    'de': _deTranslations,
    'pt': _ptTranslations,
    'it': _itTranslations,
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }

  // Convenience getters for common strings
  String get appName => translate('app_name');
  String get home => translate('home');
  String get servers => translate('servers');
  String get premium => translate('premium');
  String get settings => translate('settings');

  // Home Screen
  String get connect => translate('connect');
  String get disconnect => translate('disconnect');
  String get connecting => translate('connecting');
  String get disconnecting => translate('disconnecting');
  String get connected => translate('connected');
  String get disconnected => translate('disconnected');
  String get tapToConnect => translate('tap_to_connect');
  String get tapToDisconnect => translate('tap_to_disconnect');
  String get connectedTo => translate('connected_to');
  String get selectServer => translate('select_server');
  String get yourIP => translate('your_ip');
  String get vpnIP => translate('vpn_ip');
  String get location => translate('location');
  String get downloadSpeed => translate('download_speed');
  String get uploadSpeed => translate('upload_speed');
  String get connectionTime => translate('connection_time');

  // Server Screen
  String get allServers => translate('all_servers');
  String get freeServers => translate('free_servers');
  String get premiumServers => translate('premium_servers');
  String get searchServers => translate('search_servers');
  String get noServersFound => translate('no_servers_found');
  String get loading => translate('loading');
  String get premiumOnly => translate('premium_only');
  String get best => translate('best');
  String get ping => translate('ping');

  // Premium Screen
  String get upgradeToPremium => translate('upgrade_to_premium');
  String get unlimitedAccess => translate('unlimited_access');
  String get noAds => translate('no_ads');
  String get fasterSpeeds => translate('faster_speeds');
  String get allLocations => translate('all_locations');
  String get monthlyPlan => translate('monthly_plan');
  String get yearlyPlan => translate('yearly_plan');
  String get lifetimePlan => translate('lifetime_plan');
  String get subscribe => translate('subscribe');
  String get restorePurchases => translate('restore_purchases');
  String get premiumFeatures => translate('premium_features');

  // Settings Screen
  String get connection => translate('connection');
  String get appearance => translate('appearance');
  String get account => translate('account');
  String get miscellaneous => translate('miscellaneous');
  String get protocol => translate('protocol');
  String get killSwitch => translate('kill_switch');
  String get autoConnect => translate('auto_connect');
  String get theme => translate('theme');
  String get accentColor => translate('accent_color');
  String get language => translate('language');
  String get premiumStatus => translate('premium_status');
  String get accountManagement => translate('account_management');
  String get purchaseHistory => translate('purchase_history');
  String get notifications => translate('notifications');
  String get about => translate('about');
  String get privacyPolicy => translate('privacy_policy');
  String get termsOfService => translate('terms_of_service');
  String get support => translate('support');
  String get rateApp => translate('rate_app');
  String get shareApp => translate('share_app');
  String get version => translate('version');

  // Theme
  String get lightMode => translate('light_mode');
  String get darkMode => translate('dark_mode');
  String get systemDefault => translate('system_default');

  // Protocol
  String get udpRecommended => translate('udp_recommended');
  String get tcpReliable => translate('tcp_reliable');

  // Common
  String get ok => translate('ok');
  String get cancel => translate('cancel');
  String get save => translate('save');
  String get delete => translate('delete');
  String get edit => translate('edit');
  String get yes => translate('yes');
  String get no => translate('no');
  String get error => translate('error');
  String get success => translate('success');
  String get warning => translate('warning');
  String get info => translate('info');

  // Messages
  String get connectionSuccessful => translate('connection_successful');
  String get connectionFailed => translate('connection_failed');
  String get disconnectionSuccessful => translate('disconnection_successful');
  String get pleaseSelectServer => translate('please_select_server');
  String get premiumRequired => translate('premium_required');
  String get noInternetConnection => translate('no_internet_connection');

  // App Drawer
  String get myAccount => translate('my_account');
  String get signIn => translate('sign_in');
  String get signOut => translate('sign_out');
  String get selectLanguage => translate('select_language');

  // Extended Home Screen
  String get timeExpired => translate('time_expired');
  String get timeExpiredMessage => translate('time_expired_message');
  String get watchAd5Min => translate('watch_ad_5_min');
  String get upgradeNow => translate('upgrade_now');
  String get serverDetails => translate('server_details');
  String get serverIp => translate('server_ip');
  String get status => translate('status');
  String get active => translate('active');
  String get inactive => translate('inactive');
  String get close => translate('close');
  String get secureFastReliable => translate('secure_fast_reliable');
  String get free => translate('free');
  String get upgrade => translate('upgrade');

  // Extended Server Screen
  String get connectToServer => translate('connect_to_server');
  String get requiresPremium => translate('requires_premium');
  String get getPremium => translate('get_premium');
  String get ms => translate('ms');
  String get online => translate('online');
  String get offline => translate('offline');

  // Extended Premium Screen
  String get ultraFastServers => translate('ultra_fast_servers');
  String get accessPremiumServers => translate('access_premium_servers');
  String get advancedSecurity => translate('advanced_security');
  String get advancedEncryption => translate('advanced_encryption');
  String get adFreeExperience => translate('ad_free_experience');
  String get noInterruptions => translate('no_interruptions');
  String get unlimitedDevices => translate('unlimited_devices');
  String get connectUnlimitedDevices => translate('connect_unlimited_devices');
  String get prioritySupport => translate('priority_support');
  String get instantHelp => translate('instant_help');
  String get premiumLocations => translate('premium_locations');
  String get exclusiveServers => translate('exclusive_servers');
  String get chooseYourPlan => translate('choose_your_plan');
  String get bestValue => translate('best_value');
  String get mostPopular => translate('most_popular');
  String get popular => translate('popular');
  String get selectPlan => translate('select_plan');
  String get processing => translate('processing');
  String get pleaseWait => translate('please_wait');
  String get purchaseSuccessful => translate('purchase_successful');
  String get purchaseFailed => translate('purchase_failed');
  String get alreadyPremium => translate('already_premium');
  String get signInRequired => translate('sign_in_required');
  String get signInToPurchase => translate('sign_in_to_purchase');

  // Auth Screen
  String get welcomeBack => translate('welcome_back');
  String get createYourAccount => translate('create_your_account');
  String get axeVpn => translate('axe_vpn');
  String get signInWithGoogle => translate('sign_in_with_google');
  String get or => translate('or');
  String get email => translate('email');
  String get password => translate('password');
  String get name => translate('name');
  String get continueText => translate('continue');
  String get continueWithGoogle => translate('continue_with_google');
  String get later => translate('later');

  // Privacy & Terms
  String get privacyPolicyTitle => translate('privacy_policy_title');
  String get lastUpdated => translate('last_updated');
  String get readOurPrivacyPolicy => translate('read_our_privacy_policy');
  String get termsTitle => translate('terms_title');
  String get readOurTerms => translate('read_our_terms');

  // Support
  String get contactSupportTitle => translate('contact_support_title');
  String get getHelp => translate('get_help');

  // Common Messages
  String get somethingWentWrong => translate('something_went_wrong');
  String get tryAgain => translate('try_again');
  String get maybeLater => translate('maybe_later');
  String get rateNow => translate('rate_now');
  String get gotIt => translate('got_it');

  // Popup - Premium Server Unlock
  String get unlockPremiumServer => translate('unlock_premium_server');
  String get watch3VideosUnlock => translate('watch_3_videos_unlock');
  String get video1 => translate('video_1');
  String get video2 => translate('video_2');
  String get video3 => translate('video_3');
  String get watchNow => translate('watch_now');
  String get orGoPremium => translate('or_go_premium');
  String get serverUnlockedFor => translate('server_unlocked_for');

  // Popup - Extend Free Time
  String get extendFreeTime => translate('extend_free_time');
  String get watchVideosContinue => translate('watch_videos_continue');
  String get freeTimeExtended => translate('free_time_extended');

  // Extended Home Screen - Additional
  String get killSwitchActivated => translate('kill_switch_activated');
  String get disableKillSwitch => translate('disable_kill_switch');
  String get reconnect => translate('reconnect');
  String get subscribeForPremium => translate('subscribe_for_premium');
  String get load => translate('load');
  String get connectedUsers => translate('connected_users');
  String get freeTimeLimit => translate('free_time_limit');
  String get unlimited => translate('unlimited');
  String get currentlyConnected => translate('currently_connected');
  String get connectionSecure => translate('connection_secure');
  String get connectionNotSecure => translate('connection_not_secure');
  String get wireguard => translate('wireguard');
  String get anyconnect => translate('anyconnect');
  String get openvpnLabel => translate('openvpn_label');
  String get protectedStatus => translate('protected');
  String get notProtected => translate('not_protected');
  String get connectingStatus => translate('connecting_status');
  String get authenticating => translate('authenticating');
  String get disconnectingStatus => translate('disconnecting_status');
  String get connectionError => translate('connection_error');
  String get permissionDeniedStatus => translate('permission_denied_status');
  String get freeConnectionTime => translate('free_connection_time');
  String get goPremium => translate('go_premium');
  String get duration => translate('duration');

  // Extended Server Screen - Additional
  String get freeOnly => translate('free_only');
  String get failedToLoadServers => translate('failed_to_load_servers');
  String get filterServers => translate('filter_servers');
  String get showOnlyPremiumServers => translate('show_only_premium_servers');
  String get showOnlyFreeServers => translate('show_only_free_servers');
  String get clear => translate('clear');
  String get apply => translate('apply');
  String get ipAddress => translate('ip_address');
  String get freeLimit => translate('free_limit');
  String get watchVideoOrUpgrade => translate('watch_video_or_upgrade');
  String get premiumServerAccess => translate('premium_server_access');

  // Extended Premium Screen - Additional
  String get unlockPremium => translate('unlock_premium');
  String get accessAllServersFeatures =>
      translate('access_all_servers_features');
  String get subscribeNow => translate('subscribe_now');
  String get myReceipts => translate('my_receipts');
  String get redeemVoucher => translate('redeem_voucher');
  String get lifetimeAccess => translate('lifetime_access');
  String get receipts => translate('receipts');
  String get voucher => translate('voucher');
  String get upgradeExtendPlan => translate('upgrade_extend_plan');
  String get whatsIncluded => translate('whats_included');
  String get expired => translate('expired');
  String get daysLeft => translate('days_left');
  String get oneTime => translate('one_time');
  String get oneTimePayment => translate('one_time_payment');

  // Auth Screen - Extended
  String get loginTitle => translate('login_title');
  String get loginSignInContinue => translate('login_sign_in_continue');
  String get continueWithApple => translate('continue_with_apple');
  String get enterEmail => translate('enter_email');
  String get enterPassword => translate('enter_password');
  String get forgotPassword => translate('forgot_password');
  String get signUp => translate('sign_up');
  String get dontHaveAccount => translate('dont_have_account');
  String get alreadyHaveAccount => translate('already_have_account');
  String get continueAsGuest => translate('continue_as_guest');
  String get byContinuingAgree => translate('by_continuing_agree');
  String get termsConditions => translate('terms_conditions');
  String get appleEula => translate('apple_eula');
  String get acceptLegalTerms => translate('accept_legal_terms');
  String get legalAcceptanceDescription =>
      translate('legal_acceptance_description');

  // Premium Screen - Extended
  String get premiumSubtitle => translate('premium_subtitle');
  String get advancedGradeSecurity => translate('advanced_grade_security');
  String get subscriptionTerms => translate('subscription_terms');
  String get subscriptionTermsDescription =>
      translate('subscription_terms_description');
  String get selectBestPlan => translate('select_best_plan');
  String get oneMonthPlan => translate('one_month');
  String get threeMonthsPlan => translate('three_months');
  String get oneYearPlan => translate('one_year');
  String get continueToCheckout => translate('continue_to_checkout');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLanguage.supportedLanguages.any(
      (lang) => lang.code == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

// English translations
const Map<String, String> _enTranslations = {
  'app_name': 'VPN MASTER',
  'home': 'Home',
  'servers': 'Servers',
  'premium': 'Premium',
  'settings': 'Settings',

  // Home Screen
  'connect': 'Connect',
  'disconnect': 'Disconnect',
  'connecting': 'Connecting',
  'disconnecting': 'Disconnecting',
  'connected': 'Connected',
  'disconnected': 'Disconnected',
  'tap_to_connect': 'Tap to Connect',
  'tap_to_disconnect': 'Tap to Disconnect',
  'connected_to': 'Connected to',
  'select_server': 'Select Server',
  'your_ip': 'Your IP',
  'vpn_ip': 'VPN IP',
  'location': 'Location',
  'download_speed': 'Download',
  'upload_speed': 'Upload',
  'connection_time': 'Time',

  // Server Screen
  'all_servers': 'All Servers',
  'free_servers': 'Free Servers',
  'premium_servers': 'Premium Servers',
  'search_servers': 'Search Servers',
  'no_servers_found': 'No servers found',
  'loading': 'Loading...',
  'premium_only': 'Premium Only',
  'best': 'Best',
  'ping': 'Ping',

  // Premium Screen
  'upgrade_to_premium': 'Upgrade',
  'unlimited_access': 'Unlimited Access',
  'no_ads': 'No Ads',
  'faster_speeds': 'Faster Speeds',
  'all_locations': 'All Locations',
  'monthly_plan': 'Monthly',
  'yearly_plan': 'Yearly',
  'lifetime_plan': 'Lifetime',
  'subscribe': 'Subscribe',
  'restore_purchases': 'Restore Purchases',
  'premium_features': 'Premium Features',

  // Settings Screen
  'connection': 'Connection',
  'appearance': 'Appearance',
  'account': 'Account',
  'miscellaneous': 'Miscellaneous',
  'protocol': 'Protocol',
  'kill_switch': 'Kill Switch',
  'auto_connect': 'Auto Connect',
  'theme': 'Theme',
  'accent_color': 'Accent Color',
  'language': 'Language',
  'premium_status': 'Premium Status',
  'account_management': 'Account Management',
  'purchase_history': 'Purchase History',
  'notifications': 'Notifications',
  'about': 'About',
  'privacy_policy': 'Privacy Policy',
  'terms_of_service': 'Terms of Service',
  'support': 'Support',
  'rate_app': 'Rate App',
  'share_app': 'Share App',
  'version': 'Version',

  // Theme
  'light_mode': 'Light',
  'dark_mode': 'Dark',
  'system_default': 'System',

  // Protocol
  'udp_recommended': 'UDP (Recommended)',
  'tcp_reliable': 'TCP (Reliable)',

  // Common
  'ok': 'OK',
  'cancel': 'Cancel',
  'save': 'Save',
  'delete': 'Delete',
  'edit': 'Edit',
  'yes': 'Yes',
  'no': 'No',
  'error': 'Error',
  'success': 'Success',
  'warning': 'Warning',
  'info': 'Info',

  // Messages
  'connection_successful': 'Connected successfully',
  'connection_failed': 'Connection failed',
  'disconnection_successful': 'Disconnected successfully',
  'please_select_server': 'Please select a server',
  'premium_required': 'Premium subscription required',
  'no_internet_connection': 'No internet connection',

  // App Drawer
  'my_account': 'My Account',
  'sign_in': 'Sign In',
  'sign_out': 'Sign Out',
  'select_language': 'Select Language',

  // Extended Home Screen
  'time_expired': 'Time Expired',
  'time_expired_message':
      'Your free connection time has expired. Upgrade to Premium for unlimited VPN access or watch an ad to get more time!',
  'watch_ad_5_min': 'Watch Ad (+5 min)',
  'upgrade_now': 'Upgrade Now',
  'server_details': 'Server Details',
  'server_ip': 'Server IP',
  'status': 'Status',
  'active': 'Active',
  'inactive': 'Inactive',
  'close': 'Close',
  'secure_fast_reliable': 'Secure • Fast • Reliable',
  'free': 'FREE',
  'upgrade': 'UPGRADE',

  // Extended Server Screen
  'connect_to_server': 'Connect to Server',
  'requires_premium': 'Requires Premium',
  'get_premium': 'Get Premium',
  'ms': 'ms',
  'online': 'Online',
  'offline': 'Offline',

  // Extended Premium Screen
  'ultra_fast_servers': 'Ultra-Fast Servers',
  'access_premium_servers': 'Access to premium high-speed servers worldwide',
  'advanced_security': 'Advanced-Grade Security',
  'advanced_encryption': 'Advanced encryption and security protocols',
  'ad_free_experience': 'Ad-Free Experience',
  'no_interruptions': 'No ads, no interruptions, pure VPN experience',
  'unlimited_devices': 'Unlimited Devices',
  'connect_unlimited_devices':
      'Connect unlimited devices with one subscription',
  'priority_support': '24/7 Priority Support',
  'instant_help': 'Get instant help whenever you need it',
  'premium_locations': 'Premium Locations',
  'exclusive_servers': 'Access to exclusive server locations',
  'choose_your_plan': 'Choose Your Plan',
  'best_value': 'BEST VALUE',
  'most_popular': 'MOST POPULAR',
  'popular': 'POPULAR',
  'select_plan': 'Select Plan',
  'processing': 'Processing...',
  'please_wait': 'Please wait...',
  'purchase_successful': 'Purchase Successful!',
  'purchase_failed': 'Purchase Failed',
  'already_premium': 'You are already a Premium member!',
  'sign_in_required': 'Sign In Required',
  'sign_in_to_purchase':
      'Please sign in with your Google account to purchase Premium.',

  // Auth Screen
  'welcome_back': 'Welcome back',
  'create_your_account': 'Create your account',
  'axe_vpn': 'VPN MASTER',
  'sign_in_with_google': 'Sign In with Google',
  'or': 'OR',
  'email': 'Email',
  'password': 'Password',
  'name': 'Name',
  'continue': 'Continue',
  'continue_with_google': 'Continue with Google',
  'later': 'Later',

  // Privacy & Terms
  'privacy_policy_title': 'Privacy Policy',
  'last_updated': 'Last updated',
  'read_our_privacy_policy': 'Read our privacy policy',
  'terms_title': 'Terms of Service',
  'read_our_terms': 'Read our terms',

  // Support
  'contact_support_title': 'Contact Support',
  'get_help': 'Get help with the app',

  // Common Messages
  'something_went_wrong': 'Something went wrong',
  'try_again': 'Try Again',
  'maybe_later': 'Maybe Later',
  'rate_now': 'Rate Now',
  'got_it': 'Got It',

  // Popup - Premium Server Unlock
  'unlock_premium_server': 'Unlock Premium Server',
  'watch_3_videos_unlock': 'Watch 3 videos to unlock for temporary access',
  'video_1': 'Video 1',
  'video_2': 'Video 2',
  'video_3': 'Video 3',
  'watch_now': 'Watch Now',
  'or_go_premium': 'Or Go Premium',
  'server_unlocked_for': 'Server unlocked for %s minutes!',

  // Popup - Extend Free Time
  'extend_free_time': 'Extend Free Time',
  'watch_videos_continue': 'Watch videos to continue',
  'free_time_extended': 'Free time extended by %s minutes!',

  // Extended Home Screen - Additional
  'kill_switch_activated': 'Kill Switch Activated',
  'disable_kill_switch': 'Disable Kill Switch',
  'reconnect': 'Reconnect',
  'subscribe_for_premium': 'Please subscribe to access premium servers',
  'load': 'Load',
  'connected_users': 'Connected Users',
  'free_time_limit': 'Free Time Limit',
  'unlimited': 'Unlimited',
  'currently_connected': 'Currently Connected',
  'connection_secure': 'Your connection is secure',
  'connection_not_secure': 'Your connection is not secure',
  'wireguard': 'WireGuard',
  'anyconnect': 'AnyConnect',
  'openvpn_label': 'OpenVPN',
  'protected': 'PROTECTED',
  'not_protected': 'NOT PROTECTED',
  'connecting_status': 'CONNECTING',
  'authenticating': 'AUTHENTICATING',
  'disconnecting_status': 'DISCONNECTING',
  'connection_error': 'CONNECTION ERROR',
  'permission_denied_status': 'PERMISSION DENIED',
  'free_connection_time': 'Free Connection Time',
  'go_premium': 'Go Premium',
  'duration': 'Duration',

  // Extended Server Screen - Additional
  'free_only': 'Free only',
  'failed_to_load_servers': 'Failed to load servers',
  'filter_servers': 'Filter Servers',
  'show_only_premium_servers': 'Show only premium servers',
  'show_only_free_servers': 'Show only free servers',
  'clear': 'Clear',
  'apply': 'Apply',
  'ip_address': 'IP Address',
  'free_limit': 'Free Limit',
  'watch_video_or_upgrade':
      'Watch a video or upgrade to access premium servers',
  'premium_server_access': 'Premium Server Access',

  // Extended Premium Screen - Additional
  'unlock_premium': 'Unlock Premium',
  'access_all_servers_features': 'Access all servers & premium features',
  'subscribe_now': 'Subscribe Now',
  'my_receipts': 'My Receipts',
  'redeem_voucher': 'Redeem Voucher',
  'lifetime_access': 'Lifetime Access · Never Expires',
  'receipts': 'Receipts',
  'voucher': 'Voucher',
  'upgrade_extend_plan': 'Upgrade / Extend Plan',
  'whats_included': 'What\'s included',
  'expired': 'Expired',
  'days_left': 'days left',
  'one_time': 'ONE-TIME',
  'one_time_payment': 'one-time payment',

  // Auth Screen - Extended
  'login_title': 'VPN MASTER',
  'login_sign_in_continue': 'Sign in to continue',
  'continue_with_apple': 'Continue with Apple',
  'enter_email': 'Enter your email',
  'enter_password': 'Enter your password',
  'forgot_password': 'Forgot Password?',
  'sign_up': 'Sign Up',
  'dont_have_account': "Don't have an account?",
  'already_have_account': 'Already have an account?',
  'continue_as_guest': 'Continue as Guest',
  'by_continuing_agree': 'By continuing, you agree to our',
  'terms_conditions': 'Terms & Conditions',
  'apple_eula': 'Apple EULA',
  'accept_legal_terms': 'Accept legal terms',
  'legal_acceptance_description':
      'Review our Privacy Policy, Terms & Conditions, and Apple EULA before continuing.',

  // Premium Screen - Extended
  'premium_subtitle': 'Access all servers & premium features',
  'advanced_grade_security': 'Advanced-Grade Security',
  'subscription_terms': 'Subscription terms',
  'subscription_terms_description':
      'Review the Privacy Policy, Terms & Conditions, and Apple EULA before subscribing.',
  'select_best_plan': 'Select the best plan for you',
  'one_month': '1 Month',
  'three_months': '3 Months',
  'one_year': '1 Year',
  'continue_to_checkout': 'Continue to Checkout',
};

// Spanish translations
const Map<String, String> _esTranslations = {
  'app_name': 'VPN MASTER',
  'home': 'Inicio',
  'servers': 'Servidores',
  'premium': 'Premium',
  'settings': 'Ajustes',

  // Home Screen
  'connect': 'Conectar',
  'disconnect': 'Desconectar',
  'connecting': 'Conectando',
  'disconnecting': 'Desconectando',
  'connected': 'Conectado',
  'disconnected': 'Desconectado',
  'tap_to_connect': 'Toca para Conectar',
  'tap_to_disconnect': 'Toca para Desconectar',
  'connected_to': 'Conectado a',
  'select_server': 'Seleccionar Servidor',
  'your_ip': 'Tu IP',
  'vpn_ip': 'IP VPN',
  'location': 'Ubicación',
  'download_speed': 'Descarga',
  'upload_speed': 'Subida',
  'connection_time': 'Tiempo',

  // Server Screen
  'all_servers': 'Todos los Servidores',
  'free_servers': 'Servidores Gratuitos',
  'premium_servers': 'Servidores Premium',
  'search_servers': 'Buscar Servidores',
  'no_servers_found': 'No se encontraron servidores',
  'loading': 'Cargando...',
  'premium_only': 'Solo Premium',
  'best': 'Mejor',
  'ping': 'Ping',

  // Premium Screen
  'upgrade_to_premium': 'Actualizar',
  'unlimited_access': 'Acceso Ilimitado',
  'no_ads': 'Sin Anuncios',
  'faster_speeds': 'Velocidades Más Rápidas',
  'all_locations': 'Todas las Ubicaciones',
  'monthly_plan': 'Mensual',
  'yearly_plan': 'Anual',
  'lifetime_plan': 'De por Vida',
  'subscribe': 'Suscribirse',
  'restore_purchases': 'Restaurar Compras',
  'premium_features': 'Características Premium',

  // Settings Screen
  'connection': 'Conexión',
  'appearance': 'Apariencia',
  'account': 'Cuenta',
  'miscellaneous': 'Misceláneo',
  'protocol': 'Protocolo',
  'kill_switch': 'Interruptor de Apagado',
  'auto_connect': 'Conexión Automática',
  'theme': 'Tema',
  'accent_color': 'Color de Acento',
  'language': 'Idioma',
  'premium_status': 'Estado Premium',
  'account_management': 'Gestión de Cuenta',
  'purchase_history': 'Historial de Compras',
  'notifications': 'Notificaciones',
  'about': 'Acerca de',
  'privacy_policy': 'Política de Privacidad',
  'terms_of_service': 'Términos de Servicio',
  'support': 'Soporte',
  'rate_app': 'Calificar App',
  'share_app': 'Compartir App',
  'version': 'Versión',

  // Theme
  'light_mode': 'Claro',
  'dark_mode': 'Oscuro',
  'system_default': 'Sistema',

  // Protocol
  'udp_recommended': 'UDP (Recomendado)',
  'tcp_reliable': 'TCP (Confiable)',

  // Common
  'ok': 'Aceptar',
  'cancel': 'Cancelar',
  'save': 'Guardar',
  'delete': 'Eliminar',
  'edit': 'Editar',
  'yes': 'Sí',
  'no': 'No',
  'error': 'Error',
  'success': 'Éxito',
  'warning': 'Advertencia',
  'info': 'Información',

  // Messages
  'connection_successful': 'Conectado exitosamente',
  'connection_failed': 'Conexión fallida',
  'disconnection_successful': 'Desconectado exitosamente',
  'please_select_server': 'Por favor selecciona un servidor',
  'premium_required': 'Se requiere suscripción Premium',
  'no_internet_connection': 'Sin conexión a Internet',

  // App Drawer
  'my_account': 'Mi Cuenta',
  'sign_in': 'Iniciar Sesión',
  'sign_out': 'Cerrar Sesión',
  'select_language': 'Seleccionar Idioma',

  // Extended Home Screen
  'time_expired': 'Tiempo Expirado',
  'time_expired_message':
      '¡Tu tiempo de conexión gratuita ha expirado. Actualiza a Premium para acceso VPN ilimitado o mira un anuncio para obtener más tiempo!',
  'watch_ad_5_min': 'Ver Anuncio (+5 min)',
  'upgrade_now': 'Actualizar Ahora',
  'server_details': 'Detalles del Servidor',
  'server_ip': 'IP del Servidor',
  'status': 'Estado',
  'active': 'Activo',
  'inactive': 'Inactivo',
  'close': 'Cerrar',
  'secure_fast_reliable': 'Seguro • Rápido • Confiable',
  'free': 'GRATIS',
  'upgrade': 'ACTUALIZAR',

  // Extended Server Screen
  'connect_to_server': 'Conectar al Servidor',
  'requires_premium': 'Requiere Premium',
  'get_premium': 'Obtener Premium',
  'ms': 'ms',
  'online': 'En línea',
  'offline': 'Fuera de línea',

  // Extended Premium Screen
  'ultra_fast_servers': 'Servidores Ultra-Rápidos',
  'access_premium_servers':
      'Acceso a servidores premium de alta velocidad en todo el mundo',
  'advanced_security': 'Seguridad de Grado Avanzado',
  'advanced_encryption': 'Protocolos de cifrado y seguridad avanzados',
  'ad_free_experience': 'Experiencia Sin Anuncios',
  'no_interruptions': 'Sin anuncios, sin interrupciones, experiencia VPN pura',
  'unlimited_devices': 'Dispositivos Ilimitados',
  'connect_unlimited_devices':
      'Conecta dispositivos ilimitados con una suscripción',
  'priority_support': 'Soporte Prioritario 24/7',
  'instant_help': 'Obtén ayuda instantánea cuando la necesites',
  'premium_locations': 'Ubicaciones Premium',
  'exclusive_servers': 'Acceso a ubicaciones de servidor exclusivas',
  'choose_your_plan': 'Elige Tu Plan',
  'best_value': 'MEJOR VALOR',
  'most_popular': 'MÁS POPULAR',
  'popular': 'POPULAR',
  'select_plan': 'Seleccionar Plan',
  'processing': 'Procesando...',
  'please_wait': 'Por favor espera...',
  'purchase_successful': '¡Compra Exitosa!',
  'purchase_failed': 'Compra Fallida',
  'already_premium': '¡Ya eres miembro Premium!',
  'sign_in_required': 'Inicio de Sesión Requerido',
  'sign_in_to_purchase':
      'Por favor inicia sesión con tu cuenta de Google para comprar Premium.',

  // Auth Screen
  'welcome_back': 'Bienvenido de nuevo',
  'create_your_account': 'Crea tu cuenta',
  'axe_vpn': 'VPN MASTER',
  'sign_in_with_google': 'Iniciar Sesión con Google',
  'or': 'O',
  'email': 'Correo Electrónico',
  'password': 'Contraseña',
  'name': 'Nombre',
  'continue': 'Continuar',
  'continue_with_google': 'Continuar con Google',
  'later': 'Más Tarde',

  // Privacy & Terms
  'privacy_policy_title': 'Política de Privacidad',
  'last_updated': 'Última actualización',
  'read_our_privacy_policy': 'Lee nuestra política de privacidad',
  'terms_title': 'Términos de Servicio',
  'read_our_terms': 'Lee nuestros términos',

  // Support
  'contact_support_title': 'Contactar Soporte',
  'get_help': 'Obtén ayuda con la app',

  // Common Messages
  'something_went_wrong': 'Algo salió mal',
  'try_again': 'Intentar de Nuevo',
  'maybe_later': 'Tal Vez Después',
  'rate_now': 'Calificar Ahora',
  'got_it': 'Entendido',

  // Popup - Premium Server Unlock
  'unlock_premium_server': 'Desbloquear Servidor Premium',
  'watch_3_videos_unlock': 'Mira 3 videos para desbloquear acceso temporal',
  'video_1': 'Video 1',
  'video_2': 'Video 2',
  'video_3': 'Video 3',
  'watch_now': 'Ver Ahora',
  'or_go_premium': 'O Ir a Premium',
  'server_unlocked_for': '¡Servidor desbloqueado por %s minutos!',

  // Popup - Extend Free Time
  'extend_free_time': 'Extender Tiempo Libre',
  'watch_videos_continue': 'Mira videos para continuar',
  'free_time_extended': '¡Tiempo libre extendido por %s minutos!',

  // Extended Home Screen - Additional
  'kill_switch_activated': 'Kill Switch Activado',
  'disable_kill_switch': 'Desactivar Kill Switch',
  'reconnect': 'Reconectar',
  'subscribe_for_premium':
      'Por favor suscríbete para acceder a servidores premium',
  'load': 'Carga',
  'connected_users': 'Usuarios Conectados',
  'free_time_limit': 'Límite de Tiempo Gratis',
  'unlimited': 'Ilimitado',
  'currently_connected': 'Actualmente Conectado',
  'connection_secure': 'Tu conexión es segura',
  'connection_not_secure': 'Tu conexión no es segura',
  'wireguard': 'WireGuard',
  'anyconnect': 'AnyConnect',
  'openvpn_label': 'OpenVPN',
  'protected': 'PROTEGIDO',
  'not_protected': 'NO PROTEGIDO',
  'connecting_status': 'CONECTANDO',
  'authenticating': 'AUTENTICANDO',
  'disconnecting_status': 'DESCONECTANDO',
  'connection_error': 'ERROR DE CONEXIÓN',
  'permission_denied_status': 'PERMISO DENEGADO',
  'free_connection_time': 'Tiempo de Conexión Gratuita',
  'go_premium': 'Ir a Premium',
  'duration': 'Duración',

  // Extended Server Screen - Additional
  'free_only': 'Solo gratuitos',
  'failed_to_load_servers': 'Error al cargar servidores',
  'filter_servers': 'Filtrar Servidores',
  'show_only_premium_servers': 'Mostrar solo servidores premium',
  'show_only_free_servers': 'Mostrar solo servidores gratuitos',
  'clear': 'Limpiar',
  'apply': 'Aplicar',
  'ip_address': 'Dirección IP',
  'free_limit': 'Límite Gratis',
  'watch_video_or_upgrade':
      'Mira un video o actualiza para acceder a servidores premium',
  'premium_server_access': 'Acceso a Servidores Premium',

  // Extended Premium Screen - Additional
  'unlock_premium': 'Desbloquear Premium',
  'access_all_servers_features':
      'Accede a todos los servidores y funciones premium',
  'subscribe_now': 'Suscribirse Ahora',
  'my_receipts': 'Mis Recibos',
  'redeem_voucher': 'Canjear Cupón',
  'lifetime_access': 'Acceso de por Vida · Nunca Expira',
  'receipts': 'Recibos',
  'voucher': 'Cupón',
  'upgrade_extend_plan': 'Actualizar / Extender Plan',
  'whats_included': 'Qué está incluido',
  'expired': 'Expirado',
  'days_left': 'días restantes',
  'one_time': 'UN PAGO',
  'one_time_payment': 'pago único',

  // Auth Screen - Extended
  'login_title': 'VPN MASTER',
  'login_sign_in_continue': 'Iniciar sesión para continuar',
  'continue_with_apple': 'Continuar con Apple',
  'enter_email': 'Ingresa tu correo',
  'enter_password': 'Ingresa tu contraseña',
  'forgot_password': '¿Olvidaste tu contraseña?',
  'sign_up': 'Registrarse',
  'dont_have_account': '¿No tienes una cuenta?',
  'already_have_account': '¿Ya tienes una cuenta?',
  'continue_as_guest': 'Continuar como invitado',
  'by_continuing_agree': 'Al continuar, aceptas nuestros',
  'terms_conditions': 'Términos y Condiciones',
  'apple_eula': 'EULA de Apple',
  'accept_legal_terms': 'Aceptar términos legales',
  'legal_acceptance_description':
      'Revisa nuestra Política de Privacidad, Términos y Condiciones y EULA de Apple antes de continuar.',

  // Premium Screen - Extended
  'premium_subtitle': 'Accede a todos los servidores y funciones premium',
  'advanced_grade_security': 'Seguridad de Grado Avanzado',
  'subscription_terms': 'Términos de suscripción',
  'subscription_terms_description':
      'Revisa la Política de Privacidad, Términos y Condiciones y EULA de Apple antes de suscribirte.',
  'select_best_plan': 'Selecciona el mejor plan para ti',
  'one_month': '1 Mes',
  'three_months': '3 Meses',
  'one_year': '1 Año',
  'continue_to_checkout': 'Continuar al pago',
};

// French translations
const Map<String, String> _frTranslations = {
  'app_name': 'VPN MASTER',
  'home': 'Accueil',
  'servers': 'Serveurs',
  'premium': 'Premium',
  'settings': 'Paramètres',

  // Home Screen
  'connect': 'Connecter',
  'disconnect': 'Déconnecter',
  'connecting': 'Connexion',
  'disconnecting': 'Déconnexion',
  'connected': 'Connecté',
  'disconnected': 'Déconnecté',
  'tap_to_connect': 'Appuyez pour Connecter',
  'tap_to_disconnect': 'Appuyez pour Déconnecter',
  'connected_to': 'Connecté à',
  'select_server': 'Sélectionner un Serveur',
  'your_ip': 'Votre IP',
  'vpn_ip': 'IP VPN',
  'location': 'Emplacement',
  'download_speed': 'Téléchargement',
  'upload_speed': 'Téléversement',
  'connection_time': 'Temps',

  // Server Screen
  'all_servers': 'Tous les Serveurs',
  'free_servers': 'Serveurs Gratuits',
  'premium_servers': 'Serveurs Premium',
  'search_servers': 'Rechercher des Serveurs',
  'no_servers_found': 'Aucun serveur trouvé',
  'loading': 'Chargement...',
  'premium_only': 'Premium Uniquement',
  'best': 'Meilleur',
  'ping': 'Ping',

  // Premium Screen
  'upgrade_to_premium': 'Passer',
  'unlimited_access': 'Accès Illimité',
  'no_ads': 'Sans Publicité',
  'faster_speeds': 'Vitesses Plus Rapides',
  'all_locations': 'Tous les Emplacements',
  'monthly_plan': 'Mensuel',
  'yearly_plan': 'Annuel',
  'lifetime_plan': 'À Vie',
  'subscribe': 'Souscrire',
  'restore_purchases': 'Restaurer les Achats',
  'premium_features': 'Fonctionnalités Premium',

  // Settings Screen
  'connection': 'Connexion',
  'appearance': 'Apparence',
  'account': 'Compte',
  'miscellaneous': 'Divers',
  'protocol': 'Protocole',
  'kill_switch': 'Kill Switch',
  'auto_connect': 'Connexion Automatique',
  'theme': 'Thème',
  'accent_color': 'Couleur d\'Accentuation',
  'language': 'Langue',
  'premium_status': 'Statut Premium',
  'account_management': 'Gestion du Compte',
  'purchase_history': 'Historique d\'Achats',
  'notifications': 'Notifications',
  'about': 'À Propos',
  'privacy_policy': 'Politique de Confidentialité',
  'terms_of_service': 'Conditions d\'Utilisation',
  'support': 'Support',
  'rate_app': 'Évaluer l\'App',
  'share_app': 'Partager l\'App',
  'version': 'Version',

  // Theme
  'light_mode': 'Clair',
  'dark_mode': 'Sombre',
  'system_default': 'Système',

  // Protocol
  'udp_recommended': 'UDP (Recommandé)',
  'tcp_reliable': 'TCP (Fiable)',

  // Common
  'ok': 'OK',
  'cancel': 'Annuler',
  'save': 'Enregistrer',
  'delete': 'Supprimer',
  'edit': 'Modifier',
  'yes': 'Oui',
  'no': 'Non',
  'error': 'Erreur',
  'success': 'Succès',
  'warning': 'Avertissement',
  'info': 'Info',

  // Messages
  'connection_successful': 'Connecté avec succès',
  'connection_failed': 'Échec de la connexion',
  'disconnection_successful': 'Déconnecté avec succès',
  'please_select_server': 'Veuillez sélectionner un serveur',
  'premium_required': 'Abonnement Premium requis',
  'no_internet_connection': 'Pas de connexion Internet',

  // App Drawer
  'my_account': 'Mon Compte',
  'sign_in': 'Se Connecter',
  'sign_out': 'Se Déconnecter',
  'select_language': 'Sélectionner la Langue',

  // Extended Home Screen
  'time_expired': 'Temps Expiré',
  'time_expired_message':
      'Votre temps de connexion gratuite a expiré. Passez à Premium pour un accès VPN illimité ou regardez une annonce pour obtenir plus de temps !',
  'watch_ad_5_min': 'Regarder Annonce (+5 min)',
  'upgrade_now': 'Mettre à Niveau',
  'server_details': 'Détails du Serveur',
  'server_ip': 'IP du Serveur',
  'status': 'Statut',
  'active': 'Actif',
  'inactive': 'Inactif',
  'close': 'Fermer',
  'secure_fast_reliable': 'Sécurisé • Rapide • Fiable',
  'free': 'GRATUIT',
  'upgrade': 'AMÉLIORER',

  // Extended Server Screen
  'connect_to_server': 'Se Connecter au Serveur',
  'requires_premium': 'Nécessite Premium',
  'get_premium': 'Obtenir Premium',
  'ms': 'ms',
  'online': 'En ligne',
  'offline': 'Hors ligne',

  // Extended Premium Screen
  'ultra_fast_servers': 'Serveurs Ultra-Rapides',
  'access_premium_servers':
      'Accès aux serveurs premium haute vitesse dans le monde entier',
  'advanced_security': 'Sécurité de Niveau Avancé',
  'advanced_encryption': 'Protocoles de chiffrement et de sécurité avancés',
  'ad_free_experience': 'Expérience Sans Publicité',
  'no_interruptions':
      'Pas de publicités, pas d\'interruptions, expérience VPN pure',
  'unlimited_devices': 'Appareils Illimités',
  'connect_unlimited_devices':
      'Connectez des appareils illimités avec un abonnement',
  'priority_support': 'Support Prioritaire 24/7',
  'instant_help': 'Obtenez de l\'aide instantanée quand vous en avez besoin',
  'premium_locations': 'Emplacements Premium',
  'exclusive_servers': 'Accès à des emplacements de serveurs exclusifs',
  'choose_your_plan': 'Choisissez Votre Plan',
  'best_value': 'MEILLEURE VALEUR',
  'most_popular': 'PLUS POPULAIRE',
  'popular': 'POPULAIRE',
  'select_plan': 'Sélectionner le Plan',
  'processing': 'Traitement en cours...',
  'please_wait': 'Veuillez patienter...',
  'purchase_successful': 'Achat Réussi !',
  'purchase_failed': 'Achat Échoué',
  'already_premium': 'Vous êtes déjà membre Premium !',
  'sign_in_required': 'Connexion Requise',
  'sign_in_to_purchase':
      'Veuillez vous connecter avec votre compte Google pour acheter Premium.',

  // Auth Screen
  'welcome_back': 'Bon retour',
  'create_your_account': 'Créez votre compte',
  'axe_vpn': 'VPN MASTER',
  'sign_in_with_google': 'Se Connecter avec Google',
  'or': 'OU',
  'email': 'Email',
  'password': 'Mot de passe',
  'name': 'Nom',
  'continue': 'Continuer',
  'continue_with_google': 'Continuer avec Google',
  'later': 'Plus Tard',

  // Privacy & Terms
  'privacy_policy_title': 'Politique de Confidentialité',
  'last_updated': 'Dernière mise à jour',
  'read_our_privacy_policy': 'Lisez notre politique de confidentialité',
  'terms_title': 'Conditions d\'Utilisation',
  'read_our_terms': 'Lisez nos conditions',

  // Support
  'contact_support_title': 'Contacter le Support',
  'get_help': 'Obtenez de l\'aide avec l\'application',

  // Common Messages
  'something_went_wrong': 'Quelque chose s\'est mal passé',
  'try_again': 'Réessayer',
  'maybe_later': 'Peut-être Plus Tard',
  'rate_now': 'Noter Maintenant',
  'got_it': 'Compris',

  // Popup - Premium Server Unlock
  'unlock_premium_server': 'Déverrouiller le Serveur Premium',
  'watch_3_videos_unlock':
      'Regardez 3 vidéos pour déverrouiller l\'accès temporaire',
  'video_1': 'Vidéo 1',
  'video_2': 'Vidéo 2',
  'video_3': 'Vidéo 3',
  'watch_now': 'Regarder Maintenant',
  'or_go_premium': 'Ou Aller à Premium',
  'server_unlocked_for': 'Serveur déverrouillé pour %s minutes!',

  // Popup - Extend Free Time
  'extend_free_time': 'Prolonger le Temps Libre',
  'watch_videos_continue': 'Regardez des vidéos pour continuer',
  'free_time_extended': 'Temps libre prolongé de %s minutes!',

  // Extended Home Screen - Additional
  'kill_switch_activated': 'Kill Switch Activé',
  'disable_kill_switch': 'Désactiver le Kill Switch',
  'reconnect': 'Reconnecter',
  'subscribe_for_premium':
      'Veuillez vous abonner pour accéder aux serveurs premium',
  'load': 'Charge',
  'connected_users': 'Utilisateurs Connectés',
  'free_time_limit': 'Limite de Temps Gratuit',
  'unlimited': 'Illimité',
  'currently_connected': 'Actuellement Connecté',
  'connection_secure': 'Votre connexion est sécurisée',
  'connection_not_secure': 'Votre connexion n\'est pas sécurisée',
  'wireguard': 'WireGuard',
  'anyconnect': 'AnyConnect',
  'openvpn_label': 'OpenVPN',
  'protected': 'PROTÉGÉ',
  'not_protected': 'NON PROTÉGÉ',
  'connecting_status': 'CONNEXION',
  'authenticating': 'AUTHENTIFICATION',
  'disconnecting_status': 'DÉCONNEXION',
  'connection_error': 'ERREUR DE CONNEXION',
  'permission_denied_status': 'PERMISSION REFUSÉE',
  'free_connection_time': 'Temps de Connexion Gratuit',
  'go_premium': 'Passer à Premium',
  'duration': 'Durée',

  // Extended Server Screen - Additional
  'free_only': 'Gratuits seulement',
  'failed_to_load_servers': 'Échec du chargement des serveurs',
  'filter_servers': 'Filtrer les Serveurs',
  'show_only_premium_servers': 'Afficher uniquement les serveurs premium',
  'show_only_free_servers': 'Afficher uniquement les serveurs gratuits',
  'clear': 'Effacer',
  'apply': 'Appliquer',
  'ip_address': 'Adresse IP',
  'free_limit': 'Limite Gratuite',
  'watch_video_or_upgrade':
      'Regardez une vidéo ou passez Premium pour accéder aux serveurs premium',
  'premium_server_access': 'Accès aux Serveurs Premium',

  // Extended Premium Screen - Additional
  'unlock_premium': 'Débloquer Premium',
  'access_all_servers_features':
      'Accédez à tous les serveurs et fonctionnalités premium',
  'subscribe_now': 'S\'abonner Maintenant',
  'my_receipts': 'Mes Reçus',
  'redeem_voucher': 'Échanger un Bon',
  'lifetime_access': 'Accès à Vie · N\'expire Jamais',
  'receipts': 'Reçus',
  'voucher': 'Bon',
  'upgrade_extend_plan': 'Mettre à Niveau / Étendre le Plan',
  'whats_included': 'Ce qui est inclus',
  'expired': 'Expiré',
  'days_left': 'jours restants',
  'one_time': 'UN SEUL PAIEMENT',
  'one_time_payment': 'paiement unique',

  // Auth Screen - Extended
  'login_title': 'VPN MASTER',
  'login_sign_in_continue': 'Connectez-vous pour continuer',
  'continue_with_apple': 'Continuer avec Apple',
  'enter_email': 'Entrez votre e-mail',
  'enter_password': 'Entrez votre mot de passe',
  'forgot_password': 'Mot de passe oublié ?',
  'sign_up': 'S\'inscrire',
  'dont_have_account': 'Pas de compte ?',
  'already_have_account': 'Vous avez déjà un compte ?',
  'continue_as_guest': 'Continuer en tant qu\'invité',
  'by_continuing_agree': 'En continuant, vous acceptez nos',
  'terms_conditions': 'Conditions Générales',
  'apple_eula': 'CLUF Apple',
  'accept_legal_terms': 'Accepter les termes légaux',
  'legal_acceptance_description':
      'Consultez notre Politique de confidentialité, nos CGU et le CLUF Apple avant de continuer.',

  // Premium Screen - Extended
  'premium_subtitle': 'Accédez à tous les serveurs et fonctionnalités premium',
  'advanced_grade_security': 'Sécurité de Niveau Avancé',
  'subscription_terms': 'Conditions d\'abonnement',
  'subscription_terms_description':
      'Consultez la Politique de confidentialité, les CGU et le CLUF Apple avant de vous abonner.',
  'select_best_plan': 'Sélectionnez le meilleur plan pour vous',
  'one_month': '1 Mois',
  'three_months': '3 Mois',
  'one_year': '1 An',
  'continue_to_checkout': 'Continuer vers le paiement',
};

// German translations
const Map<String, String> _deTranslations = {
  'app_name': 'VPN MASTER',
  'home': 'Startseite',
  'servers': 'Server',
  'premium': 'Premium',
  'settings': 'Einstellungen',

  // Home Screen
  'connect': 'Verbinden',
  'disconnect': 'Trennen',
  'connecting': 'Verbinden',
  'disconnecting': 'Trennen',
  'connected': 'Verbunden',
  'disconnected': 'Getrennt',
  'tap_to_connect': 'Tippen zum Verbinden',
  'tap_to_disconnect': 'Tippen zum Trennen',
  'connected_to': 'Verbunden mit',
  'select_server': 'Server Auswählen',
  'your_ip': 'Ihre IP',
  'vpn_ip': 'VPN-IP',
  'location': 'Standort',
  'download_speed': 'Download',
  'upload_speed': 'Upload',
  'connection_time': 'Zeit',

  // Server Screen
  'all_servers': 'Alle Server',
  'free_servers': 'Kostenlose Server',
  'premium_servers': 'Premium-Server',
  'search_servers': 'Server Suchen',
  'no_servers_found': 'Keine Server gefunden',
  'loading': 'Laden...',
  'premium_only': 'Nur Premium',
  'best': 'Beste',
  'ping': 'Ping',

  // Premium Screen
  'upgrade_to_premium': 'Upgraden',
  'unlimited_access': 'Unbegrenzter Zugang',
  'no_ads': 'Keine Werbung',
  'faster_speeds': 'Schnellere Geschwindigkeiten',
  'all_locations': 'Alle Standorte',
  'monthly_plan': 'Monatlich',
  'yearly_plan': 'Jährlich',
  'lifetime_plan': 'Lebenslang',
  'subscribe': 'Abonnieren',
  'restore_purchases': 'Käufe Wiederherstellen',
  'premium_features': 'Premium-Funktionen',

  // Settings Screen
  'connection': 'Verbindung',
  'appearance': 'Erscheinungsbild',
  'account': 'Konto',
  'miscellaneous': 'Sonstiges',
  'protocol': 'Protokoll',
  'kill_switch': 'Kill Switch',
  'auto_connect': 'Auto-Verbindung',
  'theme': 'Design',
  'accent_color': 'Akzentfarbe',
  'language': 'Sprache',
  'premium_status': 'Premium-Status',
  'account_management': 'Kontoverwaltung',
  'purchase_history': 'Kaufhistorie',
  'notifications': 'Benachrichtigungen',
  'about': 'Über',
  'privacy_policy': 'Datenschutz-Bestimmungen',
  'terms_of_service': 'Nutzungsbedingungen',
  'support': 'Support',
  'rate_app': 'App Bewerten',
  'share_app': 'App Teilen',
  'version': 'Version',

  // Theme
  'light_mode': 'Hell',
  'dark_mode': 'Dunkel',
  'system_default': 'System',

  // Protocol
  'udp_recommended': 'UDP (Empfohlen)',
  'tcp_reliable': 'TCP (Zuverlässig)',

  // Common
  'ok': 'OK',
  'cancel': 'Abbrechen',
  'save': 'Speichern',
  'delete': 'Löschen',
  'edit': 'Bearbeiten',
  'yes': 'Ja',
  'no': 'Nein',
  'error': 'Fehler',
  'success': 'Erfolg',
  'warning': 'Warnung',
  'info': 'Info',

  // Messages
  'connection_successful': 'Erfolgreich verbunden',
  'connection_failed': 'Verbindung fehlgeschlagen',
  'disconnection_successful': 'Erfolgreich getrennt',
  'please_select_server': 'Bitte wählen Sie einen Server',
  'premium_required': 'Premium-Abonnement erforderlich',
  'no_internet_connection': 'Keine Internetverbindung',

  // App Drawer
  'my_account': 'Mein Konto',
  'sign_in': 'Anmelden',
  'sign_out': 'Abmelden',
  'select_language': 'Sprache Auswählen',

  // Extended Home Screen
  'time_expired': 'Zeit Abgelaufen',
  'time_expired_message':
      'Ihre kostenlose Verbindungszeit ist abgelaufen. Upgraden Sie auf Premium für unbegrenzten VPN-Zugang oder sehen Sie sich eine Anzeige an, um mehr Zeit zu erhalten!',
  'watch_ad_5_min': 'Anzeige Ansehen (+5 Min)',
  'upgrade_now': 'Jetzt Upgraden',
  'server_details': 'Server-Details',
  'server_ip': 'Server-IP',
  'status': 'Status',
  'active': 'Aktiv',
  'inactive': 'Inaktiv',
  'close': 'Schließen',
  'secure_fast_reliable': 'Sicher • Schnell • Zuverlässig',
  'free': 'KOSTENLOS',
  'upgrade': 'UPGRADE',

  // Extended Server Screen
  'connect_to_server': 'Mit Server Verbinden',
  'requires_premium': 'Erfordert Premium',
  'get_premium': 'Premium Holen',
  'ms': 'ms',
  'online': 'Online',
  'offline': 'Offline',

  // Extended Premium Screen
  'ultra_fast_servers': 'Ultra-Schnelle Server',
  'access_premium_servers':
      'Zugriff auf Premium-Hochgeschwindigkeitsserver weltweit',
  'advanced_security': 'Fortgeschrittene Sicherheit',
  'advanced_encryption': 'Erweiterte Verschlüsselung und Sicherheitsprotokolle',
  'ad_free_experience': 'Werbefreies Erlebnis',
  'no_interruptions':
      'Keine Werbung, keine Unterbrechungen, reines VPN-Erlebnis',
  'unlimited_devices': 'Unbegrenzte Geräte',
  'connect_unlimited_devices':
      'Verbinden Sie unbegrenzt Geräte mit einem Abonnement',
  'priority_support': '24/7 Prioritäts-Support',
  'instant_help': 'Erhalten Sie sofortige Hilfe, wann immer Sie sie benötigen',
  'premium_locations': 'Premium-Standorte',
  'exclusive_servers': 'Zugriff auf exklusive Server-Standorte',
  'choose_your_plan': 'Wählen Sie Ihren Plan',
  'best_value': 'BESTER WERT',
  'most_popular': 'AM BELIEBTESTEN',
  'popular': 'BELIEBT',
  'select_plan': 'Plan Auswählen',
  'processing': 'Wird bearbeitet...',
  'please_wait': 'Bitte warten...',
  'purchase_successful': 'Kauf Erfolgreich!',
  'purchase_failed': 'Kauf Fehlgeschlagen',
  'already_premium': 'Sie sind bereits Premium-Mitglied!',
  'sign_in_required': 'Anmeldung Erforderlich',
  'sign_in_to_purchase':
      'Bitte melden Sie sich mit Ihrem Google-Konto an, um Premium zu kaufen.',

  // Auth Screen
  'welcome_back': 'Willkommen zurück',
  'create_your_account': 'Erstellen Sie Ihr Konto',
  'axe_vpn': 'VPN MASTER',
  'sign_in_with_google': 'Mit Google Anmelden',
  'or': 'ODER',
  'email': 'E-Mail',
  'password': 'Passwort',
  'name': 'Name',
  'continue': 'Weiter',
  'continue_with_google': 'Mit Google Fortfahren',
  'later': 'Später',

  // Privacy & Terms
  'privacy_policy_title': 'Datenschutzrichtlinie',
  'last_updated': 'Zuletzt aktualisiert',
  'read_our_privacy_policy': 'Lesen Sie unsere Datenschutzrichtlinie',
  'terms_title': 'Nutzungsbedingungen',
  'read_our_terms': 'Lesen Sie unsere Bedingungen',

  // Support
  'contact_support_title': 'Support Kontaktieren',
  'get_help': 'Hilfe zur App erhalten',

  // Common Messages
  'something_went_wrong': 'Etwas ist schief gelaufen',
  'try_again': 'Erneut Versuchen',
  'maybe_later': 'Vielleicht Später',
  'rate_now': 'Jetzt Bewerten',
  'got_it': 'Verstanden',

  // Popup - Premium Server Unlock
  'unlock_premium_server': 'Premium-Server Freischalten',
  'watch_3_videos_unlock':
      'Sehen Sie sich 3 Videos an, um temporären Zugriff freizuschalten',
  'video_1': 'Video 1',
  'video_2': 'Video 2',
  'video_3': 'Video 3',
  'watch_now': 'Jetzt Anschauen',
  'or_go_premium': 'Oder Zur Premium Gehen',
  'server_unlocked_for': 'Server für %s Minuten freigeschaltet!',

  // Popup - Extend Free Time
  'extend_free_time': 'Kostenlose Zeit Verlängern',
  'watch_videos_continue': 'Videos ansehen zum Fortfahren',
  'free_time_extended': 'Kostenlose Zeit um %s Minuten verlängert!',

  // Extended Home Screen - Additional
  'kill_switch_activated': 'Kill Switch Aktiviert',
  'disable_kill_switch': 'Kill Switch Deaktivieren',
  'reconnect': 'Wiederverbinden',
  'subscribe_for_premium':
      'Bitte abonnieren Sie, um auf Premium-Server zuzugreifen',
  'load': 'Last',
  'connected_users': 'Verbundene Benutzer',
  'free_time_limit': 'Kostenlose Zeitgrenze',
  'unlimited': 'Unbegrenzt',
  'currently_connected': 'Derzeit Verbunden',
  'connection_secure': 'Ihre Verbindung ist sicher',
  'connection_not_secure': 'Ihre Verbindung ist nicht sicher',
  'wireguard': 'WireGuard',
  'anyconnect': 'AnyConnect',
  'openvpn_label': 'OpenVPN',
  'protected': 'GESCHÜTZT',
  'not_protected': 'NICHT GESCHÜTZT',
  'connecting_status': 'VERBINDEN',
  'authenticating': 'AUTHENTIFIZIERUNG',
  'disconnecting_status': 'TRENNEN',
  'connection_error': 'VERBINDUNGSFEHLER',
  'permission_denied_status': 'ZUGRIFF VERWEIGERT',
  'free_connection_time': 'Kostenlose Verbindungszeit',
  'go_premium': 'Premium Holen',
  'duration': 'Dauer',

  // Extended Server Screen - Additional
  'free_only': 'Nur kostenlos',
  'failed_to_load_servers': 'Server konnten nicht geladen werden',
  'filter_servers': 'Server Filtern',
  'show_only_premium_servers': 'Nur Premium-Server anzeigen',
  'show_only_free_servers': 'Nur kostenlose Server anzeigen',
  'clear': 'Löschen',
  'apply': 'Anwenden',
  'ip_address': 'IP-Adresse',
  'free_limit': 'Kostenlose Grenze',
  'watch_video_or_upgrade':
      'Sehen Sie ein Video oder upgraden Sie für Premium-Server',
  'premium_server_access': 'Premium-Server-Zugang',

  // Extended Premium Screen - Additional
  'unlock_premium': 'Premium Freischalten',
  'access_all_servers_features': 'Zugriff auf alle Server & Premium-Funktionen',
  'subscribe_now': 'Jetzt Abonnieren',
  'my_receipts': 'Meine Quittungen',
  'redeem_voucher': 'Gutschein Einlösen',
  'lifetime_access': 'Lebenslanger Zugang · Läuft nie Ab',
  'receipts': 'Quittungen',
  'voucher': 'Gutschein',
  'upgrade_extend_plan': 'Plan Upgraden / Verlängern',
  'whats_included': 'Was ist enthalten',
  'expired': 'Abgelaufen',
  'days_left': 'Tage verbleibend',
  'one_time': 'EINMALIG',
  'one_time_payment': 'Einmalzahlung',

  // Auth Screen - Extended
  'login_title': 'VPN MASTER',
  'login_sign_in_continue': 'Anmelden um fortzufahren',
  'continue_with_apple': 'Mit Apple fortfahren',
  'enter_email': 'E-Mail eingeben',
  'enter_password': 'Passwort eingeben',
  'forgot_password': 'Passwort vergessen?',
  'sign_up': 'Registrieren',
  'dont_have_account': 'Noch kein Konto?',
  'already_have_account': 'Bereits ein Konto?',
  'continue_as_guest': 'Als Gast fortfahren',
  'by_continuing_agree': 'Mit der Fortsetzung stimmen Sie unseren',
  'terms_conditions': 'AGB',
  'apple_eula': 'Apple EULA',
  'accept_legal_terms': 'Rechtliche Bedingungen akzeptieren',
  'legal_acceptance_description':
      'Bitte lesen Sie unsere Datenschutzrichtlinie, AGB und Apple EULA, bevor Sie fortfahren.',

  // Premium Screen - Extended
  'premium_subtitle': 'Zugang zu allen Servern & Premium-Funktionen',
  'advanced_grade_security': 'Fortschrittliche Sicherheit',
  'subscription_terms': 'Abonnementbedingungen',
  'subscription_terms_description':
      'Lesen Sie die Datenschutzrichtlinie, AGB und Apple EULA, bevor Sie abonnieren.',
  'select_best_plan': 'Wählen Sie den besten Plan für Sie',
  'one_month': '1 Monat',
  'three_months': '3 Monate',
  'one_year': '1 Jahr',
  'continue_to_checkout': 'Weiter zur Kasse',
};

// Portuguese translations
const Map<String, String> _ptTranslations = {
  'app_name': 'VPN MASTER',
  'home': 'Início',
  'servers': 'Servidores',
  'premium': 'Premium',
  'settings': 'Configurações',

  // Home Screen
  'connect': 'Conectar',
  'disconnect': 'Desconectar',
  'connecting': 'Conectando',
  'disconnecting': 'Desconectando',
  'connected': 'Conectado',
  'disconnected': 'Desconectado',
  'tap_to_connect': 'Toque para Conectar',
  'tap_to_disconnect': 'Toque para Desconectar',
  'connected_to': 'Conectado a',
  'select_server': 'Selecionar Servidor',
  'your_ip': 'Seu IP',
  'vpn_ip': 'IP VPN',
  'location': 'Localização',
  'download_speed': 'Download',
  'upload_speed': 'Upload',
  'connection_time': 'Tempo',

  // Server Screen
  'all_servers': 'Todos os Servidores',
  'free_servers': 'Servidores Gratuitos',
  'premium_servers': 'Servidores Premium',
  'search_servers': 'Pesquisar Servidores',
  'no_servers_found': 'Nenhum servidor encontrado',
  'loading': 'Carregando...',
  'premium_only': 'Apenas Premium',
  'best': 'Melhor',
  'ping': 'Ping',

  // Premium Screen
  'upgrade_to_premium': 'Atualizar',
  'unlimited_access': 'Acesso Ilimitado',
  'no_ads': 'Sem Anúncios',
  'faster_speeds': 'Velocidades Mais Rápidas',
  'all_locations': 'Todas as Localizações',
  'monthly_plan': 'Mensal',
  'yearly_plan': 'Anual',
  'lifetime_plan': 'Vitalício',
  'subscribe': 'Assinar',
  'restore_purchases': 'Restaurar Compras',
  'premium_features': 'Recursos Premium',

  // Settings Screen
  'connection': 'Conexão',
  'appearance': 'Aparência',
  'account': 'Conta',
  'miscellaneous': 'Diversos',
  'protocol': 'Protocolo',
  'kill_switch': 'Kill Switch',
  'auto_connect': 'Conexão Automática',
  'theme': 'Tema',
  'accent_color': 'Cor de Destaque',
  'language': 'Idioma',
  'premium_status': 'Status Premium',
  'account_management': 'Gerenciamento de Conta',
  'purchase_history': 'Histórico de Compras',
  'notifications': 'Notificações',
  'about': 'Sobre',
  'privacy_policy': 'Política de Privacidade',
  'terms_of_service': 'Termos de Serviço',
  'support': 'Suporte',
  'rate_app': 'Avaliar App',
  'share_app': 'Compartilhar App',
  'version': 'Versão',

  // Theme
  'light_mode': 'Claro',
  'dark_mode': 'Escuro',
  'system_default': 'Sistema',

  // Protocol
  'udp_recommended': 'UDP (Recomendado)',
  'tcp_reliable': 'TCP (Confiável)',

  // Common
  'ok': 'OK',
  'cancel': 'Cancelar',
  'save': 'Salvar',
  'delete': 'Excluir',
  'edit': 'Editar',
  'yes': 'Sim',
  'no': 'Não',
  'error': 'Erro',
  'success': 'Sucesso',
  'warning': 'Aviso',
  'info': 'Info',

  // Messages
  'connection_successful': 'Conectado com sucesso',
  'connection_failed': 'Falha na conexão',
  'disconnection_successful': 'Desconectado com sucesso',
  'please_select_server': 'Por favor selecione um servidor',
  'premium_required': 'Assinatura Premium necessária',
  'no_internet_connection': 'Sem conexão com a Internet',

  // App Drawer
  'my_account': 'Minha Conta',
  'sign_in': 'Entrar',
  'sign_out': 'Sair',
  'select_language': 'Selecionar Idioma',

  // Extended Home Screen
  'time_expired': 'Tempo Expirado',
  'time_expired_message':
      'Seu tempo de conexão gratuita expirou. Atualize para Premium para acesso VPN ilimitado ou assista a um anúncio para obter mais tempo!',
  'watch_ad_5_min': 'Assistir Anúncio (+5 min)',
  'upgrade_now': 'Atualizar Agora',
  'server_details': 'Detalhes do Servidor',
  'server_ip': 'IP do Servidor',
  'status': 'Status',
  'active': 'Ativo',
  'inactive': 'Inativo',
  'close': 'Fechar',
  'secure_fast_reliable': 'Seguro • Rápido • Confiável',
  'free': 'GRÁTIS',
  'upgrade': 'ATUALIZAR',

  // Extended Server Screen
  'connect_to_server': 'Conectar ao Servidor',
  'requires_premium': 'Requer Premium',
  'get_premium': 'Obter Premium',
  'ms': 'ms',
  'online': 'Online',
  'offline': 'Offline',

  // Extended Premium Screen
  'ultra_fast_servers': 'Servidores Ultra-Rápidos',
  'access_premium_servers':
      'Acesso a servidores premium de alta velocidade em todo o mundo',
  'advanced_security': 'Segurança de Nível Avançado',
  'advanced_encryption': 'Protocolos avançados de criptografia e segurança',
  'ad_free_experience': 'Experiência Sem Anúncios',
  'no_interruptions': 'Sem anúncios, sem interrupções, experiência VPN pura',
  'unlimited_devices': 'Dispositivos Ilimitados',
  'connect_unlimited_devices':
      'Conecte dispositivos ilimitados com uma assinatura',
  'priority_support': 'Suporte Prioritário 24/7',
  'instant_help': 'Obtenha ajuda instantânea sempre que precisar',
  'premium_locations': 'Localizações Premium',
  'exclusive_servers': 'Acesso a localizações exclusivas de servidores',
  'choose_your_plan': 'Escolha Seu Plano',
  'best_value': 'MELHOR VALOR',
  'most_popular': 'MAIS POPULAR',
  'popular': 'POPULAR',
  'select_plan': 'Selecionar Plano',
  'processing': 'Processando...',
  'please_wait': 'Por favor, aguarde...',
  'purchase_successful': 'Compra Bem-Sucedida!',
  'purchase_failed': 'Compra Falhou',
  'already_premium': 'Você já é membro Premium!',
  'sign_in_required': 'Login Necessário',
  'sign_in_to_purchase':
      'Por favor, faça login com sua conta do Google para comprar Premium.',

  // Auth Screen
  'welcome_back': 'Bem-vindo de volta',
  'create_your_account': 'Crie sua conta',
  'axe_vpn': 'VPN MASTER',
  'sign_in_with_google': 'Entrar com o Google',
  'or': 'OU',
  'email': 'E-mail',
  'password': 'Senha',
  'name': 'Nome',
  'continue': 'Continuar',
  'continue_with_google': 'Continuar com o Google',
  'later': 'Mais Tarde',

  // Privacy & Terms
  'privacy_policy_title': 'Política de Privacidade',
  'last_updated': 'Última atualização',
  'read_our_privacy_policy': 'Leia nossa política de privacidade',
  'terms_title': 'Termos de Serviço',
  'read_our_terms': 'Leia nossos termos',

  // Support
  'contact_support_title': 'Contatar Suporte',
  'get_help': 'Obtenha ajuda com o app',

  // Common Messages
  'something_went_wrong': 'Algo deu errado',
  'try_again': 'Tentar Novamente',
  'maybe_later': 'Talvez Depois',
  'rate_now': 'Avaliar Agora',
  'got_it': 'Entendi',

  // Popup - Premium Server Unlock
  'unlock_premium_server': 'Desbloquear Servidor Premium',
  'watch_3_videos_unlock':
      'Assista 3 vídeos para desbloquear acesso temporário',
  'video_1': 'Vídeo 1',
  'video_2': 'Vídeo 2',
  'video_3': 'Vídeo 3',
  'watch_now': 'Assistir Agora',
  'or_go_premium': 'Ou Ir para Premium',
  'server_unlocked_for': 'Servidor desbloqueado por %s minutos!',

  // Popup - Extend Free Time
  'extend_free_time': 'Estender Tempo Livre',
  'watch_videos_continue': 'Assista vídeos para continuar',
  'free_time_extended': 'Tempo livre estendido por %s minutos!',

  // Extended Home Screen - Additional
  'kill_switch_activated': 'Kill Switch Ativado',
  'disable_kill_switch': 'Desativar Kill Switch',
  'reconnect': 'Reconectar',
  'subscribe_for_premium': 'Por favor assine para acessar servidores premium',
  'load': 'Carga',
  'connected_users': 'Usuários Conectados',
  'free_time_limit': 'Limite de Tempo Gratuito',
  'unlimited': 'Ilimitado',
  'currently_connected': 'Atualmente Conectado',
  'connection_secure': 'Sua conexão está segura',
  'connection_not_secure': 'Sua conexão não está segura',
  'wireguard': 'WireGuard',
  'anyconnect': 'AnyConnect',
  'openvpn_label': 'OpenVPN',
  'protected': 'PROTEGIDO',
  'not_protected': 'NÃO PROTEGIDO',
  'connecting_status': 'CONECTANDO',
  'authenticating': 'AUTENTICANDO',
  'disconnecting_status': 'DESCONECTANDO',
  'connection_error': 'ERRO DE CONEXÃO',
  'permission_denied_status': 'PERMISSÃO NEGADA',
  'free_connection_time': 'Tempo de Conexão Gratuita',
  'go_premium': 'Ir para Premium',
  'duration': 'Duração',

  // Extended Server Screen - Additional
  'free_only': 'Somente gratuito',
  'failed_to_load_servers': 'Falha ao carregar servidores',
  'filter_servers': 'Filtrar Servidores',
  'show_only_premium_servers': 'Mostrar apenas servidores premium',
  'show_only_free_servers': 'Mostrar apenas servidores gratuitos',
  'clear': 'Limpar',
  'apply': 'Aplicar',
  'ip_address': 'Endereço IP',
  'free_limit': 'Limite Grátis',
  'watch_video_or_upgrade':
      'Assista um vídeo ou atualize para acessar servidores premium',
  'premium_server_access': 'Acesso a Servidores Premium',

  // Extended Premium Screen - Additional
  'unlock_premium': 'Desbloquear Premium',
  'access_all_servers_features':
      'Acesse todos os servidores e recursos premium',
  'subscribe_now': 'Assinar Agora',
  'my_receipts': 'Meus Recibos',
  'redeem_voucher': 'Resgatar Voucher',
  'lifetime_access': 'Acesso Vitalício · Nunca Expira',
  'receipts': 'Recibos',
  'voucher': 'Voucher',
  'upgrade_extend_plan': 'Atualizar / Estender Plano',
  'whats_included': 'O que está incluído',
  'expired': 'Expirado',
  'days_left': 'dias restantes',
  'one_time': 'ÚNICO',
  'one_time_payment': 'pagamento único',

  // Auth Screen - Extended
  'login_title': 'VPN MASTER',
  'login_sign_in_continue': 'Entre para continuar',
  'continue_with_apple': 'Continuar com Apple',
  'enter_email': 'Digite seu e-mail',
  'enter_password': 'Digite sua senha',
  'forgot_password': 'Esqueceu a senha?',
  'sign_up': 'Cadastrar',
  'dont_have_account': 'Não tem uma conta?',
  'already_have_account': 'Já tem uma conta?',
  'continue_as_guest': 'Continuar como visitante',
  'by_continuing_agree': 'Ao continuar, você concorda com nossos',
  'terms_conditions': 'Termos e Condições',
  'apple_eula': 'EULA da Apple',
  'accept_legal_terms': 'Aceitar termos legais',
  'legal_acceptance_description':
      'Leia nossa Política de Privacidade, Termos e Condições e EULA da Apple antes de continuar.',

  // Premium Screen - Extended
  'premium_subtitle': 'Acesse todos os servidores e recursos premium',
  'advanced_grade_security': 'Segurança de Nível Avançado',
  'subscription_terms': 'Termos de assinatura',
  'subscription_terms_description':
      'Leia a Política de Privacidade, Termos e Condições e EULA da Apple antes de assinar.',
  'select_best_plan': 'Selecione o melhor plano para você',
  'one_month': '1 Mês',
  'three_months': '3 Meses',
  'one_year': '1 Ano',
  'continue_to_checkout': 'Continuar para pagamento',
};

// Italian translations
const Map<String, String> _itTranslations = {
  'app_name': 'VPN MASTER',
  'home': 'Home',
  'servers': 'Server',
  'premium': 'Premium',
  'settings': 'Impostazioni',

  // Home Screen
  'connect': 'Connetti',
  'disconnect': 'Disconnetti',
  'connecting': 'Connessione',
  'disconnecting': 'Disconnessione',
  'connected': 'Connesso',
  'disconnected': 'Disconnesso',
  'tap_to_connect': 'Tocca per Connettere',
  'tap_to_disconnect': 'Tocca per Disconnettere',
  'connected_to': 'Connesso a',
  'select_server': 'Seleziona Server',
  'your_ip': 'Il Tuo IP',
  'vpn_ip': 'IP VPN',
  'location': 'Posizione',
  'download_speed': 'Download',
  'upload_speed': 'Upload',
  'connection_time': 'Tempo',

  // Server Screen
  'all_servers': 'Tutti i Server',
  'free_servers': 'Server Gratuiti',
  'premium_servers': 'Server Premium',
  'search_servers': 'Cerca Server',
  'no_servers_found': 'Nessun server trovato',
  'loading': 'Caricamento...',
  'premium_only': 'Solo Premium',
  'best': 'Migliore',
  'ping': 'Ping',

  // Premium Screen
  'upgrade_to_premium': 'Aggiorna',
  'unlimited_access': 'Accesso Illimitato',
  'no_ads': 'Nessuna Pubblicità',
  'faster_speeds': 'Velocità Più Elevate',
  'all_locations': 'Tutte le Posizioni',
  'monthly_plan': 'Mensile',
  'yearly_plan': 'Annuale',
  'lifetime_plan': 'A Vita',
  'subscribe': 'Abbonati',
  'restore_purchases': 'Ripristina Acquisti',
  'premium_features': 'Funzionalità Premium',

  // Settings Screen
  'connection': 'Connessione',
  'appearance': 'Aspetto',
  'account': 'Account',
  'miscellaneous': 'Varie',
  'protocol': 'Protocollo',
  'kill_switch': 'Kill Switch',
  'auto_connect': 'Connessione Automatica',
  'theme': 'Tema',
  'accent_color': 'Colore di Accento',
  'language': 'Lingua',
  'premium_status': 'Stato Premium',
  'account_management': 'Gestione Account',
  'purchase_history': 'Cronologia Acquisti',
  'notifications': 'Notifiche',
  'about': 'Informazioni',
  'privacy_policy': 'Informativa sulla Privacy',
  'terms_of_service': 'Termini di Servizio',
  'support': 'Supporto',
  'rate_app': 'Valuta App',
  'share_app': 'Condividi App',
  'version': 'Versione',

  // Theme
  'light_mode': 'Chiaro',
  'dark_mode': 'Scuro',
  'system_default': 'Sistema',

  // Protocol
  'udp_recommended': 'UDP (Consigliato)',
  'tcp_reliable': 'TCP (Affidabile)',

  // Common
  'ok': 'OK',
  'cancel': 'Annulla',
  'save': 'Salva',
  'delete': 'Elimina',
  'edit': 'Modifica',
  'yes': 'Sì',
  'no': 'No',
  'error': 'Errore',
  'success': 'Successo',
  'warning': 'Avviso',
  'info': 'Info',

  // Messages
  'connection_successful': 'Connesso con successo',
  'connection_failed': 'Connessione fallita',
  'disconnection_successful': 'Disconnesso con successo',
  'please_select_server': 'Seleziona un server',
  'premium_required': 'Abbonamento Premium richiesto',
  'no_internet_connection': 'Nessuna connessione Internet',

  // App Drawer
  'my_account': 'Il Mio Account',
  'sign_in': 'Accedi',
  'sign_out': 'Esci',
  'select_language': 'Seleziona Lingua',

  // Extended Home Screen
  'time_expired': 'Tempo Scaduto',
  'time_expired_message':
      'Il tuo tempo di connessione gratuita è scaduto. Passa a Premium per accesso VPN illimitato o guarda un annuncio per ottenere più tempo!',
  'watch_ad_5_min': 'Guarda Annuncio (+5 min)',
  'upgrade_now': 'Aggiorna Ora',
  'server_details': 'Dettagli Server',
  'server_ip': 'IP Server',
  'status': 'Stato',
  'active': 'Attivo',
  'inactive': 'Inattivo',
  'close': 'Chiudi',
  'secure_fast_reliable': 'Sicuro • Veloce • Affidabile',
  'free': 'GRATUITO',
  'upgrade': 'AGGIORNA',

  // Extended Server Screen
  'connect_to_server': 'Connetti al Server',
  'requires_premium': 'Richiede Premium',
  'get_premium': 'Ottieni Premium',
  'ms': 'ms',
  'online': 'Online',
  'offline': 'Offline',

  // Extended Premium Screen
  'ultra_fast_servers': 'Server Ultra-Veloci',
  'access_premium_servers':
      'Accesso a server premium ad alta velocità in tutto il mondo',
  'advanced_security': 'Sicurezza di Livello Avanzato',
  'advanced_encryption': 'Crittografia avanzata e protocolli di sicurezza',
  'ad_free_experience': 'Esperienza Senza Pubblicità',
  'no_interruptions':
      'Nessuna pubblicità, nessuna interruzione, esperienza VPN pura',
  'unlimited_devices': 'Dispositivi Illimitati',
  'connect_unlimited_devices':
      'Connetti dispositivi illimitati con un abbonamento',
  'priority_support': 'Supporto Prioritario 24/7',
  'instant_help': 'Ottieni aiuto istantaneo quando ne hai bisogno',
  'premium_locations': 'Posizioni Premium',
  'exclusive_servers': 'Accesso a posizioni server esclusive',
  'choose_your_plan': 'Scegli Il Tuo Piano',
  'best_value': 'MIGLIOR VALORE',
  'most_popular': 'PIÙ POPOLARE',
  'popular': 'POPOLARE',
  'select_plan': 'Seleziona Piano',
  'processing': 'Elaborazione...',
  'please_wait': 'Attendere prego...',
  'purchase_successful': 'Acquisto Riuscito!',
  'purchase_failed': 'Acquisto Fallito',
  'already_premium': 'Sei già membro Premium!',
  'sign_in_required': 'Accesso Richiesto',
  'sign_in_to_purchase':
      'Accedi con il tuo account Google per acquistare Premium.',

  // Auth Screen
  'welcome_back': 'Bentornato',
  'create_your_account': 'Crea il tuo account',
  'axe_vpn': 'VPN MASTER',
  'sign_in_with_google': 'Accedi con Google',
  'or': 'OPPURE',
  'email': 'Email',
  'password': 'Password',
  'name': 'Nome',
  'continue': 'Continua',
  'continue_with_google': 'Continua con Google',
  'later': 'Più Tardi',

  // Privacy & Terms
  'privacy_policy_title': 'Informativa sulla Privacy',
  'last_updated': 'Ultimo aggiornamento',
  'read_our_privacy_policy': 'Leggi la nostra informativa sulla privacy',
  'terms_title': 'Termini di Servizio',
  'read_our_terms': 'Leggi i nostri termini',

  // Support
  'contact_support_title': 'Contatta il Supporto',
  'get_help': 'Ottieni aiuto con l\'app',

  // Common Messages
  'something_went_wrong': 'Qualcosa è andato storto',
  'try_again': 'Riprova',
  'maybe_later': 'Forse Più Tardi',
  'rate_now': 'Valuta Ora',
  'got_it': 'Ho Capito',

  // Popup - Premium Server Unlock
  'unlock_premium_server': 'Sblocca Server Premium',
  'watch_3_videos_unlock': 'Guarda 3 video per sbloccare l\'accesso temporaneo',
  'video_1': 'Video 1',
  'video_2': 'Video 2',
  'video_3': 'Video 3',
  'watch_now': 'Guarda Ora',
  'or_go_premium': 'O Vai a Premium',
  'server_unlocked_for': 'Server sbloccato per %s minuti!',

  // Popup - Extend Free Time
  'extend_free_time': 'Estendi Tempo Libero',
  'watch_videos_continue': 'Guarda i video per continuare',
  'free_time_extended': 'Tempo libero esteso di %s minuti!',

  // Extended Home Screen - Additional
  'kill_switch_activated': 'Kill Switch Attivato',
  'disable_kill_switch': 'Disabilita Kill Switch',
  'reconnect': 'Riconnetti',
  'subscribe_for_premium': 'Abbonati per accedere ai server premium',
  'load': 'Carico',
  'connected_users': 'Utenti Connessi',
  'free_time_limit': 'Limite di Tempo Gratuito',
  'unlimited': 'Illimitato',
  'currently_connected': 'Attualmente Connesso',
  'connection_secure': 'La tua connessione è sicura',
  'connection_not_secure': 'La tua connessione non è sicura',
  'wireguard': 'WireGuard',
  'anyconnect': 'AnyConnect',
  'openvpn_label': 'OpenVPN',
  'protected': 'PROTETTO',
  'not_protected': 'NON PROTETTO',
  'connecting_status': 'CONNESSIONE',
  'authenticating': 'AUTENTICAZIONE',
  'disconnecting_status': 'DISCONNESSIONE',
  'connection_error': 'ERRORE DI CONNESSIONE',
  'permission_denied_status': 'PERMESSO NEGATO',
  'free_connection_time': 'Tempo di Connessione Gratuita',
  'go_premium': 'Vai a Premium',
  'duration': 'Durata',

  // Extended Server Screen - Additional
  'free_only': 'Solo gratuiti',
  'failed_to_load_servers': 'Impossibile caricare i server',
  'filter_servers': 'Filtra Server',
  'show_only_premium_servers': 'Mostra solo server premium',
  'show_only_free_servers': 'Mostra solo server gratuiti',
  'clear': 'Cancella',
  'apply': 'Applica',
  'ip_address': 'Indirizzo IP',
  'free_limit': 'Limite Gratuito',
  'watch_video_or_upgrade':
      'Guarda un video o passa a Premium per accedere ai server premium',
  'premium_server_access': 'Accesso ai Server Premium',

  // Extended Premium Screen - Additional
  'unlock_premium': 'Sblocca Premium',
  'access_all_servers_features':
      'Accedi a tutti i server e funzionalità premium',
  'subscribe_now': 'Abbonati Ora',
  'my_receipts': 'Le Mie Ricevute',
  'redeem_voucher': 'Riscatta Voucher',
  'lifetime_access': 'Accesso a Vita · Non Scade Mai',
  'receipts': 'Ricevute',
  'voucher': 'Voucher',
  'upgrade_extend_plan': 'Aggiorna / Estendi Piano',
  'whats_included': 'Cosa è incluso',
  'expired': 'Scaduto',
  'days_left': 'giorni rimasti',
  'one_time': 'UNA TANTUM',
  'one_time_payment': 'pagamento unico',

  // Auth Screen - Extended
  'login_title': 'VPN MASTER',
  'login_sign_in_continue': 'Accedi per continuare',
  'continue_with_apple': 'Continua con Apple',
  'enter_email': 'Inserisci la tua email',
  'enter_password': 'Inserisci la tua password',
  'forgot_password': 'Password dimenticata?',
  'sign_up': 'Registrati',
  'dont_have_account': 'Non hai un account?',
  'already_have_account': 'Hai già un account?',
  'continue_as_guest': 'Continua come ospite',
  'by_continuing_agree': 'Continuando, accetti i nostri',
  'terms_conditions': 'Termini e Condizioni',
  'apple_eula': 'EULA Apple',
  'accept_legal_terms': 'Accetta i termini legali',
  'legal_acceptance_description':
      'Leggi la nostra Informativa sulla privacy, i T&C e l\'EULA Apple prima di continuare.',

  // Premium Screen - Extended
  'premium_subtitle': 'Accedi a tutti i server e le funzioni premium',
  'advanced_grade_security': 'Sicurezza di Livello Avanzato',
  'subscription_terms': 'Termini di abbonamento',
  'subscription_terms_description':
      'Leggi l\'Informativa sulla privacy, i T&C e l\'EULA Apple prima di abbonarti.',
  'select_best_plan': 'Seleziona il piano migliore per te',
  'one_month': '1 Mese',
  'three_months': '3 Mesi',
  'one_year': '1 Anno',
  'continue_to_checkout': 'Vai al pagamento',
};
