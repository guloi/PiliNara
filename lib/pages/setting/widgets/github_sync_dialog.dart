import 'dart:typed_data';

import 'package:PiliPlus/utils/config_archive.dart';
import 'package:PiliPlus/utils/github_config_sync.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 打开「GitHub 设置同步」对话框。
Future<void> showGithubSyncDialog(BuildContext context) => showDialog(
  context: context,
  builder: (_) => const GithubSyncDialog(),
);

/// 把设置上传到 GitHub 仓库 / 从仓库或 Pages 链接下载并导入。
///
/// 归档格式与「导入/导出所有数据 → 导出到压缩包」完全一致
/// （见 [ConfigArchive]），因此云端文件也能用现有功能导入。
class GithubSyncDialog extends StatefulWidget {
  const GithubSyncDialog({super.key});

  @override
  State<GithubSyncDialog> createState() => _GithubSyncDialogState();
}

class _GithubSyncDialogState extends State<GithubSyncDialog> {
  late final TextEditingController _repo = TextEditingController(
    text: Pref.githubSyncRepo,
  );
  late final TextEditingController _branch = TextEditingController(
    text: Pref.githubSyncBranch,
  );
  late final TextEditingController _path = TextEditingController(
    text: Pref.githubSyncPath,
  );
  late final TextEditingController _token = TextEditingController(
    text: Pref.githubSyncToken,
  );
  late final TextEditingController _url = TextEditingController(
    text: Pref.githubSyncPagesUrl,
  );

  bool _busy = false;
  bool _hideToken = true;

  @override
  void dispose() {
    _save();
    for (final controller in [_repo, _branch, _path, _token, _url]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    Pref.githubSyncRepo = _repo.text.trim();
    Pref.githubSyncBranch = _branch.text.trim();
    Pref.githubSyncPath =
        GithubConfigSync.normalizePath(_path.text) ?? _path.text.trim();
    Pref.githubSyncToken = _token.text.trim();
    Pref.githubSyncPagesUrl = _url.text.trim();
  }

  void _toast(String message) => SmartDialog.showToast(message);

  Future<void> _upload() async {
    if (_busy) return;
    final repo = _repo.text.trim();
    final path = GithubConfigSync.normalizePath(_path.text);
    final error = GithubConfigSync.checkRepo(repo) ??
        (path == null ? '文件路径不能为空，且不能以 / 结尾' : null);
    if (error != null) {
      _toast(error);
      return;
    }
    _save();
    setState(() => _busy = true);
    SmartDialog.showLoading(msg: '上传中…');
    final result = await GithubConfigSync.upload(
      repo: repo,
      path: path!,
      branch: _branch.text,
      token: _token.text,
    );
    SmartDialog.dismiss();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) {
      _toast('已上传到 $repo/$path');
    } else {
      _toast(result);
    }
  }

  Future<void> _downloadFromRepo() async {
    if (_busy) return;
    final repo = _repo.text.trim();
    final path = GithubConfigSync.normalizePath(_path.text);
    final error = GithubConfigSync.checkRepo(repo) ??
        (path == null ? '文件路径不能为空，且不能以 / 结尾' : null);
    if (error != null) {
      _toast(error);
      return;
    }
    _save();
    setState(() => _busy = true);
    SmartDialog.showLoading(msg: '下载中…');
    final result = await GithubConfigSync.download(
      repo: repo,
      path: path!,
      branch: _branch.text,
      token: _token.text,
    );
    SmartDialog.dismiss();
    if (!mounted) return;
    setState(() => _busy = false);
    await _handleDownload(result);
  }

  Future<void> _downloadFromUrl() async {
    if (_busy) return;
    final url = _url.text.trim();
    if (url.isEmpty) {
      _toast('请填写链接（例如 GitHub Pages 上的 zip）');
      return;
    }
    _save();
    setState(() => _busy = true);
    SmartDialog.showLoading(msg: '下载中…');
    final result = await GithubConfigSync.downloadFromUrl(url);
    SmartDialog.dismiss();
    if (!mounted) return;
    setState(() => _busy = false);
    await _handleDownload(result);
  }

  Future<void> _handleDownload(GithubSyncResult result) async {
    if (!result.ok) {
      _toast(result.error!);
      return;
    }
    final bytes = result.bytes!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用云端归档覆盖当前数据？'),
        content: Text(
          '将导入 ${(bytes.length / 1024).toStringAsFixed(1)} KB 的归档，'
          '覆盖当前设置、账号信息、历史评论、搜索记录、黑名单与自定义字体，'
          '此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '取消',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _import(bytes);
  }

  Future<void> _import(Uint8List bytes) async {
    setState(() => _busy = true);
    SmartDialog.showLoading(msg: '导入中…');
    String? importResult;
    Object? failure;
    try {
      importResult = await ConfigArchive.import(
        bytes,
        onWarning: (warning) async {
          SmartDialog.dismiss();
          if (!mounted) return false;
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('注意'),
              content: Text(warning),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    '取消',
                    style: TextStyle(color: ColorScheme.of(context).outline),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('继续'),
                ),
              ],
            ),
          );
          if (ok == true) SmartDialog.showLoading(msg: '导入中…');
          return ok == true;
        },
      );
    } catch (e) {
      failure = e;
    }
    SmartDialog.dismiss();
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      _toast('导入失败：$failure');
      return;
    }
    if (importResult == null) return;
    _toast(importResult.isEmpty ? '导入成功' : '导入成功，但$importResult');
  }

  /// 由仓库与文件路径推导默认的 GitHub Pages 地址。
  void _derivePagesUrl() {
    final repo = _repo.text.trim();
    final path = GithubConfigSync.normalizePath(_path.text);
    final error = GithubConfigSync.checkRepo(repo) ??
        (path == null ? '文件路径不能为空，且不能以 / 结尾' : null);
    if (error != null) {
      _toast(error);
      return;
    }
    final parts = repo.split('/');
    _url.text =
        'https://${parts[0].toLowerCase()}.github.io/${parts[1]}/$path';
    setState(() {});
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    Widget? suffix,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      suffixIcon: suffix,
      border: const OutlineInputBorder(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return AlertDialog(
      title: const Text('GitHub 设置同步'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                controller: _repo,
                label: '仓库',
                hint: 'owner/repo',
              ),
              const SizedBox(height: 12),
              _field(
                controller: _branch,
                label: '分支',
                hint: '留空则使用仓库默认分支',
              ),
              const SizedBox(height: 12),
              _field(
                controller: _path,
                label: '文件路径',
                hint: '例如 piliruao/settings.zip',
              ),
              const SizedBox(height: 12),
              _field(
                controller: _token,
                label: 'Token（可选）',
                hint: '上传必填；下载公开仓库可留空',
                obscure: _hideToken,
                suffix: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _hideToken = !_hideToken),
                  icon: Icon(
                    _hideToken ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _field(
                controller: _url,
                label: 'Pages 链接（可选）',
                hint: 'https://user.github.io/repo/settings.zip',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy ? null : _derivePagesUrl,
                  child: const Text('按仓库推导链接'),
                ),
              ),
              Text(
                '归档格式与「导出到压缩包」相同（zip），包含设置、账号、黑名单、'
                '搜索记录与自定义字体。Token 以明文保存在本地设置中。',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('上传当前设置到仓库'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _downloadFromRepo,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('从仓库下载并导入'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _downloadFromUrl,
                icon: const Icon(Icons.link),
                label: const Text('从链接下载并导入'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
