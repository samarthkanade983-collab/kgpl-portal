import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kgpl_portal/views/hr/report_analytics_view.dart';

Map<String, dynamic> taskReview(
        {int? score = 9, String comments = 'Good work'}) =>
    {
      'id': 3,
      'source': 'task_submission',
      'intern_id': 82,
      'intern_name': 'Test Intern',
      'department_name': 'HR',
      'team_leader_name': 'Team Leader',
      'task_title': 'Checklist',
      'score': score,
      'max_score': 10,
      'comments': comments,
      'submission_status': 'graded',
      'created_at': '2026-11-19T10:27:44.000Z',
    };

void main() {
  Future<void> showFeedback(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1800, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ReportAnalyticsView())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team Leader Feedback'));
    await tester.pumpAndSettle();
  }

  testWidgets('task scores and comments coexist with general star ratings',
      (tester) async {
    await http.runWithClient(() async {
      await showFeedback(tester);
      expect(find.text('9 / 10 pts'), findsOneWidget);
      expect(find.text('Task: Checklist'), findsOneWidget);
      expect(find.text('Actions'), findsNothing);
      expect(find.byTooltip('Edit intern name'), findsNothing);
      expect(find.text('Good work'), findsOneWidget);
      expect(find.text('Reliable teammate'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
      expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              return http.Response(
                  jsonEncode(request.url.path.endsWith('/feedback')
                      ? {
                          'feedback': [
                            taskReview(),
                            {
                              'id': 3,
                              'source': 'feedback',
                              'intern_id': 82,
                              'intern_name': 'Test Intern',
                              'rating': 4,
                              'comments': 'Reliable teammate',
                            },
                          ]
                        }
                      : {'reports': []}),
                  200);
            }));
  });

  testWidgets('empty comment is explicit and refresh loads updated feedback',
      (tester) async {
    var comments = '';
    await http.runWithClient(() async {
      await showFeedback(tester);
      expect(find.text('0 / 10 pts'), findsOneWidget);
      expect(find.text('No written feedback provided.'), findsOneWidget);
      comments = 'Please attach the screenshot';
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text(comments), findsOneWidget);
      expect(find.text('No written feedback provided.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async => http.Response(
            jsonEncode(request.url.path.endsWith('/feedback')
                ? {
                    'feedback': [taskReview(score: 0, comments: comments)]
                  }
                : {'reports': []}),
            200)));
  });

  testWidgets('feedback without score remains visible', (tester) async {
    await http.runWithClient(() async {
      await showFeedback(tester);
      expect(find.text('Not scored'), findsOneWidget);
      expect(find.text('Good work'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async => http.Response(
            jsonEncode(request.url.path.endsWith('/feedback')
                ? {
                    'feedback': [taskReview(score: null)]
                  }
                : {'reports': []}),
            200)));
  });

  testWidgets('feedback failure can be retried', (tester) async {
    var fail = true;
    await http.runWithClient(() async {
      await showFeedback(tester);
      expect(find.text('Feedback unavailable'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('9 / 10 pts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              if (!request.url.path.endsWith('/feedback')) {
                return http.Response(jsonEncode({'reports': []}), 200);
              }
              return http.Response(
                  jsonEncode(fail
                      ? {'error': 'Feedback unavailable'}
                      : {
                          'feedback': [taskReview()]
                        }),
                  fail ? 500 : 200);
            }));
  });
}
