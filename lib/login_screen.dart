import 'dart:developer' as developer;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import 'api/api_config.dart';
import 'api/rastreio_api.dart';
import 'app_info.dart';
import 'l10n/app_localizations.dart';
import 'session_service.dart';
import 'theme.dart';

/// Login no mesmo layout do Validador de Passagens: área superior tingida com
/// a marca, e os campos num cartão de cantos arredondados encostado embaixo.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    // Antes este caminho apenas retornava: o toque não produzia mensagem,
    // spinner nem requisição, e o botão parecia não funcionar.
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = AppLocalizations.of(context)!.fillCredentialsMessage);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await RastreioApi.login(email, password);
      await SessionService.signIn(result);
      // O gate de autenticação troca a tela sozinho.
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error, stack) {
      // Sem este catch, qualquer falha que não seja ApiException — formato de
      // resposta inesperado, armazenamento seguro indisponível — subia para o
      // handler global, ia para o Crashlytics e a tela não mostrava nada: o
      // usuário tocava em Entrar e parecia que o botão não funcionava.
      developer.log('Login falhou', error: error, stackTrace: stack);
      FirebaseCrashlytics.instance.recordError(error, stack);
      // O tipo da exceção acompanha a mensagem: sem ele, o relato de suporte
      // vira "deu erro inesperado" e não distingue falha de armazenamento
      // seguro de erro de formato ou de plataforma.
      if (mounted) {
        setState(() => _error =
            '${AppLocalizations.of(context)!.unexpectedError} (${error.runtimeType})');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Trocar de ambiente invalida a seleção anterior: cada base tem os próprios
  /// ids de embarcação, então o que estava guardado não vale no novo.
  Future<void> _changeEnvironment(ApiEnvironment environment) async {
    if (environment == ApiConfig.current) return;
    await ApiConfig.setEnvironment(environment);
    await SessionService.clearEmbarcacao();
    if (mounted) setState(() => _error = null);
  }

  Widget _buildEnvironmentSelector() {
    final palette = context.palette;
    final options = ApiConfig.available;
    // Escondido quando o build trava o ambiente (RASTREIO_ENV) ou quando só
    // há uma opção — nos dois casos o seletor não decidiria nada.
    if (!ApiConfig.canChangeEnvironment || options.length < 2) {
      return const SizedBox.shrink();
    }
    return SegmentedButton<ApiEnvironment>(
      showSelectedIcon: false,
      segments: [
        for (final option in options)
          ButtonSegment<ApiEnvironment>(
            value: option,
            label: Text(ApiConfig.environments[option]!.label),
          ),
      ],
      selected: {ApiConfig.current},
      onSelectionChanged: _loading ? null : (selection) => _changeEnvironment(selection.first),
      style: SegmentedButton.styleFrom(
        backgroundColor: palette.surface,
        selectedBackgroundColor: palette.primaryContainer,
        selectedForegroundColor: palette.onPrimaryContainer,
        foregroundColor: palette.textSecondary,
        side: BorderSide(color: palette.border),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildBrand(AppLocalizations localizations) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // O logotipo colorido tem o "tech" em azul-escuro, que desapareceria
        // no fundo escuro — por isso a variante branca no modo escuro.
        Image.asset(
          isDark ? 'assets/brand/techrios-white.png' : 'assets/brand/techrios.png',
          width: 168,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 28),
        // Na referência o quadrado é branco porque o ícone dela é colorido.
        // O nosso glifo é branco, então o quadrado é que carrega a cor.
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            color: palette.primary,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Image.asset('assets/icon/logo.png', fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Rota Rios',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: palette.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          localizations.appTagline,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, height: 1.35, color: palette.textSecondary),
        ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool enabled,
    bool obscure = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    void Function(String)? onSubmitted,
  }) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.label),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          autocorrect: false,
          // Limpa o erro ao editar: sem isto a mensagem de um toque anterior
          // permanece na tela enquanto o usuário digita, e passa a contradizer
          // o que ele está vendo nos campos.
          onChanged: _error == null ? null : (_) => setState(() => _error = null),
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: TextStyle(fontSize: 15, color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffixIcon,
            // Campo preenchido sem borda, como no Validador.
            fillColor: palette.fieldFill,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: palette.primary, width: 1.6),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(AppLocalizations localizations, bool configured, bool enabled) {
    final palette = context.palette;
    // Sem reservar a área do sistema, o cartão chega até a borda inferior e o
    // botão fica sob a barra de navegação por gestos, que intercepta o toque
    // antes de ele chegar ao app: o usuário toca e nada acontece.
    final insetInferior = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(28, 32, 28, 24 + insetInferior),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildField(
            label: localizations.emailLabel,
            hint: localizations.emailHint,
            controller: _emailController,
            enabled: enabled,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 18),
          _buildField(
            label: localizations.passwordLabel,
            hint: '••••••••',
            controller: _passwordController,
            enabled: enabled,
            obscure: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: palette.primary,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          if (!configured || _error != null) ...[
            const SizedBox(height: 14),
            Text(
              configured ? _error! : localizations.apiKeyMissingMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13.5),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              // Pílula, como na referência.
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            onPressed: enabled ? _submit : null,
            child: _loading
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: palette.onPrimary),
                  )
                : Text(localizations.signInButton),
          ),
          const SizedBox(height: 18),
          Text(
            'v${AppInfo.version}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: palette.muted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final palette = context.palette;
    final configured = ApiConfig.isConfigured;
    final enabled = !_loading && configured;

    return Scaffold(
      backgroundColor: palette.loginBackdrop,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              // Center + scroll: centraliza quando há espaço e passa a rolar
              // quando o teclado encolhe a área, sem estourar o layout.
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildEnvironmentSelector(),
                      const SizedBox(height: 24),
                      _buildBrand(localizations),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildForm(localizations, configured, enabled),
        ],
      ),
    );
  }
}
