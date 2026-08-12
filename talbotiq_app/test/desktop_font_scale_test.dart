// Regression test for the global desktop font-size preference
// (AppStore.desktopFontScale -> main.dart's MediaQuery.textScaler wiring).
//
// Candidate desktop now shares this exact mechanism with recruiter desktop
// (see settings_page.dart's Preferences category, gated on isDesktopPlatform
// for both roles) — this test exercises the same MediaQuery(textScaler:)
// pattern main.dart wires at the MaterialApp root, without needing Firebase,
// to confirm a change to AppStore reaches a deeply-nested widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talbotiq/shared/providers/app_store.dart';

void main() {
  testWidgets('desktopFontScale reaches a deeply nested widget via MediaQuery',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.loadFromPrefs();
    store.setDesktopFontScale(1.5);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: Builder(builder: (context) {
          final scale =
              context.select<AppStore, double>((s) => s.desktopFontScale);
          return MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(body: Text('hello')),
          );
        }),
      ),
    );
    await tester.pump();

    final scaler = MediaQuery.textScalerOf(tester.element(find.text('hello')));
    expect(scaler.scale(10) / 10, closeTo(1.5, 0.001));

    store.setDesktopFontScale(0.9);
    await tester.pump();
    final scaler2 = MediaQuery.textScalerOf(tester.element(find.text('hello')));
    expect(scaler2.scale(10) / 10, closeTo(0.9, 0.001));
  });

  test('desktopFontScale persists across a fresh AppStore load', () async {
    SharedPreferences.setMockInitialValues({});
    final first = AppStore();
    await first.loadFromPrefs();
    first.setDesktopFontScale(1.2);

    final second = AppStore();
    await second.loadFromPrefs();
    expect(second.desktopFontScale, closeTo(1.2, 0.001));
  });
}
