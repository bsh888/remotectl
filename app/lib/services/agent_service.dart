import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AgentConfig {
  String server;
  String id;
  String token;
  String name;
  int fps;
  int bitrate; // bits/sec
  double scale;
  bool insecure;
  String caCert; // path to custom CA certificate (.crt)

  AgentConfig({
    this.server = 'http://localhost:8080',
    this.id = '',
    this.token = '',
    this.name = '',
    this.fps = 30,
    this.bitrate = 6000000,
    this.scale = 0.75,
    this.insecure = false,
    this.caCert = '',
  });

  factory AgentConfig.fromJson(Map<String, dynamic> j) => AgentConfig(
        server: (j['server'] as String?) ?? 'http://localhost:8080',
        id: (j['id'] as String?) ?? '',
        token: (j['token'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        fps: (j['fps'] as int?) ?? 30,
        bitrate: (j['bitrate'] as int?) ?? 6000000,
        scale: ((j['scale'] as num?) ?? 0.75).toDouble(),
        insecure: (j['insecure'] as bool?) ?? false,
        caCert: (j['ca_cert'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'server': server,
        'id': id,
        'token': token,
        'name': name,
        'fps': fps,
        'bitrate': bitrate,
        'scale': scale,
        'insecure': insecure,
        'ca_cert': caCert,
      };
}

enum AgentStatus { stopped, starting, running, error }

class AgentService extends ChangeNotifier {
  AgentStatus _status = AgentStatus.stopped;
  String _error = '';
  final List<String> _logs = [];
  Process? _process;
  AgentConfig _config = AgentConfig();
  String _sessionPwd = '';

  AgentStatus get status => _status;
  String get error => _error;
  List<String> get logs => List.unmodifiable(_logs);
  AgentConfig get config => _config;
  String get sessionPassword => _sessionPwd;
  bool get isRunning =>
      _status == AgentStatus.running || _status == AgentStatus.starting;

  /// Whether the agent subprocess can run on the current platform.
  static bool get isSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  // ── config ───────────────────────────────────────────────────────────────────

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('agent_config');
    if (raw != null) {
      try {
        _config = AgentConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    // Auto-generate a persistent 9-digit device ID on first use.
    if (_config.id.isEmpty) {
      _config.id = _generateDeviceId();
      await prefs.setString('agent_config', jsonEncode(_config.toJson()));
    }
    notifyListeners();
  }

  static String _generateDeviceId() {
    final r = Random.secure();
    return (100000000 + r.nextInt(900000000)).toString();
  }

  Future<void> saveConfig(AgentConfig cfg) async {
    _config = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('agent_config', jsonEncode(cfg.toJson()));
    notifyListeners();
  }

  // ── lifecycle ────────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (isRunning) return;
    _status = AgentStatus.starting;
    _error = '';
    _logs.clear();
    _sessionPwd = '';
    notifyListeners();

    try {
      final binary = _agentBinaryPath();
      final args = _buildArgs();
      _appendLog('▶ $binary ${args.join(' ')}');

      _process = await Process.start(binary, args);
      _status = AgentStatus.running;
      notifyListeners();

      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_appendLog);
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_appendLog);

      _process!.exitCode.then((code) {
        if (_status != AgentStatus.stopped) {
          _status = code == 0 ? AgentStatus.stopped : AgentStatus.error;
          _error = code == 0 ? '' : 'Agent 退出 (exit $code)';
          _process = null;
          notifyListeners();
        }
      });
    } catch (e) {
      _status = AgentStatus.error;
      _error = '启动失败: $e';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final prev = _status;
    _status = AgentStatus.stopped;
    _error = '';
    _sessionPwd = '';
    // On Windows, SIGTERM maps to a console event that may not reliably
    // terminate the subprocess; use SIGKILL (TerminateProcess) instead.
    final sig =
        Platform.isWindows ? ProcessSignal.sigkill : ProcessSignal.sigterm;
    _process?.kill(sig);
    _process = null;
    if (prev != AgentStatus.stopped) notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  void _appendLog(String line) {
    if (line.isEmpty) return;
    // Machine-readable markers emitted by agent — parse silently, don't log
    if (line.startsWith('SESSION_PWD:')) {
      _sessionPwd = line.substring('SESSION_PWD:'.length).trim();
      notifyListeners();
      return;
    }
    if (line.startsWith('AUTH_FAILED:')) {
      _status = AgentStatus.error;
      _error = line.substring('AUTH_FAILED:'.length).trim();
      _sessionPwd = '';
      notifyListeners();
      return;
    }
    _logs.add(line);
    if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);
    notifyListeners();
  }

  // ── helpers ──────────────────────────────────────────────────────────────────

  /// Locate the agent binary:
  /// 1. Next to the Flutter executable (production bundle).
  /// 2. In <project>/bin/ (dev: run `make agent-<platform>` first).
  static String _agentBinaryPath() {
    final exe = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final winExt = Platform.isWindows ? '.exe' : '';
    final prod = '$exe${sep}remotectl-agent$winExt';
    if (File(prod).existsSync()) return prod;

    // Dev fallback: look in project bin/
    final devName = Platform.isWindows
        ? 'remotectl-agent-windows-amd64.exe'
        : Platform.isMacOS
            ? 'remotectl-agent-mac'
            : 'remotectl-agent-linux-amd64';
    final cwd = Directory.current.path;
    final dev = '$cwd${sep}bin$sep$devName';
    if (File(dev).existsSync()) return dev;

    return prod; // will fail with a clear "file not found" message
  }

  List<String> _buildArgs() => [
        '--server', _config.server,
        '--id', _config.id.trim(),
        if (_config.token.isNotEmpty) ...['--token', _config.token],
        if (_config.name.isNotEmpty) ...['--name', _config.name],
        '--fps', _config.fps.toString(),
        '--bitrate', _config.bitrate.toString(),
        '--scale', _config.scale.toStringAsFixed(2),
        if (_config.insecure) '--insecure',
        if (_config.caCert.isNotEmpty) ...['--ca-cert', _config.caCert],
      ];

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
