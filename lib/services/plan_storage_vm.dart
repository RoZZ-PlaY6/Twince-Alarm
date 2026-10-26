import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/services/plan_storage_api.dart';

class BridgePlanStorage implements PlanStorage {
  @override
  Future<String?> read() => AlarmBridge.instance.loadPlanLibrary();

  @override
  Future<void> write(String value) =>
      AlarmBridge.instance.savePlanLibrary(value);
}

PlanStorage createPlanStorage() => BridgePlanStorage();
