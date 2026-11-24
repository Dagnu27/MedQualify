import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String mode = 'admin';
  final username = TextEditingController();
  final password = TextEditingController();
  String error = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    error = context.read<AppState>().serviceError;
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => error = '');
    if (username.text.trim().isEmpty || password.text.length < 6) {
      setState(() => error = 'Enter your username and password.');
      return;
    }
    setState(() => busy = true);
    try {
      await context.read<AppState>().login(
            role: mode,
            username: normalizeUsername(username.text),
            password: password.text,
          );
    } on ApiException catch (requestError) {
      setState(() => error = requestError.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changeServerUrl(BuildContext context, ApiClient api) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final controller = TextEditingController(text: api.baseUrl);
    final nextUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend Server URL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set your backend API address. Use HTTPS for production and an HTTP LAN address only for local development.\n\nExamples:\n• Production: https://medqualify.onrender.com\n• Local server: http://192.168.1.20:3001',
              style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://127.0.0.1:3001',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (nextUrl != null && nextUrl.isNotEmpty) {
      try {
        await api.setBaseUrl(nextUrl);
      } catch (error) {
        messenger?.showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F6F4),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE9F4EE), Color(0xFFF6FAF8)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: Column(
                children: [
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CareAuditLogo(emblemSize: 38),
                        const SizedBox(height: 24),
                        const Eyebrow('Secure workspace access'),
                        const SizedBox(height: 6),
                        const Text('Sign in to continue.', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
                        const SizedBox(height: 6),
                        const Text('Choose your role, then use the credentials assigned to you.', style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: const Color(0xFFEEF4F1), borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            children: [
                              _roleButton('admin', 'Admin', Icons.admin_panel_settings_outlined),
                              _roleButton('inspector', 'Inspector', Icons.person_outline),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text('${mode == 'admin' ? 'Admin' : 'Inspector'} username *', style: const TextStyle(fontSize: 10, color: AppColors.inkSoft)),
                        const SizedBox(height: 6),
                        TextField(controller: username, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(hintText: 'username')),
                        const SizedBox(height: 12),
                        const Text('Password *', style: TextStyle(fontSize: 10, color: AppColors.inkSoft)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(hintText: 'At least 6 characters'),
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 12),
                        ErrorBanner(error),
                        AppButton(
                          label: busy ? 'Checking…' : 'Sign in as $mode',
                          icon: Icons.login,
                          onPressed: busy ? null : _submit,
                          expanded: true,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.shield_outlined, size: 14, color: AppColors.muted),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('Protected by SQLite session encryption & secure tokens.', style: TextStyle(fontSize: 11, color: AppColors.muted))),
                            InkWell(
                              onTap: () => _changeServerUrl(context, context.read<AppState>().api),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.paper,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.settings_ethernet_rounded, size: 12, color: AppColors.teal),
                                    SizedBox(width: 4),
                                    Text('Server IP', style: TextStyle(fontSize: 10, color: AppColors.teal, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 13, color: AppColors.teal),
                      SizedBox(width: 4),
                      Text('Offline inspections', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                      SizedBox(width: 14),
                      Icon(Icons.draw_outlined, size: 13, color: AppColors.teal),
                      SizedBox(width: 4),
                      Text('Digital sign-offs', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                      SizedBox(width: 14),
                      Icon(Icons.description_outlined, size: 13, color: AppColors.teal),
                      SizedBox(width: 4),
                      Text('PDF & Excel reports', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleButton(String id, String label, IconData icon) {
    final active = mode == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          mode = id;
          error = '';
          username.clear();
          password.clear();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: active ? AppColors.teal : AppColors.inkSoft),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: active ? AppColors.ink : AppColors.inkSoft)),
            ],
          ),
        ),
      ),
    );
  }
}
