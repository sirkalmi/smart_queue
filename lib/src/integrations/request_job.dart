import 'package:dio/dio.dart';
import 'package:smart_request/smart_request.dart' as sr;

import '../smart_job.dart';

class SmartRequestConfigSerializable {
  const SmartRequestConfigSerializable({
    this.maxRetries = 3,
    this.initialDelayMs = 500,
    this.maxDelayMs = 8000,
    this.backoffFactor = 2.0,
    this.jitter = true,
    this.timeoutMs = 5000,
  });

  final int maxRetries;
  final int initialDelayMs;
  final int maxDelayMs;
  final double backoffFactor;
  final bool jitter;
  final int timeoutMs;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'maxRetries': maxRetries,
    'initialDelayMs': initialDelayMs,
    'maxDelayMs': maxDelayMs,
    'backoffFactor': backoffFactor,
    'jitter': jitter,
    'timeoutMs': timeoutMs,
  };

  static SmartRequestConfigSerializable fromMap(Map map) =>
      SmartRequestConfigSerializable(
        maxRetries: (map['maxRetries'] as int?) ?? 3,
        initialDelayMs: (map['initialDelayMs'] as int?) ?? 500,
        maxDelayMs: (map['maxDelayMs'] as int?) ?? 8000,
        backoffFactor: (map['backoffFactor'] as num?)?.toDouble() ?? 2.0,
        jitter: (map['jitter'] as bool?) ?? true,
        timeoutMs: (map['timeoutMs'] as int?) ?? 5000,
      );
}

class RequestJobPayloadKeys {
  static const String url = 'url';
  static const String method = 'method';
  static const String headers = 'headers';
  static const String body = 'body';
  static const String config = 'requestConfig';
}

SmartJob createRequestJob({
  required String id,
  required String url,
  String method = 'GET',
  Map<String, String>? headers,
  Object? body,
  SmartRequestConfigSerializable? config,
  int priority = 0,
}) {
  return SmartJob(
    id: id,
    type: 'smart_request',
    payload: <String, dynamic>{
      RequestJobPayloadKeys.url: url,
      RequestJobPayloadKeys.method: method,
      RequestJobPayloadKeys.headers: headers,
      RequestJobPayloadKeys.body: body,
      if (config != null) RequestJobPayloadKeys.config: config.toMap(),
    },
    priority: priority,
  );
}

/// Handler that adapts a queued job into a smart_request call using Dio
Future<void> queueRequestHandler(Map<String, dynamic> payload) async {
  final String url = payload[RequestJobPayloadKeys.url] as String;
  final String method =
      (payload[RequestJobPayloadKeys.method] as String? ?? 'GET').toUpperCase();
  final Map<String, String>? headers =
      (payload[RequestJobPayloadKeys.headers] as Map?)?.cast<String, String>();
  final Object? body = payload[RequestJobPayloadKeys.body];
  final SmartRequestConfigSerializable cfg =
      (payload[RequestJobPayloadKeys.config] is Map)
      ? SmartRequestConfigSerializable.fromMap(
          payload[RequestJobPayloadKeys.config] as Map,
        )
      : const SmartRequestConfigSerializable();

  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: Duration(milliseconds: cfg.timeoutMs),
      receiveTimeout: Duration(milliseconds: cfg.timeoutMs),
      sendTimeout: Duration(milliseconds: cfg.timeoutMs),
      headers: headers,
    ),
  );

  Future<Response<dynamic>> operation() async {
    switch (method) {
      case 'GET':
        return dio.get(url);
      case 'POST':
        return dio.post(url, data: body);
      case 'PUT':
        return dio.put(url, data: body);
      case 'PATCH':
        return dio.patch(url, data: body);
      case 'DELETE':
        return dio.delete(url, data: body);
      default:
        return dio.request(
          url,
          data: body,
          options: Options(method: method),
        );
    }
  }

  await sr.smartRequest<Response<dynamic>>(
    () => operation(),
    fallback: () => dio.get(url),
    config: sr.SmartRequestConfig(
      maxRetries: cfg.maxRetries,
      initialDelay: Duration(milliseconds: cfg.initialDelayMs),
      maxDelay: Duration(milliseconds: cfg.maxDelayMs),
      backoffFactor: cfg.backoffFactor,
      jitter: cfg.jitter,
      timeout: Duration(milliseconds: cfg.timeoutMs),
      onError: (Object e, StackTrace s) {},
      onRetry: (int attempt, Duration nextDelay, Object e, StackTrace s) {},
      shouldRetry: (_) => true,
    ),
  );
}
