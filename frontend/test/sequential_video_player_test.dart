import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kgpl_portal/core/config/api_config.dart';
import 'package:kgpl_portal/providers/auth_provider.dart';
import 'package:kgpl_portal/views/intern/course_player_view.dart';
import 'package:kgpl_portal/widgets/anti_cheat_player.dart';
import 'package:provider/provider.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlatform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final events = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  final calls = <String>[];

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    sources.add(dataSource);
    final id = sources.length;
    events[id] = StreamController<VideoEvent>();
    positions[id] = Duration.zero;
    events[id]!.add(VideoEvent(
      eventType: VideoEventType.initialized,
      size: const Size(1280, 720),
      duration: const Duration(seconds: 12),
    ));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) => events[textureId]!.stream;

  @override
  Future<void> dispose(int textureId) async {
    calls.add('dispose:$textureId');
    await events[textureId]!.close();
  }

  @override
  Future<void> play(int textureId) async => calls.add('play:$textureId');

  @override
  Future<void> pause(int textureId) async => calls.add('pause:$textureId');

  @override
  Future<void> setLooping(int textureId, bool looping) async {}

  @override
  Future<void> setVolume(int textureId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<Duration> getPosition(int textureId) async => positions[textureId]!;

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    positions[textureId] = position;
    calls.add('seek:$textureId:${position.inSeconds}');
  }

  @override
  Widget buildView(int textureId) => ColoredBox(
        key: ValueKey('lesson-media-$textureId'),
        color: Colors.black,
      );

  void end([int id = 1]) {
    positions[id] = const Duration(seconds: 12);
    events[id]!.add(VideoEvent(eventType: VideoEventType.completed));
  }
}

Map<String, dynamic> lesson(int id,
        {bool unlocked = true,
        bool completed = false,
        String? requiredTitle}) =>
    {
      'id': id,
      'title': 'Lesson $id',
      'duration_seconds': 12,
      'min_watch_percentage': 90,
      'completion_percentage': 0,
      'is_unlocked': unlocked,
      'is_completed': completed,
      'required_video_id': unlocked ? null : 1,
      'required_video_title': requiredTitle,
      'video_path': unlocked ? '/uploads/untrusted-$id.mp4' : null,
    };

class PlayerFixture {
  final video = FakeVideoPlatform();
  final auth = AuthProvider();
  List<Map<String, dynamic>> modules = [
    {
      'title': 'Module 1: Basics',
      'videos': [
        lesson(1),
        lesson(2, unlocked: false, requiredTitle: 'Lesson 1')
      ],
    },
    {
      'title': 'Module 2: Advanced',
      'videos': [lesson(3), lesson(4, completed: true)],
    },
  ];
  final initIds = <int>[];
  final heartbeats = <Map<String, dynamic>>[];
  int courseGets = 0;
  int initStatus = 200;
  int heartbeatStatus = 200;
  int courseStatus = 200;
  bool completed = false;
  double completionPercentage = 0;
  Object? media = '/api/v1/intern/video/1/stream?session_token=mock-session';
  Object? sessionToken = 'mock-session';
  int resume = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  Completer<void>? initGate;
  Completer<void>? courseGate;
  Completer<void>? heartbeatGate;
  int completions = 0;
  int ends = 0;

  Future<http.Response> respond(http.Request request) async {
    if (request.method == 'GET') {
      expect(request.url.path, '/api/v1/intern/courses/1');
      courseGets++;
      final snapshot = response({
        'course': {
          'title': 'Sequential course',
          'department_name': 'Training',
          'completed_videos': 1,
          'total_videos': 4,
          'modules': modules,
        },
      }, courseStatus);
      await courseGate?.future;
      return snapshot;
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (request.url.path.endsWith('/video/init')) {
      initIds.add(body['video_id'] as int);
      await initGate?.future;
      return response({
        'error': 'Complete Lesson 1 to unlock',
        'session_token': sessionToken,
        'media_url': media,
        'video_duration': 12,
        'last_position_seconds': resume,
        'is_completed': completed,
        'completion_percentage': completionPercentage,
      }, initStatus);
    }
    expect(request.url.path, '/api/v1/intern/video/heartbeat');
    heartbeats.add(body);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await heartbeatGate?.future;
    inFlight--;
    return response({
      'error': 'Session no longer authorized',
      'is_completed': completed,
      'completion_percentage': completionPercentage,
    }, heartbeatStatus);
  }

  http.Response response(Map<String, dynamic> body, int status) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});

  Future<void> show(
    WidgetTester tester, {
    bool course = false,
    Size screenSize = const Size(1440, 1100),
  }) async {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        home: Scaffold(
          body: course
              ? const CoursePlayerView(courseId: 1)
              : AntiCheatPlayer(
                  videoId: 1,
                  title: 'Lesson 1',
                  durationSeconds: 12,
                  maxVideoStageHeight: 380,
                  onCompleted: () => completions++,
                  onEnded: () => ends++,
                ),
        ),
      ),
    ));
    await flush(tester);
  }

  Future<void> play(WidgetTester tester) async {
    await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
    await flush(tester);
  }

  Future<void> select(WidgetTester tester, int id) async {
    await tester.tap(find.widgetWithText(ListTile, 'Lesson $id'));
    await flush(tester);
  }

  Future<void> refresh(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Refresh lessons'));
    await flush(tester);
  }

  void unlockNext() {
    modules[0]['videos'] = [lesson(1, completed: true), lesson(2)];
  }
}

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
}

void playerTest(
  String name,
  Future<void> Function(WidgetTester, PlayerFixture) verify, {
  bool course = false,
  Size screenSize = const Size(1440, 1100),
  void Function(PlayerFixture)? arrange,
}) {
  testWidgets(name, (tester) async {
    final originalPlatform = VideoPlayerPlatform.instance;
    final fixture = PlayerFixture();
    VideoPlayerPlatform.instance = fixture.video;
    addTearDown(() {
      VideoPlayerPlatform.instance = originalPlatform;
      fixture.auth.dispose();
    });
    arrange?.call(fixture);
    await http.runWithClient(() async {
      await fixture.show(tester, course: course, screenSize: screenSize);
      await verify(tester, fixture);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, () => MockClient(fixture.respond));
  });
}

void main() {
  playerTest('locked lessons have a lock, prerequisite and disabled tap',
      (tester, fixture) async {
    final tile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Lesson 2'));
    expect(tile.enabled, isFalse);
    expect(tile.onTap, isNull);
    expect(find.byIcon(Icons.lock_outline), findsWidgets);
    expect(find.text('Complete Lesson 1 to unlock'), findsOneWidget);
    await fixture.select(tester, 2);
    expect(fixture.initIds, [1]);
    expect(fixture.video.sources, hasLength(1));
  }, course: true);

  playerTest(
      'missing unlock flag fails closed even for completed lessons',
      (tester, fixture) async {
        final tile =
            tester.widget<ListTile>(find.widgetWithText(ListTile, 'Lesson 4'));
        expect(tile.enabled, isFalse);
        expect(tile.onTap, isNull);
        await fixture.select(tester, 4);
        expect(fixture.initIds, [1]);
      },
      course: true,
      arrange: (fixture) {
        (fixture.modules[1]['videos'] as List)[1].remove('is_unlocked');
      });

  playerTest(
      'first lesson of each module and legacy completed rewatch accessible',
      (tester, fixture) async {
    await fixture.select(tester, 3);
    expect(fixture.initIds, [1, 3]);
    fixture.completed = true;
    await fixture.select(tester, 4);
    expect(fixture.initIds, [1, 3, 4]);
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.textContaining('pass its test to unlock the next module'),
        findsOneWidget);
  }, course: true);

  playerTest('third lesson shows the same player controls as earlier lessons',
      (tester, fixture) async {
    await fixture.select(tester, 3);
    expect(find.byTooltip('Full screen'), findsOneWidget);
    expect(find.byTooltip('Playback Speed'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.play_arrow), findsOneWidget);
    expect(find.text('00:00 / 00:12'), findsOneWidget);

    await tester.tap(find.byTooltip('Full screen'));
    await flush(tester);
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    expect(find.byTooltip('Playback Speed'), findsOneWidget);
  }, course: true);

  playerTest(
    'module test is shown with its module and opens the separate runner',
    (tester, fixture) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey('start-module-test-41')),
      );
      await tester.tap(find.byKey(const ValueKey('start-module-test-41')));
      await flush(tester);

      expect(fixture.auth.activeView, 'course_module_test');
      expect(fixture.auth.activeCourseModuleTestId, 41);
      expect(fixture.auth.activeTestScheduleId, isNull);
    },
    course: true,
    arrange: (fixture) {
      fixture.modules[0]['videos'] = [
        lesson(1, completed: true),
        lesson(2, completed: true),
      ];
      fixture.modules[0]['test'] = {
        'id': 41,
        'title': 'Module 1 Check',
        'passing_score': 60,
        'question_count': 1,
        'attempt_status': null,
        'is_passed': false,
        'is_unlocked': true,
        'can_resume': false,
      };
    },
  );

  playerTest('center controls hide during playback and return on interaction',
      (tester, fixture) async {
    expect(find.byTooltip('Restart video'), findsOneWidget);
    expect(find.byTooltip('Resume video'), findsOneWidget);

    await tester.tap(find.byTooltip('Resume video'));
    await flush(tester);
    expect(find.byTooltip('Pause video'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    await flush(tester);
    expect(find.byTooltip('Restart video'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await flush(tester);
    expect(find.byTooltip('Restart video'), findsNothing);
    expect(find.byTooltip('Pause video'), findsNothing);

    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('video-stage'))));
    await flush(tester);
    expect(find.byTooltip('Pause video'), findsOneWidget);

    await tester.tap(find.byTooltip('Restart video'));
    await flush(tester);
    expect(fixture.video.calls, contains('seek:1:0'));
    expect(find.byTooltip('Pause video'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause video'));
    await flush(tester);
    expect(find.byTooltip('Resume video'), findsOneWidget);
  });

  playerTest('short course pane keeps all player controls on-screen',
      (tester, fixture) async {
    final stage = tester.getRect(find.byKey(const ValueKey('video-stage')));
    expect(stage.height, lessThan(380));
    expect(tester.getRect(find.byTooltip('Full screen')).bottom,
        lessThanOrEqualTo(stage.bottom));
    expect(tester.getRect(find.byTooltip('Playback Speed')).bottom,
        lessThanOrEqualTo(stage.bottom));
    expect(find.text('00:00 / 00:12'), findsOneWidget);
  }, course: true, screenSize: const Size(1440, 500));

  playerTest(
      'verified watch progress is distinct from playback position',
      (tester, fixture) async {
        expect(find.text('44.0% verified'), findsOneWidget);
        expect(find.textContaining('Playback position:'), findsOneWidget);
        expect(find.textContaining('44% verified •'), findsOneWidget);
      },
      course: true,
      arrange: (fixture) {
        fixture.completionPercentage = 44.01;
        fixture.resume = 12;
        (fixture.modules[0]['videos'] as List)[0]['completion_percentage'] =
            44.01;
      });

  playerTest(
      'initial selection skips locked videos without initializing them',
      (tester, fixture) async {
        expect(fixture.initIds, [3]);
      },
      course: true,
      arrange: (fixture) {
        fixture.modules[0]['videos'] = [lesson(1, unlocked: false)];
      });

  playerTest(
      'no unlocked videos creates no media or session',
      (tester, fixture) async {
        expect(fixture.initIds, isEmpty);
        expect(fixture.video.sources, isEmpty);
        expect(find.text('No unlocked videos available'), findsOneWidget);
      },
      course: true,
      arrange: (fixture) {
        fixture.modules = [
          {
            'title': 'Locked',
            'videos': [lesson(1, unlocked: false)]
          },
        ];
      });

  playerTest('refresh updates unlocks without tearing down or rotating session',
      (tester, fixture) async {
    final originalState = tester.state(find.byType(AntiCheatPlayer));
    await fixture.play(tester);
    fixture.courseGate = Completer<void>();
    fixture.unlockNext();
    await fixture.refresh(tester);
    expect(fixture.courseGets, 2);
    expect(find.byKey(const ValueKey('lesson-media-1')), findsOneWidget);
    expect(tester.state(find.byType(AntiCheatPlayer)), same(originalState));
    expect(fixture.video.calls, isNot(contains('dispose:1')));
    fixture.courseGate!.complete();
    await flush(tester);
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Lesson 2'))
            .enabled,
        isTrue);
    expect(fixture.initIds, [1]);
    expect(fixture.video.sources, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    expect(fixture.heartbeats.last['session_token'], 'mock-session');
  }, course: true);

  playerTest('completion refresh preserves the active player and its session',
      (tester, fixture) async {
    final originalState = tester.state(find.byType(AntiCheatPlayer));
    await fixture.play(tester);
    fixture.completed = true;
    fixture.unlockNext();
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    expect(fixture.courseGets, 2);
    expect(tester.state(find.byType(AntiCheatPlayer)), same(originalState));
    expect(fixture.initIds, [1]);
    expect(fixture.video.sources, hasLength(1));
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Lesson 2'))
            .enabled,
        isTrue);
  }, course: true);

  playerTest('failed refresh keeps current playback and does not advance',
      (tester, fixture) async {
    fixture.courseStatus = 500;
    await fixture.refresh(tester);
    expect(find.text('Could not refresh lessons. Please try again.'),
        findsOneWidget);
    expect(fixture.initIds, [1]);
    expect(find.byKey(const ValueKey('lesson-media-1')), findsOneWidget);
  }, course: true);

  playerTest('init must finish before any media is created',
      (tester, fixture) async {
    expect(fixture.initIds, [1]);
    expect(fixture.video.sources, isEmpty);
    fixture.initGate!.complete();
    await flush(tester);
    expect(fixture.video.sources.single.uri,
        '${ApiConfig.serverOrigin}/api/v1/intern/video/1/stream?session_token=mock-session');
  }, arrange: (fixture) => fixture.initGate = Completer<void>());

  for (final status in [401, 403, 500]) {
    playerTest('init $status shows error with no media or heartbeat timer',
        (tester, fixture) async {
      expect(find.text('Complete Lesson 1 to unlock'), findsOneWidget);
      expect(fixture.video.sources, isEmpty);
      await tester.pump(const Duration(seconds: 15));
      expect(fixture.heartbeats, isEmpty);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    }, arrange: (fixture) => fixture.initStatus = status);
  }

  playerTest('stalled authorization shows retry and controls stay visible',
      (tester, fixture) async {
    await tester.pump(const Duration(seconds: 16));
    await flush(tester);
    expect(find.text('Playback setup timed out. Please retry the lesson.'),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Full screen'), findsOneWidget);

    fixture.initGate!.complete();
    await tester.tap(find.text('Retry'));
    await flush(tester);
    expect(fixture.initIds, [1, 1]);
    expect(fixture.video.sources, hasLength(1));
  }, arrange: (fixture) => fixture.initGate = Completer<void>());

  for (final media in [null, '', '   ', 'file:///private.mp4', 'http://']) {
    playerTest(
        'invalid media ${jsonEncode(media)} never falls back to videoUrl',
        (tester, fixture) async {
      expect(fixture.video.sources, isEmpty);
      expect(
          find.textContaining('authorized media').evaluate().isNotEmpty ||
              find
                  .textContaining('playback authorization')
                  .evaluate()
                  .isNotEmpty ||
              find
                  .textContaining('could not be authorized')
                  .evaluate()
                  .isNotEmpty,
          isTrue);
      await tester.pump(const Duration(seconds: 15));
      expect(fixture.heartbeats, isEmpty);
    }, arrange: (fixture) => fixture.media = media);
  }

  playerTest('missing session token creates no media', (tester, fixture) async {
    expect(find.text('This lesson has no valid playback authorization.'),
        findsOneWidget);
    expect(fixture.video.sources, isEmpty);
  }, arrange: (fixture) => fixture.sessionToken = null);

  playerTest('authorized external media resumes a completed rewatch',
      (tester, fixture) async {
    expect(
        fixture.video.sources.single.uri, 'https://media.example/lesson.mp4');
    expect(fixture.video.calls, contains('seek:1:4'));
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(fixture.completions, 0);
  }, arrange: (fixture) {
    fixture.media = 'https://media.example/lesson.mp4';
    fixture.completed = true;
    fixture.resume = 4;
  });

  playerTest('ending without server completion never invokes callbacks',
      (tester, fixture) async {
    await fixture.play(tester);
    fixture.video.end();
    await flush(tester);
    expect(fixture.heartbeats.last['current_position_seconds'], 12);
    expect(fixture.heartbeats.last['tab_active'], isTrue);
    expect(fixture.ends, 0);
    expect(fixture.completions, 0);
    expect(
        find.textContaining(
            'has not reached its 90% verified-watch requirement'),
        findsOneWidget);
  });

  playerTest('final heartbeat confirms completion before ended callback',
      (tester, fixture) async {
    await fixture.play(tester);
    fixture.completed = true;
    fixture.video.end();
    await flush(tester);
    expect(fixture.heartbeats.last['tab_active'], isTrue);
    expect(fixture.completions, 1);
    expect(fixture.ends, 1);
  });

  playerTest('pause heartbeat credits the preceding playing interval',
      (tester, fixture) async {
    await fixture.play(tester);
    expect(fixture.heartbeats.single['tab_active'], isFalse);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.pause));
    await flush(tester);
    expect(fixture.heartbeats.last['tab_active'], isTrue);
  });

  playerTest(
      'background pauses playback and does not advance an unfinished lesson',
      (tester, fixture) async {
    await fixture.play(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await flush(tester);
    expect(fixture.video.calls, contains('pause:1'));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await flush(tester);
    expect(fixture.heartbeats.last['tab_active'], isFalse);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    final count = fixture.heartbeats.length;
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    expect(fixture.heartbeats, hasLength(count));
    fixture.video.end();
    await flush(tester);
    expect(fixture.heartbeats.last['tab_active'], isFalse);
    expect(fixture.ends, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
    expect(fixture.heartbeats.last['tab_active'], isFalse);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  for (final status in [401, 403]) {
    playerTest('heartbeat $status pauses playback and shows access error',
        (tester, fixture) async {
      await fixture.play(tester);
      fixture.heartbeatStatus = status;
      await tester.pump(const Duration(seconds: 5));
      await flush(tester);
      expect(find.textContaining('Playback access denied.'), findsOneWidget);
      expect(fixture.video.calls.last, 'pause:1');
      expect(find.byKey(const ValueKey('lesson-media-1')), findsNothing);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      final count = fixture.heartbeats.length;
      await tester.pump(const Duration(seconds: 10));
      await flush(tester);
      expect(fixture.heartbeats, hasLength(count));
      expect(fixture.ends, 0);
    });
  }

  playerTest(
      'concurrent heartbeats serialize and retain final playing interval',
      (tester, fixture) async {
    await fixture.play(tester);
    fixture.heartbeatGate = Completer<void>();
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    expect(fixture.inFlight, 1);
    fixture.completed = true;
    fixture.video.end();
    await flush(tester);
    expect(fixture.inFlight, 1);
    expect(fixture.ends, 0);
    fixture.heartbeatGate!.complete();
    await flush(tester);
    expect(fixture.maxInFlight, 1);
    expect(fixture.heartbeats.last['current_position_seconds'], 12);
    expect(fixture.heartbeats.last['tab_active'], isTrue);
    expect(fixture.ends, 1);
    expect(fixture.completions, 1);
  });

  playerTest(
      'end alone cannot auto-advance even when next lesson is unlocked',
      (tester, fixture) async {
        await fixture.play(tester);
        fixture.video.end();
        await flush(tester);
        expect(fixture.initIds, [1]);
        expect(fixture.courseGets, 1);
      },
      course: true,
      arrange: (fixture) {
        fixture.modules[0]['videos'] = [lesson(1), lesson(2)];
      });

  playerTest(
      'completed end refreshes unlock state before advancing immediate next',
      (tester, fixture) async {
    await fixture.play(tester);
    fixture.completed = true;
    fixture.courseGate = Completer<void>();
    fixture.unlockNext();
    fixture.video.end();
    await flush(tester);
    expect(fixture.courseGets, 2);
    expect(fixture.initIds, [1]);
    expect(find.byKey(const ValueKey('lesson-media-1')), findsOneWidget);
    fixture.courseGate!.complete();
    await flush(tester);
    expect(fixture.initIds, [1, 2]);
    expect(fixture.video.calls, contains('play:2'));
    expect(find.byKey(const ValueKey('lesson-media-1')), findsNothing);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(fixture.video.calls, contains('dispose:1'));
  }, course: true);

  playerTest(
      'confirmed completion never skips an immediate lock to another module',
      (tester, fixture) async {
    await fixture.play(tester);
    fixture.completed = true;
    fixture.modules[0]['videos'] = [
      lesson(1, completed: true),
      lesson(2, unlocked: false, requiredTitle: 'Lesson 1'),
    ];
    fixture.video.end();
    await flush(tester);
    expect(fixture.courseGets, 3);
    expect(fixture.initIds, [1]);
  }, course: true);

  playerTest(
      'course must confirm completion even if heartbeat reports completed',
      (tester, fixture) async {
        await fixture.play(tester);
        fixture.completed = true;
        fixture.video.end();
        await flush(tester);
        expect(fixture.initIds, [1]);
      },
      course: true,
      arrange: (fixture) {
        fixture.modules[0]['videos'] = [lesson(1), lesson(2)];
      });

  playerTest('selection during completion refresh prevents stale auto-advance',
      (tester, fixture) async {
    await fixture.play(tester);
    fixture.completed = true;
    fixture.courseGate = Completer<void>();
    fixture.unlockNext();
    fixture.video.end();
    await flush(tester);
    await fixture.select(tester, 3);
    fixture.courseGate!.complete();
    await flush(tester);
    expect(fixture.initIds, [1, 3]);
  }, course: true);

  playerTest(
      'late denied init after disposal does not create media or setState',
      (tester, fixture) async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.initGate!.complete();
    await flush(tester);
    expect(fixture.video.sources, isEmpty);
  }, arrange: (fixture) {
    fixture.initGate = Completer<void>();
    fixture.initStatus = 403;
  });

  playerTest('an older pending refresh cannot supply stale unlocks at ended',
      (tester, fixture) async {
    await fixture.play(tester);
    fixture.courseGate = Completer<void>();
    await fixture.refresh(tester);
    expect(fixture.courseGets, 2);
    fixture.completed = true;
    fixture.unlockNext();
    fixture.video.end();
    await flush(tester);
    expect(fixture.initIds, [1]);
    fixture.courseGate!.complete();
    await flush(tester);
    expect(fixture.courseGets, 3);
    expect(fixture.initIds, [1, 2]);
  }, course: true);

  playerTest('queued foreground heartbeat cannot credit a background interval',
      (tester, fixture) async {
    await fixture.play(tester);
    fixture.heartbeatGate = Completer<void>();
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    fixture.heartbeatGate!.complete();
    await flush(tester);
    expect(fixture.maxInFlight, 1);
    expect(fixture.heartbeats.skip(2).map((body) => body['tab_active']),
        everyElement(isFalse));
  });

  playerTest('paused seek to the end cannot claim playing time',
      (tester, fixture) async {
    await fixture.play(tester);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.pause));
    await flush(tester);
    fixture.video.end();
    await flush(tester);
    expect(fixture.heartbeats.last['tab_active'], isFalse);
    expect(fixture.ends, 0);
  });

  playerTest('denied final heartbeat blocks ended even on a completed rewatch',
      (tester, fixture) async {
    await fixture.play(tester);
    fixture.heartbeatStatus = 403;
    fixture.video.end();
    await flush(tester);
    expect(find.textContaining('Playback access denied.'), findsOneWidget);
    expect(fixture.ends, 0);
  }, arrange: (fixture) => fixture.completed = true);

  playerTest('late course refresh after disposal is ignored',
      (tester, fixture) async {
    fixture.courseGate = Completer<void>();
    await fixture.refresh(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.courseGate!.complete();
    await flush(tester);
    expect(fixture.initIds, [1]);
  }, course: true);
}
