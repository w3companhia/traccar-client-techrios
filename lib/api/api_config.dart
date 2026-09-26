import 'package:flutter/foundation.dart';

import '../preferences.dart';

/// Ambientes da API de rastreio da TechRios.
///
/// Os valores vêm de `String.fromEnvironment`, alimentados pelo arquivo `.env`
/// da raiz do projeto:
///
///   flutter run --dart-define-from-file=.env
///
/// Os defaults abaixo são a configuração real de cada ambiente; o `.env` serve
/// para as chaves (que não vão para o repositório) e para apontar homologação
/// à máquina do desenvolvedor enquanto a API não estiver publicada.
///
/// Atenção: são constantes de compilação. Alterar o `.env` exige rebuild —
/// hot reload não pega.
enum ApiEnvironment { homologacao, developer, producao }

class ApiEnvironmentConfig {
  const ApiEnvironmentConfig({
    required this.label,
    required String baseUrl,
    required String apiKey,
    String hostHeader = '',
  })  : _baseUrl = baseUrl,
        _apiKey = apiKey,
        _hostHeader = hostHeader;

  final String label;
  final String _baseUrl;
  final String _apiKey;
  final String _hostHeader;

  /// Valores vindos de Variables e Secrets chegam como o autor digitou: com
  /// espaço sobrando ou aspas coladas ao redor. Uma URL entre aspas derruba o
  /// Uri.parse com FormatException antes de qualquer requisição sair — falha
  /// difícil de rastrear, porque o app parece simplesmente não reagir.
  static String _limpar(String valor) {
    var limpo = valor.trim();
    final aspas = (limpo.startsWith('"') && limpo.endsWith('"')) ||
        (limpo.startsWith("'") && limpo.endsWith("'"));
    if (limpo.length >= 2 && aspas) {
      limpo = limpo.substring(1, limpo.length - 1).trim();
    }
    return limpo;
  }

  String get baseUrl => _limpar(_baseUrl);
  String get apiKey => _limpar(_apiKey);

  /// Host enviado no header quando difere do host da conexão. Usado ao apontar
  /// para a máquina local: o emulador chega nela por 10.0.2.2, mas o Traefik
  /// roteia pelo Host.
  String get hostHeader => _limpar(_hostHeader);

  bool get isConfigured => apiKey.isNotEmpty && apiKey != ApiConfig.unsetApiKey;
}

class ApiConfig {
  ApiConfig._();

  static const String unsetApiKey = '';
  static const String basePath = '/api/rastreio';

  static const Map<ApiEnvironment, ApiEnvironmentConfig> environments = {
    ApiEnvironment.homologacao: ApiEnvironmentConfig(
      label: 'Homologação',
      baseUrl: String.fromEnvironment(
        'RASTREIO_BASE_URL_HOMOLOG',
        defaultValue: 'https://app.homologacao.techrios.online',
      ),
      apiKey: String.fromEnvironment('RASTREIO_API_KEY_HOMOLOG'),
      hostHeader: String.fromEnvironment('RASTREIO_HOST_HEADER_HOMOLOG'),
    ),
    // Pré-produção: recebe o que vai para produção na semana seguinte.
    ApiEnvironment.developer: ApiEnvironmentConfig(
      label: 'Developer',
      baseUrl: String.fromEnvironment(
        'RASTREIO_BASE_URL_DEV',
        defaultValue: 'https://app.developer.techrios.online',
      ),
      apiKey: String.fromEnvironment('RASTREIO_API_KEY_DEV'),
      hostHeader: String.fromEnvironment('RASTREIO_HOST_HEADER_DEV'),
    ),
    ApiEnvironment.producao: ApiEnvironmentConfig(
      label: 'Produção',
      baseUrl: String.fromEnvironment(
        'RASTREIO_BASE_URL_PROD',
        defaultValue: 'https://app.techrios.online',
      ),
      apiKey: String.fromEnvironment('RASTREIO_API_KEY_PROD'),
      hostHeader: String.fromEnvironment('RASTREIO_HOST_HEADER_PROD'),
    ),
  };

  /// Trava o app num ambiente e esconde o seletor do login. Vazio deixa a
  /// escolha visível em debug; em release o app cai em produção, para que um
  /// build de loja nunca mostre o seletor por esquecimento do define. Um APK
  /// de teste apontando para homologação passa `RASTREIO_ENV=homologacao`.
  static const String _forcedName = String.fromEnvironment('RASTREIO_ENV');

  static ApiEnvironment? get _forced {
    final named = ApiEnvironment.values.where((e) => e.name == _forcedName).firstOrNull;
    return named ?? (kReleaseMode ? ApiEnvironment.producao : null);
  }

  static bool get canChangeEnvironment => _forced == null;

  static ApiEnvironment _current = ApiEnvironment.homologacao;

  static ApiEnvironment get current => _current;
  static ApiEnvironmentConfig get env => environments[_current]!;

  static String get baseUrl => env.baseUrl;
  static String get apiKey => env.apiKey;
  static String get hostHeader => env.hostHeader;
  static bool get isConfigured => env.isConfigured;

  /// Os dois ambientes aparecem no seletor mesmo sem chave — a tela de login
  /// avisa quando falta, o que é mais claro do que a opção sumir sem explicação.
  static List<ApiEnvironment> get available => ApiEnvironment.values;

  /// Lido depois de `Preferences.init()`, antes de qualquer chamada à API.
  static void load() {
    // Ambiente travado no build ignora qualquer escolha anterior gravada.
    final forced = _forced;
    if (forced != null) {
      _current = forced;
      return;
    }
    final stored = Preferences.instance.getString(Preferences.ambiente);
    final match = ApiEnvironment.values.where((e) => e.name == stored).firstOrNull;
    // Sem escolha anterior, começa no primeiro ambiente que tenha chave.
    final fallback = ApiEnvironment.values.where((e) => environments[e]!.isConfigured).firstOrNull;
    _current = match ?? fallback ?? ApiEnvironment.homologacao;
  }

  static Future<void> setEnvironment(ApiEnvironment environment) async {
    _current = environment;
    await Preferences.instance.setString(Preferences.ambiente, environment.name);
  }
}
