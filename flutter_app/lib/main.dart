import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'app_state.dart';
import 'models.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  await api.init();
  final raw = await rootBundle.loadString('assets/checklistData.json');
  final templates = (jsonDecode(raw) as List<dynamic>)
      .map((item) => ChecklistTemplate.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();
  final app = AppState(api, templates);
  await app.bootstrap();
  runApp(ChangeNotifierProvider.value(value: app, child: const CareAuditApp()));
}

class CareAuditApp extends StatelessWidget {
  const CareAuditApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return MaterialApp(
      title: 'CareAudit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(app.themeMode),
      home: Builder(
        builder: (context) {
          if (app.loading) {
            return Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              body: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CareAuditLogo(emblemSize: 42, center: true),
                    SizedBox(height: 16),
                    Text('Connecting to the secure workspace…', style: TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
            );
          }
          if (app.currentUser == null) return const LoginScreen();
          return const AppShell();
        },
      ),
    );
  }
}
