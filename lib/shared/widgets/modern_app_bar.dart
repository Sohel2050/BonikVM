import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';

class ModernAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final double elevation;
  final bool transparent;

  const ModernAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
    this.showBackButton = true,
    this.onBackPressed,
    this.elevation = 0,
    this.transparent = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);
    final isDarkMode =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return AppBar(
      backgroundColor: transparent
          ? Colors.transparent
          : isDarkMode
          ? const Color(0xFF0F172A).withOpacity(0.9)
          : Colors.white.withOpacity(0.9),
      foregroundColor: isDarkMode ? Colors.white : Colors.black87,
      elevation: elevation,
      shadowColor: isDarkMode
          ? Colors.black.withOpacity(0.2)
          : Colors.grey.withOpacity(0.1),
      centerTitle: centerTitle,
      leading: leading ??
          (showBackButton && Navigator.of(context).canPop()
              ? Container(
                  margin: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.05)
                          : Colors.black.withOpacity(0.02),
                    ),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: isDarkMode ? Colors.white : Colors.black87,
                      size: 16,
                    ),
                    onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
                  ),
                )
              : null),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isDarkMode ? Colors.white : Colors.black87,
          letterSpacing: 0.5,
        ),
      ),
      actions: actions?.map((action) {
        if (action is IconButton) {
          return Container(
            margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.02),
              ),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: action.icon,
              onPressed: action.onPressed,
              iconSize: action.iconSize ?? 20,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          );
        }
        return action;
      }).toList(),
      flexibleSpace: !transparent
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDarkMode
                      ? [
                          const Color(0xFF0F172A).withOpacity(0.98),
                          const Color(0xFF1E293B).withOpacity(0.92),
                        ]
                      : [
                          Colors.white.withOpacity(0.98),
                          themeColor.withOpacity(0.02),
                        ],
                ),
              ),
            )
          : null,
      systemOverlayStyle: isDarkMode
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 2);
}

// Custom AppBar for main navigation screens (Home, Servers, Settings, etc.)
class MainAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showLogo;

  const MainAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.showLogo = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);
    final isDarkMode =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return AppBar(
      backgroundColor: isDarkMode
          ? const Color(0xFF0F172A).withOpacity(0.9)
          : Colors.white.withOpacity(0.9),
      foregroundColor: isDarkMode ? Colors.white : Colors.black87,
      elevation: 0,
      shadowColor: Colors.transparent,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: leading != null
          ? Container(
              margin: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.02),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: leading,
              ),
            )
          : null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLogo) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.shield,
                  size: 32,
                  color: themeColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      actions: actions?.map((action) {
        if (action is IconButton) {
          return Container(
            margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.02),
              ),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: action.icon,
              onPressed: action.onPressed,
              iconSize: action.iconSize ?? 20,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          );
        }
        return action;
      }).toList(),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDarkMode
                ? [
                    const Color(0xFF0F172A).withOpacity(0.98),
                    const Color(0xFF1E293B).withOpacity(0.92),
                  ]
                : [
                    Colors.white.withOpacity(0.98),
                    themeColor.withOpacity(0.02),
                  ],
          ),
          border: Border(
            bottom: BorderSide(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.05),
              width: 0.5,
            ),
          ),
        ),
      ),
      systemOverlayStyle: isDarkMode
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 2);
}
