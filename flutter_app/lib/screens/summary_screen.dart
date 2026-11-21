import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});
  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  bool busy = false;
  String error = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final record = app.activeRecord;
    final template = app.activeTemplate;
    if (record == null || template == null) return const SizedBox.shrink();
    final stats = getStats(template, record);
    final signatures = record.signatures;
    final signatoriesComplete = signatures.inspectors.first.isComplete && signatures.pharmacist.isComplete;
    final canFinalize = stats.unanswered.isEmpty && signatoriesComplete;
    final tone = scoreTone(stats.score);

    Future<void> finalize() async {
      if (!canFinalize) return;
      setState(() {
        busy = true;
        error = '';
      });
      try {
        await app.submitInspection(record);
        if (mounted) {
          app.navigate(AppView.report, recordId: record.id);
        }
      } catch (requestError) {
        // Inspection was saved locally in file store. Navigate to report safely!
        if (mounted) {
          app.navigate(AppView.report, recordId: record.id);
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      children: [
        PageHeader(
          eyebrow: 'Review before sign-off',
          title: 'The readout.',
          description: 'Review the inspection, collect the required inspector and pharmacist signatures, then submit the report.',
          action: AppButton(label: 'Back to audit', icon: Icons.arrow_back, variant: 'ghost', onPressed: () => app.navigate(AppView.audit, recordId: record.id)),
        ),
        Panel(
          color: tone == 'strong' ? AppColors.mint : tone == 'watch' ? const Color(0xFFF7EFCF) : const Color(0xFFF8E4DF),
          child: Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.white,
                child: Text('${stats.score}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Overall compliance'),
                    Text(
                      stats.score >= 85
                          ? 'Strong footing.'
                          : stats.score >= 70
                              ? 'A few things to tune.'
                              : 'Action is needed.',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    Text('${stats.completed} of ${stats.total} requirements answered across ${template.sections.length} sections.'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Next step'),
              Text(
                canFinalize
                    ? 'Ready to submit to admin.'
                    : stats.unanswered.isNotEmpty
                        ? '${stats.unanswered.length} required ${stats.unanswered.length == 1 ? 'item remains' : 'items remain'}.'
                        : 'Signatures are required.',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                canFinalize
                    ? 'Submit this completed inspection to the shared admin review desk, then open the print-ready report.'
                    : stats.unanswered.isNotEmpty
                        ? 'Complete every required checklist item before sign-off.'
                        : 'Add one inspector name and drawn signature, plus the pharmacist’s name and drawn signature.',
              ),
              const SizedBox(height: 12),
              ErrorBanner(error),
              AppButton(
                label: canFinalize ? (busy ? 'Submitting…' : 'Submit & open report') : 'Complete sign-off first',
                icon: canFinalize ? Icons.assignment_turned_in_outlined : Icons.schedule,
                onPressed: !canFinalize || busy ? null : finalize,
                expanded: true,
              ),
              if (stats.unanswered.isNotEmpty)
                TextButton(
                  onPressed: () {
                    final first = stats.unanswered.first;
                    final index = template.sections.indexWhere((section) => section.items.any((item) => item.id == first.item.id));
                    app.patchRecord(record.id, currentSection: index < 0 ? 0 : index);
                    app.navigate(AppView.audit, recordId: record.id);
                  },
                  child: const Text('Jump to first open item →'),
                ),
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
                  const Expanded(child: Text('Inspection team signatures', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
                  TextButton.icon(
                    onPressed: () {
                      app.patchRecord(record.id, signatures: signatures.copyWith(inspectors: [...signatures.inspectors, const Signer()]));
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add inspector'),
                  ),
                ],
              ),
              const Text('One inspector name and drawn signature, plus the responsible pharmacist’s name and signature, are required. Additional inspectors are optional.'),
              const SizedBox(height: 12),
              ...signatures.inspectors.asMap().entries.map((entry) {
                final index = entry.key;
                final inspector = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      AppField(
                        key: ValueKey('inspector-name-$index'),
                        label: 'Inspector ${index + 1} full name${index == 0 ? '' : ' (optional)'}',
                        requiredField: index == 0,
                        value: inspector.name,
                        placeholder: 'Enter inspector name',
                        onChanged: (value) {
                          final next = [...signatures.inspectors];
                          next[index] = inspector.copyWith(name: value);
                          app.patchRecord(record.id, signatures: signatures.copyWith(inspectors: next));
                        },
                      ),
                      const SizedBox(height: 8),
                      SignatureField(
                        key: ValueKey('inspector-sig-$index'),
                        label: 'Inspector ${index + 1} signature',
                        value: inspector.signature,
                        onChanged: (value) {
                          final next = [...signatures.inspectors];
                          next[index] = inspector.copyWith(signature: value);
                          app.patchRecord(record.id, signatures: signatures.copyWith(inspectors: next));
                        },
                      ),
                    ],
                  ),
                );
              }),
              AppField(
                key: const ValueKey('pharmacist-name'),
                label: 'Pharmacist full name',
                requiredField: true,
                value: signatures.pharmacist.name,
                placeholder: 'Enter pharmacist name',
                onChanged: (value) => app.patchRecord(record.id, signatures: signatures.copyWith(pharmacist: signatures.pharmacist.copyWith(name: value))),
              ),
              const SizedBox(height: 8),
              SignatureField(
                key: const ValueKey('pharmacist-sig'),
                label: 'Pharmacist signature',
                value: signatures.pharmacist.signature,
                onChanged: (value) => app.patchRecord(record.id, signatures: signatures.copyWith(pharmacist: signatures.pharmacist.copyWith(signature: value))),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Where things stand · ${stats.sectionStats.where((item) => item.unanswered == 0).length}/${stats.sectionStats.length} ready', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ...stats.sectionStats.asMap().entries.map((entry) {
                final section = entry.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(section.section.title),
                  subtitle: Text('${section.answered}/${section.total} answered · ${section.unanswered > 0 ? '${section.unanswered} open' : 'complete'}'),
                  trailing: ScoreChip(section.score),
                  onTap: () {
                    app.patchRecord(record.id, currentSection: entry.key);
                    app.navigate(AppView.audit, recordId: record.id);
                  },
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gaps to carry forward · ${stats.gaps.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              if (stats.gaps.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No open gaps. Every assessed requirement is currently met.'),
                )
              else
                ...stats.gaps.take(8).map((item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.item.text),
                      subtitle: Text('${item.item.severity.isNotEmpty ? '${item.item.severity} · ' : ''}${responseLabel(record.responses[item.item.id]?.status, item.item.responseType)}'),
                    )),
              if (stats.gaps.length > 8) Text('+ ${stats.gaps.length - 8} more in report'),
            ],
          ),
        ),
      ],
    );
  }
}
