import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/remote_session.dart';
import 'remote_screen.dart';
import 'remote_screen_desktop.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _serverCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _selfSigned = false;
  bool _loadingDevices = false;

  final _session = RemoteSession();

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
      _selfSigned = prefs.getBool('selfSigned') ?? false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server', _serverCtrl.text.trim());
    await prefs.setString('device', _deviceCtrl.text.trim());
    await prefs.setBool('selfSigned', _selfSigned);
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    if (_session.state == SessionState.connected) {
      final isDesktop =
          Platform.isMacOS || Platform.isWindows || Platform.isLinux;
      final deviceID = _deviceCtrl.text.trim();
      final deviceInfo = _session.devices.firstWhere(
        (d) => d.id == deviceID,
        orElse: () => DeviceInfo(
            id: deviceID, name: deviceID, platform: '', viewerCount: 0),
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => isDesktop
              ? RemoteScreenDesktop(
                  session: _session,
                  deviceName: deviceInfo.name,
                  remotePlatform: deviceInfo.platform,
                )
              : RemoteScreen(
                  session: _session,
                  deviceName: deviceInfo.name,
                  remotePlatform: deviceInfo.platform,
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
    await _savePrefs();
    await _session.connect(
      serverURL: server,
      deviceID: device,
      password: pass,
      allowSelfSigned: _selfSigned,
    );
  }

  Future<void> _loadDevices() async {
    final server = _serverCtrl.text.trim();
    if (server.isEmpty) return;
    setState(() => _loadingDevices = true);
    await _session.fetchDevices(server, allowSelfSigned: _selfSigned);
    setState(() => _loadingDevices = false);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    _serverCtrl.dispose();
    _deviceCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnecting = _session.state == SessionState.connecting;
    final primary = Theme.of(context).colorScheme.primary;

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
                colors: [Color(0xFF07091A), Color(0xFF0D1526)],
              ),
            ),
          ),
          // ── Glow orbs ──
          const Positioned(
            top: -80,
            right: -60,
            child: _GlowOrb(
              color: Color(0xFF2563EB),
              size: 320,
              opacity: 0.18,
            ),
          ),
          const Positioned(
            bottom: -100,
            left: -80,
            child: _GlowOrb(
              color: Color(0xFF7C3AED),
              size: 360,
              opacity: 0.15,
            ),
          ),
          // ── Content ──
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Logo / Header (outside card) ──
                      const SizedBox(height: 16),
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF2563EB).withValues(alpha: 0.9),
                                const Color(0xFF7C3AED).withValues(alpha: 0.9),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.desktop_windows_outlined,
                            size: 36,
                            color: Colors.white,
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
                        '远程桌面控制',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.54),
                          fontSize: 14,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 32),

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
                                // Server URL
                                _labeledField(
                                  context: context,
                                  label: '服务器地址',
                                  controller: _serverCtrl,
                                  hint: 'https://192.168.1.100:8443',
                                  icon: Icons.cloud_outlined,
                                  keyboardType: TextInputType.url,
                                ),
                                const SizedBox(height: 16),

                                // Device row with refresh
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: _labeledField(
                                        context: context,
                                        label: '设备 ID',
                                        controller: _deviceCtrl,
                                        hint: 'my-mac',
                                        icon: Icons.computer_outlined,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: _loadingDevices
                                          ? Center(
                                              child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: primary,
                                                ),
                                              ),
                                            )
                                          : Tooltip(
                                              message: '获取设备列表',
                                              child: Material(
                                                color: Colors.white.withValues(alpha: 0.06),
                                                borderRadius: BorderRadius.circular(10),
                                                child: InkWell(
                                                  onTap: _loadDevices,
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: Icon(
                                                    Icons.refresh_rounded,
                                                    color: Colors.white.withValues(alpha: 0.54),
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ],
                                ),

                                // Device list
                                if (_session.devices.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _DeviceList(
                                    devices: _session.devices,
                                    selected: _deviceCtrl.text,
                                    onTap: (id) =>
                                        setState(() => _deviceCtrl.text = id),
                                  ),
                                ],

                                const SizedBox(height: 16),

                                // Password
                                _labeledField(
                                  context: context,
                                  label: '服务器密码',
                                  controller: _passCtrl,
                                  hint: '信令服务器访问密码（可选）',
                                  icon: Icons.lock_outline,
                                  obscure: true,
                                ),
                                const SizedBox(height: 14),

                                // Self-signed cert toggle
                                Row(
                                  children: [
                                    SizedBox(
                                      height: 28,
                                      child: Switch(
                                        value: _selfSigned,
                                        onChanged: (v) =>
                                            setState(() => _selfSigned = v),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '允许自签名证书',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.60),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Connect button
                                _GradientButton(
                                  label: isConnecting ? '连接中…' : '连接',
                                  icon: Icons.play_arrow_rounded,
                                  onPressed: isConnecting ? null : _connect,
                                  isLoading: isConnecting,
                                  colors: const [
                                    Color(0xFF2563EB),
                                    Color(0xFF4F46E5),
                                  ],
                                ),

                                // Error message
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
                                            _session.error,
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
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.10),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          disabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.06),
            ),
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

// ── Device list ────────────────────────────────────────────────────────────────

class _DeviceList extends StatelessWidget {
  final List<DeviceInfo> devices;
  final String selected;
  final ValueChanged<String> onTap;

  const _DeviceList({
    required this.devices,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: devices.map((d) {
        final isSelected = d.id == selected;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected
                  ? primary.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? primary.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => onTap(d.id),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primary.withValues(alpha: 0.20)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _platformIcon(d.platform),
                          size: 16,
                          color: isSelected
                              ? primary
                              : Colors.white.withValues(alpha: 0.54),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name.isNotEmpty ? d.name : d.id,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.70),
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                            if (d.id != d.name)
                              Text(
                                d.id,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.38),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (d.viewerCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.30),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${d.viewerCount}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  static IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'darwin':
        return Icons.laptop_mac;
      case 'windows':
        return Icons.laptop_windows;
      case 'linux':
        return Icons.computer;
      default:
        return Icons.devices_other_rounded;
    }
  }
}
