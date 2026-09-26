import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:rate_my_app/rate_my_app.dart';
import 'package:traccar_client/password_service.dart';
import 'package:traccar_client/push_service.dart';
import 'package:traccar_client/quick_actions.dart';
import 'package:traccar_client/login_screen.dart';
import 'package:traccar_client/session_service.dart';

import 'api/api_config.dart';
import 'app_info.dart';
import 'configuration_service.dart';
import 'geolocation_service.dart';
import 'l10n/app_localizations.dart';
import 'main_screen.dart';
import 'managed_config_service.dart';
import 'preferences.dart';
import 'theme.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();
final navigatorKey = GlobalKey<NavigatorState>();
final mainScreenKey = GlobalKey<MainScreenState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FlutterError.onError = (details) {
    // Em debug o handler padrão também roda: sem isso um erro de layout vai
    // apenas para o Crashlytics e a tela quebra sem nada no console.
    if (kDebugMode) FlutterError.presentError(details);
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  await Preferences.init();
  ApiConfig.load();
  await GeolocationService.tracker.init(Preferences.buildConfig());
  await PasswordService.migrate();
  await PushService.init();
  await ManagedConfigService.init();
  await SessionService.init();
  await AppInfo.init();
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  RateMyApp rateMyApp = RateMyApp(minDays: 0, minLaunches: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initLinks();
      await rateMyApp.init();
      final dialogContext = navigatorKey.currentContext;
      if (dialogContext != null && dialogContext.mounted && rateMyApp.shouldOpenDialog) {
        await rateMyApp.showRateDialog(dialogContext);
      }
    });
  }

  Future<void> _initLinks() async {
    AppLinks().uriLinkStream.listen(_handleUri);
  }

  Future<void> _handleUri(Uri uri) async {
    if (uri.host == 'action') {
      try {
        switch (uri.pathSegments.firstOrNull) {
          case 'start':
            await GeolocationService.tracker.start();
          case 'stop':
            await GeolocationService.tracker.stop();
        }
      } on PlatformException {
        // permission denied or startup error
      }
      return;
    }
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(AppLocalizations.of(context)!.configurationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.okButton),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ConfigurationService.applyUri(uri);
      mainScreenKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      navigatorKey: navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const AuthGate(),
    );
  }
}

/// Mostra o login enquanto não há sessão e o app depois que há.
/// Reage ao [SessionService.signedIn], então login e logout trocam a tela
/// sem que nenhuma tela precise navegar manualmente.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SessionService.signedIn,
      builder: (context, signedIn, _) {
        if (!signedIn) return const LoginScreen();
        return Stack(
          children: [
            const QuickActionsInitializer(),
            MainScreen(key: mainScreenKey),
          ],
        );
      },
    );
  }
}
