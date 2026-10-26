abstract class PlanStorage {
  Future<String?> read();
  Future<void> write(String value);
}
