import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:traccar_client/main.dart';
import 'package:traccar_client/password_service.dart';
import 'package:traccar_client/preferences.dart';

import 'geolocation_service.dart';
import 'l10n/app_localizations.dart';
import 'permission_setup_screen.dart';
import 'selection_flow.dart';
import 'session_service.dart';
import 'settings_screen.dart';
import 'theme.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  bool trackingEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Sem embarcação não há o que rastrear, então a lista abre já no login.
      if (!SessionService.hasEmbarcacao) _openSelection(showBackButton: false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshState();
    }
  }

  Future<void> _refreshState() async {
    final tracking = await GeolocationService.tracker.isTracking();
    if (!mounted) return;
    setState(() {
      trackingEnabled = tracking;
    });
  }

  void refresh() => setState(() {});

  Future<void> _openSelection({bool showBackButton = true}) async {
    final changed = await SelectionFlow.start(context, showBackButton: showBackButton);
    if (changed && mounted) setState(() {});
  }

  Future<void> _signOut() async {
    final localizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(localizations.signOutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localizations.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(localizations.okButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Sem sessão não há embarcação válida, então o rastreamento não pode seguir.
    if (await GeolocationService.tracker.isTracking()) {
      await GeolocationService.reportTrackingStopped();
    }
    try {
      await GeolocationService.tracker.stop();
    } on PlatformException {
      // already stopped or service unavailable
    }
    await SessionService.signOut();
  }

  Future<void> _toggleTracking() async {
    if (!SessionService.hasEmbarcacao) {
      await _openSelection();
      return;
    }
    final localizations = AppLocalizations.of(context)!;
    if (!await PasswordService.authenticate(context) || !mounted) return;

    // O estado guardado pode estar velho — a permissão pode ter sido revogada
    // nas configurações do sistema, ou o serviço morto pelo Android. Age-se
    // sobre o estado real, não sobre o que a tela mostrava.
    final tracking = await GeolocationService.tracker.isTracking();

    if (!tracking) {
      // isTracking() só diz se o serviço está rodando, não se ele consegue
      // posição de verdade — sem permissão ou com o GPS desligado o botão
      // acendia mesmo sem nenhuma localização sair, um falso positivo.
      final locationPermission = await Permission.locationWhenInUse.request();
      if (!locationPermission.isGranted) {
        if (!mounted) return;
        messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(localizations.trackingStartFailed),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // Sem essas duas permissões o Android mata o rastreamento em segundo
      // plano silenciosamente, sem erro nenhum pro usuário perceber.
      if (!await PermissionSetupScreen.isSatisfied()) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PermissionSetupScreen()),
        );
        if (!mounted) return;
      }

      if (await Permission.location.serviceStatus != ServiceStatus.enabled) {
        if (!mounted) return;
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(localizations.gpsDisabledTitle),
            content: Text(localizations.gpsDisabledMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(localizations.cancelButton),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(localizations.openLocationSettingsButton),
              ),
            ],
          ),
        );
        if (openSettings == true) {
          await AppSettings.openAppSettings(type: AppSettingsType.location);
        }
        return;
      }
    }

    if (tracking) {
      FirebaseCrashlytics.instance.log('tracking_toggle_stop');
      await GeolocationService.reportTrackingStopped();
      await GeolocationService.tracker.stop();
    } else {
      FirebaseCrashlytics.instance.log('tracking_toggle_start');
      try {
        await GeolocationService.tracker.start();
      } on PlatformException {
        // permission denied or startup error
      }
    }

    // start() pode retornar sem lançar enquanto a permissão ainda está
    // pendente — foi o que deixava o botão ligado sem rastreamento algum.
    // Só o SDK sabe o resultado final.
    final actuallyTracking = await GeolocationService.tracker.isTracking();
    if (!mounted) return;
    setState(() => trackingEnabled = actuallyTracking);

    if (!tracking && !actuallyTracking) {
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(localizations.trackingStartFailed),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildHeader() {
    final localizations = AppLocalizations.of(context)!;
    final palette = context.palette;
    final user = SessionService.usuarioNome;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rota Rios',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                if (user != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    user,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: palette.muted),
            tooltip: localizations.settingsTitle,
            onPressed: () async {
              if (await PasswordService.authenticate(context) && mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                setState(() {});
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.logout, color: palette.primary),
            tooltip: localizations.signOutButton,
            onPressed: _signOut,
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required String label, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: AppTheme.sectionLabel(context)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildVesselCard() {
    final localizations = AppLocalizations.of(context)!;
    final palette = context.palette;
    final vessel = SessionService.embarcacaoNome;
    final company = SessionService.empresaNome;
    return _buildCard(
      label: localizations.vesselLabel,
      children: [
        Text(
          vessel ?? localizations.noVesselSelected,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        if (company != null) ...[
          const SizedBox(height: 2),
          Text(company, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
        ],
        const SizedBox(height: 14),
        TonalButton(
          label: localizations.changeVesselButton,
          onPressed: _openSelection,
        ),
      ],
    );
  }

  Widget _buildTrackingCard() {
    final localizations = AppLocalizations.of(context)!;
    final palette = context.palette;
    return _buildCard(
      label: localizations.trackingTitle,
      children: [
        Text(
          localizations.idLabel,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: palette.label),
        ),
        const SizedBox(height: 1),
        Text(
          Preferences.instance.getString(Preferences.id) ?? '',
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'monospace',
            color: palette.textSecondary,
          ),
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 12),
          Text(
            localizations.disclosureMessage,
            style: TextStyle(fontSize: 12.5, height: 1.5, color: palette.textSecondary),
          ),
        ],
        const SizedBox(height: 14),
        // Ação única da tela: enviar posição avulsa e ver status foram para as
        // configurações, para não competirem com o botão principal.
        Center(
          child: Column(
            children: [
              _TrackingButton(active: trackingEnabled, onTap: _toggleTracking),
              const SizedBox(height: 8),
              Text(
                // Desligado, o rótulo instrui em vez de só informar o estado.
                trackingEnabled
                    ? localizations.trackingActiveLabel
                    : localizations.trackingStartHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: trackingEnabled ? palette.primary : palette.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  // Sem stretch cada Card encolhe até o próprio conteúdo e os
                  // dois ficam com larguras diferentes.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildVesselCard(),
                    const SizedBox(height: 14),
                    _buildTrackingCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão secundário do design: fundo na cor container, texto na cor da marca.
class TonalButton extends StatelessWidget {
  const TonalButton({super.key, required this.label, required this.onPressed, this.expand = false});

  final String label;
  final VoidCallback onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: palette.primaryContainer,
        foregroundColor: palette.onPrimaryContainer,
        elevation: 0,
        minimumSize: expand ? const Size.fromHeight(42) : const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.buttonRadius)),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// Botão circular de rastreamento, com as ondas pulsantes do design enquanto
/// ativo. O controlador só roda quando [active], para não gastar bateria
/// animando uma tela parada.
class _TrackingButton extends StatefulWidget {
  const _TrackingButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  State<_TrackingButton> createState() => _TrackingButtonState();
}

class _TrackingButtonState extends State<_TrackingButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(_TrackingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Uma onda: cresce de 1.0 a 1.55 enquanto desaparece.
  Widget _buildRipple(double phase, Color color) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = (_controller.value + phase) % 1.0;
        return Transform.scale(
          scale: 1 + 0.55 * t,
          child: Opacity(opacity: 0.35 * (1 - t), child: child),
        );
      },
      child: Container(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = widget.active;
    return SizedBox(
      width: 186,
      height: 186,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (active) ...[
            SizedBox(width: 120, height: 120, child: _buildRipple(0, palette.primary)),
            SizedBox(width: 120, height: 120, child: _buildRipple(0.5, palette.primary)),
          ],
          // Desligado o círculo é claro com borda e ícone na cor da marca:
          // cinza sobre cinza era lido como "desabilitado", e os testadores
          // acabavam tocando nos botões secundários.
          Material(
            color: active ? palette.primary : palette.surface,
            shape: CircleBorder(
              side: active ? BorderSide.none : BorderSide(color: palette.primary, width: 2),
            ),
            elevation: active ? 0 : 1,
            shadowColor: palette.primary.withValues(alpha: 0.3),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onTap,
              child: SizedBox(
                width: 120,
                height: 120,
                child: Icon(
                  // Alfinete cortado quando parado, inteiro quando rastreando.
                  active ? Icons.location_on : Icons.location_off,
                  size: 46,
                  color: active ? palette.onPrimary : palette.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
