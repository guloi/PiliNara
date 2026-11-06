import 'package:PiliPlus/pages/setting/widgets/switch_item.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

Future<void> portraitSlideDialog(BuildContext context) async {
  var subtreeKey = UniqueKey();

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        title: const Text('竖屏即刷'),
        contentPadding: const EdgeInsets.only(top: 8, bottom: 4),
        content: SingleChildScrollView(
          child: KeyedSubtree(
            key: subtreeKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 24),
                  leading: Icon(Icons.swipe_up_outlined),
                  title: Text('竖屏视频全屏播放时'),
                  subtitle: Text('上滑播放推荐的竖屏视频，下滑回到上一个视频'),
                ),
                SetSwitchItem(
                  title: '推荐来源使用首页推荐',
                  subtitle: Pref.portraitRC
                      ? '当前：首页推荐（可刷到的视频可能变少）'
                      : '当前：当前视频的相关推荐',
                  setKey: SettingBoxKey.portraitRC,
                  defaultVal: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  onChanged: (_) => setState(() {}),
                ),
                SetSwitchItem(
                  title: '随机视频',
                  subtitle: Pref.portraitRandom
                      ? '当前：从推荐池里随机挑一个竖屏视频'
                      : '当前：按推荐顺序依次刷',
                  setKey: SettingBoxKey.portraitRandom,
                  defaultVal: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  onChanged: (_) => setState(() {}),
                ),
                const SetSwitchItem(
                  title: '刷新推荐',
                  subtitle: '没有更多竖屏视频时，重新取一次推荐',
                  setKey: SettingBoxKey.portraitNewv,
                  defaultVal: false,
                  contentPadding: EdgeInsets.symmetric(horizontal: 24),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () async {
              await GStorage.setting.put(SettingBoxKey.portraitRC, false);
              await GStorage.setting.put(SettingBoxKey.portraitNewv, false);
              await GStorage.setting.put(SettingBoxKey.portraitRandom, false);

              setState(() => subtreeKey = UniqueKey());
            },
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    ),
  );
}
