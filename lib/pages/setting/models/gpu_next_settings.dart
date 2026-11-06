import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 「默认 gpu-next」专项设置页。
///
/// 从「音视频设置」进入，进入方式与 HDR 设置相同：点按同层级的条目。
/// 开启总开关后才会显示「HDR / 杜比视界时切回 MediaCodec」子开关。
class GpuNextSettingsPage extends StatefulWidget {
  const GpuNextSettingsPage({super.key});

  @override
  State<GpuNextSettingsPage> createState() => _GpuNextSettingsPageState();
}

class _GpuNextSettingsPageState extends State<GpuNextSettingsPage> {
  @override
  Widget build(BuildContext context) {
    // 每次 build 重新组装列表，开关切换后子选项才能立即出现/消失。
    final items = <SettingsModel>[
      SwitchModel(
        title: '默认 gpu-next',
        subtitle:
            '所有片源默认使用 gpu-next（libplacebo）渲染：SDR 走纹理 '
            'gpu-next OpenGL，HDR / 杜比视界走原生 SurfaceView。'
            '开启后 HDR 设置里的「HDR 渲染后端」对 HDR / 杜比视界片源失效，'
            '改由下面的子开关决定。正在播放的视频需重新加载后才会切换出画方式。',
        leading: const Icon(Icons.auto_awesome_outlined),
        setKey: SettingBoxKey.defaultGpuNext,
        defaultVal: false,
        onChanged: (_) {
          PlPlayerController.instance?.applyHdrOptions();
          setState(() {});
        },
      ),
      if (Pref.defaultGpuNext)
        SwitchModel(
          title: 'HDR / 杜比视界时切回 MediaCodec',
          subtitle:
              'HDR / 杜比视界片源改用 MediaCodec 直通出画'
              '（mediacodec_embed），只让 SDR 片源走 gpu-next。'
              '关闭时 HDR / 杜比视界也交给 gpu-next 处理。',
          leading: const Icon(Icons.hdr_on),
          setKey: SettingBoxKey.gpuNextHdrMediaCodec,
          defaultVal: true,
          onChanged: (_) {
            PlPlayerController.instance?.applyHdrOptions();
            setState(() {});
          },
        ),
    ];
    return SimpleScaffold(
      appBar: AppBar(title: const Text('默认 gpu-next')),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: items.length,
        itemBuilder: (context, index) => items[index].widget,
      ),
    );
  }
}
