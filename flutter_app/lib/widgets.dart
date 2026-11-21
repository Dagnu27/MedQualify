import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import 'models.dart';
import 'theme.dart';

class CareAuditLogo extends StatelessWidget {
  const CareAuditLogo({
    super.key,
    this.emblemSize = 34,
    this.inverted = false,
    this.showSubtitle = true,
    this.center = false,
  });

  final double emblemSize;
  final bool inverted;
  final bool showSubtitle;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final emblem = Container(
      width: emblemSize,
      height: emblemSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: inverted
              ? [const Color(0xFF2DD4BF), const Color(0xFF0F766E)]
              : [const Color(0xFF0D9488), const Color(0xFF115E59)],
        ),
        borderRadius: BorderRadius.circular(emblemSize * 0.28),
        boxShadow: [
          BoxShadow(
            color: (inverted ? const Color(0xFF2DD4BF) : AppColors.teal).withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.health_and_safety_rounded,
          color: Colors.white,
          size: emblemSize * 0.58,
        ),
      ),
    );

    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Care',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: emblemSize * 0.54,
              color: inverted ? Colors.white : AppColors.ink,
              letterSpacing: -0.4,
            ),
          ),
          TextSpan(
            text: 'Audit',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: emblemSize * 0.54,
              color: inverted ? const Color(0xFF5EEAD4) : AppColors.teal,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        emblem,
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            title,
            if (showSubtitle)
              Text(
                'FACILITY COMPLIANCE',
                style: TextStyle(
                  fontSize: (emblemSize * 0.25).clamp(8.0, 10.5),
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w600,
                  color: inverted ? const Color(0xFF99F6E4).withValues(alpha: 0.7) : AppColors.muted,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w500,
        color: color ?? const Color(0xFF78928B),
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = 'primary',
    this.expanded = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final String variant;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(9));
    Widget button;
    switch (variant) {
      case 'secondary':
        button = FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.mint,
            foregroundColor: AppColors.teal,
            shape: shape,
            minimumSize: const Size(0, 40),
          ),
          child: child,
        );
        break;
      case 'ghost':
        button = OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.inkSoft,
            side: const BorderSide(color: AppColors.lineStrong),
            shape: shape,
            minimumSize: const Size(0, 40),
          ),
          child: child,
        );
        break;
      case 'light':
        button = FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE5F5E8),
            foregroundColor: AppColors.deep,
            shape: shape,
            minimumSize: const Size(0, 32),
          ),
          child: child,
        );
        break;
      default:
        button = FilledButton(onPressed: onPressed, child: child);
    }
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding, this.color, this.borderColor});
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color ?? theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? theme.dividerColor),
        boxShadow: const [BoxShadow(color: Color(0x0A183533), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: child,
    );
  }
}

class TemplateMark extends StatelessWidget {
  const TemplateMark({super.key, required this.templates, required this.template, this.large = false});
  final List<ChecklistTemplate> templates;
  final ChecklistTemplate? template;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final accent = accentFor(templates, template);
    final size = large ? 43.0 : 35.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: BorderRadius.circular(large ? 12 : 10),
      ),
      child: Text(
        markFor(templates, template),
        style: TextStyle(color: accent.foreground, fontWeight: FontWeight.w700, fontSize: 10),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.isSynced = false});
  final String? status;
  final bool isSynced;

  @override
  Widget build(BuildContext context) {
    final complete = status == 'completed';
    final pending = status == null;

    final String label;
    final Color background;
    final Color textColor;
    final IconData? icon;

    if (pending) {
      label = 'In progress';
      background = const Color(0xFFF0F4F2);
      textColor = AppColors.muted;
      icon = Icons.pending_outlined;
    } else if (complete) {
      if (isSynced) {
        label = 'Synced to DB';
        background = AppColors.mint;
        textColor = const Color(0xFF1B633D);
        icon = Icons.cloud_done_rounded;
      } else {
        label = 'Saved Offline';
        background = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
        icon = Icons.save_rounded;
      }
    } else {
      label = 'Draft';
      background = const Color(0xFFF7EFCF);
      textColor = const Color(0xFF907326);
      icon = Icons.edit_note_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class ScoreChip extends StatelessWidget {
  const ScoreChip(this.score, {super.key});
  final int score;
  @override
  Widget build(BuildContext context) {
    final tone = scoreTone(score);
    final bg = tone == 'strong'
        ? AppColors.mint
        : tone == 'watch'
            ? const Color(0xFFF7EFCF)
            : const Color(0xFFF8E4DF);
    final fg = tone == 'strong'
        ? const Color(0xFF34734F)
        : tone == 'watch'
            ? const Color(0xFF927427)
            : const Color(0xFFA85949);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text('$score%', style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.description,
    this.action,
  });
  final String eyebrow;
  final String title;
  final String? description;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(eyebrow),
                const SizedBox(height: 8),
                Text(title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, height: 1.05, letterSpacing: -0.8)),
                if (description != null) ...[
                  const SizedBox(height: 10),
                  Text(description!, style: const TextStyle(color: AppColors.inkSoft, height: 1.5)),
                ],
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.requiredField = false,
    this.placeholder,
    this.maxLines = 1,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool requiredField;
  final String? placeholder;
  final int maxLines;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: label.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: 0.8, color: AppColors.inkSoft)),
          if (requiredField) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFB6654F), fontSize: 10)),
        ])),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: value,
          maxLines: maxLines,
          onChanged: onChanged,
          decoration: InputDecoration(hintText: placeholder),
        ),
      ],
    );
  }
}

class AppSelect extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final selected = options.contains(value) ? value : options.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: 0.8, color: AppColors.inkSoft)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: selected,
          items: options.map((item) => DropdownMenuItem(value: item, child: Text(item, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ],
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8E4DF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.cancel_outlined, size: 16, color: AppColors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: AppColors.red, fontSize: 12))),
        ],
      ),
    );
  }
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF34734F)),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: Color(0xFF34734F), fontSize: 12))),
        ],
      ),
    );
  }
}

class SignatureField extends StatefulWidget {
  const SignatureField({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  State<SignatureField> createState() => _SignatureFieldState();
}

class _SignatureFieldState extends State<SignatureField> {
  late final SignatureController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 2,
      penColor: AppColors.ink,
      exportBackgroundColor: Colors.white,
    );
    _controller.addListener(_export);
  }

  Future<void> _export() async {
    if (_controller.isEmpty) return;
    final bytes = await _controller.toPngBytes();
    if (bytes == null) return;
    widget.onChanged('data:image/png;base64,${base64Encode(bytes)}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Uint8List? get _existing {
    if (!widget.value.startsWith('data:image/png;base64,')) return null;
    try {
      return base64Decode(widget.value.substring('data:image/png;base64,'.length));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = _existing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: widget.label, style: const TextStyle(fontSize: 10, color: AppColors.inkSoft)),
                const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFB6654F), fontSize: 10)),
              ])),
            ),
            TextButton(
              onPressed: () {
                _controller.clear();
                widget.onChanged('');
                setState(() {});
              },
              child: const Text('Clear'),
            ),
          ],
        ),
        Container(
          height: 112,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: existing != null && _controller.isEmpty
              ? Image.memory(existing, fit: BoxFit.contain, width: double.infinity)
              : Signature(controller: _controller, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text('Draw signature above', style: TextStyle(fontSize: 10, color: AppColors.muted)),
      ],
    );
  }
}
