import 'dart:io';
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
              : RemoteScreen(session: _session, deviceName: deviceInfo.name, remotePlatform: deviceInfo.platform),
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

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo / title
                  const SizedBox(height: 16),
                  Icon(
                    Icons.desktop_windows_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'RemoteCtl',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '远程桌面控制',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white54,
                        ),
                  ),
                  const SizedBox(height: 40),

                  // Form
                  _field(
                    controller: _serverCtrl,
                    label: '服务器地址',
                    hint: 'https://192.168.1.100:8443',
                    icon: Icons.cloud_outlined,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),

                  // Device row with refresh
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: _deviceCtrl,
                          label: '设备 ID',
                          hint: 'my-mac',
                          icon: Icons.computer_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _loadingDevices
                          ? const SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          : IconButton(
                              onPressed: _loadDevices,
                              tooltip: '获取设备列表',
                              icon: const Icon(Icons.refresh),
                              color: Colors.white54,
                            ),
                    ],
                  ),

                  // Device list
                  if (_session.devices.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _DeviceList(
                      devices: _session.devices,
                      selected: _deviceCtrl.text,
                      onTap: (id) => setState(() => _deviceCtrl.text = id),
                    ),
                  ],

                  const SizedBox(height: 16),
                  _field(
                    controller: _passCtrl,
                    label: '服务器密码',
                    hint: '信令服务器访问密码（可选）',
                    icon: Icons.lock_outline,
                    obscure: true,
                  ),
                  const SizedBox(height: 12),

                  // Self-signed cert toggle
                  Row(
                    children: [
                      Switch(
                        value: _selfSigned,
                        onChanged: (v) => setState(() => _selfSigned = v),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '允许自签名证书',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Connect button
                  FilledButton.icon(
                    onPressed: isConnecting ? null : _connect,
                    icon: isConnecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(isConnecting ? '连接中…' : '连接'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),

                  // Error
                  if (_session.state == SessionState.error) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade700),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _session.error,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autocorrect: false,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.white54),
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
      ),
    );
  }
}

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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: devices.map((d) {
          final isSelected = d.id == selected;
          return InkWell(
            onTap: () => onTap(d.id),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _platformIcon(d.platform),
                    size: 20,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white54,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name.isNotEmpty ? d.name : d.id,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        if (d.id != d.name)
                          Text(
                            d.id,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (d.viewerCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${d.viewerCount} viewer',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.greenAccent),
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
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
        return Icons.devices;
    }
  }
}
