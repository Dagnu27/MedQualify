import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final name = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  late final TextEditingController adminName;
  late final TextEditingController adminUsername;
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  String error = '';
  String notice = '';
  String securityError = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    adminName = TextEditingController(text: app.admin?.name ?? '');
    adminUsername = TextEditingController(text: app.admin?.username ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    password.dispose();
    adminName.dispose();
    adminUsername.dispose();
    currentPassword.dispose();
    newPassword.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() {
      error = '';
      notice = '';
    });
    final normalized = normalizeUsername(username.text);
    if (name.text.trim().isEmpty || normalized.isEmpty || password.text.length < 6) {
      setState(() => error = 'Add a name, username, and a password with at least 6 characters.');
      return;
    }
    setState(() => busy = true);
    try {
      await context.read<AppState>().addInspector({
        'name': name.text.trim(),
        'username': normalized,
        'password': password.text,
      });
      setState(() {
        notice = '${name.text.trim()} can now sign in with $normalized.';
        name.clear();
        username.clear();
        password.clear();
      });
    } on ApiException catch (requestError) {
      setState(() => error = requestError.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveAdmin() async {
    setState(() => securityError = '');
    final normalized = normalizeUsername(adminUsername.text);
    if (adminName.text.trim().isEmpty || normalized.isEmpty || currentPassword.text.length < 6 || (newPassword.text.isNotEmpty && newPassword.text.length < 6)) {
      setState(() => securityError = 'Enter your current password and use at least 6 characters for a new password.');
      return;
    }
    try {
      await context.read<AppState>().updateAdmin({
        'name': adminName.text.trim(),
        'username': normalized,
        'currentPassword': currentPassword.text,
        'newPassword': newPassword.text,
      });
      currentPassword.clear();
      newPassword.clear();
      setState(() => notice = 'Admin credentials updated. Use the new username and password next time you sign in.');
    } on ApiException catch (requestError) {
      setState(() => securityError = requestError.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      children: [
        const PageHeader(
          eyebrow: 'Admin control room',
          title: 'The inspector roster.',
          description: 'Create and manage the credentials your inspection team uses to enter this shared workspace.',
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Add an inspector'),
              const Text('Assign a new login.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Inspector accounts are stored in the shared CareAudit database and can sign in from any approved session.', style: TextStyle(color: AppColors.inkSoft)),
              const SizedBox(height: 16),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Inspector name')),
              const SizedBox(height: 10),
              TextField(controller: username, decoration: const InputDecoration(labelText: 'Username')),
              const SizedBox(height: 10),
              TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Temporary password')),
              const SizedBox(height: 12),
              ErrorBanner(error),
              NoticeBanner(notice),
              AppButton(label: busy ? 'Creating…' : 'Create inspector account', icon: Icons.person_add_alt, onPressed: busy ? null : _add, expanded: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('People with access', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
                  Text('${app.inspectors.length} ${app.inspectors.length == 1 ? 'inspector' : 'inspectors'}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                ],
              ),
              if (app.inspectors.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No inspector accounts yet.'),
                )
              else
                ...app.inspectors.map((inspector) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(backgroundColor: AppColors.mint, child: Icon(Icons.person_outline, color: AppColors.teal)),
                      title: Text(inspector.name),
                      subtitle: Text('@${inspector.username} · added ${formatDate(inspector.createdAt, short: true)}'),
                      trailing: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusPill(inspector.active ? 'completed' : 'draft'),
                          IconButton(
                            tooltip: 'Reset password',
                            onPressed: () => _reset(inspector),
                            icon: const Icon(Icons.key, size: 18),
                          ),
                          IconButton(
                            tooltip: inspector.active ? 'Archive account' : 'Restore account',
                            onPressed: () => inspector.active ? _archive(inspector) : app.toggleInspector(inspector.id, true),
                            icon: Icon(inspector.active ? Icons.delete_outline : Icons.login, size: 18),
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Admin settings'),
              const Text('Change admin credentials.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(controller: adminName, decoration: const InputDecoration(labelText: 'Admin name')),
              const SizedBox(height: 10),
              TextField(controller: adminUsername, decoration: const InputDecoration(labelText: 'Admin username')),
              const SizedBox(height: 10),
              TextField(controller: currentPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
              const SizedBox(height: 10),
              TextField(controller: newPassword, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
              const SizedBox(height: 12),
              ErrorBanner(securityError),
              AppButton(label: 'Save admin credentials', icon: Icons.key, variant: 'secondary', onPressed: _saveAdmin),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _archive(UserAccount inspector) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive account?'),
        content: Text("Archive ${inspector.name}'s account? They will lose sign-in access, but their submitted reports will be kept."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AppState>().toggleInspector(inspector.id, false);
      setState(() => notice = "${inspector.name}'s access was archived. Submitted reports were kept.");
    } on ApiException catch (requestError) {
      setState(() => error = requestError.message);
    }
  }

  Future<void> _reset(UserAccount inspector) async {
    final controller = TextEditingController();
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set a new password for ${inspector.name}'),
        content: TextField(controller: controller, obscureText: true, decoration: const InputDecoration(hintText: 'At least 6 characters')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Reset')),
        ],
      ),
    );
    if (next == null || next.length < 6 || !mounted) return;
    try {
      await context.read<AppState>().resetInspector(inspector.id, next);
      setState(() => notice = 'Password reset for ${inspector.name}.');
    } on ApiException catch (requestError) {
      setState(() => error = requestError.message);
    }
  }
}
