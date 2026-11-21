import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final filters = {
    'facility': '',
    'inspector': '',
    'checklist': '',
    'region': '',
    'inspectionType': '',
    'ownership': '',
    'score': '',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isAdmin = app.isAdmin;
    final drafts = isAdmin ? <InspectionRecord>[] : app.records.where((record) => record.status == 'draft').toList();
    final completed = app.records.where((record) => record.status == 'completed').toList();
    final recentSorted = isAdmin
        ? ([...completed]..sort((a, b) => (b.submittedAt ?? b.completedAt ?? b.updatedAt).compareTo(a.submittedAt ?? a.completedAt ?? a.updatedAt)))
        : ([...app.records]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));
    final recent = recentSorted;
    final recentLimited = isAdmin ? recent : recent.take(5).toList();
    final filtered = isAdmin ? recentLimited.where(_matches).toList() : recentLimited;
    final average = completed.isEmpty
        ? null
        : (completed.fold<int>(0, (sum, record) {
              final template = app.templateFor(record);
              return sum + (template == null ? 0 : getStats(template, record).score);
            }) /
            completed.length)
            .round();
    final gaps = completed.fold<int>(0, (sum, record) {
      final template = app.templateFor(record);
      if (template == null) return sum;
      final stats = getStats(template, record);
      return sum + stats.critical.length + stats.major.length;
    });

    final screenWidth = MediaQuery.sizeOf(context).width;
    final statWidth = screenWidth < 520
        ? (screenWidth - 40 - 12) / 2
        : screenWidth < 960
            ? (screenWidth - 40 - 24) / 3
            : 220.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      children: [
        if (app.isInspector && app.pendingSyncCount > 0) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
              boxShadow: const [
                BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cloud_off_rounded, color: Color(0xFFD97706), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${app.pendingSyncCount} completed inspection(s) stored locally',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF92400E)),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Data is saved on your device. Sync anytime when your database server is turned on.',
                        style: TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: app.syncing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded, size: 16),
                  label: Text(app.syncing ? 'Syncing…' : 'Sync to Database', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: app.syncing ? null : () => app.syncPendingInspections(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (app.syncMessage.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB9E5CF)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    app.syncMessage,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.deep),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: AppColors.teal),
                  onPressed: app.clearSyncMessage,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (!isAdmin && drafts.isNotEmpty) ...[
          Builder(builder: (context) {
            final activeDraft = drafts.first;
            final draftTemplate = app.templateFor(activeDraft);
            final draftStats = draftTemplate != null ? getStats(draftTemplate, activeDraft) : null;
            final progress = draftStats == null || draftStats.total == 0 ? 0 : ((draftStats.completed / draftStats.total) * 100).round();
            final facName = activeDraft.metadata['facilityName']?.isNotEmpty == true ? activeDraft.metadata['facilityName']! : 'Untitled facility';

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
                boxShadow: const [
                  BoxShadow(color: Color(0x0C000000), blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2F2E7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('IN-PROGRESS DRAFT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2E6944))),
                      ),
                      const Spacer(),
                      Text('Last edited ${formatDate(activeDraft.updatedAt, short: true)}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(facName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deep)),
                  Text('${draftTemplate?.title ?? 'Audit'} · ${activeDraft.metadata['inspectionType'] ?? 'Routine'}', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              draftStats != null
                                  ? '${draftStats.completed} of ${draftStats.total} answered ($progress%)'
                                  : '$progress% complete',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.teal),
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: progress / 100, color: AppColors.teal, backgroundColor: const Color(0xFFE0EAE5)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Resume', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        onPressed: () => app.navigate(AppView.audit, recordId: activeDraft.id),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
        Panel(
          color: const Color(0xFFE5F1E9),
          borderColor: const Color(0xFFD4E6DC),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('${isAdmin ? 'Admin review desk' : 'Regulatory workspace'} · ${formatLongDate(DateTime.now())}'),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700, height: 1.02, color: AppColors.deep),
                  children: isAdmin
                      ? const [TextSpan(text: 'Reports that\n'), TextSpan(text: 'move care.', style: TextStyle(color: AppColors.teal))]
                      : const [TextSpan(text: 'Make every room\n'), TextSpan(text: 'count.', style: TextStyle(color: AppColors.teal))],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isAdmin
                    ? 'Receive completed inspections from the field, review the evidence, and generate a print-ready PDF report.'
                    : 'One clear view of facility readiness, from first walkthrough to final sign-off.',
                style: const TextStyle(color: Color(0xFF57716A), height: 1.5),
              ),
              const SizedBox(height: 18),
              if (isAdmin)
                const Chip(
                  avatar: Icon(Icons.verified, size: 16, color: AppColors.teal),
                  label: Text('Inspectors submit · admins issue reports'),
                  backgroundColor: Colors.white,
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    AppButton(label: 'Start an inspection', icon: Icons.add, onPressed: () => app.startInspection()),
                    AppButton(label: 'Browse checklists', icon: Icons.menu_book_outlined, variant: 'ghost', onPressed: () => app.navigate(AppView.library)),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _stat(Icons.edit_outlined, isAdmin ? 'Awaiting review' : 'Active drafts', '${isAdmin ? completed.length : drafts.length}', isAdmin ? 'submitted by inspectors' : (drafts.isEmpty ? 'nothing waiting in the wings' : 'pick up where you left off'), const Color(0xFF267D76), statWidth),
            _stat(Icons.verified_outlined, isAdmin ? 'Reports ready' : 'Completed visits', '${completed.length}', average == null ? 'no submitted reports yet' : '$average% average compliance', const Color(0xFFA47B25), statWidth),
            _stat(Icons.menu_book_outlined, isAdmin ? 'PDF output' : 'Templates ready', isAdmin ? 'READY' : '${app.templates.length}', isAdmin ? 'print or save from each report' : 'built from supplied source checklists', const Color(0xFF805D91), statWidth),
            _stat(Icons.bar_chart, 'Open gaps', '$gaps', 'across completed inspections', const Color(0xFFB6654F), statWidth),
          ],
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow(isAdmin ? 'Inspector submissions' : 'Your field log'),
                        Text(isAdmin ? 'All reports received' : 'Recent inspections', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  if (isAdmin) Text('${filtered.length} of ${recentLimited.length} reports', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                ],
              ),
              if (isAdmin && !app.recordsLoading && recentLimited.isNotEmpty) ...[
                const SizedBox(height: 16),
                _filters(app, recentLimited),
              ],
              const SizedBox(height: 8),
              if (app.recordsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Column(children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Loading submitted reports.')])),
                )
              else if (recentLimited.isEmpty)
                _empty(isAdmin, app)
              else if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No matching reports.')),
                )
              else
                ...filtered.map((record) => _row(app, record, isAdmin)),
            ],
          ),
        ),
      ],
    );
  }

  bool _matches(InspectionRecord record) {
    final app = context.read<AppState>();
    final template = app.templateFor(record);
    final facility = record.metadata['facilityName'] ?? '';
    final score = template == null ? 0 : getStats(template, record).score;
    final scoreFilter = filters['score']!;
    final matchesScore = scoreFilter.isEmpty ||
        (scoreFilter == 'strong' && score >= 85) ||
        (scoreFilter == 'watch' && score >= 70 && score < 85) ||
        (scoreFilter == 'attention' && score < 70);
    return facility.toLowerCase().contains(filters['facility']!.trim().toLowerCase()) &&
        (filters['inspector']!.isEmpty || record.inspectorName == filters['inspector']) &&
        (filters['checklist']!.isEmpty || template?.id == filters['checklist']) &&
        (filters['region']!.isEmpty || record.metadata['region'] == filters['region']) &&
        (filters['inspectionType']!.isEmpty || record.metadata['inspectionType'] == filters['inspectionType']) &&
        (filters['ownership']!.isEmpty || record.metadata['ownership'] == filters['ownership']) &&
        matchesScore;
  }

  Widget _filters(AppState app, List<InspectionRecord> recent) {
    List<String> field(String key) {
      final values = recent
          .map((record) => record.metadata[key])
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      return values;
    }

    final inspectors = recent.map((record) => record.inspectorName).whereType<String>().where((item) => item.isNotEmpty).toSet().toList()..sort();
    final checklists = app.templates.where((template) => recent.any((record) => record.templateId == template.id)).toList();
    Widget select(String label, String key, List<String> options, {List<({String value, String label})>? labeled}) {
      final items = labeled ?? options.map((item) => (value: item, label: item)).toList();
      final current = filters[key]!;
      String selectedLabel = 'All';
      if (current.isNotEmpty) {
        selectedLabel = items.firstWhere((item) => item.value == current, orElse: () => (value: current, label: current)).label;
      }
      return AppSelect(
        label: label,
        value: selectedLabel,
        options: ['All', ...items.map((item) => item.label)],
        onChanged: (value) {
          setState(() {
            if (value == 'All') {
              filters[key] = '';
            } else if (labeled != null) {
              filters[key] = labeled.firstWhere((item) => item.label == value).value;
            } else {
              filters[key] = value;
            }
          });
        },
      );
    }

    return Column(
      children: [
        AppField(label: 'Facility name', value: filters['facility']!, onChanged: (value) => setState(() => filters['facility'] = value), placeholder: 'Search facility'),
        const SizedBox(height: 10),
        select('Inspector', 'inspector', inspectors),
        const SizedBox(height: 10),
        select(
          'Checklist / facility type',
          'checklist',
          const [],
          labeled: checklists.map((template) => (value: template.id, label: template.title)).toList(),
        ),
        const SizedBox(height: 10),
        select('Region', 'region', field('region')),
        const SizedBox(height: 10),
        select('Inspection type', 'inspectionType', field('inspectionType')),
        const SizedBox(height: 10),
        select('Ownership', 'ownership', field('ownership')),
        const SizedBox(height: 10),
        select(
          'Compliance score',
          'score',
          const [],
          labeled: const [
            (value: 'strong', label: 'Strong · 85%+'),
            (value: 'watch', label: 'Watch · 70–84%'),
            (value: 'attention', label: 'Needs attention · below 70%'),
          ],
        ),
        if (filters.values.any((item) => item.isNotEmpty))
          TextButton(
            onPressed: () => setState(() {
              for (final key in filters.keys) {
                filters[key] = '';
              }
            }),
            child: const Text('Clear filters'),
          ),
      ],
    );
  }

  Widget _row(AppState app, InspectionRecord record, bool isAdmin) {
    final template = app.templateFor(record);
    final stats = template == null ? null : getStats(template, record);
    return InkWell(
      onTap: () => app.openAudit(record.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            TemplateMark(templates: app.templates, template: template),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.metadata['facilityName']?.isNotEmpty == true ? record.metadata['facilityName']! : 'Untitled facility', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    [
                      template?.title ?? 'Unknown checklist',
                      if (isAdmin) record.inspectorName ?? 'Unknown inspector',
                      '${isAdmin ? 'Submitted' : 'Edited'} ${formatDate(isAdmin ? record.submittedAt ?? record.completedAt ?? record.updatedAt : record.updatedAt, short: true)}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            if (stats != null) ScoreChip(stats.score),
            const SizedBox(width: 8),
            StatusPill(record.status, isSynced: record.submittedAt != null),
            if (!isAdmin)
              IconButton(
                onPressed: () => app.removeRecord(record.id),
                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value, String note, Color tone, double width) {
    return SizedBox(
      width: width,
      child: Panel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            Text(note, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _empty(bool admin, AppState app) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Text(admin ? 'No submitted reports yet.' : 'Your field log is clear.', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            admin ? 'Completed inspections will appear here after an inspector submits a visit.' : 'Start your first visit and your inspections will gather here, ready for the next handoff.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkSoft),
          ),
          if (!admin) ...[
            const SizedBox(height: 16),
            AppButton(label: 'Start first inspection', icon: Icons.add, variant: 'secondary', onPressed: () => app.startInspection()),
          ],
        ],
      ),
    );
  }
}
