import 'dart:async' show Completer, StreamSubscription, Timer, unawaited;
import 'dart:convert' show ascii, utf8;
import 'dart:io' show Platform;
import 'dart:math' show max, min;
import 'dart:ui' as ui;

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/audio_normalization.dart';
import 'package:PiliPlus/models/common/dm_chart_source.dart';
import 'package:PiliPlus/models/common/super_resolution_type.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/user/danmaku_rule.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/models_new/video/video_shot/data.dart';
import 'package:PiliPlus/pages/danmaku/danmaku_model.dart';
import 'package:PiliPlus/pages/sponsor_block/block_mixin.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_status.dart';
import 'package:PiliPlus/plugin/pl_player/models/double_tap_type.dart';
import 'package:PiliPlus/plugin/pl_player/models/duration.dart';
import 'package:PiliPlus/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:PiliPlus/plugin/pl_player/models/hdr_config.dart';
import 'package:PiliPlus/plugin/pl_player/models/heart_beat_type.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/plugin/pl_player/models/speed_lock_hint.dart';
import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/plugin/pl_player/utils/native_video_surface_channel.dart';
import 'package:PiliPlus/services/live_pip_overlay_service.dart';
import 'package:PiliPlus/services/pip_overlay_service.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/android/android_helper.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/asset_utils.dart';
import 'package:PiliPlus/utils/desktop/window_controller.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/box_ext.dart';
import 'package:PiliPlus/utils/extension/native_geometry_ext.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/ios/pip_helper.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:archive/archive.dart' show getCrc32;
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/foundation.dart'
    show ValueNotifier, clampDouble, kDebugMode;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart'
    show DeviceOrientation, HapticFeedback, KeyDownEvent;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi show Size, Rectangle;
import 'package:path/path.dart' as path;
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:PiliPlus/plugin/pl_player/models/auto_audio_only_state.dart';

typedef PlayCallback = Future<void>? Function();
typedef PlayerInitCallback = Future<void> Function();
typedef PlayOwner = ({String tag, Type? type});

/// 仅诊断构建开启：把 mpv 的完整日志写到应用外部目录，便于定位 VO 初始化失败。
const bool _hdrVerboseLog = bool.fromEnvironment('HDR_VERBOSE_LOG');

class PlPlayerController with BlockConfigMixin, AudioNormalizationMixin {
  Player? _videoPlayerController;
  VideoController? _videoController;

  static PlPlayerController? _instance;

  final Rx<PlayerStatus> _playerStatus = Rx(.paused);
  PlayerStatus get playerStatus => _playerStatus.value;
  set playerStatus(PlayerStatus value) => _playerStatus.value = value;

  final Rx<DataStatus> dataStatus = Rx(.none);

  Duration? seekToPos;
  bool hasToasted = false;
  final RxBool isSeeking = false.obs;

  final RxInt position = RxInt(0);
  final RxInt seekPosition = RxInt(0);
  int get progress => isSeeking.value ? seekPosition.value : position.value;

  int get positionInMilliseconds => _useMedia3Dovi
      ? position.value * 1000
      : videoPlayerController?.state.position.inMilliseconds ?? 0;

  final RxInt buffered = RxInt(0);

  final RxInt duration = RxInt(0);

  int durationInMilliseconds = 0;

  void updateDuration(Duration value) {
    duration.value = value.inSeconds;
    durationInMilliseconds = value.inMilliseconds;
  }

  int _playerCount = 0;

  late double lastPlaybackSpeed = 1.0;
  final RxDouble _playbackSpeed = Pref.playSpeedDefault.obs;
  late final RxDouble _longPressSpeed = Pref.longPressSpeedDefault.obs;

  final RxDouble volume = RxDouble(
    PlatformUtils.isDesktop ? Pref.desktopVolume : 1.0,
  );
  final setSystemBrightness = Pref.setSystemBrightness;

  /// 系统音量（仅在应用内音量模式下用于追踪当前系统音量）
  final RxDouble systemVolume = RxDouble(1.0);

  /// duck 相关状态
  bool _isDucked = false;
  double _preDuckVolume = 1.0;
  final RxDouble brightness = (-1.0).obs;

  /// HDR 直通时的画面遮罩亮度。
  ///
  /// 原生 SurfaceView 独立于 Flutter 合成，系统/窗口亮度不一定能压住 HDR
  /// 图层（部分设备进入 HDR 后会把面板锁在峰值亮度）。这里把亮度手势换算成
  /// Flutter 侧黑色遮罩的透明度，保证至少可以向下调暗；-1 表示不启用遮罩。
  final RxDouble nativeBrightness = (-1.0).obs;

  final RxBool showControls = false.obs;

  final RxBool showBrightnessStatus = false.obs;

  final RxBool longPressStatus = false.obs;

  /// 长按倍速锁定（仅当次播放生效，不持久化）
  bool speedLocked = false;

  /// 长按倍速锁定提示（六态，驱动播放器顶部 toast）
  final Rx<SpeedLockHint> speedLockHint = SpeedLockHint.none.obs;

  /// 长按中滑动越线后的预备态：松手才提交锁定/解锁
  bool _speedLockArmed = false;
  Timer? _speedLockHintTimer;

  final RxBool controlsLock = false.obs;

  final RxBool isFullScreen = false.obs;
  void Function(bool isFullScreen)? onFullScreenChanged;
  // 系统原生 PiP 状态
  final RxBool isNativePip = false.obs;
  bool isLive = false;

  VoidCallback? onPortraitSlideUp;
  VoidCallback? onPortraitSlideDown;
  bool Function()? onPortraitSlideEnabled;

  bool get enablePortraitSlideVideo =>
      Pref.portraitSlideVideo &&
      onPortraitSlideUp != null &&
      onPortraitSlideEnabled?.call() == true &&
      isFullScreen.value &&
      !isLive;

  bool _isVertical = false;

  final Rx<VideoFitType> videoFit = Rx(.contain);

  late final RxBool continuePlayInBackground =
      Pref.continuePlayInBackground.obs;

  bool _autoPlay = false;

  // 记录历史记录
  int? _aid;
  String? _bvid;
  int? cid;
  int? roomId;
  int? _epid;
  int? _seasonId;
  int? _pgcType;
  VideoType _videoType = VideoType.ugc;
  int _heartDuration = 0;
  int? width;
  int? height;

  late final tryLook = !Accounts.get(AccountType.video).isLogin && Pref.p1080;

  late DataSource dataSource;

  /// 最近一次 [setDataSource] 的参数快照。
  ///
  /// 出画后端确定失败（Vulkan 不可用要换 MediaCodec 直通、纹理上 gpu-next
  /// 不可用要退回 gpu）时，当前播放器只能销毁重建：换 vo 的同时还必须换
  /// 解码方式（mediacodec_embed 只认同它一起创建的硬解直通），重建后用这份
  /// 快照从原位置重新打开同一个片源。
  Future<void> Function(Duration? seekTo, bool autoplay)? _reloadSource;

  /// 正在重建播放器，避免回退逻辑重入。
  bool _rebuildingOutput = false;

  /// 片源代次：每加载一次新片源 +1。
  ///
  /// 自动回退会销毁播放器再重新打开同一片源，如果这期间用户换了分P / 换集，
  /// 那次重建必须作废，否则会把刚切走的分P又打开一遍。
  int _sourceGeneration = 0;

  Timer? _timer;
  StreamSubscription? _subForSeek;

  Box setting = GStorage.setting;

  // final Durations durations;

  String get bvid => _bvid!;

  bool isCurrentVideoSource({
    required String bvid,
    required int cid,
  }) =>
      dataStatus.value == DataStatus.loaded && _bvid == bvid && this.cid == cid;

  /// 视频播放速度
  double get playbackSpeed => _playbackSpeed.value;

  // 长按倍速
  double get longPressSpeed => _longPressSpeed.value;

  /// [videoPlayerController] instance of Player
  Player? get videoPlayerController => _videoPlayerController;

  /// [videoController] instance of Player
  VideoController? get videoController => _videoController;

  bool isMuted = false;

  /// 听视频
  late final RxBool onlyPlayAudio = false.obs;

  /// 后台自动只听音频状态机
  AutoAudioOnlyState _autoAudioState = AutoAudioOnlyState.idle;
  Timer? _autoAudioOnlyTimer;
  bool _audioReopened = false;
  AppLifecycleState? _lastAppLifecycleState;
  bool _autoAudioRestoreInProgress = false;
  int _autoAudioRestoreGeneration = 0;
  Timer? _autoAudioRestoreTimer;
  StreamSubscription? _autoAudioRestoreSubscription;
  Completer<bool>? _autoAudioRestoreCompleter;
  final RxBool suppressBufferingIndicator = false.obs;

  /// 进/出全屏的过渡窗口（约 1.2s）。
  ///
  /// 进出全屏会改方向与 SystemUI，SurfaceView 随之重建（新 wid → 重新下发
  /// vo），mpv 在 VO 重建期间会短暂报 buffering；这期间把加载动画压住，
  /// 避免全屏切换时闪一下「加载中」。窗口 HDR 的第二次下发（600ms）也落在
  /// 窗口内，万一系统又闪一次 buffering 也不会露出来。
  final RxBool fullScreenTransition = false.obs;
  Timer? _fullScreenTransitionTimer;

  /// 过渡窗口过半后重新钉窗口 HDR 的定时器（见 [_setFullScreen]）。
  Timer? _fullScreenHdrRepinTimer;

  /// 自动恢复需要重初始化的回调（视频→playerInit，直播→queryLiveUrl）
  PlayerInitCallback? onNeedsPlayerInit;

  /// 镜像
  late final RxBool flipX = false.obs;

  late final RxBool flipY = false.obs;

  final RxBool isBuffering = true.obs;

  /// 全屏方向
  // ignore: unnecessary_getters_setters
  bool get isVertical => _isVertical;

  set isVertical(bool value) {
    _isVertical = value;
  }

  /// 弹幕开关
  late final RxBool enableShowDanmaku = Pref.enableShowDanmaku.obs;
  late final RxBool enableShowLiveDanmaku = Pref.enableShowLiveDanmaku.obs;
  RxBool get enableShowDanmakuAdaptive =>
      isLive ? enableShowLiveDanmaku : enableShowDanmaku;

  late final bool autoPiP = Pref.autoPiP;
  bool get isPipMode =>
      isNativePip.value ||
      (Platform.isAndroid && AndroidHelper.isPipMode) ||
      (PlatformUtils.isDesktop && isDesktopPip);
  late bool isDesktopPip = false;
  late nativeapi.Size _lastMinSize;
  late nativeapi.Rectangle _lastWindowBounds;
  static nativeapi.Rectangle? _lastPipBounds;

  nativeapi.Rectangle _adjustPipBounds(
    nativeapi.Rectangle lastRect,
    nativeapi.Size size,
    double aspectRatio,
  ) {
    final lastSize = lastRect.size;
    final lastOrientation = lastSize.orientation;
    final orientation = size.orientation;

    if (lastOrientation != orientation) {
      final double width, height;
      switch (orientation) {
        case .portrait:
          if (lastSize.width > size.height) {
            height = min(lastSize.width, _lastWindowBounds.size.height);
            width = height * aspectRatio;
          } else {
            height = size.height;
            width = size.width;
          }
        case .landscape:
          if (lastSize.height > size.width) {
            width = lastSize.height;
            height = width / aspectRatio;
          } else {
            height = size.height;
            width = size.width;
          }
      }

      return _lastPipBounds = nativeapi.Rectangle(
        x: lastRect.x,
        y: lastRect.y,
        width: width,
        height: height,
      );
    }
    return _lastPipBounds = nativeapi.Rectangle(
      x: lastRect.x,
      y: lastRect.y,
      width: lastSize.width,
      height: lastSize.width / aspectRatio,
    );
  }

  bool updatePipBounds(Window window) {
    if (isDesktopPip) {
      _lastPipBounds = window.bounds;
      return true;
    }
    return false;
  }

  late final showWindowTitleBar = Pref.showWindowTitleBar;
  late final RxBool isAlwaysOnTop = false.obs;
  void setAlwaysOnTop(bool value, {Window? window}) {
    window ??= WindowController.instance.window;
    if (window == null) return;

    isAlwaysOnTop.value = value;
    window.isAlwaysOnTop = value;
  }

  void exitDesktopPip() {
    final window = WindowController.instance.window;
    if (window == null) return;

    isDesktopPip = false;
    if (showWindowTitleBar) window.titleBarStyle = .normal;
    window
      ..minimumSize = _lastMinSize
      ..bounds = _lastWindowBounds
      ..aspectRatio = 0;
    setAlwaysOnTop(false, window: window);
  }

  void enterDesktopPip() {
    final window = WindowController.instance.window;
    if (window == null) return;

    if (isFullScreen.value) return;

    isDesktopPip = true;

    _lastMinSize = window.minimumSize;
    _lastWindowBounds = window.bounds;

    if (showWindowTitleBar) window.titleBarStyle = .hidden;

    const shortSide = 280.0;
    const minShortSide = 160.0;
    final nativeapi.Size size;
    final nativeapi.Size minimumSize;
    final state = videoPlayerController!.state;
    int width = state.width;
    int height = state.height;
    if (width == 0) width = this.width ?? 16;
    if (height == 0) height = this.height ?? 9;
    final aspectRatio = width / height;
    if (height > width) {
      size = nativeapi.Size(width: shortSide, height: shortSide / aspectRatio);
      minimumSize = nativeapi.Size(
        width: minShortSide,
        height: minShortSide / aspectRatio,
      );
    } else {
      size = nativeapi.Size(width: shortSide * aspectRatio, height: shortSide);
      minimumSize = nativeapi.Size(
        width: minShortSide * aspectRatio,
        height: minShortSide,
      );
    }

    window.minimumSize = minimumSize;
    setAlwaysOnTop(true, window: window);
    if (_lastPipBounds != null) {
      window.bounds = _adjustPipBounds(_lastPipBounds!, size, aspectRatio);
    } else {
      window.contentSize = size;
    }
    window.aspectRatio = aspectRatio;
  }

  void toggleDesktopPip() {
    if (isDesktopPip) {
      exitDesktopPip();
    } else {
      enterDesktopPip();
    }
  }

  late bool _isAutoEnterPip = false;
  bool get isAutoEnterPip => _isAutoEnterPip;

  static bool get _isCurrVideoPage {
    final routing = Get.routing;
    if (routing.route is! GetPageRoute) {
      return false;
    }
    return _isVideoPage(routing.current);
  }

  static bool _isVideoPage(String routeName) {
    return routeName == '/videoV' || routeName == '/liveRoom';
  }

  bool get _isInInAppPip {
    return PipOverlayService.isInPipMode || LivePipOverlayService.isInPipMode;
  }

  void enterPip({bool autoEnter = false}) {
    if (videoPlayerController case NativePlayer(:final state)) {
      if (Platform.isIOS) {
        if (videoController?.id.value case final textureId?) {
          IOSPipHelper.enter(
            textureId,
            width: state.width == 0 ? width : state.width,
            height: state.height == 0 ? height : state.height,
            autoEnter: autoEnter,
            state: _iosPipState(state),
          );
        }
        return;
      }
      PageUtils.enterPip(
        autoEnter: autoEnter,
        width: state.width == 0 ? width : state.width,
        height: state.height == 0 ? height : state.height,
        isLive: isLive,
        isPlaying: playerStatus.isPlaying,
      );
    }
  }

  // void _disableAutoEnterPipIfNeeded() {
  //   // 对齐上游逻辑，如果是从视频页返回到非视频页，则切断 Auto-Enter PiP
  //   if (!_isPreviousVideoPage) {
  //     _disableAutoEnterPip();
  //   }
  // }

  void disableAutoEnterPip() => _disableAutoEnterPip();

  void _disableAutoEnterPip() {
    if (_isAutoEnterPip) {
      if (Platform.isIOS) {
        IOSPipHelper.disableAutoEnter();
      } else {
        PiliAndroidHelper.disableAutoEnterPip();
      }
    }
  }

  Map<String, Object> _iosPipState(PlayerState state, [Duration? position]) {
    return {
      'isPlaying': playerStatus.isPlaying,
      'isBuffering': isBuffering.value,
      'isLive': isLive,
      'position': (position ?? state.position).inMilliseconds,
      'duration': durationInMilliseconds,
      'speed': state.rate,
    };
  }

  void _updateIOSPip([Duration? position]) {
    if (Platform.isIOS && IOSPipHelper.needsUpdate) {
      if (_videoPlayerController case final player?) {
        IOSPipHelper.update(_iosPipState(player.state, position));
      }
    }
  }

  // 弹幕相关配置
  late final enableTapDm = PlatformUtils.isMobile && Pref.enableTapDm;
  late RuleFilter filters = Pref.danmakuFilterRule;
  // 关联弹幕控制器
  DanmakuController<DanmakuExtra>? danmakuController;

  /// 弹幕遮挡区（弹幕层坐标系）。PLVideoPlayer 的几何驱动写入，PlDanmaku 消费；
  /// 两端都以此对象为交接点，画布重建（切 P）时 PlDanmaku 从这里补读。
  final ValueNotifier<Path?> danmakuMaskPath = ValueNotifier(null);
  bool showDanmaku = true;
  Set<int> dmState = <int>{};
  late final mergeDanmaku = Pref.mergeDanmaku;
  late final String midHash = getCrc32(
    ascii.encode(Accounts.main.mid.toString()),
    0,
  ).toRadixString(16);
  late final RxDouble danmakuOpacity = Pref.danmakuOpacity.obs;

  late List<double> speedList = Pref.speedList;
  late bool enableAutoLongPressSpeed = Pref.enableAutoLongPressSpeed;
  late final showControlDuration = Pref.enableLongShowControl
      ? const Duration(seconds: 30)
      : const Duration(seconds: 3);
  // 字幕
  late double subtitleFontScale = Pref.subtitleFontScale;
  late double subtitleFontScaleFS = Pref.subtitleFontScaleFS;
  late int subtitlePaddingH = Pref.subtitlePaddingH;
  int? tmpSubtitlePaddingB;
  late int subtitlePaddingB = Pref.subtitlePaddingB;
  late double subtitleBgOpacity = Pref.subtitleBgOpacity;
  final bool showVipDanmaku = Pref.showVipDanmaku; // loop unswitching
  late double subtitleStrokeWidth = Pref.subtitleStrokeWidth;
  late int subtitleFontWeight = Pref.subtitleFontWeight;
  // 副字幕(位置边距与主字幕共用)
  late double subtitleSecondaryFontScale = Pref.subtitleSecondaryFontScale;
  late double subtitleSecondaryFontScaleFS = Pref.subtitleSecondaryFontScaleFS;
  late double subtitleSecondaryBgOpacity = Pref.subtitleSecondaryBgOpacity;
  late double subtitleSecondaryStrokeWidth = Pref.subtitleSecondaryStrokeWidth;
  late int subtitleSecondaryFontWeight = Pref.subtitleSecondaryFontWeight;
  late double subtitleSecondarySpacing = Pref.subtitleSecondarySpacing;

  // settings
  late final showFSActionItem = Pref.showFSActionItem;
  late final enableShrinkVideoSize = Pref.enableShrinkVideoSize;
  late final enablePinchRotate = Pref.enablePinchRotate;
  late final darkVideoPage = Pref.darkVideoPage;
  late final enableSlideVolumeBrightness = Pref.enableSlideVolumeBrightness;
  late final enableSlideFS = Pref.enableSlideFS;
  late final enableScrollVolume = Pref.enableScrollVolume;
  late final enableDragSubtitle = Pref.enableDragSubtitle;
  late final fastForBackwardInSeconds = Pref.fastForBackwardDuration;
  late final fastForBackwardDuration = Duration(
    seconds: fastForBackwardInSeconds,
  );

  late final horizontalSeasonPanel = Pref.horizontalSeasonPanel;
  late final preInitPlayer = Pref.preInitPlayer;
  late final showRelatedVideo = Pref.showRelatedVideo;
  late final showVideoReply = Pref.showVideoReply;
  late final showBangumiReply = Pref.showBangumiReply;
  late final reverseFromFirst = Pref.reverseFromFirst;
  late final horizontalPreview = Pref.horizontalPreview;
  DmChartSource get dmChartSource => Pref.dmChartSource;
  bool get showDmChart => dmChartSource.isEnabled;
  late final showViewPoints = Pref.showViewPoints;
  late final showFsScreenshotBtn = Pref.showFsScreenshotBtn;
  late final showFsLockBtn = Pref.showFsLockBtn;
  late final showFsLockBtnRight = Pref.showFsLockBtnRight;
  late final lockFsRotation = Pref.lockFsRotation;
  late final keyboardControl = Pref.keyboardControl;
  late final uiScale = Pref.uiScale;

  late final bool autoEnterFullScreen = Pref.autoEnterFullScreen;
  late final bool autoExitFullscreen = Pref.autoExitFullscreen;
  late final bool autoPlayEnable = Pref.autoPlayEnable;
  late final bool enableVerticalExpand = Pref.enableVerticalExpand;
  late final bool pipNoDanmaku = Pref.pipNoDanmaku;

  late final bool tempPlayerConf = Pref.tempPlayerConf;

  static const int videoPictureParameterMin = -100;
  static const int videoPictureParameterMax = 100;
  static const int audioDelayMin = -1000;
  static const int audioDelayMax = 1000;
  static const int audioDelayStep = 10;
  static const Duration _videoPictureSaveDelay = Duration(milliseconds: 300);

  late final RxInt videoBrightness =
      (tempPlayerConf ? 0 : Pref.videoBrightness).obs;
  late final RxInt videoContrast =
      (tempPlayerConf ? 0 : Pref.videoContrast).obs;
  late final RxInt videoSaturation =
      (tempPlayerConf ? 0 : Pref.videoSaturation).obs;
  late final RxInt videoGamma = (tempPlayerConf ? 0 : Pref.videoGamma).obs;
  late final RxInt videoHue = (tempPlayerConf ? 0 : Pref.videoHue).obs;
  late final RxInt audioDelayMs = (tempPlayerConf ? 0 : Pref.audioDelayMs).obs;
  Timer? _videoPictureSaveTimer;

  late int? cacheVideoQa = PlatformUtils.isMobile || Platform.isLinux
      ? null
      : Pref.defaultVideoQa;
  late int cacheAudioQa = Pref.defaultAudioQa;
  bool enableHeart = true;

  /// 当前片源是否为 HDR / 杜比视界流，由播放页在 setDataSource 前写入。
  bool isHdrSource = false;

  /// 当前片源是否为杜比视界（画质 126）。
  ///
  /// `mediacodec_embed` / Media3 路径不预切窗口 HDR（杜比由解码器/ExoPlayer
  /// 自行处理）；改走 gpu-next 后由 Vulkan 交换链输出，需要和普通 HDR 一样
  /// 预切窗口 HDR，否则 libplacebo 会按 SDR 合成。
  bool isDolbyVisionSource = false;

  /// 当前片源是否为 HDR Vivid；同样不预切 HDR 窗口模式。
  bool isHdrVividSource = false;

  /// 当前选中视频流的 codecs 字符串（用于诊断 DoVi profile 5/8）。
  String? sourceCodecs;

  /// 当前片源是否为杜比视界 profile 5（dvh1.05/dvhe.05）。
  ///
  /// profile 5 的色彩是 IPTPQc2，只能靠杜比视界 RPU 元数据还原。B 站的
  /// 杜比视界片源基本都是 profile 5；拿不到 codecs 时也按 profile 5 处理，
  /// 宁可多走一次 gpu-next，也不要按普通 HDR 处理导致整片偏色。
  bool get isDolbyVisionProfile5 {
    if (!isDolbyVisionSource) return false;
    final codecs = sourceCodecs;
    if (codecs == null || codecs.isEmpty) return true;
    return codecs.contains('.05.');
  }

  /// 当前窗口是否已被预切到 HDR 色彩模式。
  bool _windowHdrRequested = false;

  /// 是否走 Media3/ExoPlayer 解码 profile 5 的真 DoVi 实验路径。
  bool _useMedia3Dovi = false;

  /// 当前 DoVi 视频流的 URL（视频轨，音频仍由 mpv 播放）。
  String? _doviVideoUrl;
  String? _doviAudioUrl;
  // Media3 路径的起始位置：doviPrepare 不带 start，必须在准备完成后
  // 补一次 doviSeek，否则每次打开都从 0 开始，进度条看起来归零。
  int _doviStartMs = 0;

  Timer? _doviSyncTimer;
  Timer? _doviPrepareTimer;
  bool _doviPrepared = false;
  bool _doviPlaying = false;
  bool _doviDisposed = false;
  // 每次换源/换集递增，用来丢弃上一集尚未完成的 doviPrepare 回调。
  int _doviGeneration = 0;
  // 当前复用的 mpv 播放器是否已按 Media3 DoVi 模式关闭视频轨/音频轨。
  bool _playerUsesMedia3Dovi = false;

  /// 最近一次自动回退的原因（VO 初始化失败、探针超时等），供诊断显示。
  String? _lastFallbackReason;

  /// 最近若干条 mpv error 级日志（含 vo/* 前缀）。
  ///
  /// media_kit 的 stream.error 只转发 file/ffmpeg/vd/ad/cplayer/stream
  /// 前缀的日志；VO 初始化失败的原因（vo/gpu-next、vo/androidvk）只会
  /// 出现在 stream.log 里，这里留一份尾巴给 HDR 状态诊断用。
  final List<String> _mpvErrorLog = [];

  /// 最近若干条与交换链 / HDR 相关的 mpv 日志（不限 level）。
  ///
  /// 全屏后变暗到底是「Vulkan 交换链掉回 8bit / SDR」「窗口 dataspace 被复位」
  /// 还是「libplacebo 色调映射目标偏低」，只能看 libplacebo 建交换链时打印的
  /// 面配置（info 级：Available surface configurations / Picked surface
  /// configuration）与 android_reconfig 的时间点。
  /// 这里留一份尾巴拼进 HDR 状态诊断，用户复现后一次性回传即可。
  final List<String> _mpvVoLog = [];

  /// [_mpvVoLog] 的条数上限：诊断文本要塞进设置页弹窗，留太多会刷屏。
  static const int _mpvVoLogLimit = 40;

  /// 收到的 mpv 日志按 level 计数。
  ///
  /// 用来证明「diagnostics 要求了 verbose，libplacebo 的行到底有没有到 Dart
  /// 这一层」：如果 verbose 计数一直是 0，说明是 media_kit / libmpv 那边没放开，
  /// 而不是过滤条件写错了。
  final Map<String, int> _mpvLogLevelCounts = {};

  /// 「默认 gpu-next」总开关：SDR 片源也走 gpu-next（libplacebo）渲染。
  ///
  /// 仅 Android 生效：桌面端由 media_kit 直接使用 libmpv 的渲染管线，
  /// 不需要也无法在这里指定 VO。
  bool get _defaultGpuNext => Platform.isAndroid && Pref.defaultGpuNext;

  /// HDR 设置页里手动选择的后端。
  HdrBackend get _configuredBackend => HdrBackend.fromValue(Pref.hdrBackend);

  /// 「默认 gpu-next」使用的渲染 API：自动 / Vulkan / OpenGL。
  GpuNextApi get _gpuNextApi => GpuNextApi.fromValue(Pref.gpuNextApi);

  /// 是否希望片源走 gpu-next（Vulkan）。
  ///
  /// 开启「默认 gpu-next」后，HDR / 杜比视界是否仍交给 MediaCodec 由子开关
  /// [Pref.gpuNextHdrMediaCodec] 决定；未开启时沿用 HDR 设置页的选择。
  bool get _vulkanNextWanted => _defaultGpuNext
      ? _gpuNextApi != GpuNextApi.opengl
      : _configuredBackend == HdrBackend.gpuNext;

  /// 当前片源是否需要「视频在 Flutter 之下」的 SurfaceView 出画。
  ///
  /// 只有真正的 HDR 片源才需要它：Flutter 纹理固定 8bit，会丢掉 HDR 元数据；
  /// 而 SDR 片源继续走纹理，保留硬解、Anime4K 等全部 mpv 渲染能力。
  /// 出画方式在播放器创建时确定，片源切换（切换画质/换集）时由
  /// [_switchOutputIfNeeded] 重建播放器。
  bool get _hdrSurfaceRequested =>
      Platform.isAndroid && Pref.enableHdr && Pref.hdrSurface && isHdrSource;

  /// HDR / 杜比视界片源实际使用的出画后端。
  HdrBackend get _hdrOutputBackend {
    // 杜比视界 profile 5 例外：色彩是 IPTPQc2，必须由 libplacebo 用 RPU
    // 元数据还原。MediaCodec（直通或拷贝）都拿不到解码器解析出的 DoVi
    // 元数据，交给它出画会整片偏色（发绿 / 发紫），所以这类片源不跟随
    // 「HDR / 杜比视界时切回 MediaCodec」；Vulkan 不可用时按设置页的
    // 「profile 5 回退方式」决定继续软解还是切回 MediaCodec。
    if (_defaultGpuNext && isDolbyVisionProfile5) {
      // 关闭「profile 5 软解」即明确要求走 MediaCodec：gpu-next 拿不到 RPU
      // 时色彩本身就不对，与其映射成 SDR 不如交给系统解码器直通，由设备
      // 自己的杜比视界能力出画（不支持的设备会偏色，但可以激发）。
      if (!Pref.gpuNextDoviSoft && Pref.enableHA) {
        return HdrBackend.mediacodecEmbed;
      }
      // Vulkan 可用时优先它：libplacebo 先把 IPTPQc2 还原成 HDR10，再交给
      // Vulkan 交换链输出，只有这条路能真正激发杜比视界 / HDR 面板。
      if (_gpuNextApi != GpuNextApi.opengl && !_vulkanVoBlocked) {
        return HdrBackend.gpuNext;
      }
      // Vulkan 不可用（驱动不支持 / 已判定失败 / 手动选了 OpenGL）：
      // 按「profile 5 回退方式」决定交给谁——继续软解保色彩，或切回
      // MediaCodec 直通换取面板激发（非杜比视界设备会偏色）。
      if (Pref.enableHA &&
          GpuNextDoviFallback.fromValue(Pref.gpuNextDoviFallback) ==
              GpuNextDoviFallback.mediacodec) {
        return HdrBackend.mediacodecEmbed;
      }
      return HdrBackend.gpuNextGl;
    }
    // 「默认 gpu-next」开启且要求 HDR / 杜比视界切回 MediaCodec：
    // 由系统解码器直接送显，是 Android 上点亮 HDR 面板最稳的路径。
    // 这条判断必须放在 OpenGL 之前：EGL 没有 HDR 交换链，渲染 API 选了
    // OpenGL 时只有 MediaCodec 直通才能真正激发 HDR。
    if (_defaultGpuNext && Pref.gpuNextHdrMediaCodec && Pref.enableHA) {
      return HdrBackend.mediacodecEmbed;
    }
    // 「默认 gpu-next」选了 OpenGL：HDR / 杜比视界也留在 gpu-next OpenGL。
    // Android 的 EGL 路径没有 HDR 交换链，画面会被 libplacebo 映射成 SDR，
    // 但兼容性最好，适合 Vulkan 驱动有问题的设备。
    if (_defaultGpuNext && _gpuNextApi == GpuNextApi.opengl) {
      return HdrBackend.gpuNextGl;
    }
    if (_vulkanNextWanted) {
      if (_vulkanVoBlocked) {
        return _useHdrDirectFallback
            ? HdrBackend.mediacodecEmbed
            : HdrBackend.gpuNextGl;
      }
      return HdrBackend.gpuNext;
    }
    return _configuredBackend;
  }

  bool get _wantNativeSurface =>
      _hdrSurfaceRequested &&
      // mediacodec_embed 必须硬解；用户关掉硬解时退回纹理，避免黑屏。
      (_hdrOutputBackend != HdrBackend.mediacodecEmbed || Pref.enableHA);

  /// 当前 libmpv 的 Vulkan VO 是否已确认不可用。
  ///
  /// 部分 libmpv 构建打开了 libplacebo 的 Vulkan，却没有编进 SPIR-V 编译器
  /// （shaderc / glslang）。这种构建上 `vo=gpu-next` + `gpu-context=androidvk`
  /// 会创建 VO 失败，表现为纯黑屏但音频/进度正常。检测到一次后，本进程内
  /// 自动改用 gpu-next 的 OpenGL 上下文，避免用户每次都要手动切后端。
  static bool _vulkanVoUnavailable = false;

  /// 上次判定 Vulkan 不可用的时间（配合 [_vulkanVoBlocked] 做冷却重试）。
  static DateTime? _vulkanFallbackAt;

  /// 纹理出画路径上 gpu-next（OpenGL）是否已确认不可用。
  ///
  /// 部分老驱动不支持 libplacebo 需要的 GLSL 版本，纹理会整块变黑。检测到
  /// 一次后本进程内退回 gpu，避免用户每次都要手动关掉「默认 gpu-next」。
  static bool _gpuNextTextureUnavailable = false;

  /// 纹理出画路径上 gpu-next Vulkan 是否已确认不可用。
  ///
  /// 纹理没有原生 Surface，Vulkan 交换链创建失败时整块纹理变黑。检测到
  /// 一次后本进程内改用同一 vo 的 OpenGL 上下文，避免一直黑屏。
  static bool _gpuNextVulkanTextureUnavailable = false;

  /// Vulkan 失败标记带 10 分钟冷却：冷却期内不再尝试（避免每部视频都黑屏
  /// 一段时间），冷却结束自动重试，让「部分片源 / 部分时刻能正常激发」的
  /// 设备自愈。
  static bool get _vulkanVoBlocked {
    if (!_vulkanVoUnavailable) return false;
    final at = _vulkanFallbackAt;
    return at == null ||
        DateTime.now().difference(at) < const Duration(minutes: 10);
  }

  bool get _shouldProbeVulkan => !_vulkanVoBlocked && _vulkanNextWanted;

  /// Vulkan 不可用时，HDR 片源是否改走 MediaCodec 直通。
  ///
  /// gpu-next OpenGL 只会把 HDR tone map 成 SDR，面板不会进入 HDR 模式，
  /// 用户看到的就是「亮度激发不起来」。MediaCodec 直通由系统解码送显，
  /// 虽然绕过 libplacebo，但能保留真正的 HDR 亮度与广色域。
  bool get _useHdrDirectFallback =>
      Pref.enableHA &&
      isHdrSource &&
      // profile 5 的 DoVi 元数据只有软解 + libplacebo 才拿得到，交给
      // MediaCodec 会偏色；profile 8 的基底就是 HDR10，直通反而更稳。
      !isDolbyVisionProfile5 &&
      !isHdrVividSource;

  /// 纹理出画时使用的后端（SDR 片源默认走这里）。
  ///
  /// 开启「默认 gpu-next」后 SDR 也交给 libplacebo：默认走 gpu-next OpenGL
  /// 纹理；渲染 API 选 Vulkan 时改用 Vulkan 纹理，失败后回退 OpenGL。
  HdrBackend get _textureBackend {
    if (!_defaultGpuNext || _gpuNextTextureUnavailable) return HdrBackend.gpu;
    if (_gpuNextApi == GpuNextApi.vulkan && !_gpuNextVulkanTextureUnavailable) {
      return HdrBackend.gpuNext;
    }
    return HdrBackend.gpuNextGl;
  }

  /// 本次播放实际使用的后端（Vulkan 失败后自动回退）。
  HdrBackend get _renderBackend =>
      _wantNativeSurface ? _hdrOutputBackend : _textureBackend;

  /// 当前是否走 gpu-next + Vulkan 这条真正的 HDR 交换链。
  ///
  /// 只有这条路径的窗口色彩模式需要额外照顾：进出全屏会改方向与 SystemUI，
  /// 部分 ROM 会顺手复位窗口 HDR 色彩模式（画面发灰、面板不再激发）。
  /// 注意这里**不做** VO 重建：mpv 的 `android_reconfig` 已经会重新
  /// setBuffersGeometry 并重下发 BT.2020/PQ dataspace，重建是多余的，
  /// 而 `vo=null` 会让 mpv 在重建期间报 buffering，全屏切换就闪加载动画。
  /// mediacodec_embed 由解码器直通，gpu-next-gl / gpu 是 SDR 输出，都不需要。
  bool get _isVulkanHdrOutput =>
      nativeSurfaceMode.value &&
      !_useMedia3Dovi &&
      _renderBackend == HdrBackend.gpuNext;

  /// 原生 SurfaceView 是否申请 10bit 缓冲格式。
  ///
  /// 由 gpu-next（libplacebo）渲染到 Surface 时请求 10bit，给 HDR / 杜比
  /// 视界留出位深；MediaCodec 直通时缓冲格式由解码器决定，不能强设，
  /// 否则部分设备直通会失败（此时颜色也由解码器负责）。
  bool get nativeSurfaceWantsTenBit {
    if (!_defaultGpuNext) {
      return _configuredBackend != HdrBackend.mediacodecEmbed;
    }
    return _hdrOutputBackend != HdrBackend.mediacodecEmbed;
  }

  /// 设置页切换后端时调用，允许用户主动重试 Vulkan。
  static void resetVulkanFallback() {
    _vulkanVoUnavailable = false;
    _vulkanFallbackAt = null;
    _gpuNextTextureUnavailable = false;
    _gpuNextVulkanTextureUnavailable = false;
  }

  /// 原生 SurfaceView 出画开关。Rx 以便播放页在出画方式变化时立即重建视频控件。
  final RxBool nativeSurfaceMode = false.obs;

  /// 当前视频控制器（响应式）。播放器因出画方式变化而重建时，界面据此换源。
  final Rxn<VideoController> videoOutput = Rxn<VideoController>();

  bool get useNativeSurface => nativeSurfaceMode.value;

  /// 由 [HdrHwdecMode] 与片源类型决定最终使用的 `--hwdec`。
  ///
  /// 直通解码（如 Android 的 `mediacodec`）不会把画面交回 mpv，色调映射、
  /// 峰值亮度等 HDR 参数会全部无效；因此「自动」模式下 HDR 片源改用拷贝解码，
  /// SDR 片源仍沿用「硬解模式」的设置。
  ///
  /// `mediacodec_embed` 是例外：它必须由 MediaCodec 直接解码到 Surface，
  /// 所以只要走这条 HDR 出画路径，就强制使用 `mediacodec`。
  String? _resolveHwdec() {
    final backend = _renderBackend;
    if (_wantNativeSurface && backend == HdrBackend.mediacodecEmbed) {
      return 'mediacodec';
    }
    if (!Pref.enableHA) return null;
    final config = HdrConfig.fromPref();
    // gpu-next 的色彩管理依赖 mpv 拿到解码后的帧。Android 的 mediacodec
    // 直通解码把画面留在解码器/Surface 里，libplacebo 只能按不完整的
    // 色彩信息处理，HDR 片源会出现偏色（杜比视界 profile 5 的 IPTPQc2
    // 也无法还原），半屏/全屏切换后更明显。因此只要后端是 gpu-next
    // （SDR 与 HDR 都一样）就强制拷贝解码，不再跟随「直通解码」设置。
    if (backend.isGpuNext) {
      // 杜比视界 profile 5 的 IPTPQc2 只能靠 RPU 元数据还原。Android 的
      // mediacodec-copy 拿不到解码器解析出的 DoVi side data，libplacebo
      // 只能按 BT.2020/PQ 处理，画面整体偏色；这类片源只要还在 gpu-next
      // 上就强制软解保留 RPU（关闭软解时上面已改走 MediaCodec 直通）。
      if (isDolbyVisionProfile5) {
        return 'no';
      }
      return config.copyHwdec;
    }
    if (!config.enabled) return Pref.hardwareDecoding;
    return switch (config.hwdecMode) {
      HdrHwdecMode.auto =>
        isHdrSource ? config.copyHwdec : Pref.hardwareDecoding,
      HdrHwdecMode.follow => Pref.hardwareDecoding,
      HdrHwdecMode.copy => config.copyHwdec,
      HdrHwdecMode.direct => config.directHwdec,
    };
  }

  late final progressType = Pref.btmProgressBehavior;
  late final enableQuickDouble = Pref.enableQuickDouble;
  late final fullScreenGestureReverse = Pref.fullScreenGestureReverse;

  late final isRelative = Pref.useRelativeSlide;
  late final offset = isRelative
      ? Pref.sliderDuration / 100
      : Pref.sliderDuration * 1000;

  num get sliderScale => isRelative ? durationInMilliseconds * offset : offset;

  // 播放顺序相关
  late PlayRepeat playRepeat = Pref.playRepeat;

  TextStyle _buildSubtitleStyle({
    required double fontScale,
    required double fontScaleFS,
    required int fontWeight,
    required double bgOpacity,
  }) => TextStyle(
    height: 1.5,
    fontSize: 16 * (isFullScreen.value ? fontScaleFS : fontScale),
    letterSpacing: 0.1,
    wordSpacing: 0.1,
    color: Colors.white,
    fontWeight: FontWeight.values[fontWeight],
    backgroundColor: bgOpacity == 0
        ? null
        : Colors.black.withValues(alpha: bgOpacity),
  );

  TextStyle get subTitleStyle => _buildSubtitleStyle(
    fontScale: subtitleFontScale,
    fontScaleFS: subtitleFontScaleFS,
    fontWeight: subtitleFontWeight,
    bgOpacity: subtitleBgOpacity,
  );

  TextStyle get subTitleSecondaryStyle => _buildSubtitleStyle(
    fontScale: subtitleSecondaryFontScale,
    fontScaleFS: subtitleSecondaryFontScaleFS,
    fontWeight: subtitleSecondaryFontWeight,
    bgOpacity: subtitleSecondaryBgOpacity,
  );

  late final Rx<SubtitleViewConfiguration> subtitleConfig = getSubConfig.obs;
  String? _activeVideoContextKey;

  SubtitleViewConfiguration get getSubConfig {
    final subTitleStyle = this.subTitleStyle;
    final secondaryStyle = subTitleSecondaryStyle;

    // 无背景时用描边保证可读性,主副字幕各自独立
    TextStyle? strokeOf(TextStyle base, double bgOpacity, double strokeWidth) =>
        bgOpacity == 0
        ? base.copyWith(
            color: null,
            background: null,
            backgroundColor: null,
            foreground: Paint()
              ..color = Colors.black
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth,
          )
        : null;

    return SubtitleViewConfiguration(
      style: subTitleStyle,
      strokeStyle: strokeOf(
        subTitleStyle,
        subtitleBgOpacity,
        subtitleStrokeWidth,
      ),
      secondaryStyle: secondaryStyle,
      secondaryStrokeStyle: strokeOf(
        secondaryStyle,
        subtitleSecondaryBgOpacity,
        subtitleSecondaryStrokeWidth,
      ),
      spacing: subtitleSecondarySpacing,
      padding: EdgeInsets.only(
        left: subtitlePaddingH.toDouble(),
        right: subtitlePaddingH.toDouble(),
        bottom: subtitlePaddingB.toDouble(),
      ),
      textScaleFactor: 1,
    );
  }

  void updateSubtitleStyle() {
    subtitleConfig.value = getSubConfig;
  }

  void onUpdatePadding(EdgeInsets padding) {
    tmpSubtitlePaddingB = null;
    subtitlePaddingB = padding.bottom.round().clamp(0, 200);
    updateSubtitleStyle();
    putSubtitleSettings();
  }

  static PlPlayerController? get instance => _instance;

  static bool instanceExists() {
    return _instance != null;
  }

  static void setPlayCallBack(
    PlayCallback? playCallBack, {
    PlayOwner? playOwner,
  }) {
    _playCallBack = playCallBack;
    _playOwner = playOwner;
  }

  static PlayOwner? _playOwner;
  static PlayOwner? get playOwner => _playOwner;
  static PlayCallback? _playCallBack;

  static Future<void>? playIfExists() {
    if (_instance != null && !(_instance!.playerStatus.isPlaying)) {
      return _instance!.play();
    }
    return _playCallBack?.call();
  }

  // try to get PlayerStatus
  static PlayerStatus? getPlayerStatusIfExists() {
    return _instance?.playerStatus;
  }

  static Future<void>? pauseIfExists({
    bool notify = true,
    bool isInterrupt = false,
  }) {
    if (_instance?.playerStatus.isPlaying ?? false) {
      return _instance?.pause(notify: notify, isInterrupt: isInterrupt);
    }
    return null;
  }

  static Future<void>? seekToIfExists(
    Duration position, {
    bool isSeek = true,
  }) {
    return _instance?.seekTo(position, isSeek: isSeek);
  }

  static double? getVolumeIfExists() {
    return _instance?.volume.value;
  }

  static Future<void>? setVolumeIfExists(
    double volumeNew, {
    bool showIndicator = true,
  }) {
    return _instance?.setVolume(volumeNew, showIndicator: showIndicator);
  }

  Box video = GStorage.video;

  bool visible = true;

  DeviceOrientation? _orientation;
  late final checkIsAutoRotate = Platform.isAndroid && mode != .gravity;
  StreamSubscription<OrientationParams>? _orientationListener;

  void _stopOrientationListener() {
    _orientationListener?.cancel();
    _orientationListener = null;
  }

  void _onOrientationChanged(OrientationParams param) {
    _orientation = param.orientation;
    if (Platform.isIOS && !visible) return;
    if (controlsLock.value) return;
    final orientation = param.orientation;
    final isFullScreen = this.isFullScreen.value;
    if (checkIsAutoRotate &&
        param.isAutoRotate != true &&
        (!isFullScreen ||
            _isVertical ||
            orientation == .portraitUp ||
            orientation == .portraitDown)) {
      return;
    }
    switch (orientation) {
      case .portraitUp:
        if (!horizontalScreen && !_isVertical && isFullScreen) {
          if (!isManualFS) {
            triggerFullScreen(status: false, orientation: orientation);
          }
        } else {
          portraitUpMode();
        }
      case .portraitDown:
        if (!horizontalScreen) return;
        portraitDownMode();
      case .landscapeLeft:
        if (controlsLock.value && (lockFsRotation || _isVertical)) return;
        if (!horizontalScreen && !isFullScreen) {
          triggerFullScreen(orientation: orientation, isManualFS: false);
        } else {
          landscapeLeftMode();
        }
      case .landscapeRight:
        if (controlsLock.value && (lockFsRotation || _isVertical)) return;
        if (!horizontalScreen && !isFullScreen) {
          triggerFullScreen(orientation: orientation, isManualFS: false);
        } else {
          landscapeRightMode();
        }
    }
  }

  // 添加一个私有构造函数
  PlPlayerController._() {
    if (PlatformUtils.isMobile && !DeviceUtils.isChromeOS) {
      _orientationListener = NativeDeviceOrientationPlatform.instance
          .onOrientationChanged(
            checkIsAutoRotate: checkIsAutoRotate,
            angleDegrees: Platform.isAndroid ? Pref.angleDegrees : null,
          )
          .listen(_onOrientationChanged);
    }

    if (!Accounts.heartbeat.isLogin || Pref.historyPause) {
      enableHeart = false;
    }

    if (Platform.isAndroid) {
      // onPipChanged 回调是本 fork 的系统 PiP 状态同步通道（上游没有），
      // 与下方的 autoPiP 注册共用同一个 MethodChannel handler
      Utils.channel.setMethodCallHandler((call) async {
        if (call.method == 'onPipChanged') {
          final bool isInPip = call.arguments as bool;
          isNativePip.value = isInPip;
          PipOverlayService.isNativePip = isInPip;
          LivePipOverlayService.isNativePip = isInPip;
          handleAutoAudioOnlyPipChanged(isInPip);
        }
      });

      if (autoPiP) {
        if (DeviceUtils.sdkInt < 31) {
          final func = Runnable.implement($Runnable(run: _onUserLeaveHint));
          AndroidHelper$ToDart.onUserLeaveHint = func;
          func.release();
        } else {
          _isAutoEnterPip = true;
        }
      }
    } else if (Platform.isIOS && autoPiP && IOSPipHelper.isAvailable) {
      _isAutoEnterPip = true;
    }
  }

  void _onUserLeaveHint() {
    if (_isInInAppPip) {
      enterPip();
      return;
    }
    if (playerStatus.isPlaying && _isCurrVideoPage) {
      enterPip();
    }
  }

  // 获取实例 传参
  static PlPlayerController getInstance({bool isLive = false}) {
    // 如果实例尚未创建，则创建一个新实例
    return (_instance ??= PlPlayerController._())
      ..isLive = isLive
      .._playerCount += 1;
  }

  static PlPlayerController ensureInstance({bool isLive = false}) {
    return (_instance ??= PlPlayerController._())..isLive = isLive;
  }

  static bool _isAnimPgcType(int? pgcType) => pgcType == 1 || pgcType == 4;

  void resetTempSettings({int? nextPgcType}) {
    if (!tempPlayerConf) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[PlPlayer] resetTempSettings (currentContext: $_activeVideoContextKey, nextPgcType: $nextPgcType)',
      );
    }

    enableShowDanmaku.value = Pref.enableShowDanmaku;
    enableShowLiveDanmaku.value = Pref.enableShowLiveDanmaku;
    videoPlayerServiceHandler?.enableBackgroundPlay = Pref.enableBackgroundPlay;
    continuePlayInBackground.value = Pref.continuePlayInBackground;
    playRepeat = Pref.playRepeat;
    cacheVideoQa = PlatformUtils.isMobile ? null : Pref.defaultVideoQa;
    cacheAudioQa = Pref.defaultAudioQa;
    if (_playbackSpeed.value != playSpeedDefault) {
      unawaited(setPlaybackSpeed(playSpeedDefault));
    }

    final defaultSuperResolutionType = _isAnimPgcType(nextPgcType)
        ? Pref.superResolutionType
        : SuperResolutionType.disable;
    superResolutionType.value = defaultSuperResolutionType;
    if (_videoPlayerController != null) {
      unawaited(
        setShader(defaultSuperResolutionType, _videoPlayerController!),
      );
    }

    resetAllVideoPictureParameters(persist: false);
  }

  int _normalizeVideoPictureParameter(num value) => value
      .round()
      .clamp(
        videoPictureParameterMin,
        videoPictureParameterMax,
      )
      .toInt();

  RxInt? _videoPictureParameterState(String property) => switch (property) {
    'brightness' => videoBrightness,
    'contrast' => videoContrast,
    'saturation' => videoSaturation,
    'gamma' => videoGamma,
    'hue' => videoHue,
    _ => null,
  };

  void setVideoPictureParameter(String property, num value) {
    final state = _videoPictureParameterState(property);
    if (state == null) return;

    final normalized = _normalizeVideoPictureParameter(value);
    state.value = normalized;
    _applyVideoPictureProperty(property, normalized);
    _scheduleVideoPictureSettingsSave();
  }

  void resetVideoPictureParameter(String property) {
    setVideoPictureParameter(property, 0);
  }

  void setAudioDelay(int value) {
    audioDelayMs.value = value.clamp(audioDelayMin, audioDelayMax).toInt();
    _applyAudioDelay();
    _scheduleVideoPictureSettingsSave();
  }

  void resetAudioDelay() => setAudioDelay(0);

  void _applyAudioDelay() {
    final player = _videoPlayerController;
    if (player == null || onlyPlayAudio.value) return;
    try {
      player.setProperty('audio-delay', (audioDelayMs.value / 1000).toString());
    } catch (_) {}
  }

  void resetAllVideoPictureParameters({bool persist = true}) {
    videoBrightness.value = 0;
    videoContrast.value = 0;
    videoSaturation.value = 0;
    videoGamma.value = 0;
    videoHue.value = 0;
    audioDelayMs.value = 0;
    applyVideoPictureParameters();
    if (persist) {
      _scheduleVideoPictureSettingsSave();
    }
  }

  void _applyVideoPictureProperty(String property, int value) {
    final player = _videoPlayerController;
    if (player == null || onlyPlayAudio.value) return;
    try {
      player.setProperty(property, value.toString());
    } catch (_) {}
  }

  void applyVideoPictureParameters([Player? target]) {
    final player = target ?? _videoPlayerController;
    if (player == null || onlyPlayAudio.value) return;
    try {
      player
        ..setProperty('brightness', videoBrightness.value.toString())
        ..setProperty('contrast', videoContrast.value.toString())
        ..setProperty('saturation', videoSaturation.value.toString())
        ..setProperty('gamma', videoGamma.value.toString())
        ..setProperty('hue', videoHue.value.toString())
        ..setProperty('audio-delay', (audioDelayMs.value / 1000).toString());
    } catch (_) {}
  }

  /// 上一次播放的 HDR 状态快照。
  ///
  /// 设置页无法在播放时打开（会先销毁播放页），所以播放过程中定时把状态
  /// 存下来，播放结束后仍可在「HDR 状态诊断」里回看。
  static String _lastHdrSnapshot = '';

  /// 全屏期间单独留一份快照。
  ///
  /// 设置页只能在离开播放页后打开，而离开前一般会先退出全屏——若只保留
  /// 「最近一次」快照，退出全屏后的状态会把全屏故障态覆盖掉，于是永远拿不到
  /// 「全屏时到底哪里不一样」的证据。
  static String _lastFullScreenSnapshot = '';
  Timer? _hdrSnapshotTimer;
  Timer? _fullScreenSnapshotTimer;

  /// 全屏后自检发现的问题，写进诊断，下播后仍能看到。
  String? _hdrSelfCheckNote;

  /// `setWindowHdr` 下发后系统回读的窗口色彩模式（4 = HDR，0 = 默认）。
  int? _windowHdrColorMode;

  /// 显示端 HDR 能力与当前物理模式（原生回传，随自检一起刷新）。
  Map? _displayHdrInfo;

  /// 当前（或上一次）播放器与 HDR 相关的运行时状态。
  ///
  /// 关键看几处：
  /// * `出画路径`：`SurfaceView` 才可能真正输出 HDR；
  /// * `vo`：必须是 `gpu-next`，`target-colorspace-hint` 才会生效；
  /// * `hwdec-current`：`mediacodec` 表示直通，画面不经过 mpv；
  /// * `视频色彩`：gamma 为 `pq` / `hlg` 才是 HDR 片源，`bt.1886` 是 SDR。
  /// 设置页读取用：优先由当前播放器实时生成，播放器已销毁时回退到上次快照。
  ///
  /// 设置页会在打开时销毁播放页，所以不能依赖 [PlPlayerController.instance]。
  static String get lastHdrInfo {
    if (_lastHdrSnapshot.isEmpty && _lastFullScreenSnapshot.isEmpty) {
      return '播放器尚未初始化。\n请先播放一个视频（播放中无法打开设置页），'
          '\n播放几秒后再回到这里查看上次播放的快照。';
    }
    return [
      if (_lastFullScreenSnapshot.isNotEmpty) '（全屏时的快照）\n$_lastFullScreenSnapshot',
      if (_lastHdrSnapshot.isNotEmpty) '（最近一次快照）\n$_lastHdrSnapshot',
    ].join('\n\n');
  }

  String _nativeRectLabel(ui.Rect? rect) {
    if (rect == null) return '-';
    return '${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)} '
        '${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)}';
  }

  String _sizeLabel(ui.Size? size) {
    if (size == null) return '-';
    return '${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}';
  }

  /// 显示端 HDR 能力与当前物理模式（原生回传）。
  ///
  /// 面板真正被激发时 hdr 为 true、colorMode 为 4；片源明明是 HDR 而这里
  /// 仍是 SDR，说明窗口/VO 没有把 HDR 交给系统，画面会被按 SDR 处理而发暗。
  String _displayHdrLabel(Map info) {
    final mode =
        '${info['modeWidth'] ?? '-'}x${info['modeHeight'] ?? '-'}@${info['refreshRate'] ?? '-'}Hz';
    return '显示端: hdr=${info['hdr'] ?? '-'} / '
        '峰值=${info['maxLuminance'] ?? '-'} / '
        '平均=${info['maxAvgLuminance'] ?? '-'} nits / '
        '模式=$mode / 支持类型=${info['hdrTypes'] ?? '-'}';
  }

  /// 诊断里「是否真的发生过自动回退」。
  ///
  /// 不能只比较 _renderBackend 与设置里的值：杜比视界 profile 5 会按自己的
  /// 规则改变后端（例如关闭「软解」时直接走 MediaCodec 直通），那是设置生效，
  /// 不是设备 / VO 失败触发的回退。
  String _autoFallbackLabel() {
    final configured = HdrBackend.fromValue(Pref.hdrBackend);
    if (_renderBackend == configured) return '';
    final fellBack =
        _vulkanVoBlocked ||
        _vulkanVoUnavailable ||
        _gpuNextTextureUnavailable ||
        _gpuNextVulkanTextureUnavailable;
    if (fellBack) {
      return '，已自动回退（原 ${configured.label}）';
    }
    return '，按当前片源 / 设置使用（HDR 设置里选的是 ${configured.label}）';
  }

  /// `vo` 只会显示 gpu-next / gpu，看不出底层到底是 Vulkan 还是 OpenGL；
  /// Media3 路径下 mpv 的 vo 只是纹理占位（null），直接读还会是空值。
  /// 因此按控制器实际下发的后端推断，保证任何片源都能看到实际渲染 API。
  String _voApiLabel() {
    // 只有 gpu-next / gpu 才有 Vulkan / OpenGL 之分；MediaCodec 直通由系统
    // 解码器出画，标上渲染 API 反而会误导。
    if (!_renderBackend.vo.contains('gpu')) return '';
    final api =
        _renderBackend.gpuApi ??
        (_gpuNextApi == GpuNextApi.vulkan ? 'vulkan' : 'opengl');
    return api == 'vulkan' ? 'Vulkan' : 'OpenGL';
  }

  /// 「播放信息」里展示的实际出画方式。
  ///
  /// Media3 出画时 mpv 的视频轨是关掉的（`vid=no`），`hwdec-current` 与
  /// `current-vo` 都是空值，直接读会让用户以为播放器没有在出画。
  String get infoHwdecLabel {
    if (_useMedia3Dovi) {
      return 'mediacodec（Media3 / ExoPlayer 解码，mpv 不解视频）';
    }
    final player = _videoPlayerController;
    if (player == null) return '-';
    try {
      final current = player.getProperty('hwdec-current');
      return current.isEmpty ? 'no（未开启硬解）' : current;
    } catch (_) {
      return '-';
    }
  }

  /// 同上：Media3 出画时 mpv 没有真正的 vo，按控制器实际下发的后端显示。
  String get infoVoLabel {
    final vo = _renderBackend.vo;
    final api = _voApiLabel();
    return api.isEmpty ? vo : '$vo（$api）';
  }

  String get hdrDebugInfo {
    final player = _videoPlayerController;
    if (player == null) return lastHdrInfo;

    String read(String property) {
      try {
        final value = player.getProperty(property);
        return value.isEmpty ? '-' : value;
      } catch (_) {
        return '-';
      }
    }

    final native = nativeSurfaceMode.value;
    final gpuApi = read('gpu-api');
    final gpuContext = read('gpu-context');
    // Media3 出画时 mpv 的 vo 只是纹理占位（null），直接读会显示成空，
    // 因此按控制器实际下发的后端取 vo 名称与渲染 API。
    final voName = _useMedia3Dovi ? _renderBackend.vo : read('vo');
    final voApi = _voApiLabel();
    final doviLabel = !isDolbyVisionSource
        ? '否'
        : '是（${isDolbyVisionProfile5 ? 'profile 5' : 'profile 8'}）';
    return [
      '出画路径: ${native ? 'SurfaceView(HDR)' : 'Texture(8bit)'}',
      if (_useMedia3Dovi)
        '真 DoVi 解码: Media3 / ExoPlayer（视频 + 音频），'
            'mpv 只保留时间轴（不走 mpv 的 vo，下面的 vo / hwdec 按实际后端显示）',
      if (native)
        '原生 Surface: wid=${_nativeWid ?? '-'}，'
            'SurfaceView 尺寸=${_nativeSurfaceSize == null ? '-' : '${_nativeSurfaceSize!.$1}x${_nativeSurfaceSize!.$2}'}',
      if (_lastProbeMean != null)
        '直通画面采样: mean=$_lastProbeMean / max=$_lastProbeMax / '
            'bright=$_lastProbeBright（mean≈0 表示 Surface 全黑）',
      if (_lastProbeShown != null)
        '直通 SurfaceView: shown=$_lastProbeShown / vis=$_lastProbeVisibility / '
            'alpha=$_lastProbeAlpha / parent=$_lastProbeParent / '
            'windowColorMode=$_lastProbeWindowColorMode',
      if (native) '直通画面矩形: ${_nativeRectLabel(nativeContentRect.value)}',
      if (native)
        '直通挖孔矩形: ${_nativeRectLabel(nativeHoleRect.value)} / '
            '页面尺寸: ${_sizeLabel(nativePageSize.value)}',
      'vo: $voName${voApi.isEmpty ? '' : '（$voApi）'}',
      'vo-configured: ${read('vo-configured')}',
      'gpu-api: $gpuApi / gpu-context: $gpuContext',
      // Media3 出画时 mpv 的视频轨是关掉的（vid=no），读 hwdec-current 只会是空值。
      'hwdec-current: ${_useMedia3Dovi ? 'mediacodec（Media3 / ExoPlayer 解码，mpv 不解视频）' : read('hwdec-current')}',
      '视频色彩: ${read('video-params/primaries')} / ${read('video-params/gamma')}',
      '像素格式: ${read('video-params/pixelformat')}',
      '色彩矩阵: ${read('video-params/colormatrix')}',
      // sig-peak 是相对 SDR 白点（100nits）的倍数，不是 nits。
      '片源 sig-peak: ${read('video-params/sig-peak')}（×100nits）',
      'tone-mapping: ${read('tone-mapping')}',
      'hdr-compute-peak: ${read('hdr-compute-peak')}',
      'target-peak: ${read('target-peak')}',
      'target-colorspace-hint: ${read('target-colorspace-hint')}',
      'target-prim/target-trc: ${read('target-prim')} / ${read('target-trc')}',
      // video-out-params 是 libplacebo 实际出画的色彩空间：gamma=pq 且
      // primaries=bt.2020 才是真的把 HDR 交给交换链；若是 bt.1886/bt.709
      // 就是被 tone map 回了 SDR（画面会偏灰偏暗）。
      'VO 输出色彩: ${read('video-out-params/primaries')} / '
          '${read('video-out-params/gamma')} / '
          '${read('video-out-params/colorlevels')}',
      // 这两项是 VO 拿到的帧参数（=片源尺寸），不是交换链尺寸；
      // 交换链真正的尺寸/格式只能从 libplacebo 的面配置日志里看。
      'VO 输入帧尺寸: ${read('video-out-params/w')}x${read('video-out-params/h')}',
      '窗口 HDR 预切: ${_windowHdrRequested ? '是' : '否'} / '
          '实际 colorMode=${_windowHdrColorMode ?? '-'}（4=HDR，0=默认）',
      if (_displayHdrInfo != null) _displayHdrLabel(_displayHdrInfo!),
      if (_hdrSelfCheckNote != null) '全屏 HDR 自检: $_hdrSelfCheckNote',
      '杜比视界: $doviLabel',
      'dither: ${read('dither')}',
      'HDR 开关: ${Pref.enableHdr ? '开' : '关'}，'
          '直通出画: ${Pref.hdrSurface ? '开' : '关'}，'
          '后端: ${_renderBackend.label} (${_renderBackend.gpuApi ?? '-'})'
          '${_autoFallbackLabel()}',
      'Vulkan 自动回退: ${_vulkanVoBlocked ? '已触发（跳过 Vulkan，10 分钟后自动重试）' : (_vulkanVoUnavailable ? '冷却已过，下次播放重试 Vulkan' : '未触发')}',
      '默认 gpu-next: ${_defaultGpuNext ? '开（渲染 API ${_gpuNextApi.label}，HDR / 杜比视界${Pref.gpuNextHdrMediaCodec ? '切回 MediaCodec' : '也用 gpu-next'}${isDolbyVisionProfile5 ? '，profile 5 ${Pref.gpuNextDoviSoft ? '软解' : '硬解拷贝'}，回退方式「${GpuNextDoviFallback.fromValue(Pref.gpuNextDoviFallback).label}」' : ''}）' : '关'}',
      if (native && _renderBackend.gpuApi == 'vulkan')
        'Vulkan HDR 窗口: ${read('options/android-vulkan-hdr')}'
            '（"-" 表示当前 libmpv 没有 android-vulkan-hdr 补丁，需重建）',
      if (_lastFallbackReason != null) '自动回退原因: $_lastFallbackReason',
      if (_mpvErrorLog.isNotEmpty) 'mpv 错误: ${_mpvErrorLog.last}',
      'mpv 日志: 要求 verbose，已收到 '
          '${_mpvLogLevelCounts.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
      if (_mpvVoLog.isNotEmpty)
        'mpv VO 日志（最近 ${_mpvVoLog.length} 条，--- 开头是应用侧动作）:\n'
            '${_mpvVoLog.join('\n')}',
      '片源判定: ${isHdrSource ? (isDolbyVisionSource ? 'HDR / 杜比视界' : (isHdrVividSource ? 'HDR Vivid' : 'HDR')) : 'SDR'}',
      if (sourceCodecs != null) '片源 codecs: $sourceCodecs',
    ].join('\n');
  }

  /// 播放期间每 5 秒刷新一次 [hdrDebugInfo] 快照，供下播后查看。
  void _startHdrSnapshot() {
    _hdrSnapshotTimer?.cancel();
    _fullScreenSnapshotTimer?.cancel();
    _hdrSnapshotTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_videoPlayerController == null) return;
      final info = hdrDebugInfo;
      // 全屏与半屏分开存：退出全屏后的快照不能覆盖全屏故障态。
      if (isFullScreen.value) {
        _lastFullScreenSnapshot = info;
        debugPrint('[HDR] fullscreen snapshot\n$info');
      } else {
        _lastHdrSnapshot = info;
        debugPrint('[HDR] snapshot\n$info');
      }
    });
  }

  /// 全屏切换后抓一次快照并复查 HDR 出画。
  ///
  /// 尺寸变化防抖 200ms、Vulkan VO 重建都要时间，抓得太早读到的是重建
  /// 过程中的状态；1.8s 后基本稳定，反映的才是「全屏播放时」的真实参数。
  void _scheduleFullScreenSnapshot() {
    _fullScreenSnapshotTimer?.cancel();
    _fullScreenSnapshotTimer = Timer(const Duration(milliseconds: 1800), () {
      _fullScreenSnapshotTimer = null;
      if (_videoPlayerController == null) return;
      unawaited(() async {
        // 先把「全屏稳定后 libplacebo 实际按什么色彩空间出画」记进时间线，
        // 半屏/全屏各一条，方便对照交换链有没有在这次尺寸变化里掉档。
        final player = _videoPlayerController;
        if (player != null) {
          String readOut(String key) {
            try {
              final value = player.getProperty(key);
              return value.isEmpty ? '-' : value;
            } catch (_) {
              return '-';
            }
          }

          _noteVoLog(
            '--- vo-out ${readOut('video-out-params/primaries')}/'
            '${readOut('video-out-params/gamma')} '
            '${readOut('video-out-params/w')}x${readOut('video-out-params/h')}',
          );
        }
        await _probeNativeSurface();
        if (_videoPlayerController == null) return;
        await _verifyFullScreenHdr();
        final info = hdrDebugInfo;
        if (isFullScreen.value) {
          _lastFullScreenSnapshot = info;
          debugPrint('[HDR] fullscreen snapshot\n$info');
        } else {
          _lastHdrSnapshot = info;
          debugPrint('[HDR] snapshot\n$info');
        }
      }());
    });
  }

  /// 全屏稳定后的 HDR 复查（只记录，不重建）。
  ///
  /// 全屏会改 SurfaceView 尺寸，android_reconfig 会重新下发 setBuffersGeometry
  /// 与 dataspace（见 context_android.c 的 android_apply_hdr_window）。窗口 HDR
  /// 色彩模式已在 `_setFullScreen` 里钉过，这里只把显示端的实际状态记进诊断。
  ///
  /// 注意不要根据这些值自动重建 VO：部分 ROM 的 Window.colorMode 回读始终是
  /// 0（半屏出画正常时也是 0），拿它当判据会在每次进全屏时多闪黑一帧；
  /// `vo=null` 重建期间 mpv 还会报 buffering，全屏切换就闪加载动画。
  Future<void> _verifyFullScreenHdr() async {
    if (_videoPlayerController == null || !isFullScreen.value) return;
    // 窗口色彩模式已在 _setFullScreen 里钉过，这里只记录，不要再动 VO/尺寸。
    final display = await NativeVideoSurfaceChannel.hdrDisplayInfo();
    if (display != null) _displayHdrInfo = display;
    final colorMode = (_displayHdrInfo?['colorMode'] as num?)?.toInt();
    if (colorMode != null) _windowHdrColorMode = colorMode;
    final displayHdr = _displayHdrInfo?['hdr'] as bool?;
    final suspect = (colorMode != null && colorMode != 4) || displayHdr == false;
    _hdrSelfCheckNote = suspect
        ? '全屏后显示端未报告 HDR（colorMode=$colorMode hdr=$displayHdr），'
              '若画面同时变暗，请把这份快照反馈'
        : null;
    debugPrint(
      '[HDR] fullscreen check colorMode=$colorMode displayHdr=$displayHdr '
      'suspect=$suspect',
    );
  }

  /// 设置页修改 HDR / 杜比视界选项后调用，使参数立即作用于当前播放器。
  void applyHdrOptions() {
    final player = _videoPlayerController;
    if (player == null) return;
    final hdrSurface = nativeSurfaceMode.value;
    // 「默认 gpu-next」等开关会改变出画后端。原生 Surface 出画时直接重下发
    // vo；纹理出画只能等下一次加载重建 VideoController。此时不要改写正在
    // 运行的 gpu-api / gpu-context，否则会触发 VO 重建，出现黑帧。
    if (!hdrSurface && _appliedTextureBackend != _textureBackend) return;
    if (hdrSurface && _nativeWid != null && _appliedBackend != _renderBackend) {
      _applyNativeSurface(target: player);
    }
    _applyHdrProperties(player, hdrSurface: hdrSurface);
  }

  // ---------------------------------------------------------------------------
  // 原生 SurfaceView（HDR 直通出画）
  // ---------------------------------------------------------------------------

  /// 当前原生 Surface 的所有者令牌（页面/小窗切换时用于过滤过期调用）。
  int? _nativeOwner;

  /// 原生 Surface 的 global ref，作为 mpv 的 `--wid`。
  int? _nativeWid;

  /// SurfaceView 在窗口中的实际像素尺寸。
  ///
  /// `--android-surface-size` 必须与 SurfaceView 的布局尺寸一致（与旧的
  /// hybrid 出画路径一致）；视频编码尺寸（如 3840x2160）由解码器自己决定，
  /// 拿它去设置 Surface 会让部分设备黑屏。
  (int, int)? _nativeSurfaceSize;

  int? _appliedWid;
  String? _appliedVo;
  HdrBackend? _appliedBackend;

  /// 纹理出画实际生效的渲染后端（gpu / gpu-next GL），用于开关切换后重建。
  HdrBackend? _appliedTextureBackend;
  (int, int)? _appliedSurfaceSize;

  /// 布局尺寸变化的防抖更新（小窗拖动/页面动画期间尺寸逐帧变化）。
  Timer? _nativeResizeTimer;

  /// 延迟解除绑定：页面 ↔ 小窗切换时新旧控件会短暂共存。
  Timer? _nativeDetachTimer;

  /// HDR 直通画面自检（播放几秒后采样一次，区分解码器黑屏和 Flutter 遮盖）。
  Timer? _nativeProbeTimer;

  /// Vulkan VO 可用性检查：创建失败时自动回退到 gpu-next OpenGL。
  Timer? _vulkanCheckTimer;
  Timer? _vulkanTextureCheckTimer;

  /// vo 错误日志的复核计时器（2 秒后复查 vo-configured）。
  Timer? _vulkanLogConfirmTimer;

  /// 最近一次 SurfaceView 画面采样结果（平均亮度；0 表示全黑）。
  int? _lastProbeMean;
  int? _lastProbeMax;
  int? _lastProbeBright;
  bool? _lastProbeShown;
  int? _lastProbeVisibility;
  double? _lastProbeAlpha;
  String? _lastProbeParent;
  int? _lastProbeWindowColorMode;

  /// 原生视频当前在屏幕上的矩形（逻辑像素，全局坐标）。
  ///
  /// 播放页根节点用它挖出唯一的透明区域；其余区域由根节点显式铺黑，
  /// 不再依赖整页透明或窗口背景。
  final ValueNotifier<ui.Rect?> nativeContentRect = ValueNotifier<ui.Rect?>(
    null,
  );

  /// 页面根节点实际挖出的透明矩形（页面本地坐标），仅用于诊断。
  final ValueNotifier<ui.Rect?> nativeHoleRect = ValueNotifier<ui.Rect?>(null);

  /// 页面根节点尺寸，仅用于诊断挖孔是否落在页面内。
  final ValueNotifier<ui.Size?> nativePageSize = ValueNotifier<ui.Size?>(null);

  /// 原生 Surface 就绪信号：自动播放前等待它，避免「先出声音、黑屏几秒」。
  Completer<void>? _nativeSurfaceReady;

  bool get nativeSurfaceAttached => _nativeWid != null;

  int? get nativeSurfaceOwner => _nativeOwner;

  void _setVideoController(VideoController? value) {
    if (identical(_videoController, value)) return;
    _videoController = value;
    videoOutput.value = value;
  }

  bool _isStaleNativeOwner(int owner) {
    final current = _nativeOwner;
    return current != null && owner < current;
  }

  /// 原生 SurfaceView 就绪后，把 `wid` / SurfaceView 尺寸交给 mpv。
  void attachNativeSurface(int owner, int wid, int width, int height) {
    if (wid == 0 || _isStaleNativeOwner(owner)) return;
    _nativeDetachTimer?.cancel();
    _nativeDetachTimer = null;
    _nativeOwner = owner;
    _nativeWid = wid;
    if (width > 1 && height > 1) {
      _nativeSurfaceSize = (width, height);
    }
    // 播放器还没创建完时先记下来，_initPlayer 会在 VideoController 初始化
    // 完成后补一次，避免刚设置的 vo 被 media_kit 的初始化覆盖成 null。
    if (_videoPlayerController != null) {
      if (_useMedia3Dovi) {
        if (_doviPrepared) {
          // 已经在播：Surface 换了就把 ExoPlayer 重新绑上，不能重新 prepare，
          // 否则会从这一集的开头重新解码。
          unawaited(NativeVideoSurfaceChannel.doviRebind());
        } else {
          _scheduleDoviPrepare();
        }
      } else {
        _applyNativeSurface();
      }
      _completeNativeSurfaceReady();
      if (_videoPlayerController!.state.playing) {
        _scheduleNativeProbe();
        _scheduleVulkanVoCheck();
      }
    }
  }

  /// Vulkan VO 创建失败时自动回退到 gpu-next OpenGL。
  ///
  /// 只在 Vulkan 后端、真正开始播放后检查：VO 创建成功时 `vo-configured`
  /// 为 yes，缺少 SPIR-V 编译器的 libmpv 则一直是 no。回退后重下 vo/wid，
  /// 并关闭窗口 HDR 预切（EGL 路径输出 SDR），避免继续黑屏。
  void _scheduleVulkanVoCheck() {
    _vulkanCheckTimer?.cancel();
    _vulkanCheckTimer = null;
    if (!nativeSurfaceMode.value || _useMedia3Dovi) return;
    if (!_shouldProbeVulkan) return;
    if (_appliedVo != 'gpu-next' || _appliedBackend != HdrBackend.gpuNext) {
      return;
    }
    _scheduleVulkanVoCheckAttempt(0);
  }

  /// VO 初始化可能比首帧更晚（大文件解析、驱动首次编译管线、网络缓冲），
  /// 因此最多查四次（约 3 / 6 / 10 / 15 秒）；播放器还在缓冲时顺延，
  /// 避免把「卡在缓冲」误判成 Vulkan 不可用。
  void _scheduleVulkanVoCheckAttempt(int attempt, {int stalls = 0}) {
    _vulkanCheckTimer?.cancel();
    const delays = [3000, 3000, 4000, 5000];
    _vulkanCheckTimer = Timer(
      Duration(
        milliseconds:
            delays[attempt < delays.length ? attempt : delays.length - 1],
      ),
      () {
        _vulkanCheckTimer = null;
        final player = _videoPlayerController;
        if (player == null) return;
        if (!nativeSurfaceMode.value || _useMedia3Dovi) return;
        if (_appliedBackend != HdrBackend.gpuNext) return;
        if (!player.state.playing) return;
        // 缓冲中解码器还没送出首帧，vo-configured 必然是 no；最多顺延 60 秒。
        if (player.state.buffering && stalls < 20) {
          _scheduleVulkanVoCheckAttempt(attempt, stalls: stalls + 1);
          return;
        }
        var configured = '';
        try {
          configured = player.getProperty('vo-configured');
        } catch (_) {}
        if (configured == 'yes') return;
        if (attempt < 3) {
          _scheduleVulkanVoCheckAttempt(attempt + 1, stalls: stalls);
          return;
        }
        _fallbackFromVulkan(
          'vo-configured="$configured", video=${player.state.width > 0}, '
          'buffering=${player.state.buffering}',
        );
      },
    );
  }

  /// 把失败的 Vulkan VO 切到 gpu-next OpenGL。
  ///
  /// 三个触发点：mpv 的 vo 错误日志（最快）、VO 错误回调，以及开始播放
  /// 2.5 / 5 / 7.5 秒后的 `vo-configured` 检查（覆盖只报 warning、不触发 error 的
  /// 构建）。重复调用会被标记挡住。
  void _fallbackFromVulkan(String reason) {
    if (_vulkanVoUnavailable) return;
    if (!nativeSurfaceMode.value || _useMedia3Dovi) return;
    if (!_vulkanNextWanted) return;
    _lastFallbackReason = reason;
    _vulkanVoUnavailable = true;
    _vulkanFallbackAt = DateTime.now();
    // 回退目标必须在标记置位之后再算：杜比视界 profile 5 会按「回退方式」
    // 决定交给 MediaCodec 直通还是留在 gpu-next OpenGL。
    final target = _renderBackend;
    debugPrint(
      '[HDR] Vulkan VO unavailable ($reason), fallback to ${target.name}',
    );
    SmartDialog.showToast(
      switch (target) {
        HdrBackend.mediacodecEmbed => 'Vulkan 输出不可用，已回退到 MediaCodec 直通',
        HdrBackend.gpu => 'Vulkan 输出不可用，已回退到 gpu',
        _ => 'Vulkan 输出不可用，已回退到 ${target.label}',
      },
    );
    _vulkanCheckTimer?.cancel();
    _vulkanCheckTimer = null;
    _nativeProbeTimer?.cancel();
    _nativeProbeTimer = null;
    _appliedWid = null;
    _appliedVo = null;
    _appliedBackend = null;
    // VO 初始化失败时 mpv 会自动 deselect 视频轨；只把 vid 设回 auto 是
    // 无操作，必须先置 no 再让 _applyNativeSurface 写 auto，触发重新选轨。
    try {
      _videoPlayerController
        ?..setProperty('vid', 'no')
        ..setProperty('vid', 'auto');
    } catch (_) {}
    _resetWindowHdr();
    _updateWindowHdrMode();
    // 回退到 MediaCodec 直通时只改 vo 是不够的：mediacodec_embed 要求解码器
    // 把画面直接输出到 Surface，而当前播放器是按硬件拷贝 / 软解创建的，
    // 切过去拿不到帧，界面就是一直黑屏。这种情况要销毁重建播放器。
    if (target == HdrBackend.mediacodecEmbed) {
      unawaited(_rebuildOutput());
      return;
    }
    _applyNativeSurface();
    _scheduleNativeProbe();
  }

  /// 单条 vo 错误日志不足以判定 Vulkan 不可用：重建 VO、窗口尺寸变化、
  /// 换视频轨时都可能瞬时打一条 error。这里先记下原因，2 秒后复查
  /// vo-configured，仍然是 no 才真正回退。
  void _confirmVulkanFailureFromLog(String line) {
    if (_vulkanVoUnavailable) return;
    _lastFallbackReason = line;
    _vulkanLogConfirmTimer?.cancel();
    _vulkanLogConfirmTimer = Timer(const Duration(seconds: 2), () {
      _vulkanLogConfirmTimer = null;
      final player = _videoPlayerController;
      if (player == null) return;
      if (!nativeSurfaceMode.value || _useMedia3Dovi) return;
      if (_appliedBackend != HdrBackend.gpuNext) return;
      var configured = '';
      try {
        configured = player.getProperty('vo-configured');
      } catch (_) {}
      if (configured == 'yes') {
        debugPrint('[HDR] 忽略瞬时 VO 报错: $line');
        return;
      }
      _fallbackFromVulkan(line);
    });
  }

  /// 纹理路径同理：瞬时 vo 报错先复核一次再决定是否回退 OpenGL。
  void _confirmVulkanTextureFailureFromLog(String line) {
    if (_gpuNextVulkanTextureUnavailable) return;
    _lastFallbackReason = line;
    _vulkanLogConfirmTimer?.cancel();
    _vulkanLogConfirmTimer = Timer(const Duration(seconds: 2), () {
      _vulkanLogConfirmTimer = null;
      final player = _videoPlayerController;
      if (player == null) return;
      if (nativeSurfaceMode.value || _useMedia3Dovi) return;
      if (_textureBackend != HdrBackend.gpuNext) return;
      var configured = '';
      try {
        configured = player.getProperty('vo-configured');
      } catch (_) {}
      if (configured == 'yes') {
        debugPrint('[HDR] 忽略瞬时 VO 报错: $line');
        return;
      }
      _fallbackFromGpuNextVulkanTexture(line);
    });
  }

  /// 纹理出画路径上 gpu-next 初始化失败时退回 gpu。
  ///
  /// 纹理无法像原生 Surface 那样立刻重建出画，这里只记录回退标记并提示，
  /// 下一次加载视频时 [VideoController] 会按 gpu 重建。
  void _fallbackFromGpuNextTexture(String reason) {
    if (_gpuNextTextureUnavailable) return;
    debugPrint('[HDR] gpu-next texture unavailable ($reason), fallback to gpu');
    _gpuNextTextureUnavailable = true;
    _lastFallbackReason = reason;
    SmartDialog.showToast('gpu-next 输出不可用，已回退到 gpu');
    unawaited(_rebuildOutput());
  }

  /// 纹理出画 + Vulkan 时检查 VO 是否真的建起来了。
  ///
  /// 纹理路径没有原生 Surface，Vulkan 初始化失败只会得到一张黑图，
  /// 因此开始播放后检查一次 `vo-configured`，失败则退回 gpu-next OpenGL。
  void _scheduleTextureVulkanVoCheck() {
    _vulkanTextureCheckTimer?.cancel();
    _vulkanTextureCheckTimer = null;
    _vulkanLogConfirmTimer?.cancel();
    _vulkanLogConfirmTimer = null;
    if (nativeSurfaceMode.value || _useMedia3Dovi) return;
    if (_textureBackend != HdrBackend.gpuNext) return;
    _scheduleTextureVulkanVoCheckAttempt(0);
  }

  /// 与 [_scheduleVulkanVoCheckAttempt] 同理：纹理路径也查四次（约
  /// 3 / 6 / 10 / 15 秒），缓冲期间顺延，避免把首帧慢误判成失败。
  void _scheduleTextureVulkanVoCheckAttempt(int attempt, {int stalls = 0}) {
    _vulkanTextureCheckTimer?.cancel();
    const delays = [3000, 3000, 4000, 5000];
    _vulkanTextureCheckTimer = Timer(
      Duration(
        milliseconds:
            delays[attempt < delays.length ? attempt : delays.length - 1],
      ),
      () {
        _vulkanTextureCheckTimer = null;
        final player = _videoPlayerController;
        if (player == null) return;
        if (nativeSurfaceMode.value || _useMedia3Dovi) return;
        if (_textureBackend != HdrBackend.gpuNext) return;
        if (!player.state.playing) return;
        if (player.state.buffering && stalls < 20) {
          _scheduleTextureVulkanVoCheckAttempt(attempt, stalls: stalls + 1);
          return;
        }
        var configured = '';
        try {
          configured = player.getProperty('vo-configured');
        } catch (_) {}
        if (configured == 'yes') return;
        if (attempt < 3) {
          _scheduleTextureVulkanVoCheckAttempt(attempt + 1, stalls: stalls);
          return;
        }
        _fallbackFromGpuNextVulkanTexture(
          'vo-configured="$configured", video=${player.state.width > 0}, '
          'buffering=${player.state.buffering}',
        );
      },
    );
  }

  /// 纹理出画路径上 gpu-next Vulkan 失败时退回 OpenGL 上下文。
  ///
  /// 纹理无法像原生 Surface 那样立刻重建，这里只记录回退标记并提示，
  /// 下一次加载视频时 [VideoController] 会按 OpenGL 重建。
  void _fallbackFromGpuNextVulkanTexture(String reason) {
    if (_gpuNextVulkanTextureUnavailable) return;
    debugPrint(
      '[HDR] gpu-next vulkan texture unavailable ($reason), fallback to OpenGL',
    );
    _gpuNextVulkanTextureUnavailable = true;
    _lastFallbackReason = reason;
    SmartDialog.showToast('Vulkan 纹理输出不可用，已回退到 gpu-next OpenGL');
    unawaited(_rebuildOutput());
  }

  /// 播放开始后采样 SurfaceView 画面。
  ///
  /// 仅用于诊断：PixelCopy 读取的是原生 Surface 自身的内容，不受 Flutter
  /// 是否遮盖影响。数据会写入 HDR 状态快照，不再自动回退出画方式——
  /// 早期自动回退会在杜比/暗场首帧误判，把正常播放切回纹理。
  void _scheduleNativeProbe() {
    if (!nativeSurfaceMode.value || !isHdrSource) return;
    _nativeProbeTimer?.cancel();
    _nativeProbeTimer = Timer(const Duration(milliseconds: 2500), () {
      _nativeProbeTimer = null;
      _probeNativeSurface();
    });
  }

  Future<void> _probeNativeSurface() async {
    final owner = _nativeOwner;
    if (owner == null || !nativeSurfaceMode.value) return;
    final data = await NativeVideoSurfaceChannel.probe(owner: owner);
    final mean = (data?['mean'] as num?)?.toInt();
    final max = (data?['max'] as num?)?.toInt();
    final bright = (data?['bright'] as num?)?.toInt();
    final shown = data?['shown'] as bool?;
    final visibility = (data?['vis'] as num?)?.toInt();
    final alpha = (data?['alpha'] as num?)?.toDouble();
    final parent = data?['parent'] as String?;
    final windowColorMode = (data?['windowColorMode'] as num?)?.toInt();
    debugPrint(
      '[HDR] probe mean=$mean max=$max bright=$bright '
      'shown=$shown vis=$visibility alpha=$alpha parent=$parent '
      'windowColorMode=$windowColorMode',
    );
    _lastProbeMean = mean;
    _lastProbeMax = max;
    _lastProbeBright = bright;
    _lastProbeShown = shown;
    _lastProbeVisibility = visibility;
    _lastProbeAlpha = alpha;
    _lastProbeParent = parent;
    _lastProbeWindowColorMode = windowColorMode;
    if (windowColorMode != null) _windowHdrColorMode = windowColorMode;
    // 显示端是否真的进了 HDR，是「面板有没有被激发」最直接的判据。
    final display = await NativeVideoSurfaceChannel.hdrDisplayInfo();
    if (display != null) _displayHdrInfo = display;
    debugPrint(
      '[HDR] display hdr=${display?['hdr']} '
      'colorMode=${display?['colorMode']} '
      'maxLuminance=${display?['maxLuminance']} '
      'mode=${display?['modeWidth']}x${display?['modeHeight']}@${display?['refreshRate']}',
    );
  }

  /// 按当前片源预切/复位窗口 HDR 模式。
  ///
  /// 在 setDataSource 开始、播放器与首帧出现之前切换，让面板的 HDR 模式
  /// 切换发生在加载/黑屏阶段，而不是首帧出声时整屏亮一下。
  /// [force] 为 true 时即使当前请求状态没变也重新下发一次，
  /// 用于窗口尺寸变化后把系统 HDR 色彩模式重新钉回来。
  void _updateWindowHdrMode({bool force = false}) {
    // 只有 mediacodec_embed 和 gpu-next(Vulkan) 有真正的 HDR 输出路径：
    // 前者由解码器直通，后者通过 Vulkan 交换链协商 HDR 色彩空间。
    // gpu-next-gl / gpu 的 EGL 路径实际输出 SDR，不能预切窗口 HDR。
    // 杜比视界走 gpu-next 时同样需要 HDR 窗口，否则 Vulkan 交换链没有
    // HDR dataspace；Media3 路径由 ExoPlayer 自己设置，HDR Vivid 交给系统。
    final backend = _renderBackend;
    final doviViaGpuNext =
        isDolbyVisionSource && backend.isGpuNext && !_useMedia3Dovi;
    final wanted =
        _wantNativeSurface &&
        backend.supportsHdrOutput &&
        (!isDolbyVisionSource || doviViaGpuNext) &&
        !isHdrVividSource;
    if (!force && wanted == _windowHdrRequested) return;
    _windowHdrRequested = wanted;
    debugPrint(
      '[HDR] window color mode=$wanted backend=${backend.value} '
      'hdr=$isHdrSource dovi=$isDolbyVisionSource media3=$_useMedia3Dovi',
    );
    unawaited(_applyWindowHdr(wanted));
  }

  /// 下发窗口 HDR 色彩模式，并记下系统回读的 Window.colorMode。
  ///
  /// 回读值才是「面板有没有真的切过去」的判据：部分 ROM 会直接忽略
  /// `setColorMode(COLOR_MODE_HDR)`，只记录「已请求」会让诊断误判。
  Future<void> _applyWindowHdr(bool enabled) async {
    try {
      final mode = await NativeVideoSurfaceChannel.setWindowHdr(
        enabled: enabled,
      );
      _windowHdrColorMode = mode;
      _noteVoLog('--- windowHdr=$enabled applied=$mode');
      debugPrint('[HDR] window color mode=$enabled applied=$mode');
    } catch (e) {
      debugPrint('[HDR] setWindowHdr failed: $e');
    }
  }

  /// 播放页销毁时复位窗口 HDR 模式，避免设置页/首页停留在 HDR 窗口模式。
  void _resetWindowHdr() {
    if (!_windowHdrRequested) return;
    _windowHdrRequested = false;
    unawaited(_applyWindowHdr(false));
  }

  void _releaseDoviPlayer() {
    _doviGeneration++;
    _doviPrepareTimer?.cancel();
    _doviPrepareTimer = null;
    _doviSyncTimer?.cancel();
    _doviSyncTimer = null;
    _doviPrepared = false;
    _doviPlaying = false;
    // 只允许当前活跃的控制器释放原生 DoVi 播放器；旧页面/旧控制器的
    // dispose 不能把新页面刚准备好的 Media3 播放器释放掉（会直接黑屏）。
    if (_useMedia3Dovi && identical(this, _instance)) {
      unawaited(NativeVideoSurfaceChannel.doviRelease());
    }
  }

  void _scheduleDoviPrepare() {
    if (!_useMedia3Dovi || _doviDisposed) return;
    _doviPrepared = false;
    _doviPrepareTimer?.cancel();
    final generation = ++_doviGeneration;
    _doviPrepareTimer = Timer(const Duration(milliseconds: 300), () {
      _doviPrepareTimer = null;
      unawaited(_prepareDoviPlayer(generation));
    });
  }

  Future<void> _prepareDoviPlayer(int generation) async {
    if (generation != _doviGeneration ||
        !_useMedia3Dovi ||
        _doviDisposed ||
        _doviPrepared) {
      return;
    }
    final url = _doviVideoUrl;
    if (url == null || url.isEmpty) return;
    final ok = await NativeVideoSurfaceChannel.doviPrepare(
      url: url,
      audioUrl: _doviAudioUrl,
      referer: HttpString.baseUrl,
      userAgent: BrowserUa.pc,
    );
    if (generation != _doviGeneration || _doviDisposed || !_useMedia3Dovi) {
      return;
    }
    if (!ok) {
      _doviPrepareTimer?.cancel();
      _doviPrepareTimer = Timer(const Duration(milliseconds: 500), () {
        _doviPrepareTimer = null;
        unawaited(_prepareDoviPlayer(generation));
      });
      return;
    }
    _doviPrepared = true;
    final startMs = _doviStartMs;
    if (startMs > 0) {
      position.value = startMs ~/ 1000;
      unawaited(
        NativeVideoSurfaceChannel.doviSeek(
          positionMs: startMs + Pref.doviAudioOffset,
        ),
      );
    }
    _startDoviSync();
  }

  void _startDoviSync() {
    _doviSyncTimer?.cancel();
    _doviSyncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_syncDovi());
    });
  }

  Future<void> _syncDovi() async {
    if (!_useMedia3Dovi || _doviDisposed || !_doviPrepared) return;
    final player = _videoPlayerController;
    if (player == null) return;
    final playing = player.state.playing;
    // mpv 只保留时间轴，进度以 Media3 为准，否则保存/恢复会停在 0 或旧值。
    final media3Pos = await NativeVideoSurfaceChannel.doviPosition();
    if (media3Pos > 0) {
      final sec = (media3Pos / 1000).round();
      if (sec != position.value) {
        position.value = sec;
        // stream.position 在 Media3 路径被忽略，这里补上 B 站历史心跳。
        // isManual 跳过 dataStatus/暂停检查：Media3 首帧就绪时 mpv 侧可能
        // 还没进入 playing，否则历史会被漏掉。
        makeHeartBeat(sec, isManual: true);
      }
    }
    if (playing != _doviPlaying) {
      _doviPlaying = playing;
      if (playing) {
        unawaited(NativeVideoSurfaceChannel.doviPlay());
      } else {
        unawaited(NativeVideoSurfaceChannel.doviPause());
      }
    }
    // Media3 自己播音频+视频，用 ExoPlayer 原生时钟；不再根据 mpv 位置
    // seek/调速，否则会周期性卡顿、定格。
  }

  /// 更新 SurfaceView 的布局尺寸。
  ///
  /// 防抖 200ms：小窗拖动/全屏动画期间尺寸逐帧变化，逐帧改
  /// `--android-surface-size` 会让视频输出反复重建（黑闪）。
  void resizeNativeSurface(int owner, int width, int height) {
    if (owner != _nativeOwner) return;
    if (width <= 1 || height <= 1) return;
    final size = (width, height);
    if (_nativeSurfaceSize == size) return;
    _nativeSurfaceSize = size;
    if (_videoPlayerController == null || _nativeWid == null) return;
    _nativeResizeTimer?.cancel();
    _nativeResizeTimer = Timer(const Duration(milliseconds: 200), () {
      _nativeResizeTimer = null;
      if (_nativeWid == null) return;
      final player = _videoPlayerController;
      final size = _nativeSurfaceSize;
      if (player == null || size == null) return;
      if (_appliedSurfaceSize == size) return;
      // 只改尺寸，不重建 VO：mpv 会走 android_reconfig，那里已经重新
      // setBuffersGeometry 并重下发 HDR dataspace。vo=null 重建会让 mpv
      // 在重建期间报 buffering，进出全屏就闪一下加载动画。
      _noteVoLog('--- android-surface-size ${size.$1}x${size.$2}');
      try {
        player.setProperty('android-surface-size', '${size.$1}x${size.$2}');
        _appliedSurfaceSize = size;
      } catch (_) {}
    });
  }

  /// 原生 Surface 被销毁（切后台、窗口重建等）时解除绑定。
  ///
  /// 延迟 400ms 执行：页面切小窗时新控件通常会紧接着 create 并接管，
  /// 立即把 `vo` 置空会让画面黑一下。
  void detachNativeSurface(int owner) {
    if (owner != _nativeOwner) return;
    _nativeDetachTimer?.cancel();
    final ownerPlayer = _videoPlayerController;
    _nativeDetachTimer = Timer(const Duration(milliseconds: 400), () {
      _nativeDetachTimer = null;
      if (_nativeOwner != owner) return;
      // 期间播放器被换掉（切视频/切画质）时不要再动新播放器。
      if (!identical(_videoPlayerController, ownerPlayer)) return;
      _nativeResizeTimer?.cancel();
      _nativeResizeTimer = null;
      _nativeOwner = null;
      _nativeWid = null;
      _appliedWid = null;
      _appliedVo = null;
      _appliedBackend = null;
      _appliedSurfaceSize = null;
      final player = ownerPlayer;
      if (player == null) return;
      try {
        player.setProperty('vo', 'null');
        player.setProperty('wid', '0');
      } catch (_) {}
    });
  }

  void _applyNativeSurface({Player? target}) {
    // 当前片源不是原生出画，或走 Media3 DoVi 时，都不能给 mpv 下发 vo/wid。
    if (!nativeSurfaceMode.value || _useMedia3Dovi) return;
    final player = target ?? _videoPlayerController;
    final wid = _nativeWid;
    final size = _nativeSurfaceSize;
    if (player == null || wid == null || size == null) return;
    if (size.$1 <= 1 || size.$2 <= 1) return;
    final backend = _renderBackend;
    final vo = backend.vo;
    // gpu-next 与 gpu-next-gl 的 vo 都是 gpu-next，只有 gpu-api 不同；
    // 只比较 vo 会导致切换后端后仍沿用旧的 Vulkan/OpenGL 上下文。
    final needVo =
        _appliedWid != wid ||
        _appliedVo != vo ||
        _appliedBackend != backend;
    try {
      if (!needVo && _appliedSurfaceSize != size) {
        player.setProperty('android-surface-size', '${size.$1}x${size.$2}');
        _appliedSurfaceSize = size;
      }
      if (needVo) {
        _noteVoLog('--- VO 重建 wid=$wid vo=$vo ${size.$1}x${size.$2}');
        // 顺序很重要：先复位 vo，再写 gpu-api/gpu-context 等初始化参数，
        // 然后给 wid，最后才设置 vo。gpu-context 只能在 VO 创建前生效；
        // media_kit 创建 VideoController 时会把 gpu-context 覆盖成 android，
        // 所以这里必须在 vo=gpu-next 之前重新写回 androidvk。
        // 尺寸同理放在 vo=null 之后：此时没有活着的交换链，写尺寸不会触发
        // android_reconfig 去动正在出画的窗口。
        player.setProperty('vo', 'null');
        _applyHdrProperties(player, hdrSurface: true);
        if (_appliedSurfaceSize != size) {
          player.setProperty('android-surface-size', '${size.$1}x${size.$2}');
          _appliedSurfaceSize = size;
        }
        player.setProperty('wid', '$wid');
        player.setProperty('vid', 'auto');
        player.setProperty('vo', vo);
        // target-prim/target-trc/target-colorspace-hint 属于 vo 选项，
        // 部分 libmpv 构建在 vo=null 时写入会被忽略；VO 创建后、首帧前
        // 再写一次，确保 libplacebo 按 HDR10 初始化交换链。
        _applyHdrProperties(player, hdrSurface: true, reset: false);
        _appliedWid = wid;
        _appliedVo = vo;
        _appliedBackend = backend;
      }
      debugPrint(
        [
          '[HDR] nativeSurface vo=$vo',
          'wid=$wid',
          'surface=${size.$1}x${size.$2}',
        ].join(' '),
      );
      if (needVo && backend == HdrBackend.gpuNext && player.state.playing) {
        _scheduleVulkanVoCheck();
      }
    } catch (_) {}
  }

  /// [keepSurface] 为 true 时保留已经挂上的原生 SurfaceView（owner/wid/尺寸），
  /// 只清掉属于旧播放器的 applied 状态。
  ///
  /// `_initPlayer` 不能无条件清掉 wid：NativeVideoSurface 可能已经先完成
  /// `create` 并把 surfaceCreated 回调送到 Dart，而 Flutter 侧组件不会再次
  /// 触发 create，wid 被清空后就再也挂不回去，表现为随机黑屏。
  void _resetNativeSurfaceState({bool keepSurface = false}) {
    _nativeDetachTimer?.cancel();
    _nativeDetachTimer = null;
    _nativeResizeTimer?.cancel();
    _nativeResizeTimer = null;
    _nativeProbeTimer?.cancel();
    _nativeProbeTimer = null;
    _vulkanCheckTimer?.cancel();
    _vulkanCheckTimer = null;
    _vulkanTextureCheckTimer?.cancel();
    _vulkanTextureCheckTimer = null;
    _vulkanLogConfirmTimer?.cancel();
    _vulkanLogConfirmTimer = null;
    if (!keepSurface) {
      _nativeOwner = null;
      _nativeWid = null;
      _nativeSurfaceSize = null;
    }
    _appliedWid = null;
    _appliedVo = null;
    _appliedBackend = null;
    _appliedTextureBackend = null;
    _appliedSurfaceSize = null;
    nativeContentRect.value = null;
    nativeBrightness.value = -1;
    _nativeSurfaceReady = null;
  }

  void _completeNativeSurfaceReady() {
    final completer = _nativeSurfaceReady;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// 写入 mpv 的 HDR 色彩处理参数。
  ///
  /// 只改色彩处理相关的运行期属性，不在这里决定 `--vo`：
  /// * 纹理出画时 `--vo` 由 media_kit 的 Android 控制器负责；
  /// * SurfaceView 出画时由 [_applyNativeSurface] 在 `wid` 就绪后设置。
  void _applyHdrProperties(
    Player player, {
    bool hdrSurface = false,
    bool reset = true,
  }) {
    try {
      // 先复位再写入，确保关闭 HDR 后不会残留上一次的参数。
      // 逐个 try：某些 libmpv 构建可能不认识其中某个属性，不能让它中断
      // 后续 HDR 参数（尤其是 gpu-api / gpu-context）的写入。
      // VO 创建后的二次写入传 reset:false，避免把刚协商好的 HDR 交换链
      // 又复位成 SDR。
      if (reset) {
        for (final entry in HdrConfig.resetProperties.entries) {
          try {
            player.setProperty(entry.key, entry.value);
          } catch (e) {
            debugPrint('[HDR] reset ${entry.key} failed: $e');
          }
        }
      }
      final properties = Map<String, String>.from(
        HdrConfig.fromPref().mpvProperties,
      );
      final renderBackend = _renderBackend;
      // 纹理出画时同样要写 gpu-next 的渲染参数（libplacebo 的 FBO / 抖动 /
      // 色域映射）；但纹理没有 HDR 交换链，不能请求 target-colorspace-hint。
      if (hdrSurface || renderBackend.isGpuNext) {
        final backend = renderBackend;
        // 即使不是 gpu-next，也要显式写回 gpu-api/gpu-context：播放器内
        // 切换后端时，上一次留下的 vulkan/androidvk 不能带到 gpu 路径。
        if (backend.gpuApi != null) {
          properties['gpu-api'] = backend.gpuApi!;
          properties['gpu-context'] = backend.gpuContext!;
        }
        // 是否让 libmpv 的 Android Vulkan 上下文按 HDR10 输出：fork 里的
        // androidvk 会据此把 ANativeWindow 切成 BT.2020/PQ + 10bit，并向
        // libplacebo 声明 preferred_csp，显示端才会真正进入 HDR 模式。
        properties['options/android-vulkan-hdr'] =
            hdrSurface &&
                backend.gpuApi == 'vulkan' &&
                isHdrSource &&
                !isHdrVividSource
            ? 'yes'
            : 'no';
        if (backend.isGpuNext) {
          // gpu-next（libplacebo）显式声明 gpu-api/gpu-context：Vulkan 走
          // androidvk（fork 里的 ra_ctx_vulkan_android），OpenGL 走 android。
          // 同时请求 10bit 浮点 FBO + colorspace hint，让 libplacebo 直接
          // 把 HDR 交给 Surface，而不是先 tone map 成 SDR。
          properties['gpu-dumb-mode'] = 'no';
          // fbo-format 是 OpenGL 的选项；Vulkan 的交换链格式由
          // libplacebo 根据 target-colorspace-hint 自行选择。
          if (backend.gpuApi == 'opengl') {
            properties['fbo-format'] = 'rgba16hf';
          }
          if (hdrSurface && backend.gpuApi == 'vulkan') {
            // Vulkan 交换链可以协商 HDR 色彩空间；strict 关闭，协商失败
            // 时仍可回退 SDR，避免整屏发灰/黑屏。
            properties['target-colorspace-hint'] = 'yes';
            properties['target-colorspace-hint-mode'] = 'target';
            properties['target-colorspace-hint-strict'] = 'no';
            // 只给 hint 时，部分 Vulkan 驱动仍会挑 SDR 交换链；显式声明
            // BT.2020 + PQ 目标，libplacebo 才会按 HDR10 渲染并申请
            // 10bit/HDR swapchain。SDR 片源不会走这条原生路径。
            // Android Vulkan 交换链的 HDR 元数据由系统/驱动决定，
            // 强行声明 bt.2020/pq 会让 swapchain 与解码器输出二次转换，
            // 表现为偏色；交给 libplacebo 按片源自动选择。
            properties['target-prim'] = 'auto';
            properties['target-trc'] = 'auto';
          } else {
            // OpenGL/EGL 的 Android 后端没有 HDR 交换链，必须让
            // libplacebo tone map 回 SDR；请求 HDR hint 会输出错误颜色。
            properties['target-colorspace-hint'] = 'no';
          }
          properties['hdr-compute-peak'] = 'yes';
          // auto 在部分 libplacebo 版本上会退化为 clip，高饱和场景
          // 明显偏色；perceptual 对 BT.2020→显示色域的映射更稳定。
          properties['gamut-mapping-mode'] = 'perceptual';
          properties['dither-depth'] = 'auto';
          properties['video-output-levels'] = 'auto';
        } else {
          // 只有 mediacodec_embed 由系统/解码器直通 HDR；gpu 的 libmpv
          // 构建没有 Android HDR EGL/dataspace，请求 HDR 输出会黑屏或
          // 颜色异常，继续关闭 hint。
          properties['target-colorspace-hint'] =
              backend == HdrBackend.mediacodecEmbed ? 'yes' : 'no';
        }
      }
      debugPrint('[HDR] properties: $properties');
      for (final entry in properties.entries) {
        // 逐个写入：某个属性在当前 libmpv 构建上不存在时，不能影响其余
        // HDR 参数（尤其是 gpu-api/gpu-context）。
        try {
          player.setProperty(entry.key, entry.value);
        } catch (e) {
          debugPrint('[HDR] set ${entry.key} failed: $e');
        }
      }
    } catch (_) {
      // 个别平台的 libmpv 构建不支持其中某些属性，忽略即可
    }
  }

  void _scheduleVideoPictureSettingsSave() {
    if (tempPlayerConf) return;
    _videoPictureSaveTimer?.cancel();
    _videoPictureSaveTimer = Timer(
      _videoPictureSaveDelay,
      persistVideoPictureSettings,
    );
  }

  void persistVideoPictureSettings() {
    _videoPictureSaveTimer?.cancel();
    _videoPictureSaveTimer = null;
    if (tempPlayerConf) return;
    setting.putAllNE({
      SettingBoxKey.videoBrightness: videoBrightness.value,
      SettingBoxKey.videoContrast: videoContrast.value,
      SettingBoxKey.videoSaturation: videoSaturation.value,
      SettingBoxKey.videoGamma: videoGamma.value,
      SettingBoxKey.videoHue: videoHue.value,
      SettingBoxKey.audioDelayMs: audioDelayMs.value,
    });
  }

  bool _processing = false;
  bool get processing => _processing;

  // offline
  bool get isFileSource => dataSource is FileSource;

  // 初始化资源
  Future<void> setDataSource(
    DataSource dataSource, {
    bool isLive = false,
    bool autoplay = true,
    // 初始化播放位置
    Duration? seekTo,
    // 初始化播放速度
    double speed = 1.0,
    int? width,
    int? height,
    Duration? duration,
    // 方向
    bool? isVertical,
    // 记录历史记录
    int? aid,
    String? bvid,
    int? cid,
    int? roomId,
    int? epid,
    int? seasonId,
    int? pgcType,
    VideoType? videoType,
    VoidCallback? onInit,
    Volume? volume,
    bool autoFullScreenFlag = false,
    int? rotate,
  }) async {
    try {
      _processing = true;
      _sourceGeneration++;
      // 新片源前先释放旧的 Media3 DoVi 播放器。
      _releaseDoviPlayer();
      // 换 P、换集、换清晰度都是一次新的 setDataSource：清掉上一部分源
      // 留下的 Vulkan 回退记忆，让这一部分重新尝试 Vulkan。播放器重建
      // （_rebuildOutput）本身不清，否则会陷入「回退 → 重建 → 再回退」的循环。
      if (!_rebuildingOutput) resetVulkanFallback();
      // 「默认 gpu-next」等开关会改变实际出画后端，Media3 DoVi 的判定
      // 必须按真正要用的后端来算，否则 gpu-next 明明支持 DoVi 却仍走 ExoPlayer。
      final backend = _hdrOutputBackend;
      // gpu-next 的 libplacebo 能直接解析 DoVi RPU；此时让 mpv 出画，
      // Media3 只作为 mediacodec_embed / 传统 gpu 的实验兜底。
      _useMedia3Dovi =
          isDolbyVisionProfile5 &&
          Pref.media3Dovi &&
          !backend.supportsDolbyVision;
      _doviVideoUrl = _useMedia3Dovi && dataSource is NetworkSource
          ? dataSource.videoSource
          : null;
      _doviAudioUrl = _useMedia3Dovi && dataSource is NetworkSource
          ? dataSource.audioSource
          : null;
      _doviStartMs = _useMedia3Dovi ? (seekTo?.inMilliseconds ?? 0) : 0;
      _doviDisposed = false;
      // 在创建播放器/首帧之前预切窗口 HDR 模式。
      _updateWindowHdrMode();
      // 换视频/换P：结束长按及倍速锁定，恢复长按前速度。
      // 必须先于临时配置重置执行，否则 lastPlaybackSpeed 会被先行覆盖
      await releaseSpeedLock();
      final nextVideoContextKey = PipOverlayService.buildVideoContextKey(
        videoType: videoType ?? VideoType.ugc,
        bvid: bvid,
        cid: cid,
        epId: epid,
        seasonId: seasonId,
      );
      final shouldResetTempSettings =
          tempPlayerConf &&
          _activeVideoContextKey != null &&
          nextVideoContextKey != null &&
          nextVideoContextKey != _activeVideoContextKey;
      if (shouldResetTempSettings) {
        resetTempSettings(nextPgcType: pgcType);
      }
      _activeVideoContextKey = nextVideoContextKey;

      // 换视频上下文时取消自动只听定时器，状态保持
      _cancelAutoAudioOnlyTimer();
      _interruptAutoAudioRestore();
      if (_autoAudioState == AutoAudioOnlyState.autoAudioOnly) {
        _audioReopened = true;
      }
      this.isLive = isLive;
      _videoType = videoType ?? VideoType.ugc;
      this.width = width;
      this.height = height;
      this.dataSource = dataSource;
      _reloadSource = (seek, play) => setDataSource(
        dataSource,
        isLive: isLive,
        autoplay: play,
        seekTo: seek,
        speed: speed,
        width: width,
        height: height,
        duration: duration,
        isVertical: isVertical,
        aid: aid,
        bvid: bvid,
        cid: cid,
        roomId: roomId,
        epid: epid,
        seasonId: seasonId,
        pgcType: pgcType,
        videoType: videoType,
        onInit: onInit,
        volume: volume,
        autoFullScreenFlag: autoFullScreenFlag,
        rotate: rotate,
      );
      _autoPlay = autoplay;
      // 初始化数据加载状态
      dataStatus.value = DataStatus.loading;
      // 初始化全屏方向
      _isVertical = isVertical ?? false;
      _aid = aid;
      _bvid = bvid;
      this.cid = cid;
      this.roomId = roomId;
      _epid = epid;
      _seasonId = seasonId;
      _pgcType = pgcType;

      if (showSeekPreview) {
        _clearPreview();
      }
      hideDesktopProgressPreview();
      cancelLongPressTimer();
      if (_videoPlayerController != null &&
          _videoPlayerController!.state.playing) {
        await pause(notify: false);
      }

      if (_playerCount == 0) {
        if (kDebugMode) {
          debugPrint(
            '[PlPlayer] setDataSource aborted: _playerCount == 0 before init',
          );
        }
        return;
      }
      // 片源切换（切换画质 / 换集）可能改变出画方式：SDR 走纹理、HDR 走
      // SurfaceView。出画方式在播放器创建时固定，因此这里按需重建播放器。
      await _switchOutputIfNeeded();
      // 配置Player 音轨、字幕等等
      await _createVideoController(dataSource, seekTo, volume, rotate);
      // 换集/换源时播放器和原生 SurfaceView 通常会被复用，不会再次触发
      // attachNativeSurface；这里必须重新准备 Media3 DoVi 播放器，否则旧
      // 播放器已 release，SurfaceView 会一直停在上一集最后一帧（假死定格）。
      if (_useMedia3Dovi) {
        _scheduleDoviPrepare();
      }

      if (_playerCount == 0) {
        if (kDebugMode) {
          debugPrint(
            '[PlPlayer] setDataSource aborted: _playerCount == 0 after createVideoController',
          );
        }
        _removeListeners();
        _setVideoController(null);
        _videoPlayerController?.dispose();
        _videoPlayerController = null;
        return;
      }

      updateDuration(duration ?? _videoPlayerController!.state.duration);
      position.value = buffered.value = seekTo?.inSeconds ?? 0;

      dataStatus.value = .loaded;
      if (_canUseSeekPreview) {
        unawaited(ensureVideoShot());
      }

      if (autoFullScreenFlag && autoEnterFullScreen) {
        triggerFullScreen(status: true);
      }

      // HDR 直通的原生 SurfaceView 需要播放页先挂载并完成布局，才能把 wid
      // 交给 mpv；否则 _initializePlayer 会白等超时。其它路径保持原有顺序。
      if (nativeSurfaceMode.value) {
        onInit?.call();
        await _initializePlayer();
      } else {
        await _initializePlayer();
        onInit?.call();
      }
    } catch (err, stackTrace) {
      dataStatus.value = DataStatus.error;
      if (kDebugMode) {
        debugPrint(stackTrace.toString());
        debugPrint('plPlayer err:  $err');
      }
    } finally {
      _processing = false;
    }
  }

  String? shadersDirPath;
  Future<String> get copyShadersToExternalDirectory async {
    if (shadersDirPath != null) {
      return shadersDirPath!;
    }

    return shadersDirPath = await AssetUtils.getOrCopy(
      'assets/shaders',
      Assets.mpvAnime4KShaders.followedBy(Assets.mpvAnime4KShadersLite),
      path.join(appSupportDirPath, 'anime_shaders'),
    );
  }

  late final isAnim = _pgcType == 1 || _pgcType == 4;
  late final Rx<SuperResolutionType> superResolutionType =
      (isAnim ? Pref.superResolutionType : SuperResolutionType.disable).obs;
  Future<void> setShader([SuperResolutionType? type, NativePlayer? pp]) async {
    if (type == null) {
      type = superResolutionType.value;
    } else {
      superResolutionType.value = type;
      if (isAnim && !tempPlayerConf) {
        setting.put(SettingBoxKey.superResolutionType, type.index);
      }
    }
    pp ??= _videoPlayerController!;
    switch (type) {
      case SuperResolutionType.disable:
        return pp.command(const ['change-list', 'glsl-shaders', 'clr', '']);
      case SuperResolutionType.efficiency:
        return pp.command([
          'change-list',
          'glsl-shaders',
          'set',
          PathUtils.buildShadersAbsolutePath(
            await copyShadersToExternalDirectory,
            Assets.mpvAnime4KShadersLite,
          ),
        ]);
      case SuperResolutionType.quality:
        return pp.command([
          'change-list',
          'glsl-shaders',
          'set',
          PathUtils.buildShadersAbsolutePath(
            await copyShadersToExternalDirectory,
            Assets.mpvAnime4KShaders,
          ),
        ]);
    }
  }

  /// 只保留 VO / 交换链相关的日志（libplacebo 的交换链面配置就挂在这些前缀下）。
  ///
  /// 早先还按关键字过滤，结果 libplacebo 的行被误杀掉，诊断里一条都没有；
  /// 现在只按前缀筛，关键字判断交给读者。
  bool _isVoDiagLog(PlayerLog log) {
    final prefix = log.prefix.toLowerCase();
    return prefix.startsWith('vo') ||
        prefix.startsWith('vulkan') ||
        prefix.contains('libplacebo') ||
        prefix.contains('vulkan') ||
        prefix.contains('androidvk');
  }

  /// 往 [_mpvVoLog] 追加一行（带时间戳，便于对齐全屏/尺寸变化的时刻）。
  void _noteVoLog(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    _mpvVoLog.add('$stamp $line');
    if (_mpvVoLog.length > _mpvVoLogLimit) _mpvVoLog.removeAt(0);
    debugPrint('[HDR][vo-log] $line');
  }

  Future<Player> _initPlayer() async {
    assert(_videoPlayerController == null);
    if (PlatformUtils.isMobile && Pref.enableAppVolume) {
      // 移动平台应用内音量模式：初始化系统音量
      systemVolume.value = (await FlutterVolumeController.getVolume()) ?? 1.0;
      // 从持久化存储读取应用内音量
      volume.value = Pref.appVolume;
    }
    final opt = {
      'video-sync': Pref.videoSync,
      if (Platform.isAndroid) 'ao': Pref.audioOutput,
      if (_hdrVerboseLog) ...{
        'log-file': '/sdcard/Android/data/com.example.pilinara/files/mpv.log',
        'msg-level': 'all=v',
      },
    };
    final autosync = Pref.autosync;
    if (autosync != '0') {
      opt['autosync'] = autosync;
    }

    // HDR 片源在 Android 上改用「Flutter 之下的 SurfaceView」出画：
    // Flutter 纹理固定 RGBA8888，会把 10bit / HDR 元数据丢掉；SurfaceView 才能
    // 让 MediaCodec / libmpv 直接送显并点亮面板 HDR。SDR 片源继续走纹理，
    // 保留硬解、Anime4K 等 mpv 渲染能力。
    // Media3 DoVi 即使没有开启 HDR 直通也需要原生 SurfaceView 承接 ExoPlayer
    // 的画面；漏掉这一项会让 nativeSurfaceMode=false，原生 Surface 不创建，
    // Media3 拿不到 surface，表现为整屏黑屏/卡住。
    nativeSurfaceMode.value = _wantNativeSurface || _useMedia3Dovi;
    // 保留可能已经挂上的原生 SurfaceView：NativeVideoSurface 只在首次
    // create 时上报 surfaceCreated，清掉 wid 后不会再收到第二次回调。
    _resetNativeSurfaceState(keepSurface: true);
    _nativeSurfaceReady = nativeSurfaceMode.value ? Completer<void>() : null;
    debugPrint(
      '[HDR] init: enable=${Pref.enableHdr} direct=${Pref.hdrSurface} '
      'hdrSource=$isHdrSource surface=${nativeSurfaceMode.value} '
      'vo=${nativeSurfaceMode.value ? _renderBackend.vo : '-'} '
      'gpu=${_renderBackend.gpuApi ?? '-'} hwdec=${_resolveHwdec()}',
    );

    final hwdec = _resolveHwdec();
    final player = await Player.create(
      configuration: PlayerConfiguration(
        // 临时调成 verbose：libplacebo 建交换链时打的
        // 「Available surface configurations / Picked surface configuration」
        // 在 mpv 里至少在 info 以上（实测 info 收不到，故放到 verbose），
        // 是判断全屏后交换链有没有掉回 8bit/SDR 的唯一证据。
        // 见 docs/hdr.md 7.5；定位完改回 kDebugMode ? .warn : .error。
        logLevel: .verbose,
        options: opt,
      ),
    );

    // Media3 DoVi：mpv 只负责音频，视频交给原生 ExoPlayer；必须在此之前
    // 关闭 mpv 的视频轨，避免两个解码器抢同一个 Surface。
    _playerUsesMedia3Dovi = _useMedia3Dovi;
    if (_useMedia3Dovi) {
      player.setProperty('vid', 'no');
      player.setProperty('aid', 'no');
    }

    // VO 初始化失败只会出现在 mpv 日志里（media_kit 的 stream.error 不转发
    // vo/* 前缀的日志）：原生 Vulkan 建不起交换链时画面一直全黑，纹理
    // Vulkan 则是一张黑图。这里按日志提前回退，并留一份尾巴供诊断显示。
    player.stream.log.listen((log) {
      // 交换链 / 色彩空间相关的日志不分 level 都留一份：libplacebo 建交换链时
      // 打的「Available surface configurations / Picked surface configuration」
      // 恰好是全屏后「有没有 10bit + HDR 面」的唯一证据。
      _mpvLogLevelCounts[log.level] = (_mpvLogLevelCounts[log.level] ?? 0) + 1;
      if (_isVoDiagLog(log)) _noteVoLog('${log.prefix}: ${log.text}');
      if (log.level != 'error' && log.level != 'fatal') return;
      final line = '${log.prefix}: ${log.text}';
      _mpvErrorLog.add(line);
      if (_mpvErrorLog.length > 8) _mpvErrorLog.removeAt(0);
      debugPrint('[HDR][mpv-log] $line');
      if (!log.prefix.startsWith('vo')) return;
      final text = log.text.toLowerCase();
      if (!(text.contains('vulkan') ||
          text.contains('swapchain') ||
          text.contains('spir-v') ||
          text.contains('failed to create') ||
          text.contains('could not create'))) {
        return;
      }
      // 先复核再回退：VO 重建、窗口 resize、切轨时都可能瞬时报错
      if (nativeSurfaceMode.value) {
        _confirmVulkanFailureFromLog(line);
      } else if (_appliedTextureBackend == HdrBackend.gpuNext) {
        _confirmVulkanTextureFailureFromLog(line);
      }
    });

    // 渲染后端出错（例如 EGL 10bit 配置创建失败）会在这里出现，便于排查黑屏
    player.stream.error.listen((event) {
      debugPrint('[HDR][mpv-error] $event');
      final message = event.toString().toLowerCase();
      if (message.contains('video_out') ||
          message.contains('spir-v') ||
          message.contains('vulkan device') ||
          message.contains('gpu context')) {
        _fallbackFromVulkan('mpv error: $event');
      }
      // 纹理出画时 gpu-next 的 VO 由 media_kit 创建，老驱动可能直接失败。
      if (!nativeSurfaceMode.value &&
          _appliedTextureBackend?.isGpuNext == true &&
          (message.contains('gpu-next') ||
              message.contains('libplacebo') ||
              message.contains('video output') ||
              message.contains('failed to initialize'))) {
        if (_appliedTextureBackend == HdrBackend.gpuNext) {
          _fallbackFromGpuNextVulkanTexture('mpv error: $event');
        } else {
          _fallbackFromGpuNextTexture('mpv error: $event');
        }
      }
    });

    // HDR / 杜比视界：必须在视频输出初始化前写入，vo 创建时才会读取这些参数
    _applyHdrProperties(player, hdrSurface: nativeSurfaceMode.value);
    // >100% 的音量走 af 增益+限幅，避免直接放大 mpv volume 导致削波
    await setVolumeCapped(
      player,
      PlatformUtils.isMobile ? Pref.playerVolume / 100 : volume.value,
    );

    assert(_videoController == null);

    final videoController = await VideoController.create(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: hwdec != null,
        androidAttachSurfaceAfterVideoParameters: false,
        hwdec: hwdec,
        // 视频画面由应用层的原生 SurfaceView 提供，media_kit 不创建纹理。
        // Media3 DoVi 路径下 mpv 只播放音频，不需要 external surface。
        androidExternalSurface: nativeSurfaceMode.value && !_useMedia3Dovi,
        // HDR 片源的渲染后端可在设置里切换（mediacodec_embed / gpu-next / gpu），
        // 不同设备驱动对 10bit EGL 的支持差异很大。
        // 纹理出画时 SDR 片源也要走 gpu-next：只有 OpenGL 上下文能直接
        // 输出纹理，因此固定使用 gpu-next + android (OpenGL)。
        vo: nativeSurfaceMode.value && !_useMedia3Dovi
            ? _renderBackend.vo
            : (_defaultGpuNext ? HdrBackend.gpuNextGl.vo : null),
      ),
    );
    _setVideoController(videoController);
    _appliedTextureBackend = nativeSurfaceMode.value ? null : _textureBackend;

    // media_kit 的 AndroidVideoController.create 会无条件写
    // gpu-context=android，把上面 Vulkan 的 androidvk 覆盖掉。
    // 在创建 VO 之前补写一次，否则 gpu-next 永远走 OpenGL。
    _applyHdrProperties(player, hdrSurface: nativeSurfaceMode.value);

    // media_kit 的 AndroidVideoController.create 会无条件写 vid=auto，把上面
    // 关掉的 mpv 视频轨重新打开：Media3 DoVi 路径下 mpv 会再解一遍视频，既
    // 白烧解码器，也会和 ExoPlayer 抢同一块 Surface（表现为 aimagereader 取帧
    // 失败 / 黑屏）。创建完 VideoController 之后再补写一次。
    if (_useMedia3Dovi) {
      player.setProperty('vid', 'no');
      player.setProperty('aid', 'no');
    }

    if (Platform.isAndroid) {
      // Avoid sizing the surface using mpv's idle window between media loads.
      player.setProperty('force-window', 'no');
    }

    // 原生 SurfaceView 可能早于播放器就绪，这里补一次挂载。
    // media_kit 初始化会把 vo 复位成 null，所以必须强制重新下发。
    // 只有当前片源确实走原生出画时才挂载；切到 SDR/纹理时不能把旧 Surface
    // 的 vo/wid 应用到新播放器，否则新播放器会输出到旧原生层，Flutter 纹理
    // 停在最后一帧（切换视频时表现为画面定格）。
    if (nativeSurfaceMode.value && _nativeWid != null) {
      if (_useMedia3Dovi) {
        _scheduleDoviPrepare();
      } else {
        _appliedWid = null;
        _appliedVo = null;
        _appliedSurfaceSize = null;
        _applyNativeSurface(target: player);
      }
      _completeNativeSurfaceReady();
    }

    player.setMediaHeader(userAgent: BrowserUa.pc, referer: HttpString.baseUrl);

    _startListeners(player);

    return player;
  }

  /// 按当前后端重建播放器并回原位置续播。
  ///
  /// 出画后端在创建 VideoController 时就固定了（vo、hwdec 与原生 Surface 的
  /// 绑定），运行中只改 vo 会拿不到帧；这里销毁旧播放器，再用 setDataSource
  /// 记下的快照重新打开同一个片源。
  Future<void> _rebuildOutput() async {
    if (_rebuildingOutput) return;
    final reload = _reloadSource;
    final player = _videoPlayerController;
    if (reload == null || player == null) return;
    _rebuildingOutput = true;
    final generation = _sourceGeneration;
    final seekTo = player.state.position;
    final wasPlaying = player.state.playing;
    debugPrint('[HDR] rebuild player for new output backend');
    try {
      _removeListeners();
      _hdrSnapshotTimer?.cancel();
      _fullScreenSnapshotTimer?.cancel();
      // 保留已经挂上的原生 SurfaceView：重建后仍要在同一块 Surface 上出画。
      _resetNativeSurfaceState(keepSurface: true);
      _setVideoController(null);
      _videoPlayerController = null;
      nativeSurfaceMode.value = _wantNativeSurface || _useMedia3Dovi;
      try {
        await player.dispose();
      } catch (_) {}
      if (generation != _sourceGeneration) {
        // 这期间已经切了分P / 换集，旧片源的重建作废。
        debugPrint('[HDR] skip rebuild: source changed');
        return;
      }
      await reload(seekTo, wasPlaying);
    } catch (e) {
      debugPrint('[HDR] rebuild player failed: ${e}');
    } finally {
      _rebuildingOutput = false;
    }
  }

  /// 片源切换时按需重建播放器，使出画方式与新的片源类型一致。
  ///
  /// 出画方式（纹理 / SurfaceView）在创建 `VideoController` 时固定：
  /// * 纹理路径无法输出 HDR，SurfaceView 路径才能让系统点亮面板 HDR；
  /// * SurfaceView 路径使用 `vo=mediacodec_embed`，会绕过 mpv 渲染，
  ///   不适合给 SDR 片源使用（会失去 Anime4K 等能力）。
  ///
  /// 因此只在 SDR ↔ HDR 切换时重建，普通换集、换 P 不受影响。
  Future<void> _switchOutputIfNeeded() async {
    final wantNative = _wantNativeSurface || _useMedia3Dovi;
    final player = _videoPlayerController;
    if (player == null) {
      nativeSurfaceMode.value = wantNative;
      return;
    }
    // SDR 纹理出画时后端（gpu / gpu-next）也可能被开关改变，需要重建
    // VideoController 才能让新的 vo 生效。
    final textureBackendChanged =
        !wantNative && _appliedTextureBackend != _textureBackend;
    if (nativeSurfaceMode.value == wantNative && !textureBackendChanged) {
      return;
    }

    debugPrint('[HDR] output switch: native=$wantNative');
    _removeListeners();
    _hdrSnapshotTimer?.cancel();
    _fullScreenSnapshotTimer?.cancel();
    _resetNativeSurfaceState();
    _setVideoController(null);
    _videoPlayerController = null;
    nativeSurfaceMode.value = wantNative;
    // 先让 Flutter 把视频控件切到新的出画方式（纹理 ↔ 原生占位），
    // 再销毁旧播放器；否则旧 VideoController 被 dispose 后仍会被 Widget 使用一帧。
    await SchedulerBinding.instance.endOfFrame;
    try {
      await player.dispose();
    } catch (_) {}
  }

  late final buffer = Pref.initBuffer(_playbackSpeed.value);
  late final liveBuffer = Pref.initLiveBuffer();

  // 配置播放器
  Future<void> _createVideoController(
    DataSource dataSource,
    Duration? seekTo,
    Volume? volume,
    int? rotate,
  ) async {
    isBuffering.value = false;
    _heartDuration = 0;
    // 记录本次 open 的目标位置：mpv 在 seek 生效前会先报 position=0，
    // 若直接写回 position.value，进度条会被打回 0。
    seekToPos = seekTo;
    position.value = seekTo?.inSeconds ?? 0;
    // 上个视频如果是在拖动进度条时被切走，isSeeking 会残留 true，
    // progress 就会一直取 seekPosition（0），进度条看起来归零。
    isSeeking.value = false;
    seekPosition.value = 0;
    buffered.value = 0;
    danmakuController?.clear();

    var player = _videoPlayerController;
    // 复用播放器换集时，mpv 的 VO 可能在新文件 open 后失效，表现为有音频
    // 但原生 SurfaceView 一直黑屏。记录是否复用，open 完成后重新挂一次。
    final reusingPlayer = player != null;

    if (player == null) {
      player = await _initPlayer();
      if (_playerCount == 0) {
        _removeListeners();
        _setVideoController(null);
        player.dispose();
        player = null;
        return;
      }
      _videoPlayerController = player;
      if (isAnim && superResolutionType.value != .disable) {
        await setShader();
      }
    } else if (_useMedia3Dovi != _playerUsesMedia3Dovi) {
      // 复用播放器换集时，出画方式可能在 Media3 DoVi 与 mpv 原生出画之间
      // 切换（例如 DoVi 分P → HDR10 分P）。track 选择和 vo 必须跟着改，
      // 否则会沿用上一集的 vid=no / vo=null，表现为有音频无画面或定格。
      _playerUsesMedia3Dovi = _useMedia3Dovi;
      if (_useMedia3Dovi) {
        // 让下一次 _applyNativeSurface 重新下发 vo/wid。
        _appliedWid = null;
        _appliedVo = null;
        _appliedSurfaceSize = null;
        player.setProperty('vid', 'no');
        player.setProperty('aid', 'no');
        player.setProperty('vo', 'null');
      } else {
        // 上一集把视频轨关掉了（vid=no），这里必须显式打开：mpv 只在文件
        // 打开后才会把 vid 重置成 auto，而下一段代码紧接着就 open，中间
        // 如果沿用 vid=no，切到 HDR10 / profile 8 分P 后会只有声音没有画面。
        player.setProperty('aid', 'auto');
        player.setProperty('vid', 'auto');
        if (nativeSurfaceMode.value) {
          _applyNativeSurface(target: player);
        }
      }
    }

    final Map<String, String> extras = {
      if (dataSource is FileSource)
        'cache': 'no'
      else if (isLive)
        ...liveBuffer
      else
        ...buffer,
      'video-rotate': ?rotate?.toString(),
    };

    String video = dataSource.videoSource;
    if (dataSource.audioSource case final audio? when (audio.isNotEmpty)) {
      if (onlyPlayAudio.value) {
        video = audio;
      } else {
        // dely_open need provide length
        video =
            ('edl://'
            '!no_chapters;'
            // '!delay_open,media_type=video;'
            '%${isFileSource ? utf8.encode(video).length : video.length}%$video;'
            '!new_stream;!no_chapters;'
            // '!delay_open,media_type=audio;'
            '%${isFileSource ? utf8.encode(audio).length : audio.length}%$audio');
      }
      audioFilterExtras(volume, map: extras);
    }

    assert(!isLive || seekTo == null);
    // 按当前片源重新落一次 --hwdec：切换画质/换集、小窗与播放页交替时
    // 播放器会被复用，上一部杜比视界 profile 5 的软解（hwdec=no）会留在
    // 实例上，导致后面的视频也被软解。
    // 这里不能用 file-local-options：mpv 规定「没有文件在播放（open 之前
    // 正是这个状态）时写入 file-local-options 会报错」，设置会静默丢失，
    // 复用的播放器便继续沿用创建时的全局值。全局选项随时可写，并在下一个
    // 打开的文件上生效。
    player.setProperty('hwdec', _resolveHwdec() ?? 'no');
    await player.open(
      Media(
        video,
        start: seekTo,
        extras: extras.isEmpty ? null : extras,
      ),
      play: false,
    );
    // 换 P / 换集时 mpv 播放器是复用的，视频轨必须保持关闭：画面只由 Media3
    // 送到原生 SurfaceView，mpv 同时解一份会把解码器耗尽并让画面变黑。
    if (_useMedia3Dovi) {
      player.setProperty('vid', 'no');
      player.setProperty('aid', 'no');
    }
    // 同一个 mpv 实例换文件后，VO 可能被重置（wid/vo 丢失），而界面不会
    // 重新 attach SurfaceView。此时按已保存的 wid 重新初始化原生出画，
    // 且发生在 play 之前，不会出现可见黑闪。
    if (reusingPlayer &&
        nativeSurfaceMode.value &&
        !_useMedia3Dovi &&
        _nativeWid != null) {
      _appliedWid = null;
      _appliedVo = null;
      _appliedBackend = null;
      _applyNativeSurface(target: player);
    }
    applyVideoPictureParameters(player);
    debugPrint(
      '[HDR] open: hdrSource=$isHdrSource surface=${nativeSurfaceMode.value} '
      'hwdec=${_resolveHwdec()} platform=${Platform.isAndroid ? 'android' : 'desktop'}',
    );
    _startHdrSnapshot();
  }

  Future<void>? refreshPlayer() {
    if (dataSource is FileSource) {
      return null;
    }
    if (_videoPlayerController case final ctr? when (ctr.current.isNotEmpty)) {
      var media = ctr.current.last;
      if (!isLive) media = media.copyWith(start: ctr.state.position);
      return ctr.open(media, play: true);
    }
    return null;
  }

  // 开始播放
  Future<void> _initializePlayer() async {
    if (_instance == null) return;
    // 设置倍速
    if (_videoPlayerController != null) {
      final speed = isLive ? 1.0 : playbackSpeed;
      if (_videoPlayerController!.state.rate != speed) {
        await setPlaybackSpeed(speed);
      }
    }
    _initVideoFit();

    // 自动播放
    if (!_autoPlay) return;
    if (nativeSurfaceMode.value &&
        !nativeSurfaceAttached &&
        _nativeSurfaceReady != null) {
      // HDR 直通：等原生 Surface 就绪再开始播放，避免「先出声音、黑屏几秒」。
      // 超时后照常播放：Surface 晚到时 mpv 会自动补上画面。
      unawaited(
        _nativeSurfaceReady!.future
            .timeout(const Duration(milliseconds: 600), onTimeout: () {})
            .then((_) {
              if (_instance != null && _autoPlay) {
                playIfExists();
              }
            }),
      );
      return;
    }
    playIfExists();
  }

  List<StreamSubscription>? _subscriptions;
  final Set<ValueChanged<Duration>> _positionListeners = {};
  final Set<ValueChanged<PlayerStatus>> _statusListeners = {};

  Timer? _wakeLockTimer;

  void _startWakeLockTimer() {
    _wakeLockTimer?.cancel();
    _wakeLockTimer = Timer(
      const Duration(milliseconds: 500),
      _stopWakeLock,
    );
  }

  void _stopWakeLockTimer() {
    _wakeLockTimer?.cancel();
    _wakeLockTimer = null;
  }

  void _stopWakeLock() {
    WakelockPlus.disable();
    _updatePlaybackState(debugLabel: 'onVideoPaused');
  }

  void _updatePlaybackState({Duration? position, String? debugLabel}) {
    videoPlayerServiceHandler?.onUpdateState(
      playerStatus,
      isBuffering.value,
      isLive,
      position: position ?? _videoPlayerController!.state.position,
      speed: playbackSpeed,
      debugLabel: debugLabel,
    );
    _updateIOSPip(position);
  }

  /// 播放事件监听
  void _startListeners(NativePlayer player) {
    assert(_subscriptions == null);
    final stream = player.stream;
    _subscriptions = [
      /// playing
      stream.playing.listen((bool playing) {
        if (playing) {
          playerStatus = .playing;
          _stopWakeLockTimer();
          _updatePlaybackState();
          WakelockPlus.enable();
          _scheduleNativeProbe();
          _scheduleVulkanVoCheck();
          _scheduleTextureVulkanVoCheck();

          if (_isAutoEnterPip &&
              _autoAudioState != AutoAudioOnlyState.autoAudioOnly) {
            if (_isCurrVideoPage || _isInInAppPip) {
              enterPip(autoEnter: true);
            } else {
              _disableAutoEnterPip();
            }
          }
        } else {
          playerStatus = .paused;
          _startWakeLockTimer();
          _disableAutoEnterPip();
          _updateIOSPip();
        }

        for (final element in _statusListeners) {
          element(playing ? .playing : .paused);
        }

        final seconds = videoPlayerController!.state.position.inSeconds;
        if (seconds != 0) {
          makeHeartBeat(seconds, type: .status);
        }
      }),

      ///completed
      stream.completed.listen((bool completed) {
        if (completed) {
          playerStatus = .completed;
          _startWakeLockTimer();

          for (final element in _statusListeners) {
            element(.completed);
          }

          makeHeartBeat(-1, type: .completed);
        }
      }),

      /// position
      stream.position.listen((Duration position) {
        // Media3 只留时间轴时 mpv 的 position 不可信，进度由 _syncDovi 更新。
        if (_useMedia3Dovi) return;
        final posInSeconds = position.inSeconds;

        // open(start: seekTo) 生效前 mpv 会先报 0，忽略它，避免进度条归零。
        if (seekToPos != null) {
          if (posInSeconds == 0) return;
          seekToPos = null;
        }

        if (posInSeconds != this.position.value) {
          if (posInSeconds == 0 && playerStatus.isPlaying) {
            _updatePlaybackState(position: position);
          }

          this.position.value = posInSeconds;

          makeHeartBeat(posInSeconds);
        }

        for (final element in _positionListeners) {
          element(position);
        }
      }),
      stream.duration.listen((Duration duration) {
        updateDuration(duration);
        _updateIOSPip();
      }),
      stream.buffer.listen((Duration buffer) {
        buffered.value = buffer.inSeconds;
      }),
      stream.buffering.listen((bool buffering) {
        // Media3 出画时 mpv 只保留时间轴（vid/aid 都关掉），它的 buffering
        // 状态不可信，会出现多余的加载图标；交给 Media3 自己管理。
        if (_useMedia3Dovi) {
          isBuffering.value = false;
          return;
        }
        isBuffering.value = buffering;
        if (!playerStatus.isCompleted) {
          _stopWakeLockTimer();
          _updatePlaybackState();
        }
      }),
      if (kDebugMode)
        stream.log.listen(((PlayerLog log) {
          if (log.level == 'error' || log.level == 'fatal') {
            Utils.reportError(
              '${log.level}: ${log.prefix}: ${log.text}\n${player.state.playlist}',
              null,
            );
          } else {
            debugPrint(log.toString());
          }
        })),
      stream.error.listen((String event) {
        if (dataSource is FileSource &&
            event.startsWith("Failed to open file")) {
          return;
        }
        if (isLive) {
          if (event.startsWith('tcp: ffurl_read returned ') ||
              event.startsWith("Failed to open https://") ||
              event.startsWith("Can not open external file https://")) {
            Timer(const Duration(milliseconds: 3000), refreshPlayer);
          }
          return;
        }
        if (event.startsWith("Failed to open https://") ||
            event.startsWith("Can not open external file https://") ||
            //tcp: ffurl_read returned 0xdfb9b0bb
            //tcp: ffurl_read returned 0xffffff99
            event.startsWith('tcp: ffurl_read returned ')) {
          EasyThrottle.throttle(
            'controllerStream.error.listen',
            const Duration(milliseconds: 10000),
            () => Timer(const Duration(milliseconds: 3000), () {
              // if (kDebugMode) {
              //   debugPrint("isBuffering.value: ${isBuffering.value}");
              // }
              // if (kDebugMode) {
              //   debugPrint("_buffered.value: ${_buffered.value}");
              // }
              if (isBuffering.value && buffered.value == 0) {
                final customHost = VideoUtils.customCDNUrl;
                SmartDialog.showToast(
                  customHost == null
                      ? '视频链接打开失败，重试中'
                      : '视频链接打开失败，重试中\n当前自定义CDN节点：$customHost，持续失败可尝试更换或清除',
                  displayTime: customHost == null
                      ? const Duration(milliseconds: 500)
                      : const Duration(milliseconds: 3000),
                );
                refreshPlayer();
              }
            }),
          );
        } else if (event.startsWith('Could not open codec')) {
          SmartDialog.showToast('无法加载解码器, $event，可能会切换至软解');
        } else if (!onlyPlayAudio.value) {
          if (event.startsWith("error running") ||
              event.startsWith("Failed to open .") ||
              event.startsWith("Cannot open") ||
              event.startsWith("Can not open")) {
            return;
          }
          if (!kDebugMode) {
            Utils.reportError('$event\n${player.state.playlist}');
          }
          // SmartDialog.showToast('视频加载错误, $event');
        }
      }),
    ];
  }

  /// 移除事件监听
  void _removeListeners() {
    _subscriptions?.forEach((e) => e.cancel());
    _subscriptions?.clear();
    _subscriptions = null;
  }

  void _cancelSubForSeek() {
    if (_subForSeek != null) {
      _subForSeek!.cancel();
      _subForSeek = null;
    }
  }

  Future<void> seek(Duration position, {bool isSeek = false}) async {
    if (isSeek && !_useMedia3Dovi) {
      /// 拖动进度条调节时，不等待第一帧，防止抖动
      await _videoPlayerController?.stream.buffer.first;
    }
    danmakuController?.clear();
    try {
      if (_useMedia3Dovi) {
        this.position.value = position.inSeconds;
        unawaited(
          NativeVideoSurfaceChannel.doviSeek(
            positionMs: position.inMilliseconds + Pref.doviAudioOffset,
          ),
        );
      } else {
        await _videoPlayerController?.seek(position);
      }
      _updateIOSPip(position);
    } catch (e) {
      if (kDebugMode) debugPrint('seek failed: $e');
    }
  }

  /// 跳转至指定位置
  Future<void> seekTo(Duration position, {bool isSeek = true}) async {
    if (_playerCount == 0) {
      return;
    }
    if (position < Duration.zero) {
      position = Duration.zero;
    }
    _heartDuration = position.inSeconds;

    if (duration.value != 0) {
      seek(position, isSeek: isSeek);
    } else {
      // if (kDebugMode) debugPrint('seek duration else');
      _subForSeek?.cancel();
      _subForSeek = duration.listen((_) {
        seek(position, isSeek: isSeek);
        _cancelSubForSeek();
      });
    }
  }

  /// 设置倍速
  Future<void> setPlaybackSpeed(double speed) async {
    lastPlaybackSpeed = playbackSpeed;

    if (speed == _videoPlayerController?.state.rate) return;

    await _videoPlayerController?.setRate(speed);
    if (_useMedia3Dovi) {
      unawaited(NativeVideoSurfaceChannel.doviSetRate(rate: speed));
    }
    if (!isLive) _playbackSpeed.value = speed;
    _updatePlaybackState();
    if (danmakuController != null) {
      try {
        danmakuController?.updateOption(
          danmakuController!.option.copyWith(
            duration: DanmakuOptions.danmakuDuration / speed,
            staticDuration: DanmakuOptions.danmakuStaticDuration / speed,
          ),
        );
      } catch (_) {}
    }
  }

  // 还原默认速度
  double playSpeedDefault = Pref.playSpeedDefault;
  Future<void> setDefaultSpeed() async {
    await _videoPlayerController?.setRate(playSpeedDefault);
    _playbackSpeed.value = playSpeedDefault;
  }

  bool _showControlsOnNextPlay = false;

  void markManualEpisodeChange() {
    if (Pref.showControlsOnManualEpisodeChange) {
      _showControlsOnNextPlay = true;
    }
  }

  bool _consumeShowControlsOnNextPlay() {
    final showControls = _showControlsOnNextPlay;
    _showControlsOnNextPlay = false;
    return showControls;
  }

  /// 底层播放：申请音频焦点 + 启动播放，不含 UI 副作用
  Future<void> _rawPlay() async {
    await _videoPlayerController?.play();
    if (_useMedia3Dovi) {
      unawaited(NativeVideoSurfaceChannel.doviPlay());
    }
    audioSessionHandler?.setActive(true);
    playerStatus = PlayerStatus.playing;
  }

  /// 播放视频
  Future<void> play({bool repeat = false, bool hideControls = true}) async {
    if (_playerCount == 0) return;
    // 播放时自动隐藏控制条
    final showControlsOnNextPlay = _consumeShowControlsOnNextPlay();
    controls = !hideControls || showControlsOnNextPlay;
    // repeat为true，将从头播放
    if (repeat) {
      await seekTo(Duration.zero, isSeek: false);
    }

    await _rawPlay();
  }

  /// 暂停播放
  Future<void> pause({bool notify = true, bool isInterrupt = false}) async {
    await _videoPlayerController?.pause();
    if (_useMedia3Dovi) {
      unawaited(NativeVideoSurfaceChannel.doviPause());
    }
    playerStatus = .paused;

    // 主动暂停时让出音频焦点
    if (!isInterrupt) {
      audioSessionHandler?.setActive(false);
    }
  }

  bool tripling = false;

  /// 隐藏控制条
  void hideTaskControls() {
    _timer?.cancel();
    _timer = Timer(showControlDuration, () {
      if (!isSeeking.value && !tripling && !showDesktopProgressFeedback.value) {
        controls = false;
      }
      _timer = null;
    });
  }

  void onSeekStart(int seekFrom) {
    seekPosition.value = seekFrom;
    isSeeking.value = true;
  }

  void onSeekEnd() {
    if (showSeekPreview) {
      showPreview.value = false;
    }
    hasToasted = false;
    isSeeking.value = false;
    if (PlatformUtils.isDesktop) {
      requireDesktopProgressHoverReenter = _desktopProgressPointerInside;
      hideDesktopProgressPreview();
    }
    hideTaskControls();
  }

  final RxBool volumeIndicator = false.obs;
  Timer? volumeTimer;
  bool volumeInterceptEventStream = false;

  double get maxVolume => PlatformUtils.isDesktop
      ? Pref.maxVolume
      : (Pref.enableAppVolume && Pref.enableVolumeBoost ? 2.0 : 1.0);

  // 音量增强二次确认：是否已解锁突破 100%（松手后重置）
  bool volumeBoostUnlocked = false;

  // 手势滑动时的音量上限：未解锁时最大 1.0，解锁后最大 2.0
  double get gestureVolumeMax {
    if (Pref.enableAppVolume && Pref.enableVolumeBoost) {
      return volumeBoostUnlocked ? 2.0 : 1.0;
    }
    return maxVolume;
  }

  // 松手时重置解锁状态
  void onVolumeGestureEnd() {
    if (Pref.enableAppVolume && Pref.enableVolumeBoost) {
      volumeBoostUnlocked = false;
    }
  }

  Future<void> setVolume(double volume, {bool showIndicator = true}) async {
    if (this.volume.value != volume) {
      this.volume.value = volume;
      try {
        if (PlatformUtils.isDesktop) {
          await setVolumeCapped(_videoPlayerController, volume);
        } else {
          // 移动平台：根据设置选择音量控制方式
          if (Pref.enableAppVolume) {
            // 应用内音量模式：使用 media_kit 控制应用内音量
            _videoPlayerController?.setVolume(volume * 100);
            if (_useMedia3Dovi) {
              unawaited(
                NativeVideoSurfaceChannel.doviSetVolume(volume: volume),
              );
            }
          } else {
            // 默认模式：控制系统音量
            FlutterVolumeController.updateShowSystemUI(false);
            await FlutterVolumeController.setVolume(volume);
          }
        }
      } catch (err) {
        if (kDebugMode) debugPrint(err.toString());
      }
    }
    if (showIndicator) {
      volumeIndicator.value = true;
    }
    volumeInterceptEventStream = true;
    volumeTimer?.cancel();
    volumeTimer = Timer(const Duration(milliseconds: 200), () {
      volumeIndicator.value = false;
      volumeInterceptEventStream = false;
      if (PlatformUtils.isDesktop) {
        setting.put(SettingBoxKey.desktopVolume, volume.toPrecision(3));
      } else if (Pref.enableAppVolume) {
        // 移动平台应用内音量模式：保存音量到持久化存储
        // duck 期间不保存，避免保存临时的减半音量
        if (!_isDucked) {
          Pref.appVolume = volume;
        }
      }
    });
  }

  /// 处理应用内音量设置变更
  Future<void> onAppVolumeSettingChanged() async {
    if (!PlatformUtils.isMobile) return;

    // 如果播放器未初始化，直接返回（设置已保存，下次播放器初始化时生效）
    if (_videoPlayerController == null) return;

    if (Pref.enableAppVolume) {
      // 切换到应用内音量模式
      // 获取当前系统音量
      final currentSystemVolume =
          (await FlutterVolumeController.getVolume()) ?? 1.0;
      systemVolume.value = currentSystemVolume;

      final appVolume = (Pref.playerVolume / 100)
          .clamp(0.0, maxVolume)
          .toDouble();
      volume.value = appVolume;
      Pref.appVolume = appVolume;
      volumeBoostUnlocked = false;

      // 关闭上游固定增益，避免和应用内音量叠加
      _videoPlayerController?.setVolume(appVolume * 100);

      // 显示提示
      SmartDialog.showToast('已切换到应用内音量模式');
    } else {
      // 切换到同步系统音量模式
      // 恢复上游播放器音量设置，并按增益折算系统音量
      final currentSystemVolume =
          (await FlutterVolumeController.getVolume()) ?? 1.0;
      final playerGain = max(Pref.playerVolume / 100, 0.01);
      final newSystemVolume = (currentSystemVolume * volume.value / playerGain)
          .clamp(0.0, 1.0)
          .toDouble();

      await FlutterVolumeController.updateShowSystemUI(false);
      await FlutterVolumeController.setVolume(newSystemVolume);
      await _videoPlayerController?.setVolume(Pref.playerVolume);
      volumeBoostUnlocked = false;

      // 更新状态
      systemVolume.value = newSystemVolume;
      volume.value = newSystemVolume;

      SmartDialog.showToast('已切换到同步系统音量模式');
    }
  }

  /// duck 事件处理（由 audio_session.dart 调用）
  Future<void> handleDuck(bool begin) async {
    if (!PlatformUtils.isMobile) return;

    if (Pref.enableAppVolume) {
      // 应用内音量模式：使用临时音量，不影响持久化值
      if (begin) {
        _isDucked = true;
        _preDuckVolume = volume.value;
        volume.value = volume.value * 0.5;
        _videoPlayerController?.setVolume(volume.value * 100);
      } else {
        _isDucked = false;
        volume.value = _preDuckVolume;
        _videoPlayerController?.setVolume(volume.value * 100);
      }
    }
    // 同步模式：使用原有逻辑，直接调用 setVolume 即可
  }

  /// Toggle Change the videofit accordingly
  void toggleVideoFit(VideoFitType value) {
    _prefFit = videoFit.value = value;
    video.put(VideoBoxKey.cacheVideoFit, value.index);
  }

  /// 读取fit
  var _prefFit = VideoFitType.values[Pref.cacheVideoFit];
  void _initVideoFit() {
    if (_prefFit == .fill && _isVertical) {
      videoFit.value = .contain;
    } else {
      videoFit.value = _prefFit;
    }
  }

  /// 设置后台播放
  void setBackgroundPlay(bool val) {
    videoPlayerServiceHandler?.enableBackgroundPlay = val;
    if (!tempPlayerConf) {
      setting.put(SettingBoxKey.enableBackgroundPlay, val);
    }
  }

  set controls(bool visible) {
    if (!visible && PlatformUtils.isDesktop) {
      hideDesktopProgressPreview();
    }
    showControls.value = visible;
    _timer?.cancel();
    if (visible) {
      hideTaskControls();
    }
  }

  Timer? longPressTimer;
  void cancelLongPressTimer() {
    longPressTimer?.cancel();
    longPressTimer = null;
  }

  /// 设置长按倍速状态 live模式下禁用
  Future<void> setLongPressStatus(bool val, {bool isCancel = false}) async {
    if (isLive) {
      return;
    }
    if (controlsLock.value) {
      return;
    }
    if (longPressStatus.value == val) {
      return;
    }
    if (val) {
      if (playerStatus.isPlaying) {
        _speedLockArmed = false;
        _cancelSpeedLockHintTimer();
        longPressStatus.value = val;
        HapticFeedback.lightImpact();
        if (speedLocked) {
          // 锁定态：速度已固化为锁定值，不得再调速——setPlaybackSpeed 会
          // 覆盖 lastPlaybackSpeed（锁定前速度），动态倍速下还会二次翻倍
          speedLockHint.value = SpeedLockHint.swipeDownToUnlock;
        } else {
          await setPlaybackSpeed(
            enableAutoLongPressSpeed ? playbackSpeed * 2 : longPressSpeed,
          );
          if (longPressStatus.value) {
            speedLockHint.value = SpeedLockHint.swipeUpToLock;
          }
        }
      }
    } else {
      // 预备态在松手时提交；系统打断（cancel）一律不提交
      final bool commit = _speedLockArmed && !isCancel;
      _speedLockArmed = false;
      longPressStatus.value = val;
      if (speedLocked) {
        if (commit) {
          speedLocked = false;
          HapticFeedback.mediumImpact();
          await setPlaybackSpeed(lastPlaybackSpeed);
          _showTransientSpeedLockHint(SpeedLockHint.unlockedConfirm);
        } else {
          speedLockHint.value = SpeedLockHint.none;
        }
      } else {
        if (commit) {
          speedLocked = true;
          HapticFeedback.mediumImpact();
          _showTransientSpeedLockHint(SpeedLockHint.lockedConfirm);
        } else {
          speedLockHint.value = SpeedLockHint.none;
          await setPlaybackSpeed(lastPlaybackSpeed);
        }
      }
    }
  }

  // 长按倍速锁定：预备阈值 = 播放器实高 × 比例，clamp 到人体工学区间。
  // 比例由实测锚点反推（横屏半屏 48/231≈0.21、横屏全屏 96/411≈0.23），
  // 下限保小窗/小播放器手感，上限≈2.7cm 为拇指第一指节舒适推程封顶
  static const double _speedLockThresholdRatio = 0.22;
  static const double _speedLockThresholdMin = 48;
  static const double _speedLockThresholdMax = 112;
  static const double _speedLockHysteresis = 10;

  /// 长按中手指移动，dy 为相对长按起点的纵向偏移（上滑为负），
  /// [playerHeight] 为播放器组件实高（决定阈值）。
  /// 越线进入预备态、滑回取消预备，均可反复，提交只发生在松手
  void onLongPressMove(double dy, double playerHeight) {
    if (!longPressStatus.value) {
      return;
    }
    final double threshold = clampDouble(
      playerHeight * _speedLockThresholdRatio,
      _speedLockThresholdMin,
      _speedLockThresholdMax,
    );
    if (speedLocked) {
      // 下滑预备退出
      if (!_speedLockArmed && dy >= threshold) {
        _speedLockArmed = true;
        HapticFeedback.lightImpact();
        speedLockHint.value = SpeedLockHint.releaseToUnlock;
      } else if (_speedLockArmed && dy <= threshold - _speedLockHysteresis) {
        _speedLockArmed = false;
        HapticFeedback.lightImpact();
        speedLockHint.value = SpeedLockHint.swipeDownToUnlock;
      }
    } else {
      // 上滑预备锁定
      if (!_speedLockArmed && dy <= -threshold) {
        _speedLockArmed = true;
        HapticFeedback.lightImpact();
        speedLockHint.value = SpeedLockHint.releaseToLock;
      } else if (_speedLockArmed && dy >= -(threshold - _speedLockHysteresis)) {
        _speedLockArmed = false;
        HapticFeedback.lightImpact();
        speedLockHint.value = SpeedLockHint.swipeUpToLock;
      }
    }
  }

  /// 手动调速（倍速菜单/快捷键）：锁定态下先解除锁定再应用所选速度
  Future<void> setManualPlaybackSpeed(double speed) async {
    if (speedLocked) {
      await releaseSpeedLock(restoreSpeed: false);
    }
    await setPlaybackSpeed(speed);
  }

  /// 结束长按及倍速锁定；[restoreSpeed] 为 true 时恢复长按前速度
  Future<void> releaseSpeedLock({bool restoreSpeed = true}) async {
    if (!speedLocked && !longPressStatus.value) {
      return;
    }
    longPressStatus.value = false;
    speedLocked = false;
    _speedLockArmed = false;
    _cancelSpeedLockHintTimer();
    speedLockHint.value = SpeedLockHint.none;
    if (restoreSpeed) {
      await setPlaybackSpeed(lastPlaybackSpeed);
    }
  }

  void _showTransientSpeedLockHint(SpeedLockHint hint) {
    speedLockHint.value = hint;
    _speedLockHintTimer?.cancel();
    _speedLockHintTimer = Timer(const Duration(seconds: 2), () {
      if (speedLockHint.value == hint) {
        speedLockHint.value = SpeedLockHint.none;
      }
    });
  }

  void _cancelSpeedLockHintTimer() {
    _speedLockHintTimer?.cancel();
    _speedLockHintTimer = null;
  }

  bool get isCompleted =>
      videoPlayerController!.state.completed ||
      durationInMilliseconds - positionInMilliseconds <= 50;

  // 双击播放、暂停
  Future<void> onDoubleTapCenter() async {
    if (!isLive && isCompleted) {
      await videoPlayerController!.seek(Duration.zero);
      await _rawPlay();
    } else if (videoPlayerController!.state.playing) {
      await pause();
    } else {
      await _rawPlay();
    }
  }

  final RxBool mountSeekBackwardButton = false.obs;
  final RxBool mountSeekForwardButton = false.obs;

  void onDoubleTapSeekBackward() {
    mountSeekBackwardButton.value = true;
  }

  void onDoubleTapSeekForward() {
    mountSeekForwardButton.value = true;
  }

  void onForward(Duration duration) {
    onForwardBackward(videoPlayerController!.state.position + duration);
  }

  void onBackward(Duration duration) {
    onForwardBackward(videoPlayerController!.state.position - duration);
  }

  void multiBackwardStart([_]) {
    isSeeking.value = true;
    seekPosition.value = max(0, seekPosition.value - fastForBackwardInSeconds);
  }

  void multiBackwardEnd() {
    if (isSeeking.value) {
      isSeeking.value = false;
      onForwardBackward(Duration(seconds: seekPosition.value));
    } else {
      onBackward(fastForBackwardDuration);
    }
  }

  void onForwardBackward(Duration duration) {
    seekTo(
      duration.clamp(Duration.zero, videoPlayerController!.state.duration),
      isSeek: false,
    ).whenComplete(play);
  }

  void doubleTapFuc(DoubleTapType type) {
    if (!enableQuickDouble) {
      onDoubleTapCenter();
      return;
    }
    switch (type) {
      case DoubleTapType.left:
        // 双击左边区域 👈
        onDoubleTapSeekBackward();
        break;
      case DoubleTapType.center:
        onDoubleTapCenter();
        break;
      case DoubleTapType.right:
        // 双击右边区域 👈
        onDoubleTapSeekForward();
        break;
    }
  }

  /// 关闭控制栏
  void onLockControl(bool val) {
    feedBack();
    controlsLock.value = val;
    if (val) {
      hideDesktopProgressPreview();
    }
    if (!val && showControls.value) {
      showControls.refresh();
    }
    controls = !val;
  }

  void _setFullScreen(bool val) {
    isFullScreen.value = val;
    _noteVoLog('--- 全屏=$val');
    updateSubtitleStyle();
    // 全屏切换会改窗口的 SystemUI／方向，部分 ROM 上窗口 HDR 色彩模式会被
    // 系统顺手复位，画面随即发灰、面板不再激发。这里主动钉一次即可：
    // 尺寸变化走 android_reconfig，它本来就会重下发 HDR dataspace，不需要
    // 再 vo=null 重建（重建期间 mpv 会报 buffering）。
    if (_isVulkanHdrOutput) _updateWindowHdrMode(force: true);
    // SurfaceView 重建、VO 重新下发期间 mpv 会短暂报 buffering，
    // 过渡窗口（1.2s）内不显示加载动画，避免全屏切换闪一下「加载中」。
    fullScreenTransition.value = true;
    _fullScreenTransitionTimer?.cancel();
    // SurfaceView 重建 / 窗口 relayout 之后系统可能把窗口色彩模式复位，
    // 过渡窗口过半（600ms，尺寸已按新窗口下发完）再钉一次。
    _fullScreenHdrRepinTimer?.cancel();
    _fullScreenHdrRepinTimer = Timer(const Duration(milliseconds: 600), () {
      _fullScreenHdrRepinTimer = null;
      if (isFullScreen.value != val) return;
      if (_isVulkanHdrOutput) _updateWindowHdrMode(force: true);
    });
    _fullScreenTransitionTimer = Timer(const Duration(milliseconds: 1200), () {
      _fullScreenTransitionTimer = null;
      fullScreenTransition.value = false;
    });
    // 全屏/退出全屏后留一份快照：设置页只能在离开播放页后打开，
    // 全屏期间的状态必须自己存下来才拿得到。
    _scheduleFullScreenSnapshot();
    onFullScreenChanged?.call(val);
  }

  double screenRatio = 0.0;
  bool isManualFS = true;
  late final FullScreenMode mode = Pref.fullScreenMode;
  late final horizontalScreen = Pref.horizontalScreen;
  late final removeSafeArea = Pref.removeSafeArea;

  Future<void>? changeOrientation({
    required bool isVertical,
    DeviceOrientation? orientation,
  }) {
    if (orientation == null && (mode == .none || mode == .gravity)) {
      return null;
    }
    if (orientation == null &&
        (mode == .vertical ||
            (mode == .auto && isVertical) ||
            (mode == .ratio && (isVertical || screenRatio < kScreenRatio)))) {
      return portraitUpMode();
    } else {
      // https://github.com/flutter/flutter/issues/73651
      // https://github.com/flutter/flutter/issues/183708
      if (Platform.isAndroid) {
        if ((orientation ?? _orientation) == .landscapeRight) {
          return landscapeRightMode();
        } else {
          return landscapeLeftMode();
        }
      } else {
        if (orientation == .landscapeLeft) {
          return landscapeLeftMode();
        } else {
          return landscapeRightMode();
        }
      }
    }
  }

  // 全屏
  bool _fsProcessing = false;
  Future<void> triggerFullScreen({
    bool status = true,
    bool inAppFullScreen = false,
    DeviceOrientation? orientation,
    bool isManualFS = true,
  }) async {
    if (isDesktopPip) return;
    if (isFullScreen.value == status) return;

    if (_fsProcessing) return;
    _fsProcessing = true;
    this.isManualFS = isManualFS;
    try {
      if (status) {
        if (PlatformUtils.isMobile) {
          hideSystemBar();
          await changeOrientation(
            isVertical: isVertical,
            orientation: orientation,
          );
        } else {
          enterDesktopFullScreen(inAppFullScreen: inAppFullScreen);
        }
      } else {
        if (PlatformUtils.isMobile) {
          if (!removeSafeArea) {
            showSystemBar();
          }
          if (orientation == null && mode == .none) {
            return;
          }
          await resetScreenRotation();
        } else {
          exitDesktopFullScreen();
        }
      }
    } finally {
      _setFullScreen(status);
      _fsProcessing = false;
    }
  }

  void addPositionListener(ValueChanged<Duration> listener) {
    if (_playerCount == 0) return;
    _positionListeners.add(listener);
  }

  void removePositionListener(ValueChanged<Duration> listener) =>
      _positionListeners.remove(listener);

  void addStatusLister(ValueChanged<PlayerStatus> listener) {
    if (_playerCount == 0) return;
    _statusListeners.add(listener);
  }

  void removeStatusLister(ValueChanged<PlayerStatus> listener) =>
      _statusListeners.remove(listener);

  // 记录播放记录
  Future<void>? makeHeartBeat(
    int progress, {
    HeartBeatType type = .playing,
    bool isManual = false,
    dynamic aid,
    dynamic bvid,
    dynamic cid,
    dynamic epid,
    dynamic seasonId,
    dynamic pgcType,
    VideoType? videoType,
  }) {
    if (!isManual && dataStatus.value != DataStatus.loaded) {
      return null;
    }
    if (isLive ||
        !enableHeart ||
        progress == 0 ||
        (playerStatus.isPaused && !isManual)) {
      return null;
    }

    Future<void> send() async {
      try {
        await VideoHttp.heartBeat(
          aid: aid ?? _aid,
          bvid: bvid ?? _bvid,
          cid: cid ?? this.cid,
          progress: progress,
          epid: epid ?? _epid,
          seasonId: seasonId ?? _seasonId,
          subType: pgcType ?? _pgcType,
          videoType: videoType ?? _videoType,
        );
      } catch (e) {}
    }

    switch (type) {
      case .playing:
        if (progress - _heartDuration >= 5) {
          _heartDuration = progress;
          return send();
        }
      case .status:
        if (progress - _heartDuration >= 2) {
          _heartDuration = progress;
          return send();
        }
      case .completed:
        if (playerStatus.isCompleted &&
            (durationInMilliseconds - positionInMilliseconds) <= 1000) {
          progress = -1;
        }
        return send();
    }
    return null;
  }

  void setPlayRepeat(PlayRepeat type) {
    playRepeat = type;
    if (!tempPlayerConf) video.put(VideoBoxKey.playRepeat, type.index);
  }

  void putSubtitleSettings() {
    setting.putAllNE({
      SettingBoxKey.subtitleFontScale: subtitleFontScale,
      SettingBoxKey.subtitleFontScaleFS: subtitleFontScaleFS,
      SettingBoxKey.subtitlePaddingH: subtitlePaddingH,
      SettingBoxKey.subtitlePaddingB: subtitlePaddingB,
      SettingBoxKey.subtitleBgOpacity: subtitleBgOpacity,
      SettingBoxKey.subtitleStrokeWidth: subtitleStrokeWidth,
      SettingBoxKey.subtitleFontWeight: subtitleFontWeight,
      SettingBoxKey.subtitleSecondaryFontScale: subtitleSecondaryFontScale,
      SettingBoxKey.subtitleSecondaryFontScaleFS: subtitleSecondaryFontScaleFS,
      SettingBoxKey.subtitleSecondaryBgOpacity: subtitleSecondaryBgOpacity,
      SettingBoxKey.subtitleSecondaryStrokeWidth: subtitleSecondaryStrokeWidth,
      SettingBoxKey.subtitleSecondaryFontWeight: subtitleSecondaryFontWeight,
      SettingBoxKey.subtitleSecondarySpacing: subtitleSecondarySpacing,
    });
  }

  bool _isCloseAll = false;
  bool get isCloseAll => _isCloseAll;

  Future<void>? resetScreenRotation() {
    if (horizontalScreen) {
      return fullMode();
    } else {
      return portraitUpMode();
    }
  }

  void onCloseAll() {
    _isCloseAll = true;
    if (PlatformUtils.isDesktop) exitDesktopFullScreen();
    dispose();
    Get.until((route) => route.isFirst);
  }

  // ──────────────────────────────────────────────
  // 后台自动只听音频 — 状态机
  // ──────────────────────────────────────────────

  /// 手动听视频/仅播放音频标记，由三点菜单或直播按钮调用
  void markManualOnlyPlayAudio(bool enabled) {
    _interruptAutoAudioRestore();
    if (enabled) {
      _cancelAutoAudioOnlyTimer();
      _autoAudioState = AutoAudioOnlyState.manualAudioOnly;
    } else {
      if (_autoAudioState == AutoAudioOnlyState.manualAudioOnly ||
          _autoAudioState == AutoAudioOnlyState.autoAudioOnly) {
        _autoAudioState = AutoAudioOnlyState.idle;
      }
    }
  }

  /// 设置项变更时调用
  void onAutoAudioOnlySettingChanged() {
    if (!Pref.autoAudioOnlyInBackground || !continuePlayInBackground.value) {
      if (_autoAudioState == AutoAudioOnlyState.arm ||
          _autoAudioState == AutoAudioOnlyState.pipHold) {
        _cancelAutoAudioOnlyTimer();
        _autoAudioState = AutoAudioOnlyState.idle;
      } else if (_autoAudioState == AutoAudioOnlyState.autoAudioOnly) {
        _cancelAutoAudioOnlyTimer();
        unawaited(restoreFromAutoAudioOnly());
      }
    }
  }

  void _cancelAutoAudioOnlyTimer() {
    _autoAudioOnlyTimer?.cancel();
    _autoAudioOnlyTimer = null;
  }

  /// 自动只听准入检查
  bool _canEnterAutoAudioOnly() {
    if (!PlatformUtils.isMobile) return false;
    if (!Pref.autoAudioOnlyInBackground) return false;
    if (!continuePlayInBackground.value) return false;
    if (_videoPlayerController == null) return false;
    if (!playerStatus.isPlaying) return false;
    if (isPipMode) return false;
    if (_autoAudioState == AutoAudioOnlyState.manualAudioOnly) return false;
    if (_autoAudioState == AutoAudioOnlyState.autoAudioOnly) return false;
    if (Get.currentRoute == '/audio') return false;
    // 点播有独立音轨才可切；直播没有音轨限制
    if (!isLive && !_hasIndependentAudioTrack) return false;
    return true;
  }

  bool get _hasIndependentAudioTrack {
    if (dataSource is FileSource) {
      return !(dataSource as FileSource).isMp4;
    }
    return dataSource.audioSource?.isNotEmpty == true;
  }

  /// 后台 10 秒到点，切到只听
  Future<void> applyAutoAudioOnly() async {
    if (!_canEnterAutoAudioOnly()) {
      _autoAudioState = AutoAudioOnlyState.idle;
      return;
    }

    onlyPlayAudio.value = true;

    if (isLive) {
      // 直播：重拉 only_audio=1
      _autoAudioState = AutoAudioOnlyState.autoAudioOnly;
      await onNeedsPlayerInit?.call();
    } else {
      // 点播：vid=no
      try {
        _videoPlayerController?.setProperty(
          'file-local-options/vid',
          'no',
        );
      } catch (_) {
        onlyPlayAudio.value = false;
        _autoAudioState = AutoAudioOnlyState.idle;
        return;
      }
      _audioReopened = false;
      _autoAudioState = AutoAudioOnlyState.autoAudioOnly;
    }
  }

  /// 回到前台，恢复画面
  Future<void> restoreFromAutoAudioOnly() async {
    if (_autoAudioState != AutoAudioOnlyState.autoAudioOnly) return;
    if (_autoAudioRestoreInProgress) return;

    _cancelAutoAudioOnlyTimer();
    _autoAudioRestoreInProgress = true;
    final restoreGeneration = ++_autoAudioRestoreGeneration;
    suppressBufferingIndicator.value = !isLive && !_audioReopened;

    try {
      // 直播，以及自动只听期间已经重开过纯音频 Media 的点播，
      // 都没有可供 vid=auto 复用的视频输入，直接走页面级恢复。
      if (isLive || _audioReopened) {
        await _fullRestore();
        return;
      }

      final player = _videoPlayerController;
      if (player == null || player.current.isEmpty) {
        await _fullRestore();
        return;
      }

      onlyPlayAudio.value = false;

      // 第一层：在当前 EDL Media 上重新选择视频轨，不重开 Media。
      try {
        player.setProperty('file-local-options/vid', 'auto');
      } catch (_) {
        await _fullRestore();
        return;
      }
      applyVideoPictureParameters();

      final restoredByTrackSwitch = await _waitForVideoOutput(
        restoreGeneration,
        checkCurrentState: false,
      );
      if (!_isAutoAudioRestoreCurrent(restoreGeneration)) {
        return;
      }

      if (restoredByTrackSwitch) {
        _completeAutoAudioRestore();
        return;
      }

      if (!_canUseAutoAudioRestoreFallback(player)) {
        _completeAutoAudioRestore();
        return;
      }

      // 第二层：当前 EDL 仍可复用时，只重开这一个 Media。
      if (await _reopenCurrentMedia(restoreGeneration)) {
        _completeAutoAudioRestore();
        return;
      }

      if (_isAutoAudioRestoreCurrent(restoreGeneration) &&
          _canUseAutoAudioRestoreFallback(player)) {
        // 第三层：当前 Media 也无法恢复时，交给页面重新初始化资源。
        await _fullRestore();
      } else if (_isAutoAudioRestoreCurrent(restoreGeneration)) {
        _completeAutoAudioRestore();
      }
    } finally {
      if (restoreGeneration == _autoAudioRestoreGeneration) {
        _autoAudioRestoreInProgress = false;
        suppressBufferingIndicator.value = false;
      }
    }
  }

  /// 等待当前 Media 恢复真实视频输出。
  Future<bool> _waitForVideoOutput(
    int restoreGeneration, {
    bool checkCurrentState = true,
  }) {
    final player = _videoPlayerController;
    if (player == null) return Future.value(false);
    if (checkCurrentState && _hasVideoOutput(player)) {
      return Future.value(true);
    }

    final completer = _autoAudioRestoreCompleter = Completer<bool>();
    final subscription = player.stream.videoParams.listen((_) {
      if (!_isAutoAudioRestoreCurrent(restoreGeneration)) {
        _finishAutoAudioRestoreWait(false);
      } else if (_hasVideoOutput(player)) {
        _finishAutoAudioRestoreWait(true);
      }
    });
    _autoAudioRestoreSubscription = subscription;
    _autoAudioRestoreTimer = Timer(
      const Duration(seconds: 4),
      () => _finishAutoAudioRestoreWait(false),
    );
    return completer.future;
  }

  bool _hasVideoOutput(Player player) {
    final state = player.state;
    if (state.track.video.id == 'no') return false;
    final params = state.videoParams;
    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    return width > 0 && height > 0;
  }

  bool _canUseAutoAudioRestoreFallback(Player player) =>
      playerStatus.isPlaying || player.state.buffering;

  bool _isAutoAudioRestoreCurrent(int restoreGeneration) =>
      restoreGeneration == _autoAudioRestoreGeneration &&
      _autoAudioState == AutoAudioOnlyState.autoAudioOnly &&
      _lastAppLifecycleState != AppLifecycleState.hidden &&
      _lastAppLifecycleState != AppLifecycleState.paused &&
      _lastAppLifecycleState != AppLifecycleState.detached &&
      !isPipMode;

  void _completeAutoAudioRestore() {
    _autoAudioState = AutoAudioOnlyState.idle;
    _audioReopened = false;
  }

  void _finishAutoAudioRestoreWait(bool result) {
    final completer = _autoAudioRestoreCompleter;
    if (completer == null || completer.isCompleted) return;
    _autoAudioRestoreTimer?.cancel();
    _autoAudioRestoreTimer = null;
    unawaited(_autoAudioRestoreSubscription?.cancel());
    _autoAudioRestoreSubscription = null;
    _autoAudioRestoreCompleter = null;
    completer.complete(result);
  }

  void _interruptAutoAudioRestore() {
    if (!_autoAudioRestoreInProgress && _autoAudioRestoreCompleter == null) {
      return;
    }
    _autoAudioRestoreGeneration++;
    _autoAudioRestoreInProgress = false;
    suppressBufferingIndicator.value = false;
    _finishAutoAudioRestoreWait(false);
  }

  /// 第二层：重开当前 Media，避免立即进入页面级 playerInit 的加载状态。
  Future<bool> _reopenCurrentMedia(int restoreGeneration) async {
    final player = _videoPlayerController;
    if (player == null || player.current.isEmpty) return false;
    if (!_isAutoAudioRestoreCurrent(restoreGeneration)) return false;

    try {
      final shouldResumePlayback = player.state.playing;
      await player.open(
        player.current.last.copyWith(start: player.state.position),
        play: shouldResumePlayback,
      );
      applyVideoPictureParameters(player);
    } catch (_) {
      return false;
    }

    if (!_isAutoAudioRestoreCurrent(restoreGeneration)) return false;
    return _waitForVideoOutput(restoreGeneration);
  }

  /// 第三层：点播 playerInit，直播 queryLiveUrl。
  Future<void> _fullRestore() async {
    suppressBufferingIndicator.value = false;
    onlyPlayAudio.value = false;
    _completeAutoAudioRestore();
    await onNeedsPlayerInit?.call();
  }

  /// 生命周期变化 — 由 view 转发
  void handleAutoAudioOnlyLifecycle(AppLifecycleState state) {
    _lastAppLifecycleState = state;

    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _cancelAutoAudioOnlyTimer();
        if (_autoAudioRestoreInProgress) {
          _interruptAutoAudioRestore();
        }
        // 已在只听/手动听视频时，保持状态不退出
        if (_autoAudioState == AutoAudioOnlyState.autoAudioOnly ||
            _autoAudioState == AutoAudioOnlyState.manualAudioOnly) {
          break;
        }
        if (isPipMode) {
          _autoAudioState = AutoAudioOnlyState.pipHold;
        } else if (_canEnterAutoAudioOnly()) {
          _autoAudioOnlyTimer = Timer(
            const Duration(seconds: 10),
            applyAutoAudioOnly,
          );
          _autoAudioState = AutoAudioOnlyState.arm;
        }
        break;
      case AppLifecycleState.resumed:
        _cancelAutoAudioOnlyTimer();
        if (_autoAudioState == AutoAudioOnlyState.autoAudioOnly) {
          if (!_autoAudioRestoreInProgress) {
            unawaited(restoreFromAutoAudioOnly());
          }
        } else if (_autoAudioState == AutoAudioOnlyState.arm ||
            _autoAudioState == AutoAudioOnlyState.pipHold) {
          _autoAudioState = AutoAudioOnlyState.idle;
        }
        // manualAudioOnly / pipHold / arm / idle：保持状态不重置
        break;
      case AppLifecycleState.inactive:
        // 过渡状态，忽略
        break;
      case AppLifecycleState.detached:
        _cancelAutoAudioOnlyTimer();
        _interruptAutoAudioRestore();
        break;
    }
  }

  /// 系统 PiP 变化时由 onPipChanged 调用
  void handleAutoAudioOnlyPipChanged(bool isInPip) {
    if (isInPip) {
      _cancelAutoAudioOnlyTimer();
      if (_autoAudioRestoreInProgress) {
        _interruptAutoAudioRestore();
      }
      if (_autoAudioState == AutoAudioOnlyState.arm) {
        _autoAudioState = AutoAudioOnlyState.pipHold;
      }
    } else {
      // PiP 关闭
      _cancelAutoAudioOnlyTimer();
      if (_lastAppLifecycleState == AppLifecycleState.resumed) {
        if (_autoAudioState == AutoAudioOnlyState.autoAudioOnly) {
          unawaited(restoreFromAutoAudioOnly());
        } else if (_autoAudioState == AutoAudioOnlyState.arm ||
            _autoAudioState == AutoAudioOnlyState.pipHold) {
          _autoAudioState = AutoAudioOnlyState.idle;
        }
        // manualAudioOnly 保持不动
      } else {
        // 仍在后台：仅当不在只听/手动听时重新 arm
        if (_autoAudioState == AutoAudioOnlyState.autoAudioOnly ||
            _autoAudioState == AutoAudioOnlyState.manualAudioOnly) {
          return;
        }
        _autoAudioState = AutoAudioOnlyState.arm;
        _autoAudioOnlyTimer = Timer(
          const Duration(seconds: 10),
          applyAutoAudioOnly,
        );
      }
    }
  }

  void dispose() {
    // 离开播放页时复位窗口 HDR 模式，避免设置页/首页留在 HDR 窗口模式。
    _resetWindowHdr();
    _doviDisposed = true;
    _releaseDoviPlayer();
    _hdrSnapshotTimer?.cancel();
    _fullScreenSnapshotTimer?.cancel();
    _fullScreenTransitionTimer?.cancel();
    _fullScreenTransitionTimer = null;
    _fullScreenHdrRepinTimer?.cancel();
    _fullScreenHdrRepinTimer = null;
    // 注意：不要在这里抓快照。销毁过程中 surfaceDestroyed 会把 vo 置回 null，
    // 抓到的会是「拆机态」。播放中每 5 秒的快照已经足够还原真实状态。
    _cancelAutoAudioOnlyTimer();
    _interruptAutoAudioRestore();
    _autoAudioState = AutoAudioOnlyState.idle;
    _audioReopened = false;
    _lastAppLifecycleState = null;
    // 每次减1，最后销毁
    resetScreenRotation();
    cancelLongPressTimer();
    _cancelSpeedLockHintTimer();
    speedLocked = false;
    _speedLockArmed = false;
    speedLockHint.value = SpeedLockHint.none;
    _cancelSubForSeek();
    if (!_isCloseAll && _playerCount > 1) {
      _playerCount -= 1;
      _heartDuration = 0;
      return;
    }

    _playerCount = 0;
    if (removeSafeArea) {
      showSystemBar();
    }
    danmakuController = null;
    danmakuMaskPath.value = null;
    _stopOrientationListener();
    _disableAutoEnterPip();
    setPlayCallBack(null);
    dmState.clear();
    hideDesktopProgressPreview();
    if (showSeekPreview) {
      _clearPreview();
    }
    if (Platform.isAndroid) {
      AndroidHelper$ToDart.onUserLeaveHint = null;
    } else if (Platform.isIOS) {
      IOSPipHelper.dispose();
    }
    _timer?.cancel();
    persistVideoPictureSettings();
    // _position.close();
    // _playerEventSubs?.cancel();
    // _sliderPosition.close();
    // _sliderTempPosition.close();
    // _isSliderMoving.close();
    // _duration.close();
    // _buffered.close();
    // _showControls.close();
    // _controlsLock.close();

    // playerStatus.close();
    // dataStatus.close();

    if (PlatformUtils.isDesktop && isAlwaysOnTop.value) {
      WindowController.instance.window?.isAlwaysOnTop = false;
    }

    _removeListeners();
    _positionListeners.clear();
    _statusListeners.clear();
    _stopWakeLockTimer();
    WakelockPlus.disable();
    if (kDebugMode) {
      debugPrint('dispose player');
    }
    nativeSurfaceMode.value = false;
    _resetNativeSurfaceState();
    _setVideoController(null);
    _sourceGeneration++;
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _activeVideoContextKey = null;
    danmakuMaskPath.dispose();
    // 离开播放页后清掉 Vulkan / 纹理的自动回退记忆：下次播放重新尝试，
    // 否则「某部片源回退过一次」会一直留在进程里，退出视频也不会恢复。
    resetVulkanFallback();
    _instance = null;
    videoPlayerServiceHandler?.clear();
  }

  static void updatePlayCount() {
    if (_instance?._playerCount == 1) {
      _instance?.dispose();
    } else {
      _instance?._playerCount -= 1;
    }
  }

  void setContinuePlayInBackground() {
    continuePlayInBackground.toggle();
    if (!tempPlayerConf) {
      setting.put(
        SettingBoxKey.continuePlayInBackground,
        continuePlayInBackground.value,
      );
    }
    // 关掉后台播放时，停止自动只听状态机
    if (!continuePlayInBackground.value) {
      onAutoAudioOnlySettingChanged();
    }
  }

  late final Map<String, ui.Image?> previewCache = {};
  LoadingState<VideoShotData>? videoShot;
  late final RxBool showPreview = false.obs;
  late final showSeekPreview = Pref.showSeekPreview;
  late final previewIndex = RxnInt();
  final RxBool showDesktopProgressFeedback = false.obs;
  final Rx<double?> desktopProgressHoverValue = Rx<double?>(null);
  final Rx<double?> desktopProgressPreviewValue = Rx<double?>(null);
  final RxInt progressPreviewSeconds = 0.obs;
  final RxInt desktopProgressPreviewLayoutVersion = 0.obs;
  bool _desktopProgressPointerInside = false;
  bool requireDesktopProgressHoverReenter = false;

  bool get _canUseSeekPreview =>
      !isFileSource && showSeekPreview && cid != null;

  void refreshDesktopProgressPreviewLayout() {
    desktopProgressPreviewLayoutVersion.value++;
  }

  double _progressValueFromDuration(Duration value) {
    if (durationInMilliseconds <= 0) {
      return 0.0;
    }
    return (value.inMilliseconds / durationInMilliseconds).clamp(0.0, 1.0);
  }

  void _setDesktopProgressPreviewState(Duration value) {
    final progressValue = _progressValueFromDuration(value);
    progressPreviewSeconds.value = value.inSeconds;
    desktopProgressHoverValue.value = progressValue;
    desktopProgressPreviewValue.value = progressValue;
  }

  void updateDesktopProgressPreviewFromDrag(Duration value) {
    if (!PlatformUtils.isDesktop) {
      return;
    }
    _setDesktopProgressPreviewState(value);
    showDesktopProgressFeedback.value = true;
    if (!isFileSource && showSeekPreview) {
      updatePreviewIndex(value.inSeconds);
    }
  }

  void onDesktopProgressDragStart(Duration value) {
    _desktopProgressPointerInside = true;
    requireDesktopProgressHoverReenter = false;
    updateDesktopProgressPreviewFromDrag(value);
  }

  void onDesktopProgressHoverStart(Duration value) {
    _desktopProgressPointerInside = true;
    if (controlsLock.value || isSeeking.value) {
      return;
    }
    if (requireDesktopProgressHoverReenter) {
      return;
    }
    _setDesktopProgressPreviewState(value);
    showDesktopProgressFeedback.value = true;
    if (!isFileSource && showSeekPreview) {
      updatePreviewIndex(value.inSeconds);
    }
  }

  void onDesktopProgressHoverUpdate(Duration value) {
    _desktopProgressPointerInside = true;
    if (controlsLock.value || isSeeking.value) {
      return;
    }
    if (requireDesktopProgressHoverReenter) {
      return;
    }
    _setDesktopProgressPreviewState(value);
    showDesktopProgressFeedback.value = true;
    if (!isFileSource && showSeekPreview) {
      updatePreviewIndex(value.inSeconds);
    }
  }

  void onDesktopProgressHoverEnd() {
    _desktopProgressPointerInside = false;
    requireDesktopProgressHoverReenter = false;
    if (!isSeeking.value) {
      hideDesktopProgressPreview();
      hideTaskControls();
    }
  }

  void hideDesktopProgressPreview() {
    showDesktopProgressFeedback.value = false;
    desktopProgressHoverValue.value = null;
    desktopProgressPreviewValue.value = null;
    if (showSeekPreview) {
      showPreview.value = false;
    }
  }

  void _setPreviewIndexFromShot(int seconds) {
    final shot = videoShot;
    if (shot case Success(:final response)) {
      previewIndex.value = max(
        0,
        (response.index.where((item) => item <= seconds).length - 2),
      );
    }
  }

  Future<void> ensureVideoShot() async {
    if (!_canUseSeekPreview) {
      return;
    }
    if (videoShot is Loading) {
      return;
    }
    if (videoShot case Success()) {
      return;
    }

    final requestBvid = bvid;
    final requestCid = cid!;
    videoShot = LoadingState.loading();
    final response = await VideoHttp.videoshot(
      bvid: requestBvid,
      cid: requestCid,
    );
    if (requestBvid != _bvid || requestCid != cid) {
      return;
    }

    videoShot = response;
    if (!showPreview.value) {
      return;
    }
    if (response case Success()) {
      _setPreviewIndexFromShot(progressPreviewSeconds.value);
    } else {
      showPreview.value = false;
      previewIndex.value = null;
    }
  }

  void updatePreviewIndex(int seconds) {
    if (!_canUseSeekPreview) {
      return;
    }
    showPreview.value = true;
    if (videoShot == null) {
      previewIndex.value = null;
      unawaited(ensureVideoShot());
      return;
    }
    if (videoShot is Loading) {
      previewIndex.value = null;
      return;
    }
    if (videoShot case Success()) {
      _setPreviewIndexFromShot(seconds);
    } else {
      showPreview.value = false;
      previewIndex.value = null;
    }
  }

  void _clearPreview() {
    showPreview.value = false;
    previewIndex.value = null;
    videoShot = null;
    for (final i in previewCache.values) {
      i?.dispose();
    }
    previewCache.clear();
  }

  /// 上游的 getVideoShot 与之并存的 ensureVideoShot（本 fork）：
  /// ensureVideoShot 会做 _canUseSeekPreview 守卫 + 迟到响应丢弃，
  /// 保留本 fork 版本，删除上游的简单版避免命名冲突。
  int _screenshotState = 0;

  /// 抓取当前画面：HDR 直通时 mpv 拿不到帧，改由原生 SurfaceView 截图。
  Future<ui.Image?> _grabScreenshotImage() async {
    final nativeOwner = _nativeOwner;
    if (!nativeSurfaceMode.value || nativeOwner == null) {
      return videoPlayerController?.screenshot();
    }
    final bytes = await NativeVideoSurfaceChannel.capture(owner: nativeOwner);
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<void> takeScreenshot() async {
    if (_screenshotState > 0) return;
    _screenshotState = 1;
    SmartDialog.showToast('截图中');
    final image = await _grabScreenshotImage();
    if (image != null) {
      SmartDialog.showToast('点击弹窗或按 Enter 保存截图');
      await showDialog(
        context: Get.context!,
        requestFocus: true,
        builder: (context) {
          Future<void> save() async {
            if (_screenshotState > 1) return;
            _screenshotState = 2;
            final bytes = await image.toByteData(format: .png);
            if (bytes != null) {
              final time = DurationUtils.formatDuration(
                positionInMilliseconds / 1000,
              ).replaceAll(':', '-');
              ImageUtils.saveByteImg(
                bytes: bytes.buffer.asUint8List(),
                fileName: 'screenshot_${cid}_$time',
              );
            } else {
              SmartDialog.showToast('保存失败');
            }
            Get.back();
          }

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                final key = event.logicalKey;
                if (key == .keyS || key == .enter || key == .numpadEnter) {
                  save();
                  return .handled;
                }
              }
              return .ignored;
            },
            child: GestureDetector(
              onTap: save,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: min(MediaQuery.widthOf(context) / 3, 350),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          width: 5,
                          color: ColorScheme.of(context).surface,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: RawImage(image: image),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
      image.dispose();
    } else {
      SmartDialog.showToast('截图失败');
    }
    _screenshotState = 0;
  }

  void onPopInvokedWithResult(
    bool didPop,
    Object? result, {
    bool pauseOnPop = true,
  }) {
    if (didPop) {
      if (pauseOnPop && playerStatus.isPlaying) {
        pause();
      }

      setPlayCallBack(null);

      if (Platform.isAndroid && _playerCount <= 1) {
        _disableAutoEnterPip();
        if (!setSystemBrightness) {
          ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
        }
      }

      return;
    }

    if (controlsLock.value) {
      onLockControl(false);
      return;
    }
    if (isDesktopPip) {
      exitDesktopPip();
      return;
    }
    if (isFullScreen.value) {
      triggerFullScreen(status: false);
      return;
    }
    Get.back();
  }
}
