import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../report_exporter.dart';
import '../theme.dart';
import '../widgets.dart';
import 'summary_screen.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String downloadBusy = '';
  String downloadError = '';

  Future<void> _export(ChecklistTemplate template, InspectionRecord record, String format) async {
    setState(() {
      downloadBusy = format;
      downloadError = '';
    });
    try {
      await ReportExporter.shareReport(
        context: context,
        template: template,
        record: record,
        format: format,
      );
    } catch (error) {
      setState(() => downloadError = 'Export error: $error');
    } finally {
      if (mounted) setState(() => downloadBusy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final record = app.activeRecord;
    final template = app.activeTemplate;
    if (record == null || template == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('This inspection is no longer available.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          AppButton(label: 'Back to overview', icon: Icons.home_outlined, onPressed: app.openHome),
        ],
      );
    }
    if (record.status != 'completed') {
      return const SummaryScreen();
    }
    final stats = getStats(template, record);
    final address = record.metadata['facilityAddress']?.isNotEmpty == true
        ? record.metadata['facilityAddress']!
        : [
            record.metadata['region'],
            record.metadata['zone'],
            record.metadata['woreda'],
            record.metadata['town'],
            record.metadata['kebele'],
          ].where((item) => item != null && item.isNotEmpty).join(' · ');
    final signatures = record.signatures;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton(
              label: app.isAdmin ? 'Back to submitted reports' : 'Back to summary',
              icon: Icons.arrow_back,
              variant: 'ghost',
              onPressed: app.isAdmin ? app.openHome : () => app.navigate(AppView.summary, recordId: record.id),
            ),
            if (!app.isAdmin)
              AppButton(label: 'Edit inspection', icon: Icons.edit_outlined, variant: 'ghost', onPressed: () => app.navigate(AppView.audit, recordId: record.id)),
            AppButton(
              label: downloadBusy == 'pdf' ? 'Preparing…' : 'Share PDF',
              icon: Icons.picture_as_pdf_outlined,
              onPressed: downloadBusy.isNotEmpty ? null : () => _export(template, record, 'pdf'),
            ),
            AppButton(
              label: downloadBusy == 'xlsx' ? 'Preparing…' : 'Share Excel',
              icon: Icons.table_chart_outlined,
              variant: 'secondary',
              onPressed: downloadBusy.isNotEmpty ? null : () => _export(template, record, 'xlsx'),
            ),
            AppButton(
              label: downloadBusy == 'docx' ? 'Preparing…' : 'Share Word',
              icon: Icons.description_outlined,
              variant: 'ghost',
              onPressed: downloadBusy.isNotEmpty ? null : () => _export(template, record, 'docx'),
            ),
            AppButton(
              label: 'Print',
              icon: Icons.print_outlined,
              variant: 'ghost',
              onPressed: () => ReportExporter.printReport(template: template, record: record),
            ),
          ],
        ),
        ErrorBanner(downloadError),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('FINAL INSPECTION REPORT', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700))),
                  ScoreChip(stats.score),
                ],
              ),
              const SizedBox(height: 8),
              Eyebrow(template.title),
              Text(record.metadata['facilityName']?.isNotEmpty == true ? record.metadata['facilityName']! : 'Untitled facility', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              Text('${address.isEmpty ? 'Address not supplied' : address} · ${record.metadata['inspectionType']} visit · completed ${formatDate(record.completedAt ?? record.updatedAt)}', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _meta('Licensed professional', [record.metadata['professionalName'], record.metadata['profession']].where((item) => item != null && item.isNotEmpty).join(' · ')),
                  _meta('Facility head', record.metadata['headName']),
                  _meta('Owner / operator', record.metadata['ownerName']),
                  _meta('Facility license no. / date', [record.metadata['licenseNo'], record.metadata['licenseDate']].where((item) => item != null && item.isNotEmpty).join(' · ')),
                  _meta('Valid trade license', record.metadata['tradeLicenseStatus']),
                  _meta('Lead assessor', record.metadata['assessor']),
                  _meta('Phone / P.O. Box', [record.metadata['contact'], record.metadata['poBox']].where((item) => item != null && item.isNotEmpty).join(' · ')),
                  _meta('Annual patient load', record.metadata['annualLoad']),
                  _meta('House number', record.metadata['houseNo']),
                ],
              ),
              const SizedBox(height: 16),
              Panel(
                color: AppColors.mint,
                padding: const EdgeInsets.all(14),
                child: Text(
                  '${stats.score >= 85 ? 'Strong footing with targeted follow-up.' : stats.score >= 70 ? 'Compliant in many areas, with follow-up required.' : 'Material gaps require a documented action plan.'}\n${stats.critical.length} critical markers · ${stats.major.length} major markers · ${stats.unanswered.length} unanswered requirements',
                ),
              ),
              const SizedBox(height: 20),
              const Text('01  Section scores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ...stats.sectionStats.map((section) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(section.section.title),
                    subtitle: Text('${section.answered}/${section.total} answered'),
                    trailing: ScoreChip(section.score),
                  )),
              const SizedBox(height: 12),
              const Text('02  Attention markers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              if (stats.gaps.isEmpty)
                const Text('No gaps recorded in this inspection.')
              else
                ...stats.gaps.map((item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text((item.item.severity.isEmpty ? 'open' : item.item.severity).toUpperCase(), style: const TextStyle(fontSize: 10, color: AppColors.goldInk)),
                      title: Text(item.item.text),
                      subtitle: Text('${item.sectionTitle} · ${responseLabel(record.responses[item.item.id]?.status, item.item.responseType)}${(record.responses[item.item.id]?.remark ?? '').isNotEmpty ? ' · ${record.responses[item.item.id]!.remark}' : ''}'),
                    )),
              const SizedBox(height: 12),
              const Text('03  Assessment detail', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ...template.sections.map((section) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text(section.title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.teal)),
                      ...section.items.map((item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(item.text, style: const TextStyle(fontSize: 13)),
                            subtitle: (record.responses[item.id]?.remark ?? '').isNotEmpty ? Text('Remark: ${record.responses[item.id]!.remark}') : null,
                            trailing: Text(responseLabel(record.responses[item.id]?.status, item.responseType), style: const TextStyle(fontSize: 11)),
                          )),
                    ],
                  )),
              const SizedBox(height: 12),
              const Text('04  Visit notes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(record.metadata['notes']?.isNotEmpty == true ? record.metadata['notes']! : 'No additional visit note was recorded.'),
              const SizedBox(height: 16),
              ...signatures.inspectors.asMap().entries.map((entry) => _signer('Inspector ${entry.key + 1}', entry.value)),
              _signer('Pharmacist', signatures.pharmacist),
              _meta('Process owner', record.metadata['processOwner']),
              _meta('Lead assessor', record.metadata['assessor']),
              _meta('Date', formatDate(record.completedAt ?? record.updatedAt)),
              const SizedBox(height: 16),
              Text('CareAudit · Source checklist: ${template.sourceFile}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _meta(String label, String? value) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, color: AppColors.muted, letterSpacing: 0.8)),
          Text((value == null || value.isEmpty) ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _signer(String role, Signer signer) {
    Widget image;
    if (signer.signature.startsWith('data:image/png;base64,')) {
      try {
        image = Image.memory(
          Uri.parse(signer.signature).data!.contentAsBytes(),
          height: 48,
        );
      } catch (_) {
        image = const Text('No signature recorded', style: TextStyle(color: AppColors.muted, fontSize: 11));
      }
    } else {
      image = const Text('No signature recorded', style: TextStyle(color: AppColors.muted, fontSize: 11));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(role, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          Text(signer.name.isEmpty ? '—' : signer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          image,
        ],
      ),
    );
  }
}
