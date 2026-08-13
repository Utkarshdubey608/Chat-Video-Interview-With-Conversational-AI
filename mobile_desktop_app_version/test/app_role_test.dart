// Role-safety regression test.
//
// AuthGate's entire recruiter/candidate routing decision boils down to one
// question: what does AppRoleX.fromWire return? RecruiterShell is only ever
// reachable when this resolves to AppRole.recruiter, so the one property that
// must never break is: an unrecognized/missing role can NEVER resolve to
// recruiter — it must fail closed to the least-privileged role (candidate).
// Full AuthGate/RecruiterShell/CandidateShell integration tests would need
// Firebase test scaffolding this suite doesn't have yet (FirebaseAuth.instance
// is read directly inside several widgets they host) — this test covers the
// pure decision function that drives the routing instead.

import 'package:flutter_test/flutter_test.dart';
import 'package:talbotiq/features/auth/app_role.dart';

void main() {
  group('AppRoleX.fromWire', () {
    test('the exact stored recruiter value resolves to recruiter', () {
      expect(AppRoleX.fromWire('recruiter'), AppRole.recruiter);
    });

    test('the exact stored candidate value resolves to candidate', () {
      expect(AppRoleX.fromWire('candidate'), AppRole.candidate);
    });

    test('a missing role (no users/{uid} doc yet) fails closed to candidate', () {
      expect(AppRoleX.fromWire(null), AppRole.candidate);
    });

    test('garbage/unexpected wire values fail closed to candidate, never recruiter', () {
      for (final bad in ['', 'Recruiter', 'RECRUITER', 'admin', 'recruiter ', 'null']) {
        expect(AppRoleX.fromWire(bad), AppRole.candidate,
            reason: 'wire value "$bad" must not grant recruiter access');
      }
    });
  });

  group('AppRoleX.wire / label round-trip', () {
    test('recruiter round-trips through its wire value', () {
      expect(AppRoleX.fromWire(AppRole.recruiter.wire), AppRole.recruiter);
    });

    test('candidate round-trips through its wire value', () {
      expect(AppRoleX.fromWire(AppRole.candidate.wire), AppRole.candidate);
    });

    test('labels are human-readable and distinct', () {
      expect(AppRole.recruiter.label, 'Recruiter');
      expect(AppRole.candidate.label, 'Candidate');
    });
  });
}
