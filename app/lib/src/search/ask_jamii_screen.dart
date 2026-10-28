import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/row_line.dart';
import '../widgets/screen_nav.dart';

/// "Ask Jamii" — conversational search with a direct answer plus receipts,
/// not a list of links. Same pattern as Revolut AIR / Bank of America's
/// Erica: people prefer asking to navigating.
///
/// No language model backs this yet, so the exchange above the input is a
/// worked example, not a live conversation. The input itself is real
/// (it accepts and clears text) but submitting shows an honest "coming
/// soon" notice rather than faking a second answer — same posture as the
/// other acknowledged-but-unbuilt stubs elsewhere in the app (see
/// `chat_screen.dart`'s "Set reminder"/"Add to calendar").
class AskJamiiScreen extends StatefulWidget {
  const AskJamiiScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<AskJamiiScreen> createState() => _AskJamiiScreenState();
}

class _AskJamiiScreenState extends State<AskJamiiScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ask() {
    final question = _controller.text.trim();
    if (question.isEmpty) return;
    _controller.clear();
    FocusScope.of(context).unfocus();
    AppSnackBar.show(context,
        message: 'Ask Jamii is coming soon.', tone: SnackTone.warning);
  }

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Ask Jamii', onBack: widget.onBack),
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(3),
                  ),
                ),
                child: Text(
                  "What's cheapest to send 10K to Tanzania?",
                  style: AppText.ui(size: 12.5, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.navy800,
              border: Border.all(color: AppColors.line),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(3),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: AppText.ui(size: 12.5, height: 1.55),
                    children: [
                      const TextSpan(text: 'Jamii Pay, at '),
                      TextSpan(
                          text: r'$0.04',
                          style: AppText.ui(
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: AppColors.green)),
                      const TextSpan(text: ' flat.'),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                RowLine(
                    label: 'Jamii Pay',
                    value: r'$0.04',
                    valueColor: AppColors.green),
                const RowLine(label: 'M-Pesa (cross-border)', value: r'$3.10'),
                const RowLine(label: 'Bank transfer', value: r'$8.50'),
                const RowLine(
                    label: 'Western Union', value: r'$9.90', showBorder: false),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Example above — try your own question below.',
              style: AppText.ui(size: 11, color: AppColors.ink3)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.navy800,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 16, color: AppColors.ink3),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: AppText.ui(size: 12.5),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _ask(),
                    decoration: InputDecoration(
                      hintText: 'Ask another question…',
                      hintStyle: AppText.ui(size: 12.5, color: AppColors.ink3),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _ask,
                  icon: Icon(Icons.arrow_upward_rounded,
                      size: 18, color: AppColors.blue),
                  tooltip: 'Ask',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
