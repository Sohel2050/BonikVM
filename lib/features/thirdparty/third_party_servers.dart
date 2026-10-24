import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_service.dart' show VpnServer;

/// Free connection time (minutes) on third-party servers.
/// 0 = unlimited (no countdown timer). Set e.g. 60 to limit it to one hour.
const int kThirdPartyFreeMinutes = 0;

const int _maxCandidates = 80;
const int _maxShown = 40;
const int _probeConcurrency = 16;
const Duration _failedTtl = Duration(hours: 24);
const Duration _refreshAfter = Duration(minutes: 10);

const String _listUrl = 'https://www.vpngate.net/api/iphone';

/// Countries whose servers are never shown. Check with your own legal
/// adviser which countries you must block.
const Set<String> _blockedCodes = {'RU', 'AE'};
const Set<String> _blockedNames = {
  'russian federation',
  'russia',
  'united arab emirates',
};

/// Remembers servers that failed to connect, so they stay hidden for 24 hours.
class ThirdPartyFailed {
  ThirdPartyFailed._();

  static const String _key = 'third_party_failed_v1';

  /// Increases whenever a server is marked as failed.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<Map<String, int>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final now = DateTime.now().millisecondsSinceEpoch;
      final out = <String, int>{};
      decoded.forEach((k, v) {
        final t = v is int ? v : int.tryParse('$v');
        if (t != null && now - t < _failedTtl.inMilliseconds) {
          out['$k'] = t;
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<Set<String>> activeIps() async => (await _read()).keys.toSet();

  static Future<void> mark(String? ip) async {
    if (ip == null || ip.isEmpty) return;
    try {
      final map = await _read();
      map[ip] = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(map));
      changes.value++;
    } catch (_) {}
  }
}

class _Row {
  final String hostname;
  final String ip;
  final String countryLong;
  final String countryShort;
  final String operatorName;
  final String configB64;
  final int ping;
  final int speed;
  final int sessions;

  const _Row({
    required this.hostname,
    required this.ip,
    required this.countryLong,
    required this.countryShort,
    required this.operatorName,
    required this.configB64,
    required this.ping,
    required this.speed,
    required this.sessions,
  });
}

class _Target {
  final String host;
  final int port;
  final bool tcp;
  const _Target(this.host, this.port, this.tcp);
}

List<String> _splitCsvLine(String line) {
  final out = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        sb.write(ch);
      }
    } else {
      if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        out.add(sb.toString());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
  }
  out.add(sb.toString());
  return out;
}

List<_Row> _parseRows(String raw) {
  final lines = raw
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trim().isNotEmpty && !l.startsWith('*'))
      .map((l) => l.startsWith('#') ? l.substring(1) : l)
      .toList();
  if (lines.length < 2) return [];

  final headers = _splitCsvLine(lines.first).map((e) => e.trim()).toList();
  int idx(String name) => headers.indexOf(name);
  final iHost = idx('HostName');
  final iIp = idx('IP');
  final iPing = idx('Ping');
  final iSpeed = idx('Speed');
  final iCl = idx('CountryLong');
  final iCs = idx('CountryShort');
  final iSess = idx('NumVpnSessions');
  final iOp = idx('Operator');
  final iCfg = idx('OpenVPN_ConfigData_Base64');
  if (iIp < 0 || iCfg < 0) return [];

  final rows = <_Row>[];
  for (final line in lines.skip(1)) {
    final f = _splitCsvLine(line);
    if (f.length != headers.length) continue;
    String at(int i) => (i >= 0 && i < f.length) ? f[i].trim() : '';
    rows.add(
      _Row(
        hostname: at(iHost),
        ip: at(iIp),
        countryLong: at(iCl),
        countryShort: at(iCs).toUpperCase(),
        operatorName: at(iOp),
        configB64: at(iCfg),
        ping: int.tryParse(at(iPing)) ?? 0,
        speed: int.tryParse(at(iSpeed)) ?? 0,
        sessions: int.tryParse(at(iSess)) ?? 0,
      ),
    );
  }
  return rows;
}

bool _isBlocked(_Row r) {
  final code = r.countryShort.toUpperCase();
  final name = r.countryLong.toLowerCase();
  return _blockedCodes.contains(code) || _blockedNames.contains(name);
}

/// Decodes the Base64 .ovpn text. Old servers use AES-CBC, which new OpenVPN
/// versions refuse without a data-ciphers line, so that line is added.
String? _decodeConfig(String b64) {
  try {
    var config = utf8.decode(
      base64.decode(base64.normalize(b64)),
      allowMalformed: true,
    );
    for (final cipher in ['AES-128-CBC', 'AES-256-CBC']) {
      if (config.contains('cipher $cipher') &&
          !config.contains('data-ciphers')) {
        config = config.replaceAll(
          'cipher $cipher',
          "cipher $cipher\ndata-ciphers '$cipher'\ndata-ciphers-fallback '$cipher'",
        );
      }
    }
    return config;
  } catch (_) {
    return null;
  }
}

_Target? _target(String config) {
  String? host;
  int? port;
  var tcp = false;
  for (final raw in config.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.startsWith('proto ')) {
      tcp = line.contains('tcp');
    } else if (host == null && line.startsWith('remote ')) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        host = parts[1];
        port = int.tryParse(parts[2]);
      }
    }
  }
  if (host == null || port == null) return null;
  return _Target(host, port, tcp);
}

Future<bool> _probe(_Target t) => t.tcp ? _probeTcp(t) : _probeUdp(t);

Future<bool> _probeTcp(_Target t) async {
  try {
    final socket = await Socket.connect(
      t.host,
      t.port,
      timeout: const Duration(seconds: 3),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Sends an OpenVPN hard-reset packet and waits for any answer.
Future<bool> _probeUdp(_Target t) async {
  RawDatagramSocket? socket;
  Timer? resend;
  StreamSubscription<RawSocketEvent>? sub;
  try {
    final address =
        (await InternetAddress.lookup(t.host, type: InternetAddressType.IPv4))
            .first;
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final answered = Completer<bool>();
    sub = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket?.receive();
        if (datagram != null &&
            datagram.data.isNotEmpty &&
            !answered.isCompleted) {
          answered.complete(true);
        }
      }
    });

    final random = Random.secure();
    final packet = Uint8List(14);
    packet[0] = 0x38;
    for (var i = 1; i <= 8; i++) {
      packet[i] = random.nextInt(256);
    }
    socket.send(packet, address, t.port);
    resend = Timer(
      const Duration(milliseconds: 1500),
      () => socket?.send(packet, address, t.port),
    );

    return await answered.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => false,
    );
  } catch (_) {
    return false;
  } finally {
    resend?.cancel();
    await sub?.cancel();
    socket?.close();
  }
}

String _flagEmoji(String code) {
  final c = code.toUpperCase();
  if (c.length != 2) return '';
  final a = c.codeUnitAt(0);
  final b = c.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '';
  return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
}

VpnServer _toVpnServer(_Row r, String config, _Target t, int order) {
  return VpnServer(
    id: 'vg_${r.ip}',
    name: r.hostname.isNotEmpty ? r.hostname : r.ip,
    ip: r.ip,
    country: r.countryLong,
    countryCode: r.countryShort,
    flag: _flagEmoji(r.countryShort),
    premium: false,
    latency: r.ping,
    configUrl: '',
    protocol: t.tcp ? 'TCP' : 'UDP',
    tcpPort: t.tcp ? '${t.port}' : '',
    udpPort: t.tcp ? '' : '${t.port}',
    port: t.port,
    vpnUsername: 'vpn',
    vpnPassword: 'vpn',
    useFile: false,
    freeConnectDuration: kThirdPartyFreeMinutes,
    connectedDevices: r.sessions,
    order: order,
    capacity: 100000,
    protocols: const ['openvpn'],
    vpnProtocolType: 'openvpn',
    provider: 'vpngate',
    providerServerId: r.ip,
    providerPayload: {
      'ovpnConfiguration': config,
      'speedBps': r.speed,
      'operator': r.operatorName,
      'sessions': r.sessions,
    },
  );
}

class ThirdPartyState {
  final bool loading;
  final bool probing;
  final String? error;
  final List<VpnServer> servers;
  final DateTime? loadedAt;

  const ThirdPartyState({
    this.loading = false,
    this.probing = false,
    this.error,
    this.servers = const [],
    this.loadedAt,
  });

  ThirdPartyState copyWith({
    bool? loading,
    bool? probing,
    String? error,
    bool clearError = false,
    List<VpnServer>? servers,
    DateTime? loadedAt,
  }) {
    return ThirdPartyState(
      loading: loading ?? this.loading,
      probing: probing ?? this.probing,
      error: clearError ? null : (error ?? this.error),
      servers: servers ?? this.servers,
      loadedAt: loadedAt ?? this.loadedAt,
    );
  }
}

class ThirdPartyNotifier extends StateNotifier<ThirdPartyState> {
  ThirdPartyNotifier() : super(const ThirdPartyState()) {
    ThirdPartyFailed.changes.addListener(_onFailedChanged);
  }

  int _generation = 0;

  @override
  void dispose() {
    ThirdPartyFailed.changes.removeListener(_onFailedChanged);
    super.dispose();
  }

  Future<void> _onFailedChanged() async {
    final failed = await ThirdPartyFailed.activeIps();
    if (!mounted) return;
    state = state.copyWith(
      servers: state.servers
          .where((s) => !failed.contains(s.providerServerId))
          .toList(),
    );
  }

  Future<String> _download() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
      ),
    );
    final response = await dio.get<String>(
      _listUrl,
      options: Options(
        headers: {'User-Agent': 'Mozilla/5.0', 'Accept': 'text/plain'},
      ),
    );
    final text = response.data ?? '';
    if (!text.contains('HostName')) {
      throw Exception('The server list was empty');
    }
    return text;
  }

  Future<void> load({bool force = false}) async {
    if (state.loading || state.probing) return;
    final at = state.loadedAt;
    if (!force &&
        at != null &&
        state.servers.isNotEmpty &&
        DateTime.now().difference(at) < _refreshAfter) {
      return;
    }

    final gen = ++_generation;
    state = state.copyWith(
      loading: true,
      probing: false,
      clearError: true,
      servers: const [],
    );

    try {
      final raw = await _download();
      final rows = _parseRows(raw);
      final failed = await ThirdPartyFailed.activeIps();

      final candidates = rows
          .where((r) => r.configB64.isNotEmpty && r.ip.isNotEmpty)
          .where((r) => !_isBlocked(r))
          .where((r) => !failed.contains(r.ip))
          .toList();

      candidates.sort((a, b) {
        final speed = b.speed.compareTo(a.speed);
        if (speed != 0) return speed;
        final ping = a.ping.compareTo(b.ping);
        if (ping != 0) return ping;
        return a.sessions.compareTo(b.sessions);
      });

      final top = candidates.take(_maxCandidates).toList();
      if (!mounted || gen != _generation) return;
      if (top.isEmpty) {
        state = state.copyWith(
          loading: false,
          probing: false,
          error: 'No servers are available right now.',
        );
        return;
      }

      state = state.copyWith(loading: false, probing: true);
      await _probeAll(top, gen);
      if (!mounted || gen != _generation) return;

      state = state.copyWith(
        probing: false,
        loadedAt: DateTime.now(),
        error: state.servers.isEmpty
            ? 'No working servers found. Pull down to try again.'
            : null,
        clearError: state.servers.isNotEmpty,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ThirdParty] load failed: $e');
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
        loading: false,
        probing: false,
        error: 'Could not load the server list. Check your connection and try again.',
      );
    }
  }

  Future<void> _probeAll(List<_Row> rows, int gen) async {
    var next = 0;
    final alive = <int, VpnServer>{};

    Future<void> worker() async {
      while (true) {
        if (!mounted || gen != _generation) return;
        if (alive.length >= _maxShown) return;
        final i = next++;
        if (i >= rows.length) return;

        final row = rows[i];
        final config = _decodeConfig(row.configB64);
        if (config == null) continue;
        final target = _target(config);
        if (target == null) continue;

        final ok = await _probe(target);
        if (!ok) continue;
        if (!mounted || gen != _generation) return;
        if (alive.length >= _maxShown) return;

        alive[i] = _toVpnServer(row, config, target, i);
        final ordered = alive.keys.toList()..sort();
        state = state.copyWith(servers: [for (final k in ordered) alive[k]!]);
      }
    }

    await Future.wait([for (var k = 0; k < _probeConcurrency; k++) worker()]);
  }
}

final thirdPartyServersProvider =
    StateNotifierProvider<ThirdPartyNotifier, ThirdPartyState>(
  (ref) => ThirdPartyNotifier(),
);
