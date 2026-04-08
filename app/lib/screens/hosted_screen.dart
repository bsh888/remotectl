import 'dart:io';
import 'dart:ui';
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
  bool _logExpanded = false;

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
    // Auto-scroll log to bottom (only when panel is expanded)
    if (_logExpanded) {
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

  void _copySessionPwd() {
    final pwd = widget.agentService.sessionPassword;
    if (pwd.isEmpty) return;
    Clipboard.setData(ClipboardData(text: pwd));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('会话密码已复制'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)) {
      return _buildUnsupported(context);
    }
    return _buildContent(context);
  }

  // ── unsupported ──────────────────────────────────────────────────────────────

  Widget _buildUnsupported(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF07091A), Color(0xFF0D1526)],
            ),
          ),
        ),
        const Positioned(
          top: -80,
          right: -60,
          child: _GlowOrb(color: Color(0xFF2563EB), size: 300, opacity: 0.15),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.desktop_access_disabled_outlined,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '共享本机仅支持桌面平台',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.54),
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'macOS · Windows · Linux',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.38),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '当前平台: ${Platform.operatingSystem}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.24),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── main content ─────────────────────────────────────────────────────────────

  Widget _buildContent(BuildContext context) {
    final svc = widget.agentService;
    final running = svc.isRunning;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: false,
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
              opacity: 0.16,
            ),
          ),
          const Positioned(
            bottom: 100,
            left: -80,
            child: _GlowOrb(
              color: Color(0xFF7C3AED),
              size: 300,
              opacity: 0.13,
            ),
          ),
          // ── Content ──
          SafeArea(
            child: Column(
              children: [
                // ── Config + controls (scrollable) ──
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Device ID card ──
                            _DeviceIdCard(
                              idController: _idCtrl,
                              status: svc.status,
                              error: svc.error,
                              sessionPwd: svc.sessionPassword,
                              onCopy: _copyDeviceId,
                              onCopyPwd: _copySessionPwd,
                              enabled: !running,
                            ),
                            const SizedBox(height: 20),

                            // ── Connection config glass card ──
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                    sigmaX: 16, sigmaY: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white
                                        .withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white
                                          .withValues(alpha: 0.10),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Section label
                                      Text(
                                        '连接配置',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.60),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      _hostedLabeledField(
                                        context: context,
                                        label: '服务器地址',
                                        controller: _serverCtrl,
                                        hint: 'https://192.168.1.100:8443',
                                        icon: Icons.cloud_outlined,
                                        enabled: !running,
                                        keyboardType: TextInputType.url,
                                      ),
                                      const SizedBox(height: 12),
                                      _hostedLabeledField(
                                        context: context,
                                        label: '设备密钥',
                                        controller: _tokenCtrl,
                                        hint: '用于验证身份的密钥（可选）',
                                        icon: Icons.vpn_key_outlined,
                                        obscure: true,
                                        enabled: !running,
                                      ),
                                      const SizedBox(height: 12),
                                      _hostedLabeledField(
                                        context: context,
                                        label: '显示名称',
                                        controller: _nameCtrl,
                                        hint: '（默认同设备 ID）',
                                        icon: Icons.badge_outlined,
                                        enabled: !running,
                                      ),
                                      const SizedBox(height: 4),

                                      // Advanced toggle
                                      TextButton.icon(
                                        onPressed: () => setState(() =>
                                            _showAdvanced = !_showAdvanced),
                                        icon: Icon(
                                          _showAdvanced
                                              ? Icons.expand_less_rounded
                                              : Icons.expand_more_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          _showAdvanced
                                              ? '收起高级设置'
                                              : '高级设置',
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white
                                              .withValues(alpha: 0.38),
                                          alignment: Alignment.centerLeft,
                                          padding: EdgeInsets.zero,
                                        ),
                                      ),

                                      if (_showAdvanced) ...[
                                        Row(children: [
                                          Expanded(
                                            child: _hostedLabeledField(
                                              context: context,
                                              label: 'FPS',
                                              controller: _fpsCtrl,
                                              hint: '30',
                                              icon: Icons.speed_outlined,
                                              keyboardType:
                                                  TextInputType.number,
                                              enabled: !running,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _hostedLabeledField(
                                              context: context,
                                              label: '码率 (kbps)',
                                              controller: _bitrateCtrl,
                                              hint: '6000',
                                              icon: Icons
                                                  .settings_input_antenna,
                                              keyboardType:
                                                  TextInputType.number,
                                              enabled: !running,
                                            ),
                                          ),
                                        ]),
                                        const SizedBox(height: 12),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '分辨率缩放: ${(_scale * 100).round()}%',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.54),
                                                fontSize: 13,
                                              ),
                                            ),
                                            Slider(
                                              value: _scale,
                                              min: 0.25,
                                              max: 1.0,
                                              divisions: 3,
                                              label:
                                                  '${(_scale * 100).round()}%',
                                              onChanged: running
                                                  ? null
                                                  : (v) => setState(
                                                      () => _scale = v),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              child: _hostedLabeledField(
                                                context: context,
                                                label: 'CA 证书路径',
                                                controller: _caCertCtrl,
                                                hint: '/path/to/server.crt（可选）',
                                                icon: Icons.verified_outlined,
                                                enabled: !running,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            SizedBox(
                                              height: 48,
                                              child: OutlinedButton(
                                                onPressed:
                                                    running ? null : _pickCaCert,
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.white
                                                      .withValues(alpha: 0.54),
                                                  side: BorderSide(
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: running
                                                                ? 0.07
                                                                : 0.15),
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
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
                                                : (v) => setState(
                                                    () => _insecure = v),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '跳过证书验证（不安全）',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                  alpha: running ? 0.24 : 0.70),
                                            ),
                                          ),
                                        ]),
                                        const SizedBox(height: 8),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ── Start / Stop button ──
                            _GradientButton(
                              label: running ? '停止共享' : '开始共享',
                              icon: running
                                  ? Icons.stop_circle_outlined
                                  : Icons.play_circle_outlined,
                              onPressed: _startStop,
                              isLoading: false,
                              colors: running
                                  ? const [
                                      Color(0xFFB91C1C),
                                      Color(0xFF7F1D1D),
                                    ]
                                  : const [
                                      Color(0xFF2563EB),
                                      Color(0xFF7C3AED),
                                    ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Log panel (collapsible) ──
                if (svc.logs.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF060A18).withValues(alpha: 0.95),
                          const Color(0xFF040710).withValues(alpha: 0.98),
                        ],
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header / toggle bar
                        InkWell(
                          onTap: () => setState(
                              () => _logExpanded = !_logExpanded),
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(14, 8, 6, 8),
                            child: Row(children: [
                              Icon(
                                _logExpanded
                                    ? Icons.expand_more_rounded
                                    : Icons.chevron_right_rounded,
                                size: 16,
                                color: Colors.white.withValues(alpha: 0.38),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '日志',
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.50),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: 0.10),
                                  ),
                                ),
                                child: Text(
                                  '${svc.logs.length}',
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.38),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (_logExpanded)
                                TextButton(
                                  onPressed: svc.clearLogs,
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        Colors.white.withValues(alpha: 0.24),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                  ),
                                  child: const Text('清空',
                                      style: TextStyle(fontSize: 11)),
                                ),
                            ]),
                          ),
                        ),
                        // Expandable content
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          height: _logExpanded ? 180 : 0,
                          child: SelectionArea(
                            child: ListView.builder(
                              controller: _logScroll,
                              padding: const EdgeInsets.fromLTRB(
                                  14, 0, 14, 10),
                              itemCount: svc.logs.length,
                              itemBuilder: (_, i) => Text(
                                svc.logs[i],
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.54),
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
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
        ],
      ),
    );
  }
}

// ── Labeled field (hosted screen) ─────────────────────────────────────────────

Widget _hostedLabeledField({
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
          color: enabled
              ? Colors.white
              : Colors.white.withValues(alpha: 0.38),
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
          fillColor:
              Colors.white.withValues(alpha: enabled ? 0.06 : 0.02),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          isDense: true,
        ),
      ),
    ],
  );
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

// ── Device ID card ─────────────────────────────────────────────────────────────

class _DeviceIdCard extends StatelessWidget {
  final TextEditingController idController;
  final AgentStatus status;
  final String error;
  final String sessionPwd;
  final VoidCallback onCopy;
  final VoidCallback onCopyPwd;
  final bool enabled;

  const _DeviceIdCard({
    required this.idController,
    required this.status,
    required this.error,
    required this.sessionPwd,
    required this.onCopy,
    required this.onCopyPwd,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = switch (status) {
      AgentStatus.stopped => ('未共享', Colors.white38),
      AgentStatus.starting => ('启动中…', const Color(0xFFFB923C)),
      AgentStatus.running => ('共享中', const Color(0xFF4ADE80)),
      AgentStatus.error => ('错误', const Color(0xFFF87171)),
    };

    final isRunning = status == AgentStatus.running;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E3A8A).withValues(alpha: 0.60),
            const Color(0xFF1E40AF).withValues(alpha: 0.30),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning
              ? const Color(0xFF4ADE80).withValues(alpha: 0.40)
              : statusColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: isRunning
            ? [
                BoxShadow(
                  color: const Color(0xFF4ADE80).withValues(alpha: 0.12),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(children: [
            // Status dot with glow
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            if (status == AgentStatus.error && error.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  error,
                  style: const TextStyle(
                    color: Color(0xFFF87171),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ]),
          const SizedBox(height: 14),

          // Label
          Text(
            '本机设备 ID',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.54),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
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
                      color: Colors.white.withValues(alpha: 0.20),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: IconButton(
                  onPressed: onCopy,
                  tooltip: '复制设备 ID',
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  color: Colors.white.withValues(alpha: 0.60),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '控制端输入此 ID 即可连接到本机',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.30),
              fontSize: 11,
            ),
          ),

          // ── Session password (shown only when agent is running) ──
          if (sessionPwd.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
            const SizedBox(height: 14),
            Text(
              '会话密码',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.54),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    sessionPwd,
                    style: const TextStyle(
                      color: Color(0xFF4ADE80),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: IconButton(
                    onPressed: onCopyPwd,
                    tooltip: '复制会话密码',
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    color: Colors.white.withValues(alpha: 0.60),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '每次启动随机生成，控制端连接时输入此密码',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.30),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
