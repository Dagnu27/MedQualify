import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'audit_screen.dart';
import 'dashboard_screen.dart';
import 'library_screen.dart';
import 'report_screen.dart';
import 'setup_screen.dart';
import 'summary_screen.dart';
import 'team_screen.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static Future<void> confirmLogout(BuildContext context, AppState app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.red),
            SizedBox(width: 10),
            Text('Sign out', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out of CareAudit?',
          style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.inkSoft)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Log out'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await app.logout();
    }
  }

  static Future<void> showThemePicker(BuildContext context, AppState app) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.palette_outlined, color: AppColors.teal, size: 20),
                    const SizedBox(width: 8),
                    const Text('Screen Background & Display', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose the background mode that best fits your environment and eye comfort.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 16),
                ...AppThemeMode.values.map((mode) {
                  final isSelected = app.themeMode == mode;
                  return InkWell(
                    onTap: () {
                      app.setThemeMode(mode);
                      Navigator.of(ctx).pop();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.mint.withValues(alpha: 0.4) : Theme.of(ctx).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.teal : Theme.of(ctx).dividerColor,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: mode.bgPreview,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black26),
                            ),
                            child: Center(
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: mode.accentPreview,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mode.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: isSelected ? AppColors.teal : null,
                                  ),
                                ),
                                Text(
                                  mode.description,
                                  style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle_rounded, color: AppColors.teal, size: 20),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.currentUser!;
    final title = switch (app.view) {
      AppView.dashboard => 'Overview',
      AppView.library => 'Checklist library',
      AppView.setup => 'New inspection',
      AppView.team => 'Inspector accounts',
      _ => app.activeTemplate?.title ?? 'Inspection',
    };
    final recordView = [AppView.audit, AppView.summary, AppView.report].contains(app.view);
    Widget body;
    if (recordView && (app.activeRecord == null || app.activeTemplate == null)) {
      body = ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('This inspection is no longer in this device.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('It may have been removed or you may be opening it on a different device.'),
          const SizedBox(height: 16),
          AppButton(label: 'Back to overview', icon: Icons.home_outlined, onPressed: app.openHome),
        ],
      );
    } else {
      body = switch (app.view) {
        AppView.dashboard => const DashboardScreen(),
        AppView.library => const LibraryScreen(),
        AppView.team => const TeamScreen(),
        AppView.setup => const SetupScreen(),
        AppView.audit => const AuditScreen(),
        AppView.summary => const SummaryScreen(),
        AppView.report => const ReportScreen(),
      };
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      drawer: Drawer(child: _Sidebar(app: app)),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CareAudit', style: TextStyle(fontSize: 11, color: AppColors.muted)),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          if (MediaQuery.sizeOf(context).width >= 600)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  app.isAdmin ? 'Submitted reports' : 'Saved locally',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Change screen background',
            icon: const Icon(Icons.palette_outlined, size: 20, color: AppColors.teal),
            onPressed: () => showThemePicker(context, app),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.teal,
                  child: Text(
                    (user.name.isNotEmpty ? user.name : user.username).substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  user.name.isNotEmpty ? user.name : user.username,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.deep),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: const BorderSide(color: Color(0x38B2604E)),
                backgroundColor: const Color(0xFFFDF4F2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.logout_rounded, size: 14),
              label: const Text('Log out', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              onPressed: () => confirmLogout(context, app),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          if (MediaQuery.sizeOf(context).width >= 980)
            SizedBox(width: 238, child: _Sidebar(app: app, inDrawer: false)),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.app, this.inDrawer = true});
  final AppState app;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    Widget item(AppView view, String label, IconData icon) {
      final active = app.view == view;
      return ListTile(
        selected: active,
        selectedTileColor: AppColors.sidebarActive,
        leading: Icon(icon, color: active ? Colors.white : AppColors.sidebarText),
        title: Text(label, style: TextStyle(color: active ? Colors.white : AppColors.sidebarText, fontSize: 13)),
        onTap: () {
          app.navigate(view);
          if (inDrawer) Navigator.of(context).maybePop();
        },
      );
    }

    final content = ColoredBox(
      color: AppColors.deep,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: InkWell(
                onTap: () {
                  app.openHome();
                  if (inDrawer) Navigator.of(context).maybePop();
                },
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: CareAuditLogo(emblemSize: 34, inverted: true),
                ),
              ),
            ),
            const Divider(color: Color(0x1CFFFFFF)),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text('WORKSPACE', style: TextStyle(color: Color(0xFF7FA69B), fontSize: 10, letterSpacing: 1.3)),
            ),
            item(AppView.dashboard, 'Overview', Icons.dashboard_outlined),
            if (app.isInspector) item(AppView.library, 'Checklist library', Icons.menu_book_outlined),
            if (app.isAdmin) item(AppView.team, 'Inspector accounts', Icons.groups_outlined),
            ListTile(
              leading: const Icon(Icons.palette_outlined, color: AppColors.sidebarText),
              title: const Text('Theme & Display', style: TextStyle(color: AppColors.sidebarText, fontSize: 13)),
              subtitle: Text(app.themeMode.label, style: const TextStyle(color: Color(0xFF7FA69B), fontSize: 10)),
              onTap: () {
                if (inDrawer) Navigator.of(context).maybePop();
                AppShell.showThemePicker(context, app);
              },
            ),
            if (app.isInspector) ...[
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C4E4A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x24BEECD3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FIELD NOTE', style: TextStyle(color: Color(0xFFB9E2C9), fontSize: 10, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      const Text('Keep the visit focused on what changes care.', style: TextStyle(color: Color(0xFFD3E8DB), fontSize: 12)),
                      const SizedBox(height: 12),
                      AppButton(
                        label: 'New inspection',
                        icon: Icons.add,
                        variant: 'light',
                        onPressed: () {
                          app.startInspection();
                          if (inDrawer) Navigator.of(context).maybePop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ] else
              const Spacer(),
            const Divider(color: Color(0x1CFFFFFF)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F322F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x1FFFFFFF)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF1E524E),
                          child: Text(
                            (app.currentUser?.name.isNotEmpty == true ? app.currentUser!.name : app.currentUser?.username ?? 'U').substring(0, 1).toUpperCase(),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF99F6E4), fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.currentUser?.name.isNotEmpty == true ? app.currentUser!.name : (app.currentUser?.username ?? 'User'),
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                app.isAdmin ? 'System Administrator' : 'Field Inspector',
                                style: const TextStyle(color: Color(0xFF7FA69B), fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFFA292),
                          backgroundColor: const Color(0x24FFA292),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.logout_rounded, size: 15),
                        label: const Text('Sign out', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        onPressed: () {
                          if (inDrawer) Navigator.of(context).maybePop();
                          AppShell.confirmLogout(context, app);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return inDrawer ? content : content;
  }
}
