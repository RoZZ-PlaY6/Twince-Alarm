import 'dart:js_interop';

import 'package:twince_alarm/services/plan_storage_api.dart';

@JS('localStorage.getItem')
external JSString? _getPlanItem(JSString key);

@JS('localStorage.setItem')
external void _setPlanItem(JSString key, JSString value);

class _WebPlanStorage implements PlanStorage {
  static const _key = 'twince_alarm_plan_library';

  @override
  Future<String?> read() async => _getPlanItem(_key.toJS)?.toDart;

  @override
  Future<void> write(String value) async {
    _setPlanItem(_key.toJS, value.toJS);
  }
}

PlanStorage createPlanStorage() => _WebPlanStorage();
