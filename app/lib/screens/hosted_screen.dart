import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/agent_service.dart';

class HostedScreen extends StatefulWidget {
  final AgentService agentService;
  const HostedScreen({super.key, required this.agentService});

  @override
  State<HostedScreen> createState() => _HostedScreenState();
}

class _HostedScreenState extends State<HostedScreen> {
  late final TextEditingController _serverCtrl;
  late final TextEditingController _idCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _fpsCtrl;
  late final TextEditingController _bitrateCtrl;
  late final TextEditingController _caCertCtrl;
  double _scale = 0.75;
  bool _insecure = false;
  bool _showAdvanced = false;

  final _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final cfg = widget.agentService.config;
    _serverCtrl = TextEditingController(text: cfg.server);
    _idCtrl = TextEditingController(text: cfg.id);
    _tokenCtrl = TextEditingController(text: cfg.token);
    _nameCtrl = TextEditingController(text: cfg.name);
    _fpsCtrl = TextEditingController(text: cfg.fps.toString());
    _bitrateCtrl =
        TextEditingController(text: (cfg.bitrate ~/ 1000).toString());
    _caCertCtrl = TextEditingController(text: cfg.caCert);
    _scale = cfg.scale;
    _insecure = cfg.insecure;

    widget.agentService.addListener(_onAgentChanged);
    widget.agentService.loadConfig().then((_) {
      if (!mounted) return;
      _syncFromConfig();
    });
  }

  void _syncFromConfig() {
    final cfg = widget.agentService.config;
    setState(() {
      _serverCtrl.text = cfg.server;
      // Auto-fill device ID from hostname if not set
      _idCtrl.text = cfg.id.isNotEmpty ? cfg.id : _defaultDeviceId();
      _tokenCtrl.text = cfg.token;
      _nameCtrl.text = cfg.name;
      _fpsCtrl.text = cfg.fps.toString();
      _bitrateCtrl.text = (cfg.bitrate ~/ 1000).toString();
      _caCertCtrl.text = cfg.caCert;
      _scale = cfg.scale;
      _insecure = cfg.insecure;
    });
  }

  String _defaultDeviceId() {
    try {
      return Platform.localHostname.toLowerCase().replaceAll(' ', '-');
    } catch (_) {
      return '';
    }
  }

  void _onAgentChanged() {
    if (!mounted) return;
    setState(() {});
    // Auto-scroll log to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients &&
          _logScroll.position.maxScrollExtent > 0) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    widget.agentService.removeListener(_onAgentChanged);
    _serverCtrl.dispose();
    _idCtrl.dispose();
    _tokenCtrl.dispose();
    _nameCtrl.dispose();
    _fpsCtrl.dispose();
    _bitrateCtrl.dispose();
    _caCertCtrl.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  AgentConfig _buildConfig() => AgentConfig(
        server: _serverCtrl.text.trim(),
        id: _idCtrl.text.trim(),
        token: _tokenCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        fps: int.tryParse(_fpsCtrl.text) ?? 30,
        bitrate: (int.tryParse(_bitrateCtrl.text) ?? 6000) * 1000,
        scale: _scale,
        insecure: _insecure,
        caCert: _caCertCtrl.text.trim(),
      );

  Future<void> _startStop() async {
    if (widget.agentService.isRunning) {
      await widget.agentService.stop();
    } else {
      await widget.agentService.saveConfig(_buildConfig());
      await widget.agentService.start();
    }
  }

  Future<void> _pickCaCert() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['crt', 'pem', 'cer'],
      dialogTitle: '选择 CA 证书文件',
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _caCertCtrl.text = result.files.single.path!);
    }
  }

  void _copyDeviceId() {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) return;
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('设备 ID 已复制'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)) {
      return _buildUnsupported(context);
    }
    return _buildContent(context);
  }

  // ── unsupported ──────────────────────────────────────────────────────────────

  Widget _buildUnsupported(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.desktop_access_disabled_outlined,
                  size: 64, color: Colors.white24),
              const SizedBox(height: 16),
              const Text('共享本机仅支持桌面平台',
                  style: TextStyle(color: Colors.white54, fontSize: 18)),
              const SizedBox(height: 8),
              const Text('macOS · Windows · Linux',
                  style: TextStyle(color: Colors.white38, fontSize: 14)),
              const SizedBox(height: 24),
              Text(
                '当前平台: ${Platform.operatingSystem}',
                style: const TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── main content ─────────────────────────────────────────────────────────────

  Widget _buildContent(BuildContext context) {
    final svc = widget.agentService;
    final running = svc.isRunning;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Config + controls (scrollable) ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Device ID card (prominent, Sunflower-style) ──
                        _DeviceIdCard(
                          idController: _idCtrl,
                          status: svc.status,
                          error: svc.error,
                          onCopy: _copyDeviceId,
                          enabled: !running,
                        ),
                        const SizedBox(height: 20),

                        // ── Server + token ──
                        _Field(
                          controller: _serverCtrl,
                          label: '服务器地址',
                          hint: 'https://192.168.1.100:8443',
                          icon: Icons.cloud_outlined,
                          enabled: !running,
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: _tokenCtrl,
                          label: '设备密钥',
                          hint: '用于验证身份的密钥（可选）',
                          icon: Icons.vpn_key_outlined,
                          obscure: true,
                          enabled: !running,
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: _nameCtrl,
                          label: '显示名称',
                          hint: '（默认同设备 ID）',
                          icon: Icons.badge_outlined,
                          enabled: !running,
                        ),
                        const SizedBox(height: 4),

                        // Advanced toggle
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _showAdvanced = !_showAdvanced),
                          icon: Icon(
                            _showAdvanced
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                          ),
                          label: Text(_showAdvanced ? '收起高级设置' : '高级设置'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white38,
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.zero,
                          ),
                        ),

                        if (_showAdvanced) ...[
                          Row(children: [
                            Expanded(
                              child: _Field(
                                controller: _fpsCtrl,
                                label: 'FPS',
                                hint: '30',
                                icon: Icons.speed_outlined,
                                keyboardType: TextInputType.number,
                                enabled: !running,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Field(
                                controller: _bitrateCtrl,
                                label: '码率 (kbps)',
                                hint: '6000',
                                icon: Icons.settings_input_antenna,
                                keyboardType: TextInputType.number,
                                enabled: !running,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '分辨率缩放: ${(_scale * 100).round()}%',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 13),
                              ),
                              Slider(
                                value: _scale,
                                min: 0.25,
                                max: 1.0,
                                divisions: 3,
                                label: '${(_scale * 100).round()}%',
                                onChanged: running
                                    ? null
                                    : (v) => setState(() => _scale = v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _Field(
                                  controller: _caCertCtrl,
                                  label: 'CA 证书路径',
                                  hint: '/path/to/server.crt（可选）',
                                  icon: Icons.verified_outlined,
                                  enabled: !running,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 56,
                                child: OutlinedButton(
                                  onPressed: running ? null : _pickCaCert,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white54,
                                    side: BorderSide(
                                        color: Colors.white.withOpacity(
                                            running ? 0.07 : 0.15)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                  ),
                                  child: const Text('浏览'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Switch(
                              value: _insecure,
                              onChanged: running
                                  ? null
                                  : (v) => setState(() => _insecure = v),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '跳过证书验证（不安全）',
                              style: TextStyle(
                                  color: running
                                      ? Colors.white24
                                      : Colors.white70),
                            ),
                          ]),
                          const SizedBox(height: 8),
                        ],

                        const SizedBox(height: 20),

                        // Start / Stop
                        SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _startStop,
                            icon: running
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Icon(Icons.play_circle_outlined),
                            label: Text(
                              running ? '停止共享' : '开始共享',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: running
                                  ? Colors.red.shade700
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Log panel ──
            if (svc.logs.isNotEmpty)
              Container(
                height: 180,
                decoration: const BoxDecoration(
                  color: Color(0xFF070C1A),
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
                      child: Row(children: [
                        const Text('日志',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 11)),
                        const Spacer(),
                        TextButton(
                          onPressed: svc.clearLogs,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white24,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                          ),
                          child: const Text('清空',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _logScroll,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        itemCount: svc.logs.length,
                        itemBuilder: (_, i) => Text(
                          svc.logs[i],
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Device ID card ─────────────────────────────────────────────────────────────
// Sunflower-style: shows the device ID prominently with status and copy button.

class _DeviceIdCard extends StatelessWidget {
  final TextEditingController idController;
  final AgentStatus status;
  final String error;
  final VoidCallback onCopy;
  final bool enabled;

  const _DeviceIdCard({
    required this.idController,
    required this.status,
    required this.error,
    required this.onCopy,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final (statusIcon, statusLabel, statusColor) = switch (status) {
      AgentStatus.stopped  => (Icons.circle_outlined,  '未共享', Colors.white38),
      AgentStatus.starting => (Icons.pending_outlined,  '启动中…', Colors.orange),
      AgentStatus.running  => (Icons.circle,            '共享中', Colors.greenAccent),
      AgentStatus.error    => (Icons.error_outline,     '错误', Colors.redAccent),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E3A8A).withOpacity(0.6),
            const Color(0xFF1E40AF).withOpacity(0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(children: [
            Icon(statusIcon, size: 14, color: statusColor),
            const SizedBox(width: 6),
            Text(
              statusLabel,
              style: TextStyle(
                  color: statusColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
            if (status == AgentStatus.error && error.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ]),
          const SizedBox(height: 14),

          // Label
          const Text(
            '本机设备 ID',
            style: TextStyle(
                color: Colors.white54, fontSize: 12, letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),

          // ID + copy button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: idController,
                  enabled: enabled,
                  autocorrect: false,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: '设备标识',
                    hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.2),
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                onPressed: onCopy,
                tooltip: '复制设备 ID',
                icon: const Icon(Icons.copy_outlined, size: 20),
                color: Colors.white54,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '控制端输入此 ID 即可连接到本机',
            style: TextStyle(color: Colors.white30, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Shared text field ─────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final bool enabled;
  final TextInputType? keyboardType;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      keyboardType: keyboardType,
      autocorrect: false,
      style: TextStyle(color: enabled ? Colors.white : Colors.white38),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.white54),
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        enabledBorder: OutlineInputBorder(
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.15)),
          borderRadius: BorderRadius.circular(8),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.07)),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary),
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Colors.white
            .withOpacity(enabled ? 0.06 : 0.02),
      ),
    );
  }
}
