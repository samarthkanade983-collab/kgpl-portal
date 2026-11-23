import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kgpl_portal/views/intern/certificate_view.dart';

Map<String, dynamic> certificateResponse({required bool eligible}) => {
      'eligible': eligible,
      'intern_name': 'Test Intern',
      'intern_code': 'TEST-001',
      'department': 'IT',
      'pending_videos_count': eligible ? 0 : 1,
      'pending_materials_count': 0,
      'pending_tests_count': 0,
      'progress_percent': eligible ? 100 : 50,
      'certificate': {
        'recipient_name': 'Test Intern',
        'intern_code': 'TEST-001',
        'department': 'IT',
        'body_text': 'Completed the assigned training curriculum.',
        'signer_name': 'HR Admin',
        'signer_title': 'HR',
        'organization': 'KGPL',
        'issue_date': '2026-11-19',
        'serial': 'TEST-CERT-001',
      },
    };

void main() {
  Future<void> showCertificate(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: CertificateView())));
    await tester.pumpAndSettle();
  }

  testWidgets('API failure shows retry, not false completion milestones',
      (tester) async {
    var requests = 0;
    await http.runWithClient(() async {
      await showCertificate(tester);
      expect(find.text('Unable to load certificate status'), findsOneWidget);
      expect(find.text('Certificate locked — keep going!'), findsNothing);
      expect(find.text('All course video lessons watched'), findsNothing);
      expect(find.text('All SOP study materials read'), findsNothing);
      expect(find.text('All scheduled MCQ assessments passed'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('Unable to load certificate status'), findsNothing);
      expect(
          find.text(
              'Congratulations! Your course is complete and your certificate is unlocked.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              requests++;
              if (requests == 1) {
                return http.Response(
                    jsonEncode(
                        {'error': 'Failed to verify certificate eligibility'}),
                    500);
              }
              return http.Response(
                  jsonEncode(certificateResponse(eligible: true)), 200);
            }));
  });

  testWidgets('unfinished training remains locked with real pending items',
      (tester) async {
    await http.runWithClient(() async {
      await showCertificate(tester);
      expect(find.text('Certificate locked — keep going!'), findsOneWidget);
      expect(find.text('1 video lesson(s) remaining'), findsOneWidget);
      expect(find.text('50% complete'), findsOneWidget);
      expect(find.text('Unable to load certificate status'), findsNothing);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async => http.Response(
            jsonEncode(certificateResponse(eligible: false)), 200)));
  });
}
