import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kgpl_portal/views/intern/practical_tasks_view.dart';

Map<String, dynamic> practicalTask({
  int id = 1,
  String? status = 'graded',
  Object? score = 9,
  Object? maxScore = 10,
  String? feedback = 'Good implementation; clear notes.',
}) =>
    {
      'id': id,
      'title': 'Practical task $id',
      'description': 'Implement and explain the solution.',
      'submission_text': 'My implementation notes.',
      'submission_status': status,
      'score': score,
      'max_score': maxScore,
      'tl_feedback': feedback,
    };

class PracticalTasksFixture {
  List<Map<String, dynamic>> tasks = [practicalTask()];
  int requests = 0;

  Future<http.Response> respond(http.Request request) async {
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/intern/tasks');
    requests++;
    return http.Response(jsonEncode({'tasks': tasks}), 200,
        headers: {'content-type': 'application/json'});
  }
}

void setViewport(WidgetTester tester, {double width = 1200}) {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> showTasks(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: PracticalTasksView()),
  ));
  await tester.pumpAndSettle();
}

Future<void> openDetails(WidgetTester tester) async {
  final button = find.text('View Submission Details');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text('Submission Details'), findsOneWidget);
}

void feedbackTest(
  String name,
  Future<void> Function(WidgetTester, PracticalTasksFixture) verify, {
  void Function(PracticalTasksFixture)? arrange,
  double width = 1200,
}) {
  testWidgets(name, (tester) async {
    setViewport(tester, width: width);
    final fixture = PracticalTasksFixture();
    arrange?.call(fixture);
    await http.runWithClient(() async {
      await showTasks(tester);
      expect(fixture.requests, 1);
      await verify(tester, fixture);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, () => MockClient(fixture.respond));
  });
}

void main() {
  feedbackTest('shows 9/10 and saved feedback in card and details',
      (tester, fixture) async {
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('Score: 9 / 10'), findsOneWidget);
    expect(find.text('TL REVIEW'), findsOneWidget);
    expect(find.text('TL Feedback: "Good implementation; clear notes."'),
        findsOneWidget);
    expect(find.text('A+ GRADE'), findsNothing);
    expect(find.textContaining('Verified & Certified'), findsNothing);
    expect(find.text('No written feedback provided.'), findsNothing);
    await openDetails(tester);
    expect(find.text('GRADED & EVALUATED'), findsOneWidget);
    expect(find.text('Score Awarded: 9 / 10'), findsOneWidget);
    expect(find.text('TL Review Feedback:'), findsOneWidget);
    expect(find.text('"Good implementation; clear notes."'), findsOneWidget);
  });

  for (final feedback in [null, '', '   ']) {
    feedbackTest('zero score with ${jsonEncode(feedback)} feedback is not N/A',
        (tester, fixture) async {
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('N/A'), findsNothing);
      expect(find.text('Score: 0 / 10'), findsOneWidget);
      expect(find.text('No written feedback provided.'), findsOneWidget);
      await openDetails(tester);
      expect(find.text('Score Awarded: 0 / 10'), findsOneWidget);
      expect(find.text('No written feedback provided.'), findsNWidgets(2));
    }, arrange: (fixture) {
      fixture.tasks = [practicalTask(score: 0, feedback: feedback)];
    });
  }

  for (final status in ['resubmission_required', 'graded']) {
    feedbackTest('$status feedback is visible without a score',
        (tester, fixture) async {
      expect(
          find.text('TL Feedback: "Please add validation."'), findsOneWidget);
      expect(find.textContaining('Score:'), findsNothing);
      expect(find.text('No written feedback provided.'), findsNothing);
      expect(find.text('N/A'), findsOneWidget);
      if (status == 'resubmission_required') {
        expect(find.text('RESUBMISSION REQUIRED'), findsOneWidget);
        expect(find.text('UNDER REVIEW'), findsNothing);
      }
      await openDetails(tester);
      expect(find.text('"Please add validation."'), findsOneWidget);
      expect(find.textContaining('Score Awarded:'), findsNothing);
      if (status == 'resubmission_required') {
        expect(find.text('RESUBMISSION REQUIRED'), findsNWidgets(2));
        expect(find.text('UNDER TEAM LEADER REVIEW'), findsNothing);
      }
    }, arrange: (fixture) {
      fixture.tasks = [
        practicalTask(
            status: status,
            score: null,
            feedback: '  Please add validation.  '),
      ];
    });

    feedbackTest('$status without score or nonempty feedback has no review',
        (tester, fixture) async {
      expect(find.text('TL REVIEW'), findsNothing);
      expect(find.text('No written feedback provided.'), findsNothing);
      await openDetails(tester);
      expect(find.text('TL Review Feedback:'), findsNothing);
      expect(find.textContaining('Score Awarded:'), findsNothing);
    }, arrange: (fixture) {
      fixture.tasks = [
        practicalTask(status: status, score: null, feedback: '  ')
      ];
    });
  }

  feedbackTest('pending resubmission hides stale score and feedback everywhere',
      (tester, fixture) async {
    expect(find.text('UNDER REVIEW'), findsOneWidget);
    expect(find.text('N/A'), findsOneWidget);
    expect(find.text('TL REVIEW'), findsNothing);
    expect(find.textContaining('Score:'), findsNothing);
    expect(find.textContaining('Old review'), findsNothing);
    await openDetails(tester);
    expect(find.text('UNDER TEAM LEADER REVIEW'), findsOneWidget);
    expect(find.textContaining('Score Awarded:'), findsNothing);
    expect(find.textContaining('Old review'), findsNothing);
    expect(find.text('TL Review Feedback:'), findsNothing);
    expect(find.text('No written feedback provided.'), findsNothing);
  }, arrange: (fixture) {
    fixture.tasks = [practicalTask(status: 'pending', feedback: 'Old review')];
  });

  feedbackTest('Refresh retrieves and displays the latest review',
      (tester, fixture) async {
    expect(find.textContaining('Old review'), findsNothing);
    expect(find.text('N/A'), findsOneWidget);
    fixture.tasks = [practicalTask(feedback: 'Latest saved feedback')];
    expect(find.text('Refresh').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(fixture.requests, 2);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('Score: 9 / 10'), findsOneWidget);
    expect(find.text('TL Feedback: "Latest saved feedback"'), findsOneWidget);
    expect(find.textContaining('Old review'), findsNothing);
    await openDetails(tester);
    expect(find.text('Score Awarded: 9 / 10'), findsOneWidget);
    expect(find.text('"Latest saved feedback"'), findsOneWidget);
  }, arrange: (fixture) {
    fixture.tasks = [practicalTask(status: 'pending', feedback: 'Old review')];
  });

  feedbackTest('averages normalized graded scores with positive maxima only',
      (tester, fixture) async {
    // Mean of 90% and 20%, not raw scores or a weighted percentage.
    expect(find.text('55%'), findsOneWidget);
  }, arrange: (fixture) {
    fixture.tasks = [
      practicalTask(),
      practicalTask(id: 2, score: '20', maxScore: '100'),
      practicalTask(id: 3, status: 'pending'),
      practicalTask(id: 4, status: 'resubmission_required'),
      practicalTask(id: 5, status: null),
      practicalTask(id: 6, maxScore: 0),
      practicalTask(id: 7, maxScore: -10),
      practicalTask(id: 8, maxScore: null),
      practicalTask(id: 9, score: null),
    ];
  });

  feedbackTest('no positive maximum means the average is N/A',
      (tester, fixture) async {
    expect(find.text('N/A'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  }, arrange: (fixture) {
    fixture.tasks = [practicalTask(maxScore: 0)];
  });

  feedbackTest('header wraps beside Refresh at narrow widths',
      (tester, fixture) async {
    final header = tester.widget<Row>(find.ancestor(
      of: find.text('Assigned Practical Tasks'),
      matching: find.byType(Row),
    ));
    // Constrain just the header; existing toolbar layout is outside this fix.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(width: 360, child: header)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Assigned Practical Tasks').hitTestable(), findsOneWidget);
    expect(find.text('Refresh').hitTestable(), findsOneWidget);
    expect(tester.getRect(find.text('Assigned Practical Tasks')).right,
        lessThan(tester.getRect(find.text('Refresh')).left));
  }, arrange: (fixture) => fixture.tasks = []);

  for (final statusCode in [200, 500]) {
    testWidgets('fetch completion after disposal is safe ($statusCode)',
        (tester) async {
      setViewport(tester);
      final response = Completer<http.Response>();
      var requests = 0;
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: PracticalTasksView()),
        ));
        await tester.pump();
        expect(requests, 1);
        final refresh = tester.widget<OutlinedButton>(find.ancestor(
          of: find.text('Refresh'),
          matching:
              find.byWidgetPredicate((widget) => widget is OutlinedButton),
        ));
        expect(refresh.onPressed, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        response.complete(http.Response(
            jsonEncode(statusCode == 200
                ? {'tasks': <Object>[]}
                : {'error': 'Temporary failure'}),
            statusCode));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
          () => MockClient((request) {
                requests++;
                return response.future;
              }));
    });
  }
}
