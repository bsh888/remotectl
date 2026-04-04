import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  double _scale = 0.5;
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
      _idCtrl.text = cfg.id;
      _tokenCtrl.text = cfg.token;
      _nameCtrl.text = cfg.name;
      _fpsCtrl.text = cfg.fps.toString();
      _bitrateCtrl.text = (cfg.bitrate ~/ 1000).toString();
      _scale = cfg.scale;
      _insecure = cfg.insecure;
    });
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
    _logScroll.dispose();
    super.dispose();
  }

  AgentConfig _buildConfig() => AgentConfig(
        server: _serverCtrl.text.trim(),
        id: _idCtrl.text.trim(),
        token: _tokenCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        fps: int.tryParse(_fpsCtrl.text) ?? 30,
        bitrate: (int.tryParse(_bitrateCtrl.text) ?? 3000) * 1000,
        scale: _scale,
        insecure: _insecure,
      );

  Future<void> _startStop() async {
    if (widget.agentService.isRunning) {
      await widget.agentService.stop();
    } else {
      await widget.agentService.saveConfig(_buildConfig());
      await widget.agentService.start();
    }
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
              const Text('被控模式仅支持桌面平台',
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

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Config + controls (scrollable) ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Status card
                        _StatusCard(status: svc.status, error: svc.error),
                        const SizedBox(height: 20),

                        // Form fields
                        _Field(
                          controller: _serverCtrl,
                          label: '服务器地址',
                          hint: 'https://192.168.1.100:8443',
                          icon: Icons.cloud_outlined,
                          enabled: !running,
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: _idCtrl,
                          label: '设备 ID',
                          hint: 'my-mac',
                          icon: Icons.computer_outlined,
                          enabled: !running,
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: _tokenCtrl,
                          label: '连接密码',
                          hint: '（可选）',
                          icon: Icons.lock_outline,
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
                          label:
                              Text(_showAdvanced ? '收起高级设置' : '高级设置'),
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
                                hint: '3000',
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
                          Row(children: [
                            Switch(
                              value: _insecure,
                              onChanged: running
                                  ? null
                                  : (v) => setState(() => _insecure = v),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '允许自签名证书',
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
                        FilledButton.icon(
                          onPressed: _startStop,
                          icon: running
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(running ? '停止被控' : '启动被控'),
                          style: FilledButton.styleFrom(
                            backgroundColor: running
                                ? Colors.red.shade700
                                : Theme.of(context).colorScheme.primary,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(fontSize: 16),
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
                    // Log header
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
                    // Log lines
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

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final AgentStatus status;
  final String error;
  const _StatusCard({required this.status, required this.error});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      AgentStatus.stopped  => (Icons.circle_outlined, '未运行', Colors.white38),
      AgentStatus.starting => (Icons.pending_outlined, '启动中…', Colors.orange),
      AgentStatus.running  => (Icons.circle, '运行中', Colors.green),
      AgentStatus.error    => (Icons.error_outline, '错误', Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('被控状态: $label',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w600)),
              if (status == AgentStatus.error && error.isNotEmpty)
                Text(error,
                    style: const TextStyle(
                        color: Colors.red, fontSize: 12)),
            ],
          ),
        ),
      ]),
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
