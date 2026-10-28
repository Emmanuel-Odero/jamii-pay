import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/screen_nav.dart';

/// "Add contact" — live kind-detection on the address field, matching
/// `designs/jammii-pay-prototype.html`'s `contactNew` screen exactly:
/// `@` → email, `/^[+\d\s]+$/` → phone, else treated as a payment ID
/// (validated server-side on save, since only the server knows what's
/// actually registered).
class ContactNewScreen extends StatefulWidget {
  const ContactNewScreen(
      {super.key, required this.onBack, required this.onSave, this.errorText});

  final VoidCallback onBack;
  final void Function(String name, ContactKind kind, String value) onSave;
  final String? errorText;

  @override
  State<ContactNewScreen> createState() => _ContactNewScreenState();
}

class _ContactNewScreenState extends State<ContactNewScreen> {
  final _nameController = TextEditingController();
  final _addrController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _addrController.dispose();
    super.dispose();
  }

  ContactKind get _kind => detectContactKind(_addrController.text);

  (String, Color)? get _hint {
    final v = _addrController.text.trim();
    if (v.isEmpty) return null;
    return switch (_kind) {
      ContactKind.email => (
          'Email — they will need to claim payments',
          AppColors.amber
        ),
      ContactKind.phone => (
          'Phone — we will check if they are on Jamii',
          AppColors.amber
        ),
      ContactKind.handle => (
          'Payment ID — checked when you save',
          AppColors.ink3
        ),
    };
  }

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      _addrController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final hint = _hint;

    return AppScreen(
      footer: AppButton(
        label: 'Save contact',
        onPressed: _canSave
            ? () => widget.onSave(
                _nameController.text.trim(), _kind, _addrController.text.trim())
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Add contact', onBack: widget.onBack),
          if (widget.errorText != null) ...[
            Text(widget.errorText!,
                style: AppText.ui(size: 12, color: AppColors.coral)),
            const SizedBox(height: 12),
          ],
          Text('Name', style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          AppCard(
            variant: AppCardVariant.selected,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              maxLength: 28,
              style: AppText.ui(size: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                counterText: '',
                hintText: 'Their name',
                hintStyle: AppText.ui(size: 15, color: AppColors.ink3),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Payment ID, phone or email',
              style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 8),
          AppCard(
            variant: AppCardVariant.selected,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _addrController,
              onChanged: (_) => setState(() {}),
              style: AppText.mono(size: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Any of the three',
                hintStyle: AppText.mono(size: 15, color: AppColors.ink3),
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint.$1, style: AppText.ui(size: 11, color: hint.$2)),
          ],
        ],
      ),
    );
  }
}
