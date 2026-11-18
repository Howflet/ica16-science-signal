import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'dev/dev_faults.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'services/attempt_repository.dart';
import 'services/trivia_api.dart';
import 'state/quiz_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final faults = DevFaults();
  final controller = QuizController(
    auth: FirebaseAuth.instance,
    trivia: TriviaApi(faults: faults),
    repo: AttemptRepository(faults: faults),
  );
  runApp(ScienceSignalApp(controller: controller, faults: faults));
}

class ScienceSignalApp extends StatelessWidget {
  const ScienceSignalApp({
    super.key,
    required this.controller,
    required this.faults,
  });

  final QuizController controller;
  final DevFaults faults;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF30274C),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Science Signal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF30274C),
          foregroundColor: Colors.white,
        ),
      ),
      home: HomeScreen(controller: controller, faults: faults),
    );
  }
}
