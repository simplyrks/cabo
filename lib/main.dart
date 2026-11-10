import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'networking/seat_store.dart';
import 'providers/game_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The saved seat is read before the first screen, so Home can offer a rejoin
  final seats = await SeatStore.open();
  runApp(ProviderScope(
    overrides: [seatStoreProvider.overrideWithValue(seats)],
    child: const CaboApp(),
  ));
}

class CaboApp extends StatelessWidget {
  const CaboApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Cabo',
      theme: AppTheme.dark,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
