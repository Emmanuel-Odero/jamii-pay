import 'package:flutter/material.dart';

import '../models/guardian_labels.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_screen.dart';
import '../widgets/info_banner.dart';
import '../widgets/screen_nav.dart';

/// Recovery R2 — "Two of three approve". A threshold, not a checklist: the
/// unused method greys out rather than nagging the user for it — one less
/// thing to do at the worst moment.
///
/// Driven entirely by `GET /recovery/:id` — both the configured guardian
/// types and the approvals recorded against them — rather than a local
/// `Wallet` object, since the device running recovery may have no session
/// at all.
class RecoveryApprovalsScreen extends StatelessWidget {
  const RecoveryApprovalsScreen({
    super.key,
    required this.guardians,
    required this.approvals,
    required this.threshold,
    required this.onBack,
    required this.onStartWait,
  });

  final List<String> guardians;
  final List<String> approvals;
  final int threshold;
  final VoidCallback onBack;
  final VoidCallback onStartWait;

  bool get _enoughApprovals => approvals.length >= threshold;

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      footer: AppButton(
        label: 'Start the wait',
        variant: AppButtonVariant.green,
        onPressed: _enoughApprovals ? onStartWait : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenNav(title: 'Approvals', onBack: onBack),
          Text('${approvals.length} of $threshold',
              style: AppText.screenTitle(size: 22)),
          const SizedBox(height: 8),
          Text('Use any $threshold. You don\'t need all of them.',
              style: AppText.screenSub()),
          for (final id in guardians) ...[
            _GuardianRow(id: id, approved: approvals.contains(id)),
            const SizedBox(height: 9),
          ],
          if (_enoughApprovals)
            const InfoBanner(
                icon: Icons.check_circle_outline,
                text: 'Enough approvals. The 48-hour safety wait starts now.')
          else
            InfoBanner(
              icon: Icons.more_horiz,
              tone: BannerTone.warning,
              text:
                  'Waiting for $threshold approvals — ${approvals.length} recorded so far.',
            ),
        ],
      ),
    );
  }
}

class _GuardianRow extends StatelessWidget {
  const _GuardianRow({required this.id, required this.approved});
  final String id;
  final bool approved;

  @override
  Widget build(BuildContext context) {
    final title = guardianLabels[id] ?? id;
    return AppCard(
      variant: approved ? AppCardVariant.green : AppCardVariant.plain,
      child: Row(
        children: [
          Container(
            width: 21,
            height: 21,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: approved ? AppColors.green : AppColors.navy600,
              shape: BoxShape.circle,
            ),
            child: approved
                ? Icon(Icons.check, size: 13, color: AppColors.onGreen)
                : Icon(Icons.remove, size: 13, color: AppColors.ink3),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.ui(
                    size: 13,
                    weight: FontWeight.w700,
                    color: approved ? AppColors.ink : AppColors.ink2),
              ),
              Text(approved ? 'Approved' : 'Not yet',
                  style: AppText.ui(
                      size: 11,
                      color: approved ? AppColors.ink2 : AppColors.ink3)),
            ],
          ),
        ],
      ),
    );
  }
}
