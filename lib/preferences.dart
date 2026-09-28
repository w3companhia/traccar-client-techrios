import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart';

class Preferences {
  static Future<void>? _initFuture;
  static late SharedPreferencesWithCache instance;

  static const String id = 'id';
  static const String url = 'url';
  static const String accuracy = 'accuracy';
  static const String distance = 'distance';
  static const String interval = 'interval';
  static const String angle = 'angle';
  static const String heartbeat = 'heartbeat';
  static const String buffer = 'buffer';
  static const String wakelock = 'wakelock';
  static const String stopDetection = 'stop_detection';
  static const String preferPlatformProviders = 'prefer_platform_providers';
  static const String password = 'password';

  /// Controla a migração forçada de configuração abaixo — some dispositivos
  /// tinham valores antigos (ex: precisão média, intervalo de 300s) e a
  /// operação decidiu padronizar todo mundo, inclusive quem já rastreava.
  static const String operationalDefaultsVersion = 'operational_defaults_version';
  static const int _currentOperationalDefaultsVersion = 1;

  // Seleção vinda da API de rastreio da TechRios.
  static const String empresaId = 'empresa_id';
  static const String empresaNome = 'empresa_nome';
  static const String embarcacaoId = 'embarcacao_id';
  static const String embarcacaoNome = 'embarcacao_nome';
  static const String usuarioNome = 'usuario_nome';
  static const String ambiente = 'ambiente';

  /// Servidor Traccar da W3 Companhia. O usuário não configura mais a URL.
  static const String defaultServerUrl = 'https://traccar.w3companhia.com/';

  static Future<void> init() async {
    _initFuture ??= _createInstance();
    await _initFuture;
  }

  static Future<void> _createInstance() async {
    instance = await SharedPreferencesWithCache.create(
      sharedPreferencesOptions: Platform.isAndroid
          ? SharedPreferencesAsyncAndroidOptions(backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences)
          : SharedPreferencesOptions(),
      cacheOptions: SharedPreferencesWithCacheOptions(
        allowList: {
          id, url, accuracy, distance, interval, angle, heartbeat, buffer, wakelock, stopDetection, preferPlatformProviders, password,
          empresaId, empresaNome, embarcacaoId, embarcacaoNome, usuarioNome, ambiente, operationalDefaultsVersion,
        },
      ),
    );
    if (Platform.isAndroid) {
      for (final key in {interval, distance, angle, heartbeat}) {
        if (instance.get(key) is String) {
          await instance.setInt(key, int.tryParse(instance.getString(key) ?? '') ?? 0);
        }
      }
    }
    // Instalações antigas ficaram com o servidor de demonstração do upstream.
    if (instance.getString(url) == 'http://demo.traccar.org:5055') {
      await instance.setString(url, defaultServerUrl);
    }
    if (instance.getString(id) == null) {
      await instance.setString(id, (Random().nextInt(90000000) + 10000000).toString());
      await instance.setString(url, defaultServerUrl);
    }
    // Aplica uma vez só, mesmo em quem já rastreava com outros valores —
    // depois disso o usuário pode alterar livremente sem ser sobrescrito de
    // novo a cada abertura do app.
    if ((instance.getInt(operationalDefaultsVersion) ?? 0) < _currentOperationalDefaultsVersion) {
      await instance.setString(accuracy, 'highest');
      await instance.setInt(distance, 40);
      await instance.setInt(interval, 30);
      await instance.setInt(angle, 0);
      await instance.setInt(heartbeat, 0);
      await instance.setBool(buffer, true);
      await instance.setBool(wakelock, true);
      await instance.setBool(stopDetection, true);
      await instance.setBool(preferPlatformProviders, false);
      await instance.setInt(operationalDefaultsVersion, _currentOperationalDefaultsVersion);
    }
  }

  static Config buildConfig() {
    return Config(
      serverUrl: instance.getString(url) ?? '',
      deviceId: instance.getString(id) ?? '',
      location: LocationConfig(
        accuracy: switch (instance.getString(accuracy)) {
          'highest' => Accuracy.highest,
          'high' => Accuracy.high,
          'low' => Accuracy.low,
          _ => Accuracy.medium,
        },
        distanceMeters: instance.getInt(distance) ?? 40,
        intervalSeconds: instance.getInt(interval) ?? 30,
        angleDegrees: instance.getInt(angle) ?? 0,
        heartbeatIntervalSeconds: instance.getInt(heartbeat) ?? 0,
        stopDetection: instance.getBool(stopDetection) ?? true,
      ),
      wakeLock: instance.getBool(wakelock) ?? true,
      buffer: instance.getBool(buffer) ?? true,
      preferPlatformProviders: instance.getBool(preferPlatformProviders) ?? false,
    );
  }
}
