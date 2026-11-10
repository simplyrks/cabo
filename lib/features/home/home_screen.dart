import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cabo/core/server_config.dart';
import 'package:cabo/core/theme/app_theme.dart';
import 'package:cabo/networking/room_api.dart';
import 'package:cabo/providers/game_provider.dart';
import 'package:cabo/networking/seat_store.dart';
import 'package:cabo/features/rules/rules_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  Timer? _refreshTimer;
  List<RoomInfo>? _rooms; // null until the first load finishes
  bool _roomsFailed = false;

  @override
  void initState() {
    super.initState();
    // Coming home closes the connection. A seat in a game is kept for the
    // player (the game plays for them), and the card below offers a way back.
    ref.read(reconnectProvider.notifier).stop();
    ref.read(gameClientProvider).disconnect();
    _loadRooms();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _loadRooms());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await fetchRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _roomsFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _roomsFailed = true);
    }
  }

  void _joinWithCode() {
    final room = normalizeRoomCode(_codeCtrl.text);
    if (room == null) {
      _showError('Enter a game code, like G3');
      return;
    }
    _join(room);
  }

  void _join(String room) {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('Please enter your name');
      return;
    }

    // Clear stale state from any previous session before reconnecting
    resetGameSession(ref);
    ref.read(roomCodeProvider.notifier).state = null;
    ref.read(lobbyErrorProvider.notifier).state = null;

    // Connect (non-blocking) → start message routing → send joinLobby → navigate.
    // The lobby handles the result: 'welcome' seats the player, an error sends
    // them back here with the reason.
    ref.read(connectionProvider.notifier).connect(room);
    ref.read(messageRouterProvider).start();
    ref.read(gameClientProvider).joinLobby(name);
    context.go('/lobby');
  }

  /// Back into the game this device left, using its saved seat.
  void _rejoin() {
    resetGameSession(ref);
    ref.read(lobbyErrorProvider.notifier).state = null;
    ref.read(messageRouterProvider).start();
    ref.read(reconnectProvider.notifier).start();
    context.go('/game');
  }

  Widget _buildRejoinCard(SavedSeat seat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.highlight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.highlight.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.replay, color: AppColors.highlight),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You have a game in progress',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Game ${seat.room.toUpperCase()} · playing as ${seat.name}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          ElevatedButton(onPressed: _rejoin, child: const Text('Rejoin')),
          IconButton(
            tooltip: 'Forget this game',
            onPressed: () => ref.read(savedSeatProvider.notifier).clear(),
            icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final savedSeat = ref.watch(savedSeatProvider);
    return Scaffold(
      body: WithRulesButton(
          child: Center(
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

                if (savedSeat != null) _buildRejoinCard(savedSeat),

                // Name field
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Your Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),

                // Create button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _join(newRoomPath),
                    child: const Text('Create New Game'),
                  ),
                ),
                const SizedBox(height: 16),

                // Join by code
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Game Code',
                          hintText: 'G3',
                          prefixIcon: Icon(Icons.tag),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _joinWithCode(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _joinWithCode,
                      child: const Text('Join'),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Games list
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Games',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildRoomList(),
              ],
            ),
          ),
        ),
      )),
    );
  }

  Widget _buildRoomList() {
    final rooms = _rooms;
    if (_roomsFailed) {
      return const _RoomListMessage(
          'Could not reach the game server. Retrying...');
    }
    if (rooms == null) {
      return const CircularProgressIndicator(color: AppColors.highlight);
    }
    if (rooms.isEmpty) {
      return const _RoomListMessage('No games yet. Create one to get started.');
    }
    return Column(
      children: rooms
          .map((room) => _RoomTile(room: room, onJoin: () => _join(room.code)))
          .toList(),
    );
  }
}

class _RoomListMessage extends StatelessWidget {
  final String message;

  const _RoomListMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final RoomInfo room;
  final VoidCallback onJoin;

  const _RoomTile({required this.room, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final detail = switch (room.status) {
      'playing' => 'In progress',
      'full' => 'Full',
      _ => '${room.players}/${room.maxPlayers} players',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            room.code.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              detail,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: room.isJoinable ? onJoin : null,
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}
