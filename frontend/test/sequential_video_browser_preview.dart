import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:kgpl_portal/core/theme/app_theme.dart';
import 'package:kgpl_portal/providers/auth_provider.dart';
import 'package:kgpl_portal/views/intern/course_player_view.dart';

final completed = <int>{};
bool denySessions = false;
int sessionRequests = 0;

Map<String, dynamic> lesson(int id, {bool firstInModule = false}) {
  final unlocked = firstInModule || completed.contains(id) ||
      List.generate(id - 1, (index) => index + 1).every(completed.contains);
  final required = List.generate(id - 1, (index) => index + 1)
      .where((previous) => !completed.contains(previous));
  return {
    'id': id,
    'title': 'Video $id',
    'duration_seconds': 17,
    'min_watch_percentage': 90,
    'video_path': null,
    'is_completed': completed.contains(id) ? 1 : 0,
    'is_unlocked': unlocked,
    'required_video_id': unlocked ? null : required.first,
    'required_video_title': unlocked ? null : 'Video ${required.first}',
  };
}

Future<http.Response> respond(http.Request request) async {
  Object result;
  int status = 200;
  if (request.method == 'GET') {
    result = {
      'course': {
        'id': 1,
        'title': 'Sequential video preview',
        'department_name': 'Isolated test fixture',
        'total_videos': 6,
        'completed_videos': completed.length,
        'modules': [
          {'id': 1, 'title': 'Module 1: Five sequential videos',
            'videos': List.generate(5, (index) => lesson(index + 1, firstInModule: index == 0))},
          {'id': 2, 'title': 'Module 2: Independent first lesson', 'videos': [lesson(6, firstInModule: true)]},
        ],
      },
    };
  } else {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final id = body['video_id'] as int;
    if (request.url.path.endsWith('/init')) {
      sessionRequests++;
      if (denySessions || lesson(id, firstInModule: id == 1 || id == 6)['is_unlocked'] != true) {
        status = 403;
        result = {'error': 'Preview access denied'};
      } else {
        result = {
          'session_token': 'isolated-fixture-session',
          'media_url': 'http://localhost:3011/assets/assets/videos/kuhugrantha-intro.mp4',
          'last_position_seconds': 0,
          'is_completed': completed.contains(id),
          'video_duration': 17,
        };
      }
    } else {
      if (body['tab_active'] == true && (body['current_position_seconds'] as num) >= 15) completed.add(id);
      result = {'is_completed': completed.contains(id), 'completion_percentage': completed.contains(id) ? 100 : 0};
    }
  }
  return http.Response(jsonEncode(result), status, headers: {'content-type': 'application/json'});
}

void main() {
  http.runWithClient(() {
    runApp(ChangeNotifierProvider(create: (_) => AuthProvider(), child: MaterialApp(
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const FixturePage(),
    )));
  }, () => MockClient(respond));
}

class FixturePage extends StatefulWidget {
  const FixturePage({super.key});
  @override
  State<FixturePage> createState() => _FixturePageState();
}

class _FixturePageState extends State<FixturePage> {
  int generation = 0;
  @override
  Widget build(BuildContext context) => Scaffold(body: Column(children: [
    Wrap(spacing: 12, children: [
      TextButton(onPressed: () => setState(() { completed.clear(); denySessions = false; sessionRequests = 0; generation++; }), child: const Text('Reset fixture')),
      TextButton(onPressed: () => setState(() { completed.add(1); }), child: const Text('Complete first (fixture)')),
      TextButton(onPressed: () => setState(() { denySessions = true; generation++; }), child: const Text('Deny sessions')),
      TextButton(onPressed: () => setState(() {}), child: const Text('Inspect session count')),
      Text('Session initializations: $sessionRequests'),
    ]),
    Expanded(child: CoursePlayerView(key: ValueKey(generation), courseId: 1)),
  ]));
}
