// Lightweight widget smoke tests for the recruiter design-system widgets.
// (Replaces the stock `flutter create` counter test, which targeted a counter
// UI this app never had.) These render plugin-free widgets so they stay fast
// and deterministic in CI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('RecruiterPageHeader renders its title, kicker and action',
      (tester) async {
    await tester.pumpWidget(_host(const RecruiterPageHeader(
      kicker: 'AI Interview',
      title: 'Sessions',
      subtitle: 'Create and review candidate interviews.',
      action: Icon(Icons.add),
    )));

    expect(find.text('AI INTERVIEW'), findsOneWidget); // kicker upper-cased
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('RecruiterEmptyState renders title + description', (tester) async {
    await tester.pumpWidget(_host(const RecruiterEmptyState(
      icon: Icons.mic_none,
      title: 'No sessions yet',
      description: 'Create a session to run an interview on this device.',
    )));

    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('RecruiterBadge renders its label', (tester) async {
    await tester.pumpWidget(
        _host(const RecruiterBadge(text: 'Completed', color: Colors.green)));
    expect(find.text('Completed'), findsOneWidget);
  });
}
