# Design-fidelity audit — mockup vs. implementation

Date: 2026-08-25. Source of truth: `../designs/jammii-pay-mockup.html` (21
`.screen` blocks), cross-checked against `../designs/jammii-pay-prototype.html`,
`../designs/jamii-pay-tech-presentation.html`, and `../designs/jamii-pay-pitch-deck.html`.
Compared against the Flutter implementation at `app/lib/`.

This is a living document — update it as gaps close or the design changes,
rather than letting it go stale. See git history for when each section was
last actually re-verified against the code.

## 1. Screen inventory (21/21 built, 20/21 reachable)

| # | Screen | Dart file | Status |
|---|---|---|---|
| 1 | Welcome | `onboarding/welcome_screen.dart` | Matches |
| 2 | Language | `onboarding/language_screen.dart` | Matches |
| 3 | Set PIN | `onboarding/pin_screen.dart` | Matches; real enforcement added (hash persisted, checked by `LockScreen`) |
| 4 | Biometric | `onboarding/biometric_screen.dart` | Matches; real `local_auth` prompt, not a fake advance |
| 5 | Handle | `onboarding/handle_screen.dart` | Redesigned: mockup's static demo handle → real editable field hitting `GET /handles/availability` |
| 6 | Guardians | `onboarding/guardians_screen.dart` | Matches exactly |
| 7 | Done | `onboarding/done_screen.dart` | Matches |
| 8 | Home | `wallet/home_screen.dart` | Matches structurally; greeting lost personalization (see gap 6) |
| 9 | Receive | `wallet/receive_screen.dart` | Real QR (mockup's is decorative); paybill matches |
| 10 | Send | `wallet/send_screen.dart` | Redesigned to real inputs, but **dead end** (see gap 2) |
| 11 | Savings | `wallet/savings_screen.dart` | Matches; actions are honest "coming soon" (no backend) |
| 12 | Activity | `wallet/activity_screen.dart` | Matches structurally |
| 13 | Recovery R1 (Start) | `recovery/recovery_start_screen.dart` | Fixed to real editable handle (borrowed-phone case) |
| 14 | Recovery R2 (Approvals) | `recovery/recovery_approvals_screen.dart` | Matches; driven by real server data |
| 15 | Recovery R3 (Waiting) | `recovery/recovery_waiting_screen.dart` | Matches; "$40 available now" is static in both design and code (gap 10) |
| 16 | Recovery R4 (Veto) | `recovery/recovery_veto_screen.dart` | Built, matches design, **but unreachable** (gap 1) |
| 17 | Search Home | `search/search_screen.dart` (`_HomeState`) | Matches |
| 18 | Search Autocomplete | `search/search_screen.dart` (`_AutocompleteState`) | Only reachable via literal `"mpesaa"` (gap 4) |
| 19 | Search Results | `search/search_screen.dart` (`_ResultsState`) | Static demo data |
| 20 | Search Zero-results | `search/search_screen.dart` (`_ZeroState`) | Only reachable via literal `"kwik cash"` (gap 5) |
| 21 | Ask Jamii | `search/ask_jamii_screen.dart` | Static; "Ask another question" bar is decorative, not a real `TextField` |

## 2. Design tokens — fully faithful

All 15 named CSS custom properties in the mockup's `:root` block (navy
scale, ink scale, line/line-2 alpha composites, blue/green/coral/amber,
the three font families, the two border radii) have bit-exact counterparts
in `app_colors.dart` / `app_text.dart` / `app_theme.dart`. No gaps here —
this layer doesn't need revisiting.

## 3. `jammii-pay-prototype.html` — a materially bigger, undocumented product

This file is not a draft of the mockup — it's a separate, more ambitious
interactive prototype with real feature surface that exists **nowhere**
else (not in the mockup, not in the app):

- **Contacts** (address book, on-Jamii vs. invite distinction)
- **Groups / Chamas** — pooled savings with configurable voting power and
  majority-vote withdrawals. The single largest gap: a whole product
  surface with no mockup screen and no implementation.
- **Escrow claim-by-link** — sending to someone not yet on JamiiPay via a
  claimable link with a 72h countdown (the `claims` table already exists
  in `crates/server`'s schema, unused by any route)
- **Cash-out to M-Pesa** — dedicated flow with an explicit spread
  disclosure ("Our spread · 0.8% · shown openly")
- **Hide savings** — a coercion-protection feature (hide the savings card
  behind a gesture)
- **Per-event alert settings**, **theme switching**

None of this is scoped into the current build. Flagging it here so it's a
deliberate decision, not a silent gap — **not implementing any of this in
this pass**; it's a separate scoping conversation.

## 4. Reachability

Traced from `main.dart` → `app_router.dart` → `onboarding_flow.dart` /
`wallet_flow.dart`. Every screen is reachable except **Recovery R4
(Veto)** — `buildRecoveryVeto` (`recovery_flow.dart`) has zero call sites
anywhere in `lib/`. Its own doc comment claims a Settings demo entry point
exists; it doesn't.

## 5. Concrete gaps, ranked — and what's been done about each

1. **Recovery veto (R4) unreachable.** → *Fixed this pass*: added a demo
   entry point from Settings, honestly labeled as a demo (no push
   infrastructure exists to route this to a real second device).
2. **Send money is a dead end** — no backend endpoint, `onConfirm` always
   shows "coming soon". → *Fixed this pass*: added a real
   `POST /wallets/:id/transfers` endpoint (debits sender, credits
   recipient by handle, writes both transaction rows) and wired
   `SendScreen` to it.
3. **"Hold to confirm" gesture missing** — Send used a plain tap button
   where the design specifies a hold gesture as a deliberate
   reversibility safeguard. → *Fixed this pass*.
4. **Search has no real typo tolerance** — only one hardcoded literal
   (`"mpesaa"`) triggers the autocomplete state. → *Fixed this pass*:
   basic edit-distance matching against a small known-services list.
5. **Zero-results search only triggers on one literal string**
   (`"kwik cash"`) — any other unmatched query falls through to Results
   instead of the designed no-dead-ends recovery UI. → *Fixed this pass*:
   zero-state now triggers on genuine no-match, matched against real
   transaction/contact data plus the known-services list.
6. **Home greeting lost personalization** ("Habari, Amina" → "Habari").
   No display-name field exists separate from the handle. → *Fixed this
   pass*: greets by the handle base (capitalized) — the only real identity
   data available; not inventing a fake name field.
7. **Notification bell / Cash out / Pay bill are dead ends with no screen
   behind them at all** (unlike Send, which at least has a real screen).
   → Left as honest "coming soon" — building real screens for these needs
   backend features (notifications, bill-pay integration) that don't
   exist yet. Not attempted this pass.
8. **Prototype-only features** (Contacts, Chamas, escrow claim-links,
   cash-out, hide-savings, alert settings) — Not attempted this pass; see
   §3. Flagging as a real, scoped-out gap rather than pretending it
   doesn't exist.
9. **QR payload (`jamiipay://pay/$handle`) is an undocumented invention**
   — no design source specifies a payload format. Left as-is (it's
   functional and internally consistent); flagged for awareness.
10. **Recovery R3's "$40 available now" is static copy**, not derived from
    the wallet's real balance — true in both the design and the code.
    Not attempted this pass (would need a documented partial-unlock
    formula, which doesn't exist in any design source).
11. **Language screen offers 5 languages; the pitch deck's own roadmap
    only commits to 3 for launch.** Cross-document inconsistency, not a
    code bug. No action taken — flagging for product decision.
