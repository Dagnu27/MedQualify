import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final filtered = app.templates
        .where((template) => '${template.title} ${template.description}'.toLowerCase().contains(search.toLowerCase()))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      children: [
        PageHeader(
          eyebrow: 'Source checklists',
          title: 'The library',
          description: 'Seven inspection paths, translated into one focused workspace.',
          action: AppButton(label: 'New inspection', icon: Icons.add, onPressed: () => app.startInspection()),
        ),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search facility type or checklist…',
          ),
          onChanged: (value) => setState(() => search = value),
        ),
        const SizedBox(height: 8),
        Text('Showing ${filtered.length} of ${app.templates.length}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        const SizedBox(height: 16),
        Panel(
          color: AppColors.mint,
          borderColor: const Color(0xFFCDE7D8),
          padding: const EdgeInsets.all(16),
          child: const Text('Built from your supplied documents. Each template keeps its source wording, optional requirements, response scale, and severity cues.'),
        ),
        const SizedBox(height: 16),
        ...filtered.asMap().entries.map((entry) {
          final template = entry.value;
          final index = app.templates.indexWhere((item) => item.id == template.id);
          final accent = templateAccents[index < 0 ? 0 : index % templateAccents.length];
          final standardCount = template.sections.fold<int>(0, (sum, section) => sum + section.items.where((item) => item.responseType == 'standard').length);
          final availabilityCount = template.itemCount - standardCount;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TemplateMark(templates: app.templates, template: template, large: true),
                      const Spacer(),
                      Text('0${index + 1} / ${template.itemCount.toString().padLeft(3, '0')} items', style: TextStyle(color: accent.foreground, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(template.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(template.description, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.5)),
                  const SizedBox(height: 12),
                  Text('${template.sections.length} sections · $standardCount standards${availabilityCount > 0 ? ' · $availabilityCount supplies' : ''}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => app.startInspection(template.id),
                    child: const Text('Use this checklist →'),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
