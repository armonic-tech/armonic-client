import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/widgets/instance_rail.dart';

void main() {
  final instances = [
    StoredInstance(baseUrl: 'http://a:4000', name: 'Armonic', token: 't'),
    StoredInstance(baseUrl: 'http://b:4000', name: 'Beta', token: 't'),
  ];

  Future<InstanceInfo> info(String baseUrl) async => InstanceInfo(
        id: baseUrl,
        name: baseUrl,
        description: '',
        memberCount: 3,
        host: baseUrl,
        claimed: true,
      );

  Future<void> pumpRail(
    WidgetTester tester, {
    ValueChanged<StoredInstance>? onSelect,
    ValueChanged<StoredInstance>? onRemove,
    VoidCallback? onAdd,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InstanceRail(
          instances: instances,
          selectedUrl: instances.first.baseUrl,
          onSelect: onSelect ?? (_) {},
          onRemove: onRemove ?? (_) {},
          onAdd: onAdd ?? () {},
          fetchInfo: info,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('one square per stored instance, plus the add square',
      (tester) async {
    await pumpRail(tester);

    expect(find.text('AR'), findsOneWidget);
    expect(find.text('BE'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('tapping a square selects that instance', (tester) async {
    StoredInstance? selected;
    await pumpRail(tester, onSelect: (i) => selected = i);

    await tester.tap(find.text('BE'));
    expect(selected?.baseUrl, 'http://b:4000');
  });

  testWidgets('the add square asks for a new instance', (tester) async {
    var added = false;
    await pumpRail(tester, onAdd: () => added = true);

    await tester.tap(find.byIcon(Icons.add));
    expect(added, isTrue);
  });

  testWidgets('right-click removes an instance from the list', (tester) async {
    StoredInstance? removed;
    await pumpRail(tester, onRemove: (i) => removed = i);

    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await gesture.down(tester.getCenter(find.text('BE')));
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text(strings.removeFromList));
    await tester.pumpAndSettle();
    expect(removed?.baseUrl, 'http://b:4000');
  });
}
