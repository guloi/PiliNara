import 'package:PiliPlus/models/common/enum_with_label.dart';

enum LogLevelType implements EnumWithLabel {
  v('v'),
  info('info'),
  warn('warn'),
  error('error'),
  debug('debug'),
  trace('trace'),
  ;

  @override
  final String label;
  const LogLevelType(this.label);
}