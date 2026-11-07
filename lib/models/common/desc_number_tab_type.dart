import 'package:PiliPlus/models/common/enum_with_label.dart';

/// 视频简介里可以显示的视频号。
enum DescNumberType implements EnumWithLabel {
  /// bv 号（`BV1xx411c7mD` 这种）。
  bv('bv', 'bv 号'),

  /// av 号（`av170001` 这种）。
  av('av', 'av 号');

  /// 默认两个都显示，bv 在前。
  static const List<DescNumberType> kDefault = [.bv, .av];

  /// 简介里用的短前缀 / 设置页里显示的短名字。
  @override
  final String label;

  /// 设置页与对话框里用的完整名字。
  final String title;

  const DescNumberType(this.label, this.title);
}
