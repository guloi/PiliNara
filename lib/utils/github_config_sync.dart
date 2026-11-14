import 'dart:convert' show base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:typed_data';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';

/// 同步结果：`error == null` 表示成功，此时 [bytes] 为下载到的文件字节。
class GithubSyncResult {
  const GithubSyncResult.ok(this.bytes) : error = null;

  const GithubSyncResult.fail(this.error) : bytes = null;

  final Uint8List? bytes;
  final String? error;

  bool get ok => error == null;
}

/// 把设置同步到 GitHub（只同步 `setting.json`，不含账号、黑名单、字体）。
///
/// - 上传：`PUT /repos/{repo}/contents/{path}`，文件不存在时新建、存在时按
///   已有 sha 更新；
/// - 从仓库下载：同一个 Contents 接口的 `application/vnd.github.raw`；
/// - 从链接下载：GitHub Pages 等任意可直链的地址；内容若是早先导出的 zip
///   归档，仍走 ConfigArchive（见调用方）。
///
/// 隐私：上传前剔除 [sensitiveSettingKeys]（Token、API Key、WebDAV 地址与账号密码、
/// buvid、同步仓库地址）；导入后把这些键恢复成本机原来的值，不会被云端覆盖。
///
/// 全程使用独立的 [Dio]：GitHub 不是 B 站接口，不能走带拦截器的
/// `Request()` 单例（参见 `cdn_node_store.dart`）。
abstract final class GithubConfigSync {
  static const String _apiBase = 'https://api.github.com';
  static const Duration _timeout = Duration(seconds: 30);

  /// 与 [ConfigArchive] 的上限保持一致。
  static const int _maxBytes = 64 * 1024 * 1024;
  static const String _commitMessage = 'chore(settings): 由 piliruao 同步设置';

  static final RegExp _repoPattern = RegExp(
    r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
  );

  /// 只存本机、不参与云同步的设置项。
  ///
  /// 目标是「云端文件泄露也不至于泄露账号/设备标识」：Token、AI 的 API Key、
  /// WebDAV 的地址与账号密码、buvid（B 站设备指纹）、同步用的仓库地址。
  /// 换设备时重新填一次即可。
  static const Set<String> sensitiveSettingKeys = {
    SettingBoxKey.aiApiKey,
    SettingBoxKey.buvid,
    SettingBoxKey.githubSyncRepo,
    SettingBoxKey.githubSyncToken,
    SettingBoxKey.webdavPassword,
    SettingBoxKey.webdavUri,
    SettingBoxKey.webdavUsername,
  };

  /// 生成待上传的 `setting.json` 字节：与「导出设置」同一份数据，但剔除凭据。
  static Uint8List buildSettingsJson() {
    final data =
        jsonDecode(GStorage.exportAllSettings()) as Map<String, dynamic>;
    final settings = data[GStorage.setting.name];
    if (settings is Map) {
      settings.removeWhere(
        (key, _) => sensitiveSettingKeys.contains(key),
      );
    }
    return Uint8List.fromList(utf8.encode(jsonEncode(data)));
  }

  /// 判断下载内容是 zip 归档（早先版本用「导出到压缩包」上传）。
  static bool isZipArchive(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07);

  /// 导入 `setting.json`：成功返回 null，失败返回提示文案。
  ///
  /// 与 [GStorage.importAllJsonSettings] 的区别是：导入前备份本机的
  /// [sensitiveSettingKeys]，导入（它会 clear 整个 setting box）后写回，
  /// 因此云端内容不会覆盖本机保存的 Token / API Key / WebDAV 账号密码。
  static Future<String?> importSettingsJson(Uint8List bytes) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return '文件不是有效的 JSON';
    }
    if (decoded is! Map<String, dynamic>) return '文件不是设置文件';
    final settings = decoded[GStorage.setting.name];
    if (settings is! Map<String, dynamic>) {
      return '文件缺少 ${GStorage.setting.name} 字段';
    }
    final video = decoded[GStorage.video.name];
    if (video is! Map<String, dynamic>) {
      return '文件缺少 ${GStorage.video.name} 字段';
    }
    // 上传端已经剔除过，这里再兜一次：兼容手工编辑或第三方生成的文件。
    settings.removeWhere((key, _) => sensitiveSettingKeys.contains(key));

    final local = <String, dynamic>{};
    for (final key in sensitiveSettingKeys) {
      final value = GStorage.setting.get(key);
      if (value != null) local[key] = value;
    }
    await GStorage.importAllJsonSettings(decoded);
    if (local.isNotEmpty) await GStorage.setting.putAll(local);
    return null;
  }

  /// 仓库为空或格式不对时返回错误文案。
  static String? checkRepo(String repo) {
    final value = repo.trim();
    if (value.isEmpty) return '请先填写仓库（owner/repo）';
    if (!_repoPattern.hasMatch(value)) return '仓库格式应为 owner/repo';
    return null;
  }

  /// 规范化文件路径：去掉首尾空白与前导 `/`；不合法时返回 null。
  static String? normalizePath(String path) {
    var value = path.trim();
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    if (value.isEmpty || value.endsWith('/')) return null;
    return value;
  }

  /// 上传当前设置，成功返回 null，失败返回提示文案。
  static Future<String?> upload({
    required String repo,
    required String path,
    String branch = '',
    String token = '',
  }) async {
    final repoError = checkRepo(repo);
    if (repoError != null) return repoError;
    final normalized = normalizePath(path);
    if (normalized == null) return '文件路径不能为空，且不能以 / 结尾';
    if (token.trim().isEmpty) return '上传需要填写 Token（需 repo 读写权限）';

    final url = _contentsUrl(repo.trim(), normalized);
    final ref = branch.trim();
    final dio = _dio(token: token);
    try {
      // Contents API 更新已有文件必须带 sha，先查一次。
      final existing = await dio.get<dynamic>(
        url,
        queryParameters: ref.isEmpty ? null : {'ref': ref},
      );
      final code = existing.statusCode ?? 0;
      String? sha;
      if (code == 200) {
        final data = existing.data;
        if (data is! Map) return '目标路径是一个目录，请填写文件名';
        sha = data['sha'] as String?;
      } else if (code != 404) {
        return _statusMessage(code);
      }

      final bytes = buildSettingsJson();
      final res = await dio.put<dynamic>(
        url,
        data: {
          'message': _commitMessage,
          'content': base64Encode(bytes),
          if (sha != null) 'sha': sha,
          if (ref.isNotEmpty) 'branch': ref,
        },
      );
      final putCode = res.statusCode ?? 0;
      if (putCode == 201 || putCode == 200) return null;
      if (putCode == 422) return '上传被拒绝：文件过大，或分支不存在';
      return _statusMessage(putCode);
    } catch (e) {
      return '上传失败：$e';
    } finally {
      dio.close(force: true);
    }
  }

  /// 从仓库下载文件字节。
  static Future<GithubSyncResult> download({
    required String repo,
    required String path,
    String branch = '',
    String token = '',
  }) async {
    final repoError = checkRepo(repo);
    if (repoError != null) return GithubSyncResult.fail(repoError);
    final normalized = normalizePath(path);
    if (normalized == null) {
      return const GithubSyncResult.fail('文件路径不能为空，且不能以 / 结尾');
    }

    final ref = branch.trim();
    final dio = _dio(token: token, responseType: ResponseType.bytes);
    try {
      final res = await dio.get<List<int>>(
        _contentsUrl(repo.trim(), normalized),
        queryParameters: ref.isEmpty ? null : {'ref': ref},
        options: Options(
          headers: {'accept': 'application/vnd.github.raw'},
        ),
      );
      final code = res.statusCode ?? 0;
      if (code == 404) return GithubSyncResult.fail('文件不存在：$normalized');
      if (code != 200) return GithubSyncResult.fail(_statusMessage(code));
      return _fromBytes(res.data);
    } catch (e) {
      return GithubSyncResult.fail('下载失败：$e');
    } finally {
      dio.close(force: true);
    }
  }

  /// 从任意直链下载（GitHub Pages、jsDelivr 等）。
  static Future<GithubSyncResult> downloadFromUrl(String url) async {
    final value = url.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return const GithubSyncResult.fail('请填写 http(s) 开头的链接');
    }
    final dio = _dio(responseType: ResponseType.bytes);
    try {
      final res = await dio.get<List<int>>(value);
      final code = res.statusCode ?? 0;
      if (code != 200) return GithubSyncResult.fail('下载失败：HTTP $code');
      return _fromBytes(res.data);
    } catch (e) {
      return GithubSyncResult.fail('下载失败：$e');
    } finally {
      dio.close(force: true);
    }
  }

  static GithubSyncResult _fromBytes(List<int>? data) {
    if (data == null || data.isEmpty) {
      return const GithubSyncResult.fail('下载到的内容为空');
    }
    if (data.length > _maxBytes) {
      return const GithubSyncResult.fail('下载内容超过 64MB，拒绝导入');
    }
    return GithubSyncResult.ok(Uint8List.fromList(data));
  }

  static String _contentsUrl(String repo, String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return '$_apiBase/repos/$repo/contents/$encoded';
  }

  static String _statusMessage(int code) {
    switch (code) {
      case 401:
        return 'Token 无效或已过期';
      case 403:
        return '没有权限（Token 需要 repo 权限），或触发了速率限制';
      case 404:
        return '仓库或分支不存在，或 Token 无权访问';
      case 409:
        return '文件冲突，请重试';
      case 422:
        return '文件过大，或参数不被接受';
      default:
        return 'GitHub 返回 HTTP $code';
    }
  }

  static Dio _dio({
    String token = '',
    ResponseType responseType = ResponseType.json,
  }) {
    final headers = <String, String>{
      'user-agent': BrowserUa.pc,
      'accept': 'application/vnd.github+json',
    };
    final value = token.trim();
    if (value.isNotEmpty) {
      headers['authorization'] = 'Bearer $value';
    }
    return Dio(
      BaseOptions(
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        sendTimeout: _timeout,
        responseType: responseType,
        headers: headers,
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (_) => true,
      ),
    );
  }
}
