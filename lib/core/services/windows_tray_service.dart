import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

/// Makes the Windows build behave like the mobile app: a fixed,
/// phone-proportioned window instead of a freely-resizable desktop window,
/// and a system tray icon so closing the window minimizes to the tray
/// (like Android's notification-area behavior) instead of quitting or
/// leaving a separate taskbar entry.
class WindowsTrayService with WindowListener, TrayListener {
  WindowsTrayService._internal();
  static final WindowsTrayService instance = WindowsTrayService._internal();

  /// Phone-like portrait window size — same aspect ratio ballpark as a
  /// typical phone screen, so the mobile-first UI doesn't have to stretch
  /// across a full desktop window.
  static const _windowSize = Size(420, 840);

  Future<void> initialize() async {
    if (!Platform.isWindows) return;

    await windowManager.ensureInitialized();

    const options = WindowOptions(
      size: _windowSize,
      minimumSize: _windowSize,
      maximumSize: _windowSize,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'VPN MASTER',
    );

    windowManager.addListener(this);
    // Intercept the close ("X") button — handled in onWindowClose below —
    // instead of letting it quit the process.
    await windowManager.setPreventClose(true);

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await _initTray();
  }

  Future<void> _initTray() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/images/tray_icon.ico');
    await trayManager.setToolTip('VPN MASTER');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: 'Open VPN MASTER'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: 'Quit'),
        ],
      ),
    );
  }

  // ── WindowListener ──────────────────────────────────────────────────
  @override
  void onWindowClose() async {
    // The X button minimizes to the tray rather than quitting — mirrors
    // how the mobile app backgrounds instead of exiting. The VPN
    // connection (if any) keeps running, same as backgrounding on mobile.
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  // ── TrayListener ────────────────────────────────────────────────────
  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        _showWindow();
        break;
      case 'exit_app':
        _quit();
        break;
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}
