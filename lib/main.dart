import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/db/app_database.dart';
import 'core/haptics/app_haptics.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bootstrap: open the database and preferences BEFORE the first frame so
  // the UI never renders against a missing store. If either fails we still
  // render an error screen instead of a white flash.
  try {
    final db = await AppDatabase.open();
    final prefs = await SharedPreferences.getInstance();
    // Respect the user's haptics choice from the first interaction.
    AppHaptics.enabled = prefs.getBool('haptics_enabled') ?? true;
    runApp(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const HisablyApp(),
      ),
    );
  } catch (e) {
    runApp(const _BootstrapErrorApp());
  }
}

class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 44),
                const SizedBox(height: 16),
                Text(
                  'Hisably could not open its local database.\n'
                  'Please restart the app — your data is safe on this device.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
