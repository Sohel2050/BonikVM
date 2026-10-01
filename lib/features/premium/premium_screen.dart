// lib/features/premium/premium_screen.dart
// Quickro-POS-style subscription screen.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import '../../shared/providers/theme_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../core/localization/app_localizations.dart';
import '../../services/billing_service.dart';
import '../../screens/auth/legal_webview_screen.dart';
import 'billing_bottom_sheets.dart';

// ignore: library_private_types_in_public_api
final GlobalKey<_PremiumScreenState> premiumScreenKey =
GlobalKey<_PremiumScreenState>();

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key, this.autoRefresh = false});
  final bool autoRefresh;

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  static const _appleEulaUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  String? _selectedProductId;

  void refresh() => ref.read(subscriptionProvider.notifier).refresh();
  // Alias used by MainShell toolbar
  void refreshProducts() => refresh();

  // Plans come only from the admin panel (via the API). No hardcoded fallback,
  // so a stale price or a product that does not exist in the store is never shown.
  List<Map<String, dynamic>> _parseCatalog(SubscriptionState sub) =>
      sub.planCatalog;

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider);
    final theme = ref.watch(themeColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F4F8);
    final catalog = _parseCatalog(sub);

    if (_selectedProductId == null && catalog.isNotEmpty) {
      final popular = catalog.firstWhere(
            (p) => p['is_popular'] == true,
        orElse: () => catalog.first,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          setState(() => _selectedProductId = popular['product_id'] as String?);
      });
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: sub.isLoading
          ? Center(child: CircularProgressIndicator(color: theme))
          : sub.isPremium
          ? _ActiveView(
        sub: sub,
        theme: theme,
        isDark: isDark,
        screenState: this,
      )
          : catalog.isEmpty
          ? _PlansUnavailable(
        theme: theme,
        isDark: isDark,
        onRetry: refresh,
      )
          : _SelectView(
        catalog: catalog,
        theme: theme,
        isDark: isDark,
        selectedId: _selectedProductId,
        onSelect: (id) => setState(() => _selectedProductId = id),
        bg: bg,
      ),
    );
  }
}

// ─── ACTIVE SUBSCRIPTION ─────────────────────────────────────────────────────

class _ActiveView extends StatelessWidget {
  const _ActiveView({
    required this.sub,
    required this.theme,
    required this.isDark,
    required this.screenState,
  });
  final SubscriptionState sub;
  final Color theme;
  final bool isDark;
  final _PremiumScreenState screenState;

  @override
  Widget build(BuildContext context) {
    final name = sub.displayName;
    final expiresAt = sub.expiresAt;
    final isLife = sub.isLifetime;
    final source = (sub.subscription?['platform'] as String? ?? 'unknown')
        .toUpperCase();
    final daysLeft = expiresAt != null
        ? expiresAt.difference(DateTime.now()).inDays
        : null;
    final totalDays = (sub.subscription?['duration_days'] as num?)?.toInt();
    double? progress;
    if (!isLife && expiresAt != null && totalDays != null && totalDays > 0) {
      progress = ((totalDays - (daysLeft ?? 0)) / totalDays).clamp(0.0, 1.0);
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero status card ──────────────────────────────────
            FadeInDown(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme,
                      theme.withValues(alpha: 0.72),
                      Colors.green.shade700,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: theme.withValues(alpha: 0.35),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _CircleIcon(
                          icon: Icons.currency_exchange,
                          bg: Colors.white.withValues(alpha: 0.18),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _Pill(
                                label: source,
                                bg: Colors.white.withValues(alpha: 0.2),
                                textColor: Colors.white70,
                              ),
                            ],
                          ),
                        ),
                        _Pill(
                          label: '✓  ACTIVE',
                          bg: Colors.white.withValues(alpha: 0.2),
                          textColor: Colors.white70,
                          fontSize: 12,
                        ),
                      ],
                    ),
                    // Expiry / lifetime info
                    if (isLife) ...[
                      const SizedBox(height: 18),
                      const Divider(),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.all_inclusive,
                            color: Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context).lifetimeAccess,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ] else if (expiresAt != null) ...[
                      const SizedBox(height: 18),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.event,
                            color: Colors.white60,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _fmtDate(expiresAt),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            daysLeft != null && daysLeft < 0
                                ? AppLocalizations.of(context).expired
                                : '${daysLeft ?? 0} ${AppLocalizations.of(context).daysLeft}',
                            style: TextStyle(
                              color: (daysLeft ?? 0) <= 0
                                  ? Colors.red.shade200
                                  : (daysLeft! <= 7
                                  ? Colors.orange.shade200
                                  : Colors.white70),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                            valueColor: const AlwaysStoppedAnimation(
                              Colors.white70,
                            ),
                            minHeight: 7,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // ── Quick actions ─────────────────────────────────────
            FadeInUp(
              delay: const Duration(milliseconds: 80),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.receipt_long_outlined,
                      label: 'Receipts',
                      isDark: isDark,
                      theme: theme,
                      onTap: () => showReceiptsSheet(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.local_offer_outlined,
                      label: 'Voucher',
                      isDark: isDark,
                      theme: theme,
                      onTap: () {
                        final ref =
                            (context as Element)
                                .findAncestorStateOfType<ConsumerState>()
                                ?.ref ??
                                (screenState as ConsumerState).ref;
                        showVoucherSheet(context, ref);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FadeInUp(
              delay: const Duration(milliseconds: 140),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(Icons.upgrade_rounded, color: theme),
                  label: Text(
                    AppLocalizations.of(context).upgradeExtendPlan,
                    style: TextStyle(color: theme, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => screenState.refresh(),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // ── Included features ─────────────────────────────────
            FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: Text(
                AppLocalizations.of(context).whatsIncluded,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
            ),
            ..._kFeatures(context).map(
                  (f) => FadeInUp(
                delay: const Duration(milliseconds: 230),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: theme.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(f.$1, color: theme, size: 18),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.$2,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(
                              f.$3,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // ── Cancel subscription ───────────────────────────────
            FadeInUp(
              delay: const Duration(milliseconds: 260),
              child: _CancelButton(
                isDark: isDark,
                platform: sub.platform,
                screenState: screenState,
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ─── PLAN SELECTION ───────────────────────────────────────────────────────────

class _SelectView extends StatelessWidget {
  const _SelectView({
    required this.catalog,
    required this.theme,
    required this.isDark,
    required this.selectedId,
    required this.onSelect,
    required this.bg,
  });
  final List<Map<String, dynamic>> catalog;
  final Color theme;
  final bool isDark;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ref = (context as Element)
        .findAncestorStateOfType<ConsumerState>()
        ?.ref;

    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final subColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF6B7280);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE5E7EB);

    final selected = catalog.firstWhere(
          (p) => p['product_id'] == selectedId,
      orElse: () => <String, dynamic>{},
    );
    final savings = _computeSavings(catalog);
    final adminFeatures = _planFeatures(selected);

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hero ───────────────────────────────────────────
                  FadeInDown(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.withValues(alpha: isDark ? 0.22 : 0.16),
                            theme.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  theme,
                                  theme.withValues(alpha: 0.7),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.withValues(alpha: 0.45),
                                  blurRadius: 28,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.workspace_premium_rounded,
                              color: Colors.white,
                              size: 42,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.unlockPremium,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.accessAllServersFeatures,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13.5, color: subColor),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.chooseYourPlan,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ── Plans (all data comes from the admin panel) ──
                        ...catalog.asMap().entries.map((entry) {
                          final plan = entry.value;
                          final id = plan['product_id'] as String?;
                          return FadeInUp(
                            delay: Duration(milliseconds: 55 * entry.key),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PlanCard(
                                plan: plan,
                                isSelected: selectedId == id,
                                savePercent: savings[id],
                                theme: theme,
                                isDark: isDark,
                                onTap: () => onSelect(id),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 10),

                        // ── What's included ──────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.whatsIncluded,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: titleColor,
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (adminFeatures.isNotEmpty)
                                ...adminFeatures.map(
                                      (t) => _FeatureRow(
                                    icon: Icons.check_circle_rounded,
                                    title: t,
                                    theme: theme,
                                    isDark: isDark,
                                  ),
                                )
                              else
                                ..._kFeatures(context).map(
                                      (f) => _FeatureRow(
                                    icon: f.$1,
                                    title: f.$2,
                                    subtitle: f.$3,
                                    theme: theme,
                                    isDark: isDark,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        _SubscriptionLegalLinks(
                          isDark: isDark,
                          themeColor: theme,
                          onOpenTerms: () =>
                              Navigator.pushNamed(context, '/terms'),
                          onOpenPrivacy: () =>
                              Navigator.pushNamed(context, '/privacy'),
                          onOpenAppleEula: Platform.isIOS
                              ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LegalWebViewScreen(
                                title: 'Apple EULA',
                                url: _PremiumScreenState._appleEulaUrl,
                              ),
                            ),
                          )
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () => showReceiptsSheet(context),
                              icon: Icon(
                                Icons.receipt_long_outlined,
                                size: 15,
                                color: Colors.grey.shade500,
                              ),
                              label: Text(
                                l10n.myReceipts,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 14,
                              color: Colors.grey.shade400,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                if (ref != null) showVoucherSheet(context, ref);
                              },
                              icon: Icon(
                                Icons.local_offer_outlined,
                                size: 15,
                                color: Colors.grey.shade500,
                              ),
                              label: Text(
                                l10n.redeemVoucher,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Pinned checkout bar ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme,
                  disabledBackgroundColor: theme.withValues(alpha: 0.35),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shadowColor: theme.withValues(alpha: 0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: selectedId == null || selected.isEmpty
                    ? null
                    : () {
                  final widgetRef = context
                      .findAncestorStateOfType<ConsumerState>()
                      ?.ref;
                  if (widgetRef != null) {
                    showPaymentMethodSheet(
                      context,
                      widgetRef,
                      selectedId!,
                      selected,
                    );
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_open_rounded, size: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        selected.isEmpty
                            ? l10n.continueToCheckout
                            : '${l10n.continueToCheckout}  •  \$${_fmtPrice(_planPrice(selected))}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Plan helpers (everything is derived from the admin-configured data) ─────

double _planPrice(Map<String, dynamic> p) {
  double? parse(dynamic v) => v == null ? null : double.tryParse(v.toString());
  final platform = Platform.isAndroid
      ? parse(p['android_price'])
      : (Platform.isIOS ? parse(p['ios_price']) : null);
  if (platform != null && platform > 0) return platform;
  return parse(p['web_price']) ?? 0;
}

int _planDays(Map<String, dynamic> p) {
  final d = p['duration_days'];
  if (d == null) return 0;
  return d is num ? d.toInt() : int.tryParse(d.toString()) ?? 0;
}

bool _planIsLifetime(Map<String, dynamic> p) =>
    p['is_lifetime'] == true || _planDays(p) == 0;

String _fmtPrice(double v) => v.toStringAsFixed(2);

String _planDuration(Map<String, dynamic> p) {
  final days = _planDays(p);
  if (days == 0) return 'Lifetime';
  if (days % 365 == 0) {
    final y = days ~/ 365;
    return y == 1 ? '1 year' : '$y years';
  }
  if (days % 30 == 0) {
    final m = days ~/ 30;
    return m == 1 ? '1 month' : '$m months';
  }
  return '$days days';
}

/// % saved per day versus the shortest plan, keyed by product_id.
Map<String?, int> _computeSavings(List<Map<String, dynamic>> catalog) {
  final timed = catalog
      .where((p) => !_planIsLifetime(p) && _planPrice(p) > 0)
      .toList();
  if (timed.length < 2) return {};
  timed.sort((a, b) => _planDays(a).compareTo(_planDays(b)));
  final base = _planPrice(timed.first) / _planDays(timed.first);
  final result = <String?, int>{};
  for (final p in timed.skip(1)) {
    final perDay = _planPrice(p) / _planDays(p);
    final pct = ((1 - perDay / base) * 100).round();
    if (pct >= 5) result[p['product_id'] as String?] = pct;
  }
  return result;
}

/// Feature lines the admin entered for the selected plan (if any).
List<String> _planFeatures(Map<String, dynamic> plan) {
  final raw = plan['features'];
  if (raw is! List) return const [];
  return raw
      .map((e) {
    if (e is Map) return (e['text'] ?? e['name'] ?? e['title'] ?? '').toString();
    return e.toString();
  })
      .where((t) => t.trim().isNotEmpty)
      .toList();
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.theme,
    required this.isDark,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color theme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: theme, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF6B7280),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionLegalLinks extends StatelessWidget {
  const _SubscriptionLegalLinks({
    required this.isDark,
    required this.themeColor,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
    this.onOpenAppleEula,
  });

  final bool isDark;
  final Color themeColor;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;
  final VoidCallback? onOpenAppleEula;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white70 : const Color(0xFF4B5563);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white70,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).subscriptionTerms,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).subscriptionTermsDescription,
            style: TextStyle(fontSize: 12, height: 1.45, color: textColor),
          ),
          const SizedBox(height: 10),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _LegalChip(
                      label: AppLocalizations.of(context).privacyPolicy,
                      onTap: onOpenPrivacy,
                      themeColor: themeColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _LegalChip(
                      label: AppLocalizations.of(context).termsConditions,
                      onTap: onOpenTerms,
                      themeColor: themeColor,
                    ),
                  ),
                ],
              ),
              if (onOpenAppleEula != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: _LegalChip(
                    label: AppLocalizations.of(context).appleEula,
                    onTap: onOpenAppleEula!,
                    themeColor: themeColor,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LegalChip extends StatelessWidget {
  const _LegalChip({
    required this.label,
    required this.onTap,
    required this.themeColor,
  });

  final String label;
  final VoidCallback onTap;
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: themeColor,
        side: BorderSide(color: themeColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

// ─── PLAN CARD (2-col grid) ───────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.theme,
    required this.isDark,
    required this.onTap,
    this.savePercent,
  });
  final Map<String, dynamic> plan;
  final bool isSelected;
  final Color theme;
  final bool isDark;
  final VoidCallback onTap;
  final int? savePercent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name =
        plan['display_name'] as String? ?? plan['product_id'] as String? ?? '';
    final price = _planPrice(plan);
    final days = _planDays(plan);
    final isLife = _planIsLifetime(plan);
    final isPopular = plan['is_popular'] == true;
    final perDay = (!isLife && days > 0 && price > 0) ? price / days : null;

    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final subColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF6B7280);

    Widget pill(String label, List<Color> colors, {IconData? icon}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 10, color: Colors.white),
              const SizedBox(width: 3),
            ],
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.withValues(alpha: isDark ? 0.12 : 0.07)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          border: Border.all(
            color: isSelected
                ? theme
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB)),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? theme.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? theme : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? theme
                      : (isDark
                      ? const Color(0xFF475569)
                      : const Color(0xFFD1D5DB)),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLife
                        ? l10n.oneTimePayment
                        : (perDay != null
                        ? '${_planDuration(plan)}  •  \$${perDay.toStringAsFixed(2)} / day'
                        : _planDuration(plan)),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: subColor,
                    ),
                  ),
                  if (isPopular || isLife || savePercent != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (isPopular)
                          pill(
                            l10n.popular,
                            [theme, theme.withValues(alpha: 0.75)],
                            icon: Icons.local_fire_department_rounded,
                          ),
                        if (isLife)
                          pill(
                            l10n.oneTime,
                            const [Color(0xFFD97706), Color(0xFFF59E0B)],
                            icon: Icons.star_rounded,
                          ),
                        if (savePercent != null)
                          pill(
                            'Save $savePercent%',
                            const [Color(0xFF059669), Color(0xFF10B981)],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${_fmtPrice(price)}',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? theme : titleColor,
                  ),
                ),
                if (!isLife) ...[
                  const SizedBox(height: 2),
                  Text(
                    _planDuration(plan),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.bg, this.size = 28});
  final IconData icon;
  final Color bg;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
    child: Icon(icon, color: Colors.white70, size: size),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.bg,
    required this.textColor,
    this.fontSize = 11,
  });
  final String label;
  final Color bg;
  final Color textColor;
  final double fontSize;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.theme,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool isDark;
  final Color theme;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: isDark ? const Color(0xFF161B22) : Colors.white70,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF30363D) : Colors.grey.shade200,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── FEATURE LIST ────────────────────────────────────────────────────────────

List<(IconData, String, String)> _kFeatures(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return [
    (Icons.flash_on, l10n.ultraFastServers, l10n.accessPremiumServers),
    (Icons.security, l10n.advancedGradeSecurity, l10n.advancedEncryption),
    (Icons.block, l10n.adFreeExperience, l10n.noInterruptions),
    (Icons.device_hub, l10n.unlimitedDevices, l10n.connectUnlimitedDevices),
    (Icons.public, l10n.premiumLocations, l10n.exclusiveServers),
  ];
}

// ─── CANCEL INFO SHEET (IAP) ─────────────────────────────────────────────────

class _CancelInfoSheet extends StatelessWidget {
  const _CancelInfoSheet({required this.isDark, required this.message});
  final bool isDark;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F2E) : Colors.white70,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.info_outline, color: Colors.blue, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Cancel Subscription',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black54,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Got it',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CANCEL CONFIRM SHEET ────────────────────────────────────────────────────

class _CancelConfirmSheet extends StatelessWidget {
  const _CancelConfirmSheet({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F2E) : Colors.white70,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cancel_outlined,
              color: Colors.red,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Cancel Subscription',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Are you sure you want to cancel your subscription?\n'
                'You will keep access until the end of the current billing period.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black54,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          // Keep button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Keep Subscription',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Cancel button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Cancel Subscription',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CANCEL BUTTON ────────────────────────────────────────────────────────────

class _CancelButton extends ConsumerStatefulWidget {
  const _CancelButton({
    required this.isDark,
    required this.platform,
    required this.screenState,
  });
  final bool isDark;
  final String? platform;
  final _PremiumScreenState screenState;

  @override
  ConsumerState<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends ConsumerState<_CancelButton> {
  bool _cancelling = false;

  bool get _isIap =>
      widget.platform == 'app_store' || widget.platform == 'google_play';

  Future<void> _onCancel() async {
    // IAP subscriptions: direct to the store's subscription management
    if (_isIap) {
      final msg = widget.platform == 'app_store'
          ? 'To cancel your App Store subscription, go to:\nSettings → Apple ID → Subscriptions.'
          : 'To cancel your Google Play subscription, open the Play Store → Subscriptions.';
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return _CancelInfoSheet(isDark: isDark, message: msg);
        },
      );
      return;
    }

    // Non-IAP: confirm then call backend cancel
    if (!mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return _CancelConfirmSheet(isDark: isDark);
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await BillingService().cancelSubscription();
      if (!mounted) return;
      // Refresh subscription state
      await ref.read(subscriptionProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription cancelled.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: Colors.red.shade400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.red.shade200),
          ),
        ),
        icon: _cancelling
            ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.red,
          ),
        )
            : const Icon(Icons.cancel_outlined, size: 18),
        label: const Text(
          'Cancel Subscription',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        onPressed: _cancelling ? null : _onCancel,
      ),
    );
  }
}

// ─── PLANS UNAVAILABLE (API failed or no enabled products) ───────────────────

class _PlansUnavailable extends StatelessWidget {
  const _PlansUnavailable({
    required this.theme,
    required this.isDark,
    required this.onRetry,
  });
  final Color theme;
  final bool isDark;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: theme),
            const SizedBox(height: 14),
            Text(
              'Plans could not be loaded',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, color: theme),
              label: Text('Retry', style: TextStyle(color: theme)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: theme, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
