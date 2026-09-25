import 'dart:convert';
import 'dart:io';

import '../app_info.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseUrl,
    this.downloadUrl,
  });

  final String version;
  final String releaseUrl;
  final String? downloadUrl;
}

class UpdateService {
  Future<UpdateInfo?> checkForUpdate() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.https('api.github.com', '/repos/Reedboot/Dayforge/releases'),
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Dayforge/$appVersion');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub returned HTTP ${response.statusCode}.');
      }

      final releases = jsonDecode(
        await response.transform(utf8.decoder).join(),
      );
      if (releases is! List) {
        throw const FormatException('GitHub returned an invalid release list.');
      }
      for (final value in releases) {
        if (value is! Map) continue;
        final tag = value['tag_name'];
        final url = value['html_url'];
        if (tag is! String || url is! String || !tag.startsWith('v')) {
          continue;
        }
        final version = tag.substring(1);
        if (!_isNewer(version, appVersion)) continue;
        return UpdateInfo(
          version: version,
          releaseUrl: url,
          downloadUrl: _assetUrl(value['assets']),
        );
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  bool _isNewer(String candidate, String current) {
    final candidateParts = _versionParts(candidate);
    final currentParts = _versionParts(current);
    for (var index = 0; index < 3; index++) {
      if (candidateParts[index] != currentParts[index]) {
        return candidateParts[index] > currentParts[index];
      }
    }
    return false;
  }

  List<int> _versionParts(String version) {
    final parts = version.split('.');
    return List<int>.generate(
      3,
      (index) => index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0,
    );
  }

  String? _assetUrl(Object? assets) {
    if (assets is! List) return null;
    final expectedName = switch (Platform.operatingSystem) {
      'android' => 'Dayforge-android-preview.apk',
      'windows' => 'Dayforge-windows-x64.zip',
      'linux' => 'Dayforge-linux-x64.tar.gz',
      _ => null,
    };
    if (expectedName == null) return null;
    for (final asset in assets) {
      if (asset is Map &&
          asset['name'] == expectedName &&
          asset['browser_download_url'] is String) {
        return asset['browser_download_url'] as String;
      }
    }
    return null;
  }
}
