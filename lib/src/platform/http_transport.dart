import 'dart:convert';
import 'dart:io';
import '../core/info.dart';
import '../core/ports.dart';

/// Ephemeral requests, no redirects, cookies or implicit application User-Agent.
class IoTransport implements PulseTransport {
  IoTransport({this.timeout});
  final Duration? timeout;
  final _clients = <HttpClient>{};
  @override
  Future<PulseResponse> send(PulseRequest input) async {
    final duration =
        timeout ?? Duration(seconds: 10 + input.body.length ~/ 16384);
    final client = HttpClient()
      ..connectionTimeout = duration
      ..autoUncompress = false
      ..userAgent = '${PulseInfo.sdkName}/${PulseInfo.version}';
    _clients.add(client);
    try {
      return await _send(client, input).timeout(duration);
    } catch (_) {
      return const PulseResponse(0);
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Future<PulseResponse> _send(HttpClient client, PulseRequest input) async {
    final request = await client.postUrl(input.url);
    request.followRedirects = false;
    request.headers.set('X-App-Key', input.appKey);
    request.headers.contentType = ContentType.json;
    if (input.gzip) {
      request.headers.set('Content-Encoding', 'gzip');
    }
    request.contentLength = input.body.length;
    request.add(input.body);
    final response = await request.close();
    final after = response.headers.value('Retry-After');
    final body = <int>[];
    await for (final chunk in response) {
      if (body.length + chunk.length > 65536) {
        return PulseResponse(response.statusCode, retryAfter: after);
      }
      body.addAll(chunk);
    }
    return PulseResponse(
      response.statusCode,
      body: utf8.decode(body, allowMalformed: true),
      retryAfter: after,
    );
  }

  @override
  Future<PulseResponse> get(
    Uri url,
    String appKey, {
    String? ifNoneMatch,
  }) async {
    final duration = timeout ?? const Duration(seconds: 10);
    final client = HttpClient()
      ..connectionTimeout = duration
      ..autoUncompress = false
      ..userAgent = '${PulseInfo.sdkName}/${PulseInfo.version}';
    _clients.add(client);
    try {
      return await _get(client, url, appKey, ifNoneMatch).timeout(duration);
    } catch (_) {
      return const PulseResponse(0);
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Future<PulseResponse> _get(
    HttpClient client,
    Uri url,
    String appKey,
    String? ifNoneMatch,
  ) async {
    final request = await client.getUrl(url);
    request.followRedirects = false;
    request.headers.set('X-App-Key', appKey);
    request.headers.set('Accept', 'application/json');
    if (ifNoneMatch != null) {
      request.headers.set('If-None-Match', ifNoneMatch);
    }
    final response = await request.close();
    final body = <int>[];
    await for (final chunk in response) {
      if (body.length + chunk.length > 65536) {
        return PulseResponse(response.statusCode);
      }
      body.addAll(chunk);
    }
    return PulseResponse(
      response.statusCode,
      body: utf8.decode(body, allowMalformed: true),
    );
  }

  @override
  void cancel() {
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
  }
}
