import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';
import 'driver_extension.dart';

void main() {
  group("One punch test group", () {
    late FlutterDriver driver;

    setUp(() async {
      driver = await initAndroidFlutterDriver();
    });

    test("One punch test", () async {
      await driver.tap(find.byType('FloatingActionButton'));
    });
  });
}
