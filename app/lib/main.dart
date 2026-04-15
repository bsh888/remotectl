import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'l10n.dart';
import 'screens/connect_screen.dart';
import 'screens/hosted_screen.dart';
import 'services/agent_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSavedLocale();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const RemoteCtlApp());
}

class RemoteCtlApp extends StatelessWidget {
  const RemoteCtlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) => MaterialApp(
        title: 'RemoteCtl',
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: localizationsDelegates,
        supportedLocales: supportedLocales,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFF5033),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          navigationBarTheme: NavigationBarThemeData(
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                );
              }
              return TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              );
            }),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;
  final _agentService = AgentService();
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
  }

  Future<AppExitResponse> _onExitRequested() async {
    if (!_agentService.isRunning) return AppExitResponse.exit;
    if (!mounted) {
      await _agentService.stop();
      return AppExitResponse.exit;
    }

    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l.exitConfirmTitle),
        content: Text(l.exitConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.exitCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.exitConfirm),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _agentService.stop();
      return AppExitResponse.exit;
    }
    return AppExitResponse.cancel;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _agentService.stop();
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _agentService.dispose();
    super.dispose();
  }

  void _showLangPicker() {
    final current = localeNotifier.value;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final items = [
          (const Locale('zh'), '简体中文'),
          (const Locale('en'), 'English'),
          (const Locale('zh', 'TW'), '繁體中文'),
        ];
        return SimpleDialog(
          title: const Text('Language / 语言'),
          children: items.map((item) {
            final selected = item.$1 == current;
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                saveLocale(item.$1);
                _agentService.syncWindowLocale();
              },
              child: Row(
                children: [
                  Text(item.$2),
                  if (selected) ...[
                    const Spacer(),
                    const Icon(Icons.check, size: 18),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const ConnectScreen(),
          HostedScreen(agentService: _agentService),
        ],
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            backgroundColor: const Color(0xFF070A0F).withValues(alpha: 0.92),
            indicatorColor: const Color(0xFFFF5033).withValues(alpha: 0.18),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            height: 64,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.monitor_outlined),
                selectedIcon: const Icon(Icons.monitor),
                label: l.navRemote,
              ),
              NavigationDestination(
                icon: const Icon(Icons.screen_share_outlined),
                selectedIcon: const Icon(Icons.screen_share),
                label: l.navHosted,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: _showLangPicker,
        backgroundColor: const Color(0xFF131B26),
        foregroundColor: Colors.white60,
        elevation: 2,
        tooltip: 'Language',
        child: const Icon(Icons.language, size: 20),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
    );
  }
}
