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

  List<Map<String, dynamic>> _parseCatalog(SubscriptionState sub) {
    if (sub.planCatalog.isNotEmpty) return sub.planCatalog;
    return [
      {
        'product_id': '1m',
        'display_name': '1 Month',
        'web_price': '4.99',
        'is_popular': false,
        'is_lifetime': false,
        'duration_days': 30,
      },
      {
        'product_id': '3m',
        'display_name': '3 Months',
        'web_price': '11.99',
        'is_popular': true,
        'is_lifetime': false,
        'duration_days': 90,
      },
      {
        'product_id': '1y',
        'display_name': '1 Year',
        'web_price': '29.99',
        'is_popular': false,
        'is_lifetime': false,
        'duration_days': 365,
      },
    ];
  }

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
                          icon: Icons.workspace_premium,
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
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _Pill(
                                label: source,
                                bg: Colors.white.withValues(alpha: 0.2),
                                textColor: Colors.white,
                              ),
                            ],
                          ),
                        ),
                        _Pill(
                          label: '✓  ACTIVE',
                          bg: Colors.white.withValues(alpha: 0.2),
                          textColor: Colors.white,
                          fontSize: 12,
                        ),
                      ],
                    ),
                    // Expiry / lifetime info
                    if (isLife) ...[
                      const SizedBox(height: 18),
                      const Divider(color: Colors.white24),
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
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ] else if (expiresAt != null) ...[
                      const SizedBox(height: 18),
                      const Divider(color: Colors.white24),
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
                                        : Colors.white),
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
                              Colors.white,
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
                                    ? Colors.white
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
    final ref = (context as Element)
        .findAncestorStateOfType<ConsumerState>()
        ?.ref;

    return SafeArea(
      top: false,
      child: Column(
        children: [
          // ── Clean header ──────────────────────────────────────
          FadeInDown(
            child: Container(
              width: double.infinity,
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: theme,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context).unlockPremium,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context).accessAllServersFeatures,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Scrollable body ───────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).chooseYourPlan,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Vertical plan list ────────────────────────
                  ...catalog.asMap().entries.map(
                    (entry) => FadeInUp(
                      delay: Duration(milliseconds: 55 * entry.key),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PlanCard(
                          plan: entry.value,
                          isSelected: selectedId == entry.value['product_id'],
                          theme: theme,
                          isDark: isDark,
                          onTap: () =>
                              onSelect(entry.value['product_id'] as String?),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ── Feature checkmarks ────────────────────────
                  ..._kFeatures(context).map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: theme,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            f.$2,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ── Subscribe CTA ─────────────────────────────
                  FadeInUp(
                    delay: const Duration(milliseconds: 200),
                    child: SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 6,
                          shadowColor: theme.withValues(alpha: 0.45),
                        ),
                        icon: const Icon(
                          Icons.lock_open_rounded,
                          color: Colors.white,
                        ),
                        label: Text(
                          AppLocalizations.of(context).continueToCheckout,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        onPressed: selectedId == null
                            ? null
                            : () {
                                final planData = catalog.firstWhere(
                                  (p) => p['product_id'] == selectedId,
                                  orElse: () => <String, dynamic>{},
                                );
                                final widgetRef = context
                                    .findAncestorStateOfType<ConsumerState>()
                                    ?.ref;
                                if (widgetRef != null) {
                                  showPaymentMethodSheet(
                                    context,
                                    widgetRef,
                                    selectedId!,
                                    planData,
                                  );
                                }
                              },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  _SubscriptionLegalLinks(
                    isDark: isDark,
                    themeColor: theme,
                    onOpenTerms: () => Navigator.pushNamed(context, '/terms'),
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

                  const SizedBox(height: 10),

                  // ── Secondary links ───────────────────────────
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
                          AppLocalizations.of(context).myReceipts,
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
                          AppLocalizations.of(context).redeemVoucher,
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
        color: isDark ? const Color(0xFF161B22) : Colors.white,
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
              color: isDark ? Colors.white : const Color(0xFF111827),
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
  });
  final Map<String, dynamic> plan;
  final bool isSelected;
  final Color theme;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        plan['display_name'] as String? ?? plan['product_id'] as String;
    final price = plan['web_price']?.toString() ?? '–';
    final isPopular = plan['is_popular'] == true;
    final isLife =
        plan['is_lifetime'] == true ||
        plan['product_id'] == 'lt' ||
        plan['product_id'] == 'lifetime';
    final hasBadge = isPopular || isLife;
    final badgeLabel = isPopular
        ? AppLocalizations.of(context).popular
        : AppLocalizations.of(context).oneTime;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.withOpacity(0.08)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          border: Border.all(
            color: isSelected
                ? theme
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB)),
            width: isSelected ? 2.0 : 1.0,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? theme.withOpacity(0.12)
                  : Colors.black.withOpacity(isDark ? 0.15 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            // Selection circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? theme : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? theme
                      : (isDark ? const Color(0xFF475569) : const Color(0xFFD1D5DB)),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 14),
            // Plan info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF111827),
                        ),
                      ),
                      if (hasBadge) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: isPopular
                                ? LinearGradient(colors: [theme, theme.withOpacity(0.8)])
                                : const LinearGradient(colors: [Color(0xFFD97706), Color(0xFFF59E0B)]),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: (isPopular ? theme : const Color(0xFFD97706)).withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPopular ? Icons.local_fire_department_rounded : Icons.star_rounded,
                                size: 10,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                badgeLabel.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLife
                        ? AppLocalizations.of(context).oneTimePayment
                        : _durLabel(plan),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            // Price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$$price',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isSelected
                        ? theme
                        : (isDark ? Colors.white : const Color(0xFF111827)),
                  ),
                ),
                if (!isLife) ...[
                  const SizedBox(height: 2),
                  Text(
                    'per period',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF9CA3AF),
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

  static String _durLabel(Map<String, dynamic> p) {
    final d = p['duration_days'];
    if (d == null) return 'lifetime';
    final days = (d is int) ? d : int.tryParse(d.toString()) ?? 0;
    if (days <= 31) return '30 days';
    if (days <= 92) return '90 days';
    if (days >= 365) return '1 year';
    return '$days days';
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
    child: Icon(icon, color: Colors.white, size: size),
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
    color: isDark ? const Color(0xFF161B22) : Colors.white,
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
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
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
        color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
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
                  color: Colors.white,
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
        color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
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
              color: isDark ? Colors.white : Colors.black87,
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
                  color: Colors.white,
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
