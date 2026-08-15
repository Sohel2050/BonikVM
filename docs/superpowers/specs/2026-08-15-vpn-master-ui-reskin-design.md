# VPN Master UI Re-skin + Windows Removal

## Background

`BonikVM` (branch `feature/ads-sdk-update`) started life as the VPN Master
app, then commit `9e570b0` ("Rebase app onto newer AxeVPN template base,
keep VPN MASTER identity") replaced most of the UI layer with a newer
AxeVPN template while keeping VPN Master's branding, and later added
Windows desktop support and LevelPlay mediation adapters (`fb272ee`).

`vpn master.rar` (extracted at `C:\Users\Dexter\StudioProjects\vpn master`)
is a snapshot of the app as it existed *before* that rebase — its last
commit is June 7 2026, older than the rebase. Its UI is visibly plainer
than the current one: a static `BottomNavigationBar` and solid-color drawer
header, vs. the current floating glassmorphic nav bar, gradient drawer with
native-ad slot, Premium tab, and language selector. It also predates
Windows support entirely and uses an older ad-mediation dependency
(`ironsource_mediation` vs. current `unity_levelplay_mediation`) and an
older `axevpn_flutter` reference (git ref vs. published package).

The user wants the app's visual design reverted to vpn master's simpler
look, while keeping all functionality BonikVM has added since (ad
mediation logic, Premium tier, bug fixes) — except Windows support, which
should be removed outright.

## Goal

Re-skin BonikVM's UI to match vpn master's simpler visual design, and
remove Windows desktop support, without regressing any backend logic,
provider wiring, or bug fixes added on top of the AxeVPN rebase.

## Non-goals

- No dependency downgrades. BonikVM's newer package versions
  (`unity_levelplay_mediation`, `google_mobile_ads` 9.x, `axevpn_flutter`
  as a pub package, current Firebase versions) stay as-is; vpn master's UI
  gets ported onto them, not the reverse.
- No removal of features vpn master simply predates and BonikVM added
  independent of the AxeVPN rebase (Premium tab/screen, ad mediation,
  debug screens, language selector). These are not "new UI to revert,"
  they're functionality gaps — only the AxeVPN-rebase-era *visual* changes
  are being reverted.
- No test suite work beyond running the existing default
  `test/widget_test.dart` — the project has no other automated tests to
  extend or preserve.

## Approach: per-file reconciliation

For each file that differs between the two trees, vpn master's version is
the visual/structural reference, but it is **ported into** BonikVM's
current file, not copied over it. Concretely, per file:

1. Diff the two versions.
2. Carry over vpn master's layout, colors, component structure, copy, and
   asset references.
3. Keep BonikVM's provider names, service calls, and any logic added since
   the rebase (bug fixes, new providers, ad-mediation calls) that vpn
   master doesn't have an equivalent of.
4. Where vpn master lacks a feature BonikVM added post-rebase and it isn't
   Windows-specific (Premium tab, language selector, native ad slot,
   debug/admin screens), keep BonikVM's version of that piece untouched —
   it's additive, not a UI reversion target.
5. Fix any API calls that reference the old dependency versions vpn master
   used (e.g. no `ironsource_mediation` symbols should be introduced;
   mediation calls stay on `unity_levelplay_mediation`).

This is a manual, file-by-file pass — not a scripted merge — because the
two trees have unrelated git histories on disk and diverged in both
directions (BonikVM added things vpn master doesn't have, vpn master has
an older look BonikVM doesn't have).

## Phases

Each phase ends with `flutter analyze` and a manual pass in the
browser/emulator on the touched screens, then a commit, before starting
the next phase.

### Phase 1 — Foundation
`lib/shared/widgets/`: `main_shell.dart`, `modern_app_bar.dart`,
`splash_screen.dart`, `custom_app_bar.dart`; `lib/shared/providers/theme_provider.dart`.
These underpin every screen, so they go first.

### Phase 2 — Core screens
`lib/features/home/home_screen.dart` (+ its extracted sub-widgets in
`lib/features/home/widgets/` and `utils/`, which vpn master doesn't have
split out — keep the split, re-skin their contents),
`lib/features/servers/servers_screen.dart`,
`lib/features/premium/premium_screen.dart` +
`billing_bottom_sheets.dart`.

### Phase 3 — Secondary screens
`lib/features/settings/settings_screen.dart`,
`lib/features/support/support_screen.dart`,
`lib/features/about/about_screen.dart`,
`lib/features/onboarding/onboarding_screen.dart`,
`lib/screens/auth/sign_in_screen.dart`,
`lib/screens/payment/payment_options_screen.dart`,
`lib/screens/payment/receipt_screen.dart`.

### Phase 4 — Ad widgets
`lib/widgets/level_play_banner_ad.dart`,
`lib/widgets/level_play_rewarded_popup.dart`,
`lib/widgets/unified_ads_popup.dart`,
`lib/widgets/unified_ads_popup_simple.dart`.
Re-skin visuals only; the LevelPlay/AdMob init and load logic hardened in
`fb272ee` must not be touched.

### Phase 5 — Windows removal
Delete outright:
- `windows/` (native runner folder)
- `lib/core/services/windows_google_auth.dart`
- `lib/core/services/windows_tray_service.dart`
- `lib/core/services/windows_v2ray_service.dart`
- `lib/core/services/windows_vpn_service.dart`
- `lib/core/services/windows_wireguard_service.dart`
- `lib/features/premium/windows_checkout.dart`
- `lib/widgets/connection_map_widget.dart` (Windows-only map widget)

Remove from `pubspec.yaml`: `window_manager`, `tray_manager`,
`flutter_secure_storage`, the `windows:` block under
`flutter_launcher_icons`.

**Correction (discovered during execution):** `flutter_secure_storage` is NOT
Windows-only — it's used unconditionally in `lib/core/api_client.dart`,
`lib/core/services/notification_service.dart`, and `lib/services/api_service.dart`
for cross-platform token storage. It was removed here in error and restored in
a follow-up commit. Only `window_manager` and `tray_manager` were correctly
Windows-only.

Sweep every remaining file with a `Platform.isWindows` or `dart:io`
branch and collapse it to the non-Windows path:
- `lib/core/api/api_service.dart`
- `lib/core/api_client.dart`
- `lib/core/services/admob_service.dart`
- `lib/core/services/level_play_service.dart`
- `lib/core/services/notification_service.dart`
- `lib/core/services/update_service.dart`
- `lib/core/services/vpn_bundle_tester.dart`
- `lib/core/services/vpn_debug_service.dart`
- `lib/core/services/vpn_service.dart`
- `lib/features/debug/vpn_debug_screen.dart`
- `lib/features/premium/billing_bottom_sheets.dart`
- `lib/features/premium/premium_screen.dart`
- `lib/features/servers/servers_screen.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/main.dart`
- `lib/screens/auth/sign_in_screen.dart`
- `lib/screens/payment/payment_options_screen.dart`
- `lib/services/auth_service.dart`
- `lib/services/billing_service.dart`
- `lib/services/payment_service.dart`
- `lib/shared/providers/app_providers.dart`

This list is a starting inventory from a `grep` pass at spec-writing time;
re-verify it at the start of phase 5 in case earlier phases touched these
files, and check `android`/`ios`/`web`/root-level build config
(`analysis_options.yaml`, CI configs if any) for Windows-only entries too.

## Testing / verification

- `flutter analyze` after every phase — zero new warnings/errors introduced.
- Manual click-through of every screen touched in that phase, in both
  light and dark mode, before moving to the next phase.
- After phase 5, a full `flutter build` for Android (and iOS if
  practical) to confirm removing Windows didn't break shared code paths.
- No new automated tests are added; existing `test/widget_test.dart` just
  needs to keep passing.

## Risks

- **Ad mediation regressions**: phase 4 touches the same widgets hardened
  in the last commit for init-timing and crash fixes. Re-skinning must
  change layout/visuals only, not init sequencing, ad-load callbacks, or
  timeout values.
- **Windows sweep incompleteness**: `Platform.isWindows` branches may hide
  in files not caught by the phase-5 grep if new ones appear during phases
  1-4. Re-grep at phase 5 start.
- **Feature/UI conflation**: the biggest risk is misjudging phase-2/3
  files where vpn master's simpler screen also lacks a feature BonikVM
  added (e.g. vpn master's `settings_screen.dart` may be missing
  UI hooks for features that now exist). Each such gap needs a
  case-by-case call: keep BonikVM's addition, styled to match vpn
  master's look, rather than dropping the feature.

## Work location

Phases committed sequentially directly on `feature/ads-sdk-update`, one
commit per phase, so each phase is reviewable independently.
