import 'dart:convert' show base64Encode;
import 'dart:typed_data';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/utils/config_archive.dart';
import 'package:archive/archive.dart' show OutputMemoryStream;
import 'package:dio/dio.dart';

/// 同步结果：`error == null` 表示成功，此时 [bytes] 为归档字节。
class GithubSyncResult {
  const GithubSyncResult.ok(this.bytes) : error = null;

  const GithubSyncResult.fail(this.error) : bytes = null;

  final Uint8List? bytes;
  final String? error;

  bool get ok => error == null;
}

/// 把设置同步到 GitHub，复用 [ConfigArchive] 的 zip 归档格式。
///
/// - 上传：`PUT /repos/{repo}/contents/{path}`，文件不存在时新建、存在时按
///   已有 sha 更新；
/// - 从仓库下载：同一个 Contents 接口的 `application/vnd.github.raw`；
/// - 从链接下载：GitHub Pages 等任意可直链的 zip。
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

  /// 生成与「导出到压缩包」完全一致的 zip 字节。
  static Uint8List buildArchive() {
    final out = OutputMemoryStream();
    ConfigArchive.export(out);
    final bytes = out.getBytes();
    out.closeSync();
    return bytes;
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

      final bytes = buildArchive();
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

  /// 从仓库下载归档字节。
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
      return const GithubSyncResult.fail('归档超过 64MB，拒绝导入');
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
