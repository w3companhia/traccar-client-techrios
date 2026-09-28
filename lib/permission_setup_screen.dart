import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'l10n/app_localizations.dart';
import 'theme.dart';

/// Passo a passo das duas permissões que o Android exige fora do fluxo
/// normal do app para o rastreamento sobreviver em segundo plano.
///
/// Ignorar otimização de bateria dá para conceder com um toque, direto por
/// cima do app. Localização "o tempo todo" o próprio Android obriga a passar
/// pela tela de Configurações a partir do Android 11 — não tem como o app
/// conceder isso sozinho, é bloqueio deliberado de privacidade do sistema.
class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  /// true quando as duas permissões já estão concedidas (ou fora do Android,
  /// onde otimização de bateria nem existe).
  static Future<bool> isSatisfied() async {
    if (!Platform.isAndroid) return true;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final location = await Permission.locationAlways.isGranted;
    return battery && location;
  }

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen>
    with WidgetsBindingObserver {
  bool _batteryGranted = false;
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cobre quem concedeu pela tela de Configurações e voltou ao app.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final location = await Permission.locationAlways.isGranted;
    if (!mounted) return;
    setState(() {
      _batteryGranted = battery;
      _locationGranted = location;
    });
  }

  Future<void> _requestBattery() async {
    await Permission.ignoreBatteryOptimizations.request();
    await _refresh();
  }

  Future<void> _requestLocation() async {
    // Segundo plano só pode ser pedido depois que o de primeiro plano já
    // estiver concedido, senão o Android recusa a solicitação inteira.
    await Permission.locationWhenInUse.request();
    final status = await Permission.locationAlways.request();
    if (status.isGranted) {
      await _refresh();
      return;
    }
    // A partir do Android 11 o diálogo raramente concede "o tempo todo"
    // diretamente; isso já pula para a tela de detalhes do app, um passo mais
    // perto do que abrir Configurações e procurar o app na lista.
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final palette = context.palette;
    final allGranted = _batteryGranted && _locationGranted;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.permissionSetupTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                localizations.permissionSetupIntro,
                style: TextStyle(fontSize: 14, height: 1.4, color: palette.textSecondary),
              ),
              const SizedBox(height: 20),
              _PermissionStep(
                granted: _batteryGranted,
                label: localizations.batteryOptimizationStepLabel,
                description: localizations.optimizationMessage,
                buttonLabel: localizations.batteryOptimizationButton,
                onPressed: _requestBattery,
              ),
              const SizedBox(height: 14),
              _PermissionStep(
                granted: _locationGranted,
                label: localizations.backgroundLocationStepLabel,
                description: localizations.backgroundLocationInstructions,
                buttonLabel: localizations.backgroundLocationButton,
                onPressed: _requestLocation,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(allGranted),
                child: Text(allGranted ? localizations.okButton : localizations.permissionSetupSkipButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionStep extends StatelessWidget {
  const _PermissionStep({
    required this.granted,
    required this.label,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final bool granted;
  final String label;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  granted ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: granted ? palette.primary : palette.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: TextStyle(fontSize: 13, height: 1.4, color: palette.textSecondary)),
            if (!granted) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onPressed, child: Text(buttonLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
