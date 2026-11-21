import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'state/app_controller.dart';
import 'ui/app_shell.dart';
import 'ui/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  runApp(PosApp(controller: AppController()));
}

class PosApp extends StatefulWidget {
  const PosApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<PosApp> createState() => _PosAppState();
}

class _PosAppState extends State<PosApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    widget.controller.onToast = (message) {
      final messenger = _messenger.currentState;
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
    };
    widget.controller.init();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppController>.value(
      value: widget.controller,
      child: Selector<AppController, String>(
        selector: (_, controller) => controller.theme,
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'Mie Pangsit Jakarta POS',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: _messenger,
            locale: const Locale('id', 'ID'),
            supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: PosTheme.light(),
            darkTheme: PosTheme.dark(),
            themeMode: theme == 'dark' ? ThemeMode.dark : ThemeMode.light,
            home: Consumer<AppController>(
              builder: (context, controller, _) {
                if (controller.loading) {
                  return const _SplashScreen();
                }
                if (controller.user == null) {
                  return const LoginScreen();
                }
                return const AppShell();
              },
            ),
          );
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: PosColors.sky.withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/img/pangsitmie.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Icon(
                    Icons.ramen_dining_rounded,
                    size: 40,
                    color: PosColors.sky,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Mie Pangsit Jakarta',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
