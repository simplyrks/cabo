import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cabo/core/theme/app_theme.dart';
import 'package:cabo/providers/game_provider.dart';

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lobby = ref.watch(lobbyProvider);
    final localPlayer = ref.watch(localPlayerProvider);
    final gameState = ref.watch(gameStateProvider);
    final roomCode = ref.watch(roomCodeProvider)?.toUpperCase();
    final lobbyError = ref.watch(lobbyErrorProvider);

    // The join failed or the connection dropped — back to home with the reason
    if (lobbyError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(lobbyErrorProvider) == null) return;
        ref.read(lobbyErrorProvider.notifier).state = null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lobbyError), backgroundColor: AppColors.danger),
        );
        context.go('/');
      });
    }

    // Navigate to game screen once game starts
    if (gameState != null && gameState.phase != 'lobby') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/game');
      });
    }

    final isHost = localPlayer?.id == lobby.hostId;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Lobby', style: TextStyle(color: AppColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (roomCode != null) ...[
                  _RoomCodeBanner(code: roomCode),
                  const SizedBox(height: 24),
                ],
                const Text(
                  'Players',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: lobby.players.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.highlight,
                          ),
                        )
                      : ListView.builder(
                          itemCount: lobby.players.length,
                          itemBuilder: (_, i) {
                            final p = lobby.players[i];
                            final pid = p['id'] as String;
                            final pname = p['name'] as String;
                            final isYou = pid == localPlayer?.id;
                            final isThisHost = pid == lobby.hostId;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: isYou
                                    ? Border.all(
                                        color: AppColors.highlight, width: 1)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppColors.highlight
                                        .withValues(alpha: 0.2),
                                    radius: 18,
                                    child: Text(
                                      pname.isNotEmpty
                                          ? pname[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: AppColors.highlight,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      pname,
                                      style: TextStyle(
                                        color: isYou
                                            ? AppColors.highlight
                                            : AppColors.textPrimary,
                                        fontWeight: isYou
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (isThisHost)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.gold
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'HOST',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.gold,
                                        ),
                                      ),
                                    ),
                                  if (isYou && !isThisHost)
                                    const Text(
                                      'YOU',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.highlight,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
                if (!lobby.canStart && lobby.players.length < 2)
                  const Text(
                    'Waiting for at least 2 players...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                const SizedBox(height: 12),
                if (isHost)
                  ElevatedButton(
                    onPressed: lobby.canStart
                        ? () => ref.read(gameClientProvider).startGame()
                        : null,
                    child: const Text('Start Game'),
                  )
                else
                  const Text(
                    'Waiting for host to start...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                const SizedBox(height: 8),
                Text(
                  '${lobby.players.length}/4 players',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomCodeBanner extends StatelessWidget {
  final String code;

  const _RoomCodeBanner({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Game code — share it with your group',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            icon: const Icon(Icons.copy, color: AppColors.gold),
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
          ),
        ],
      ),
    );
  }
}
