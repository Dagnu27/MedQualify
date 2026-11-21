import 'theme.dart';

class UserAccount {
  const UserAccount({
    required this.id,
    required this.role,
    required this.name,
    required this.username,
    this.active = true,
    this.createdAt,
  });

  final String id;
  final String role;
  final String name;
  final String username;
  final bool active;
  final String? createdAt;

  bool get isAdmin => role == 'admin';
  bool get isInspector => role == 'inspector';

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      active: json['active'] != false,
      createdAt: json['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'name': name,
        'username': username,
        'active': active,
        if (createdAt != null) 'createdAt': createdAt,
      };
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    required this.responseType,
    required this.optional,
    this.severity = '',
    this.scored = true,
  });

  final String id;
  final String text;
  final String responseType;
  final bool optional;
  final String severity;
  final bool scored;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      responseType: json['responseType']?.toString() ?? 'standard',
      optional: json['optional'] == true,
      severity: json['severity']?.toString() ?? '',
      scored: json['scored'] != false,
    );
  }
}

class ChecklistSection {
  const ChecklistSection({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<ChecklistItem> items;

  factory ChecklistSection.fromJson(Map<String, dynamic> json) {
    return ChecklistSection(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => ChecklistItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

class ChecklistTemplate {
  const ChecklistTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.sourceFile,
    required this.sections,
    required this.itemCount,
  });

  final String id;
  final String title;
  final String description;
  final String sourceFile;
  final List<ChecklistSection> sections;
  final int itemCount;

  factory ChecklistTemplate.fromJson(Map<String, dynamic> json) {
    final sections = (json['sections'] as List<dynamic>? ?? [])
        .map((section) => ChecklistSection.fromJson(Map<String, dynamic>.from(section as Map)))
        .toList();
    return ChecklistTemplate(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      sourceFile: json['sourceFile']?.toString() ?? '',
      sections: sections,
      itemCount: json['itemCount'] is int
          ? json['itemCount'] as int
          : sections.fold(0, (sum, section) => sum + section.items.length),
    );
  }
}

class ItemResponse {
  const ItemResponse({this.status, this.remark = ''});

  final String? status;
  final String remark;

  Map<String, dynamic> toJson() => {
        if (status != null) 'status': status,
        'remark': remark,
      };

  factory ItemResponse.fromJson(Map<String, dynamic> json) {
    return ItemResponse(
      status: json['status']?.toString(),
      remark: json['remark']?.toString() ?? '',
    );
  }

  ItemResponse copyWith({String? status, String? remark}) {
    return ItemResponse(status: status ?? this.status, remark: remark ?? this.remark);
  }
}

class Signer {
  const Signer({this.name = '', this.signature = ''});

  final String name;
  final String signature;

  bool get isComplete =>
      name.trim().isNotEmpty && signature.startsWith('data:image/png;base64,');

  Map<String, dynamic> toJson() => {'name': name, 'signature': signature};

  factory Signer.fromJson(Map<String, dynamic>? json) {
    return Signer(
      name: json?['name']?.toString() ?? '',
      signature: json?['signature']?.toString() ?? '',
    );
  }

  Signer copyWith({String? name, String? signature}) {
    return Signer(name: name ?? this.name, signature: signature ?? this.signature);
  }
}

class InspectionSignatures {
  const InspectionSignatures({
    required this.inspectors,
    required this.pharmacist,
  });

  final List<Signer> inspectors;
  final Signer pharmacist;

  factory InspectionSignatures.empty() {
    return const InspectionSignatures(
      inspectors: [Signer()],
      pharmacist: Signer(),
    );
  }

  factory InspectionSignatures.fromJson(Map<String, dynamic>? json) {
    final saved = json ?? const {};
    final rawInspectors = saved['inspectors'];
    var inspectors = <Signer>[];
    if (rawInspectors is List) {
      inspectors = rawInspectors
          .map((item) => Signer.fromJson(item is Map ? Map<String, dynamic>.from(item) : null))
          .toList();
      inspectors = [
        for (var i = 0; i < inspectors.length; i++)
          if (i == 0 || inspectors[i].name.trim().isNotEmpty || inspectors[i].signature.isNotEmpty)
            inspectors[i],
      ];
    }
    if (inspectors.isEmpty) inspectors = [const Signer()];
    return InspectionSignatures(
      inspectors: inspectors,
      pharmacist: Signer.fromJson(
        saved['pharmacist'] is Map ? Map<String, dynamic>.from(saved['pharmacist'] as Map) : null,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'inspectors': inspectors.map((item) => item.toJson()).toList(),
        'pharmacist': pharmacist.toJson(),
      };

  InspectionSignatures copyWith({List<Signer>? inspectors, Signer? pharmacist}) {
    return InspectionSignatures(
      inspectors: inspectors ?? this.inspectors,
      pharmacist: pharmacist ?? this.pharmacist,
    );
  }
}

const defaultMeta = {
  'facilityName': '',
  'facilityAddress': '',
  'region': '',
  'zone': '',
  'woreda': '',
  'town': '',
  'kebele': '',
  'houseNo': '',
  'poBox': '',
  'contact': '',
  'ownerName': '',
  'headName': '',
  'professionalName': '',
  'profession': '',
  'licenseNo': '',
  'licenseDate': '',
  'tradeLicenseStatus': 'Not recorded',
  'yearOpened': '',
  'inspectionType': 'Routine',
  'ownership': 'Private',
  'annualLoad': '',
  'assessor': '',
  'processOwner': '',
  'notes': '',
};

class InspectionRecord {
  InspectionRecord({
    required this.id,
    required this.templateId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.submittedAt,
    this.inspectorName,
    this.currentSection = 0,
    Map<String, String>? metadata,
    Map<String, ItemResponse>? responses,
    InspectionSignatures? signatures,
  })  : metadata = {...defaultMeta, ...?metadata},
        responses = responses ?? {},
        signatures = signatures ?? InspectionSignatures.empty();

  final String id;
  String templateId;
  String status;
  final String createdAt;
  String updatedAt;
  String? completedAt;
  String? submittedAt;
  String? inspectorName;
  int currentSection;
  Map<String, String> metadata;
  Map<String, ItemResponse> responses;
  InspectionSignatures signatures;

  factory InspectionRecord.create(String templateId) {
    final now = DateTime.now().toUtc().toIso8601String();
    return InspectionRecord(
      id: 'inspection-${DateTime.now().millisecondsSinceEpoch}',
      templateId: templateId,
      status: 'draft',
      createdAt: now,
      updatedAt: now,
    );
  }

  factory InspectionRecord.fromJson(Map<String, dynamic> json) {
    final meta = <String, String>{};
    final rawMeta = json['metadata'];
    if (rawMeta is Map) {
      rawMeta.forEach((key, value) {
        meta[key.toString()] = value?.toString() ?? '';
      });
    }
    final responses = <String, ItemResponse>{};
    final rawResponses = json['responses'];
    if (rawResponses is Map) {
      rawResponses.forEach((key, value) {
        if (value is Map) {
          responses[key.toString()] = ItemResponse.fromJson(Map<String, dynamic>.from(value));
        }
      });
    }
    return InspectionRecord(
      id: json['id']?.toString() ?? '',
      templateId: json['templateId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      createdAt: json['createdAt']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      updatedAt: json['updatedAt']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      completedAt: json['completedAt']?.toString(),
      submittedAt: json['submittedAt']?.toString(),
      inspectorName: json['inspectorName']?.toString(),
      currentSection: json['currentSection'] is int ? json['currentSection'] as int : 0,
      metadata: meta,
      responses: responses,
      signatures: InspectionSignatures.fromJson(
        json['signatures'] is Map ? Map<String, dynamic>.from(json['signatures'] as Map) : null,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'status': status,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'completedAt': completedAt,
        'currentSection': currentSection,
        'metadata': metadata,
        'responses': responses.map((key, value) => MapEntry(key, value.toJson())),
        'signatures': signatures.toJson(),
        if (submittedAt != null) 'submittedAt': submittedAt,
        if (inspectorName != null) 'inspectorName': inspectorName,
      };

  InspectionRecord clone() => InspectionRecord.fromJson(toJson());
}

class FlattenedItem {
  FlattenedItem({required this.item, required this.sectionId, required this.sectionTitle});
  final ChecklistItem item;
  final String sectionId;
  final String sectionTitle;
}

class SectionStats {
  SectionStats({
    required this.section,
    required this.total,
    required this.answered,
    required this.unanswered,
    required this.score,
  });

  final ChecklistSection section;
  final int total;
  final int answered;
  final int unanswered;
  final int score;
}

class InspectionStats {
  InspectionStats({
    required this.items,
    required this.completed,
    required this.total,
    required this.unanswered,
    required this.score,
    required this.gaps,
    required this.critical,
    required this.major,
    required this.sectionStats,
  });

  final List<FlattenedItem> items;
  final int completed;
  final int total;
  final List<FlattenedItem> unanswered;
  final int score;
  final List<FlattenedItem> gaps;
  final List<FlattenedItem> critical;
  final List<FlattenedItem> major;
  final List<SectionStats> sectionStats;
}

List<FlattenedItem> flattenItems(ChecklistTemplate template) {
  return [
    for (final section in template.sections)
      for (final item in section.items)
        FlattenedItem(item: item, sectionId: section.id, sectionTitle: section.title),
  ];
}

double scoreValue(String? status) {
  if (status == 'met' || status == 'available') return 1;
  if (status == 'partial') return 0.5;
  return 0;
}

InspectionStats getStats(ChecklistTemplate template, InspectionRecord record) {
  final items = flattenItems(template);
  bool hasStatus(ChecklistItem item) => record.responses[item.id]?.status != null;
  final unanswered = items.where((item) => !item.item.optional && !hasStatus(item.item)).toList();
  bool eligible(ChecklistItem item) {
    final status = record.responses[item.id]?.status;
    return item.scored && (!item.optional || (status != null && status != 'na'));
  }

  final scoredItems = items.where((item) => eligible(item.item)).toList();
  final score = scoredItems.isEmpty
      ? 0
      : ((scoredItems.fold<double>(0, (sum, item) => sum + scoreValue(record.responses[item.item.id]?.status)) /
                  scoredItems.length) *
              100)
          .round();
  final completed = items.where((item) => hasStatus(item.item)).length;
  final gaps = items.where((item) {
    final status = record.responses[item.item.id]?.status;
    return status == 'unmet' || status == 'not-available' || (!item.item.optional && status == null);
  }).toList();
  final sectionStats = template.sections.map((section) {
    final sectionItems = section.items;
    final answered = sectionItems.where(hasStatus).length;
    final sectionUnanswered = sectionItems.where((item) => !item.optional && !hasStatus(item)).length;
    final eligibleItems = sectionItems.where(eligible).toList();
    final sectionScore = eligibleItems.isEmpty
        ? 0
        : ((eligibleItems.fold<double>(0, (sum, item) => sum + scoreValue(record.responses[item.id]?.status)) /
                    eligibleItems.length) *
                100)
            .round();
    return SectionStats(
      section: section,
      total: sectionItems.length,
      answered: answered,
      unanswered: sectionUnanswered,
      score: sectionScore,
    );
  }).toList();
  return InspectionStats(
    items: items,
    completed: completed,
    total: items.length,
    unanswered: unanswered,
    score: score,
    gaps: gaps,
    critical: gaps.where((item) => item.item.severity == 'critical').toList(),
    major: gaps.where((item) => item.item.severity == 'major').toList(),
    sectionStats: sectionStats,
  );
}

String responseLabel(String? status, String type) {
  switch (status) {
    case 'met':
      return 'Met';
    case 'partial':
      return 'Partially met';
    case 'unmet':
      return 'Unmet';
    case 'available':
      return 'Available';
    case 'not-available':
      return 'Not available';
    case 'na':
      return 'Not applicable';
    default:
      return 'Not assessed';
  }
}

String scoreTone(int score) {
  if (score >= 85) return 'strong';
  if (score >= 70) return 'watch';
  return 'risk';
}

TemplateAccent accentFor(List<ChecklistTemplate> templates, ChecklistTemplate? template) {
  final index = templates.indexWhere((item) => item.id == template?.id);
  return templateAccents[index < 0 ? 0 : index % templateAccents.length];
}

String markFor(List<ChecklistTemplate> templates, ChecklistTemplate? template) {
  final index = templates.indexWhere((item) => item.id == template?.id);
  return templateMarks[index < 0 ? 0 : index % templateMarks.length];
}

String normalizeUsername(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

String formatDate(String? value, {bool short = false}) {
  if (value == null || value.isEmpty) return '—';
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  if (short) return '${months[date.month - 1]} ${date.day}';
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String formatLongDate(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
