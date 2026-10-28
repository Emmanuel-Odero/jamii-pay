import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/wallet.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/handle_chip.dart';
import '../widgets/info_banner.dart';
import '../widgets/screen_nav.dart';

enum _CheckState { idle, tooShort, invalid, checking, error }

/// Onboarding 5/7 — "Pick your handle". Framed as a "payment name", not a
/// "wallet address" — the test for a good one is whether it can be said
/// out loud over a phone call, since that's how most get shared.
///
/// The user types their own base (this used to be hardcoded to the mockup's
/// `amina7k3n` demo persona for every signup — fixed so each person actually
/// gets their own name). Hits `GET /handles/availability` for real, debounced
/// while typing; matches the server's `is_valid_base` rule (3-20 lowercase
/// letters/digits) client-side so the error state is immediate, not a
/// round-trip.
class HandleScreen extends StatefulWidget {
  const HandleScreen({super.key, required this.onBack, required this.onClaim});

  final VoidCallback onBack;
  final ValueChanged<String> onClaim;

  @override
  State<HandleScreen> createState() => _HandleScreenState();
}

class _HandleScreenState extends State<HandleScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;

  _CheckState _state = _CheckState.tooShort;
  HandleAvailability? _availability;

  static final _validBase = RegExp(r'^[a-z0-9]{3,20}$');

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final base = raw.trim().toLowerCase();
    _debounce?.cancel();
    setState(() {
      _availability = null;
      if (base.isEmpty || base.length < 3) {
        _state = _CheckState.tooShort;
      } else if (!_validBase.hasMatch(base)) {
        _state = _CheckState.invalid;
      } else {
        _state = _CheckState.checking;
        _debounce =
            Timer(const Duration(milliseconds: 450), () => _check(base));
      }
    });
  }

  Future<void> _check(String base) async {
    final requestId = ++_requestId;
    try {
      final result =
          await context.read<WalletStore>().checkHandleAvailability(base);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _availability = result;
        _state = _CheckState.idle;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _state = _CheckState.error);
    }
  }

  void _selectSuggestion(String fullHandle) {
    final base = fullHandle.substring(0, fullHandle.length - 1);
    _controller.text = base;
    _controller.selection = TextSelection.collapsed(offset: base.length);
    _onChanged(base);
  }

  @override
  Widget build(BuildContext context) {
    final available = _availability?.available ?? false;
    final checkDigit = _availability?.checkDigit ?? '';
    final suggestions = _availability?.suggestions ?? const [];
    final base = _controller.text.trim().toLowerCase();

    return AppScreen(
      footer: AppButton(
        label: 'Claim this name',
        onPressed: available ? () => widget.onClaim('$base$checkDigit') : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(onBack: widget.onBack, step: 4, totalSteps: 5),
          Text('Your payment name', style: AppText.screenTitle()),
          const SizedBox(height: 8),
          Text(
            'This is what people type to pay you. Choose something you can say out loud over the phone.',
            style: AppText.screenSub(),
          ),
          const SizedBox(height: 14),
          AppCard(
            variant: AppCardVariant.selected,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: _onChanged,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    maxLength: 20,
                    textInputAction: TextInputAction.done,
                    style: AppText.mono(size: 20, letterSpacing: 1),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'yourname',
                      hintStyle: AppText.mono(
                          size: 20, letterSpacing: 1, color: AppColors.ink3),
                    ),
                  ),
                ),
                if (checkDigit.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(checkDigit,
                        style:
                            AppText.mono(size: 18, color: AppColors.navy900)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _StatusLine(
              state: _state, available: available, onRetry: () => _check(base)),
          const SizedBox(height: 12),
          const InfoBanner(
            icon: Icons.info_outline,
            tone: BannerTone.warning,
            text:
                'The last character is added automatically. It catches mistakes if someone types your '
                'name wrong.',
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Suggestions',
                style: AppText.ui(size: 12, color: AppColors.ink3)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final full in suggestions)
                  GestureDetector(
                    onTap: () => _selectSuggestion(full),
                    child: HandleChip(
                      base: full.substring(0, full.length - 1),
                      checkDigit: full.substring(full.length - 1),
                      size: HandleChipSize.small,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(
      {required this.state, required this.available, required this.onRetry});
  final _CheckState state;
  final bool available;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _CheckState.tooShort:
        return Text('At least 3 characters.',
            style: AppText.ui(size: 11, color: AppColors.ink3));
      case _CheckState.invalid:
        return Text('Lowercase letters and numbers only.',
            style: AppText.ui(size: 11, color: AppColors.coral));
      case _CheckState.checking:
        return Text('Checking…',
            style: AppText.ui(size: 11, color: AppColors.ink3));
      case _CheckState.error:
        return GestureDetector(
          onTap: onRetry,
          child: Text('Could not reach the server. Tap to retry.',
              style: AppText.ui(size: 11, color: AppColors.coral)),
        );
      case _CheckState.idle:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              available ? 'Available' : 'Already taken',
              style: AppText.ui(
                  size: 11,
                  color: available ? AppColors.green : AppColors.coral),
            ),
            if (available) ...[
              const SizedBox(width: 4),
              Icon(Icons.check, size: 13, color: AppColors.green),
            ],
          ],
        );
    }
  }
}
