import 'package:flutter/material.dart';

class MoreFunctionsDialog extends StatelessWidget {
  const MoreFunctionsDialog({
    super.key,
    required this.isDarkMode,
    required this.functionTypes,
    required this.onSelected,
  });

  final bool isDarkMode;
  final List<String> functionTypes;
  final ValueChanged<int> onSelected;

  static const _undoIndex = 7;

  // 只调整展示顺序；点击时仍使用原功能索引，确保控制器逻辑不变。
  static const _displayOrder = <int>[
    _undoIndex,
    0,
    1,
    2,
    3,
    5,
    6,
    8,
    9,
    11,
    12,
    4,
    10,
  ];

  static const _icons = <IconData>[
    Icons.sort_rounded,
    Icons.cleaning_services_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.my_location_rounded,
    Icons.delete_outline_rounded,
    Icons.restart_alt_rounded,
    Icons.backup_outlined,
    Icons.undo_rounded,
    Icons.track_changes_outlined,
    Icons.percent_rounded,
    Icons.logout_rounded,
    Icons.format_list_numbered_rounded,
    Icons.swap_horiz_rounded,
  ];

  static const _descriptions = <String>[
    '按当前规则重新排列投注数据',
    '清除消数列中的全部数据',
    '使用输入框中的金额修改本金',
    '将当前随机位置设为参考位置',
    '删除当前账号的全部数据，不可恢复',
    '从最后一条投注记录重置流水',
    '立即备份当前数据库',
    '撤销最后一条投注记录',
    '使用输入框中的数值修改期望值',
    '使用输入框中的数值修改赔率',
    '退出当前账号并返回登录页',
    '显示或隐藏投注记录序号',
    '切换红色与绿色的输赢含义',
  ];

  static const _accentColors = <Color>[
    Color(0xFF2CB7CF),
    Color(0xFF38B8AA),
    Color(0xFF478BE6),
    Color(0xFF6677D9),
    Color(0xFFEF7C32),
    Color(0xFFE1A72C),
    Color(0xFF2CB7CF),
    Color(0xFF38B8AA),
    Color(0xFF8B74D6),
    Color(0xFFE1A72C),
    Color(0xFFE35D5D),
    Color(0xFF478BE6),
    Color(0xFF38B8AA),
  ];

  String _displayTitle(String value) {
    return value.replaceFirst(RegExp(r'^\d+\.'), '');
  }

  Color _tileColor(int index, Color accentColor) {
    if (isDarkMode) {
      final opacity = index == 4 || index == 10 ? 0.16 : 0.10;
      return Color.alphaBlend(
        accentColor.withValues(alpha: opacity),
        const Color(0xFF1C2837),
      );
    }

    if (index == 4 || index == 10) return const Color(0xFFFFF4EE);
    if (index == 5 || index == 9) return const Color(0xFFFFFAEC);
    if (index == 0 || index == 2 || index == 6 || index == 11) {
      return const Color(0xFFF1F6FF);
    }
    return const Color(0xFFF6F8FC);
  }

  @override
  Widget build(BuildContext context) {
    final orderedIndexes = <int>[
      ..._displayOrder.where((index) => index < functionTypes.length),
      ...List.generate(functionTypes.length, (index) => index)
          .where((index) => !_displayOrder.contains(index)),
    ];
    final screenHeight = MediaQuery.sizeOf(context).height;
    final dialogHeight =
        screenHeight * 0.84 < 760.0 ? screenHeight * 0.84 : 760.0;
    final surfaceColor = isDarkMode ? const Color(0xFF16212F) : Colors.white;
    final primaryTextColor =
        isDarkMode ? const Color(0xFFF5F7FA) : const Color(0xFF202A3A);
    final secondaryTextColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.58)
        : const Color(0xFF7A8494);
    final dividerColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE8EDF3);

    return Dialog(
      key: const ValueKey('more-functions-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      elevation: 20,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          height: dialogHeight,
          child: Material(
            key: const ValueKey('more-functions-surface'),
            color: surfaceColor,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '更多功能',
                          style: TextStyle(
                            color: primaryTextColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('more-functions-close'),
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: secondaryTextColor,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: dividerColor),
                Expanded(
                  child: Scrollbar(
                    child: ListView.separated(
                      key: const ValueKey('more-functions-list'),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                      itemCount: orderedIndexes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, position) {
                        final actionIndex = orderedIndexes[position];
                        final accentColor = actionIndex < _accentColors.length
                            ? _accentColors[actionIndex]
                            : const Color(0xFF2CB7CF);
                        final icon = actionIndex < _icons.length
                            ? _icons[actionIndex]
                            : Icons.tune_rounded;
                        final description = actionIndex < _descriptions.length
                            ? _descriptions[actionIndex]
                            : '执行该功能';
                        final title = _displayTitle(functionTypes[actionIndex]);

                        return Material(
                          key: ValueKey('more-function-$actionIndex'),
                          color: _tileColor(actionIndex, accentColor),
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              onSelected(actionIndex);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: accentColor.withValues(
                                          alpha: isDarkMode ? 0.16 : 0.11),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(icon,
                                        color: accentColor, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: actionIndex == 4
                                                ? accentColor
                                                : primaryTextColor,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: secondaryTextColor,
                                            fontSize: 11,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
