part of 'package:PiliPlus/pages/live_room/controller.dart';

/// 本 fork 相对上游 PiliPlus 新增的直播状态：应用内小窗（PiP）、未开播聊天室、
/// 开播时长口径等。纯状态放在这里，需要访问类字段的方法留在 controller.dart。
mixin _LiveForkMixin on GetxController, _LiveDataMixin {
  // ---------- 应用内小窗（PiP） ----------

  /// 是否处于「从应用内小窗返回」的一次性恢复流程
  bool isReturningFromPip = false;

  /// 小窗面板是否正在展示
  final RxBool isInPipMode = false.obs;

  /// 三点菜单「应用内画中画」的触发入口，由直播页 State 绑定：
  /// 小窗流程依赖页面的路由生命周期（pop 收起），controller 自身无法发起
  VoidCallback? onRequestInAppPip;

  /// 直播页能否被 pop：页面 popScope 的 canPop 与三点菜单小窗入口共用
  bool get canPopPage =>
      !plPlayerController.isFullScreen.value && !plPlayerController.isDesktopPip;

  // ---------- 未开播聊天室 ----------

  final isUnstartedRoom = false.obs;
  int? liveStatus;

  /// live_status == 2 是 B 站侧的「轮播中」（轮播 UP 的投稿）
  bool get isRoundRoom => liveStatus == 2;

  // ---------- 兼容上游改名 ----------

  bool get isLogin => isMainLogin;

  final superChatTimeType = Pref.superChatTimeType;
}
