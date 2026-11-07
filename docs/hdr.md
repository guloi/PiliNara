# HDR / 杜比视界支持（Android 直通出画）

本分支（`ds-ai-hdr`）为播放器补上了 HDR / HDR Vivid / 杜比视界的片源获取、色彩处理，
并在 Android 上实现了**真正能点亮面板 HDR** 的出画路径。桌面端仍保持 media_kit 的
纹理渲染，只做色调映射。

## 一、两种出画路径

Flutter 的 `Texture` 固定是 **RGBA8888**，HDR 元数据在这一步必然丢失。因此：

| 片源 | 出画方式 | 说明 |
| --- | --- | --- |
| SDR | Flutter 纹理（media_kit 原路径） | 保留硬解、Anime4K、色调映射等全部 mpv 渲染能力 |
| HDR / 杜比视界 | **Flutter 之下的原生 SurfaceView** | 默认 `mediacodec_embed` 由解码器直接送显；也可选 `gpu-next` 走 Vulkan 交换链输出 |

关键点：

* SurfaceView 由原生 `VideoSurfaceHost` 插到窗口内容视图的**第 0 层**，位于 Flutter
  surface 之下；Flutter 的 surface 在透明模式下仍绘制在其上方。
* 视频区域只保留一块透明占位，**弹幕、字幕、控制栏、手势全部是 Flutter 绘制**，
  不会被原生 View 遮挡或吃掉点击（这是旧的 hybrid composition PlatformView 方案
  解决不了的问题）。
* 出画方式在播放器创建时确定。切换画质 / 换集导致 SDR ↔ HDR 变化时，
  `PlPlayerController._switchOutputIfNeeded()` 会重建播放器（其余情况复用）。

## 二、设置项

设置 → 播放设置 →「开启硬解」下方：

| 设置项 | 存储键 | 默认值 | 说明 |
| --- | --- | --- | --- |
| HDR 支持 | `enableHdr` | 开 | 总开关。关闭后 HDR 片源也走纹理（只做色调映射） |
| HDR 直通出画 | `hdrSurface` | **开** | HDR 片源改用 SurfaceView 直通送显；切换后重开视频生效 |
| HDR 渲染后端 | `hdrBackend` | **`mediacodec_embed`** | `mediacodec_embed`：解码器直通，最稳；`gpu-next`：libplacebo + Vulkan，实验性 HDR；`gpu-next-gl` / `gpu`：OpenGL 兼容路径 |
| HDR 解码方式 | `hdrHwdecMode` | `auto` | `gpu-next` 下 HDR 片源固定拷贝解码；`mediacodec_embed` 直通路径固定 `mediacodec`；SDR 片源沿用该设置 |
| HDR 输出模式 | `hdrOutputMode` | `auto` | `passthrough` 会额外写 `target-colorspace-hint=yes`（对纹理路径基本无效） |
| HDR 色调映射 | `hdrToneMapping` | `auto` | `--tone-mapping`，纹理 / `gpu-next` / `gpu` 路径有效；`mediacodec_embed` 不生效 |
| HDR 目标峰值亮度 | `hdrTargetPeak` | `0`（自动） | `--target-peak`，纹理 / `gpu-next` / `gpu` 路径有效 |
| HDR 动态峰值检测 | `hdrComputePeak` | 开 | `--hdr-compute-peak`，纹理 / `gpu-next` / `gpu` 路径有效 |
| 杜比视界兼容模式 | `dolbyVisionFallback` | 开 | 仅 profile 5 回退 HDR10；profile 8/8.4 不回退 |
| HDR 状态诊断 | — | — | 查看当前出画路径、`wid`、`vo`、`hwdec-current`、片源色彩等 |

> `mediacodec_embed` 由 MediaCodec 直接解码到 Surface，mpv 拿不到帧，
> 因此色调映射 / 峰值亮度 / 抖动等参数在这条路径上**不会生效**，这是直通的代价，
> 也是它唯一能真正输出 HDR 的原因。关闭「HDR 直通出画」即可回到可调色调映射的纹理路径。
>
> `gpu-next` 下 HDR 片源不受「直通解码」设置影响：直通解码会让 libplacebo
> 拿不到解码后的帧，出现偏色或色调映射失效，因此固定使用 `mediacodec-copy`。
> 需要省电可选回 `mediacodec_embed` 后端。

### 2.1 默认 gpu-next

音视频设置 →「HDR / 杜比视界」的下一行就是「默认 gpu-next」，进入方式相同：
左侧是开关（立即生效），右侧箭头进入同名二级页面调整子选项。

| 设置项 | 存储键 | 默认值 | 说明 |
| --- | --- | --- | --- |
| 默认 gpu-next | `defaultGpuNext` | 关 | 所有片源默认用 gpu-next（libplacebo）出画：SDR 走纹理，HDR / 杜比视界走原生 SurfaceView。开启后「HDR 渲染后端」对 HDR / 杜比视界片源失效，改由下面的子选项决定 |
| 渲染 API | `gpuNextApi` | `auto` | `auto`：SDR 走 gpu-next OpenGL，HDR / 杜比视界在关闭下一项后走 Vulkan；`vulkan`：SDR 纹理也走 Vulkan（初始化失败自动回退 OpenGL）；`opengl`：全部 OpenGL，兼容性最好，但 EGL 无法激发 HDR |
| HDR / 杜比视界时切回 MediaCodec | `gpuNextHdrMediaCodec` | 开 | HDR / 杜比视界片源改走 `mediacodec_embed` 直通，只让 SDR 走 gpu-next。渲染 API 为 `opengl` 时**建议保持开启**：这是 OpenGL 模式下唯一能真正激发 HDR 的路径；关闭后 HDR 会被映射成 SDR。**杜比视界 profile 5 例外**：它的 IPTPQc2 只能由 libplacebo 还原，MediaCodec 出画会偏色，因此 profile 5 优先走 gpu-next，不受本项影响；Vulkan 不可用时按下一项的「profile 5 回退方式」处理 |
| 杜比视界 profile 5 回退方式 | `gpuNextDoviFallback` | `soft` | Vulkan 不可用（驱动不支持、已判定失败，或渲染 API 选了 `opengl`）时 profile 5 的出画方式：`soft` 继续用 gpu-next OpenGL 软解——色彩正确，但 EGL 没有 HDR 交换链，面板不会激发；`mediacodec` 切回 `mediacodec_embed` 直通——杜比视界设备能正常激发，非杜比视界设备拿不到 RPU 会偏色 |
| 杜比视界 profile 5 软解 | `gpuNextDoviSoft` | 开 | 开启：profile 5 在 gpu-next 上一律软解（`hwdec=no`），libplacebo 拿到 RPU 才能还原 IPTPQc2，色彩正确、Vulkan 下可激发。关闭：直接切回 `mediacodec_embed` 直通，由设备自身的杜比视界能力出画（能激发，但拿不到 RPU 的设备会偏色） |

## 三、原生出画层怎么工作

`android/app/src/main/kotlin/com/example/pilinara/VideoSurfaceHost.kt`：

1. `create(owner, x, y, w, h, tenBit, hdr)`：创建（或**复用**）SurfaceView，
   一次性按最终矩形添加，不存在「先 1×1 再跳位」的黑闪；
2. `setRect`：页面滚动、全屏/半屏、旋转、小窗拖动时逐帧只更新布局；
3. `surfaceCreated`：把 `android.view.Surface` 的 global ref（`wid`）回传 Dart；
4. 窗口 HDR 模式只对真正有 HDR 输出能力的后端预切换（`mediacodec_embed` 与
   `gpu-next` Vulkan），并在播放器/首帧出现之前完成，避免首帧出声时整屏亮一下。
   `gpu-next-gl` / `gpu` 不切换窗口 HDR，否则 SDR 画面会被系统当成 HDR 显示而发灰。
   原生 `setHdr` 通道保留但已不再使用；
5. `remove`：延迟 400ms 销毁。页面 ↔ 小窗切换时新旧控件会短暂共存，
   立即销毁会导致 Surface 重建、mpv 重新初始化 → 黑闪；
6. `capture`：用 `PixelCopy` 抓当前画面，供 HDR 直通时截图。

Dart 侧 `lib/plugin/pl_player/utils/native_video_surface.dart`：

* 控件本身透明，尺寸与视频画面一致；
* 每帧结束后读取 `RenderBox` 在屏幕上的真实矩形（含 FittedBox 缩放与手势缩放），
  变化时才下发 `setRect`，不主动申请帧、不空转；
* 用自增的 `owner` 令牌交接页面/小窗两个控件，过期调用会被原生与控制器同时忽略；
* 只有拿到有效视频尺寸（`VideoController.rect`）后才 `create`，保证首帧尺寸正确。

`--android-surface-size` 使用 **SurfaceView 的实际布局尺寸**（与旧的 hybrid 出画路径
一致），不是视频编码尺寸。部分设备/解码器在 `android-surface-size` 与 SurfaceView
布局不一致时会直接黑屏（例如把 3840×2160 写到一个 1080×607 的 Surface 上）。
布局尺寸变化做了 200ms 防抖，小窗拖动/全屏动画期间不会逐帧重建视频输出。

### 页面/视频控件不能有不透明底色

原生视频在 Flutter surface 之下，Flutter 场景里任何不透明绘制都会盖住它。视频页：

* `SimpleScaffold` 的 Material 透明，视频 header 的黑底移除；
* 非视频区域（简介/评论/侧栏/小窗）显式加回主题表面色背景；
* `PLVideoPlayer` 的 `_videoWidget` 在 native 模式下透明；
* **最容易漏的一层**：`videoPlayer()` 的 `Stack` 里有一层铺满视频区的
  `const ColoredBox(color: Colors.black)`。它在视频控件之下、原生视频之上，
  HDR 直通时必须跳过（`if (plPlayerController?.useNativeSurface != true)`），
  否则会出现「挖孔正确、采样 mean=227、孔内仍然全黑」。
  这是最终定位到的直接原因。
* 播放页根节点用 `HdrHolePunch` 铺黑，只把视频矩形挖成透明；
* 预测性返回时用 `HdrVideoBlackout` 只压黑当前视频矩形，页面其余部分仍然可见，
  不再盖整屏黑幕。

### Flutter 必须用 surface 渲染模式（FlutterSurfaceView）

`FlutterActivity` 的默认实现是：

```java
getRenderMode() {
  return getBackgroundMode() == opaque ? RenderMode.surface : RenderMode.texture;
}
```

把 `getBackgroundMode()` 设为 `transparent` 后，默认会使用 **FlutterTextureView**。
TextureView 属于窗口内部的一层，窗口本身不透明，无法透出窗口之后的视频
SurfaceView（表现为采样有画面但屏幕全黑）。因此 `MainActivity` 必须同时覆盖：

```kotlin
override fun getBackgroundMode() = BackgroundMode.transparent
override fun getRenderMode() = RenderMode.surface
```

`surface` 模式下 delegate 会创建 `FlutterSurfaceView(context, transparent = true)`，
它自己会设置 `PixelFormat.TRANSPARENT(-2)` 并 `setZOrderOnTop(true)`；不要再强行
改成 `TRANSLUCENT(-3)`。HDR 状态诊断会显示 `backgroundMode` / `renderMode` 以及
视图树中每个 SurfaceView 的 `format` / `size`（`getFormat` 在 compileSdk 37 的
stub 中已移除，运行时用反射读取，读不到显示 `?`）。

### 整屏亮度跳变属系统 HDR 模式切换

真 HDR 需要显示面板切到 HDR 模式。部分设备只支持**全局** HDR 模式（而不是按层合成
HDR/SDR），进入 HDR 播放时整个屏幕（包括 SDR 的弹幕/控件/简介）会变亮一次。

应用会在 `setDataSource` 阶段、首帧之前通过 `setWindowHdr` 预切窗口色彩模式
（`window.setColorMode(COLOR_MODE_HDR)`），让这次跳变发生在加载/黑屏阶段而不是首帧
出声时；离开播放页时复位为 `COLOR_MODE_DEFAULT`。它只对 `mediacodec_embed` 与
`gpu-next` Vulkan 生效。即使不预切，部分设备也会根据 HDR Surface 的 dataspace 自动
切换，应用无法完全消除；不希望出现跳变时，关闭「HDR 直通出画」走 8bit 色调映射。

## 四、mpv 参数（HDR 路径）

### 4.1 mediacodec_embed（默认，推荐）

```text
vo=mediacodec_embed
hwdec=mediacodec            # 必须直通硬解
wid=<SurfaceView 的 Surface global ref>
android-surface-size=WxH    # SurfaceView 布局尺寸（不是视频编码尺寸）
vid=auto
target-colorspace-hint=yes
```

`tone-mapping` / `hdr-compute-peak` / `dither` 仍会写入，但这条路径下 mpv 拿不到帧，
参数不参与最终画面，HDR 完全由 MediaCodec 输出 buffer 的 dataspace 决定。

### 4.2 gpu-next + Vulkan（实验）

需要带 Vulkan 的 libmpv 构建（本仓库 fork：
`https://github.com/guloi/libmpv-android-video-build`，构建时打开 `MPV_VULKAN` /
`LIBPLACEBO_VULKAN`，并且 **libplacebo 必须带 SPIR-V 编译器 shaderc**）。
`ra_ctx_vulkan_android`（`gpu-context=androidvk`）是 fork 新增的 Android Vulkan 上下文。

PiliNara 不再手工替换 jar：`third_party/media_kit_libs_android_video` 的
`downloadLibmpv` 任务会在每次 Android 构建时从 fork 的 `libmpv-latest` release
下载各 ABI 的 `default-*.jar` 与 `SHA256SUMS`，校验后放进 `build/output`。
因此 fork 的 Build workflow 每跑一次，App 下次构建就会自动用上最新库；首次使用
必须先手动跑一次该 workflow，生成 `libmpv-latest`。

> **没有 shaderc 会直接黑屏**：libplacebo 的 Vulkan 后端要用 shaderc/glslang 编译
> GLSL。只开 `-Dvulkan=enabled` 而没有 `-Dshaderc=enabled` 时，mpv 日志会出现
> `Failed initializing any SPIR-V compiler! Maybe libplacebo was built without support
> for either libshaderc or glslang?`，随后 `Failed initializing vulkan device`，
> 表现为音频/进度正常但画面纯黑。fork 的 `dep_libplacebo=(shaderc)` 与
> `libplacebo.sh -Dshaderc=enabled` 已修复这一点。

```text
gpu-api=vulkan
gpu-context=androidvk
vo=gpu-next
gpu-dumb-mode=no
target-colorspace-hint=yes
target-colorspace-hint-mode=target
target-colorspace-hint-strict=no
target-prim=auto
target-trc=auto
hdr-compute-peak=yes
gamut-mapping-mode=auto
dither-depth=auto
video-output-levels=auto
wid=<SurfaceView 的 Surface global ref>
```

顺序很重要：**先 `vo=null` → 写 `gpu-api` / `gpu-context` → 给 `wid` →
`vo=gpu-next` → 再写一次 HDR 属性**。`gpu-context` 只在 VO 创建时读取一次；
`target-colorspace-hint` / `target-prim` / `target-trc` 是 VO 选项，`vo=null`
时写入会被忽略，必须在 VO 创建后再写一次（`reset: false`，避免把刚协商好的
HDR 交换链复位成 SDR）。

> **media_kit 会覆盖 `gpu-context`**：`AndroidVideoController.create` 在
> `Player.create` 之后无条件写入 `vo=null`、`gpu-context=android`、`opengl-es=yes`、
> `force-window=yes`（`third_party/media_kit_video/lib/src/video_controller/android_video_controller/real.dart`）。
> 如果只在创建播放器前写 Vulkan 参数，`gpu-context` 一定会被改回 `android`，gpu-next
> 永远走 OpenGL。因此 `PlPlayerController._initPlayer()` 在 `VideoController.create`
> 之后补写一次 HDR 属性，`_applyNativeSurface()` 在 `vo=gpu-next` 之前写初始化参数、
> 在 `vo=gpu-next` 之后（首帧前）再补写一次 HDR 目标属性。

`gpu-next` 的 `vo_gpu_next` 在 `target-colorspace-hint=yes` 且上下文没有报告目标
色彩空间（`ra_ctx_vulkan_android` 的 `target_csp` 返回空）时，会按 HDR10（PQ/BT.2020）
构造 hint，再通过 `VK_EXT_swapchain_colorspace` 协商交换链。

`gpu-next` + Vulkan 在「默认 gpu-next」打开、渲染 API 为 `auto` / `vulkan` 时生效。
HDR / 杜比视界片源会额外写一个 fork 新增的 mpv 选项 `options/android-vulkan-hdr=yes`（见 4.4）：
fork 的 `androidvk` 上下文据此把 `ANativeWindow` 切成 BT.2020/PQ dataspace + 10bit 格式，
并把 `preferred_csp` 报成 HDR10，`vo_gpu_next` 才会把 HDR 传给
`pl_swapchain_colorspace_hint`，显示端（SurfaceFlinger / 面板）才会真正进入 HDR。
旧 libmpv 没有这个选项时只会打一条未知选项 warning，行为与以前一致：画面正常，但面板不激发。

**自动回退**：三个触发点。

1. mpv 的 `vo/*` 错误日志（`stream.log` 里 level=error 且文本含 `vulkan` /
   `swapchain` / `spir-v` / `failed to create`）——最快，原生 Vulkan 建不起
   交换链时立刻回退；
2. `stream.error`（media_kit 只转发 file/ffmpeg/vd/ad/cplayer/stream 前缀，
   `vo/*` 不会出现在这里，只能覆盖部分情况）；
3. 播放开始 2.5 / 5 / 7.5 秒各读一次 `vo-configured`，三次都不是 `yes` 才判
   失败（只查一两次容易把「首帧解码慢、VO 还没建好」误判成失败，这正是之前
   HDR 下 gpu-next 动不动就回退的原因之一）。

判失败后设置 `_vulkanVoUnavailable` 并回退：HDR 片源改用 `mediacodec_embed`
直通，保住面板 HDR 亮度；SDR / 杜比兼容路径改用 `gpu-next OpenGL`。回退时重新下
`vo/wid`；SDR / OpenGL 路径会关闭窗口 HDR 预切。状态诊断会显示「已自动回退
（原 gpu-next Vulkan）」「Vulkan 自动回退: 已触发」，并新增「自动回退原因」与
「mpv 错误」两行（最后一条 error 级 mpv 日志），便于回报真实失败文本。
设置页重新选择后端会清除该标记，允许再次尝试 Vulkan。

回退到 `mediacodec_embed`（或纹理 `gpu`）时只改 `vo` 是不够的：
`mediacodec_embed` 要求解码器把画面直接输出到 Surface（`hwdec=mediacodec`），
而播放器是按硬件拷贝 / 软解创建的，切过去拿不到帧就是一直黑屏——这正是之前
「选了切回 MediaCodec 却回退不了」的原因。因此这类回退会销毁播放器，按
`setDataSource` 记下的参数快照（含播放位置、播放状态）重建
（`_rebuildOutput()`），出画后端与解码方式一起换掉。

### 4.3 gpu-next OpenGL / gpu（兼容）

`gpu-next-gl` 使用 `gpu-api=opengl` / `gpu-context=android` 并写 `fbo-format=rgba16hf`
（`fbo-format` 是 OpenGL 选项，Vulkan 路径不能写），同时显式写
`target-colorspace-hint=no`，让 libplacebo 正常 tone map 回 SDR。Android EGL 没有
HDR 交换链扩展，这条路径通常只输出 SDR，主要用于兼容排查。

### 4.4 fork 里的 Android Vulkan HDR 输出（android-vulkan-hdr）

mpv 本体按上游 `v0.41.0` 拉取，改动以 patch 形式放在 fork：

`third_party/libmpv-android-video-build/buildscripts/patches/mpv/android-vulkan-hdr.patch`

`buildscripts/patch.sh` 在每次 bundle 前把 `deps/<dep>` `git reset --hard` 回上游版本，再依次
`git apply` 所有 `patches/<dep>/*.patch`（`deps/` 是构建时下载目录，被 `.gitignore` 忽略），
所以新选项和 `context_android.c` 的改动都应该写成 patch，而不是直接改 `deps/mpv`。

patch 内容：

- `options/options.h` / `options/options.c`：新增 vo 选项 `--android-vulkan-hdr`（默认 `no`）。
- `video/out/vulkan/context_android.c`：
  - `android_init` 在 `vkCreateAndroidSurfaceKHR` 之前，HDR 时先
    `ANativeWindow_setBuffersGeometry(..., AHARDWAREBUFFER_FORMAT_R10G10B10A2_UNORM)` +
    `ANativeWindow_setBuffersDataSpace(ADATASPACE_BT2020_PQ)`，让 WSI 由窗口 dataspace
    推导出 HDR 的 `VkColorSpaceKHR`；
  - 给 `ra_ctx_params` 填 `preferred_csp`（HDR10）与 `color_depth`（10），
    `vo_gpu_next` 的 `target_csp` 才会是 HDR10；
  - `android_reconfig`：`ANativeWindow_setBuffersGeometry` 会复位 dataspace，HDR 分支每次
    resize 后重新设置；`ANativeWindow_setBuffersDataSpace` 是 API 28 才有的符号，而 fork 按
    `apilvl=24` 编译，所以用 `dlsym(RTLD_DEFAULT, ...)` 解析，运行时缺失就只设 10bit 格式。

只写 mpv 的 `target-colorspace-hint` / `target-prim` / `target-trc` 不会改变交换链的实际
编码格式，libplacebo 仍按 `VK_COLOR_SPACE_SRGB` 输出 SDR；上面的 dataspace + `preferred_csp`
才是「面板激发」的必要条件。

App 要等 fork 重新跑一次 Build workflow、生成新的 `libmpv-latest` 之后才会带上这个 patch
（下载流程见 4.2）。

## 五、片源获取

`VideoHttp.videoUrl` 的 `fnval` 保持 `4048`：

| 位 | 含义 |
| --- | --- |
| 16 | DASH |
| 64 | HDR（画质 125） |
| 128 | 4K |
| 256 | 杜比音频 |
| 512 | 杜比视界（画质 126） |
| 1024 | 8K |
| 2048 | AV1 |

> **不要加 4096**：曾把 `fnval` 改成 `8144` 想打开 HDR Vivid（129），但 4096 不是
> web playurl 支持的位，服务端会返回 `-404`，表现为所有视频都提示不存在。
> 因此 HDR Vivid 片源目前取不到；HDR（125）与杜比视界（126）不受影响。

## 六、平台能力与已知限制

1. **gpu-next Vulkan 仍是实验路径**。libmpv fork 增加了 `ra_ctx_vulkan_android`，
   gpu-next 可通过 `VK_EXT_swapchain_colorspace` 请求 HDR10 交换链。但**必须用带
   `android-vulkan-hdr` patch（见 4.4）重新构建的 libmpv**：线上旧的
   `libmpv-latest` 里 `video/out/vulkan/context_android.c` 只调用
   `ANativeWindow_setBuffersGeometry`，没有 `ANativeWindow_setBuffersDataSpace`，
   Vulkan 交换链会被 ROM 当 SDR 合成（画面正常但面板不切 HDR，或颜色发灰）；
   带上 patch 之前请求 `target-colorspace-hint=yes` 还可能让部分驱动的交换链直接
   创建失败，于是触发「自动回退」。**确定能点亮 HDR 的仍是 `mediacodec_embed`**；
   Vulkan 路径因设备驱动差异或 libmpv 缺少 shaderc 也可能黑屏。应用已内置日志 +
   `vo-configured` 双重检测：HDR 片源自动回退到 `mediacodec_embed` 直通，
   SDR 路径回退 `gpu-next-gl`；也可以手动切后端。
   另外：原生 SurfaceView 只在 gpu-next（libplacebo）自己渲染时请求 10bit
   缓冲（`RGBA_1010102`）；HDR 交给 MediaCodec 直通时缓冲格式由解码器决定，
   不再强设，避免直通失败。缓冲格式只在创建 SurfaceView 时生效一次，所以
   后端在 8bit / 10bit 之间切换时（杜比视界 profile 5 分P 之后接 HDR10 /
   profile 8 分P）`NativeVideoSurface` 会重建 SurfaceView 换取对应位深，
   否则 HDR 会渲染到 8bit 缓冲上，表现为只有声音没有画面。
   此外 fork 的构建矩阵里 `MPV_VULKAN` 与 `LIBPLACEBO_VULKAN` 必须同时打开；只开
   其中一个会出现 GL/mediacodec 输出全黑（fork 提交 `effde5e` 用于二分定位）。
2. **杜比视界 profile 5**：使用 IPTPQc2 色彩空间，`mediacodec_embed` 直通会把它
   当成 SDR（诊断里表现为 `bt.709 / bt.1886`、`sig-peak=0`）导致偏色。选择
   `gpu-next` / `gpu-next-gl` 时由 libplacebo 解析 DoVi RPU，保留 126 原片源，
   不再触发兼容模式回退，也不走 Media3；`mediacodec_embed` / `gpu` 下开启「杜比视界
   兼容模式」才会改用同分辨率 HDR10（125）。兼容模式只处理 profile 5；profile
   8/8.4 带 HDR10/HLG 基础层，始终保留 DoVi 直通。走 gpu-next 的 profile 5 会让
   窗口进入 HDR 模式（Vulkan 交换链按 HDR10 输出），这是正常行为。
   开启「默认 gpu-next」后，profile 5 默认走 gpu-next：即使
   「HDR / 杜比视界时切回 MediaCodec」开着，也不再交给 MediaCodec 直通，
   因为解码器不会把 DoVi RPU 交回给应用，直通的结果就是整片偏色。
   若确实想用系统解码器直通（例如设备支持杜比视界、希望交给它激发），把
   「杜比视界 profile 5 软解」关掉即可，此时 profile 5 直接走 `mediacodec_embed`。
   走 gpu-next 时一律软解：`mediacodec-copy` 拿不到 RPU，libplacebo 就没有色彩
   元数据，既偏色又会被当成 SDR 输出（亮度不激发）。
   此时渲染 API 为 `opengl` 或 Vulkan 已被判定不可用时，按设置页的
   「杜比视界 profile 5 回退方式」决定出画：`soft`（默认）退回 `gpu-next-gl` 软解，
   色彩仍然正确，只是 EGL 无法激发 HDR，画面会被映射成 SDR；`mediacodec`
   切回 `mediacodec_embed` 直通，杜比视界面板能正常激发，非杜比视界设备会偏色。
   回退判定（Vulkan 自动回退、纹理回退）会在离开播放页时清空，下次播放重新尝试。
   HDR（125）与杜比视界 profile 8 仍按「切回 MediaCodec」的设置走直通。
   关掉「软解」后如果还开着 HDR 设置里的「profile 5 Media3 解码（实验）」，
   视频会改由 Media3/ExoPlayer 解到同一块原生 SurfaceView，mpv 只保留时间轴；
   此时 mpv 的视频轨是关掉的（`vid=no`），诊断里的 vo / hwdec 按实际后端显示
   （Media3 出画时会注明「Media3 / ExoPlayer 解码」），真正的出画路径看
   「真 DoVi 解码」那行。
3. **手势限制**：原生 SurfaceView 是独立图层，无法跟随 Flutter 的旋转与镜像。
   HDR 直通时禁用双指旋转、自动重置镜像；缩放/平移通过矩形同步仍然可用。
4. **PiP**：支持，但小窗圆角无法裁切原生图层（会看到直角视频）；
   关闭动画只作用于 Flutter 层。系统 PiP 与 App 内小窗均已做透明底色适配。
5. **截图**：HDR 直通时改用原生 `PixelCopy`，不再依赖 `Player.screenshot()`。
6. **透明 Flutter surface**：为让视频位于 Flutter 之下，Activity 使用
   `BackgroundMode.transparent`；窗口背景已固定为黑色（`NormalTheme` + `onCreate`），
   避免透白闪烁。

## 七、「面板亮度没有激发」怎么排查

设置 → 播放设置 →「HDR 状态诊断」：

1. `出画路径` 必须是 `SurfaceView(HDR)`；如果是 `Texture(8bit)`，说明当前画质不是
   HDR/杜比视界档位，或关闭了「HDR 直通出画」/「HDR 支持」/硬解；
2. `原生 Surface` 的 `wid` 不为 `-`；为 `-` 说明 SurfaceView 还没创建/挂载；
3. 按后端核对 `vo` / `gpu-api` / `gpu-context`：
   * `mediacodec_embed`：`vo=mediacodec_embed`，`hwdec-current=mediacodec`；
   * `gpu-next`：`vo=gpu-next`、`gpu-api=vulkan`、`gpu-context=androidvk`，
     `hwdec-current` 应为 `mediacodec-copy` / `auto-copy`（mpv 需要拿到帧）；
   * `gpu-next-gl`：`gpu-api=opengl`、`gpu-context=android`；
4. 如果 `gpu-context` 仍显示 `android`，说明 media_kit 的覆盖没有被补写覆盖掉——
   检查 `_initPlayer` 中 `VideoController.create` 之后的 `_applyHdrProperties` 调用；
5. `gpu-next` 还要确认 `target-colorspace-hint=yes`、
   `target-colorspace-hint-mode=target`、`target-prim=auto`、`target-trc=auto`
   已经生效；这些是 VO 选项，只在 `vo=gpu-next` 之后补写才会被 libplacebo 看到；
6. `视频色彩` 的 gamma 为 `pq` / `hlg` 才是真 HDR 片源；`bt.1886` 是 SDR；
7. 以上都正常但面板仍不亮：检查设备是否支持 HDR、系统显示设置是否开启 HDR，
   以及当前窗口是否被系统限制为 SDR。

### 7.1 亮度手势在 HDR 下没有反应

部分设备进入 HDR 输出后会把面板锁在峰值亮度，WindowManager.LayoutParams.screenBrightness
或系统亮度设置都压不住原生 HDR 图层。HDR 直通时亮度手势改为调整 Flutter 侧的黑色
遮罩（PlPlayerController.nativeBrightness），只向下压暗、不影响解码/色调映射：

* setBrightness 在 useNativeSurface 为 true 时不再调用系统/应用窗口亮度；
* HDR 直通从面板峰值亮度开始，首次滑动先把基准和值对齐到 1.0，避免
  _brightnessValue 初始值较低时第一次滑动把画面瞬间压黑；value=base 不遮、
  value=0 全黑；切换出/重新进入 HDR 时依据 nativeBrightness 的 -1 复位；
* 遮罩在 lib/pages/video/widgets/hdr_hole_punch.dart 的
  HdrNativeBrightnessOverlay，夹在挖孔黑底与页面内容之间，只压暗视频孔，
  控制栏和亮度指示仍然清晰；IgnorePointer 不拦截手势；
* SDR / 纹理路径仍走原来的系统或应用窗口亮度，不受影响。

### 7.2 进全屏后画面发灰、面板不再激发 HDR（半屏正常）

gpu-next + Vulkan 直通时，`android-surface-size` 一变，mpv 就会走
`android_reconfig`，那里重新 `ANativeWindow_setBuffersGeometry` 会把窗口的
BT.2020/PQ dataspace 复位。补丁本应在 HDR 分支补回来，但部分 ROM
（如 Oneplus Ace 5 / DerpFest A17）上重建出来的 Vulkan 交换链仍回落成 SDR：
画面变暗发灰、面板退出 HDR，而半屏时不做 resize 所以一切正常。

现在的处理（`PlPlayerController`）：

* `_setFullScreen` 在 HDR 直通时（`_isVulkanHdrOutput`，即
  `nativeSurfaceMode && !_useMedia3Dovi && _renderBackend == gpuNext`）用
  `_updateWindowHdrMode(force: true)` 重新钉一次窗口色彩模式，并在 600ms 后
  （SurfaceView 重建、尺寸下发完成时）再钉一次——进出全屏的 SystemUI／方向
  切换可能把第一次的钉法冲掉；
* `resizeNativeSurface` 的 200ms 防抖回调里**只写** `android-surface-size`，
  不重建 VO。

> 曾经试过「resize 时 `vo=null` 重建 VO」来绕开 `android_reconfig`，结论是不必要
> 而且有害：`video/out/vulkan/context_android.c` 的 `android_reconfig` 本来就会在
> `ra_vk_ctx_resize` 之前调 `android_apply_hdr_window()`（`setBuffersGeometry` 成
> R10G10B10A2 + `setBuffersDataSpace(BT2020_PQ)`），重建并不能多保住什么；
> 而 `vo=null` 期间 mpv 会短暂报 buffering，加上进出全屏的 SurfaceView 重建，
> 表现就是「切全屏闪一下加载中」。

### 7.3 怎么拿到「全屏那一刻」的证据

「HDR 状态诊断」只能在设置页里打开，而设置页会先销毁播放页，所以看到的永远
是「上次播放的快照」；更麻烦的是退出全屏后每 5 秒一次的定时快照会把全屏期间
的状态覆盖掉，等于拿不到故障态。现在改成：

* **全屏快照单独保存**：`PlPlayerController._lastFullScreenSnapshot`。播放中
  每 5 秒的快照按 `isFullScreen` 分流，全屏期间写全屏快照，半屏写「最近一次」
  快照；诊断页两段一起显示（`lastHdrInfo`），可以直接对比。
* **进/出全屏 1.8 秒后主动抓一次**：`_setFullScreen` 调
  `_scheduleFullScreenSnapshot`，此时尺寸防抖（200ms）与 VO 重建都已完成，
  抓到的才是稳定态；顺带重新下发一次窗口 HDR 色彩模式
  （`_verifyFullScreenHdr`）。
* **新增系统侧判据**（原生 `hdrDisplayInfo`，`DisplayManager` +
  `Display.HdrCapabilities`）：
  - `窗口 HDR 预切: 是 / 实际 colorMode=N(名字)`——`setWindowHdr` 现在会回读
    `Window.colorMode`，名字由原生按 `ActivityInfo.COLOR_MODE_*` 常量翻出来
    （默认 / 广播 / 游戏 / HDR / 自动），ROM 忽略请求时能直接看出来；

  - `显示端: hdr=…/ 峰值=…nits / 平均=…nits / 模式=WxH@Hz / 支持类型=…`；
  - `全屏 HDR 自检: …`——全屏稳定后若窗口模式不是 `HDR`/`自动` 或 `display.isHdr=false`，
    记一条提示，提示用户把快照发回来。

> 注意：这些值只用于判断，不要拿来自动重建 VO。部分 ROM 的 `Window.colorMode`
> 回读始终是 0（半屏出画正常时也是 0），当判据会在每次进全屏时多闪黑一帧。

### 7.4 进出全屏不闪「加载中」

进出全屏会改方向与 SystemUI，SurfaceView 随之重建（新 `wid` → 重新下发 `vo`），
mpv 在 VO 重建期间会短暂报 buffering，于是加载动画闪一下。处理：

* 尺寸变化不再触发 VO 重建（见 7.2），把最常见的抖动源去掉；
* `PlPlayerController.fullScreenTransition`：`_setFullScreen` 打开 1.2s 过渡
  窗口，`lib/plugin/pl_player/view/view.dart` 的加载动画条件里加上
  `!fullScreenTransition.value`，这段时间既不显示 `dataStatus.loading`
  也不显示 `isBuffering` 的转圈（600ms 的第二次 HDR 下发也落在窗口内）。

### 7.5 交换链到底选了哪个面：直接看 mpv 日志

「全屏变暗」的几种可能（交换链掉回 8bit / SDR、窗口 dataspace 被复位、
libplacebo 色调映射目标偏低）在应用侧看不出来，只能靠 libplacebo 建交换链时
打印的面配置：

* info 级 `Available surface configurations:` 列出窗口当前支持的全部
  `格式 + 色彩空间`（有没有 10bit、有没有 `HDR10_ST2084`）；
* info 级 `Picked surface configuration N: <format> + <colorspace>` 是最终选中的那个。

mpv 客户端的日志级别由 `PlayerConfiguration.logLevel` 决定（默认 release 是
`error`），这两行**默认收不到**；实测放到 `info` 也收不到，要放到 `MPVLogLevel.v`。
级别可以在「设置 → HDR / 杜比视界 → HDR 状态诊断」对话框右上角的
「日志 …」按钮里切（`SettingBoxKey.logLevelType` / `Pref.logLevelType` /
`LogLevelType`，默认 `info`）。注意 `logLevel` 只在 `Player.create` 时通过
`mpv_request_log_messages` 下发（media_kit 没有 setLogLevel），**改完要重新打开
视频**才生效；对话框里的内容仍是打开那一刻抓的，重开视频后再看才是新级别的输出。

诊断里的「mpv 日志: 要求 v，已收到 …」那一行是按 level 统计的到达计数：
如果 `v` 一直是 0，问题在 media_kit / libmpv 没放开，而不是这边的
过滤条件写错了（早先版本确实按关键字把 libplacebo 的行误杀过一轮）。

另一条更省事的判据是 mpv 的 `video-out-params`（诊断里的「VO 输出色彩」）：
它就是 libplacebo 实际出画的色彩空间，`pq` + `bt.2020` 说明 HDR 确实交给了
交换链；若变成 `bt.1886` / `bt.709`，说明被 tone map 回了 SDR。

`PlPlayerController._mpvVoLog` 只按前缀（`vo` / `vulkan`）和
`libplacebo` / `androidvk` 关键字收集，**不限 level**（面配置是 info 级），留最近 40 条，
并把应用侧动作也插进去做时间线：
`--- 全屏=true`、`--- android-surface-size 2400x1080`、`--- windowHdr=true
applied=0`、`--- VO 重建 wid=… vo=…`。这些行会拼在「HDR 状态诊断」末尾
（`mpv VO 日志（最近 N 条）`）。

### 7.6 全屏变暗：先分清「交换链尺寸」与「合成路径」

到最新一版快照为止，两个状态里能拿到的证据完全一致：

* 窗口色彩模式两态相同（早期版本读到的 `2` 并不是 HDR，具体名字见 7.7），
  显示端 `hdr=true`、峰值 2000 nits；
* `video-out-params` 两态都是 `bt.2020 / pq / limited`，没有回落 SDR；
* 半屏 `Picked surface configuration 61: VK_FORMAT_A2B10G10R10_UNORM_PACK32 +
  VK_COLOR_SPACE_HDR10_ST2084_EXT`，全屏那次没有再打印 `Picked surface configuration`。

最后一条**不代表**全屏没重建交换链：libplacebo v7.360.1 的
`src/vulkan/swapchain.c` 里 `pick_surf_format()` 只在「选中的格式/色彩空间真的变了」时才
`PL_INFO` 并置 `needs_recreate`；而 `vk_sw_resize()` 只要 `width/height` 变了就会
`vk_sw_recreate()`（那行是 debug 级，诊断里看不到）。所以全屏是按 2528x1264
**重建了一张同样格式**的 10bit HDR10 交换链。

格式、dataspace、窗口 HDR 模式都一样之后，两态唯一剩下的差异就是**图层/交换链的像素尺寸**
（2528x1264 vs 1264x632）。「mediacodec_embed 全屏正常」不能排除尺寸：直通路径的图层尺寸
虽然相同，但缓冲是解码器给的 YUV（P010），走的是另一条硬件合成路径。

定位开关：「设置 → HDR / 杜比视界 →（诊断）全屏半分辨率出画」
（`SettingBoxKey.hdrFullScreenHalfRes` / `Pref.hdrFullScreenHalfRes` /
`PlPlayerController._effectiveSurfaceSize()`、`refreshNativeSurfaceSizeDebug()`）。
打开后全屏写入的 `--android-surface-size` 与半屏一样，由 SurfaceFlinger 把
1264x632 的 HDR 缓冲放大到全屏：

* 亮度恢复正常 → 与交换链/图层尺寸有关（DPU 对大尺寸 10bit RGB HDR 图层的处理、
  或回退到 GPU 合成），可以把「全屏时限制交换链尺寸」做成正式策略；
* 依旧偏暗 → 与尺寸无关，问题在 Vulkan 缓冲被合成的方式（同尺寸的 mediacodec
  直通是正常的），需要往 mpv/libplacebo 侧改（例如换 LINEAR 色彩空间面，或补 HDR
  静态元数据）。

### 7.7 窗口色彩模式：名字由原生给，别再猜数字

全屏变暗排查里最容易走错的一步，是拿 `Window.colorMode` 的数字直接下结论。
`ActivityInfo` 的常量在各版本 SDK 里顺序不同（`COLOR_MODE_DEFAULT` /
`BROADCAST` / `GAME` / `HDR` / `AUTO`），Dart 侧硬编码「4=HDR」最后把
「游戏模式」当成了「HDR 已激发」。

现在的做法：

* `MainActivity.colorModeLabel()` 用 `when` 对 `ActivityInfo.COLOR_MODE_*` 常量
  出名字（默认 / 广播 / 游戏 / HDR / 自动），`describeHdrDisplay()` 与
  `windowColorMode` 通道方法都带 `label`；
* `setWindowHdr` 回读不一致时会再用 `window.attributes.colorMode` 走一次
  （`setColorMode` 只改 `Window.mColorMode`，部分 ROM 随后被窗口属性更新覆盖），
  并打 `setWindowHdr requested=… applied=… retried=…` 日志；
* `PlPlayerController._scheduleColorModeTimeline()` 在进出全屏后的
  0 / 400 / 900 / 1600 / 2600 ms 各采一次（只读），拼成诊断里的
  「窗口色彩模式时间线」。单点回读分不清「一直是这个值」和「切换时被改掉」。

两个同源判据：

* `显示端: … HDR 余量=…`（API 34+ `Display.getHdrSdrRatio()`）——SF 给 HDR
  图层留的余量，HDR 图层被 tone map 时按它压；
* `显示端: … 旋转=…° 窗口=WxH / …`——全屏不只把图层变大，通常还伴随一次
  90° 旋转（半屏竖屏 → 全屏横屏）。旋转和尺寸都会让 SF/HWC 重新决定这一层由谁
  合成，所以两个变量必须同时记录，否则「尺寸无关」的结论就站不住脚；
* `全屏半分辨率出画: 开/关 / 当前写入尺寸=WxH`——实验开关本身的状态。
  早先那次 A/B 没生效也没人发现，就是因为诊断里没有这一行；
* `直通画面采样: mean=… size=… error=…`——PixelCopy 读 SurfaceView 的真实像素。
  `mean` 在两种状态下相近但屏幕亮度不同 → 暗在合成/显示端，不在 mpv；
  `mean` 本身就很小 → 是 libplacebo 出的画面就暗。全屏时早先一直只有 `null`，
  现在失败也会回 `error`（owner 不符 / 尺寸为 0 / PixelCopy 返回码）并重试一次。

## 八、代码位置

| 文件 | 作用 |
| --- | --- |
| `android/.../VideoSurfaceHost.kt` | 原生 SurfaceView 宿主：创建/复用、矩形、HDR 色彩模式、PixelCopy 截图 |
| `android/.../MainActivity.kt` | `com.pilinara/video_surface` 通道、透明 Flutter surface、黑色窗口背景 |
| `lib/plugin/pl_player/utils/native_video_surface.dart` | Flutter 侧透明占位 + 逐帧矩形同步 + owner 交接 |
| `lib/plugin/pl_player/utils/native_video_surface_channel.dart` | 通道封装（create / setRect / setHdr / remove / capture） |
| `lib/plugin/pl_player/controller.dart` | 出画方式决策、播放器重建、`wid`/`vo` 下发、HDR 属性、诊断、截图 |
| `lib/plugin/pl_player/models/hdr_config.dart` | HDR 模式/算法/解码方式/后端枚举与 mpv 属性 |
| `lib/pages/setting/models/video_settings.dart` | 设置项、对话框、状态诊断 |
| `lib/pages/video/controller.dart` | 播放前写入「当前片源是否 HDR」 |
| `lib/pages/video/widgets/hdr_hole_punch.dart` | 视频挖孔黑底、返回手势压黑、HDR 亮度遮罩 |
| `lib/common/widgets/pip_mini_video_content.dart` | 小窗视频内容（透明底色 + 原生占位） |
| `lib/services/pip_overlay_service.dart` | 小窗/系统 PiP 的透明底色适配 |
| `lib/utils/video_utils.dart` | 杜比视界兼容模式的选质回退 |
| `third_party/media_kit_video` | 仅保留 `androidExternalSurface`（不创建纹理，由应用提供 Surface）；注意它会覆盖 `gpu-context` |
| `third_party/libmpv-android-video-build` | libmpv / libplacebo 带 Vulkan 的构建 fork（`androidvk` 上下文、构建矩阵） |

## 九、自测建议

1. 找一部带「杜比视界」或「HDR」标签的视频，选对应画质播放；
2. 状态诊断确认 `出画路径=SurfaceView(HDR)`、`vo=mediacodec_embed`、
   `hwdec-current=mediacodec`、gamma 为 `pq`/`hlg`；
3. 观察打开视频时是否还有整屏闪烁；正常应只有视频区域短暂黑场后出画；
4. 全屏 ↔ 半屏、竖屏 ↔ 横屏、进入 App 内小窗 / 系统 PiP，确认视频位置正确、
   弹幕与控制栏正常、退出后亮度回落；
5. 截图（HDR 直通下走 PixelCopy）应能正常保存；
6. 切到 SDR 画质：应自动重建为纹理出画，Anime4K 等能力恢复；
7. 关闭「HDR 直通出画」后重开视频：回到纹理路径，色调映射参数应即时可调。

## 十、打开视频白屏 / 灰屏修复记录

打开视频时曾出现整屏灰色（约 `#b5b5b5`）或启动时白屏，两者来源不同：

### 10.1 整屏灰色 = Flutter release ErrorWidget

`lib/pages/video/view.dart` 为了实现预测性返回手势的黑色遮罩，曾把 `ModalRoute` 强转成
`Listenable`：

```dart
// 错误：ModalRoute 不是 Listenable
animation: (route as Listenable?) ?? kAlwaysDismissedAnimation,
```

`ModalRoute` 继承自 `TransitionRoute`，并没有实现 `Listenable`，这个 cast 在 build 时
抛出 `TypeError`。release 模式下 Flutter 用 `ErrorWidget` 覆盖整页，颜色就是
`0xF0C0C0C0` 叠在黑底上的灰色，看起来像「白屏/灰屏」。按返回键能立刻回到首页，
因为路由本身没有问题。

正确做法是使用 `NavigatorState.userGestureInProgressNotifier`（Flutter 自己的
`_ModalScopeState` 也用它跟踪 `popGestureInProgress`）：

```dart
final Listenable? gesture = route?.navigator?.userGestureInProgressNotifier;
...
animation: gesture ?? kAlwaysDismissedAnimation,
```

> 如果以后再次看到整屏灰色，先用 `flutter run` 看 build 异常；不要只按「白屏」去查
> 原生 Surface。

### 10.2 启动白屏 = LaunchTheme 的白色启动图

* `android/app/src/main/res/drawable/background.png` 是一个 **1×1 白色像素**，旧的
  `launch_background.xml`（含 `-v21` / `night` 变体）把它铺满全屏；
* `values-v31/styles.xml` 的 `android:windowSplashScreenBackground` 还是 `#ffffff`。

Android 12+ 在 Flutter 首帧之前显示 splash，于是先白一下。现在四个
`launch_background.xml` 都改成 `@android:color/black`，`values-v31` /
`values-night-v31` 的 splash 背景也统一为 `#000000`，与 `NormalTheme` 的黑色窗口背景一致。
