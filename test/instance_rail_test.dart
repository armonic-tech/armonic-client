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

  /// Only Beta has a logo, so one tile paints an image and the other keeps
  /// its initials in the same pump.
  Future<InstanceInfo> infoWithLogo(String baseUrl) async => InstanceInfo(
    id: baseUrl,
    name: baseUrl,
    description: '',
    memberCount: 3,
    host: baseUrl,
    claimed: true,
    logoThumbPath: baseUrl == 'http://b:4000'
        ? '/server/s1/logo/thumb?v=att-1'
        : '',
  );

  Future<void> pumpRail(
    WidgetTester tester, {
    ValueChanged<StoredInstance>? onSelect,
    ValueChanged<StoredInstance>? onRemove,
    VoidCallback? onAdd,
    ValueChanged<StoredInstance>? onCreateInvite,
    ValueChanged<StoredInstance>? onChangeLogo,
    ValueChanged<StoredInstance>? onRemoveLogo,
    LiveLogo Function(String baseUrl)? logoOf,
    bool Function(String baseUrl)? canInvite,
    Future<InstanceInfo> Function(String baseUrl)? fetchInfo,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InstanceRail(
            instances: instances,
            selectedUrl: instances.first.baseUrl,
            onSelect: onSelect ?? (_) {},
            onRemove: onRemove ?? (_) {},
            onAdd: onAdd ?? () {},
            onCreateInvite: onCreateInvite,
            onChangeLogo: onChangeLogo,
            onRemoveLogo: onRemoveLogo,
            logoOf: logoOf,
            canInvite: canInvite,
            fetchInfo: fetchInfo ?? info,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one square per stored instance, plus the add square', (
    tester,
  ) async {
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

  Future<void> rightClick(WidgetTester tester, String initials) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(tester.getCenter(find.text(initials)));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('right-click removes an instance from the list', (tester) async {
    StoredInstance? removed;
    await pumpRail(tester, onRemove: (i) => removed = i);

    await rightClick(tester, 'BE');

    await tester.tap(find.text(strings.removeFromList));
    await tester.pumpAndSettle();
    expect(removed?.baseUrl, 'http://b:4000');
  });

  testWidgets('an admin can mint an invite straight from the rail', (
    tester,
  ) async {
    StoredInstance? invited;
    await pumpRail(
      tester,
      canInvite: (baseUrl) => baseUrl == 'http://b:4000',
      onCreateInvite: (i) => invited = i,
    );

    await rightClick(tester, 'BE');
    await tester.tap(find.text(strings.createInvite));
    await tester.pumpAndSettle();

    expect(invited?.baseUrl, 'http://b:4000');
  });

  testWidgets('no invite entry for an instance the user does not administer', (
    tester,
  ) async {
    await pumpRail(
      tester,
      canInvite: (baseUrl) => baseUrl == 'http://b:4000',
      onCreateInvite: (_) {},
    );

    await rightClick(tester, 'AR');

    expect(find.text(strings.createInvite), findsNothing);
    expect(find.text(strings.removeFromList), findsOneWidget);
  });

  testWidgets('a tile paints the logo its instance advertises, initials '
      'otherwise', (tester) async {
    await pumpRail(tester, fetchInfo: infoWithLogo);

    // The request itself fails under test, which is the fallback path: the
    // tile with a logo still holds an Image, the one without never builds one.
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('AR'), findsOneWidget);
  });

  testWidgets('removing the logo is offered only while there is one', (
    tester,
  ) async {
    StoredInstance? cleared;
    await pumpRail(
      tester,
      canInvite: (_) => true,
      onRemoveLogo: (i) => cleared = i,
      logoOf: (baseUrl) => LiveLogo(
        known: true,
        path: baseUrl == 'http://b:4000'
            ? '/server/s1/logo/thumb?v=att-1'
            : null,
      ),
    );

    await rightClick(tester, 'AR');
    expect(find.text(strings.removeServerLogo), findsNothing);
    await tester.tap(find.text(strings.removeFromList).last);
    await tester.pumpAndSettle();

    await rightClick(tester, 'BE');
    await tester.tap(find.text(strings.removeServerLogo));
    await tester.pumpAndSettle();
    expect(cleared?.baseUrl, 'http://b:4000');
  });

  // The removal case: GET /info was fetched while the logo still existed, so
  // the tile must not fall back to it. This is what kept the old logo on
  // screen until something else rebuilt the rail.
  testWidgets('a session that says "no logo" outranks a stale /info', (
    tester,
  ) async {
    await pumpRail(
      tester,
      fetchInfo: infoWithLogo,
      logoOf: (_) => const LiveLogo(known: true),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('BE'), findsOneWidget);
  });

  testWidgets('a live session repaints without waiting for /info', (
    tester,
  ) async {
    // /info never advertises a logo here, so the only source is the session.
    await pumpRail(
      tester,
      logoOf: (baseUrl) => LiveLogo(
        known: true,
        path: baseUrl == 'http://b:4000'
            ? '/server/s1/logo/thumb?v=att-1'
            : null,
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('AR'), findsOneWidget);
  });

  testWidgets('an instance with no session falls back to /info', (
    tester,
  ) async {
    await pumpRail(
      tester,
      fetchInfo: infoWithLogo,
      logoOf: (_) => const LiveLogo(known: false),
    );

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('an admin can change the logo straight from the rail', (
    tester,
  ) async {
    StoredInstance? asked;
    await pumpRail(
      tester,
      canInvite: (baseUrl) => baseUrl == 'http://b:4000',
      onChangeLogo: (i) => asked = i,
    );

    await rightClick(tester, 'BE');
    await tester.tap(find.text(strings.changeServerLogo));
    await tester.pumpAndSettle();

    expect(asked?.baseUrl, 'http://b:4000');
  });
}
