import 'dart:io' show Platform;

import 'package:PiliPlus/utils/storage_pref.dart';

/// HDR 输出模式。
///
/// 注意：这些模式只影响 mpv 的色彩处理参数，**不会**切换视频输出驱动
/// （`--vo`）。media_kit 依赖 `--vo=libmpv`（桌面）与 `--vo=gpu`（Android）
/// 把画面交给 Flutter 纹理，改动 `--vo` 会直接黑屏。
enum HdrOutputMode {
  /// 按片源自动决定：HDR 片源做色调映射，SDR 片源保持原样。
  auto('auto', '自动（色调映射）', 'HDR 片源自动做色调映射，SDR 片源保持原样'),

  /// 尝试把 HDR 元数据直通给显示端。
  passthrough('passthrough', 'HDR 直通（实验）', '尝试直通 HDR 元数据，需要渲染后端与显示设备同时支持');

  const HdrOutputMode(this.value, this.label, this.desc);

  /// 持久化到设置中的值。
  final String value;

  /// 设置页展示的名称。
  final String label;

  /// 设置页展示的说明。
  final String desc;

  static HdrOutputMode fromValue(String? value) =>
      values.firstWhere((e) => e.value == value, orElse: () => auto);
}

/// HDR 渲染后端（Android SurfaceView 出画时使用的 `--vo`）。
///
/// 不同设备的 libmpv/GPU 驱动对 10bit / HDR 输出的支持差异很大，这里提供
/// 几种可选后端，方便逐一切换验证；改完需要重新打开视频。
enum HdrBackend {
  /// libplacebo 渲染链路，走本仓库 fork 的 Android Vulkan 上下文
  /// （`gpu-api=vulkan` / `gpu-context=androidvk`）。Vulkan swapchain 可借助
  /// `VK_EXT_swapchain_colorspace` 协商 HDR 色彩空间，这是 gpu-next 真正
  /// 输出 HDR 的路径；仍属实验项，部分 ROM 还需要额外的 dataspace 支持。
  gpuNext(
    'gpu-next',
    'gpu-next',
    'gpu-next Vulkan（实验）',
    'vulkan',
    'androidvk',
    'libplacebo + Vulkan，可协商 HDR 交换链；需要带 Vulkan 且带 SPIR-V 编译器（shaderc）的 libmpv。初始化失败时 HDR 片源回退 MediaCodec 直通，其余回退 OpenGL',
  ),

  /// gpu-next 的 OpenGL/EGL 路径：libplacebo + OpenGL。
  ///
  /// 原生 Android EGL 没有 HDR 色彩空间扩展，但配合同仓库的 libmpv 补丁
  /// （挑选 10bit EGLConfig + 把窗口 dataspace 声明成 BT.2020/PQ + 让
  /// libplacebo 按调用方给的色彩空间编码）后，EGL 窗口缓冲来自 gralloc，
  /// 是 UBWC 压缩的，SurfaceFlinger 能把 HDR 图层直接交给 HWC 合成（含旋转）。
  /// 这条路径正是为了解决「Vulkan 交换链只给线性缓冲 → 旋转后被迫 CLIENT
  /// 合成 → PQ 被画进 SDR target → 画面几乎全黑」。
  gpuNextGl(
    'gpu-next-gl',
    'gpu-next',
    'gpu-next OpenGL',
    'opengl',
    'android',
    'libplacebo + OpenGL/EGL，输出 10bit BT.2020/PQ；缓冲走 EGL/gralloc（UBWC），'
        '全屏 / 横屏旋转时 HWC 可直接合成。需要打过 GL HDR 补丁的 libmpv',
  ),

  /// 传统 GPU 渲染，兼容性更好，但通常无法激发 HDR。
  gpu(
    'gpu',
    'gpu',
    'gpu（兼容模式）',
    'opengl',
    'android',
    '兼容性最好，但几乎无法激发 HDR',
  ),

  /// 由 MediaCodec 直接解码到 SurfaceView，HDR 由解码器/系统直通，
  /// 不经过 mpv 渲染，因此色调映射等参数不生效。
  /// 这是当前唯一确定能点亮面板 HDR 的后端（需要开启硬解），也是默认值。
  mediacodecEmbed(
    'mediacodec_embed',
    'mediacodec_embed',
    'MediaCodec 直通（推荐）',
    null,
    null,
    '解码器直接送显，HDR 由系统直通；需要开启硬解',
  );

  const HdrBackend(
    this.value,
    this.vo,
    this.label,
    this.gpuApi,
    this.gpuContext,
    this.desc,
  );

  /// 持久化到设置中的值。
  final String value;

  /// 传给 mpv 的 `--vo`。
  final String vo;

  /// 设置页展示的名称。
  final String label;

  /// mpv `--gpu-api`；`mediacodec_embed` 不需要。
  final String? gpuApi;

  /// mpv `--gpu-context`；`mediacodec_embed` 不需要。
  final String? gpuContext;

  /// 设置页展示的说明。
  final String desc;

  bool get isGpuNext => this == gpuNext || this == gpuNextGl;

  /// 是否有可能真正把 HDR 交给显示端。
  ///
  /// `gpu-next` 走 Vulkan 交换链色彩空间协商；`gpu-next-gl` 靠 libmpv 的
  /// Android/EGL 补丁把窗口缓冲切成 10bit 并声明 BT.2020/PQ dataspace；
  /// `mediacodec_embed` 由解码器直接送显。传统 `gpu` 没有这套处理，不能把
  /// 窗口预切成 HDR，否则 SDR 画面会被系统当成 HDR 显示而发灰。
  bool get supportsHdrOutput =>
      this == gpuNext || this == gpuNextGl || this == mediacodecEmbed;

  /// 是否能由 libplacebo 解析杜比视界 RPU（profile 5 的 IPTPQc2）。
  ///
  /// gpu-next / gpu-next-gl 都走 libplacebo，能正确还原 DoVi；传统 `gpu`
  /// 没有 DoVi 映射，profile 5 只能回退 HDR10 或交给 Media3。
  bool get supportsDolbyVision => isGpuNext;

  static HdrBackend fromValue(String? value) =>
      values.firstWhere((e) => e.value == value, orElse: () => gpuNext);
}

/// 「默认 gpu-next」使用的渲染 API。
///
/// * [auto]：HDR / 杜比视界走 Vulkan 交换链，能真正点亮 HDR 面板；SDR 走纹理
///   gpu-next OpenGL；
/// * [vulkan]：SDR 也走 Vulkan 纹理，统一由 Vulkan 交换链出画；
/// * [opengl]：全部走 OpenGL。配合同仓库的 libmpv GL HDR 补丁，Android EGL
///   也能输出 10bit BT.2020/PQ（缓冲走 EGL/gralloc 的 UBWC，旋转时 HWC 仍可
///   直接合成）；没有该补丁的 libmpv 上 HDR 片源会被映射成 SDR。
enum GpuNextApi {
  auto('auto', '自动（推荐）', 'SDR 走 OpenGL，HDR / 杜比视界走 Vulkan'),
  vulkan('vulkan', 'Vulkan', '全部走 Vulkan，HDR 激发最完整，依赖驱动'),
  opengl(
    'opengl',
    'OpenGL',
    '全部走 OpenGL/EGL，同样能输出 10bit BT.2020/PQ（需要打过 GL HDR 补丁的 libmpv）',
  );

  const GpuNextApi(this.value, this.label, this.desc);

  /// 持久化到设置中的值。
  final String value;

  /// 设置页展示的名称。
  final String label;

  /// 设置页展示的说明。
  final String desc;

  static GpuNextApi fromValue(String? value) =>
      values.firstWhere((e) => e.value == value, orElse: () => auto);
}

/// 杜比视界 profile 5 无法走 gpu-next Vulkan 时的回退方式。
///
/// profile 5 的色彩是 IPTPQc2，只有 libplacebo 从 DoVi RPU 还原才对；
/// 但 Vulkan 交换链在部分驱动上不可用，渲染 API 也可能被手动选成 OpenGL。
/// 此时要么继续用 gpu-next 的 OpenGL 上下文软解（色彩正确、面板不激发），
/// 要么把出画交回 MediaCodec（杜比视界设备能激发，非杜比设备会偏色）。
enum GpuNextDoviFallback {
  soft('soft', '软解（gpu-next OpenGL）', 'libplacebo 软解，色彩正确，但吃 CPU 且无法激发 HDR'),
  mediacodec(
    'mediacodec',
    '切回 MediaCodec',
    '系统解码器直通出画：可激发杜比视界，不支持的设备会偏色',
  );

  const GpuNextDoviFallback(this.value, this.label, this.desc);

  /// 持久化到设置中的值。
  final String value;

  /// 设置页展示的名称。
  final String label;

  /// 设置页展示的说明。
  final String desc;

  static GpuNextDoviFallback fromValue(String? value) =>
      values.firstWhere((e) => e.value == value, orElse: () => soft);
}

/// mpv `--tone-mapping` 可选的色调映射算法。
///
/// 取值参考 mpv 手册，未知取值会被 libmpv 忽略并使用默认算法。
enum HdrToneMapping {
  auto('auto', '自动'),
  bt2390('bt.2390', 'BT.2390（推荐）'),
  spline('spline', 'Spline（细节丰富）'),
  hable('hable', 'Hable（胶片感）'),
  mobius('mobius', 'Mobius（保留高光）'),
  reinhard('reinhard', 'Reinhard（柔和）'),
  clip('clip', 'Clip（硬裁切）'),
  st2094_40('st2094-40', 'ST2094-40（动态元数据）'),
  st2094_10('st2094-10', 'ST2094-10（动态元数据）');

  const HdrToneMapping(this.value, this.label);

  final String value;
  final String label;

  static HdrToneMapping fromValue(String? value) =>
      values.firstWhere((e) => e.value == value, orElse: () => auto);
}

/// HDR 解码方式。
///
/// 直通解码（如 Android 的 `mediacodec`）把解码结果直接送到 Surface，
/// mpv 拿不到 10bit 画面，因此无法做高质量的色调映射；
/// 拷贝解码（`mediacodec-copy` / `auto-copy`）则会把画面交回 mpv 处理。
enum HdrHwdecMode {
  auto(
    'auto',
    '自动（HDR 优先拷贝解码）',
    'HDR 直通出画时固定 mediacodec；gpu-next 下 HDR 片源固定使用拷贝解码以保证色调映射生效，SDR 片源保持原设置',
  ),
  follow(
    'follow',
    '跟随硬解设置',
    '始终使用「硬解模式」中选择的解码器；gpu-next 下 HDR 片源会改用拷贝解码',
  ),
  copy('copy', '拷贝解码（可色调映射）', '解码后交给 mpv 处理，色调映射效果更好，但更耗电'),
  direct(
    'direct',
    '直通解码（省电）',
    'HDR 数据直接送显，可能无法执行色调映射；gpu-next 下 HDR 片源会改用拷贝解码以避免偏色',
  );

  const HdrHwdecMode(this.value, this.label, this.desc);

  final String value;
  final String label;
  final String desc;

  static HdrHwdecMode fromValue(String? value) =>
      values.firstWhere((e) => e.value == value, orElse: () => auto);
}

/// HDR / 杜比视界的播放配置快照。
///
/// 关于杜比视界（Dolby Vision）：
/// * B 站的杜比视界片源为 HEVC 编码（画质 id `126`），ffmpeg 可以正常解码；
/// * profile 8.x 带有 HDR10 兼容基础层，即使渲染端忽略 DoVi 元数据，
///   观感依然是正确的 HDR；
/// * profile 5 使用 IPTPQc2 色彩空间，需要 libplacebo（mpv `gpu-next`）
///   解析 RPU 元数据才能正确还原色彩；
/// * Android 走「Flutter 之下的 SurfaceView」+ `vo=mediacodec_embed` 时，
///   MediaCodec 的输出 dataspace 与窗口 HDR 色彩模式一起交给系统直通，
///   色彩由系统/显示端处理（mpv 的色调映射参数在该路径下不生效）；
/// * 纹理出画（SDR 路径或关闭直通出画时）只能做 8bit 色调映射。
class HdrConfig {
  const HdrConfig({
    required this.enabled,
    required this.mode,
    required this.toneMapping,
    required this.targetPeak,
    required this.computePeak,
    required this.hwdecMode,
  });

  /// 是否启用 HDR 色彩处理。
  final bool enabled;

  final HdrOutputMode mode;

  final HdrToneMapping toneMapping;

  /// 目标峰值亮度（nits），`0` 表示交给 mpv 自动判断。
  final int targetPeak;

  /// 是否逐帧计算峰值亮度（mpv `--hdr-compute-peak`）。
  final bool computePeak;

  final HdrHwdecMode hwdecMode;

  factory HdrConfig.fromPref() => HdrConfig(
    enabled: Pref.enableHdr,
    mode: HdrOutputMode.fromValue(Pref.hdrOutputMode),
    toneMapping: HdrToneMapping.fromValue(Pref.hdrToneMapping),
    targetPeak: Pref.hdrTargetPeak,
    computePeak: Pref.hdrComputePeak,
    hwdecMode: HdrHwdecMode.fromValue(Pref.hdrHwdecMode),
  );

  /// 「HDR 目标峰值亮度」的可选值（nits），`0` 表示自动。
  static const List<int> targetPeakChoices = [
    0,
    100,
    200,
    300,
    400,
    600,
    800,
    1000,
    1500,
    2000,
  ];

  static String targetPeakLabel(int nits) => nits <= 0 ? '自动' : '$nits nits';

  bool get passthrough => mode == HdrOutputMode.passthrough;

  /// 需要在播放器上设置的 mpv 属性。
  ///
  /// 这些属性都支持运行期修改，所以设置页改动后可以直接重新应用，
  /// 不必销毁播放器。未启用 HDR 时返回空表，保持 media_kit 的默认行为。
  Map<String, String> get mpvProperties {
    if (!enabled) return const {};
    return {
      'tone-mapping': toneMapping.value,
      'hdr-compute-peak': computePeak ? 'yes' : 'no',
      if (targetPeak > 0) 'target-peak': '$targetPeak',
      if (passthrough) 'target-colorspace-hint': 'yes',
      // media_kit 初始化时把 dither 设为 no；HDR 内容最终落到 8bit 纹理时
      // 开启抖动可以明显减少天空、暗部等渐变色带。这里用开销较低的
      // ordered，避免低端设备因逐像素误差扩散掉帧。
      'dither-depth': 'auto',
      'dither': 'ordered',
    };
  }

  /// 关闭 HDR 时用于复位的取值，与 media_kit 初始化后的默认值保持一致。
  ///
  /// 注意：`target-peak=auto` 在部分设备/后端上会导致视频输出创建失败（黑屏），
  /// 所以这里不复位该项；「自动」的含义就是从不设置它，交给 mpv 默认值。
  static const Map<String, String> resetProperties = {
    'tone-mapping': 'auto',
    'hdr-compute-peak': 'no',
    'target-colorspace-hint': 'no',
    'target-prim': 'auto',
    'target-trc': 'auto',
    'dither': 'no',
    'dither-depth': 'auto',
  };

  /// 拷贝解码对应的 `--hwdec`：解码结果会回到 mpv，可以做色调映射。
  String get copyHwdec {
    if (Platform.isAndroid) return 'mediacodec-copy';
    if (Platform.isIOS) return 'videotoolbox-copy';
    return 'auto-copy';
  }

  /// 直通解码对应的 `--hwdec`：省电，但 mpv 拿不到画面，色调映射不生效。
  String get directHwdec {
    if (Platform.isAndroid) return 'mediacodec';
    if (Platform.isIOS) return 'videotoolbox';
    return 'auto';
  }
}
