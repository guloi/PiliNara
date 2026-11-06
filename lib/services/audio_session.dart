import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_session/audio_session.dart';

class AudioSessionHandler {
  late AudioSession _session;
  bool _playInterrupted = false;
  bool _pausedService = false;

  Future<bool> setActive(bool active) {
    return _session.setActive(active);
  }

  AudioSessionHandler() {
    initSession();
  }

  Future<void> _configureSession() async {
    if (Pref.mixWithOthers && Platform.isIOS) {
      await _session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        ),
      );
    } else {
      await _session.configure(const AudioSessionConfiguration.music());
    }
  }

  Future<void> reconfigure() async {
    await _session.setActive(false);
    await _configureSession();
  }

  Future<void> initSession() async {
    _session = await AudioSession.instance;
    await _configureSession();

    _session.interruptionEventStream.listen(_onInterrupted);

    // 耳机拔出暂停
    _session.becomingNoisyEventStream.listen((_) {
      videoPlayerServiceHandler?.onPause?.call() ??
          PlPlayerController.pauseIfExists();
    });
  }

  void _onInterrupted(AudioInterruptionEvent event) {
    final playerStatus = PlPlayerController.getPlayerStatusIfExists();
    final servicePlaying = videoPlayerServiceHandler?.isPlaying?.call() == true;
    if (event.begin) {
      if (playerStatus != PlayerStatus.playing && !servicePlaying) return;
      switch (event.type) {
        case AudioInterruptionType.duck:
          PlPlayerController.instance?.handleDuck(true);
          break;
        case AudioInterruptionType.pause:
          // 接收到其他 App 播放音频的通知，如果允许了同时播放，就无视
          if (Pref.mixWithOthers) return;
          _pauseForInterrupt(servicePlaying);
          break;
        case AudioInterruptionType.unknown:
          // Android 的 unknown 对应永久失去音频焦点；iOS 的 unknown
          // 对应音频中断开始，不能复用 Android 的豁免逻辑。
          if (Platform.isAndroid && Pref.mixWithOthers) return;
          _pauseForInterrupt(servicePlaying);
          break;
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          PlPlayerController.instance?.handleDuck(false);
          break;
        case AudioInterruptionType.pause:
          if (_playInterrupted && _pausedService) {
            videoPlayerServiceHandler?.onPlay?.call();
          } else if (_playInterrupted) {
            PlPlayerController.playIfExists();
          }
          break;
        case AudioInterruptionType.unknown:
          break;
      }
      _playInterrupted = false;
      _pausedService = false;
    }
  }

  void _pauseForInterrupt(bool servicePlaying) {
    if (servicePlaying) {
      videoPlayerServiceHandler?.onPause?.call();
      _pausedService = true;
    } else {
      PlPlayerController.pauseIfExists(isInterrupt: true);
    }
    _playInterrupted = true;
  }
}
