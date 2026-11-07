package com.example.pilinara

import android.app.Activity
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.SurfaceView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource

/**
 * 杜比视界 profile 5 的 Media3 视频解码器（实验）。
 *
 * 视频由 ExoPlayer/MediaCodec 按 DoVi 流解码到应用的原生 SurfaceView，
 * 音频也由 ExoPlayer 播放；控制器把视频位置同步给 mpv，由 mpv 保留时间轴。
 */
class DoviPlayer(
    private val activity: Activity,
    private val surfaceProvider: () -> SurfaceView?,
) {
    companion object {
        private const val TAG = "DoviPlayer"

        /** 首帧看门狗：超过这个时间还没有画面就重新绑定 Surface。 */
        private const val FIRST_FRAME_TIMEOUT_MS = 3500L
    }

    private var player: ExoPlayer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var watchdog: Runnable? = null

    /** 上一次 [prepare] 的音轨地址，看门狗重建播放器时需要。 */
    private var lastAudioUrl: String? = null

    /** 看门狗已经重建过几次播放器，避免画面始终出不来时无限重建。 */
    private var recreateCount = 0

    @Volatile
    private var renderedFirstFrame = false

    fun prepare(
        url: String,
        audioUrl: String?,
        referer: String,
        userAgent: String,
    ): Boolean {
        release()
        val surfaceView = surfaceProvider()
        if (surfaceView == null) {
            Log.w(TAG, "prepare: native SurfaceView not ready")
            return false
        }
        lastAudioUrl = audioUrl
        return runCatching {
            fun source(u: String): ProgressiveMediaSource {
                val dataSourceFactory = DefaultHttpDataSource.Factory()
                    .setUserAgent(userAgent)
                    .setDefaultRequestProperties(
                        mapOf(
                            "Referer" to referer,
                            "User-Agent" to userAgent,
                        ),
                    )
                    .setAllowCrossProtocolRedirects(true)
                return ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(MediaItem.fromUri(Uri.parse(u)))
            }

            // B 站 DASH 的音视频是分开的，videoSource 本身没有音轨；
            // 有 audioSource 时用 MergingMediaSource 合并，否则 ExoPlayer
            // 只有视频，音轨会完全缺失。
            val videoSource = source(url)
            val mediaSource = if (audioUrl.isNullOrEmpty()) {
                videoSource
            } else {
                MergingMediaSource(videoSource, source(audioUrl))
            }
            val renderers = DefaultRenderersFactory(activity)
                .setEnableDecoderFallback(true)
            val exo = ExoPlayer.Builder(activity, renderers).build()
            exo.setVideoSurfaceView(surfaceView)
            exo.volume = 1f
            exo.playWhenReady = true
            exo.addListener(object : Player.Listener {
                override fun onRenderedFirstFrame() {
                    renderedFirstFrame = true
                    recreateCount = 0
                    cancelWatchdog()
                }

                override fun onPlayerError(error: PlaybackException) {
                    Log.w(TAG, "playback error: ${error.errorCodeName}", error)
                    // 音频轨合并失败（例如 Dolby/EC3 音轨）时回退到纯视频，
                    // 避免整个杜比视频黑屏。
                    if (!audioUrl.isNullOrEmpty()) {
                        prepare(url, null, referer, userAgent)
                    }
                }
            })
            exo.setMediaSource(mediaSource)
            exo.prepare()
            player = exo
            renderedFirstFrame = false
            scheduleFirstFrameWatchdog(exo, url, audioUrl, referer, userAgent, 0)
            true
        }.onFailure {
            Log.w(TAG, "prepare failed", it)
        }.getOrDefault(false)
    }

    /**
     * 首帧看门狗。
     *
     * 切分 P / 换集时原生 SurfaceView 会被复用，而旧 ExoPlayer 的 Surface 绑定
     * 可能已经失效：表现为「有声音、画面一直黑」，且 ExoPlayer 不报错。这里在
     * 首帧迟迟不来时重新绑定 Surface 并 seek 一次强制重绘，仍不行就重建播放器。
     */
    private fun scheduleFirstFrameWatchdog(
        exo: ExoPlayer,
        url: String,
        audioUrl: String?,
        referer: String,
        userAgent: String,
        attempt: Int,
    ) {
        cancelWatchdog()
        val runnable = Runnable {
            if (player !== exo || renderedFirstFrame) return@Runnable
            val sv = surfaceProvider()
            Log.w(TAG, "no first frame yet (attempt=$attempt, surface=$sv)")
            if (sv == null) {
                if (attempt < 3) {
                    scheduleFirstFrameWatchdog(
                        exo, url, audioUrl, referer, userAgent, attempt + 1,
                    )
                }
                return@Runnable
            }
            runCatching { exo.clearVideoSurface() }
            runCatching { exo.setVideoSurfaceView(sv) }
            runCatching { exo.seekTo(exo.currentPosition.coerceAtLeast(1L)) }
            if (attempt >= 1) {
                if (recreateCount >= 2) {
                    Log.w(TAG, "still no frame after recreate, give up")
                    return@Runnable
                }
                recreateCount += 1
                Log.w(TAG, "still no frame, recreate player (#$recreateCount)")
                prepare(url, audioUrl ?: lastAudioUrl, referer, userAgent)
            } else {
                scheduleFirstFrameWatchdog(
                    exo, url, audioUrl, referer, userAgent, attempt + 1,
                )
            }
        }
        watchdog = runnable
        mainHandler.postDelayed(runnable, FIRST_FRAME_TIMEOUT_MS)
    }

    /**
     * 原生 SurfaceView 被重建（切分 P、缓冲格式变化、Activity 重建）后，
     * 把当前 ExoPlayer 重新绑到新的 Surface 上。
     *
     * 只重绑不重新 prepare：重新 prepare 会跳回片头，而画面黑只是 Surface
     * 失效导致的，与媒体数据无关。
     */
    fun rebindSurface(): Boolean {
        val exo = player ?: return false
        val surfaceView = surfaceProvider() ?: return false
        return runCatching {
            exo.clearVideoSurface()
            exo.setVideoSurfaceView(surfaceView)
            true
        }.onFailure { Log.w(TAG, "rebindSurface failed", it) }.getOrDefault(false)
    }

    private fun cancelWatchdog() {
        watchdog?.let { mainHandler.removeCallbacks(it) }
        watchdog = null
    }

    fun play() {
        player?.play()
    }

    fun pause() {
        player?.pause()
    }

    fun seekTo(positionMs: Long) {
        player?.seekTo(positionMs.coerceAtLeast(0L))
    }

    fun setRate(rate: Float) {
        player?.setPlaybackSpeed(rate.coerceAtLeast(0.1f))
    }

    fun setVolume(volume: Float) {
        player?.volume = volume.coerceIn(0f, 1f)
    }

    fun position(): Long = player?.currentPosition ?: 0L

    fun release() {
        cancelWatchdog()
        // 分集/换源时先解绑旧 Surface，否则新 ExoPlayer 可能继续往旧
        // Surface 出画，Flutter 侧表现为画面定格不动。
        runCatching { player?.clearVideoSurface() }
        runCatching { player?.release() }
        player = null
        renderedFirstFrame = false
    }
}
