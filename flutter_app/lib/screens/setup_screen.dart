import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final record = app.activeRecord;
    final template = app.activeTemplate;
    if (record == null || template == null) return const SizedBox.shrink();
    final metadata = record.metadata;

    Future<void> setField(String field, String value) {
      return app.patchRecord(record.id, metadata: {field: value});
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      children: [
        PageHeader(
          eyebrow: 'Open a field visit',
          title: 'Set the context first.',
          description: 'A few details now make the final report much easier to trust.',
          action: AppButton(label: 'Cancel', icon: Icons.close, variant: 'ghost', onPressed: app.openHome),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('01 · Select checklist'),
              const Text('What are you assessing?', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ...app.templates.map((item) => ListTile(
                    selected: item.id == record.templateId,
                    selectedTileColor: const Color(0xFFEEF7F1),
                    leading: TemplateMark(templates: app.templates, template: item),
                    title: Text(item.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('${item.itemCount} items · ${item.sections.length} sections'),
                    trailing: item.id == record.templateId ? const Icon(Icons.check_circle, color: Color(0xFF4A9A6A)) : null,
                    onTap: () => app.patchRecord(record.id, templateId: item.id, currentSection: 0),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('02 · Facility snapshot'),
              const Text('Who is in the room?', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _field(record, 'Facility name', 'facilityName', metadata, setField, requiredField: true, placeholder: 'e.g. Selam Primary Clinic'),
              _field(record, 'Licensed professional', 'professionalName', metadata, setField, placeholder: 'Full name'),
              _field(record, 'Profession', 'profession', metadata, setField, placeholder: 'e.g. General Practitioner'),
              _field(record, 'Region', 'region', metadata, setField),
              _field(record, 'Zone', 'zone', metadata, setField),
              _field(record, 'Woreda', 'woreda', metadata, setField),
              _field(record, 'Town', 'town', metadata, setField),
              _field(record, 'Kebele', 'kebele', metadata, setField),
              _field(record, 'House number', 'houseNo', metadata, setField),
              _field(record, 'Head / director', 'headName', metadata, setField, placeholder: 'Full name'),
              _field(record, 'Owner name (including grandfather\'s name)', 'ownerName', metadata, setField, placeholder: 'Full name'),
              _field(record, 'Facility license no.', 'licenseNo', metadata, setField, placeholder: 'Optional'),
              _field(record, 'Facility license date', 'licenseDate', metadata, setField, placeholder: 'Date'),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppSelect(
                  label: 'Valid trade license?',
                  value: metadata['tradeLicenseStatus'] ?? 'Not recorded',
                  options: const ['Not recorded', 'Yes', 'No'],
                  onChanged: (value) => setField('tradeLicenseStatus', value),
                ),
              ),
              _field(record, 'Year opened', 'yearOpened', metadata, setField, placeholder: 'YYYY'),
              _field(record, 'Phone', 'contact', metadata, setField, placeholder: 'Phone number'),
              _field(record, 'P.O. Box', 'poBox', metadata, setField),
              _field(record, 'Annual patient load', 'annualLoad', metadata, setField, placeholder: 'Optional'),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppSelect(
                  label: 'Inspection type',
                  value: metadata['inspectionType'] ?? 'Routine',
                  options: const ['Initial / New', 'Routine', 'Follow-up', 'Investigative'],
                  onChanged: (value) => setField('inspectionType', value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppSelect(
                  label: 'Ownership',
                  value: metadata['ownership'] ?? 'Private',
                  options: const ['Private', 'Governmental', 'Non-governmental'],
                  onChanged: (value) => setField('ownership', value),
                ),
              ),
              _field(record, 'Lead assessor', 'assessor', metadata, setField, placeholder: 'Your name'),
              _field(record, 'Process owner name', 'processOwner', metadata, setField, placeholder: 'Full name'),
              _field(record, 'Visit note', 'notes', metadata, setField, placeholder: 'A short context note for the report', maxLines: 3),
              const Divider(),
              const SizedBox(height: 8),
              Text(template.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Ready for ${template.itemCount} source requirements', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
              const SizedBox(height: 12),
              AppButton(
                label: 'Open audit workspace',
                icon: Icons.arrow_forward,
                onPressed: (metadata['facilityName'] ?? '').trim().isEmpty
                    ? null
                    : () => app.openAudit(record.id),
                expanded: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(
    InspectionRecord record,
    String label,
    String key,
    Map<String, String> metadata,
    Future<void> Function(String, String) setField, {
    bool requiredField = false,
    String? placeholder,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppField(
        key: ValueKey('${record.id}-$key'),
        label: label,
        requiredField: requiredField,
        value: metadata[key] ?? '',
        placeholder: placeholder,
        maxLines: maxLines,
        onChanged: (value) => setField(key, value),
      ),
    );
  }
}
