import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n.dart';
import '../services/remote_session.dart';
import 'remote_screen.dart';
import 'remote_screen_desktop.dart';

const _historyKey = 'rc_history';
const _maxHistory = 8;

class _HistoryEntry {
  final String serverURL;
  final String deviceID;
  final String password;
  final int ts;

  const _HistoryEntry({
    required this.serverURL,
    required this.deviceID,
    required this.password,
    required this.ts,
  });

  factory _HistoryEntry.fromJson(Map<String, dynamic> j) => _HistoryEntry(
        serverURL: j['serverURL'] as String,
        deviceID: j['deviceID'] as String,
        password: j['password'] as String,
        ts: j['ts'] as int,
      );

  Map<String, dynamic> toJson() => {
        'serverURL': serverURL,
        'deviceID': deviceID,
        'password': password,
        'ts': ts,
      };
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _serverCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();

  final _session = RemoteSession();
  List<_HistoryEntry> _history = [];

  // Track last attempted connection for saving on success
  String _lastServer = '';
  String _lastDevice = '';
  String _lastPass = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _session.addListener(_onSessionChanged);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverCtrl.text = prefs.getString('server') ?? '';
      _deviceCtrl.text = prefs.getString('device') ?? '';
    });
    await _loadHistory(prefs);
  }

  Future<void> _loadHistory([SharedPreferences? p]) async {
    final prefs = p ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey) ?? '[]';
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => _HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() => _history = list);
    } catch (_) {}
  }

  Future<void> _saveToHistory(String serverURL, String deviceID, String password) async {
    final entry = _HistoryEntry(
      serverURL: serverURL,
      deviceID: deviceID,
      password: password,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    final filtered = _history
        .where((h) => !(h.deviceID == deviceID && h.serverURL == serverURL))
        .toList();
    final updated = [entry, ...filtered].take(_maxHistory).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(updated.map((e) => e.toJson()).toList()));
    setState(() => _history = updated);
  }

  Future<void> _removeHistory(String deviceID, String serverURL) async {
    final updated = _history
        .where((h) => !(h.deviceID == deviceID && h.serverURL == serverURL))
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(updated.map((e) => e.toJson()).toList()));
    setState(() => _history = updated);
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server', _serverCtrl.text.trim());
    await prefs.setString('device', _deviceCtrl.text.trim());
  }

  void _fillFromHistory(_HistoryEntry entry) {
    setState(() {
      _serverCtrl.text = entry.serverURL;
      _deviceCtrl.text = entry.deviceID;
      _passCtrl.text = entry.password;
    });
    FocusScope.of(context).requestFocus(_passFocus);
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    if (_session.state == SessionState.connected) {
      _saveToHistory(_lastServer, _lastDevice, _lastPass);
      final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => isDesktop
              ? RemoteScreenDesktop(
                  session: _session,
                  deviceName: _lastDevice,
                  remotePlatform: _session.remotePlatform,
                )
              : RemoteScreen(
                  session: _session,
                  deviceName: _lastDevice,
                  remotePlatform: _session.remotePlatform,
                ),
        ),
      );
    }
  }

  Future<void> _connect() async {
    final server = _serverCtrl.text.trim();
    final device = _deviceCtrl.text.trim();
    final pass = _passCtrl.text;
    if (server.isEmpty || device.isEmpty) return;
    _lastServer = server;
    _lastDevice = device;
    _lastPass = pass;
    await _savePrefs();
    await _session.connect(
      serverURL: server,
      deviceID: device,
      password: pass,
    );
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    _serverCtrl.dispose();
    _deviceCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnecting = _session.state == SessionState.connecting;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          // ── Background gradient ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF070A0F), Color(0xFF0D1117)],
              ),
            ),
          ),
          // ── Glow orbs ──
          const Positioned(
            top: -80,
            right: -60,
            child: _GlowOrb(color: Color(0xFFFF5033), size: 320, opacity: 0.10),
          ),
          const Positioned(
            bottom: -100,
            left: -80,
            child: _GlowOrb(color: Color(0xFF1EE0A3), size: 360, opacity: 0.07),
          ),
          // ── Content ──
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Logo / Header ──
                      const SizedBox(height: 16),
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C2740),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFF5033).withValues(alpha: 0.28),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF5033).withValues(alpha: 0.18),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.desktop_windows_outlined,
                            size: 36,
                            color: Color(0xFFFF5033),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'RemoteCtl',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(context).connectSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.54),
                          fontSize: 14,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Recent connections ──
                      if (_history.isNotEmpty) ...[
                        _buildHistorySection(),
                        const SizedBox(height: 16),
                      ],

                      // ── Form card ──
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.10),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _labeledField(
                                  context: context,
                                  label: AppLocalizations.of(context).serverAddress,
                                  controller: _serverCtrl,
                                  hint: 'https://192.168.1.100:8443',
                                  icon: Icons.cloud_outlined,
                                  keyboardType: TextInputType.url,
                                ),
                                const SizedBox(height: 16),
                                _labeledField(
                                  context: context,
                                  label: AppLocalizations.of(context).deviceId,
                                  controller: _deviceCtrl,
                                  hint: AppLocalizations.of(context).deviceIdHint,
                                  icon: Icons.computer_outlined,
                                ),
                                const SizedBox(height: 16),
                                _labeledField(
                                  context: context,
                                  label: AppLocalizations.of(context).sessionPassword,
                                  controller: _passCtrl,
                                  hint: AppLocalizations.of(context).sessionPasswordHint,
                                  icon: Icons.lock_outline,
                                  obscure: true,
                                  focusNode: _passFocus,
                                ),
                                const SizedBox(height: 20),
                                _GradientButton(
                                  label: isConnecting
                                      ? AppLocalizations.of(context).connecting
                                      : AppLocalizations.of(context).connect,
                                  icon: Icons.arrow_forward_rounded,
                                  onPressed: isConnecting ? null : _connect,
                                  isLoading: isConnecting,
                                  colors: const [Color(0xFFFF5033), Color(0xFFE03B22)],
                                ),
                                if (_session.state == SessionState.error) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.red.withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline,
                                            color: Colors.redAccent, size: 18),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            AppLocalizations.of(context).sessionError(_session.error),
                                            style: const TextStyle(
                                              color: Colors.redAccent,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).recentConnections,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              ..._history.map((entry) => _HistoryRow(
                    entry: entry,
                    onTap: () => _fillFromHistory(entry),
                    onRemove: () => _removeHistory(entry.deviceID, entry.serverURL),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── History row ────────────────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  final _HistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _HistoryRow({
    required this.entry,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final serverDisplay = entry.serverURL.replaceFirst(RegExp(r'^https?://'), '');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5033).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.computer_outlined,
                  color: Color(0xFFFF5033),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.deviceID,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      serverDisplay,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final l = AppLocalizations.of(context);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l.deleteRecordTitle),
                      content: Text(l.deleteRecordContent),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l.delete),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) onRemove();
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

Widget _labeledField({
  required BuildContext context,
  required String label,
  required TextEditingController controller,
  required String hint,
  required IconData icon,
  bool obscure = false,
  bool enabled = true,
  TextInputType? keyboardType,
  FocusNode? focusNode,
}) {
  final primary = Theme.of(context).colorScheme.primary;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.60),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        enabled: enabled,
        keyboardType: keyboardType,
        autocorrect: false,
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.38),
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(
            icon,
            color: Colors.white.withValues(alpha: enabled ? 0.54 : 0.28),
            size: 20,
          ),
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.24),
            fontSize: 14,
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            borderRadius: BorderRadius.circular(10),
          ),
          disabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(10),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: primary, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: enabled ? 0.06 : 0.02),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          isDense: true,
        ),
      ),
    ],
  );
}

// ── Gradient button ────────────────────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final List<Color> colors;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.colors,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      height: 52,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: disabled
                ? colors.map((c) => c.withValues(alpha: 0.4)).toList()
                : colors,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: colors.first.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Glow orb ───────────────────────────────────────────────────────────────────

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const _GlowOrb({
    required this.color,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
