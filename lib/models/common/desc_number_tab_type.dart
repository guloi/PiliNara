import 'package:PiliPlus/models/common/enum_with_label.dart';

enum DescNumberType implements EnumWithLabel {
  bv('bv', 'bv'),
  av('av', 'av');

  static const List<DescNumberType> kDefault = [.bv, .av];

  /// 简介里用的短前缀 / 设置页里显示的短名字。
  @override
  final String label;

  /// 设置页与对话框里用的完整名字。
  final String title;

  const DescNumberType(this.label, this.title);
}
