package com.example.pilinara

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager.LayoutParams
import android.widget.ImageView
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private lateinit var methodChannel: MethodChannel
    private var videoSurfaceHost: VideoSurfaceHost? = null
    private var doviPlayer: DoviPlayer? = null

    /**
     * 透明背景模式：让 Flutter 的 surface 支持逐像素透明且 Z 序置顶，
     * 这样播放页可以把 HDR 视频的 SurfaceView 放在 Flutter 之下，
     * 弹幕/控件等 Flutter UI 仍然绘制在视频之上。
     *
     * 只有 HDR 直通出画需要它；窗口背景已在 NormalTheme / onCreate 中固定为黑色，
     * 因此不会出现透白闪烁。
     */
    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode =
        FlutterActivityLaunchConfigs.BackgroundMode.transparent

    /**
     * 必须强制 surface 渲染模式。
     *
     * FlutterActivity 的默认实现是：backgroundMode != opaque 时返回
     * RenderMode.texture。TextureView 属于窗口内的一层，窗口本身不透明，
     * 会把位于窗口之后的 HDR 视频 SurfaceView 完全盖住（采样有画面但全黑）。
     * 只有 FlutterSurfaceView（RenderMode.surface）才能以 TRANSLUCENT + Z 置顶
     * 的方式叠在视频 SurfaceView 之上，露出挖孔区域。
     */
    override fun getRenderMode(): RenderMode = RenderMode.surface

    /**
     * SurfaceHolder.getFormat() 在 compileSdk 37 的 stub 里已被移除，
     * 运行时仍然存在，这里用反射读取用于诊断（读不到返回 null）。
     */
    private fun readSurfaceFormat(holder: SurfaceHolder): Int? {
        return runCatching {
            val method = holder.javaClass.getMethod("getFormat")
            (method.invoke(holder) as? Number)?.toInt()
        }.recoverCatching {
            val method = holder.javaClass.getMethod("getSurfaceFormat")
            (method.invoke(holder) as? Number)?.toInt()
        }.getOrNull()
    }

    /** 诊断：Flutter 层是否透明、背景模式与视图树。 */
    private fun describeSurface(): String {
        val builder = StringBuilder()
        builder.append("backgroundMode=").append(getBackgroundMode().name)
        builder.append("\nrenderMode=").append(getRenderMode().name)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.append("\nwindowColorMode=").append(window.colorMode)
        }
        val decor = window.decorView as? ViewGroup ?: return builder.toString()
        fun walk(view: View, depth: Int) {
            builder.append('\n').append("  ".repeat(depth)).append(view.javaClass.name)
            if (view is TextureView) {
                builder.append(" [TextureView]")
            }
            if (view is ImageView) {
                builder.append(" [ImageView]")
            }
            if (view is SurfaceView) {
                builder
                    .append(" format=")
                    .append(readSurfaceFormat(view.holder) ?: "?")
                    .append(" size=")
                    .append(view.width)
                    .append('x')
                    .append(view.height)
                if (view.tag == VideoSurfaceHost.SURFACE_TAG) {
                    builder.append(" [video]")
                }
            }
            if (view is ViewGroup) {
                for (i in 0 until view.childCount) {
                    walk(view.getChildAt(i), depth + 1)
                }
            }
        }
        walk(decor, 0)
        return builder.toString()
    }

    /** Window.colorMode 的可读名字，避免在 Dart 侧硬编码常量表。 */
    private fun colorModeLabel(mode: Int): String = when (mode) {
        ActivityInfo.COLOR_MODE_DEFAULT -> "默认"
        ActivityInfo.COLOR_MODE_BROADCAST -> "广播"
        ActivityInfo.COLOR_MODE_GAME -> "游戏"
        ActivityInfo.COLOR_MODE_HDR -> "HDR"
        ActivityInfo.COLOR_MODE_AUTO -> "自动"
        else -> "未知"
    }

    /**
     * 只读当前 Window.colorMode，不产生副作用。
     *
     * 全屏/半屏切换后 mpv 侧参数完全一致、但画面亮度不同，唯一变过的系统状态
     * 就是这个值，所以要能低成本地连续采样，看它什么时候被系统改掉。
     */
    private fun readWindowColorMode(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return mapOf("mode" to -1, "label" to "不支持")
        }
        val mode = window.colorMode
        return mapOf("mode" to mode, "label" to colorModeLabel(mode))
    }

    /**
     * 诊断：显示端的 HDR 能力与当前物理模式。
     *
     * 面板是否真的进了 HDR，单看 mpv 的参数（target-peak=auto）看不出来：
     * ANativeWindow_setBuffersGeometry 会把 dataspace 复位，全屏这类尺寸变化
     * 之后 Vulkan 交换链有可能回落成 SDR。这里把系统侧的判据一并带回去：
     * 窗口色彩模式（原生翻好的名字）、display.isHdr、以及 SF 的 HDR 余量。
     */
    private fun describeHdrDisplay(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            out["colorMode"] = window.colorMode
            out["colorModeLabel"] = colorModeLabel(window.colorMode)
        }
        val manager = getSystemService(DisplayManager::class.java)
        val display = manager?.getDisplay(Display.DEFAULT_DISPLAY) ?: return out
        out["hdr"] = display.isHdr
        display.hdrCapabilities?.let { caps ->
            out["maxLuminance"] = caps.desiredMaxLuminance
            out["maxAvgLuminance"] = caps.desiredMaxAverageLuminance
            out["minLuminance"] = caps.desiredMinLuminance
            out["hdrTypes"] = caps.supportedHdrTypes.joinToString(",")
        }
        // SF 给 HDR 图层留的「亮度余量」：HDR 图层被 tone map 时按它压，
        // 显示端没真的进 HDR 时这个值会明显偏小。
        if (Build.VERSION.SDK_INT >= 34) {
            out["hdrSdrRatioAvailable"] = display.isHdrSdrRatioAvailable
            out["hdrSdrRatio"] = display.hdrSdrRatio
        }
        display.mode?.let { mode ->
            out["modeWidth"] = mode.physicalWidth
            out["modeHeight"] = mode.physicalHeight
            out["refreshRate"] = mode.refreshRate
        }
        // 屏幕旋转与当前窗口尺寸：全屏除了「图层变大」，往往还伴随一次
        // 90° 旋转（半屏竖屏 → 全屏横屏）。两者都会让 SF/HWC 重新决定这一层
        // 由谁合成，所以必须和尺寸一起记录，不能只记尺寸。
        out["rotation"] = when (display.rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            out["windowSize"] = "${bounds.width()}x${bounds.height()}"
        }
        return out
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        videoSurfaceHost?.release()
        videoSurfaceHost = null
        doviPlayer?.release()
        doviPlayer = null

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "PiliNara")
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                else -> result.notImplemented()
            }
        }

        // HDR 视频底层（SurfaceView）控制通道
        val surfaceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pilinara/video_surface",
        )
        val host = VideoSurfaceHost(this, surfaceChannel)
        videoSurfaceHost = host
        doviPlayer = DoviPlayer(this) { host.surfaceView() }

        surfaceChannel.setMethodCallHandler { call, result ->
            fun intArg(name: String): Int =
                (call.argument<Any>(name) as? Number)?.toInt() ?: 0
            fun boolArg(name: String): Boolean =
                call.argument<Any>(name) as? Boolean ?: false

            when (call.method) {
                "create" -> {
                    host.create(
                        owner = intArg("owner"),
                        left = intArg("x"),
                        top = intArg("y"),
                        width = intArg("width"),
                        height = intArg("height"),
                        wantTenBit = boolArg("tenBit"),
                    )
                    result.success(null)
                }
                "setRect" -> {
                    host.setRect(
                        owner = intArg("owner"),
                        left = intArg("x"),
                        top = intArg("y"),
                        width = intArg("width"),
                        height = intArg("height"),
                    )
                    result.success(null)
                }
                "setHdr" -> {
                    // 旧版接口，保留方法名兼容；窗口 HDR 改由 setWindowHdr 控制，
                    // 只在播放器首帧前预切，避免页面停留时整屏高亮。
                    result.success(null)
                }
                "setWindowHdr" -> {
                    // 回读 Window.colorMode：部分 ROM 会直接忽略这次请求，Dart 侧
                    // 只看「已请求」会误判面板已切到 HDR。回读值还是「被系统改写」
                    // 的唯一证据（全屏后实测会变成 COLOR_MODE_GAME）。
                    var applied = -1
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val requested = if (boolArg("enabled")) {
                            ActivityInfo.COLOR_MODE_HDR
                        } else {
                            ActivityInfo.COLOR_MODE_DEFAULT
                        }
                        runCatching {
                            window.setColorMode(requested)
                        }.onFailure { Log.w("PiliNara", "setColorMode failed", it) }
                        applied = window.colorMode
                        if (applied != requested) {
                            // setColorMode 走 Window.mColorMode，某些 ROM 会被随后
                            // 的窗口属性更新覆盖；再走一次 LayoutParams 这条路。
                            runCatching {
                                val lp = window.attributes
                                lp.colorMode = requested
                                window.attributes = lp
                            }.onFailure {
                                Log.w("PiliNara", "layoutParams colorMode failed", it)
                            }
                            val retried = window.colorMode
                            Log.w(
                                "PiliNara",
                                "setWindowHdr requested=$requested(${colorModeLabel(requested)}) " +
                                    "applied=$applied(${colorModeLabel(applied)}) " +
                                    "retried=$retried(${colorModeLabel(retried)})",
                            )
                            applied = retried
                        }
                    }
                    result.success(applied)
                }
                // 诊断：只读窗口色彩模式（可连续采样）。
                "windowColorMode" -> result.success(readWindowColorMode())
                // 诊断：显示端 HDR 能力与当前物理模式。
                "hdrDisplayInfo" -> result.success(describeHdrDisplay())
                "remove" -> {
                    host.remove(owner = intArg("owner"))
                    result.success(null)
                }
                "capture" -> host.capture(
                    owner = intArg("owner"),
                    result = result,
                )
                "probe" -> host.probe(
                    owner = intArg("owner"),
                    result = result,
                )
                "surfaceInfo" -> result.success(describeSurface())
                "doviPrepare" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val audioUrl = call.argument<String>("audioUrl")
                    val referer = call.argument<String>("referer").orEmpty()
                    val userAgent = call.argument<String>("userAgent").orEmpty()
                    result.success(
                        doviPlayer?.prepare(url, audioUrl, referer, userAgent) == true,
                    )
                }
                "doviRebind" -> {
                    result.success(doviPlayer?.rebindSurface() == true)
                }
                "doviPlay" -> {
                    doviPlayer?.play()
                    result.success(null)
                }
                "doviPause" -> {
                    doviPlayer?.pause()
                    result.success(null)
                }
                "doviSetVolume" -> {
                    (call.argument<Any>("volume") as? Number)?.toFloat()?.let {
                        doviPlayer?.setVolume(it)
                    }
                    result.success(null)
                }
                "doviSeek" -> {
                    (call.argument<Any>("positionMs") as? Number)?.toLong()?.let {
                        doviPlayer?.seekTo(it)
                    }
                    result.success(null)
                }
                "doviSetRate" -> {
                    (call.argument<Any>("rate") as? Number)?.toFloat()?.let {
                        doviPlayer?.setRate(it)
                    }
                    result.success(null)
                }
                "doviPosition" -> result.success(doviPlayer?.position() ?: 0L)
                "doviRelease" -> {
                    doviPlayer?.release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        doviPlayer?.release()
        doviPlayer = null
        videoSurfaceHost?.release()
        videoSurfaceHost = null
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 透明 Flutter surface 下，未被 Flutter 绘制的区域会露出窗口背景，
        // 统一给黑色，避免出现白色闪烁。
        window.setBackgroundDrawable(ColorDrawable(Color.BLACK))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
        methodChannel.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }
}
