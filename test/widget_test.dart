import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/main.dart';

void main() {
  testWidgets('home shows the Twince clock dashboard', (tester) async {
    await tester.pumpWidget(const TwinceAlarmApp(connectPlatform: false));
    await tester.pump();

    expect(find.text('TWINCE'), findsOneWidget);
    expect(find.text('Alarms'), findsOneWidget);
    expect(find.text('No alarms yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
