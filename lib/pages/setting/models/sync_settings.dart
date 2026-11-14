import 'package:PiliPlus/common/widgets/dialog/export_import.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/github_sync_dialog.dart';
import 'package:PiliPlus/pages/webdav/view.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

/// 同步设置：WebDAV、GitHub 仓库 / Pages、本地归档
List<SettingsModel> get syncSettings => [
  NormalModel(
    title: 'WebDAV 设置',
    leading: const Icon(MdiIcons.databaseCogOutline),
    getSubtitle: () {
      final uri = Pref.webdavUri;
      return uri.isEmpty ? '未配置服务器' : uri;
    },
    onTap: (context, _) => Get.to(() => const WebDavSettingPage()),
  ),
  NormalModel(
    title: 'GitHub 设置同步',
    leading: const Icon(Icons.cloud_outlined),
    getSubtitle: () {
      final repo = Pref.githubSyncRepo;
      return repo.isEmpty
          ? '上传到仓库，或从仓库 / Pages 链接下载'
          : '仓库：$repo';
    },
    onTap: (context, _) => showGithubSyncDialog(context),
  ),
  NormalModel(
    title: '导出 / 导入设置',
    leading: const Icon(Icons.import_export),
    subtitle: '保存为本地 zip 归档，或从归档恢复',
    onTap: (context, _) => showDataImportExportDialog(context),
  ),
];
