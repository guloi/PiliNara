import 'dart:math';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

class PortraitFeedItem {
  PortraitFeedItem({
    required this.bvid,
    this.cid,
    this.aid,
    this.cover,
    this.title,
    this.dimension,
  });

  final String bvid;
  int? cid;
  final int? aid;
  final String? cover;
  final String? title;
  Dimension? dimension;

  bool get isVertical => dimension?.isVertical == true;
}

class PortraitFeedService {
  PortraitFeedService._();

  static final PortraitFeedService instance = PortraitFeedService._();

  static const int _maxHistory = 50;
  static const int _maxProbe = 30;

  final List<PortraitFeedItem> _queue = [];
  final List<PortraitFeedItem> _history = [];

  String? _cursor;
  bool _filling = false;
  int _homeIdx = 0;
  bool _refreshing = false;
  // 预取的下一个视频与它的锚点 bvid：只在同一个「当前视频」上滑时复用，
  // 锚点变了就丢弃，避免用户绕回来时拿到过期的推荐。
  PortraitFeedItem? _prefetched;
  String? _prefetchedFor;
  Future<void>? _prefetchFuture;
  String? _prefetchFor;
  DateTime? _lastRefreshAt;
  static const Duration _refreshCooldown = Duration(seconds: 5);
  final Set<String> _rejected = <String>{};

  /// 开启「随机视频」后从候选池里随机取，而不是按推荐顺序依次取
  final Random _random = Random();

  String? get cursor => _cursor;

  int get historyLength => _history.length;

  bool get canGoPrevious => _history.isNotEmpty;

  void visit(String bvid) {
    if (_cursor == bvid) {
      return;
    }
    final int index = _history.indexWhere((e) => e.bvid == bvid);
    if (index == -1) {
      _queue.clear();
      _history.clear();
      _dropPrefetch();
    } else {
      _history.removeRange(index, _history.length);
    }
    _cursor = bvid;
  }

  void push(PortraitFeedItem item) {
    if (_history.isNotEmpty && _history.last.bvid == item.bvid) {
      return;
    }
    _history.add(item);
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
  }

  PortraitFeedItem? pop() {
    if (_history.isEmpty) {
      return null;
    }
    _dropPrefetch();
    return _history.removeLast();
  }

  void markCursor(PortraitFeedItem item) => _cursor = item.bvid;

  void clear() {
    _queue.clear();
    _history.clear();
    _rejected.clear();
    _cursor = null;
    _dropPrefetch();
  }

  /// 关闭「竖屏即刷」或换页面时彻底清空，连首页推荐的分页游标一起重置，
  /// 下次打开从头开始取推荐
  void reset() {
    clear();
    _homeIdx = 0;
    _lastRefreshAt = null;
    _refreshing = false;
  }

  Future<bool> _refreshFeed(String currentBvid) async {
    if (_refreshing) return false;
    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _refreshCooldown) {
      return false;
    }
    _refreshing = true;
    _lastRefreshAt = now;
    try {
      _queue.clear();
      if (Pref.portraitRC) {
        await _fillHomeRcmd();
      } else {
        await _fillRelated(bvid: currentBvid);
      }
      return true;
    } finally {
      _refreshing = false;
    }
  }

  /// 后台预取 [currentBvid] 之后的视频：上滑时直接命中缓存，不必等网络和
  /// 竖屏探测。失败静默，真正切换时还会再试一次。
  void preloadNext({required String currentBvid}) {
    if (currentBvid.isEmpty) return;
    if (_prefetchFor == currentBvid && _prefetchFuture != null) return;
    if (_prefetchedFor == currentBvid && _prefetched != null) return;
    _prefetchFor = currentBvid;
    late final Future<void> future;
    future = _findNext(currentBvid)
        .then((item) {
          if (item != null && _prefetchFor == currentBvid) {
            _prefetched = item;
            _prefetchedFor = currentBvid;
          }
        })
        .catchError((_) {})
        .whenComplete(() {
          if (identical(_prefetchFuture, future)) {
            _prefetchFuture = null;
          }
        });
    _prefetchFuture = future;
  }

  PortraitFeedItem? _takePrefetched(String currentBvid) {
    final item = _prefetched;
    final forBvid = _prefetchedFor;
    _prefetched = null;
    _prefetchedFor = null;
    if (item == null || forBvid != currentBvid) {
      return null;
    }
    if (item.bvid == currentBvid || _history.any((e) => e.bvid == item.bvid)) {
      return null;
    }
    return item;
  }

  void _dropPrefetch() {
    _prefetched = null;
    _prefetchedFor = null;
    _prefetchFor = null;
    _prefetchFuture = null;
  }

  Future<PortraitFeedItem?> next({required String currentBvid}) async {
    final pending = _prefetchFuture;
    if (pending != null && _prefetchFor == currentBvid) {
      await pending;
    }
    if (_takePrefetched(currentBvid) case final cached?) {
      return cached;
    }
    return _findNext(currentBvid);
  }

  Future<PortraitFeedItem?> _findNext(String currentBvid) async {
    bool refreshed = false;
    // 随机模式下相关推荐很快就会刷完，补一次首页推荐，免得刷几下就断流
    bool homeFilled = false;
    for (int i = 0; i < _maxProbe; i++) {
      var item = _take(currentBvid);
      if (item == null) {
        await _fill(bvid: currentBvid);
        item = _take(currentBvid);
      }
      if (item == null &&
          Pref.portraitRandom &&
          !Pref.portraitRC &&
          !homeFilled) {
        homeFilled = true;
        await _fillHomeRcmd();
        item = _take(currentBvid);
      }
      if (item == null) {
        if (Pref.portraitNewv) {
          if (refreshed || !await _refreshFeed(currentBvid)) {
            return null;
          }
          refreshed = true;
          continue;
        }
        return null;
      }
      if (await _ensureVertical(item)) {
        return item;
      }
      if (item.dimension != null) {
        _rejected.add(item.bvid);
      }
    }
    return null;
  }

  PortraitFeedItem? _take(String currentBvid) {
    // 先剪掉当前视频、已经刷过的和探测出不是竖屏的条目，剩下的才是候选
    _queue.removeWhere(
      (e) =>
          e.bvid == currentBvid ||
          _history.any((h) => h.bvid == e.bvid) ||
          _rejected.contains(e.bvid),
    );
    if (_queue.isEmpty) {
      return null;
    }
    // 随机视频：候选池里随机挑一个，避免每次都是同一批推荐按同样顺序刷
    final int index = Pref.portraitRandom ? _random.nextInt(_queue.length) : 0;
    return _queue.removeAt(index);
  }

  Future<bool> _ensureVertical(PortraitFeedItem item) async {
    if (item.isVertical) {
      return true;
    }
    if (item.dimension != null) {
      return false;
    }
    try {
      final res = await SearchHttp.ab2cWithDimension(
        aid: item.aid,
        bvid: item.bvid,
      );
      if (res == null) {
        return false;
      }
      item.cid ??= res.cid;
      item.dimension = res.dimension;
      return item.isVertical;
    } catch (_) {
      return false;
    }
  }

  Future<void> _fill({required String bvid}) async {
    if (Pref.portraitRC) {
      await _fillHomeRcmd();
    } else {
      await _fillRelated(bvid: bvid);
    }
  }

  Future<void> _fillHomeRcmd() async {
    final res = await VideoHttp.rcmdVideoList(ps: 20, freshIdx: _homeIdx);
    if (res case Success(:final response)) {
      _homeIdx++;
      for (final e in response) {
        final String? bvid = e.bvid;
        if (bvid == null || bvid.isEmpty) {
          continue;
        }
        _queue.add(
          PortraitFeedItem(
            bvid: bvid,
            cid: e.cid,
            aid: e.aid,
            cover: e.cover,
            title: e.title,
            dimension: e.dimension,
          ),
        );
      }
    }
  }

  Future<void> _fillRelated({required String bvid}) async {
    if (_filling) return;
    _filling = true;
    try {
      final res = await VideoHttp.relatedVideoList(bvid: bvid);
      if (res case Success(:final response)) {
        for (final HotVideoItemModel e
            in response ?? const <HotVideoItemModel>[]) {
          if (e.isLive == true || e.isPugv == true) {
            continue;
          }
          if (e.redirectUrl?.isNotEmpty == true) {
            continue;
          }
          if (e.dimension != null && !e.dimension!.isVertical) {
            continue;
          }
          final String? itemBvid = e.bvid;
          if (itemBvid == null || itemBvid.isEmpty) {
            continue;
          }
          _queue.add(
            PortraitFeedItem(
              bvid: itemBvid,
              cid: e.cid,
              aid: e.aid,
              cover: e.cover,
              title: e.title,
              dimension: e.dimension,
            ),
          );
        }
      }
    } catch (_) {
    } finally {
      _filling = false;
    }
  }
}
