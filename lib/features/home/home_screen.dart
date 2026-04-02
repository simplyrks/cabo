import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cabo/core/theme/app_theme.dart';
import 'package:cabo/providers/game_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController(text: 'localhost');
  final _portCtrl = TextEditingController(text: '8080');
  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _connect() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('Please enter your name');
      return;
    }
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8080;

    // Clear stale state from any previous session before reconnecting
    ref.read(gameStateProvider.notifier).clear();
    ref.read(roundEndProvider.notifier).state = null;
    ref.read(roundEndGameStateProvider.notifier).state = null;
    ref.read(lobbyProvider.notifier).reset();
    ref.read(localPlayerProvider.notifier).state = null;
    ref.read(peekRevealProvider.notifier).state = null;

    // Connect (non-blocking) → start message routing → send joinLobby → navigate.
    // Connection success is confirmed reactively when the server sends 'welcome'.
    ref.read(connectionProvider.notifier).connect(host, port);
    ref.read(messageRouterProvider).start();
    ref.read(gameClientProvider).joinLobby(name);
    context.go('/lobby');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    // When served over HTTPS (production), wss:// is used automatically
    // and the port field is irrelevant — cloud proxies handle TLS on 443.
    final isProduction = Uri.base.scheme == 'https';

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Title
                const Text(
                  'CABO',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    letterSpacing: 12,
                  ),
                ),
                const Text(
                  'The Card Game',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 56),

                // Name field
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Your Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 16),

                // Host field
                TextField(
                  controller: _hostCtrl,
                  decoration: InputDecoration(
                    labelText: isProduction ? 'Server Hostname' : 'Server IP',
                    hintText: isProduction
                        ? 'your-app.up.railway.app'
                        : 'localhost',
                    prefixIcon: const Icon(Icons.dns_outlined),
                  ),
                  keyboardType: TextInputType.url,
                ),

                // Port field — only shown in local dev (HTTP)
                if (!isProduction) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _portCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      prefixIcon: Icon(Icons.link),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
                const SizedBox(height: 32),

                // Connect button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _connect,
                    child: const Text('Join Game'),
                  ),
                ),

                const SizedBox(height: 24),
                Text(
                  isProduction
                      ? 'Enter the Railway/Fly.io hostname above.\nAll connections use secure WebSocket (wss://) automatically.'
                      : 'Make sure the server is running on the host machine.\nRun: dart run server/bin/main.dart',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
