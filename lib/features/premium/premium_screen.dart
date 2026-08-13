import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/providers/theme_provider.dart';
import '../../core/services/purchase_service.dart';
import '../../core/api/api_service.dart';
import '../../screens/auth/sign_in_screen.dart';
import '../../screens/payment/payment_options_screen.dart';
import '../../services/auth_service.dart';
import '../../core/localization/app_localizations.dart';
import 'dart:async';

final GlobalKey<_PremiumScreenState> premiumScreenKey =
GlobalKey<_PremiumScreenState>();

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key, this.autoRefresh = false});

  final bool autoRefresh;

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;

  // Purchase service
  final PurchaseService _purchaseService = PurchaseService();
  final ApiService _apiService = ApiService();
  StreamSubscription<PurchaseResult>? _purchaseResultSubscription;
  bool _isLoading = false;

  // Dynamic pricing plans
  List<PurchasePlan> _apiPlans = [];
  bool _plansLoaded = false;
  bool _purchaseSuccessful = false;

  List<PremiumFeature> _getPremiumFeatures(Color themeColor, bool isDarkMode) {
    return [
      PremiumFeature(
        icon: Icons.flash_on,
        title: 'Ultra-Fast Servers',
        description: 'Get Access to premium high-speed servers',
        gradient: LinearGradient(
          colors: [
            isDarkMode ? themeColor : themeColor.withValues(alpha: 0.8),
            isDarkMode
                ? themeColor.withValues(alpha: 0.7)
                : themeColor.withValues(alpha: 0.6),
          ],
        ),
      ),

      PremiumFeature(
        icon: Icons.block,
        title: 'Ad-Free Experience',
        description: 'No ads, no Disturb, pure VPN experience',
        gradient: LinearGradient(
          colors: [
            isDarkMode ? Colors.green : Colors.green.withValues(alpha: 0.8),
            isDarkMode
                ? Colors.green.withValues(alpha: 0.7)
                : Colors.green.withValues(alpha: 0.6),
          ],
        ),
      ),



    ];
  }

  // Convert API plans to SubscriptionPlan objects
  List<SubscriptionPlan> _getDisplayPlans() {
    if (_plansLoaded && _apiPlans.isNotEmpty) {
      return _apiPlans.map((apiPlan) {
        // Get real price from store if available
        final realPrice = _purchaseService.getRealPrice(apiPlan.id);

        return SubscriptionPlan(
          id: apiPlan.id,
          name: apiPlan.name,
          price:
          realPrice ??
              apiPlan.formattedPrice, // Use real price if available
          period: '/${apiPlan.period}',
          originalPrice: apiPlan.formattedOriginalPrice,
          discount: apiPlan.discount,
          features: apiPlan.features,
          isPopular: apiPlan.isPopular,
        );
      }).toList();
    }

    // Return empty list if no plans available from API
    // Don't use fallback plans anymore
    return [];
  }

  // ⚠️ Selected plan is now set dynamically from API response
  // First enabled plan from /api/v1/purchase/plans is selected by default
  String _selectedPlan = ''; // Will be set from API data

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
          ),
        );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _animationController.forward();
    _pulseAnimationController.repeat(reverse: true);

    // Initialize purchase service
    _initializePurchaseService();

    // Load pricing plans from API
    _loadPricingPlans();
  }

  /// Public method for main shell to trigger a product refresh
  Future<void> refreshProducts() async {
    await _loadPricingPlans();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _apiPlans.isNotEmpty
              ? 'Products refreshed successfully!'
              : 'No products available',
        ),
        backgroundColor: _apiPlans.isNotEmpty ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loadPricingPlans() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
      });

      print('[Premium] Loading pricing plans from API...');
      final plans = await _apiService.getPurchasePlans();
      print('[Premium] API response: plans = ${plans?.length ?? 0} items');

      if (!mounted) return;

      if (plans != null && plans.isNotEmpty) {
        print('[Premium] Plans loaded successfully: ${plans.length} plans');
        setState(() {
          _apiPlans = plans;
          _plansLoaded = true;
          _isLoading = false;

          // Set default selected plan to the popular one, or first one if none marked as popular
          final popularPlan = plans.firstWhere(
                (plan) => plan.isPopular,
            orElse: () => plans.first,
          );
          _selectedPlan = popularPlan.id;
        });
      } else {
        print('[Premium] No plans received from API');
        setState(() {
          _plansLoaded = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[Premium] Error loading pricing plans: $e');
      if (!mounted) return;
      setState(() {
        _plansLoaded = false;
        _isLoading = false;
      });
    }
  }

  void _initializePurchaseService() async {
    await _purchaseService.initialize();

    // Track if we've shown a success dialog to prevent duplicates
    bool hasShownSuccessDialog = false;

    _purchaseResultSubscription = _purchaseService.purchaseResultStream.listen((
        result,
        ) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result.isSuccess && !hasShownSuccessDialog) {
          hasShownSuccessDialog = true;

          // Mark purchase as successful for handling in build method
          setState(() {
            _purchaseSuccessful = true;
          });

          // Verify subscription with backend
          _verifyPurchaseWithBackend(result.productId!);

          // Show success dialog
          _showSuccessDialog();
        } else if (result.isError) {
          // Show error dialog
          _showErrorDialog(result.errorMessage ?? 'Purchase failed');
        }
      }
    });
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: true, // Allow tap outside to close
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF1E293B),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium,
                size: 40,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Welcome to Premium!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'You now have access to all premium features. Enjoy unlimited VPN access!',
              style: TextStyle(fontSize: 16, color: Color(0xFF94A3B8)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              // Close dialog and navigate back to home
              Navigator.of(context).popUntil(ModalRoute.withName('/home'));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Start Using Premium'),
          ),
        ],
      ),
    );
  }

  /// Verify purchase with backend server
  Future<void> _verifyPurchaseWithBackend(String productId) async {
    try {
      // Get current user info from authentication
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      // CRITICAL FIX: Don't verify with fake data!
      // Only proceed if we have actual purchase data// TODO: Implement proper verification only when we have real Google Play receipt data
      // For now, we skip verification to prevent auto-reactivation of cancelled subscriptions

      return;

      // DISABLED CODE - The below code was causing auto-reactivation with fake data
      /*
      final result = await _apiService.verifyPurchase(
        userId: user.uid,
        receiptData: 'google_play_receipt_$productId', // This was fake data
        productId: productId,
        platform: Platform.isAndroid ? 'android' : 'ios',
        transactionId: 'real_transaction_${DateTime.now().millisecondsSinceEpoch}', // This was fake
        firebaseUid: user.uid,
        userEmail: user.email,
      );

      if (result != null && result['success'] == true) {

        await _purchaseService.activateSubscriptionBenefits();
      } else {

      }
      */
    } catch (e) {}
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Purchase Failed',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(error, style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _purchasePlan() async {
    if (_isLoading) return;

    // Check if user is authenticated
    if (AuthService.requiresAuthForPurchase()) {
      // Navigate to login screen
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (context) => const SignInScreen()));

      // Check if user is now authenticated
      if (!AuthService.isLoggedIn) {
        return; // User didn't complete authentication
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication successful!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }

    // Get selected plan details
    final selectedPlan = _getDisplayPlans().firstWhere(
          (plan) => plan.id == _selectedPlan,
    );

    // Navigate to payment options screen
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentOptionsScreen(
            planId: selectedPlan.id,
            planName: selectedPlan.name,
            planPrice: selectedPlan.price,
            planDetails: {
              'price':
              double.tryParse(
                selectedPlan.price.replaceAll(RegExp(r'[^\d.]'), ''),
              ) ??
                  0.0,
              'period': selectedPlan.period,
              'features': selectedPlan.features,
              'is_popular': selectedPlan.isPopular,
            },
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseAnimationController.dispose();
    _purchaseResultSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(premiumStatusProvider);
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);
    final isDarkMode =
        themeMode == ThemeMode.dark ||
            (themeMode == ThemeMode.system &&
                MediaQuery.of(context).platformBrightness == Brightness.dark);

    // Handle purchase success in build method (safe for ref operations)
    if (_purchaseSuccessful) {
      _purchaseSuccessful = false; // Reset flag
      ref.read(premiumStatusProvider.notifier).setPremiumStatus(true);
    }

    // Check if we should show purchase options
    final shouldShowPurchaseOptions =
        !isPremium && (_plansLoaded && _apiPlans.isNotEmpty);

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : Colors.grey[50],
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Hero Section
                    _buildHeroSection(isPremium, isDarkMode, themeColor),

                    // Features Section
                    if (!isPremium) ...[
                      _buildFeaturesSection(isDarkMode, themeColor),

                      // Check if products are available from admin panel
                      if (shouldShowPurchaseOptions) ...[
                        // Subscription Plans
                        _buildSubscriptionPlans(isDarkMode, themeColor),

                        // Purchase Button
                        _buildPurchaseButton(isDarkMode, themeColor),

                        // Terms & Privacy
                        _buildTermsSection(isDarkMode),
                      ] else if (!_isLoading) ...[
                        // Show message when no products are available
                        _buildNoProductsMessage(isDarkMode),
                      ] else ...[
                        // Show loading indicator
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      ],
                    ],

                    // Bottom spacing
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroSection(bool isPremium, bool isDarkMode, Color themeColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (isPremium) ...[
            // Premium Badge with pulse animation
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.workspace_premium,
                          color: Colors.black,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'PREMIUM ACTIVE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: Text(
                '🎉 You\'re enjoying the full\nVPN MASTER experience!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeInUp(
              delay: const Duration(milliseconds: 400),
              child: Text(
                'Thank you for supporting VPN MASTER! Enjoy unlimited access to all premium features.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : Colors.grey[600],
                  height: 1.5,
                ),
              ),
            ),
          ] else ...[
            // Crown Icon with animation
            FadeInDown(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            themeColor,
                            themeColor.withValues(alpha: 0.8),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: themeColor.withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.workspace_premium,
                        size: 50,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
            FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: Text(
                'Unlock Premium\nFeatures',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeInUp(
              delay: const Duration(milliseconds: 400),
              child: Text(
                'Get unlimited access to premium servers,\nad-free experience, and priority support',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : Colors.grey[600],
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeaturesSection(bool isDarkMode, Color themeColor) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeInLeft(
            child: Text(
              'Premium Features',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio:
              0.95, // Reduced aspect ratio to allow more vertical space
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _getPremiumFeatures(themeColor, isDarkMode).length,
            itemBuilder: (context, index) => _buildFeatureCard(
              _getPremiumFeatures(themeColor, isDarkMode)[index],
              index,
              isDarkMode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(PremiumFeature feature, int index, bool isDarkMode) {
    return FadeInUp(
      delay: Duration(milliseconds: 100 * index),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 24,
          horizontal: 16,
        ), // Increased vertical padding
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDarkMode
                  ? Colors.black.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: feature.gradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: feature.gradient.colors.first.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(feature.icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              feature.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                feature.description,
                style: TextStyle(
                  fontSize: 11,
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : Colors.grey[600],
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionPlans(bool isDarkMode, Color themeColor) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeInLeft(
            child: Text(
              'Choose Your Plan',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FadeInLeft(
            delay: const Duration(milliseconds: 200),
            child: Text(
              'Select the plan that works best for you',
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode ? const Color(0xFF94A3B8) : Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(
            _getDisplayPlans().length,
                (index) => _buildPlanCard(
              _getDisplayPlans()[index],
              index,
              isDarkMode,
              themeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(
      SubscriptionPlan plan,
      int index,
      bool isDarkMode,
      Color themeColor,
      ) {
    final isSelected = _selectedPlan == plan.id;

    return FadeInUp(
      delay: Duration(milliseconds: 100 * index),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedPlan = plan.id;
          });
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDarkMode
                ? themeColor.withValues(alpha: 0.1)
                : themeColor.withValues(alpha: 0.05))
                : (isDarkMode ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? themeColor
                  : (isDarkMode
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.2)),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? themeColor.withValues(alpha: 0.2)
                    : (isDarkMode
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.1)),
                blurRadius: isSelected ? 15 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Popular Badge
              if (plan.isPopular)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'POPULAR',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),

              // Plan Content
              Row(
                children: [
                  // Radio Button
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? themeColor
                            : (isDarkMode
                            ? const Color(0xFF6B7280)
                            : Colors.grey),
                        width: 2,
                      ),
                      color: isSelected ? themeColor : Colors.transparent,
                    ),
                    child: isSelected
                        ? const Center(
                      child: Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      ),
                    )
                        : null,
                  ),

                  const SizedBox(width: 16),

                  // Plan Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              plan.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                            if (plan.discount != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  plan.discount!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              plan.price,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: themeColor,
                              ),
                            ),
                            Text(
                              plan.period,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode
                                    ? const Color(0xFF94A3B8)
                                    : Colors.grey[600],
                              ),
                            ),
                            if (plan.originalPrice != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                plan.originalPrice!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode
                                      ? const Color(0xFF94A3B8)
                                      : Colors.grey[600],
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...plan.features.map(
                              (feature) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: themeColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    feature,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDarkMode
                                          ? const Color(0xFF94A3B8)
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPurchaseButton(bool isDarkMode, Color themeColor) {
    final selectedPlan = _getDisplayPlans().firstWhere(
          (plan) => plan.id == _selectedPlan,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: FadeInUp(
        delay: const Duration(milliseconds: 500),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _purchasePlan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  shadowColor: themeColor.withValues(alpha: 0.3),
                ),
                child: _isLoading
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                )
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.workspace_premium, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'Start Premium ${selectedPlan.price}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Cancel anytime • 30-day money-back guarantee',
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? const Color(0xFF94A3B8) : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsSection(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FadeInUp(
        delay: const Duration(milliseconds: 600),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text(
              'By purchasing you agree to our Terms of Service and Privacy Policy. Subscription automatically renews unless auto-renew is turned off at least 24-hours before the end of the current period.',
              style: TextStyle(
                fontSize: 11,
                color: isDarkMode ? const Color(0xFF6B7280) : Colors.grey[500],
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    // Open terms of service
                  },
                  child: Text(
                    'Terms of Service',
                    style: TextStyle(
                      fontSize: 12,
                      color: ref.watch(themeColorProvider),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                Text(
                  ' • ',
                  style: TextStyle(
                    color: isDarkMode
                        ? const Color(0xFF6B7280)
                        : Colors.grey[500],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Open privacy policy
                  },
                  child: Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 12,
                      color: ref.watch(themeColorProvider),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoProductsMessage(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: FadeInUp(
        delay: const Duration(milliseconds: 300),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.info_outline, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  Text(
                    'Premium Not Available',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Premium subscriptions are currently not available. Please contact support for more information.',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode
                          ? const Color(0xFF94A3B8)
                          : Colors.grey[600],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
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

// Data classes
class PremiumFeature {
  final IconData icon;
  final String title;
  final String description;
  final LinearGradient gradient;

  PremiumFeature({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
  });
}

class SubscriptionPlan {
  final String id;
  final String name;
  final String price;
  final String period;
  final String? originalPrice;
  final String? discount;
  final List<String> features;
  final bool isPopular;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.period,
    this.originalPrice,
    this.discount,
    required this.features,
    required this.isPopular,
  });
}
