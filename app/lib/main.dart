import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/connect_screen.dart';
import 'screens/hosted_screen.dart';
import 'services/agent_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    return MaterialApp(
      title: 'RemoteCtl',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final _agentService = AgentService();

  @override
  void dispose() {
    _agentService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const ConnectScreen(),
          HostedScreen(agentService: _agentService),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: const Color(0xFF0A0F1E),
        indicatorColor: const Color(0xFF2563EB).withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_outlined),
            selectedIcon: Icon(Icons.monitor),
            label: '控制端',
          ),
          NavigationDestination(
            icon: Icon(Icons.screen_share_outlined),
            selectedIcon: Icon(Icons.screen_share),
            label: '被控端',
          ),
        ],
      ),
    );
  }
}
