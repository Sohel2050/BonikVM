import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A random id created once per app install and sent to the server as
/// `device_id` in EVERY request that identifies the device (VPN config
/// download, peer request, connect/disconnect logs, push token registration).
///
/// Do NOT use Android `Build.ID` (`androidInfo.id`) for this: it is identical
/// on every phone with the same firmware, so different phones end up sharing
/// one VPN key, one push token and one session on the server.
class DeviceIdentity {
  static const _key = 'device_uuid_v1';
  static String? _cached;

  /// 32 lowercase hex chars (a UUID v4 without dashes). The server accepts
  /// 32-64 chars of [A-Za-z0-9_-] and ignores anything else.
  static Future<String> id() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.length < 32) {
      id = const Uuid().v4().replaceAll('-', '');
      await prefs.setString(_key, id);
    }
    return _cached = id;
  }
}
