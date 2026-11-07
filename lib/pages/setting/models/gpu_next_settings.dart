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
        subtitle: 'SDR 走纹理，HDR / 杜比视界走原生 SurfaceView。重新加载视频后生效。',
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
          subtitle: Pref.gpuNextSplitHdr
              ? '下面的分流开关已开启：HDR / 杜比视界固定走 gpu-next OpenGL，这里不再生效。'
              : api == GpuNextApi.opengl
              ? '建议保持开启，否则 HDR / 杜比视界会被映射成 SDR。'
              : '开启后 HDR / 杜比视界走 MediaCodec 直通，SDR 走 gpu-next。',
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
          title: 'SDR 走 Vulkan，HDR / 杜比视界走 OpenGL',
          subtitle:
              'Vulkan 在 Android 上只拿得到线性缓冲，全屏 / 横屏旋转 10bit 图层时会被系统退回 GPU 合成，画面发暗；'
              'EGL 走 gralloc（UBWC），HWC 能直接合成。开启后按片源分流，重新加载视频后生效。',
          leading: const Icon(Icons.compare_arrows),
          setKey: SettingBoxKey.gpuNextSplitHdr,
          defaultVal: false,
          onChanged: (_) {
            PlPlayerController.instance?.applyHdrOptions();
            setState(() {});
          },
        ),
      if (Pref.defaultGpuNext)
        NormalModel(
          title: '杜比视界 profile 5 回退方式',
          leading: const Icon(Icons.hdr_plus_outlined),
          getSubtitle: () {
            final fallback = GpuNextDoviFallback.fromValue(
              Pref.gpuNextDoviFallback,
            );
            return '当前：${fallback.label}。Vulkan 不可用或渲染 API 为 OpenGL 时使用';
          },
          onTap: _showGpuNextDoviFallbackDialog,
        ),
      if (Pref.defaultGpuNext)
        SwitchModel(
          title: '杜比视界 profile 5 软解',
          subtitle: '开启：gpu-next 软解，色彩正确；关闭：切回 MediaCodec 直通，靠设备自身杜比视界能力出画。',
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

  Future<void> _showGpuNextDoviFallbackDialog(
    BuildContext context,
    VoidCallback setState,
  ) async {
    final res = await showDialog<String>(
      context: context,
      builder: (context) => SelectDialog<String>(
        title: '杜比视界 profile 5 回退方式',
        value: Pref.gpuNextDoviFallback,
        values: GpuNextDoviFallback.values
            .map((e) => (e.value, e.label))
            .toList(),
        subtitleBuilder: (context, index) => Text(
          GpuNextDoviFallback.values[index].desc,
          style: TextTheme.of(context).labelSmall?.copyWith(
            color: ColorScheme.of(context).outline,
          ),
        ),
      ),
    );
    if (res != null) {
      await GStorage.setting.put(SettingBoxKey.gpuNextDoviFallback, res);
      PlPlayerController.resetVulkanFallback();
      PlPlayerController.instance?.applyHdrOptions();
      setState();
    }
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
