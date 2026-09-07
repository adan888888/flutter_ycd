import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screen_lock/flutter_screen_lock.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:ycd/model/linechart_data_model.dart';
import 'package:ycd/my_db/jsq_operation_record_model.dart';
import 'package:ycd/my_db/jsq_bet_record_model.dart';
import 'package:ycd/my_widget/custom_dialog.dart';
import 'package:ycd/my_widget/more_functions_dialog.dart';
import 'package:ycd/utils/bx_loading.dart';
import 'package:ycd/utils/my_character.dart';
import 'package:ycd/utils/network/api.dart';
import 'package:ycd/utils/network/api_session_handler.dart';
import 'package:ycd/utils/network/get_store.dart';
import 'package:ycd/utils/network/http_mgr.dart';

import 'ji_shu_qi_state.dart';

class JiShuQiController extends GetxController {
  EasyRefreshController refreshcontroller = EasyRefreshController(controlFinishRefresh: true, controlFinishLoad: true);

  /// 统计区下拉刷新（与投注列表同款 EasyRefresh 样式，独立 controller）
  EasyRefreshController statsRefreshController = EasyRefreshController(controlFinishRefresh: true);
  final JiShuQiState state = JiShuQiState();

  final scrollController = ScrollController();

  /// 投注列表「眼睛」行 GlobalKey，用于精确定位滚动（避免手算行高累积误差）
  final GlobalKey tempIndexRowKey = GlobalKey();
  final textEditingController = TextEditingController();
  final focusNode = FocusNode();
  double _lastKeyboardInset = 0;
  Timer? _keyboardOpenSettleTimer;
  int _bettingListScrollGeneration = 0;
  bool _keepBettingListPinnedDuringKeyboard = false;
  bool _bettingListUserDragActive = false;
  DateTime? _ignoreTapOutsideUntil;

// 定义一个计时器，用于延时锁屏
  Timer? _timer;

  final ScrollController roadMapScrollController = ScrollController(); //路子图的controller
  final AudioPlayer _diceSoundPlayer = AudioPlayer();
  bool _diceSoundAvailable = true;

  /// 并发多次 [_getLineCharts] 时仅采纳最近一次发起的 `linechartData` 回调，避免旧响应把已画好的曲线冲掉。
  int _lineChartRequestGen = 0;

  @override
  void onInit() {
    super.onInit();
    BXLoading.syncTheme(state.isDarkMode);
    WakelockPlus.enable();
    onUserInteraction();
    focusNode.addListener(_onInputFocusChanged);

    List.generate(32, (index) => state.totalValue.add('$index'));
    textEditingController.addListener(
      () {
        state.bettingMoney = textEditingController.text;
        if (textEditingController.text.isNotEmpty) {
          ///总体
          state.totalValue[20] = pVal1();

          ///局部
          state.totalValue[24] = pVal2();
          update();
        }
      },
    );
    scrollController.addListener(_onBettingListScroll);
    unawaited(_bootstrapPageData());
  }

  /// 进入页面：统一 Loading；并行请求关闭各自 Toast，由本方法汇总提示一次。
  Future<void> _bootstrapPageData() async {
    BXLoading.show();
    String? errorMsg;
    try {
      Future<void> track(Future<void> future) => future.catchError((e) {
            errorMsg ??= e is String ? e : e.toString();
          });

      await Future.wait([
        track(_queryOperationRecords(isShowLoading: false, showError: false)),
        track(_getStatisticalAreasData(JiShuQiState.tempIndexCmdInit, isShowLoading: false, showError: false)),
        track(_reloadBettingListTail(isShowLoading: false, showError: false)),
      ]);
    } finally {
      BXLoading.reset();
    }
    if (errorMsg != null && errorMsg!.isNotEmpty) {
      BXLoading.showToast(errorMsg!);
    }
    state.isInitialDataLoading = false;
    state.isCanPress = true;
    update();
  }

  void _onInputFocusChanged() {
    if (!focusNode.hasFocus) return;
    // 刚聚焦时短暂忽略 onTapOutside，避免 Android 弹出键盘瞬间误触收回。
    _ignoreTapOutsideUntil = DateTime.now().add(const Duration(milliseconds: 280));
  }

  bool get shouldIgnoreTapOutside {
    final until = _ignoreTapOutsideUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void onInputTapOutside() {
    if (shouldIgnoreTapOutside) return;
    guardAgainstKeyboardPop();
  }

  /// 按最新一页重新拉取投注记录（`last_id: -1`，与进入页面时一致）。
  /// [minCount] 至少条数；若已通过上拉加载更多历史，则用当前条数避免刷新后列表变短。
  /// **局部平衡锚点 id 若不在本窗口内**：不扩列表、不特殊处理；该行不在 `betRecordList` 时眼睛不出现即可。
  Future<void> _reloadBettingListTail({
    int minCount = 66,
    bool isShowLoading = false,
    bool showError = true,
  }) async {
    final completer = Completer<void>();
    final n = state.betRecordList.length > minCount ? state.betRecordList.length : minCount;
    BXGet<JsqBetRecordModel>(
      Api.loadMore,
      params: {"last_id": -1, "uid": GetStore.getInstance().userModel.userId, "c": n},
      success: (isSuccess, code, message, results) {
        if (isSuccess) {
          if (results.isEmpty) {
            state.betRecordList.clear();
            _reloadLuZiTu();
            if (!state.isBigRoad) {
              _getLineCharts(applyStatsTail: true);
            }
            update();
          } else {
            state.betRecordList.clear();
            state.betRecordList = List<JsqBetRecordModel>.from(results);
            _reloadLuZiTu();
            if (!state.isBigRoad) {
              _getLineCharts(applyStatsTail: true);
            }
            update();
            scrollBettingListToBottom();
          }
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      failed: (message, _) {
        if (!completer.isCompleted) {
          completer.completeError(message);
        }
      },
      isShowLoading: isShowLoading,
      showError: showError,
      onModel: (m) => JsqBetRecordModel.fromJson(m),
    );
    return completer.future;
  }

  /// 更新大路图
  /// 根据百家乐大路规则更新大路图数据
  /// [winner] 本局获胜者（闲家/庄家/和局）
  ///
  /// 大路规则：
  /// - 和局不记录在大路中
  /// - 第一局记录在[0][0]位置
  /// - 与上局不同：向右移动（新列）
  /// - 与上局相同：向下移动（同列）
  /// - 长龙规则（标准）：同列向下，若到底或下方被占，则锁定当前行改为向右平移
  void updateBigRoad(String winner) {
    debugPrint('🐉️ 上局: ${state.lastWinner} 当前: $winner');

    // 和局不记录在大路中
    if (winner == '和局') {
      return;
    }

    /************如果是第一局，直接记录在第1行第1列 ********************************************** */
    if (state.lastWinner == '') {
      debugPrint('🐉️ 第一局，记录在 [${state.currentRow}][${state.currentCol}]');
      state.bigRoad[state.currentRow][state.currentCol] = winner;
      state.currentCol++;
    }

    /************ 如果与上一局不同，向右移动（新列）************************************************/
    else if (state.lastWinner != winner) {
      state.dragonStartCol = -1;
      state.dragonParallelRow = -1;
      state.currentRow = 0;
      state.bigRoad[state.currentRow][state.currentCol] = winner;
      debugPrint('🐉️ 与上一局不同，记录在 [${state.currentRow}][${state.currentCol}]');
      state.currentCol++;
    }

    /************ 如果与上一局相同，向下移动 *****************************************************/
    else {
      state.currentRow++;
      var ids = state.currentCol - 1; // 当前列的列

      // 如果下方有内容，或者已经超过6行，则需要往右平移（长龙处理）
      if ((state.currentRow < JiShuQiState.bigRoadRows && state.bigRoad[state.currentRow][ids].isNotEmpty) ||
          state.currentRow > JiShuQiState.bigRoadRows - 1) {
        // 长龙处理：向右平移
        state.dragonStartCol++;
        state.bigRoad[state.dragonParallelRow][state.dragonStartCol] = winner;
        debugPrint('🐉️（长龙处理）与上一局相同，记录在 [${state.dragonParallelRow}][${state.dragonStartCol}]');
      } else {
        // 没有超过6行，且下方没有内容，正常往下走
        state.bigRoad[state.currentRow][state.currentCol - 1] = winner;
        state.dragonParallelRow = state.currentRow; // 记录最后一次行
        state.dragonStartCol = state.currentCol - 1; // 记录最后一次列
        debugPrint('🐉️ 与上一局相同，记录在 [${state.currentRow}][${state.currentCol - 1}]');
      }
    }

    state.lastWinner = winner;
  }

  /// 自动滚动到当前绘制位置
  void scrollToCurrentPosition() {
    // 使用 addPostFrameCallback 保证在当前帧绘制完成后再执行滚动，避免滚动区域未布局完成导致异常
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (roadMapScrollController.hasClients) {
        // 计算当前列右边界的位置(这样计算还是有点不准，能在整个数据里找到最右边的列才更准，不过实际中应该没有那长的龙，先就这样吧)
        double currentColRightEdge =
            (state.dragonStartCol == -1 ? state.currentCol : state.dragonStartCol + 1) * JiShuQiState.cellWidth;

        double currentScrollOffset = roadMapScrollController.position.pixels /* 当前滚动位置（滑动了多少）*/;
        /* 当前滚动位置 + 可见区域尺寸 = 可见区域右边界 */
        double visibleRightEdge = currentScrollOffset + roadMapScrollController.position.viewportDimension /* 可见区域尺寸 */;

        // 只有当当前列的右边界超出可见区域右边界时才滚动
        if (currentColRightEdge > visibleRightEdge) {
          // 计算需要滚动的距离，让当前列刚好可见
          double scrollDistance = currentColRightEdge - visibleRightEdge + JiShuQiState.cellWidth;
          double newOffset = currentScrollOffset + scrollDistance;

          // 确保不超过最大滚动范围
          double maxOffset = roadMapScrollController.position.maxScrollExtent;
          if (newOffset > maxOffset) {
            newOffset = maxOffset;
          }

          roadMapScrollController.animateTo(
            newOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  /// 路子图数据变更后调度滚动：`update()` 之后 extent 可能尚未更新，多帧 + 短延迟与投注列表兜底一致。
  void _scheduleRoadMapScrollAfterRebuild() {
    if (!state.hasBigRoadData) return;
    void tick() => scrollToCurrentPosition();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tick();
      WidgetsBinding.instance.addPostFrameCallback((_) => tick());
    });
    Future.delayed(const Duration(milliseconds: 50), tick);
    Future.delayed(const Duration(milliseconds: 180), tick);
  }

  static const double _bettingListBottomThreshold = 1.5;

  bool _computeBettingListAtBottom() {
    if (!scrollController.hasClients) return state.isBettingListAtBottom;
    final pos = scrollController.position;
    final max = pos.maxScrollExtent;
    if (!max.isFinite) return state.isBettingListAtBottom;
    if (max <= 0.5) return true;
    return max - pos.pixels <= _bettingListBottomThreshold;
  }

  void _onBettingListScroll() {
    final atBottom = _computeBettingListAtBottom();
    if (atBottom == state.isBettingListAtBottom) return;
    state.isBettingListAtBottom = atBottom;
    update();
  }

  void _syncBettingListAtBottom({bool? atBottom}) {
    final next = atBottom ?? _computeBettingListAtBottom();
    if (next == state.isBettingListAtBottom) return;
    state.isBettingListAtBottom = next;
    update();
  }

  /// 右下角悬浮钮：在底部时向上滚到眼睛行，否则向下滚到列表最底。
  void onBettingListJumpFabTap() {
    dismissKeyboard();
    if (state.isBettingListAtBottom) {
      // 没有眼睛目标或列表尚未挂载时 jump 是 no-op，此时仍要保留收键盘后的粘底校正。
      if (scrollController.hasClients && state.currentTempIndex != 0) {
        _stopKeepingBettingListPinned();
      }
      jumpToCurrentTempIndexRow();
    } else {
      if (_lastKeyboardInset > 0) {
        _keepBettingListPinnedDuringKeyboard = true;
      }
      scrollBettingListToBottom();
    }
  }

  /// 投注列表时间升序（最新在底部）。多帧 + 延迟重试，避免刚 `update()` 后 extent 未算准、或未挂上 Scrollable。
  void scrollBettingListToBottom() {
    final generation = ++_bettingListScrollGeneration;
    bool isCurrentRequest() => generation == _bettingListScrollGeneration;

    void jumpToEnd() {
      if (!isCurrentRequest() || !scrollController.hasClients) return;
      final max = scrollController.position.maxScrollExtent;
      if (!max.isFinite || max < 0) return;
      scrollController.jumpTo(max);
    }

    /// 仍未挂上 Scrollable；或已与底部相差较大：再试。extent 尚为 0 但条数较多时视为未布局完。
    bool needsAnotherTry() {
      if (!isCurrentRequest()) return false;
      if (!scrollController.hasClients) return state.betRecordList.isNotEmpty;
      if (state.betRecordList.isEmpty) return false;
      final pos = scrollController.position;
      final max = pos.maxScrollExtent;
      if (!max.isFinite) return true;
      if (max <= 0.5) {
        return state.betRecordList.length > 8;
      }
      return max - pos.pixels > 1.5;
    }

    void scheduleFrames(int left) {
      if (left <= 0 || !isCurrentRequest()) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isCurrentRequest()) return;
        jumpToEnd();
        final more = needsAnotherTry() && left > 1;
        if (more) scheduleFrames(left - 1);
      });
    }

    void retryAfterDelay() {
      if (!isCurrentRequest()) return;
      jumpToEnd();
      if (isCurrentRequest()) {
        _syncBettingListAtBottom(atBottom: true);
      }
    }

    scheduleFrames(10);
    Future.delayed(const Duration(milliseconds: 50), retryAfterDelay);
    Future.delayed(const Duration(milliseconds: 180), retryAfterDelay);
    Future.delayed(const Duration(milliseconds: 420), retryAfterDelay);
  }

  /// 用户开始触摸列表/页面后，旧的自动滚动重试不得再抢占拖动手势。
  void cancelPendingBettingListAutoScroll() {
    _keyboardOpenSettleTimer?.cancel();
    _bettingListScrollGeneration++;
  }

  void _stopKeepingBettingListPinned() {
    _keepBettingListPinnedDuringKeyboard = false;
    cancelPendingBettingListAutoScroll();
  }

  /// 列表真实拖动会暂停旧的自动滚动，但在确认离开底部前仍保留键盘会话的粘底意图。
  void onBettingListUserDragStart() {
    _bettingListUserDragActive = true;
    cancelPendingBettingListAutoScroll();
  }

  void onBettingListUserDragPositionChanged() {
    if (!_bettingListUserDragActive) return;
    _keepBettingListPinnedDuringKeyboard =
        _lastKeyboardInset > 0 && _computeBettingListAtBottom();
    cancelPendingBettingListAutoScroll();
  }

  void onBettingListUserDragEnd() {
    if (!_bettingListUserDragActive) return;
    _bettingListUserDragActive = false;
    _keepBettingListPinnedDuringKeyboard =
        _lastKeyboardInset > 0 && _computeBettingListAtBottom();
    cancelPendingBettingListAutoScroll();
  }

  /// 点击列表等空白区域时收起键盘（不用 TextField.onTapOutside，避免弹出瞬间误触收回）。
  void dismissKeyboard() {
    if (focusNode.hasFocus) {
      focusNode.unfocus(disposition: UnfocusDisposition.scope);
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary.hasFocus) {
      primary.unfocus(disposition: UnfocusDisposition.scope);
    }
  }

  /// 底部键盘展开或输入框仍聚焦时释放焦点。
  /// 用于点骰子、关庄闲弹窗等场景，避免输入框再次被激活、键盘又顶起来。
  /// 若键盘本就没开，则不做任何事。
  void guardAgainstKeyboardPop() {
    if (!focusNode.hasFocus && _lastKeyboardInset <= 0) return;
    dismissKeyboard();
  }

  /// 键盘“弹出完成后”再滚到底，避免动画过程中触发布局抖动。
  void onKeyboardInsetChanged(double inset) {
    final previousInset = _lastKeyboardInset;
    if (previousInset == inset) return;

    _lastKeyboardInset = inset;

    // inset 动画本身不是用户滚动，不能让它取消刚由数据更新触发的滚底重试。
    _keyboardOpenSettleTimer?.cancel();
    if (inset > 0) {
      if (previousInset <= 0) {
        _keepBettingListPinnedDuringKeyboard = true;
      }
      // 键盘动画或键盘类型切换会连续上报 inset。每次变化都重新计时，
      // 确保使用稳定后的列表视口高度滚到底。
      _keyboardOpenSettleTimer = Timer(const Duration(milliseconds: 260), () {
        if (!focusNode.hasFocus ||
            _lastKeyboardInset <= 0 ||
            !_keepBettingListPinnedDuringKeyboard) {
          return;
        }
        scrollBettingListToBottom();
      });
    } else if (inset <= 0 && previousInset > 0) {
      final shouldRestoreBottom = _keepBettingListPinnedDuringKeyboard;
      _keepBettingListPinnedDuringKeyboard = false;
      if (!shouldRestoreBottom) {
        return;
      }

      // 键盘完全收起时图表与 SafeArea 会重新加入布局；等新 viewport 生效后再按新的 extent 滚底。
      final generation = _bettingListScrollGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (generation != _bettingListScrollGeneration || _lastKeyboardInset > 0) {
          return;
        }
        scrollBettingListToBottom();
      });
    }
  }

  void jumpToCurrentTempIndexRow() {
    if (!scrollController.hasClients) return;
    final tempIndex = state.currentTempIndex;
    if (tempIndex == 0) return;

    int idx = state.betRecordList.indexWhere((e) => e.id != null && e.id == tempIndex);
    // 如果眼睛的位置不在列表中，则加载更多数据，再滚动到眼睛的位置
    if (idx < 0) {
      unawaited(_loadMoreForTempIndex(tempIndex));
      return;
    }
    _scrollToTempIndexRow(idx);
  }

  Future<void> _loadMoreForTempIndex(int tempIndex) async {
    if (state.betRecordList.isEmpty) return;
    final firstId = state.betRecordList.first.id;
    if (firstId == null) return;
    // 目标 id 比当前最旧 id 还新，说明不存在“往前加载更多”空间。
    if (tempIndex >= firstId) return;

    var loadCount = firstId - tempIndex;
    if (loadCount < 1) loadCount = 1;
    final inserted = await onLoadMore(
      count: loadCount,
      preserveViewport: false,
    );
    if (inserted <= 0) return;

    // 加载后按最新列表重算一次索引再滚动。
    await WidgetsBinding.instance.endOfFrame;
    if (!scrollController.hasClients) return;
    final idx = state.betRecordList.indexWhere((e) => e.id != null && e.id == tempIndex);
    if (idx >= 0) {
      _scrollToTempIndexRow(idx);
    }
  }

  /// 滚到「眼睛」行：优先 [Scrollable.ensureVisible]；行未挂载时用行高粗估再重试。
  void _scrollToTempIndexRow(int idx) {
    if (!scrollController.hasClients || idx < 0) return;
    const rowH = JiShuQiState.bettingTableRowHeight;

    Future<void> tryEnsure({int attempt = 0}) async {
      final ctx = tempIndexRowKey.currentContext;
      if (ctx != null) {
        final viewport = scrollController.position.viewportDimension;
        final align = viewport > 0 ? (JiShuQiState.bettingTableScrollTopInset / viewport).clamp(0.0, 0.35) : 0.0;
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: align,
        );
        return;
      }
      if (attempt > 15) return;
      final maxS = scrollController.position.maxScrollExtent;
      if (maxS.isFinite) {
        scrollController.jumpTo((idx * rowH).clamp(0.0, maxS));
      }
      await WidgetsBinding.instance.endOfFrame;
      await tryEnsure(attempt: attempt + 1);
    }

    unawaited(tryEnsure());
  }

  /// 顶部插入历史行后恢复视口：用固定行高累计增量（避免 LazyList / EasyRefresh 回弹时 maxScrollExtent 不准）。
  /// 下拉刷新时 [keptPixels] 可能为负，按 0 处理。
  void _schedulePreserveScrollAfterPrepend(double keptPixels, int insertedCount) {
    if (insertedCount <= 0 || !keptPixels.isFinite) return;
    final delta = JiShuQiState.bettingTableRowHeight * insertedCount;
    final base = keptPixels < 0 ? 0.0 : keptPixels;

    void apply() {
      if (!scrollController.hasClients) return;
      final maxS = scrollController.position.maxScrollExtent;
      if (!maxS.isFinite) return;
      scrollController.jumpTo((base + delta).clamp(0.0, maxS));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      apply();
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    });
    // EasyRefresh 收起头部时还会改一次 offset，晚一点再对齐
    Future.delayed(const Duration(milliseconds: 320), apply);
    Future.delayed(const Duration(milliseconds: 560), apply);
  }

  /// 局部平衡锚点（投注列表「眼睛」行 id）：以后端“jsq_operation_records.temp_index”为准，
  /// 对应客户端 `operationRecordList.last.tempIndex`；值为整数且 **>2** 视为有效 投注记录主键 id。
  /// **temp_index 为取消或重启指令**：`currentTempIndex` 固定为 **0**。
  /// 若无 操作记录数据则退回统计接口回填的 `totalValue[29]`（兼容冷启动顺序）。
  /// **锚点 id 不在当前 `betRecordList` 时**：不处理列表窗口（不保证眼睛可见）；仅保持 `currentTempIndex` 与配置一致。
  void _syncLocalTempIndexWithBackendState() {
    if (state.operationRecordList.isNotEmpty) {
      final raw = state.operationRecordList.last.tempIndex?.trim() ?? '';
      // 后端 temp_index 为清空指令：锚点归零
      if (_isClearLocalTempIndex(raw)) {
        state.currentTempIndex = 0;
        return;
      }
      final v = int.tryParse(raw);
      state.currentTempIndex = _isEffectiveLocalTempIndex(v) ? v! : 0;
      return;
    }
    if (state.totalValue.length > 29) {
      final raw = state.totalValue[29].toString().trim();
      if (raw.isEmpty) return;
      if (_isClearLocalTempIndex(raw)) {
        state.currentTempIndex = 0;
        return;
      }
      final v = int.tryParse(raw);
      if (_isEffectiveLocalTempIndex(v)) state.currentTempIndex = v!;
    }
  }

  bool _isClearLocalTempIndex(Object? tempIndex) =>
      tempIndex == JiShuQiState.tempIndexCmdCancel || tempIndex == JiShuQiState.tempIndexCmdReset;

  bool _isEffectiveLocalTempIndex(Object? tempIndex) => tempIndex is int && tempIndex > 2;

  /// tempIndex 指令协议：
  /// - init：页面首次加载，恢复后端已保存的锚点。
  /// - keep：数据变化后刷新统计，但保留当前锚点。
  /// - cancel(取消)：用户主动取消局部平衡。
  /// - reset(重启)：重启局部数据后清空局部平衡锚点。
  /// - anchor(>2)：选中投注记录 id 作为局部平衡锚点。
  Future<void> _getStatisticalAreasData(
    Object? tempIndex, {
    bool isShowLoading = true,
    bool showError = true,
  }) {
    final completer = Completer<void>();
    BXGet<dynamic>(
      Api.getStatisticalAreasData,
      params: {"tempIndex": tempIndex},
      isShowLoading: isShowLoading,
      showError: showError,
      success: (isSuccess, code, message, results) {
        state.totalValue = results.map((e) => e.toString()).toList();
        state.totalValue[28] = "${state.js1}/${state.js2}";

        void continueAfterStatsReady() {
          _syncLocalTempIndexWithBackendState();
          //预测平均值
          if (textEditingController.text.isNotEmpty) {
            ///总体
            state.totalValue[20] = pVal1();

            ///局部
            state.totalValue[24] = pVal2();
          }
          state.isCanPress = true;

          if (state.isBigRoad) {
            _reloadLuZiTu(); //路子图直接在本地的数据处理
            update();
          } else {
            // 统计区 totalValue[4] 由服务端按全表重算，用作折线最右一点，避免与 column_current_jin 漂移（如大输赢后末端不更新）
            _getLineCharts(applyStatsTail: true);
          }
          _delayedTask(); //必须要提一个方法放出去，不然会会卡下面的代码
          if (!completer.isCompleted) {
            completer.complete();
          }
        }

        // 取消、重启或选中锚点行(>2) 时后端会更新 operationRecord.tempIndex；须先拉 operationRecord 再同步，
        // 否则会沿用内存里旧的 temp_index，把 currentTempIndex 又写回去（取消失效）。
        final ti = tempIndex;
        final needsFreshOperationRecords = _isClearLocalTempIndex(ti) || _isEffectiveLocalTempIndex(ti);
        if (needsFreshOperationRecords) {
          _queryOperationRecords().then((_) => continueAfterStatsReady()).catchError((_) => continueAfterStatsReady());
        } else {
          continueAfterStatsReady();
        }
      },
      failed: (message, _) {
        state.isCanPress = true;
        if (!completer.isCompleted) {
          completer.completeError(message);
        }
      },
    );
    return completer.future;
  }

  Future<void> _delayedTask() async {
    Future.delayed(const Duration(milliseconds: 300), () {
      state.totalValue[29] = state.randomValue;
      update();
    });
  }

  void showBottomFunction() {
    dismissKeyboard();
    Get.dialog<void>(
      MoreFunctionsDialog(
        isDarkMode: state.isDarkMode,
        functionTypes: state.functionTypes,
        onSelected: (index) => unawaited(functionConfirm(index)),
      ),
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: state.isDarkMode ? 0.62 : 0.42),
      useSafeArea: true,
    );
  }

  double _commissionRate() {
    if (state.totalValue.length <= 31) return 0.95;
    final raw = state.totalValue[31].toString();
    if (raw.isEmpty || raw == '31') return 0.95;
    return double.tryParse(raw) ?? 0.95;
  }

  double? _parseStatDouble(dynamic raw) {
    final s = MyCharacter.removeChineseCharacters(raw.toString()).trim();
    if (s.isEmpty || s == '-') return null;
    return double.tryParse(s);
  }

  String pVal2() {
    if (state.bettingMoney.isEmpty || !state.bettingMoney.isNum) return '';
    final bet = double.tryParse(textEditingController.text);
    if (bet == null) return '';
    final val = state.randomValue == '庄' ? (bet * _commissionRate()).toStringAsFixed(2) : textEditingController.text;
    final x = _parseStatDouble(state.totalValue[18]); //总输赢
    final y = double.tryParse(val); //输入框下注额
    final z = _parseStatDouble(state.totalValue[14]); //净胜
    if (x == null || y == null || z == null) return '';
    final z1 = z.abs(); //净胜绝对值
    if (z == 0) {
      return "回合结束";
    } else if (z > 0) /*赢>输的情况*/ {
      if ((z1 - 1) <= 0) {
        return '${((x + y) / (z1 + 1)).toStringAsFixed(1)}/';
      }
      return '${((x + y) / (z1 + 1)).toStringAsFixed(1)}/${((x - y) / (z1 - 1)).toStringAsFixed(1)}';
    } else {
      if ((z1 - 1) <= 0) {
        return '/${((x - y) / (z1 + 1)).toStringAsFixed(1)}';
      }
      return '${((x + y) / (z1 - 1)).toStringAsFixed(1)}/${((x - y) / (z1 + 1)).toStringAsFixed(1)}';
    }
  }

  String pVal1() {
    if (state.bettingMoney.isEmpty || !state.bettingMoney.isNum) return '';
    final bet = double.tryParse(textEditingController.text);
    if (bet == null) return '';
    final val = state.randomValue == '庄' ? (bet * _commissionRate()).toStringAsFixed(2) : textEditingController.text;
    final x = _parseStatDouble(state.totalValue[17]); //总输赢
    final y = double.tryParse(val); //输入框下注额
    final z = _parseStatDouble(state.totalValue[13]); //净胜
    if (x == null || y == null || z == null) return '';
    final z1 = z.abs(); //净胜绝对值
    if (z == 0) {
      return "回合结束";
    } else if (z > 0) /*赢>输的情况*/ {
      if ((z1 - 1) <= 0) {
        return '${((x + y) / (z1 + 1)).toStringAsFixed(1)}/';
      }
      return '${((x + y) / (z1 + 1)).toStringAsFixed(1)}/${((x - y) / (z1 - 1)).toStringAsFixed(1)}';
    } else {
      if ((z1 - 1) <= 0) {
        return '/${((x - y) / (z1 + 1)).toStringAsFixed(1)}';
      }
      return '${((x + y) / (z1 - 1)).toStringAsFixed(1)}/${((x - y) / (z1 + 1)).toStringAsFixed(1)}';
    }
  }

  @override
  void onClose() {
    cancelPendingBettingListAutoScroll();
    scrollController.removeListener(_onBettingListScroll);
    focusNode.removeListener(_onInputFocusChanged);
    _timer?.cancel();
    _diceSoundPlayer.dispose();
    statsRefreshController.dispose();
    WakelockPlus.disable();
    focusNode.dispose();
    textEditingController.dispose();
    super.onClose();
  }

  void _playSound(String asset, {double volume = 1.0}) {
    if (!_diceSoundAvailable) return;
    unawaited(() async {
      try {
        await _diceSoundPlayer.stop();
        await _diceSoundPlayer.play(
          AssetSource(asset),
          volume: volume,
          mode: PlayerMode.lowLatency,
        );
      } catch (e) {
        _diceSoundAvailable = false;
        debugPrint('sound unavailable: $e');
      }
    }());
  }

  void _randomFeedback() => unawaited(HapticFeedback.lightImpact());

  void _playRandomSound() => _playSound('sounds/random_ding.wav', volume: 0.4);

  void _playDiceRollSound() => _playSound('sounds/zhuotou.mp3');

  setRandom(Function(int) f) {
    if (!state.isCanPress) {
      return;
    }
    guardAgainstKeyboardPop();
    _randomFeedback();
    _playRandomSound();
    state.isCanPress = false;
    state.js2 = state.js2 + 1;
    state.totalValue[28] = "${state.js1}/${state.js2}";
    BXGet(
      Api.randomBankerPlayer,
      success: (isSuccess, code, message, results) {
        var result = (results.first as Map)["result"].toString();

        if (result.isNotEmpty) {
          state.randomValue = state.totalValue[29] = result;
        } else {
          // if (next(1, 90485) > 44625 - MyState.OFFSET8431) {
          //1到100（包含1，100）//<= 70 是 70%庄 30%闲
          if (_next(1, 100) <= state.ratio) {
            state.randomValue = state.totalValue[29] = '庄';
          } else {
            state.randomValue = state.totalValue[29] = '闲';
          }
        }
        Get.dialog(
          ZhuangXianDialog(
            state.randomValue,
            darkTextColor: state.darkTextColor,
          ),
          barrierDismissible: false,
          barrierColor: Colors.black.withValues(alpha: 0.18),
        ).then((_) => guardAgainstKeyboardPop());
        state.isCanPress = true;

        ///总体
        state.totalValue[20] = pVal1();

        ///局部
        state.totalValue[24] = pVal2();
        update();
      },
      isShowLoading: false, // 使用自定义的Loading
    );
  }

  _next(int min, int max) => min + Random().nextInt(max - min + 1);

  Future<void> _queryOperationRecords({
    bool isShowLoading = false,
    bool showError = true,
  }) {
    final completer = Completer<void>();
    BXGet<JsqOperationRecordModel>(Api.getOperationRecords,
        isShowLoading: isShowLoading,
        showError: showError,
        success: (isSuccess, code, message, value) {
          state.operationRecordList.clear();
          if (value.isNotEmpty) {
            state.operationRecordList = value;
            state.totalValue[0] = '${state.operationRecordList.last.benjin}'; //本金
            state.totalValue[19] = '${state.operationRecordList.last.mean}'; //期望值
            // 折线形状必须由 [_getLineCharts]（投注记录末尾或 linechartData）提供；此处若用本金铺满 75 点，
            // 会在接口已画出真实曲线之后覆盖成一条水平线（本金为 0 时即为「全 0」）。
            _syncLocalTempIndexWithBackendState();
          } else {
            state.currentTempIndex = 0;
          }
          update();
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        failed: (p0, p1) {
          refreshcontroller.finishRefresh(IndicatorResult.fail);
          state.isCanPress = true;
          if (!completer.isCompleted) {
            completer.completeError(p0);
          }
        },
        onModel: (m) => JsqOperationRecordModel.fromJson(m));
    return completer.future;
  }

  betRecordButton(int i, String recordType, {JsqOperationRecordModel? operationRecord, JsqBetRecordModel? betRecord}) {
    if (state.randomValue.isEmpty) {
      Get.snackbar("温馨提示", '请摇塞子',
          duration: const Duration(seconds: 2),
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.white.withValues(alpha: 0.2));
      return;
    }

    if (state.bettingMoney.isEmpty) {
      Get.snackbar("温馨提示", '请输入下注金额',
          duration: const Duration(seconds: 2),
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.white.withValues(alpha: 0.3));
      return;
    }
    if (!state.bettingMoney.isNum) {
      Get.snackbar("温馨提示", '请输入数字',
          duration: const Duration(seconds: 2),
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.white.withValues(alpha: 0.3));
      return;
    }
    if (!state.isCanPress) {
      Get.snackbar("温馨提示", '速度太快',
          duration: const Duration(seconds: 2),
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.white.withValues(alpha: 0.3));
      return;
    }
    _playDiceRollSound();
    BXLoading.show(douyinStyle: true);
    state.isCanPress = false;
    state.js1 = state.js1 + 1;
    final table = recordType == 'betRecord'
        ? JsqBetRecordModel(
            id: state.betRecordList.length + 1,
            xiazhujine: double.tryParse(state.bettingMoney),
            zx: (i == 2 || i == 3) ? '庄' : '闲',
            remark: (i == 1 || i == 2) ? "1" : "-1",
            shengfulu:
                ((i == 1 || i == 3) && (state.randomValue == '闲')) || ((i == 2 || i == 4) && (state.randomValue == '庄'))
                    ? "正打"
                    : "反打",
            shuyingzhi: syzLAmount(i),
            shuyingzhiXiaoshu: syzLAmount(i),
            currentJin: getCurrentJin(i, double.parse(state.bettingMoney)),
          )
        : JsqOperationRecordModel(benjin: 10000, yongjin: 0.95, mean: 0.08, restartIndex: 0, liushuiIndex: 10);

    ///改变成插入远程数据库
    if (recordType == 'operationRecord') {
      BXPut<JsqOperationRecordModel>(Api.createOperationRecord,
          params: (table as JsqOperationRecordModel).toJson()
            ..addAll({"user_id": int.parse(GetStore.getInstance().userModel.userId)}),
          isShowLoading: false,
          success: (isSuccess, code, message, results) {
            BXLoading.dismiss();
            state.isCanPress = true;
            if (isSuccess) BXLoading.showToast("操作记录");
          },
          failed: (p0, p1) {
            state.isCanPress = true;
            BXLoading.dismiss();
          },
          onModel: (m) => JsqOperationRecordModel.fromJson(m));
    } else {
      BXPut<JsqBetRecordModel>(Api.createBetRecord,
          isShowLoading: false,
          params: (table as JsqBetRecordModel).toJson()
            ..remove("betRecordId")
            ..addAll({"user_id": int.parse(GetStore.getInstance().userModel.userId)}),
          success: (isSuccess, code, message, results) {
            if (results.isNotEmpty) {
              final row = results.first;
              row.seq =
                  state.betRecordList.isEmpty ? 1 : (state.betRecordList.last.seq ?? state.betRecordList.length) + 1;
              state.betRecordList.add(row);
            }
            update(); // 先让 ListView 用新 itemCount 布局，再滚到底才准
            scrollBettingListToBottom();
            _getStatisticalAreasData(JiShuQiState.tempIndexCmdKeep, isShowLoading: false)
                .whenComplete(BXLoading.dismiss);
          },
          failed: (p0, p1) {
            state.isCanPress = true;
            BXLoading.dismiss();
          },
          onModel: (m) => JsqBetRecordModel.fromJson(m));
    }
  }

  /// 折线：需要完整 75 个点。
  /// - 本地已加载 ≥75 条时，用 betRecordList 末尾 75 条（时间升序，与列表一致）。
  /// - 否则（如首屏只拉 66 条）走 linechartData 接口，从库中取最近 75 笔（id 降序返回，从尾到头填入）。
  /// - [applyStatsTail]：在刚从统计接口回填后，将最右一点强制为 [totalValue[4]]（本金+累计输赢），与统计区「当前金额」一致。
  void _getLineCharts({bool applyStatsTail = false}) {
    final gen = ++_lineChartRequestGen;
    final benjin =
        state.operationRecordList.isNotEmpty ? double.tryParse(state.operationRecordList.last.benjin.toString()) : null;
    void resetChartPad(double p) {
      if (state.chartData.length != 75) {
        state.chartData = List.generate(75, (index) => LineChartDataModel(index, p));
      } else {
        for (var i = 0; i < 75; i++) {
          state.chartData[i].sales = p;
        }
      }
    }

    final pad = benjin ?? (state.chartData.isNotEmpty ? state.chartData[0].sales : 0.0);
    resetChartPad(pad);

    final list = state.betRecordList;
    if (list.length >= 75) {
      final n = list.length;
      final start = n - 75;
      for (var k = 0; k < 75; k++) {
        final v = list[start + k].currentJin;
        if (v != null) {
          state.chartData[k].sales = v;
        }
      }
      if (applyStatsTail) {
        _syncChartLastPointWithTotalValue();
      }
      update();
      return;
    }

    BXGet<dynamic>(
      Api.getLinechartData,
      success: (isSuccess, code, message, results) {
        if (gen != _lineChartRequestGen) return;
        if (!isSuccess) return;
        resetChartPad(benjin ?? (state.chartData.isNotEmpty ? state.chartData[0].sales : 0.0));
        var z = 0;
        for (var i = results.length - 1; i >= 0 && z < state.chartData.length; i--) {
          if (results[i].toString().isNotEmpty) {
            state.chartData[z].sales = double.parse(results[i].toString());
          }
          z++;
        }
        if (applyStatsTail) {
          _syncChartLastPointWithTotalValue();
        }
        update();
      },
      isShowLoading: false, // 第二个接口不显示loading，避免重复显示
    );
  }

  /// 与统计区 [totalValue[4]] 对齐折线最右端（第 75 点），对应服务端「本金 + 全表输赢累计」。
  void _syncChartLastPointWithTotalValue() {
    if (state.chartData.length != 75) return;
    if (state.totalValue.length <= 4) return;
    final raw = MyCharacter.removeChineseCharacters(state.totalValue[4].toString()).trim();
    if (raw.isEmpty) return;
    final v = double.tryParse(raw);
    if (v != null) {
      state.chartData[74].sales = v;
    }
  }

  getCurrentJin(int i, double playMoney) {
    var lastJinE = state.betRecordList.isEmpty ? 5000 : double.parse(state.totalValue[4].toString());
    switch (i) {
      case 1:
        return (lastJinE + playMoney);
      case 2:
        return (lastJinE) +
            playMoney *
                double.parse(
                    state.totalValue[31] == "31" || state.totalValue[31] == "" ? "0.95" : state.totalValue[31]);
      case 3:
      case 4:
        return (lastJinE) - playMoney;
    }
  }

  double? syzLAmount(int i) {
    final bet = double.tryParse(state.bettingMoney);
    if (bet == null) return null;
    switch (i) {
      case 1:
        return bet;
      case 2:
        final odds = double.tryParse(
                state.totalValue[31] == "31" || state.totalValue[31] == "" ? "0.95" : state.totalValue[31]) ??
            0.95;
        return bet * odds;
      case 3:
      case 4:
        return -bet;
      default:
        return null;
    }
  }

  /// 输赢展示字符串（带 +/- 前缀，仅用于界面）
  String syzL(int i) {
    final amount = syzLAmount(i);
    if (amount == null) return '';
    if (amount > 0) {
      return amount == double.parse(state.bettingMoney) && i == 1
          ? '+${state.bettingMoney}'
          : '+${_formatZhuangYingShuying(amount)}';
    }
    return '-${state.bettingMoney}';
  }

  /// 庄赢输赢字符串：去掉末尾多余 0，避免 0.095 被格式化成与 0.1 混淆。
  String _formatZhuangYingShuying(double value) {
    final s = value.toStringAsFixed(8); //四舍五入到8位小数
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  void deleteLast() {
    dismissKeyboard();
    if (state.betRecordList.isEmpty) return;
    BXDelete<JsqBetRecordModel>(Api.deleteLast,
        success: (isSuccess, code, message, results) {
          if (!isSuccess) return;
          if (results.isNotEmpty) {
            final deletedId = results.first.id;
            final idx = deletedId == null ? -1 : state.betRecordList.indexWhere((e) => e.id == deletedId);
            if (idx >= 0) {
              state.betRecordList.removeAt(idx);
            } else if (state.betRecordList.isNotEmpty) {
              state.betRecordList.removeLast();
            }
          }
          state.js1 = state.js1 - 1;
          state.totalValue[28] = "${state.js1}/${state.js2}";
          _getStatisticalAreasData(JiShuQiState.tempIndexCmdKeep, isShowLoading: false);
          _reloadLuZiTu();
          update();
        },
        failed: (_, __) {},
        onModel: (m) => JsqBetRecordModel.fromJson(m));
  }

  void updateLists(int index) {
    dismissKeyboard();
    BXLoading.show();
    BXPost(
      Api.xiaoShu,
      isShowLoading: false,
      params: state.betRecordList[index].toJson()..update("shuyingzhi_xiaoshu", (value) => null),
      success: (isSuccess, code, message, results) {
        if (isSuccess) {
          state.betRecordList[index].shuyingzhiXiaoshu = null;
          Future.delayed(const Duration(milliseconds: 500), () {
            BXLoading.dismiss();
            update();
          });
        } else {
          BXLoading.dismiss();
        }
      },
      failed: (_, __) => BXLoading.dismiss(),
    );
  }

  /// 重启前从统计区取 2/6/14/18 拼接快照（须在调用 restart 接口之前），
  /// 其中 index 18 四舍五入保留 1 位小数。
  String _buildRestartStatSnapshot() {
    const indices = [2, 6, 14, 18];
    return indices.map((i) {
      if (i >= state.totalValue.length) return '';
      final raw = MyCharacter.removeChineseCharacters(state.totalValue[i].toString()).trim();
      if (i != 18) return raw;
      final v = double.tryParse(raw);
      return v == null ? raw : v.toStringAsFixed(1);
    }).join('/');
  }

  /// 当前回合是否无数据（看统计区「回合局数」totalValue[2]）
  bool _isRoundStatsEmpty() {
    if (state.totalValue.length <= 2) return true;
    final raw = MyCharacter.removeChineseCharacters(state.totalValue[2].toString()).trim();
    if (raw.isEmpty || raw == '-' || raw == '0') return true;
    final count = int.tryParse(raw);
    return count == null || count <= 0;
  }

  void _saveLastRowRestartStatSnapshot(
    String snapshot, {
    required VoidCallback onDone,
    VoidCallback? onFail,
  }) {
    if (state.betRecordList.isEmpty) {
      onFail?.call();
      return;
    }
    if (snapshot.isEmpty) {
      onDone();
      return;
    }
    BXPut<dynamic>(
      Api.updateLastRowRestartStatSnapshot,
      isShowLoading: false,
      showError: false,
      params: {'restartStatSnapshot': snapshot},
      success: (isSuccess, code, message, results) {
        if (isSuccess) {
          if (state.betRecordList.isNotEmpty) {
            state.betRecordList.last.restartStatSnapshot = snapshot;
          }
          onDone();
        } else {
          BXLoading.showToast(message.isNotEmpty ? message : '保存重启快照失败');
          onFail?.call();
        }
      },
      failed: (_, __) => onFail?.call(),
    );
  }

  void _callRestartApi(String snapshot) {
    if (state.betRecordList.isEmpty) {
      BXLoading.dismiss();
      return;
    }
    BXPost<JsqOperationRecordModel>(
      Api.restart,
      isShowLoading: false,
      params: {"index": state.betRecordList.last.id},
      success: (isSuccess, code, message, value) {
        BXLoading.dismiss();
        if (isSuccess) {
          state.operationRecordList = value;
          state.betRecordList = state.betRecordList.map((element) => element..shuyingzhiXiaoshu = null).toList();
          if (snapshot.isNotEmpty && state.betRecordList.isNotEmpty) {
            state.betRecordList.last.restartStatSnapshot = snapshot;
          }
          state.currentTempIndex = 0;
          _getStatisticalAreasData(JiShuQiState.tempIndexCmdReset);
          update();
        } else {
          BXLoading.showToast(message.isNotEmpty ? message : '重启失败');
        }
      },
      failed: (_, __) => BXLoading.dismiss(),
      onModel: (m) => JsqOperationRecordModel.fromJson(m),
    );
  }

  //重启局部数据
  void reStart() {
    dismissKeyboard();
    Get.defaultDialog(
      barrierDismissible: false,
      backgroundColor: state.isDarkMode ? const Color(0xFF1E2A3A) : Colors.white,
      title: '警告',
      content: Text(
        '是否重启局部数据',
        style: TextStyle(color: state.isDarkMode ? state.darkTextColor : Colors.black),
      ),
      titleStyle: TextStyle(color: state.isDarkMode ? state.darkTextColor : Colors.black),
      contentPadding: const EdgeInsets.all(20),
      onCancel: () {},
      onConfirm: () {
        Get.back();
        if (state.betRecordList.isEmpty) {
          BXLoading.showToast('暂无投注记录，无法重启');
          return;
        }
        if (_isRoundStatsEmpty()) {
          BXLoading.showToast('回合数据为空，无需重启');
          return;
        }
        BXLoading.show(douyinStyle: true);
        final snapshot = _buildRestartStatSnapshot();
        if (snapshot.isNotEmpty) {
          state.betRecordList.last.restartStatSnapshot = snapshot;
          update();
        }
        _saveLastRowRestartStatSnapshot(
          snapshot,
          onDone: () => _callRestartApi(snapshot),
          onFail: BXLoading.dismiss,
        );
      },
    );
  }

  void updateBenJin(String b) {
    BXPost<JsqOperationRecordModel>(
      Api.updateBenjin,
      params: {"benjin": b},
      isShowLoading: false,
      success: (isSuccess, code, message, value) {
        BXLoading.dismiss();
        if (isSuccess) {
          BXLoading.showToast("${value.last.benjin}");
          state.totalValue[0] = b;
          state.totalValue[4] = (double.parse(state.totalValue[0]) + double.parse(state.totalValue[17])).toString();
          _getStatisticalAreasData(JiShuQiState.tempIndexCmdKeep);
        }
      },
      failed: (_, __) => BXLoading.dismiss(),
      onModel: (m) => JsqOperationRecordModel.fromJson(m),
    );
  }

  void updateOdds(String b) {
    BXPost/*<Map<String,dynamic>>*/(Api.updateOdds,
        params: {"odds": b},
        isShowLoading: false,
        success: (isSuccess, int code, String message, List<dynamic> results) {
          BXLoading.dismiss();
          if (isSuccess) {
            BXLoading.showToast(message);
            debugPrint("赔率值是=${(results[0]["odds"])}");
            state.totalValue[31] = (results[0]["odds"]).toString();
            _getStatisticalAreasData(JiShuQiState.tempIndexCmdKeep); //和recordButton里面传一样的参数，确保不会破坏局部平衡
          }
        },
        failed: (_, __) => BXLoading.dismiss());
  }

  //底部选项
  Future<void> functionConfirm(int i) async {
    var s = textEditingController.text.toString();
    switch (i) {
      case 0: //排列数据
        sort();
        break;
      case 1: //清除数据（消数列数据全部清除）
        int count = 0;
        for (var _ in state.betRecordList) {
          state.betRecordList[count].shuyingzhiXiaoshu = null;
          update();
          count++;
        }
        BXPost<dynamic>(
          Api.cleanDataD,
          params: {"uid": GetStore.getInstance().userModel.userId},
          success: (isSuccess, code, message, results) {
            if (isSuccess && results.isNotEmpty) {
              debugPrint("清除一共多少${results.first}条数据");
            }
          },
        );
        break;
      case 2: //修改本金
        BXLoading.show(douyinStyle: true);
        if (s.isEmpty) {
          BXLoading.dismiss();
          BXLoading.showToast('请输入金额 ${textEditingController.text} ');
          break;
        }
        if (!s.isNum) {
          BXLoading.dismiss();
          BXLoading.showToast('请输入数字 ${textEditingController.text} ');
          break;
        }
        updateBenJin(s);
        break;
      case 3: //修改位置
        BXLoading.show(douyinStyle: true);
        state.js2 = state.js1;
        state.totalValue[28] = "${state.js1}/${state.js2}";
        BXLoading.dismiss();
        break;
      case 4: //删除全部数据（当前用户下）
        Get.defaultDialog(
          barrierDismissible: false,
          backgroundColor: state.isDarkMode ? const Color(0xFF1E2A3A) : Colors.white,
          title: '警告',
          content: Text(
            '是否删除全部数据',
            style: TextStyle(color: state.isDarkMode ? state.darkTextColor : Colors.black),
          ),
          titleStyle: TextStyle(color: state.isDarkMode ? state.darkTextColor : Colors.black),
          contentPadding: const EdgeInsets.all(20),
          onCancel: () {},
          onConfirm: () {
            Get.back();
            BXDelete(Api.deleteAll, success: (isSuccess, code, message, results) {
              if (isSuccess) {
                BXLoading.showToast(message);
                state.operationRecordList.clear();
                state.betRecordList.clear();
                state.randomValue = '';
                List.generate(32, (index) => state.totalValue[index] = index.toString());
                _getStatisticalAreasData(JiShuQiState.tempIndexCmdReset, isShowLoading: false);
              }
            });
          },
        );
        break;
      case 5: //重置流水
        if (state.betRecordList.isEmpty) {
          BXLoading.showToast('暂无投注记录');
          break;
        }
        BXPost(
          Api.resetLiuShui,
          params: {"resetIndex": state.betRecordList.last.id},
          success: (bool isSuccess, int code, String message, List<dynamic> results) {},
        );
        break;
      case 6: //备份数据
        BXLoading.show(douyinStyle: true);
        BXPost(
          Api.backupManual,
          isShowLoading: false,
          success: (isSuccess, code, message, results) {
            debugPrint('=====备份完成===== ${results.first}');
            BXLoading.dismiss();
            if (isSuccess) {
              Get.snackbar(
                '备份成功',
                '数据库备份已完成',
                snackPosition: SnackPosition.TOP,
                backgroundColor: Colors.green,
                colorText: Colors.white,
                duration: const Duration(seconds: 3),
              );
            } else {
              Get.snackbar(
                '备份失败',
                message,
                snackPosition: SnackPosition.TOP,
                backgroundColor: Colors.red,
                colorText: Colors.white,
                duration: const Duration(seconds: 3),
              );
            }
          },
          failed: (error, model) {
            BXLoading.dismiss();
            Get.snackbar(
              '备份失败',
              '网络错误：$error',
              snackPosition: SnackPosition.TOP,
              backgroundColor: Colors.red,
              colorText: Colors.white,
              duration: const Duration(seconds: 3),
            );
          },
        );
        break;
      case 7: //返回上步
        deleteLast();
        break;
      case 8: //修改期望值
        if (s.isEmpty) {
          BXLoading.showToast('请输入期望值 ${textEditingController.text} ');
          break;
        }
        if (!s.isNum) {
          BXLoading.showToast('请输入数字 ${textEditingController.text} ');
          break;
        }
        updateQiWangZhi(s);
        break;
      case 9: //修改赔率
        BXLoading.show(douyinStyle: true);
        if (s.isEmpty) {
          BXLoading.dismiss();
          BXLoading.showToast('请输入赔率 ${textEditingController.text} ');
          break;
        }
        if (!s.isNum) {
          BXLoading.dismiss();
          BXLoading.showToast('请输入赔率 ${textEditingController.text} ');
          break;
        }
        updateOdds(s);
        break;
      case 10: //退出程序
        await GetStore.getInstance().logout();
        ApiSessionHandler.goLogin(clearStack: false);
        break;
      case 11: //隐藏/显示序号
        state.isSeqVisible = !state.isSeqVisible;
        state.selectIndex = 11;
        update();
        break;
      case 12: //红输绿赢 / 红赢绿输
        state.isRedWinGreenLose = !state.isRedWinGreenLose;
        state.selectIndex = 12;
        update();
        break;
    }
  }

  sort() {
    dismissKeyboard();
    BXLoading.show(douyinStyle: true);
    BXPost(
      Api.sortXiaoShu,
      isShowLoading: false,
      success: (isSuccess, code, message, results) {
        BXLoading.dismiss();
        if (isSuccess) {
          var list = (results.first as Map<String, dynamic>)["sorted_sequence"];
          final n = state.betRecordList.length;
          final m = list.length;
          for (int i = 0; i < n; i++) {
            final idx = m - n + i;
            if (idx < 0 || idx >= m) {
              state.betRecordList[i].shuyingzhiXiaoshu = null;
              continue;
            }
            state.betRecordList[i].shuyingzhiXiaoshu = double.tryParse(list[idx].toString());
          }
          update();
        }
      },
      failed: (_, __) => BXLoading.dismiss(),
    );
  }

  void updateQiWangZhi(String qiwangzhi) {
    BXPost/*<Map<String,dynamic>>*/(Api.updateQiWangValue, params: {"mean": qiwangzhi}, isShowLoading: false,
        success: (isSuccess, int code, String message, List<dynamic> results) {
      if (isSuccess) {
        BXLoading.showToast(message);
        debugPrint("期望值是=${(results[0]["mean"])}");
        state.totalValue[19] = (results[0]["mean"]).toString();
        // 修改期望值后，重新刷新统计区数据，保持界面数据和后台一致
        _getStatisticalAreasData(JiShuQiState.tempIndexCmdKeep);
      }
    });
  }

  lockScreen() {
    _timer?.cancel();
    _timer = null;
    screenLock(
      config: const ScreenLockConfig(
        backgroundColor: Colors.black,
      ),
      onValidate: (input) => getFuture(input),
      secretsConfig: const SecretsConfig(
        spacing: 15, // or spacingRatio
        padding: EdgeInsets.all(40),
        //输入密码框的配置
        // secretConfig: SecretConfig(
        //   borderColor: Colors.red,
        //   borderSize: 1.0,
        //   disabledColor: Colors.black,
        //   enabledColor: Colors.red,
        // ),
      ),
      title: const Icon(Icons.lock, size: 30, color: Colors.white),
      context: Get.context!,
      correctString: '1234',
      canCancel: false,
      //是否可以取消
      onUnlocked: () {
        Get.back();
        onUserInteraction();
      },
    );
  }

  void onUserInteraction() {
    cancelPendingBettingListAutoScroll();
    // 取消之前的计时器
    _timer?.cancel();
    // 设置新的计时器，时间设置为你想要的锁屏延时时间
    _timer = Timer(Duration(seconds: 60 * state.LockScreenTime), () {
      lockScreen();
    });
  }

  getFuture(String input) => Future.delayed(const Duration(milliseconds: 200), () {
        if (input.length == 4 && input == "0000") {
          return true;
        } else {
          BXLoading.showError(toast: '密码错误');
          return false;
        }
      });

  /// 切换暗黑主题
  void toggleDarkMode() {
    dismissKeyboard();
    state.isDarkMode = !state.isDarkMode;
    BXLoading.syncTheme(state.isDarkMode);
    update();
  }

  /// 切换图表显示/隐藏
  void toggleChartVisibility() {
    dismissKeyboard();
    state.isChartVisible = !state.isChartVisible;
    update();
  }

  Future<String?> getDeviceId() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String? deviceId;

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      // deviceId = androidInfo.board;
      // deviceId = androidInfo.hardware;//mt6762
      // deviceId = androidInfo.product;//dandelion
      // deviceId = androidInfo.tags;//release-keys
      deviceId = androidInfo.device; //release-keys
      debugPrint(androidInfo.data.toString());
      deviceId = androidInfo.device; //release-keys
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      // iOS没有设备ID的概念，但可以使用idfv来获取用户标识符
      deviceId = iosInfo.identifierForVendor;
    }

    return deviceId;
  }

  //(取消)局部平衡
  juBuPingHeng(Object index, {v}) {
    guardAgainstKeyboardPop();
    final targetIndex = index != JiShuQiState.tempIndexCmdCancel && state.currentTempIndex == index
        ? JiShuQiState.tempIndexCmdCancel
        : index;

    // 取消指令：取消局部平衡
    if (targetIndex == JiShuQiState.tempIndexCmdCancel) {
      if (state.currentTempIndex == 0) {
        return;
      }
      state.currentTempIndex = 0;
    } else if (_isEffectiveLocalTempIndex(targetIndex)) {
      state.currentTempIndex = targetIndex as int;
    }
    update();
    if (state.betRecordList.isNotEmpty) _getStatisticalAreasData(targetIndex);
  }

  //统计区的下拉刷新（网络错误 Toast 由 HttpService 统一处理）
  Future<void> refreshStatsArea() async {
    state.isRefreshing = true;
    update();
    var success = true;
    try {
      await _queryOperationRecords(isShowLoading: false);
      await _getStatisticalAreasData(JiShuQiState.tempIndexCmdKeep, isShowLoading: false);
      await _reloadBettingListTail(isShowLoading: false);
    } catch (_) {
      success = false;
    } finally {
      state.isRefreshing = false;
      update();
      statsRefreshController.finishRefresh(
        success ? IndicatorResult.success : IndicatorResult.fail,
        true,
      );
    }
  }

  //下拉刷新
  void onRefresh() {
    refreshStatsArea();
  }

  //加载更多
  Future<int> onLoadMore({
    int count = 250,
    bool preserveViewport = true,
  }) {
    final completer = Completer<int>();
    // id 为 null 时 Dio 会发出 last_id= 无值，后端会走错分支；空列表用 -1。
    // 与后端 LoadMore 一致：数据为 created_at 升序，分页游标为当前已加载中最旧一条（first）的 id。
    final anchorId = state.betRecordList.isEmpty ? -1 : (state.betRecordList.first.id ?? -1);
    BXGet<JsqBetRecordModel>(Api.loadMore,
        params: {"last_id": anchorId, "uid": GetStore.getInstance().userModel.userId, "c": count}, //"c"每页多少个数据
        success: (isSuccess, code, message, results) {
          if (!isSuccess) {
            refreshcontroller.finishRefresh(IndicatorResult.fail, true);
            if (!completer.isCompleted) completer.complete(0);
            return;
          }

          if (results.isEmpty) {
            if (state.betRecordList.isEmpty) {
              update();
            }
            refreshcontroller.finishRefresh(IndicatorResult.noMore, true);
            if (!completer.isCompleted) completer.complete(0);
            return;
          }

          if (results.isNotEmpty) {
            double? keptPixels;
            if (scrollController.hasClients) {
              keptPixels = scrollController.position.pixels;
            }
            state.betRecordList.insertAll(0, results);
            if (!state.isBigRoad) {
              _getLineCharts(applyStatsTail: true);
            }
            update();
            refreshcontroller.finishRefresh(IndicatorResult.success, true);
            if (preserveViewport && keptPixels != null) {
              _schedulePreserveScrollAfterPrepend(keptPixels, results.length);
            }
          }
          if (!completer.isCompleted) completer.complete(results.length);
        },
        failed: (_, __) {
          refreshcontroller.finishRefresh(IndicatorResult.fail, true);
          if (!completer.isCompleted) completer.complete(0);
        },
        onModel: (m) => JsqBetRecordModel.fromJson(m));
    return completer.future;
  }

  changeChart() {
    dismissKeyboard();
    _reloadLuZiTu();
    state.isBigRoad = !state.isBigRoad;
    if (!state.isBigRoad) {
      _getLineCharts(applyStatsTail: true);
    }
    update();
    // 切到大路子图时组件本帧才挂上 Scrollable，须在 update 之后再调度一次滚动。
    if (state.isBigRoad) {
      _scheduleRoadMapScrollAfterRebuild();
    }
  }

  //重新加载路子图
  _reloadLuZiTu() {
    var list = state.betRecordList.map((e) => (e.shuyingzhi ?? 0) < 0 ? "闲家" : "庄家").toList();
    state.initializeBigRoad();
    for (var value in list) {
      updateBigRoad(value);
    }
    _scheduleRoadMapScrollAfterRebuild();
  }
}
