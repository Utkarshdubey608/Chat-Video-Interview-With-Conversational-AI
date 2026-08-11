// test/recruiter_action_bar_test.dart
//
// The labelled action bar that replaced the recruiter screens' icon-only app bar
// actions. Testable because it has no Firebase in its path, and worth testing
// because two of the actions it carries (publish results, delete test) are
// irreversible — so "is it labelled", "is it disabled when unavailable" and "is
// the destructive one distinguishable" are behavioural, not cosmetic.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talbotiq/features/interviews/recruiter/widgets/recruiter_action_bar.dart';

Future<void> _pump(WidgetTester tester, List<RecruiterAction> actions) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RecruiterActionBar(actions: actions)),
    ));

void main() {
  testWidgets('every action shows its label, not just an icon', (t) async {
    await _pump(t, [
      RecruiterAction(
          label: 'Leaderboard',
          icon: Icons.leaderboard_outlined,
          onPressed: () {}),
      RecruiterAction(
          label: 'Publish results',
          icon: Icons.publish_outlined,
          onPressed: () {}),
    ]);

    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Publish results'), findsOneWidget);
    expect(find.byIcon(Icons.leaderboard_outlined), findsOneWidget);
  });

  testWidgets('tapping a label runs the action', (t) async {
    var taps = 0;
    await _pump(t, [
      RecruiterAction(
          label: 'Retry failed scoring',
          icon: Icons.autorenew,
          onPressed: () => taps++),
    ]);

    await t.tap(find.text('Retry failed scoring'));
    expect(taps, 1);
  });

  testWidgets('a null onPressed leaves the action visible but inert', (t) async {
    // Visible-but-disabled rather than hidden: a recruiter should be able to see
    // that "Retry failed scoring" exists and is simply not available yet, instead
    // of wondering where it went.
    await _pump(t, const [
      RecruiterAction(
          label: 'Retry failed scoring',
          icon: Icons.autorenew,
          onPressed: null),
    ]);

    expect(find.text('Retry failed scoring'), findsOneWidget);
    final inkWell = t.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onTap, isNull);
  });

  testWidgets('a destructive action is coloured differently from a normal one',
      (t) async {
    await _pump(t, [
      RecruiterAction(
          label: 'Publish results',
          icon: Icons.publish_outlined,
          onPressed: () {}),
      RecruiterAction(
          label: 'Delete test',
          icon: Icons.delete_forever_outlined,
          onPressed: () {},
          destructive: true),
    ]);

    Color labelColour(String text) =>
        t.widget<Text>(find.text(text)).style!.color!;

    // The delete button must not look like the button next to it.
    expect(labelColour('Delete test'),
        isNot(equals(labelColour('Publish results'))));

    final scheme = Theme.of(t.element(find.text('Delete test'))).colorScheme;
    expect(labelColour('Delete test'), scheme.error);
    expect(labelColour('Publish results'), scheme.primary);
  });

  testWidgets('an empty action list renders nothing at all', (t) async {
    await _pump(t, const []);
    // Not an empty bordered container floating above the list.
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('actions reflow instead of overflowing on a narrow screen',
      (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await _pump(t, [
      for (final label in [
        'Leaderboard',
        'Rounds & schedule',
        'Retry failed scoring',
        'Publish results',
        'Delete test',
      ])
        RecruiterAction(label: label, icon: Icons.circle, onPressed: () {}),
    ]);

    // A Row would have thrown a RenderFlex overflow here; a Wrap lays the
    // buttons onto more lines instead.
    expect(t.takeException(), isNull);
    expect(find.text('Delete test'), findsOneWidget);
  });
}
