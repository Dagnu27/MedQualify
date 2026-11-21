import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterMode = 'all'; // 'all', 'unanswered', 'gaps', 'critical'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filterMode = 'all';
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final record = app.activeRecord;
    final template = app.activeTemplate;
    if (record == null || template == null) return const SizedBox.shrink();
    final stats = getStats(template, record);
    final currentIndex = (record.currentSection).clamp(0, template.sections.length - 1);
    final section = template.sections[currentIndex];
    final sectionStat = stats.sectionStats[currentIndex];
    final totalProgress = stats.total == 0 ? 0 : ((stats.completed / stats.total) * 100).round();

    Future<void> setResponse(ChecklistItem item, String status) {
      final next = Map<String, ItemResponse>.from(record.responses);
      final current = next[item.id] ?? const ItemResponse();
      next[item.id] = current.copyWith(status: status);
      return app.patchRecord(record.id, responses: next);
    }

    Future<void> setRemark(ChecklistItem item, String remark) {
      final next = Map<String, ItemResponse>.from(record.responses);
      final current = next[item.id] ?? const ItemResponse();
      next[item.id] = current.copyWith(remark: remark);
      return app.patchRecord(record.id, responses: next);
    }

    // Evaluate search and filter across all items
    final isFiltering = _searchQuery.isNotEmpty || _filterMode != 'all';
    final List<({ChecklistSection section, ChecklistItem item, int sectionIndex})> matchingItems = [];

    if (isFiltering) {
      for (var sIdx = 0; sIdx < template.sections.length; sIdx++) {
        final sec = template.sections[sIdx];
        for (final item in sec.items) {
          final res = record.responses[item.id];
          final hasStatus = res?.status != null && res!.status!.isNotEmpty;
          final isGap = res?.status == 'unmet' || res?.status == 'not-available' || res?.status == 'partial';

          // Apply filter mode
          if (_filterMode == 'unanswered' && hasStatus) continue;
          if (_filterMode == 'gaps' && !isGap) continue;
          if (_filterMode == 'critical' && item.severity != 'critical' && item.severity != 'major') continue;

          // Apply keyword search
          if (_searchQuery.isNotEmpty) {
            final textMatch = item.text.toLowerCase().contains(_searchQuery);
            final secMatch = sec.title.toLowerCase().contains(_searchQuery);
            final remarkMatch = (res?.remark ?? '').toLowerCase().contains(_searchQuery);
            if (!textMatch && !secMatch && !remarkMatch) continue;
          }

          matchingItems.add((section: sec, item: item, sectionIndex: sIdx));
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: [
        TextButton.icon(
          onPressed: app.openHome,
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('All inspections'),
        ),
        Row(
          children: [
            TemplateMark(templates: app.templates, template: template),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow('${record.metadata['facilityName']?.isNotEmpty == true ? record.metadata['facilityName'] : 'Untitled facility'} · ${record.metadata['inspectionType']}'),
                  Text(template.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('${stats.completed} / ${stats.total} answered · $totalProgress%', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: totalProgress / 100, color: AppColors.teal, backgroundColor: const Color(0xFFDCE7E1)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'View summary & sign-off',
            icon: Icons.bar_chart,
            variant: 'secondary',
            onPressed: () => app.navigate(AppView.summary, recordId: record.id),
          ),
        ),
        const SizedBox(height: 16),

        // SEARCH & QUICK FILTER BAR
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isFiltering ? AppColors.teal : AppColors.line, width: isFiltering ? 1.5 : 1),
            boxShadow: const [
              BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search requirements (e.g. storage, license, fridge)…',
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.teal),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('all', 'All Items', Icons.list_alt_rounded),
                    const SizedBox(width: 6),
                    _filterChip('unanswered', 'Unanswered (${stats.unanswered.length})', Icons.help_outline_rounded),
                    const SizedBox(width: 6),
                    _filterChip('gaps', 'Gaps / Unmet (${stats.gaps.length})', Icons.warning_amber_rounded),
                    const SizedBox(width: 6),
                    _filterChip('critical', 'Critical / Major', Icons.priority_high_rounded),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // FILTERED RESULTS VIEW
        if (isFiltering) ...[
          Row(
            children: [
              Text(
                'Showing ${matchingItems.length} matching requirement${matchingItems.length == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.deep),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearSearch,
                child: const Text('Reset search & filters', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (matchingItems.isEmpty)
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.search_off_rounded, size: 40, color: AppColors.muted),
                    const SizedBox(height: 8),
                    const Text('No requirements match your search', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 4),
                    const Text('Try different keywords or reset your filter chips.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
                      onPressed: _clearSearch,
                      child: const Text('Clear Filters'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...matchingItems.map((entry) {
              final sec = entry.section;
              final item = entry.item;
              final res = record.responses[item.id];
              return _buildItemCard(
                item: item,
                response: res,
                recordId: record.id,
                sectionTitle: 'Section ${entry.sectionIndex + 1}: ${sec.title}',
                setResponse: (status) => setResponse(item, status),
                setRemark: (remark) => setRemark(item, remark),
              );
            }),
        ] else ...[
          // REGULAR SECTION VIEW
          Panel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Visit sections'),
                const Text('Walk the standard', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                ...template.sections.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final s = stats.sectionStats[index];
                  return ListTile(
                    selected: index == currentIndex,
                    selectedTileColor: const Color(0xFFEDF7F0),
                    title: Text(item.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    subtitle: Text('${s.answered}/${s.total} answered'),
                    trailing: s.unanswered == 0 ? const Icon(Icons.check_circle, color: Color(0xFF53A474), size: 16) : null,
                    onTap: () => app.patchRecord(record.id, currentSection: index),
                  );
                }),
                const Divider(),
                const Text('Scoring note: Optional items are excluded unless you mark them applicable.', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Eyebrow('Section ${currentIndex + 1} / ${template.sections.length}'),
          Text(section.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          Text('${sectionStat.answered} answered · ${sectionStat.unanswered} required remaining · ${sectionStat.score}% section score', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          ...section.items.asMap().entries.map((entry) {
            final item = entry.value;
            final response = record.responses[item.id];
            return _buildItemCard(
              item: item,
              response: response,
              recordId: record.id,
              index: entry.key,
              setResponse: (status) => setResponse(item, status),
              setRemark: (remark) => setRemark(item, remark),
            );
          }),
          Row(
            children: [
              AppButton(
                label: 'Previous',
                icon: Icons.arrow_back,
                variant: 'ghost',
                onPressed: currentIndex == 0 ? null : () => app.patchRecord(record.id, currentSection: currentIndex - 1),
              ),
              const Spacer(),
              if (currentIndex < template.sections.length - 1)
                AppButton(label: 'Next section', icon: Icons.arrow_forward, onPressed: () => app.patchRecord(record.id, currentSection: currentIndex + 1))
              else
                AppButton(label: 'Review inspection', icon: Icons.bar_chart, onPressed: () => app.navigate(AppView.summary, recordId: record.id)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _filterChip(String mode, String label, IconData icon) {
    final active = _filterMode == mode;
    return InkWell(
      onTap: () => setState(() => _filterMode = mode),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.teal : const Color(0xFFF1F5F3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? Colors.white : AppColors.inkSoft),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Colors.white : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard({
    required ChecklistItem item,
    required ItemResponse? response,
    required String recordId,
    int? index,
    String? sectionTitle,
    required ValueChanged<String> setResponse,
    required ValueChanged<String> setRemark,
  }) {
    final options = item.responseType == 'availability'
        ? const [('available', 'Available'), ('not-available', 'Not available')]
        : const [('met', 'Met'), ('partial', 'Partially met'), ('unmet', 'Unmet')];
    final hasGap = response?.status == 'unmet' || response?.status == 'not-available';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.all(16),
        borderColor: hasGap ? const Color(0xFFDF927E) : AppColors.line,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sectionTitle != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFE2EFE9), borderRadius: BorderRadius.circular(4)),
                child: Text(sectionTitle, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.teal)),
              ),
            ],
            Row(
              children: [
                if (index != null)
                  Text((index + 1).toString().padLeft(2, '0'), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                const Spacer(),
                if (item.severity.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: item.severity == 'critical'
                          ? const Color(0xFFF8DED8)
                          : item.severity == 'major'
                              ? const Color(0xFFF8EBC5)
                              : const Color(0xFFE8EEF6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(item.severity.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                if (item.optional)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFF0E7F5), borderRadius: BorderRadius.circular(4)),
                    child: const Text('OPTIONAL', style: TextStyle(fontSize: 9)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.text, style: const TextStyle(height: 1.45, fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in options)
                  _responseButton(option.$1, option.$2, response?.status, () => setResponse(option.$1)),
                if (item.optional)
                  _responseButton('na', 'Not applicable', response?.status, () => setResponse('na')),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('$recordId-${item.id}-remark'),
              initialValue: response?.remark ?? '',
              decoration: const InputDecoration(
                hintText: 'Add a remark, evidence note, or follow-up…',
                prefixIcon: Icon(Icons.edit_outlined, size: 16),
                isDense: true,
              ),
              onChanged: setRemark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _responseButton(String status, String label, String? selected, VoidCallback onTap) {
    final active = selected == status;
    Color bg = const Color(0xFFFBFDFB);
    Color fg = AppColors.inkSoft;
    Color border = AppColors.line;
    if (active) {
      if (status == 'met' || status == 'available') {
        bg = const Color(0xFFE2F2E7);
        fg = const Color(0xFF33784E);
        border = const Color(0xFFABD6B9);
      } else if (status == 'partial') {
        bg = const Color(0xFFF9F0D0);
        fg = const Color(0xFF8D7028);
        border = const Color(0xFFE5D18B);
      } else if (status == 'unmet' || status == 'not-available') {
        bg = const Color(0xFFF9E3DF);
        fg = const Color(0xFFA55140);
        border = const Color(0xFFE3AFA4);
      } else {
        bg = const Color(0xFFF0E7F4);
        fg = const Color(0xFF71587E);
        border = const Color(0xFFD5C0DF);
      }
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) Icon(Icons.check, size: 14, color: fg),
            if (active) const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
