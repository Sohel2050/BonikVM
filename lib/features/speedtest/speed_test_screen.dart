import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/level_play_service.dart';
import '../../core/services/vpn_state.dart';
import '../../core/localization/app_localizations.dart';
import '../../shared/providers/app_providers.dart';
import '../../widgets/level_play_banner_ad.dart';

const String kSpeedTestBase = 'https://speedtest.albonik.com';
const int kSpeedTestSeconds = 8;
const int kFreeTestsBeforeReward = 2;

/// Speed-test palette. Follows the app's light/dark mode AND the accent
/// colour the user picked (Theme.primaryColor), instead of fixed colours.
class _SP {
  final bool dark;
  final Color accent;
  const _SP(this.dark, this.accent);

  Color get bg => dark ? const Color(0xFF0A0A0A) : const Color(0xFFF8F9FA);
  Color get card => dark ? const Color(0xFF161616) : Colors.white;
  Color get line => dark ? const Color(0xFF1F1F1F) : const Color(0xFFE5E7EB);
  Color get track => dark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E7EB);
  Color get muted => dark ? const Color(0xFF8C8C8C) : const Color(0xFF6B7280);
  Color get text => dark ? Colors.white : const Color(0xFF111827);
  Color get grid => dark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
  Color get orange => const Color(0xFFF5A623); // upload colour (fixed)

  /// Readable text/icon colour to put ON TOP of [accent].
  Color get onAccent =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : Colors.black;
}

extension _SPX on BuildContext {
  _SP get sp {
    final t = Theme.of(this);
    return _SP(t.brightness == Brightness.dark, t.primaryColor);
  }
}

class _Counter {
  int value = 0;
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _PingResult {
  final int ping;
  final int jitter;
  const _PingResult(this.ping, this.jitter);
}

class SpeedTestEngine {
  final String base;
  bool _cancelled = false;
  bool _phaseStop = false;
  String? lastError;
  final List<HttpClient> _clients = [];

  SpeedTestEngine(this.base);

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _phaseStop = true;
    _closeClients();
  }

  void _closeClients() {
    for (final c in _clients) {
      try {
        c.close(force: true);
      } catch (_) {}
    }
    _clients.clear();
  }

  HttpClient _newClient() {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 5)
      ..autoUncompress = false
      ..userAgent =
          'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';
    _clients.add(c);
    return c;
  }

  /// Extra request headers (overridden by the Cloudflare engine).
  void _hdr(HttpClientRequest r) {}

  String _url(String path) =>
      '$base/$path?r=${DateTime.now().microsecondsSinceEpoch}';

  Future<_PingResult> measurePing() async {
    final client = _newClient();
    final samples = <double>[];
    for (var i = 0; i < 10; i++) {
      if (_cancelled) throw const _Cancelled();
      final sw = Stopwatch()..start();
      final req = await client.getUrl(Uri.parse(_url('ping')));
      _hdr(req);
      final res = await req.close();
      await res.drain<void>();
      sw.stop();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('bad status ${res.statusCode}');
      }
      if (i > 0) samples.add(sw.elapsedMicroseconds / 1000.0);
    }
    _closeClients();
    final avg = samples.reduce((a, b) => a + b) / samples.length;
    var diff = 0.0;
    for (var i = 1; i < samples.length; i++) {
      diff += (samples[i] - samples[i - 1]).abs();
    }
    final jitter = samples.length > 1 ? diff / (samples.length - 1) : 0.0;
    return _PingResult(avg.round(), jitter.round());
  }

  Future<double> measureDownload(void Function(double mbps) onProgress) {
    return _runPhase(workers: 4, worker: _downloadWorker, onProgress: onProgress);
  }

  Future<double> measureUpload(void Function(double mbps) onProgress) {
    return _runPhase(workers: 3, worker: _uploadWorker, onProgress: onProgress);
  }

  Future<void> _downloadWorker(_Counter total) async {
    final client = _newClient();
    try {
      while (!_phaseStop && !_cancelled) {
        final req = await client.getUrl(Uri.parse(_url('dl.bin')));
        _hdr(req);
        final res = await req.close();
        if (res.statusCode < 200 || res.statusCode >= 300) {
          await res.drain<void>();
          throw HttpException('bad status ${res.statusCode}');
        }
        await for (final chunk in res) {
          if (_phaseStop || _cancelled) break;
          total.value += chunk.length;
        }
      }
    } catch (e) {
      lastError = e.toString();
    }
  }

  Future<void> _uploadWorker(_Counter total) async {
    final client = _newClient();
    final rnd = math.Random();
    final chunk = Uint8List(64 * 1024);
    for (var i = 0; i < chunk.length; i++) {
      chunk[i] = rnd.nextInt(256);
    }
    const chunksPerRequest = 64;
    try {
      while (!_phaseStop && !_cancelled) {
        final req = await client.postUrl(Uri.parse(_url('upload')));
        _hdr(req);
        req.headers.contentType = ContentType.binary;
        req.contentLength = chunk.length * chunksPerRequest;
        for (var i = 0; i < chunksPerRequest; i++) {
          if (_phaseStop || _cancelled) return;
          req.add(chunk);
          await req.flush();
          total.value += chunk.length;
        }
        final res = await req.close();
        await res.drain<void>();
      }
    } catch (e) {
      lastError = e.toString();
    }
  }

  Future<double> _runPhase({
    required int workers,
    required Future<void> Function(_Counter total) worker,
    required void Function(double mbps) onProgress,
  }) async {
    _phaseStop = false;
    final total = _Counter();
    final sw = Stopwatch()..start();
    final history = <List<int>>[];
    var warmMs = 0;
    var warmBytes = 0;
    var warmSet = false;
    final done = Completer<void>();

    final futures = <Future<void>>[
      for (var i = 0; i < workers; i++) worker(total),
    ];
    Future.wait(futures).then((_) {
      if (!done.isCompleted) done.complete();
    });

    final timer = Timer.periodic(const Duration(milliseconds: 250), (t) {
      final ms = sw.elapsedMilliseconds;
      final bytes = total.value;
      history.add([ms, bytes]);
      if (!warmSet && ms >= 1000) {
        warmSet = true;
        warmMs = ms;
        warmBytes = bytes;
      }
      var j = history.length - 1;
      while (j > 0 && ms - history[j][0] < 1000) {
        j--;
      }
      final dt = ms - history[j][0];
      final db = bytes - history[j][1];
      if (dt > 0) onProgress(db * 8 / (dt / 1000.0) / 1e6);
      if (ms >= kSpeedTestSeconds * 1000 || _cancelled) {
        if (!done.isCompleted) done.complete();
      }
    });

    await done.future;
    timer.cancel();
    _phaseStop = true;
    final ms = sw.elapsedMilliseconds;
    final bytes = total.value;
    _closeClients();

    if (_cancelled) throw const _Cancelled();
    if (bytes == 0) {
      throw HttpException('no data${lastError != null ? ' ($lastError)' : ''}');
    }

    final secs = (ms - warmMs) / 1000.0;
    final measuredBytes = bytes - warmBytes;
    if (secs <= 0) return 0;
    return measuredBytes * 8 / secs / 1e6;
  }
}

/// Cloudflare speed test endpoints (speed.cloudflare.com).
class _CloudflareEngine extends SpeedTestEngine {
  _CloudflareEngine() : super('https://speed.cloudflare.com');

  @override
  void _hdr(HttpClientRequest r) {
    r.headers.set('Origin', 'https://speed.cloudflare.com');
    r.headers.set('Referer', 'https://speed.cloudflare.com/');
    r.headers.set('Accept', '*/*');
  }

  @override
  String _url(String path) {
    final r = DateTime.now().microsecondsSinceEpoch;
    switch (path) {
      case 'ping':
        return '$base/__down?bytes=0&r=$r';
      case 'dl.bin':
        return '$base/__down?bytes=100000000&r=$r';
      default:
        return '$base/__up?r=$r';
    }
  }
}

/// M-Lab NDT7 (WebSocket) speed test. The nearest server is found through the
/// public M-Lab "locate" API.
class _Ndt7Engine extends SpeedTestEngine {
  _Ndt7Engine() : super('');

  static const String _protocol = 'net.measurementlab.ndt.v7';
  String? _dlUrl;
  String? _ulUrl;
  final List<WebSocket> _sockets = [];

  Future<void> _locate() async {
    if (_dlUrl != null && _ulUrl != null) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(
          'https://locate.measurementlab.net/v2/nearest/ndt/ndt7?client_name=vpn-master-app'));
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw const HttpException('locate failed');
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final results = (json['results'] as List<dynamic>?) ?? const <dynamic>[];
      for (final r in results) {
        final urls = (r as Map<String, dynamic>)['urls'] as Map<String, dynamic>?;
        final d = urls?['wss:///ndt/v7/download'] as String?;
        final u = urls?['wss:///ndt/v7/upload'] as String?;
        if (d != null && u != null) {
          _dlUrl = d;
          _ulUrl = u;
          return;
        }
      }
      throw const HttpException('no M-Lab server');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<_PingResult> measurePing() async {
    await _locate();
    if (_cancelled) throw const _Cancelled();
    final host = Uri.parse(_dlUrl!).host;
    final samples = <double>[];
    for (var i = 0; i < 7; i++) {
      if (_cancelled) throw const _Cancelled();
      final sw = Stopwatch()..start();
      final sock = await Socket.connect(host, 443,
          timeout: const Duration(seconds: 5));
      sw.stop();
      sock.destroy();
      if (i > 0) samples.add(sw.elapsedMicroseconds / 1000.0);
    }
    final avg = samples.reduce((a, b) => a + b) / samples.length;
    var diff = 0.0;
    for (var i = 1; i < samples.length; i++) {
      diff += (samples[i] - samples[i - 1]).abs();
    }
    final jitter = samples.length > 1 ? diff / (samples.length - 1) : 0.0;
    return _PingResult(avg.round(), jitter.round());
  }

  // NDT7 is a single-stream test (the access tokens are per URL).
  @override
  Future<double> measureDownload(void Function(double mbps) onProgress) =>
      _runPhase(workers: 1, worker: _downloadWorker, onProgress: onProgress);

  @override
  Future<double> measureUpload(void Function(double mbps) onProgress) =>
      _runPhase(workers: 1, worker: _uploadWorker, onProgress: onProgress);

  @override
  Future<void> _downloadWorker(_Counter total) async {
    try {
      final ws = await WebSocket.connect(
        _dlUrl!,
        protocols: const [_protocol],
        compression: CompressionOptions.compressionOff,
      ).timeout(const Duration(seconds: 10));
      _sockets.add(ws);
      final closed = Completer<void>();
      ws.listen(
        (dynamic m) {
          if (m is List<int>) {
            total.value += m.length;
          } else if (m is String) {
            total.value += m.length;
          }
        },
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object _) {
          if (!closed.isCompleted) closed.complete();
        },
        cancelOnError: true,
      );
      while (!_phaseStop && !_cancelled && !closed.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      lastError = e.toString();
    }
  }

  @override
  Future<void> _uploadWorker(_Counter total) async {
    try {
      final ws = await WebSocket.connect(
        _ulUrl!,
        protocols: const [_protocol],
        compression: CompressionOptions.compressionOff,
      ).timeout(const Duration(seconds: 10));
      _sockets.add(ws);
      final rnd = math.Random();
      final chunk = Uint8List(64 * 1024);
      for (var i = 0; i < chunk.length; i++) {
        chunk[i] = rnd.nextInt(256);
      }
      Stream<List<int>> gen() async* {
        while (!_phaseStop && !_cancelled) {
          yield chunk;
          total.value += chunk.length;
        }
      }

      await ws.addStream(gen());
    } catch (e) {
      lastError = e.toString();
    }
  }

  @override
  void _closeClients() {
    for (final s in _sockets) {
      try {
        s.close().catchError((Object _) {});
      } catch (_) {}
    }
    _sockets.clear();
    super._closeClients();
  }
}

enum _Provider { cloudflare, mlab }

enum _Phase { ready, ping, download, upload, done, error }

class SpeedTestScreen extends ConsumerStatefulWidget {
  /// When true the screen is used as a tab inside MainShell: the shell already
  /// shows the app bar, so the screen hides its own header (back button/title).
  final bool embedded;

  const SpeedTestScreen({super.key, this.embedded = false});

  @override
  ConsumerState<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends ConsumerState<SpeedTestScreen> {
  static int _testsSinceReward = 0;
  bool _adShownForThisTest = false;

  SpeedTestEngine? _engine;
  _Provider _provider = _Provider.cloudflare;
  List<ConnectivityResult> _net = const [];
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  _Phase _phase = _Phase.ready;
  double _live = 0;
  double _down = 0;
  double _up = 0;
  int _ping = 0;
  int _jitter = 0;
  double? _planMbps; // speed the user pays for (optional)
  bool _checkingSites = false;
  final Map<String, int?> _siteMs = {}; // null = timeout, missing = not checked

  bool get _running =>
      _phase == _Phase.ping ||
      _phase == _Phase.download ||
      _phase == _Phase.upload;

  @override
  void initState() {
    super.initState();
    _loadProvider();
    _loadPlan();
    Connectivity().checkConnectivity().then((r) {
      if (mounted) setState(() => _net = r);
    }).catchError((Object _) {});
    _netSub = Connectivity().onConnectivityChanged.listen((r) {
      if (mounted) setState(() => _net = r);
    });
  }

  @override
  void dispose() {
    _netSub?.cancel();
    _engine?.cancel();
    LevelPlayService.instance.clearRewardedCallbacks();
    super.dispose();
  }

  Future<void> _loadProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('speedtest_provider') == 'mlab' && mounted) {
        setState(() => _provider = _Provider.mlab);
      }
    } catch (_) {}
  }

  Future<void> _setProvider(_Provider p) async {
    if (_running || p == _provider) return;
    setState(() => _provider = p);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('speedtest_provider', p.name);
    } catch (_) {}
  }

  String get _netLabel {
    if (_net.contains(ConnectivityResult.wifi)) return 'Wi-Fi';
    if (_net.contains(ConnectivityResult.mobile)) return tr('mobile_data');
    if (_net.contains(ConnectivityResult.ethernet)) return 'Ethernet';
    if (_net.contains(ConnectivityResult.vpn)) return 'VPN';
    if (_net.isEmpty || _net.contains(ConnectivityResult.none)) {
      return tr('no_network');
    }
    return tr('online_label');
  }

  IconData get _netIcon {
    if (_net.contains(ConnectivityResult.wifi)) return Icons.wifi_rounded;
    if (_net.contains(ConnectivityResult.mobile)) {
      return Icons.signal_cellular_alt_rounded;
    }
    if (_net.contains(ConnectivityResult.ethernet)) {
      return Icons.settings_ethernet_rounded;
    }
    if (_net.isEmpty || _net.contains(ConnectivityResult.none)) {
      return Icons.wifi_off_rounded;
    }
    return Icons.public;
  }

  bool get _needsReward =>
      !ref.read(premiumStatusProvider) &&
      (_phase == _Phase.done || _phase == _Phase.error) &&
      _testsSinceReward >= kFreeTestsBeforeReward;

  Future<void> _onStartPressed() async {
    if (_running) return;
    if (!_needsReward) {
      _adShownForThisTest = false;
      await _start();
      return;
    }
    final svc = LevelPlayService.instance;
    final available = await svc.checkRewardedVideoAvailable();
    if (!mounted) return;
    if (!available) {
      _testsSinceReward = 0;
      _adShownForThisTest = false;
      await _start();
      return;
    }
    var earned = false;
    svc.setRewardedCallbacks(
      LevelPlayRewardedCallbacks(
        onRewarded: (name, amount) => earned = true,
        onShowFailed: (msg) {
          if (!mounted) return;
          _testsSinceReward = 0;
          _adShownForThisTest = false;
          _start();
        },
        onClosed: () {
          if (!mounted) return;
          if (earned) {
            _testsSinceReward = 0;
            _adShownForThisTest = true;
            _start();
          } else {
            _snack(tr('st_watch_full_ad'));
          }
        },
      ),
    );
    await svc.showRewardedVideo(placementName: 'Rewards');
  }

  String? _errDetail;

  String _short(Object e) {
    final t = e.toString().replaceAll('\n', ' ');
    return t.length > 110 ? '${t.substring(0, 110)}...' : t;
  }

  /// Runs one full test (ping, download, upload) with [engine].
  /// Throws on failure; returns false when the test was cancelled.
  Future<bool> _runEngine(SpeedTestEngine engine) async {
    _engine = engine;
    setState(() {
      _phase = _Phase.ping;
      _live = 0;
      _down = 0;
      _up = 0;
      _ping = 0;
      _jitter = 0;
    });
    final p = await engine.measurePing();
    if (!mounted || engine.cancelled) return false;
    setState(() {
      _ping = p.ping;
      _jitter = p.jitter;
      _phase = _Phase.download;
      _live = 0;
    });
    final d = await engine.measureDownload((v) {
      if (mounted && !engine.cancelled) setState(() => _live = v);
    });
    if (!mounted || engine.cancelled) return false;
    setState(() {
      _down = d;
      _phase = _Phase.upload;
      _live = 0;
    });
    final u = await engine.measureUpload((v) {
      if (mounted && !engine.cancelled) setState(() => _live = v);
    });
    if (!mounted || engine.cancelled) return false;
    setState(() {
      _up = u;
      _phase = _Phase.done;
      _live = 0;
    });
    return true;
  }

  Future<void> _start() async {
    if (_running) return;
    _errDetail = null;
    final mlabFirst = _provider == _Provider.mlab;
    final names = mlabFirst ? ['M-Lab', 'Cloudflare'] : ['Cloudflare', 'M-Lab'];
    SpeedTestEngine make(int i) => (i == 0) == mlabFirst
        ? _Ndt7Engine()
        : _CloudflareEngine();
    final errors = <String>[];
    for (var i = 0; i < 2; i++) {
      final engine = make(i);
      try {
        final ok = await _runEngine(engine);
        if (!ok) return;
        _onFinished();
        return;
      } on _Cancelled {
        return;
      } catch (e) {
        debugPrint('Speed test: ${names[i]} failed: $e');
        if (!mounted || engine.cancelled) return;
        errors.add('${names[i]}: ${_short(e)}');
      }
    }
    if (!mounted) return;
    setState(() {
      _errDetail = errors.join('\n');
      _phase = _Phase.error;
    });
  }

  void _stop() {
    _engine?.cancel();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.ready;
      _live = 0;
    });
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('speedtest_history');
      final list = raw == null
          ? <dynamic>[]
          : List<dynamic>.from(jsonDecode(raw) as List<dynamic>);
      final connected = ref.read(vpnStateProvider).value == VpnState.connected;
      list.insert(0, <String, dynamic>{
        't': DateTime.now().millisecondsSinceEpoch,
        'p': _provider.name,
        'd': _down,
        'u': _up,
        'ping': _ping,
        'j': _jitter,
        'b': ((_down + _up) * kSpeedTestSeconds * 125000).round(),
        'v': connected ? ref.read(currentServerProvider)?.name : null,
      });
      if (list.length > 30) list.removeRange(30, list.length);
      await prefs.setString('speedtest_history', jsonEncode(list));
    } catch (_) {}
  }


  Future<void> _loadPlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble('speedtest_plan_mbps');
      if (v != null && v > 0 && mounted) setState(() => _planMbps = v);
    } catch (_) {}
  }

  Future<void> _editPlan() async {
    final ctrl = TextEditingController(
      text: _planMbps == null ? '' : _planMbps!.toStringAsFixed(0),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.sp.card,
        title: Text(tr('st_set_plan'),
            style: TextStyle(color: context.sp.text, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: context.sp.text),
          decoration: InputDecoration(
            hintText: tr('st_plan_hint'),
            hintStyle: TextStyle(color: context.sp.muted),
            suffixText: 'Mbps',
            suffixStyle: TextStyle(color: context.sp.muted),
          ),
        ),
        actions: [
          if (_planMbps != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(tr('remove'), style: TextStyle(color: context.sp.muted)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel'), style: TextStyle(color: context.sp.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('save'), style: TextStyle(color: context.sp.accent)),
          ),
        ],
      ),
    );
    if (result == null) return;
    final v = double.tryParse(result.replaceAll(',', '.'));
    try {
      final prefs = await SharedPreferences.getInstance();
      if (v == null || v <= 0) {
        await prefs.remove('speedtest_plan_mbps');
        if (mounted) setState(() => _planMbps = null);
      } else {
        await prefs.setDouble('speedtest_plan_mbps', v);
        if (mounted) setState(() => _planMbps = v);
      }
    } catch (_) {}
  }

  static const List<(String, String, IconData)> _sites = [
    ('Google', 'https://www.google.com/generate_204', Icons.search),
    ('YouTube', 'https://www.youtube.com/generate_204', Icons.play_arrow_rounded),
    ('Facebook', 'https://www.facebook.com/favicon.ico', Icons.thumb_up_alt_outlined),
    ('WhatsApp', 'https://www.whatsapp.com/favicon.ico', Icons.chat_bubble_outline),
    ('Cloudflare', 'https://www.cloudflare.com/cdn-cgi/trace', Icons.cloud_outlined),
  ];

  Future<int?> _pingSite(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..autoUncompress = false;
    try {
      final sw = Stopwatch()..start();
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>().timeout(const Duration(seconds: 5));
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _checkSites() async {
    if (_checkingSites || _running) return;
    setState(() {
      _checkingSites = true;
      _siteMs.clear();
    });
    await Future.wait(_sites.map((site) async {
      final ms = await _pingSite(site.$2);
      if (mounted) setState(() => _siteMs[site.$1] = ms);
    }));
    if (mounted) setState(() => _checkingSites = false);
  }

  Widget _planCard() {
    String sub = tr('st_compare');
    if (_planMbps != null) {
      final plan = _planMbps!.toStringAsFixed(0);
      if (_phase == _Phase.done && _down > 0) {
        final pct = (_down / _planMbps! * 100).round();
        sub = tr('st_plan_reached', {'plan': plan, 'pct': '$pct'});
      } else {
        sub = tr('st_plan_each', {'plan': plan});
      }
    }
    return InkWell(
      onTap: _editPlan,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.sp.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('st_set_plan'),
                      style: TextStyle(
                          color: context.sp.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(sub,
                      style: TextStyle(color: context.sp.muted, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.edit_outlined, color: context.sp.muted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _latencyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.sp.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tr('st_latency_title'),
                    style: TextStyle(
                        color: context.sp.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
              _checkingSites
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.sp.accent),
                    )
                  : TextButton(
                      onPressed: _running ? null : _checkSites,
                      child: Text(tr('check'),
                          style: TextStyle(
                              color: context.sp.accent,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr('st_latency_desc'),
            style: TextStyle(color: context.sp.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final site in _sites)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(site.$3, color: context.sp.muted, size: 22),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(site.$1,
                        style: TextStyle(
                            color: context.sp.text, fontSize: 15)),
                  ),
                  Text(
                    !_siteMs.containsKey(site.$1)
                        ? '--'
                        : (_siteMs[site.$1] == null
                            ? tr('st_no_response')
                            : '${_siteMs[site.$1]} ms'),
                    style: TextStyle(
                      color: _siteMs.containsKey(site.$1) &&
                              _siteMs[site.$1] == null
                          ? const Color(0xFFF87171)
                          : context.sp.muted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _fmtTime(int ms) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $hh:$mm';
  }

  Future<void> _showHistory() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _SpeedHistoryScreen()),
    );
  }

  void _onFinished() {
    _saveHistory();
    _testsSinceReward++;
    final premium = ref.read(premiumStatusProvider);
    if (!premium && !_adShownForThisTest) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        LevelPlayService.instance
            .showInterstitial(placementName: 'Interstitial');
      });
    }
  }

  Future<void> _watchAdForTime() async {
    final svc = LevelPlayService.instance;
    final available = await svc.checkRewardedVideoAvailable();
    if (!mounted) return;
    if (!available) {
      _snack(tr('st_no_ad'));
      return;
    }
    final cfg = await ref.read(adsPopupConfigProvider.future);
    final minutes = cfg.adRewardDuration;
    svc.setRewardedCallbacks(
      LevelPlayRewardedCallbacks(
        onRewarded: (name, amount) {
          ref
              .read(freeConnectionTimerProvider.notifier)
              .addTime(minutes * 60);
          _snack(tr('st_time_extended', {'n': '$minutes'}));
        },
        onShowFailed: (msg) =>
            _snack(tr('st_no_ad')),
      ),
    );
    await svc.showRewardedVideo(placementName: 'Rewards');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  String _fmt(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  double get _gaugeValue {
    switch (_phase) {
      case _Phase.download:
      case _Phase.upload:
        return _live;
      case _Phase.done:
        return _down;
      default:
        return 0;
    }
  }

  String get _bigText {
    final v = _gaugeValue;
    if (_phase == _Phase.ready || _phase == _Phase.ping || _phase == _Phase.error) {
      return '--';
    }
    return _fmt(v);
  }

  String get _unitText {
    switch (_phase) {
      case _Phase.ping:
        return tr('st_checking_ping');
      case _Phase.download:
        return tr('st_mbps_download');
      case _Phase.upload:
        return tr('st_mbps_upload');
      case _Phase.done:
        return tr('st_mbps_download');
      case _Phase.error:
        return tr('st_test_failed');
      case _Phase.ready:
        return 'Mbps';
    }
  }

  String get _statusLabel {
    switch (_phase) {
      case _Phase.ready:
        return tr('st_tap_start');
      case _Phase.ping:
        return _provider == _Provider.mlab
            ? tr('st_finding_server')
            : tr('st_checking_ping');
      case _Phase.download:
        return tr('st_testing_download');
      case _Phase.upload:
        return tr('st_testing_upload');
      case _Phase.done:
        return tr('st_result');
      case _Phase.error:
        return tr('st_test_failed');
    }
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) => InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: context.sp.card, shape: BoxShape.circle),
          child: Icon(icon, size: 22, color: context.sp.text),
        ),
      );

  Widget _header() => widget.embedded
      ? const SizedBox.shrink()
      : Row(
        children: [
          if (!widget.embedded) ...[
            _circleBtn(Icons.arrow_back, () => Navigator.of(context).maybePop()),
            const SizedBox(width: 14),
            Text(tr('st_header'),
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: context.sp.text)),
          ],
          const Spacer(),
          Flexible(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_netIcon, size: 18, color: context.sp.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_netLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.sp.muted, fontSize: 14)),
              ),
            ]),
          ),
          IconButton(
            tooltip: tr('history'),
            icon: Icon(Icons.history, color: context.sp.muted),
            onPressed: _showHistory,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final vpnState = ref.watch(vpnStateProvider).value;
    final connected = vpnState == VpnState.connected;
    final server = ref.watch(currentServerProvider);
    final premium = ref.watch(premiumStatusProvider);
    final timer = ref.watch(freeConnectionTimerProvider);

    final fraction = (math.log(1 + _gaugeValue) / math.log(1 + 500))
        .clamp(0.0, 1.0)
        .toDouble();
    final color = _phase == _Phase.upload ? context.sp.orange : context.sp.accent;

    final gated = !_running &&
        !premium &&
        (_phase == _Phase.done || _phase == _Phase.error) &&
        _testsSinceReward >= kFreeTestsBeforeReward;
    final ctaLabel = _running
        ? tr('stop')
        : (_phase == _Phase.done || _phase == _Phase.error
            ? (gated ? tr('st_watch_ad_again') : tr('st_test_again'))
            : tr('start'));
    final gaugeHeight =
        (MediaQuery.of(context).size.height * 0.26).clamp(180.0, 250.0);

    return Scaffold(
      backgroundColor: context.sp.bg,
      body: SafeArea(
        top: !widget.embedded,
        child: Column(
          children: [
            const _AdBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                children: [
                  _header(),
                  if (!widget.embedded) const SizedBox(height: 10),
                  _ProviderToggle(
                    value: _provider,
                    enabled: !_running,
                    onChanged: _setProvider,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: gaugeHeight,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: fraction),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                      builder: (context, f, _) => CustomPaint(
                        painter: _GaugePainter(
                            fraction: f,
                            color: color,
                            trackColor: context.sp.track),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _bigText,
                                    style: TextStyle(
                                      color: context.sp.text,
                                      fontSize: 56,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  _unitText,
                                  style: TextStyle(
                                      color: context.sp.muted, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.symmetric(
                        horizontal: BorderSide(color: context.sp.line),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: _ResultCell(
                              icon: Icons.arrow_downward,
                              label: tr('download_word'),
                              color: context.sp.accent,
                              value: (_phase == _Phase.done ||
                                      _phase == _Phase.upload)
                                  ? _fmt(_down)
                                  : '--',
                            ),
                          ),
                          VerticalDivider(width: 1, color: context.sp.line),
                          Expanded(
                            child: _ResultCell(
                              icon: Icons.arrow_upward,
                              label: tr('upload_word'),
                              color: context.sp.orange,
                              value: _phase == _Phase.done ? _fmt(_up) : '--',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniCard(
                          label: tr('ping_word'),
                          value: _ping > 0 ? '$_ping ms' : '--',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MiniCard(
                          label: tr('jitter_word'),
                          value: _ping > 0 ? '$_jitter ms' : '--',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.public, size: 22, color: context.sp.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          connected
                              ? '${tr('st_connected_server')}: ${server?.name ?? 'VPN'}'
                              : tr('st_not_connected'),
                          style:
                              TextStyle(color: context.sp.muted, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  if (_phase == _Phase.error)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('st_cant_reach'),
                            style: TextStyle(color: Colors.redAccent),
                          ),
                          if (_errDetail != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(_errDetail!,
                                  style: TextStyle(
                                      color: context.sp.muted, fontSize: 11)),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  _planCard(),
                  const SizedBox(height: 12),
                  _latencyCard(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                _statusLabel,
                style: TextStyle(
                    color: _running ? context.sp.accent : context.sp.muted, fontSize: 14),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _running ? _stop : _onStartPressed,
                      style: FilledButton.styleFrom(
                        backgroundColor: _running ? context.sp.card : context.sp.accent,
                        foregroundColor: _running ? context.sp.text : context.sp.onAccent,
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        ctaLabel,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  if (_phase == _Phase.done && !premium && timer.isActive) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _watchAdForTime,
                        icon: Icon(Icons.play_circle_outline,
                            size: 20, color: context.sp.accent),
                        label: Text(
                          tr('st_watch_ad_free'),
                          style: TextStyle(color: context.sp.accent, fontSize: 15),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: context.sp.accent),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Network type + History button shown on the right side of the top app bar
/// when the Speed Test page is used as a tab inside MainShell.
class SpeedTestAppBarActions extends ConsumerStatefulWidget {
  const SpeedTestAppBarActions({super.key});

  @override
  ConsumerState<SpeedTestAppBarActions> createState() =>
      _SpeedTestAppBarActionsState();
}

class _SpeedTestAppBarActionsState
    extends ConsumerState<SpeedTestAppBarActions> {
  List<ConnectivityResult> _net = const [];
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then((r) {
      if (mounted) setState(() => _net = r);
    }).catchError((Object _) {});
    _sub = Connectivity().onConnectivityChanged.listen((r) {
      if (mounted) setState(() => _net = r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String get _label {
    if (_net.contains(ConnectivityResult.wifi)) return 'Wi-Fi';
    if (_net.contains(ConnectivityResult.mobile)) return tr('mobile_data');
    if (_net.contains(ConnectivityResult.ethernet)) return 'Ethernet';
    if (_net.contains(ConnectivityResult.vpn)) return 'VPN';
    if (_net.isEmpty || _net.contains(ConnectivityResult.none)) {
      return tr('no_connection');
    }
    return tr('online_label');
  }

  IconData get _icon {
    if (_net.contains(ConnectivityResult.wifi)) return Icons.wifi;
    if (_net.contains(ConnectivityResult.mobile)) {
      return Icons.signal_cellular_alt;
    }
    if (_net.contains(ConnectivityResult.ethernet)) {
      return Icons.settings_ethernet;
    }
    if (_net.isEmpty || _net.contains(ConnectivityResult.none)) {
      return Icons.signal_wifi_off;
    }
    return Icons.public;
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final color = context.sp.dark ? Colors.white70 : Colors.black54;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon, size: 18, color: color),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 90),
          child: Text(
            _label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 13),
          ),
        ),
        IconButton(
          tooltip: tr('history'),
          icon: Icon(Icons.history, color: color),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => const _SpeedHistoryScreen()),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _ProviderToggle extends StatelessWidget {
  final _Provider value;
  final bool enabled;
  final ValueChanged<_Provider> onChanged;

  const _ProviderToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  Widget _segment(BuildContext context, String label, _Provider p) {
    final selected = value == p;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(p) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? context.sp.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? context.sp.onAccent : context.sp.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.sp.card,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            _segment(context, 'Cloudflare', _Provider.cloudflare),
            _segment(context, 'M-Lab', _Provider.mlab),
          ],
        ),
      ),
    );
  }
}

class _ResultCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String value;

  const _ResultCell({
    required this.icon,
    required this.label,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontSize: 17)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: context.sp.text,
                fontSize: 36,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text('Mbps', style: TextStyle(color: context.sp.muted, fontSize: 15)),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String label;
  final String value;

  const _MiniCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: context.sp.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.sp.muted, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: context.sp.text,
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color trackColor;

  _GaugePainter(
      {required this.fraction, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 16;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = 135 * math.pi / 180;
    const sweep = 270 * math.pi / 180;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, start, sweep, false, track);
    if (fraction > 0.005) {
      final bar = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect, start, sweep * fraction, false, bar);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.trackColor != trackColor;
}

class _AdBanner extends ConsumerStatefulWidget {
  const _AdBanner();

  @override
  ConsumerState<_AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<_AdBanner> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    if (_failed || ref.watch(premiumStatusProvider)) {
      return const SizedBox.shrink();
    }
    return Padding(
      // Slightly more space ABOVE the banner than below it.
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Center(
        child: SizedBox(
          width: 320,
          height: 50,
          child: LevelPlayBannerAd(
            adUnitId: LevelPlayService.instance.bannerAdUnitId,
            onFailed: () {
              if (mounted) setState(() => _failed = true);
            },
          ),
        ),
      ),
    );
  }
}


class _SpeedHistoryScreen extends StatefulWidget {
  const _SpeedHistoryScreen();

  @override
  State<_SpeedHistoryScreen> createState() => _SpeedHistoryScreenState();
}

class _SpeedHistoryScreenState extends State<_SpeedHistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var items = <Map<String, dynamic>>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('speedtest_history');
      if (raw != null) {
        items = (jsonDecode(raw) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _items = items;
        _loaded = true;
      });
    }
  }

  String _mb(num bytes) => '${(bytes / 1000000).toStringAsFixed(1)} MB';

  String _fmtV(double v) =>
      v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  String _fmtTime(int ms) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, $hh:$mm';
  }

  Future<void> _export() async {
    if (_items.isEmpty) return;
    final b = StringBuffer(
        'time,provider,download_mbps,upload_mbps,ping_ms,jitter_ms,data_mb,vpn_server\n');
    for (final m in _items) {
      final t = DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt())
          .toIso8601String();
      b.writeln([
        t,
        m['p'] == 'mlab' ? 'M-Lab' : 'Cloudflare',
        ((m['d'] as num?) ?? 0).toStringAsFixed(2),
        ((m['u'] as num?) ?? 0).toStringAsFixed(2),
        m['ping'] ?? '',
        m['j'] ?? '',
        (((m['b'] as num?) ?? 0) / 1000000).toStringAsFixed(1),
        (m['v'] ?? '').toString().replaceAll(',', ' '),
      ].join(','));
    }
    try {
      await Share.share(b.toString(), subject: tr('st_history_subject'));
    } catch (_) {}
  }

  Future<void> _clear() async {
    if (_items.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.sp.card,
        title: Text(tr('st_clear_q'),
            style: TextStyle(color: context.sp.text, fontSize: 17)),
        content: Text(tr('st_clear_msg'),
            style: TextStyle(color: context.sp.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'), style: TextStyle(color: context.sp.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('clear'), style: TextStyle(color: context.sp.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('speedtest_history');
    } catch (_) {}
    if (mounted) setState(() => _items = []);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    num monthBytes = 0;
    num allBytes = 0;
    for (final m in _items) {
      final b = (m['b'] as num?) ?? 0;
      allBytes += b;
      final d = DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt());
      if (d.year == now.year && d.month == now.month) monthBytes += b;
    }
    // Newest first in storage; the chart shows the last 6 oldest -> newest.
    final last6 = _items
        .take(6)
        .map((m) => ((m['d'] as num?) ?? 0).toDouble())
        .toList()
        .reversed
        .toList();
    final latest = last6.isEmpty ? 0.0 : last6.last;
    final best = last6.isEmpty ? 0.0 : last6.reduce(math.max);
    final avg =
        last6.isEmpty ? 0.0 : last6.reduce((a, b) => a + b) / last6.length;

    return Scaffold(
      backgroundColor: context.sp.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: context.sp.card, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back,
                          color: context.sp.text, size: 22),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(tr('history'),
                        style: TextStyle(
                            color: context.sp.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    onPressed: _items.isEmpty ? null : _export,
                    icon: Icon(Icons.download_rounded,
                        color: context.sp.text.withValues(alpha: 0.7)),
                  ),
                  IconButton(
                    onPressed: _items.isEmpty ? null : _clear,
                    icon: Icon(Icons.delete_outline_rounded,
                        color: context.sp.text.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: context.sp.card,
                              borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            children: [
                              Icon(Icons.data_usage_rounded,
                                  color: context.sp.muted, size: 28),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tr('st_data_used'),
                                        style: TextStyle(
                                            color: context.sp.muted, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text(
                                      tr('st_data_line', {'m': _mb(monthBytes), 'a': _mb(allBytes)}),
                                      style: TextStyle(
                                          color: context.sp.text,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: context.sp.card,
                              borderRadius: BorderRadius.circular(20)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('st_chart_title'),
                                  style: TextStyle(
                                      color: context.sp.muted, fontSize: 14)),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 130,
                                width: double.infinity,
                                child: last6.length < 2
                                    ? Center(
                                        child: Text(tr('st_chart_empty'),
                                            style: TextStyle(
                                                color: context.sp.muted, fontSize: 13)),
                                      )
                                    : CustomPaint(
                                        painter: _LineChartPainter(last6,
                                            lineColor: context.sp.accent,
                                            gridColor: context.sp.grid)),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _stat(tr('st_latest'), _fmtV(latest)),
                                  _stat(tr('st_average'), _fmtV(avg),
                                      center: true),
                                  _stat(tr('st_best'), _fmtV(best), end: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const _AdBanner(),
                        const SizedBox(height: 4),
                        if (_items.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(tr('st_no_tests'),
                                  style: TextStyle(
                                      color: context.sp.muted, fontSize: 14)),
                            ),
                          )
                        else
                          for (final m in _items) _row(m),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value,
      {bool center = false, bool end = false}) {
    return Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : (center ? CrossAxisAlignment.center : CrossAxisAlignment.start),
      children: [
        Text(label, style: TextStyle(color: context.sp.muted, fontSize: 14)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: context.sp.text,
                fontSize: 26,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _row(Map<String, dynamic> m) {
    final prov = m['p'] == 'mlab' ? 'M-Lab' : 'Cloudflare';
    final vpn = m['v'] as String?;
    final bytes = (m['b'] as num?) ?? 0;
    final sub = [
      if (vpn != null) vpn,
      prov,
      if (bytes > 0) _mb(bytes),
    ].join(' - ');
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: context.sp.card, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.wifi_rounded, color: context.sp.muted, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmtTime((m['t'] as num).toInt()),
                    style: TextStyle(color: context.sp.muted, fontSize: 15)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.arrow_downward,
                          color: context.sp.accent, size: 18),
                      const SizedBox(width: 4),
                      Text(_fmtV(((m['d'] as num?) ?? 0).toDouble()),
                          style: TextStyle(
                              color: context.sp.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w600)),
                    ]),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.arrow_upward,
                          color: context.sp.orange, size: 18),
                      const SizedBox(width: 4),
                      Text(_fmtV(((m['u'] as num?) ?? 0).toDouble()),
                          style: TextStyle(
                              color: context.sp.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w600)),
                    ]),
                    Text(tr('st_ping_ms', {'v': '${m['ping']}'}),
                        style: TextStyle(
                            color: context.sp.text, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(sub,
                    style: TextStyle(color: context.sp.muted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color gridColor;
  _LineChartPainter(this.values,
      {required this.lineColor, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);
    const pad = 8.0;
    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = pad + (size.width - 2 * pad) * i / (values.length - 1);
      final y = pad + (size.height - 2 * pad) * (1 - (values[i] - minV) / range);
      pts.add(Offset(x, y));
    }
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = lineColor;
    for (final p in pts) {
      canvas.drawCircle(p, 5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor;
}
