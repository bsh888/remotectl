import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'l10n.dart';
import 'screens/connect_screen.dart';
import 'screens/hosted_screen.dart';
import 'services/agent_service.dart';

// MethodChannel shared with MainFlutterWindow.swift on macOS.
const _windowChannel = MethodChannel('remotectl/window');

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
  // Set to true after the user confirms quit via the macOS ✕ dialog, so that
  // the subsequent onExitRequested (triggered by applicationShouldTerminate)
  // doesn't show a second confirmation dialog.
  bool _quitConfirmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
    // macOS: MainFlutterWindow.performClose sends "windowCloseRequested"
    // instead of closing immediately. We show the dialog here (where we have
    // full context + localization), then call back "confirmClose" to let Swift
    // actually close the window.
    // macOS: MainFlutterWindow.performClose sends "windowCloseRequested" via Swift.
    // Windows: flutter_window.cpp WM_CLOSE handler sends the same message.
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
      _windowChannel.setMethodCallHandler(_onWindowMethodCall);
    }
  }

  Future<dynamic> _onWindowMethodCall(MethodCall call) async {
    if (call.method == 'windowCloseRequested') {
      if (!mounted) {
        await _agentService.stop();
        _windowChannel.invokeMethod('confirmClose');
        return;
      }
      final confirmed = await _showQuitDialog();
      if (confirmed == true) {
        _quitConfirmed = true;
        await _agentService.stop();
        if (Platform.isMacOS) {
          // Let Swift close the window (MainFlutterWindow.performClose flow).
          _windowChannel.invokeMethod('confirmClose');
        } else {
          // Windows: destroy the window by posting WM_CLOSE back after we
          // have stopped the agent — but now the Dart flag is set so the
          // handler won't re-show the dialog.  Simplest cross-platform exit.
          exit(0);
        }
      }
      // else: user cancelled — window stays open
    }
  }

  Future<AppExitResponse> _onExitRequested() async {
    // On macOS, closing the window via our dialog already set _quitConfirmed;
    // the subsequent applicationShouldTerminate call must not show a second dialog.
    if (_quitConfirmed) return AppExitResponse.exit;
    if (!mounted) {
      await _agentService.stop();
      return AppExitResponse.exit;
    }
    final confirmed = await _showQuitDialog();
    if (confirmed == true) {
      await _agentService.stop();
      return AppExitResponse.exit;
    }
    return AppExitResponse.cancel;
  }

  Future<bool?> _showQuitDialog() {
    final l = AppLocalizations.of(context);
    final agentRunning = _agentService.isRunning;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l.exitConfirmTitle),
        content: Text(agentRunning ? l.exitConfirmContent : l.exitConfirmContentIdle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.exitCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(agentRunning ? l.exitConfirm : l.exitConfirmIdle),
          ),
        ],
      ),
    );
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
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
    );
  }
}
