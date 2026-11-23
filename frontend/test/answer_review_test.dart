import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kgpl_portal/views/team_leader/quiz_assessment_view.dart';

class ReviewFixture {
  List<Map<String, dynamic>> quizzes = [];
  List<Map<String, dynamic>> questions = [
    {
      'id': 16,
      'question_text': 'How many layers are in the OSI model?',
      'question_type': 'single_choice',
      'options': ['5', '7'],
      'correct_answer': '7',
      'marks': 10,
    },
    {
      'id': 17,
      'question_text': 'What does MAC stand for?',
      'question_type': 'single_choice',
      'options': ['Media Access Control', 'Other'],
      'correct_answer': 'Media Access Control',
      'marks': 10,
    },
  ];
  List<Map<String, dynamic>> attempts = [
    {
      'id': 11,
      'status': 'submitted',
      'intern_name': 'Test Intern',
      'intern_code': 'TEST-001',
      'start_time': '2026-11-16T14:40:00',
      'end_time': '2026-11-16T14:47:00',
      'needs_review': 0,
      'total_score': 20,
      'submitted_answers': {'16': '7', '17': 'Media Access Control'},
      'reviewed_at': null,
    },
  ];
  bool failAttempts = false;
  final List<http.Request> writes = [];

  Future<http.Response> respond(http.Request request) async {
    Object response;
    if (request.method != 'GET') {
      writes.add(request);
      if (request.url.path != '/api/v1/tl/attempts/11/review') {
        throw StateError('Unexpected write: ${request.url}');
      }
      attempts.first['needs_review'] = 0;
      attempts.first['reviewed_at'] = '2026-11-17T10:00:00';
      attempts.first['review_data'] = {
        '17': {'marks_awarded': 8},
      };
      attempts.first['total_score'] = 18;
      response = {'message': 'Saved'};
    } else {
      switch (request.url.path) {
        case '/api/v1/tl/quizzes':
          response = {'quizzes': quizzes};
          break;
        case '/api/v1/tl/schedules':
          response = {
            'schedules': [
              {
                'id': 22,
                'quiz_id': 14,
                'quiz_title': 'Test Assessment',
                'start_window': '2026-11-16T14:00:00',
                'end_window': '2026-11-16T16:00:00',
                'pending_reviews': 0,
              },
            ],
          };
          break;
        case '/api/v1/tl/interns':
          response = {'interns': []};
          break;
        case '/api/v1/hr/courses':
          response = {'courses': []};
          break;
        case '/api/v1/tl/schedules/22/attempts':
          if (failAttempts) {
            return http.Response(jsonEncode({'error': 'Temporary failure'}), 503);
          }
          response = {'attempts': attempts};
          break;
        case '/api/v1/tl/quizzes/14':
          response = {'questions': questions};
          break;
        default:
          throw StateError('Unexpected request: ${request.url}');
      }
    }
    return http.Response(jsonEncode(response), 200,
        headers: {'content-type': 'application/json'});
  }

  void useWrittenQuestion() {
    questions[1] = {
      'id': 17,
      'question_text': 'Explain a network switch.',
      'question_type': 'short_answer',
      'marks': 10,
    };
    attempts.first['submitted_answers']['17'] =
        'A switch forwards frames to the destination device.';
    attempts.first['needs_review'] = 1;
    attempts.first['total_score'] = 10;
  }
}

void reviewTest(
  String name,
  Future<void> Function(WidgetTester, ReviewFixture) verify, {
  void Function(ReviewFixture)? arrange,
}) {
  testWidgets(name, (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = ReviewFixture();
    arrange?.call(fixture);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: QuizAssessmentView()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scheduled Tests for Interns (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View answers'));
      await tester.pumpAndSettle();
      await verify(tester, fixture);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, () => MockClient(fixture.respond));
  });
}

void main() {
  testWidgets('keeps one scheduling button and opens the schedule dialog',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = ReviewFixture()
      ..quizzes = [
        {'id': 14, 'title': 'Test Assessment', 'question_count': 2},
        {'id': 15, 'title': 'Second Assessment', 'question_count': 1},
      ];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: QuizAssessmentView()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Test Assessment'), findsOneWidget);
      expect(find.text('Second Assessment'), findsOneWidget);
      expect(find.text('Schedule Test for Interns'), findsOneWidget);
      expect(find.text('Set & Schedule for Interns'), findsNothing);
      await tester.tap(find.text('Schedule Test for Interns'));
      await tester.pumpAndSettle();
      expect(find.text('Set & Schedule Online Test for Interns'), findsOneWidget);
      expect(fixture.writes, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, () => MockClient(fixture.respond));
  });

  reviewTest('shows every submitted MCQ and automatic grading status',
      (tester, fixture) async {
    expect(find.text('Answer Review'), findsOneWidget);
    expect(find.text("Intern's answer"), findsNWidgets(2));
    expect(find.text('Selected: 7'), findsOneWidget);
    expect(find.text('Selected: Media Access Control'), findsOneWidget);
    expect(find.text('Automatically graded'), findsOneWidget);
    expect(find.text('20 / 20 pts'), findsOneWidget);
    expect(find.text('Save Review'), findsNothing);
    expect(fixture.writes, isEmpty);
  });

  reviewTest('renders actual selected wrong answers and unanswered questions',
      (tester, fixture) async {
    expect(find.text('Selected: 5'), findsOneWidget);
    expect(find.text('Correct answer: 7  (Incorrect)'), findsOneWidget);
    expect(find.text('No answer submitted'), findsOneWidget);
  }, arrange: (fixture) {
    fixture.attempts.first['submitted_answers'] = {'16': '5'};
    fixture.attempts.first['total_score'] = 0;
  });

  reviewTest('compares MCQs case insensitively', (tester, fixture) async {
    expect(find.text('Selected: media access control'), findsOneWidget);
    expect(find.text('Correct answer: Media Access Control  (Correct)'),
        findsOneWidget);
  }, arrange: (fixture) {
    fixture.attempts.first['submitted_answers']['17'] = 'media access control';
  });

  reviewTest('shows written answers and validates and saves marks in the mock',
      (tester, fixture) async {
    expect(find.text('Selected: 7'), findsOneWidget);
    expect(find.text('A switch forwards frames to the destination device.'),
        findsOneWidget);
    expect(find.text('Awaiting review'), findsOneWidget);
    expect(find.text('10 / 20 pts (provisional)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '11');
    await tester.tap(find.text('Save Review'));
    await tester.pumpAndSettle();
    expect(fixture.writes, isEmpty);
    expect(find.text('Enter marks between 0 and 10 for every written answer'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), '8');
    await tester.tap(find.text('Save Review'));
    await tester.pumpAndSettle();
    expect(fixture.writes, hasLength(1));
    expect(jsonDecode(fixture.writes.single.body), {
      'reviews': [
        {'question_id': 17, 'marks': 8},
      ],
    });
    expect(find.text('Reviewed'), findsOneWidget);
    expect(find.text('18 / 20 pts'), findsOneWidget);
    expect(find.text('Save Review'), findsNothing);
  }, arrange: (fixture) => fixture.useWrittenQuestion());

  for (final status in ['in_progress', 'timed_out']) {
    reviewTest('$status attempts are not labelled reviewed or graded',
        (tester, fixture) async {
      expect(find.text(status == 'timed_out' ? 'Timed out' : 'In progress'),
          findsOneWidget);
      expect(find.text('Not submitted'), findsNWidgets(2));
      expect(find.text('Reviewed'), findsNothing);
      expect(find.text('Automatically graded'), findsNothing);
      expect(find.text('20 / 20 pts'), findsNothing);
      expect(find.text('Save Review'), findsNothing);
    }, arrange: (fixture) {
      fixture.attempts.first['status'] = status;
      fixture.attempts.first['submitted_answers'] = <String, String>{};
      fixture.attempts.first['needs_review'] = 1;
    });
  }

  reviewTest('displays empty attempts', (tester, fixture) async {
    expect(find.text('No intern has attempted this test yet.'), findsOneWidget);
  }, arrange: (fixture) => fixture.attempts = []);

  reviewTest('displays empty question list', (tester, fixture) async {
    expect(find.text('This paper has no questions.'), findsOneWidget);
  }, arrange: (fixture) => fixture.questions = []);

  reviewTest('displays API failure and retries successfully',
      (tester, fixture) async {
    expect(find.text('Unable to load answer review.'), findsOneWidget);
    expect(find.text('Temporary failure'), findsOneWidget);
    expect(find.text('No intern has attempted this test yet.'), findsNothing);
    fixture.failAttempts = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: 7'), findsOneWidget);
    expect(find.text('Unable to load answer review.'), findsNothing);
  }, arrange: (fixture) => fixture.failAttempts = true);

  reviewTest('answers remain accessible in a narrow dialog',
      (tester, fixture) async {
    tester.view.physicalSize = const Size(665, 605);
    await tester.pumpAndSettle();
    expect(find.text('Selected: 7'), findsOneWidget);
    expect(find.text('Selected: Media Access Control'), findsOneWidget);
    expect(find.text('Automatically graded'), findsOneWidget);
  });
}
