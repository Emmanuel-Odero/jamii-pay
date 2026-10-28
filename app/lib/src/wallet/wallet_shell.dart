import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// `.tabbar` — the bottom tab bar. Matches
/// `designs/jammii-pay-prototype.html`'s real 5-tab bar (Wallet/Contacts/
/// Groups/Activity/Settings) rather than the mockup's placeholder "Cards"
/// tab, which had no design source or backend behind it at all.
class WalletTabBar extends StatelessWidget {
  const WalletTabBar(
      {super.key,
      required this.currentIndex,
      required this.onTap,
      this.badges = const {}});

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Tab index → badge count. 0 shows nothing. Contacts (1) carries
  /// unread chats, Groups (2) open votes — the two places new activity
  /// hides that users kept missing.
  final Map<int, int> badges;

  static const _tabs = [
    (Icons.account_balance_wallet_outlined, 'Wallet'),
    (Icons.people_outline, 'Contacts'),
    (Icons.groups_outlined, 'Groups'),
    (Icons.receipt_long_outlined, 'Activity'),
    (Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navy800,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 13),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == currentIndex,
                  label: (badges[i] ?? 0) > 0
                      ? '${_tabs[i].$2}, ${badges[i]} new'
                      : _tabs[i].$2,
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: i == currentIndex ? 1 : 0.55,
                              child: Icon(
                                _tabs[i].$1,
                                size: 19,
                                color: i == currentIndex
                                    ? AppColors.blue
                                    : AppColors.ink3,
                              ),
                            ),
                            if ((badges[i] ?? 0) > 0)
                              Positioned(
                                top: -4,
                                right: -10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.coral,
                                    borderRadius:
                                        BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    badges[i]! > 99
                                        ? '99+'
                                        : '${badges[i]}',
                                    style: AppText.mono(
                                        size: 9,
                                        weight: FontWeight.w700,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _tabs[i].$2,
                          style: AppText.ui(
                            size: 9.5,
                            weight: FontWeight.w600,
                            color: i == currentIndex
                                ? AppColors.blue
                                : AppColors.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
