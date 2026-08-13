import 'package:flutter/material.dart';

/// Global navigator key so services (e.g. NotificationService) can push routes
/// without a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
