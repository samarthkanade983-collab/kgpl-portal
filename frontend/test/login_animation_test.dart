import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:kgpl_portal/providers/auth_provider.dart';
import 'package:kgpl_portal/views/auth/login_view.dart';

class FakeAuthProvider extends AuthProvider {
  final logins = <List<String>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchPublicDepartments() async => [
        {'id': 1, 'name': 'IT Infrastructure'},
      ];

  @override
  Future<bool> login(String email, String password,
      {bool rememberMe = true}) async {
    logins.add([email, password]);
    return true;
  }
}

class FakeVideoPlatform extends VideoPlayerPlatform {
  late final events = StreamController<VideoEvent>();
  bool failInitialization = false;
  final calls = <String>[];
  DataSource? source;
  double? volume;
  bool? looping;
  Duration position = Duration.zero;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    source = dataSource;
    if (failInitialization) {
      events.addError(PlatformException(
          code: 'VideoError', message: 'Animation could not be loaded'));
    } else {
      events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(1280, 720),
        duration: const Duration(seconds: 17),
      ));
    }
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) => events.stream;

  @override
  Future<void> dispose(int textureId) async {
    calls.add('dispose');
    await events.close();
  }

  @override
  Future<void> play(int textureId) async => calls.add('play');

  @override
  Future<void> pause(int textureId) async => calls.add('pause');

  @override
  Future<void> setLooping(int textureId, bool looping) async {
    this.looping = looping;
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {}

  @override
  Future<Duration> getPosition(int textureId) async => position;

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    calls.add('seek');
    this.position = position;
  }

  @override
  Widget buildView(int textureId) => const ColoredBox(
        key: ValueKey('brand-video'),
        color: Colors.black,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeVideoPlatform video;
  late FakeAuthProvider auth;
  late VideoPlayerPlatform originalPlatform;

  setUp(() {
    originalPlatform = VideoPlayerPlatform.instance;
    video = FakeVideoPlatform();
    VideoPlayerPlatform.instance = video;
    auth = FakeAuthProvider();
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalPlatform;
    auth.dispose();
  });

  Future<void> showLogin(WidgetTester tester,
      {Size size = const Size(1440, 1000), bool reduceMotion = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const LoginView(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  Future<void> closeLogin(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(find.byType(LoginView), findsNothing);
    expect(video.calls, contains('dispose'));
    expect(tester.takeException(), isNull);
  }

  testWidgets('autoplays the bundled animation muted on a loop without controls',
      (tester) async {
    await showLogin(tester);
    expect(video.source?.asset, 'assets/videos/kuhugrantha-intro.mp4');
    expect(video.volume, 0);
    expect(video.looping, true);
    expect(video.calls, contains('play'));
    expect(find.byKey(const ValueKey('brand-video')), findsOneWidget);
    expect(find.byTooltip('Pause animation'), findsNothing);
    expect(find.byTooltip('Play animation'), findsNothing);
    await closeLogin(tester);
  });

  testWidgets('resizing preserves looping playback without restarting',
      (tester) async {
    await showLogin(tester);
    tester.view.physicalSize = const Size(665, 740);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(video.looping, true);
    expect(video.calls.where((call) => call == 'play'), hasLength(1));
    expect(video.calls, isNot(contains('dispose')));
    expect(find.byTooltip('Pause animation'), findsNothing);
    await closeLogin(tester);
  });

  testWidgets('reduced motion preference keeps the animation paused',
      (tester) async {
    await showLogin(tester, reduceMotion: true);
    expect(video.calls, isNot(contains('play')));
    expect(video.looping, true);
    expect(find.byTooltip('Play animation'), findsNothing);
    await closeLogin(tester);
  });

  testWidgets('video failure leaves the branding and login usable',
      (tester) async {
    video.failInitialization = true;
    await showLogin(tester);
    expect(find.byKey(const ValueKey('brand-video')), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'test-password');
    await tester.tap(find.text('Sign In to Dashboard'));
    await tester.pump();
    expect(auth.logins.single, ['person@example.com', 'test-password']);
    await closeLogin(tester);
  });

  testWidgets('login validates and submits without waiting for animation',
      (tester) async {
    await showLogin(tester);
    await tester.tap(find.text('Sign In to Dashboard'));
    await tester.pump();
    expect(find.text('Please enter both email and password'), findsOneWidget);
    expect(auth.logins, isEmpty);
    await tester.enterText(
        find.byType(TextField).at(0), ' person@example.com ');
    await tester.enterText(find.byType(TextField).at(1), 'test-password');
    await tester.tap(find.text('Sign In to Dashboard'));
    await tester.pump();
    expect(auth.logins.single, ['person@example.com', 'test-password']);
    expect(find.byTooltip('Pause animation'), findsNothing);
    await closeLogin(tester);
  });

  for (final width in [320.0, 665.0]) {
    testWidgets('login and registration remain usable at width $width',
        (tester) async {
      await showLogin(tester, size: Size(width, 740));
      expect(find.byKey(const ValueKey('brand-video')), findsOneWidget);
      await tester.ensureVisible(find.text('Sign In to Dashboard'));
      await tester.tap(find.text('Sign In to Dashboard'));
      await tester.pump();
      expect(find.text('Please enter both email and password'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign Up / Register'));
      await tester.tap(find.text('Sign Up / Register'));
      await tester.pump();
      await tester.ensureVisible(find.text('Create Account & Enter Portal'));
      expect(find.text('Create Account & Enter Portal'), findsOneWidget);
      await closeLogin(tester);
    });
  }
}
