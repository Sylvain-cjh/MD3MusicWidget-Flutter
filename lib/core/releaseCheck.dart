import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';



abstract final class ReleaseCheck {
  static final _endpoint = Uri.https(
    'api.github.com',
    '/repos/Sylvain-cjh/MD3MusicWidget-Flutter/releases/latest',
  );
  static const _maxResponseBytes = 1024 * 1024;
  static final _version = RegExp(
    r'^[vV]?(\d+(?:\.\d+){1,3})(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );

  static Future<String?> fetchLatestTag() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await _request(client).timeout(const Duration(seconds: 8));
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _request(HttpClient client) async {
    final request = await client.getUrl(_endpoint);
    request.followRedirects = false;
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'MD3MusicWidget');
    final response = await request.close();
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Release lookup failed: ${response.statusCode}');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > _maxResponseBytes) {
        throw const FormatException('Release response is too large');
      }
      bytes.add(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (data is! Map ||
        data['draft'] != false ||
        data['prerelease'] != false ||
        data['tag_name'] is! String) {
      throw const FormatException('Invalid stable release response');
    }
    return data['tag_name'] as String;
  }

  
  
  
  static bool isNewer(String tag, String current) {
    final latest = _version.firstMatch(tag.trim());
    final installed = _version.firstMatch(current.trim());
    if (latest == null || latest.group(2) != null || installed == null) {
      throw const FormatException('Invalid version identifier');
    }
    final a = latest.group(1)!.split('.').map(int.parse).toList();
    final b = installed.group(1)!.split('.').map(int.parse).toList();
    for (var i = 0; i < 4; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return installed.group(2) != null;
  }
}
