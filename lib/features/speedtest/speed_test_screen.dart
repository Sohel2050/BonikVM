import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/level_play_service.dart';
import '../../core/services/vpn_state.dart';
import '../../shared/providers/app_providers.dart';
import '../../widgets/level_play_banner_ad.dart';

const String kSpeedTestBase = 'https://speedtest.albonik.com';
const int kSpeedTestSeconds = 8;
const int kFreeTestsBeforeReward = 2;

const Color _kBg = Color(0xFF0B0B0B);
const Color _kCard = Color(0xFF1C1C1C);
const Color _kLime = Color(0xFFAEEA1C);
const Color _kOrange = Color(0xFFF59E0B);
const Color _kTrack = Color(0xFF242424);
const Color _kMuted = Color(0xFF8A8A8A);

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
      ..autoUncompress = false;
    _clients.add(c);
    return c;
  }

  String _url(String path) =>
      '$base/$path?r=${DateTime.now().microsecondsSinceEpoch}';

  Future<_PingResult> measurePing() async {
    final client = _newClient();
    final samples = <double>[];
    for (var i = 0; i < 10; i++) {
      if (_cancelled) throw const _Cancelled();
      final sw = Stopwatch()..start();
      final req = await client.getUrl(Uri.parse(_url('ping')));
      final res = await req.close();
      await res.drain<void>();
      sw.stop();
      if (res.statusCode != 200) throw const HttpException('bad status');
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
        final res = await req.close();
        if (res.statusCode != 200) {
          await res.drain<void>();
          throw const HttpException('bad status');
        }
        await for (final chunk in res) {
          if (_phaseStop || _cancelled) break;
          total.value += chunk.length;
        }
      }
    } catch (_) {}
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
    } catch (_) {}
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
    if (bytes == 0) throw const HttpException('no data');

    final secs = (ms - warmMs) / 1000.0;
    final measuredBytes = bytes - warmBytes;
    if (secs <= 0) return 0;
    return measuredBytes * 8 / secs / 1e6;
  }
}

enum _Phase { ready, ping, download, upload, done, error }

class SpeedTestScreen extends ConsumerStatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  ConsumerState<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends ConsumerState<SpeedTestScreen> {
  static int _testsSinceReward = 0;
  bool _adShownForThisTest = false;

  SpeedTestEngine? _engine;
  _Phase _phase = _Phase.ready;
  double _live = 0;
  double _down = 0;
  double _up = 0;
  int _ping = 0;
  int _jitter = 0;

  bool get _running =>
      _phase == _Phase.ping ||
      _phase == _Phase.download ||
      _phase == _Phase.upload;

  @override
  void dispose() {
    _engine?.cancel();
    LevelPlayService.instance.clearRewardedCallbacks();
    super.dispose();
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
            _snack('Watch the full ad to run another test.');
          }
        },
      ),
    );
    await svc.showRewardedVideo(placementName: 'Rewards');
  }

  Future<void> _start() async {
    if (_running) return;
    final engine = SpeedTestEngine(kSpeedTestBase);
    _engine = engine;
    setState(() {
      _phase = _Phase.ping;
      _live = 0;
      _down = 0;
      _up = 0;
      _ping = 0;
      _jitter = 0;
    });
    try {
      final p = await engine.measurePing();
      if (!mounted || engine.cancelled) return;
      setState(() {
        _ping = p.ping;
        _jitter = p.jitter;
        _phase = _Phase.download;
        _live = 0;
      });

      final d = await engine.measureDownload((v) {
        if (mounted && !engine.cancelled) setState(() => _live = v);
      });
      if (!mounted || engine.cancelled) return;
      setState(() {
        _down = d;
        _phase = _Phase.upload;
        _live = 0;
      });

      final u = await engine.measureUpload((v) {
        if (mounted && !engine.cancelled) setState(() => _live = v);
      });
      if (!mounted || engine.cancelled) return;
      setState(() {
        _up = u;
        _phase = _Phase.done;
        _live = 0;
      });
      _onFinished();
    } on _Cancelled {
      return;
    } catch (_) {
      if (!mounted || engine.cancelled) return;
      setState(() => _phase = _Phase.error);
    }
  }

  void _stop() {
    _engine?.cancel();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.ready;
      _live = 0;
    });
  }

  void _onFinished() {
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
      _snack('No ad available right now. Try again in a moment.');
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
          _snack('Free time extended by $minutes minutes');
        },
        onShowFailed: (msg) =>
            _snack('No ad available right now. Try again in a moment.'),
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
        return 'Checking ping...';
      case _Phase.download:
        return 'Mbps download';
      case _Phase.upload:
        return 'Mbps upload';
      case _Phase.done:
        return 'Mbps download';
      case _Phase.error:
        return 'Test failed';
      case _Phase.ready:
        return 'Mbps';
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpnState = ref.watch(vpnStateProvider).value;
    final connected = vpnState == VpnState.connected;
    final server = ref.watch(currentServerProvider);
    final premium = ref.watch(premiumStatusProvider);
    final timer = ref.watch(freeConnectionTimerProvider);

    final fraction = (math.log(1 + _gaugeValue) / math.log(1 + 500))
        .clamp(0.0, 1.0)
        .toDouble();
    final color = _phase == _Phase.upload ? _kOrange : _kLime;

    final gated = !_running &&
        !premium &&
        (_phase == _Phase.done || _phase == _Phase.error) &&
        _testsSinceReward >= kFreeTestsBeforeReward;
    final ctaLabel = _running
        ? 'Stop'
        : (_phase == _Phase.done || _phase == _Phase.error
            ? (gated ? 'Watch ad and test again' : 'Test again')
            : 'Start test');

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: _kCard,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Speed test',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const _AdBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    SizedBox(
                      width: 240,
                      height: 140,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: fraction),
                            duration: const Duration(milliseconds: 250),
                            builder: (context, f, _) => CustomPaint(
                              size: const Size(240, 140),
                              painter: _GaugePainter(fraction: f, color: color),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _bigText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 38,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _unitText,
                                  style: const TextStyle(
                                    color: _kMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: const BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(color: Color(0xFF2A2A2A)),
                        ),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              child: _ResultCell(
                                icon: Icons.arrow_downward,
                                label: 'Download',
                                color: _kLime,
                                value: (_phase == _Phase.done ||
                                        _phase == _Phase.upload)
                                    ? _fmt(_down)
                                    : '--',
                              ),
                            ),
                            const VerticalDivider(
                              width: 1,
                              color: Color(0xFF2A2A2A),
                            ),
                            Expanded(
                              child: _ResultCell(
                                icon: Icons.arrow_upward,
                                label: 'Upload',
                                color: _kOrange,
                                value:
                                    _phase == _Phase.done ? _fmt(_up) : '--',
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
                            label: 'Ping',
                            value: _ping > 0 ? '$_ping ms' : '-- ms',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MiniCard(
                            label: 'Jitter',
                            value: _ping > 0 ? '$_jitter ms' : '-- ms',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.public, size: 16, color: _kMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            connected
                                ? 'Connected server: ${server?.name ?? 'VPN'}'
                                : 'Not connected to VPN. Testing your normal connection.',
                            style: const TextStyle(
                              color: _kMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_phase == _Phase.error) ...[
                      const SizedBox(height: 12),
                      const Text(
                        "Couldn't reach the test server. Check your connection and try again.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFF87171), fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _running ? _stop : _onStartPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _running ? _kCard : _kLime,
                          foregroundColor: _running ? Colors.white : _kBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          ctaLabel,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (_phase == _Phase.done && !premium && timer.isActive) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: _watchAdForTime,
                          icon: const Icon(Icons.play_circle_outline,
                              size: 18, color: Colors.green),
                          label: const Text(
                            'Watch ad to get free time',
                            style: TextStyle(color: Colors.green, fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.green.withValues(alpha: 0.4),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const _AdBanner(),
            const SizedBox(height: 4),
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Text('Mbps', style: TextStyle(color: _kMuted, fontSize: 11)),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _kMuted, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
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

  _GaugePainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height - 15),
      radius: size.width / 2 - 20,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = _kTrack;
    canvas.drawArc(rect, math.pi, math.pi, false, track);
    if (fraction > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect, math.pi, math.pi * fraction, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.fraction != fraction || old.color != color;
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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
