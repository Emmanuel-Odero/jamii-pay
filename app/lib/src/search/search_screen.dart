import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transaction.dart';
import '../state/wallet_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/handle_chip.dart';
import '../widgets/info_banner.dart';
import '../widgets/pill.dart';
import '../widgets/screen_nav.dart';
import '../widgets/tx_row.dart';

/// Search & discovery. One screen, four states driven by what's typed —
/// matching the mockup's Home / Autocomplete / Results / Zero-results
/// panels. No real search backend exists (no server endpoint), so matching
/// is client-side against real transactions plus a small known-terms list
/// — but it's genuine edit-distance fuzzy matching, not a single hardcoded
/// trigger string. The design's own claim ("a dropped or swapped letter
/// still finds M-Pesa") only actually held for the exact literal "mpesaa"
/// before this; typing "mpess", "mpes", etc. now correctly triggers the
/// same did-you-mean path, and genuinely unmatched queries (not just one
/// specific string) now reach the zero-results screen.
class SearchScreen extends StatefulWidget {
  const SearchScreen(
      {super.key,
      required this.onBack,
      required this.onAskJamii,
      required this.onCashOut});

  final VoidCallback onBack;
  final VoidCallback onAskJamii;
  final VoidCallback onCashOut;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchState { home, autocomplete, results, zero }

/// Known services/people the demo can recognize — the design's "Popular
/// near you" chips plus the one demo contact used throughout the mockup.
/// A real search backend would replace this with actual service/contact
/// lookups; this is a fuzzy-matched stand-in for one.
const _knownTerms = [
  'm-pesa',
  'cash out',
  'pay bill',
  'airtime',
  'water bill',
  'school fees',
  'yusuf omar'
];

/// Standard Levenshtein edit distance — insert/delete/substitute cost 1.
int _editDistance(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// The closest known term to [q], or null if nothing is close enough to
/// plausibly be a typo of it (a query further than ~40% of the term's own
/// length isn't "a dropped or swapped letter", it's just a different word).
String? _closestKnownTerm(String q) {
  String? best;
  var bestDistance = 1 << 30;
  for (final term in _knownTerms) {
    final distance = _editDistance(q, term);
    final threshold = (term.length * 0.4).ceil().clamp(1, 3);
    if (distance <= threshold && distance < bestDistance) {
      best = term;
      bestDistance = distance;
    }
  }
  return best;
}

/// Display casing for a `_knownTerms` entry — the one irregular case is
/// "m-pesa", styled "M-Pesa" everywhere else in this app.
String _titleCase(String term) {
  if (term == 'm-pesa') return 'M-Pesa';
  return term
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// No threshold — always returns *some* suggestion, for the zero-results
/// screen's "did you mean" nicety, which the design shows even for queries
/// that aren't a close typo of anything in particular.
String _bestGuessTerm(String q) {
  var best = _knownTerms.first;
  var bestDistance = 1 << 30;
  for (final term in _knownTerms) {
    final distance = _editDistance(q, term);
    if (distance < bestDistance) {
      best = term;
      bestDistance = distance;
    }
  }
  return best;
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _filter = 'All';

  String get _query => _controller.text.trim().toLowerCase();

  bool get _isPeopleMatch {
    final q = _query;
    return q.isNotEmpty &&
        (q.contains('yusuf') ||
            _editDistance(q, 'yusuf') <= 2 ||
            _editDistance(q, 'yusuf omar') <= 3);
  }

  _SearchState get _state {
    final q = _query;
    if (q.isEmpty) return _SearchState.home;
    final hasRealMatches = _matches(context).isNotEmpty;
    if (hasRealMatches || _isPeopleMatch) return _SearchState.results;
    final closest = _closestKnownTerm(q);
    if (closest != null) return _SearchState.autocomplete;
    return _SearchState.zero;
  }

  List<Transaction> _matches(BuildContext context) {
    final q = _query;
    final all = context.read<WalletStore>().transactions;
    if (_isPeopleMatch) {
      return all.where((t) => t.title.toLowerCase().contains('yusuf')).toList();
    }
    return all.where((t) => t.title.toLowerCase().contains(q)).toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The hide-savings secret-phrase reveal — matches the prototype's
  /// `bindSearch` binding exactly: an exact-match query immediately
  /// reveals savings, clears the field, and returns to Home, rather than
  /// running through the ordinary search states at all.
  void _onQueryChanged(BuildContext context) {
    final revealed =
        context.read<WalletStore>().checkSavingsRevealPhrase(_controller.text);
    if (revealed) {
      _controller.clear();
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy900,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAskJamii,
        backgroundColor: AppColors.blue,
        icon: const Icon(Icons.chat_bubble_outline),
        label: Text('Ask Jamii',
            style: AppText.ui(
                size: 13, weight: FontWeight.w700, color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScreenNav(title: 'Search', onBack: widget.onBack),
              _SearchBox(
                  controller: _controller,
                  onChanged: (_) => _onQueryChanged(context)),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: switch (_state) {
                    _SearchState.home => _HomeState(
                        filter: _filter,
                        onFilter: (f) => setState(() => _filter = f)),
                    _SearchState.autocomplete => _AutocompleteState(
                        suggestion: _closestKnownTerm(_query)!,
                        matches: _matches(context),
                      ),
                    _SearchState.results => _ResultsState(
                        matches: _matches(context), showPeople: _isPeopleMatch),
                    _SearchState.zero => _ZeroState(
                        query: _controller.text,
                        suggestion: _bestGuessTerm(_query),
                        onCashOut: widget.onCashOut),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.navy800,
        border: Border.all(
            color: controller.text.isEmpty ? AppColors.line : AppColors.blue),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 17, color: AppColors.ink3),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppText.ui(size: 13),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Search transactions, contacts, services…',
                hintStyle: AppText.ui(size: 12.5, color: AppColors.ink3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeState extends StatelessWidget {
  const _HomeState({required this.filter, required this.onFilter});
  final String filter;
  final ValueChanged<String> onFilter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final label in [
              'All',
              'Transactions',
              'Contacts',
              'Services',
              'Help'
            ])
              AppPill(
                  label: label,
                  selected: label == filter,
                  onTap: () => onFilter(label)),
          ],
        ),
        const SizedBox(height: 16),
        Text('Recent', style: AppText.ui(size: 12, color: AppColors.ink3)),
        const SizedBox(height: 7),
        const Wrap(spacing: 6, children: [
          AppPill(label: 'Yusuf'),
          AppPill(label: 'M-Pesa'),
          AppPill(label: 'Water bill')
        ]),
        const SizedBox(height: 16),
        Text('Popular near you',
            style: AppText.ui(size: 12, color: AppColors.ink3)),
        const SizedBox(height: 7),
        const Wrap(spacing: 6, children: [
          AppPill(label: 'Send to M-Pesa'),
          AppPill(label: 'Buy airtime'),
          AppPill(label: 'Pay school fees'),
        ]),
        const SizedBox(height: 20),
        const InfoBanner(
            icon: Icons.check_circle_outline,
            text:
                'Fees are always shown before you commit — never hidden behind "Continue".'),
      ],
    );
  }
}

class _AutocompleteState extends StatelessWidget {
  const _AutocompleteState({required this.suggestion, required this.matches});
  final String suggestion;
  final List<Transaction> matches;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          variant: AppCardVariant.selected,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Text('Did you mean', style: AppText.ui(size: 13)),
              const SizedBox(width: 9),
              AppPill(label: _titleCase(suggestion), selected: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Matches while you type',
            style: AppText.ui(size: 12, color: AppColors.ink3)),
        for (final tx in matches.take(1)) TxRow(tx: tx),
      ],
    );
  }
}

class _ResultsState extends StatelessWidget {
  const _ResultsState({required this.matches, required this.showPeople});
  final List<Transaction> matches;
  final bool showPeople;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPeople) ...[
          Text('People', style: AppText.ui(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 6),
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                AvatarCircle(
                    name: 'Yusuf Omar', color: AppColors.blue, size: 36),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Yusuf Omar',
                          style:
                              AppText.ui(size: 13.5, weight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      const HandleChip(
                          base: 'yusufo22',
                          checkDigit: 'c',
                          size: HandleChipSize.small),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Send',
                        style: AppText.ui(
                            size: 11,
                            weight: FontWeight.w700,
                            color: AppColors.blue)),
                    Icon(Icons.arrow_forward, size: 13, color: AppColors.blue),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text('Transactions · ${matches.length}',
            style: AppText.ui(size: 12, color: AppColors.ink3)),
        if (matches.isEmpty)
          Text('No matching transactions',
              style: AppText.ui(size: 12.5, color: AppColors.ink3))
        else
          for (final tx in matches)
            TxRow(tx: tx, showBorder: tx != matches.last),
      ],
    );
  }
}

class _ZeroState extends StatelessWidget {
  const _ZeroState(
      {required this.query, required this.suggestion, required this.onCashOut});
  final String query;
  final String suggestion;
  final VoidCallback onCashOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Icon(Icons.search_off, size: 30, color: AppColors.ink3),
        const SizedBox(height: 8),
        Text('No matches for "$query"',
            style: AppText.ui(size: 13.5, weight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text("Here's what's close, and what other people search for.",
            textAlign: TextAlign.center, style: AppText.screenSub()),
        const SizedBox(height: 8),
        AppCard(
          variant: AppCardVariant.selected,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Did you mean',
                  style: AppText.ui(size: 12, color: AppColors.ink2)),
              const SizedBox(height: 2),
              Text(_titleCase(suggestion),
                  style: AppText.ui(size: 13.5, weight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Popular services',
              style: AppText.ui(size: 12, color: AppColors.ink3)),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 7, runSpacing: 7, children: [
          const AppPill(icon: Icons.arrow_upward, label: 'Send'),
          AppPill(icon: Icons.sync_alt, label: 'Cash out', onTap: onCashOut),
          const AppPill(icon: Icons.receipt_long_outlined, label: 'Pay bill'),
          const AppPill(icon: Icons.sim_card_outlined, label: 'Airtime'),
        ]),
        const SizedBox(height: 18),
        AppButton(
          label: 'Still stuck? Chat with support',
          variant: AppButtonVariant.outline,
          onPressed: () => AppSnackBar.show(context,
              message: 'Support chat is coming soon.', tone: SnackTone.warning),
        ),
      ],
    );
  }
}
