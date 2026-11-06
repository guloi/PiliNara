import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/hdr_config.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 「默认 gpu-next」专项设置页。
///
/// 从「音视频设置」进入，进入方式与 HDR 设置相同：点按同层级的条目。
/// 开启总开关后才会显示「渲染 API」与「HDR / 杜比视界时切回 MediaCodec」等子选项。
class GpuNextSettingsPage extends StatefulWidget {
  const GpuNextSettingsPage({super.key});

  @override
  State<GpuNextSettingsPage> createState() => _GpuNextSettingsPageState();
}

class _GpuNextSettingsPageState extends State<GpuNextSettingsPage> {
  @override
  Widget build(BuildContext context) {
    // 每次 build 重新组装列表，开关切换后子选项才能立即出现/消失。
    final api = GpuNextApi.fromValue(Pref.gpuNextApi);
    final items = <SettingsModel>[
      SwitchModel(
        title: '默认 gpu-next',
        subtitle:
            '所有片源默认使用 gpu-next（libplacebo）渲染：SDR 走纹理出画，'
            'HDR / 杜比视界走原生 SurfaceView。开启后 HDR 设置里的「HDR 渲染后端」'
            '对 HDR / 杜比视界片源失效，改由下面的子选项决定。'
            '正在播放的视频需重新加载后才会切换出画方式。',
        leading: const Icon(Icons.auto_awesome_outlined),
        setKey: SettingBoxKey.defaultGpuNext,
        defaultVal: false,
        onChanged: (_) {
          PlPlayerController.instance?.applyHdrOptions();
          setState(() {});
        },
      ),
      if (Pref.defaultGpuNext)
        NormalModel(
          title: '渲染 API',
          leading: const Icon(Icons.memory_outlined),
          getSubtitle: () => '当前：${api.label}。${api.desc}',
          onTap: _showGpuNextApiDialog,
        ),
      if (Pref.defaultGpuNext)
        SwitchModel(
          title: 'HDR / 杜比视界时切回 MediaCodec',
          subtitle: api == GpuNextApi.opengl
              ? '渲染 API 为 OpenGL 时建议保持开启：EGL 没有 HDR 交换链，'
                    'HDR / 杜比视界只有交给 MediaCodec 直通才能真正激发；'
                    '关闭后这类片源会被 libplacebo 映射成 SDR。'
                    '杜比视界 profile 5 例外：它始终走 gpu-next，否则会偏色。'
              : 'HDR / 杜比视界片源改用 MediaCodec 直通出画'
                    '（mediacodec_embed），只让 SDR 片源走 gpu-next。'
                    '关闭时 HDR / 杜比视界也交给 gpu-next 处理。'
                    '杜比视界 profile 5 例外：它始终走 gpu-next，否则会偏色。',
          leading: const Icon(Icons.hdr_on),
          setKey: SettingBoxKey.gpuNextHdrMediaCodec,
          defaultVal: true,
          onChanged: (_) {
            PlPlayerController.instance?.applyHdrOptions();
            setState(() {});
          },
        ),
      if (Pref.defaultGpuNext)
        SwitchModel(
          title: '杜比视界 profile 5 软解',
          subtitle:
              'profile 5 的色彩要靠杜比视界 RPU 元数据还原，硬解拷贝拿不到这些元数据'
              '会导致整体偏色；这类片源始终走 gpu-next（不受上一项影响）。'
              '开启后改用软解渲染（更吃性能），关闭则用硬件拷贝解码。',
          leading: const Icon(Icons.color_lens_outlined),
          setKey: SettingBoxKey.gpuNextDoviSoft,
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

  Future<void> _showGpuNextApiDialog(
    BuildContext context,
    VoidCallback setState,
  ) async {
    final res = await showDialog<String>(
      context: context,
      builder: (context) => SelectDialog<String>(
        title: '渲染 API',
        value: Pref.gpuNextApi,
        values: GpuNextApi.values.map((e) => (e.value, e.label)).toList(),
        subtitleBuilder: (context, index) => Text(
          GpuNextApi.values[index].desc,
          style: TextTheme.of(context).labelSmall?.copyWith(
            color: ColorScheme.of(context).outline,
          ),
        ),
      ),
    );
    if (res != null) {
      await GStorage.setting.put(SettingBoxKey.gpuNextApi, res);
      PlPlayerController.resetVulkanFallback();
      PlPlayerController.instance?.applyHdrOptions();
      setState();
    }
  }
}
