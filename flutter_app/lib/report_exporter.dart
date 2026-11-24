import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';

class ReportExporter {
  static Uint8List? _decodeBase64Image(String? dataUri) {
    if (dataUri == null || !dataUri.contains('base64,')) return null;
    try {
      final base64Str = dataUri.split('base64,').last.trim();
      return base64Decode(base64Str);
    } catch (_) {
      return null;
    }
  }

  static String safeFileName(InspectionRecord record) {
    final raw = (record.metadata['facilityName'] ?? 'inspection')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return raw.isEmpty ? 'inspection' : raw;
  }

  /// Generates a comprehensive, multi-page regulatory inspection PDF completely on-device.
  static Future<Uint8List> generatePdf(ChecklistTemplate template, InspectionRecord record) async {
    final stats = getStats(template, record);
    final pdf = pw.Document();
    final metadata = record.metadata;

    final primaryColor = PdfColor.fromHex('0B6B67');
    final darkColor = PdfColor.fromHex('143C3A');
    final mutedColor = PdfColor.fromHex('71817D');
    final mintColor = PdfColor.fromHex('DFF1E7');
    final criticalColor = PdfColor.fromHex('B2604E');
    final majorColor = PdfColor.fromHex('B45309');

    final pharmacistSigBytes = _decodeBase64Image(record.signatures.pharmacist.signature);
    final inspectorSigBytes = record.signatures.inspectors.isNotEmpty
        ? _decodeBase64Image(record.signatures.inspectors.first.signature)
        : null;

    final facilityName = metadata['facilityName']?.isNotEmpty == true
        ? metadata['facilityName']!
        : 'Untitled facility';

    final location = [
      metadata['region'],
      metadata['zone'],
      metadata['woreda'],
      metadata['town'],
      metadata['kebele'],
      metadata['houseNo'],
    ].where((s) => s != null && s.isNotEmpty).join(' · ');

    final completedDate = formatDate(record.completedAt ?? record.updatedAt);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('CareAudit · FACILITY COMPLIANCE SYSTEM',
                  style: pw.TextStyle(color: primaryColor, fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(color: mutedColor, fontSize: 8)),
            ],
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 8),
          // Title & Overall Score Banner
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: mintColor,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 52,
                  height: 52,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.white,
                    shape: pw.BoxShape.circle,
                  ),
                  child: pw.Center(
                    child: pw.Text('${stats.score}%',
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: darkColor)),
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('FINAL INSPECTION REPORT',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                      pw.Text(facilityName,
                          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: darkColor)),
                      pw.Text('${template.title} · ${metadata['inspectionType'] ?? 'Routine'} Visit · Completed $completedDate',
                          style: pw.TextStyle(fontSize: 9, color: darkColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Metadata Grid
          pw.Text('FACILITY & VISIT INFORMATION',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey200, width: 0.5),
            children: [
              pw.TableRow(
                children: [
                  _pdfMetaCell('Facility Address', metadata['facilityAddress'] ?? location),
                  _pdfMetaCell('Lead Assessor', metadata['assessor'] ?? '—'),
                  _pdfMetaCell('Facility Head', metadata['headName'] ?? '—'),
                ],
              ),
              pw.TableRow(
                children: [
                  _pdfMetaCell('Licensed Professional', '${metadata['professionalName'] ?? '—'} (${metadata['profession'] ?? ''})'),
                  _pdfMetaCell('License No. / Date', '${metadata['licenseNo'] ?? '—'} · ${metadata['licenseDate'] ?? ''}'),
                  _pdfMetaCell('Valid Trade License', metadata['tradeLicenseStatus'] ?? '—'),
                ],
              ),
              pw.TableRow(
                children: [
                  _pdfMetaCell('Owner / Operator', metadata['ownerName'] ?? '—'),
                  _pdfMetaCell('Contact / Phone', metadata['contact'] ?? '—'),
                  _pdfMetaCell('Annual Patient Load', metadata['annualLoad'] ?? '—'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // Section Scores
          pw.Text('01 · SECTION BREAKDOWN',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey200, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _pdfHeaderCell('Section Title'),
                  _pdfHeaderCell('Requirements Met', align: pw.TextAlign.center),
                  _pdfHeaderCell('Score', align: pw.TextAlign.right),
                ],
              ),
              ...stats.sectionStats.map(
                (sec) => pw.TableRow(
                  children: [
                    _pdfCell(sec.section.title),
                    _pdfCell('${sec.answered}/${sec.total} answered', align: pw.TextAlign.center),
                    _pdfCell('${sec.score}%', align: pw.TextAlign.right, bold: true),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),

        
          pw.Text('02 · ATTENTION MARKERS & GAPS (${stats.gaps.length})',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor)),
          pw.SizedBox(height: 6),
          if (stats.gaps.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Text('No compliance gaps recorded. All assessed requirements met.',
                  style: pw.TextStyle(fontSize: 9, color: mutedColor)),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey200, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _pdfHeaderCell('Severity', width: 60),
                    _pdfHeaderCell('Requirement & Section'),
                    _pdfHeaderCell('Status & Remark'),
                  ],
                ),
                ...stats.gaps.map((gap) {
                  final sev = gap.item.severity.toLowerCase();
                  final sevColor = sev == 'critical' ? criticalColor : sev == 'major' ? majorColor : mutedColor;
                  final resp = record.responses[gap.item.id];
                  final remark = (resp?.remark != null && resp!.remark.isNotEmpty) ? ' | ${resp.remark}' : '';
                  return pw.TableRow(
                    children: [
                      _pdfCell(sev.toUpperCase(), color: sevColor, bold: true),
                      _pdfCell('${gap.item.text}\n(${gap.sectionTitle})'),
                      _pdfCell('${responseLabel(resp?.status, gap.item.responseType)}$remark'),
                    ],
                  );
                }),
              ],
            ),
          pw.SizedBox(height: 16),

          // Visit Notes
          pw.Text('03 · VISIT NOTES',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor)),
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey200, width: 0.5),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              metadata['notes']?.isNotEmpty == true ? metadata['notes']! : 'No additional visit notes recorded.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
          pw.SizedBox(height: 16),

          // Digital Signatures
          pw.Text('04 · VERIFICATION & SIGN-OFF',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor)),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Lead Inspector Signature', style: pw.TextStyle(fontSize: 8, color: mutedColor)),
                      pw.Text(
                        record.signatures.inspectors.isNotEmpty && record.signatures.inspectors.first.name.isNotEmpty
                            ? record.signatures.inspectors.first.name
                            : (record.inspectorName ?? 'Lead Inspector'),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                      ),
                      pw.SizedBox(height: 6),
                      if (inspectorSigBytes != null)
                        pw.Image(pw.MemoryImage(inspectorSigBytes), height: 36, fit: pw.BoxFit.contain)
                      else
                        pw.Text('[Digitally Signed]', style: pw.TextStyle(fontSize: 8, color: mutedColor)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Facility Pharmacist Signature', style: pw.TextStyle(fontSize: 8, color: mutedColor)),
                      pw.Text(
                        record.signatures.pharmacist.name.isNotEmpty
                            ? record.signatures.pharmacist.name
                            : 'Facility Pharmacist',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                      ),
                      pw.SizedBox(height: 6),
                      if (pharmacistSigBytes != null)
                        pw.Image(pw.MemoryImage(pharmacistSigBytes), height: 36, fit: pw.BoxFit.contain)
                      else
                        pw.Text('[Digitally Signed]', style: pw.TextStyle(fontSize: 8, color: mutedColor)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _pdfMetaCell(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label.toUpperCase(), style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
          pw.SizedBox(height: 2),
          pw.Text(value.isEmpty ? '—' : value,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _pdfHeaderCell(String text, {double? width, pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
    );
  }

  static pw.Widget _pdfCell(String text,
      {pw.TextAlign align = pw.TextAlign.left, bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
    );
  }

  /// Generates clean CSV content that natively opens in Excel, Google Sheets, Numbers.
  static String generateCsv(ChecklistTemplate template, InspectionRecord record) {
    final stats = getStats(template, record);
    final meta = record.metadata;
    final buffer = StringBuffer();

    String escape(String? val) {
      if (val == null) return '""';
      final cleaned = val.replaceAll('"', '""');
      return '"$cleaned"';
    }

    // Header block
    buffer.writeln('${escape("CareAudit Final Inspection Report")},${escape("")},${escape("")},${escape("")}');
    buffer.writeln('${escape("Facility")},${escape(meta['facilityName'] ?? "Untitled facility")}');
    buffer.writeln('${escape("Checklist Template")},${escape(template.title)}');
    buffer.writeln('${escape("Inspection Type")},${escape(meta['inspectionType'] ?? "Routine")}');
    buffer.writeln('${escape("Completed Date")},${escape(formatDate(record.completedAt ?? record.updatedAt))}');
    buffer.writeln('${escape("Overall Compliance Score")},${escape("${stats.score}%")}');
    buffer.writeln('${escape("Critical Gaps")},${escape("${stats.critical.length}")}');
    buffer.writeln('${escape("Major Gaps")},${escape("${stats.major.length}")}');
    buffer.writeln('');

    // Facility Information
    buffer.writeln('${escape("FACILITY INFORMATION")},${escape("VALUE")}');
    buffer.writeln('${escape("Address")},${escape(meta['facilityAddress'] ?? "")}');
    buffer.writeln('${escape("Licensed Professional")},${escape("${meta['professionalName'] ?? ""} (${meta['profession'] ?? ""})")}');
    buffer.writeln('${escape("Facility Head")},${escape(meta['headName'] ?? "")}');
    buffer.writeln('${escape("Owner / Operator")},${escape(meta['ownerName'] ?? "")}');
    buffer.writeln('${escape("License No. / Date")},${escape("${meta['licenseNo'] ?? ""} ${meta['licenseDate'] ?? ""}")}');
    buffer.writeln('${escape("Valid Trade License")},${escape(meta['tradeLicenseStatus'] ?? "")}');
    buffer.writeln('${escape("Lead Assessor")},${escape(meta['assessor'] ?? "")}');
    buffer.writeln('${escape("Contact Phone")},${escape(meta['contact'] ?? "")}');
    buffer.writeln('${escape("Visit Notes")},${escape(meta['notes'] ?? "")}');
    buffer.writeln('');

    // Detailed Audit Items
    buffer.writeln('${escape("Checklist Section")},${escape("Requirement")},${escape("Response")},${escape("Severity")},${escape("Inspector Remark")}');
    for (final sec in template.sections) {
      for (final item in sec.items) {
        final resp = record.responses[item.id];
        buffer.writeln([
          escape(sec.title),
          escape(item.text),
          escape(responseLabel(resp?.status, item.responseType)),
          escape(item.severity.isEmpty ? "—" : item.severity.toUpperCase()),
          escape(resp?.remark ?? "—"),
        ].join(','));
      }
    }

    return buffer.toString();
  }

  /// Generates a rich styled HTML Word Document (.doc) that opens natively in Microsoft Word and Google Docs.
  static String generateDoc(ChecklistTemplate template, InspectionRecord record) {
    final stats = getStats(template, record);
    final meta = record.metadata;

    final facility = meta['facilityName']?.isNotEmpty == true ? meta['facilityName']! : 'Untitled facility';
    final completed = formatDate(record.completedAt ?? record.updatedAt);

    final buffer = StringBuffer();
    buffer.writeln('''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>CareAudit Inspection Report - $facility</title>
<style>
body { font-family: Calibri, 'Segoe UI', Arial, sans-serif; margin: 30px; color: #173533; line-height: 1.4; }
h1 { color: #0B6B67; font-size: 24px; margin-bottom: 4px; }
.meta-header { background: #DFF1E7; padding: 16px; border-radius: 8px; margin-bottom: 20px; }
.score-badge { font-size: 28px; font-weight: bold; color: #0B6B67; }
table { width: 100%; border-collapse: collapse; margin-top: 10px; margin-bottom: 24px; font-size: 11px; }
th, td { border: 1px solid #DDE6E2; padding: 8px 10px; text-align: left; }
th { background: #F1F6F4; color: #143C3A; font-weight: bold; }
.critical { color: #B2604E; font-weight: bold; }
.major { color: #B45309; font-weight: bold; }
.met { color: #1B633D; font-weight: bold; }
.section-title { color: #0B6B67; font-size: 14px; font-weight: bold; margin-top: 18px; border-bottom: 2px solid #0B6B67; padding-bottom: 4px; }
</style>
</head>
<body>
<div class="meta-header">
  <h1>CareAudit · Final Inspection Report</h1>
  <div style="font-size: 18px; font-weight: bold; color: #143C3A;">$facility</div>
  <div style="font-size: 12px; color: #5F7270;">${template.title} | ${meta['inspectionType'] ?? 'Routine'} visit | Completed $completed</div>
  <div style="margin-top: 10px;"><span class="score-badge">${stats.score}%</span> Overall Compliance Score</div>
</div>

<div class="section-title">Facility Information</div>
<table>
  <tr><th>Facility Address</th><td>${meta['facilityAddress'] ?? '—'}</td><th>Lead Assessor</th><td>${meta['assessor'] ?? '—'}</td></tr>
  <tr><th>Licensed Professional</th><td>${meta['professionalName'] ?? '—'} (${meta['profession'] ?? ''})</td><th>License No.</th><td>${meta['licenseNo'] ?? '—'}</td></tr>
  <tr><th>Facility Head</th><td>${meta['headName'] ?? '—'}</td><th>Owner / Operator</th><td>${meta['ownerName'] ?? '—'}</td></tr>
  <tr><th>Valid Trade License</th><td>${meta['tradeLicenseStatus'] ?? '—'}</td><th>Contact Phone</th><td>${meta['contact'] ?? '—'}</td></tr>
</table>

<div class="section-title">Section Scores Breakdown</div>
<table>
  <tr><th>Section</th><th>Requirements Met</th><th>Score</th></tr>''');

    for (final sec in stats.sectionStats) {
      buffer.writeln('<tr><td>${sec.section.title}</td><td>${sec.answered}/${sec.total} answered</td><td><b>${sec.score}%</b></td></tr>');
    }

    buffer.writeln('''</table>
<div class="section-title">Assessment Detail</div>
<table>
  <tr><th>Section</th><th>Requirement</th><th>Response</th><th>Severity</th><th>Inspector Remarks</th></tr>''');

    for (final sec in template.sections) {
      for (final item in sec.items) {
        final resp = record.responses[item.id];
        final sevClass = item.severity.toLowerCase();
        buffer.writeln('<tr><td>${sec.title}</td><td>${item.text}</td><td>${responseLabel(resp?.status, item.responseType)}</td><td class="$sevClass">${item.severity.toUpperCase()}</td><td>${resp?.remark ?? '—'}</td></tr>');
      }
    }

    buffer.writeln('''</table>
<div class="section-title">Visit Notes</div>
<p>${meta['notes']?.isNotEmpty == true ? meta['notes']! : 'No additional visit note was recorded.'}</p>

<div class="section-title">Inspection Sign-off</div>
<table>
  <tr><th>Lead Inspector</th><td>${record.signatures.inspectors.firstOrNull?.name ?? record.inspectorName ?? 'Lead Inspector'}</td></tr>
  <tr><th>Facility Pharmacist</th><td>${record.signatures.pharmacist.name.isNotEmpty ? record.signatures.pharmacist.name : 'Facility Pharmacist'}</td></tr>
</table>
</body>
</html>''');

    return buffer.toString();
  }

  /// Exports and shares the report in the desired format (PDF, Excel, Word).
  /// Works 100% on-device offline with zero server requirement!
  static Future<void> shareReport({
    required BuildContext context,
    required ChecklistTemplate template,
    required InspectionRecord record,
    required String format, // 'pdf', 'xlsx', 'docx'
  }) async {
    final fileName = 'careaudit-${safeFileName(record)}';

    if (format == 'pdf') {
      final bytes = await generatePdf(template, record);
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, name: '$fileName.pdf', mimeType: 'application/pdf')],
      ));
    } else if (format == 'xlsx') {
      // Excel spreadsheet
      final csvString = generateCsv(template, record);
      final bytes = Uint8List.fromList(utf8.encode(csvString));
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, name: '$fileName.csv', mimeType: 'text/csv')],
      ));
    } else if (format == 'docx') {
      // Word document
      final docString = generateDoc(template, record);
      final bytes = Uint8List.fromList(utf8.encode(docString));
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, name: '$fileName.doc', mimeType: 'application/msword')],
      ));
    }
  }

  /// Native print layout dialog (for direct wireless/USB printing or saving as PDF).
  static Future<void> printReport({
    required ChecklistTemplate template,
    required InspectionRecord record,
  }) async {
    final bytes = await generatePdf(template, record);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}
