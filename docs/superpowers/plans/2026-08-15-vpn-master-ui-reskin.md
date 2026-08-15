# VPN Master UI Re-skin + Windows Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Revert BonikVM's UI to vpn master.rar's simpler pre-rebase visual
design across shared chrome, screens, and ad widgets, then remove Windows
desktop support entirely — without regressing provider wiring, ad
mediation logic, or bug fixes added since the AxeVPN rebase.

**Architecture:** File-by-file reconciliation (see spec). This is a visual
migration, not new feature work with unit-testable logic — there is no
automated oracle for "does this screen look like vpn master's." The task
cycle below replaces the standard write-test/implement/pass loop with:
**diff → port → `flutter analyze` → manual visual check → commit**. Each
task names the exact vpn master source file, the exact BonikVM target
file, and (where known) the specific BonikVM-only symbols that must
survive the port untouched. Where a task's preserve-list isn't already
known from prior investigation, the task's first step is to derive it via
diff — a concrete, mechanical instruction, not a vague one.

**Tech Stack:** Flutter/Dart, Riverpod, go_router, LevelPlay (`unity_levelplay_mediation`), google_mobile_ads, axevpn_flutter.

**Spec:** [docs/superpowers/specs/2026-08-15-vpn-master-ui-reskin-design.md](../specs/2026-08-15-vpn-master-ui-reskin-design.md)

## Global Constraints

- Reference source tree for the old UI: `C:\Users\Dexter\StudioProjects\vpn master\lib` (read-only reference, never edit).
- Target tree: `C:\Users\Dexter\StudioProjects\BonikVM\lib` (all edits happen here), branch `feature/ads-sdk-update`.
- Never introduce `ironsource_mediation` symbols — mediation stays on `unity_levelplay_mediation`.
- Never change `axevpn_flutter` back to a git dependency — it stays the pub package version already in `pubspec.yaml`.
- Keep every BonikVM-only feature that isn't Windows-specific (Premium tab, language selector, native ad slot, debug/admin screens) — port its *styling* to match vpn master's look, never delete the feature itself.
- Run `flutter analyze` after every task; zero new errors/warnings before committing.
- One commit per task.

---

## Phase 1 — Foundation

### Task 1: Re-skin `main_shell.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\shared\widgets\main_shell.dart`
- Modify: `lib/shared/widgets/main_shell.dart`

**Known preserve-list** (confirmed by prior diff during design):
- The `PremiumScreen` tab (index 2) and its `premiumScreenKey` — vpn master only has 3 tabs (Home/Servers/Settings), BonikVM has 4 (Home/Servers/Premium/Settings). Keep 4 tabs.
- `_drawerNativeAd` / `_isDrawerNativeAdLoaded` / `_initializeDrawerNativeAd()` / `_disposeDrawerNativeAd()` and the `AdMobService.instance.createNativeAd(...)` call — native ad slot in the drawer.
- `UpdateService.instance.checkForUpdates(context: context)` call in `initState`'s post-frame callback.
- The `vpnStateProvider` listener (not `vpnProvider` — see the comment in the current file explaining `vpnProvider` never fires).
- `LanguageSelector(showInDrawer: true)` in the drawer.
- `_showAboutDialog()` and its `_buildAboutItem`/`_buildQuickAction` helpers.
- Theme toggle `IconButton` in the Home app bar actions.

**Port from vpn master:**
- `BottomNavigationBar`-style bottom nav instead of the current floating glassmorphic pill nav (or keep the floating style if you judge it strictly nicer — default to vpn master's plain style per the spec's "revert to simpler look" decision).
- Solid-color gradient drawer header (vpn master's simpler two/three-stop gradient) instead of the current avatar-card header — keep BonikVM's Premium/Free badge logic, restyle to vpn master's badge look.
- `_onWillPop` snackbar copy/style ("Double Press Back To Exit VPN MASTER", lightGreen background) — decide whether to keep this exact copy or BonikVM's current copy ("Press back again to exit VPN MASTER", black87 background); default to vpn master's copy/style per the revert decision, but keep the `Duration(seconds: 2)` timing logic as-is (identical in both).
- Background image + dark overlay `Stack` (`assets/images/bg2.png` + `Colors.black.withOpacity(0.2)`) behind the `Scaffold` body, present in vpn master, absent in current BonikVM — re-add it if the asset `assets/images/bg2.png` still exists in `assets/`.

- [ ] **Step 1: Confirm the reference asset exists**

Run: `ls "C:\Users\Dexter\StudioProjects\BonikVM\assets\images\bg2.png"`
Expected: file exists (it's already declared in `pubspec.yaml` assets). If missing, skip the background-image port and note it in the commit message.

- [ ] **Step 2: Port the visual changes into `lib/shared/widgets/main_shell.dart`**

Apply the "Port from vpn master" changes above while keeping every item in "Known preserve-list" functioning identically (same provider names, same method names, same call sites).

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/shared/widgets/main_shell.dart`
Expected: no new errors.

- [ ] **Step 4: Manual visual check**

Run the app (`flutter run -d chrome` or an emulator), and verify: all 4 tabs still navigate, the drawer opens and shows the native ad slot for free users, the About dialog opens, the language selector works, dark mode toggle works, back-press-to-exit still requires two presses within 2 seconds.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/main_shell.dart
git commit -m "Re-skin main_shell to vpn master's simpler chrome, keep Premium tab and ad slot"
```

### Task 2: Re-skin `modern_app_bar.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\shared\widgets\modern_app_bar.dart`
- Modify: `lib/shared/widgets/modern_app_bar.dart`

- [ ] **Step 1: Diff and list BonikVM-only symbols**

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\shared\widgets\modern_app_bar.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\shared\widgets\modern_app_bar.dart"`

Note every public class/method/parameter present only in the BonikVM version — these are used by call sites elsewhere (main_shell.dart, screens) and must keep the same name and signature after the port, even if their internal styling changes.

- [ ] **Step 2: Port vpn master's app bar visuals**

Apply vpn master's colors, spacing, and title styling to `MainAppBar`/`ModernAppBar` in the BonikVM file, keeping every symbol from Step 1's list with unchanged name/signature.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/shared/widgets/modern_app_bar.dart`
Expected: no new errors. If a call site elsewhere breaks (e.g. a removed parameter), fix the call site, not by re-adding the parameter unless it's still needed.

- [ ] **Step 4: Manual visual check**

Run the app and check the app bar on Home, Servers, Premium, and Settings tabs — title text, icons, and actions all still present and tappable.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/modern_app_bar.dart
git commit -m "Re-skin modern_app_bar to vpn master's styling"
```

### Task 3: Re-skin `splash_screen.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\shared\widgets\splash_screen.dart`
- Modify: `lib/shared/widgets/splash_screen.dart`

- [ ] **Step 1: Diff and list BonikVM-only symbols**

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\shared\widgets\splash_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\shared\widgets\splash_screen.dart"`

The vpn master file is 208 lines, BonikVM's is 187 — note what BonikVM removed/changed (likely simplified already) as well as what it added, so nothing routed through splash init (auth check, update check, navigation target) gets dropped.

- [ ] **Step 2: Port vpn master's splash visuals**

Apply vpn master's logo treatment, animation, and background to the BonikVM file, keeping all navigation/init logic identified in Step 1 unchanged.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/shared/widgets/splash_screen.dart`
Expected: no new errors.

- [ ] **Step 4: Manual visual check**

Cold-start the app and confirm the splash screen displays, then correctly routes to onboarding/sign-in/main-shell depending on auth state.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/splash_screen.dart
git commit -m "Re-skin splash_screen to vpn master's styling"
```

### Task 4: Re-skin `theme_provider.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\shared\providers\theme_provider.dart`
- Modify: `lib/shared/providers/theme_provider.dart`

- [ ] **Step 1: Diff the two files**

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\shared\providers\theme_provider.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\shared\providers\theme_provider.dart"`

These are nearly identical in length (278 vs 277 lines) — this is likely a near-trivial diff (color palette values, not structure). Identify exactly which color constants differ.

- [ ] **Step 2: Port vpn master's color palette**

Update the theme color values (light/dark scheme colors, `themeColorProvider` default/options) to match vpn master, keeping `ThemeMode`/`ThemeModeNotifier` class and provider names unchanged (every screen references `themeModeProvider` and `themeColorProvider` by name).

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/shared/providers/theme_provider.dart`
Expected: no new errors.

- [ ] **Step 4: Manual visual check**

Toggle dark/light mode from the drawer and confirm colors across Home/Servers/Settings match vpn master's palette.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/providers/theme_provider.dart
git commit -m "Port vpn master's theme color palette"
```

---

## Phase 2 — Core screens

### Task 5: Re-skin `home_screen.dart` and its sub-widgets

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\features\home\home_screen.dart`
- Modify: `lib/features/home/home_screen.dart`
- Modify (as needed): `lib/features/home/widgets/connection_stats_section.dart`, `lib/features/home/widgets/home_small_widgets.dart`, `lib/features/home/widgets/location_cards.dart`, `lib/features/home/utils/country_emoji.dart`

**Known preserve-list:**
- The disposed-widget guard on the delayed IP-refresh callback (fixed in commit `fb272ee` — a VPN-disconnect-then-navigate-away race). Search for the `ref` usage inside a `Future.delayed`/timer callback and confirm it checks `mounted` (or equivalent) before use; do not regress this fix while porting the surrounding UI.
- The extraction into `widgets/connection_stats_section.dart`, `widgets/home_small_widgets.dart`, `widgets/location_cards.dart`, and `utils/country_emoji.dart` — vpn master has this all inline in one file; keep BonikVM's split, re-skin the contents of each extracted widget to match vpn master's visuals instead of merging everything back into `home_screen.dart`.
- `connection_map_widget.dart` usage — **do not remove yet**, that happens in Phase 5 (Task 15). For this task, keep it wired as-is even though its styling may look dated next to the rest of the re-skinned screen.

- [ ] **Step 1: Diff and inventory**

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\features\home\home_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\features\home\home_screen.dart"`

Also read the four BonikVM sub-widget files listed above in full, since vpn master has their equivalent UI inlined in the single `home_screen.dart` — you'll be mapping vpn master's inline sections onto BonikVM's split files.

- [ ] **Step 2: Locate and note the disposed-widget guard**

Run: `grep -n "mounted" lib/features/home/home_screen.dart`

Confirm which callback this guards (the IP-refresh delay mentioned in commit `fb272ee`'s message) so Step 3 doesn't remove it while restyling that section.

- [ ] **Step 3: Port vpn master's visuals into the split files**

For each of `home_screen.dart`, `connection_stats_section.dart`, `home_small_widgets.dart`, `location_cards.dart`: apply vpn master's layout/colors/copy for the corresponding section, keeping the `mounted` guard from Step 2 and every provider/service call (VPN state, connection stats, server selection) unchanged.

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze lib/features/home`
Expected: no new errors.

- [ ] **Step 5: Manual visual check**

Run the app, connect/disconnect the VPN, and confirm: connection status UI updates correctly, IP address refresh doesn't crash on rapid disconnect-then-navigate, location card and stats sections render with vpn master's styling.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home
git commit -m "Re-skin home screen and sub-widgets to vpn master's styling"
```

### Task 6: Re-skin `servers_screen.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\features\servers\servers_screen.dart`
- Modify: `lib/features/servers/servers_screen.dart`

**Known preserve-list:**
- `serversScreenKey` (a `GlobalKey` referenced from `main_shell.dart`'s app bar actions for search/filter triggers — do not rename).
- `triggerSearchDialog()` / `triggerFilterDialog()` methods on the state class (called from `main_shell.dart`).
- `serversProvider` (invalidated/refreshed from `main_shell.dart`'s app bar refresh action).
- Any `Platform.isWindows` branch — leave it in place for this task; Phase 5 removes it separately.

- [ ] **Step 1: Diff and confirm preserved API surface**

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\features\servers\servers_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\features\servers\servers_screen.dart"`

Run: `grep -n "serversScreenKey\|triggerSearchDialog\|triggerFilterDialog\|serversProvider" lib/features/servers/servers_screen.dart`

Confirm these all still exist after Step 2's edits — `main_shell.dart` calls them by these exact names.

- [ ] **Step 2: Port vpn master's visuals**

Apply vpn master's server list layout, card styling, and filter/search dialog visuals, keeping the API surface from Step 1 unchanged.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/features/servers/servers_screen.dart lib/shared/widgets/main_shell.dart`
Expected: no new errors (checking main_shell.dart too since it calls into this file).

- [ ] **Step 4: Manual visual check**

Open the Servers tab, use the search icon and filter icon from the app bar (both call into this screen), select a server, and confirm the list still refreshes via the app bar's refresh button.

- [ ] **Step 5: Commit**

```bash
git add lib/features/servers/servers_screen.dart
git commit -m "Re-skin servers screen to vpn master's styling"
```

### Task 7: Re-skin `premium_screen.dart` and `billing_bottom_sheets.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\features\premium\premium_screen.dart`, `C:\Users\Dexter\StudioProjects\vpn master\lib\features\premium\billing_bottom_sheets.dart`
- Modify: `lib/features/premium/premium_screen.dart`, `lib/features/premium/billing_bottom_sheets.dart`

**Note:** vpn master's `premium_screen.dart` is 1320 lines vs BonikVM's 1418 — this screen exists in both (it's not a BonikVM-only addition despite the earlier assumption that Premium was purely post-rebase; verify in Step 1 whether vpn master's version is feature-equivalent or a genuinely older iteration of the same screen). `billing_bottom_sheets.dart` also exists in both (1696 vs 1861 lines).

**Do not touch in this task:** any `Platform.isWindows`/`windows_checkout.dart` branch — Phase 5 handles that removal.

- [ ] **Step 1: Diff both files and classify the differences**

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\features\premium\premium_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\features\premium\premium_screen.dart"`

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\features\premium\billing_bottom_sheets.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\features\premium\billing_bottom_sheets.dart"`

For each diff hunk, classify as: (a) pure visual/copy — port from vpn master, or (b) functional (payment provider wiring, `premiumScreenKey`, `refreshProducts()`, Windows checkout branch, subscription state) — keep BonikVM's version untouched.

- [ ] **Step 2: Port the visual hunks**

Apply the (a)-classified changes from Step 1, leaving (b)-classified code exactly as-is.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/features/premium`
Expected: no new errors.

- [ ] **Step 4: Manual visual check**

Open the Premium tab, open a billing bottom sheet for a plan, confirm `premiumScreenKey.currentState?.refreshProducts()` (triggered from the app bar refresh action) still works, and that the free-vs-premium badge states render correctly.

- [ ] **Step 5: Commit**

```bash
git add lib/features/premium/premium_screen.dart lib/features/premium/billing_bottom_sheets.dart
git commit -m "Re-skin premium screen and billing sheets to vpn master's styling"
```

---

## Phase 3 — Secondary screens

Each task in this phase follows the same four-step shape: diff, port visuals only (preserving any provider/service calls and navigation targets found in the diff), analyze, manually verify the screen opens and its actions work, commit. Preserve-lists below are only what's already known; confirm the full list via each task's own diff step.

### Task 8: Re-skin `settings_screen.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\features\settings\settings_screen.dart`
- Modify: `lib/features/settings/settings_screen.dart`

**Known preserve-list:** any `Platform.isWindows` branch (leave for Phase 5), all navigation entries to screens vpn master doesn't have equivalents for (e.g. debug/admin screens if linked from here).

- [ ] **Step 1:** `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\features\settings\settings_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\features\settings\settings_screen.dart"` — classify hunks as visual vs functional.
- [ ] **Step 2:** Port visual hunks only into `lib/features/settings/settings_screen.dart`.
- [ ] **Step 3:** Run `flutter analyze lib/features/settings/settings_screen.dart` — expect no new errors.
- [ ] **Step 4:** Open Settings tab, tap through each list item/toggle, confirm all still navigate/function.
- [ ] **Step 5:** `git add lib/features/settings/settings_screen.dart && git commit -m "Re-skin settings screen to vpn master's styling"`

### Task 9: Re-skin `support_screen.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\features\support\support_screen.dart`
- Modify: `lib/features/support/support_screen.dart`

- [ ] **Step 1:** `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\features\support\support_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\features\support\support_screen.dart"` (near-identical length, 551 vs 550 — likely a small diff; read it fully).
- [ ] **Step 2:** Port visual differences into `lib/features/support/support_screen.dart`, keeping any contact/URL-launch logic unchanged.
- [ ] **Step 3:** Run `flutter analyze lib/features/support/support_screen.dart` — expect no new errors.
- [ ] **Step 4:** Open Support screen from the drawer, confirm contact links/forms still work.
- [ ] **Step 5:** `git add lib/features/support/support_screen.dart && git commit -m "Re-skin support screen to vpn master's styling"`

### Task 10: Re-skin `about_screen.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\features\about\about_screen.dart`
- Modify: `lib/features/about/about_screen.dart`

- [ ] **Step 1:** `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\features\about\about_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\features\about\about_screen.dart"` (both 411 lines — read the full diff, likely copy/version-string differences).
- [ ] **Step 2:** Port visual/copy differences into `lib/features/about/about_screen.dart`. Note: `main_shell.dart`'s `_showAboutDialog()` (kept in Task 1) is a separate inline dialog, not this screen — don't conflate the two; this file is the standalone About screen if navigated to directly.
- [ ] **Step 3:** Run `flutter analyze lib/features/about/about_screen.dart` — expect no new errors.
- [ ] **Step 4:** Navigate to the About screen and confirm content/links render.
- [ ] **Step 5:** `git add lib/features/about/about_screen.dart && git commit -m "Re-skin about screen to vpn master's styling"`

### Task 11: Re-skin `onboarding_screen.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\features\onboarding\onboarding_screen.dart`
- Modify: `lib/features/onboarding/onboarding_screen.dart`

- [ ] **Step 1:** `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\features\onboarding\onboarding_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\features\onboarding\onboarding_screen.dart"` (both 220 lines).
- [ ] **Step 2:** Port visual differences (slide content, illustrations, page-indicator styling) into `lib/features/onboarding/onboarding_screen.dart`, keeping the completion/navigation callback that routes to sign-in or main shell unchanged.
- [ ] **Step 3:** Run `flutter analyze lib/features/onboarding/onboarding_screen.dart` — expect no new errors.
- [ ] **Step 4:** Fresh-install flow (or clear app state) and confirm onboarding displays and its "Get Started"/skip action routes correctly.
- [ ] **Step 5:** `git add lib/features/onboarding/onboarding_screen.dart && git commit -m "Re-skin onboarding screen to vpn master's styling"`

### Task 12: Re-skin `sign_in_screen.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\screens\auth\sign_in_screen.dart`
- Modify: `lib/screens/auth/sign_in_screen.dart`

**Known preserve-list:** any `Platform.isWindows` branch (leave for Phase 5), Google/Apple sign-in provider calls (`auth_providers.dart`, `google_login_config_service.dart` if referenced here).

- [ ] **Step 1:** `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\screens\auth\sign_in_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\screens\auth\sign_in_screen.dart"` — classify hunks as visual vs functional (1111 vs 1145 lines).
- [ ] **Step 2:** Port visual hunks only into `lib/screens/auth/sign_in_screen.dart`.
- [ ] **Step 3:** Run `flutter analyze lib/screens/auth/sign_in_screen.dart` — expect no new errors.
- [ ] **Step 4:** Run the sign-in flow end to end (or as far as test credentials allow) and confirm buttons/forms still submit.
- [ ] **Step 5:** `git add lib/screens/auth/sign_in_screen.dart && git commit -m "Re-skin sign-in screen to vpn master's styling"`

### Task 13: Re-skin `payment_options_screen.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\screens\payment\payment_options_screen.dart`
- Modify: `lib/screens/payment/payment_options_screen.dart`

**Known preserve-list:** any `Platform.isWindows` branch (leave for Phase 5), Stripe/PayPal payment provider calls.

- [ ] **Step 1:** `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\screens\payment\payment_options_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\screens\payment\payment_options_screen.dart"` — classify hunks (1750 vs 1741 lines, nearly identical size — expect mostly visual).
- [ ] **Step 2:** Port visual hunks only into `lib/screens/payment/payment_options_screen.dart`.
- [ ] **Step 3:** Run `flutter analyze lib/screens/payment/payment_options_screen.dart` — expect no new errors.
- [ ] **Step 4:** Walk through the payment options flow (test/sandbox mode) and confirm each payment method entry still routes to its handler.
- [ ] **Step 5:** `git add lib/screens/payment/payment_options_screen.dart && git commit -m "Re-skin payment options screen to vpn master's styling"`

### Task 14: Re-skin `receipt_screen.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\screens\payment\receipt_screen.dart`
- Modify: `lib/screens/payment/receipt_screen.dart`

- [ ] **Step 1:** `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\screens\payment\receipt_screen.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\screens\payment\receipt_screen.dart"` (both 510 lines).
- [ ] **Step 2:** Port visual differences into `lib/screens/payment/receipt_screen.dart`, keeping PDF-generation/share logic unchanged.
- [ ] **Step 3:** Run `flutter analyze lib/screens/payment/receipt_screen.dart` — expect no new errors.
- [ ] **Step 4:** Generate a test receipt and confirm the screen renders and share/export still works.
- [ ] **Step 5:** `git add lib/screens/payment/receipt_screen.dart && git commit -m "Re-skin receipt screen to vpn master's styling"`

---

## Phase 4 — Ad widgets

Re-skin visuals only. **Do not touch** init sequencing, ad-load callbacks, timeout values, or debug-build test-ad-ID logic hardened in commit `fb272ee` — verify each of those still matches BonikVM's current file after the port (they should be untouched, not merely "similar").

### Task 15: Re-skin `level_play_banner_ad.dart` and `level_play_rewarded_popup.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\widgets\level_play_banner_ad.dart`, `C:\Users\Dexter\StudioProjects\vpn master\lib\widgets\level_play_rewarded_popup.dart`
- Modify: `lib/widgets/level_play_banner_ad.dart`, `lib/widgets/level_play_rewarded_popup.dart`

- [ ] **Step 1: Diff both files**

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\widgets\level_play_banner_ad.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\widgets\level_play_banner_ad.dart"`

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\widgets\level_play_rewarded_popup.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\widgets\level_play_rewarded_popup.dart"`

Both files are the same line count in both trees (115 and 510) — this strongly suggests the diff is mostly/purely cosmetic (colors, container styling, copy), not a mediation-package migration (that already happened structurally without a line-count change). Confirm no `ironsource_mediation` imports appear in the vpn master version before porting anything — if they do, translate the call to the equivalent `unity_levelplay_mediation` API rather than copying it.

- [ ] **Step 2: Port visual differences**

Apply vpn master's container styling/copy to both files, leaving every SDK call, callback, and timeout value from the current BonikVM files unchanged.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/widgets/level_play_banner_ad.dart lib/widgets/level_play_rewarded_popup.dart`
Expected: no new errors.

- [ ] **Step 4: Manual check**

Run a debug build (which per commit `fb272ee` always uses Google's test ad unit IDs) and confirm a banner ad loads on Home/Servers and a rewarded popup can be triggered and completes its callback.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/level_play_banner_ad.dart lib/widgets/level_play_rewarded_popup.dart
git commit -m "Re-skin LevelPlay banner and rewarded ad widgets to vpn master's styling"
```

### Task 16: Re-skin `unified_ads_popup.dart` and `unified_ads_popup_simple.dart`

**Files:**
- Reference: `C:\Users\Dexter\StudioProjects\vpn master\lib\widgets\unified_ads_popup.dart`, `C:\Users\Dexter\StudioProjects\vpn master\lib\widgets\unified_ads_popup_simple.dart`
- Modify: `lib/widgets/unified_ads_popup.dart`, `lib/widgets/unified_ads_popup_simple.dart`

**Note:** `unified_ads_popup_simple.dart` is 462 lines in vpn master vs 367 in BonikVM — BonikVM's is meaningfully shorter, meaning real logic was removed/refactored there since vpn master (recall vpn master's own history includes "Refactor ad display logic in home and servers screens; update UnifiedAdsPopupSimple for single-ad mode" — so this file's *logic* already evolved past vpn master's snapshot, not just its look). Read both fully before deciding what's safe to port.

- [ ] **Step 1: Diff both files and read `unified_ads_popup_simple.dart` in full**

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\widgets\unified_ads_popup.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\widgets\unified_ads_popup.dart"`

Run: `diff "C:\Users\Dexter\StudioProjects\vpn master\lib\widgets\unified_ads_popup_simple.dart" "C:\Users\Dexter\StudioProjects\BonikVM\lib\widgets\unified_ads_popup_simple.dart"`

For `unified_ads_popup_simple.dart` specifically, identify what the ~95-line reduction removed (likely multi-ad-mode branching, given the "single-ad mode" refactor) and treat that as functional, not visual — do not reintroduce it.

- [ ] **Step 2: Port visual-only differences**

Apply vpn master's popup styling/copy to both files, keeping BonikVM's single-ad-mode logic in `unified_ads_popup_simple.dart` and all SDK calls in `unified_ads_popup.dart` unchanged.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/widgets/unified_ads_popup.dart lib/widgets/unified_ads_popup_simple.dart`
Expected: no new errors.

- [ ] **Step 4: Manual check**

Trigger both popup variants in a debug build and confirm they display and dismiss correctly, still in single-ad mode.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/unified_ads_popup.dart lib/widgets/unified_ads_popup_simple.dart
git commit -m "Re-skin unified ads popups to vpn master's styling, keep single-ad-mode logic"
```

---

## Phase 5 — Windows removal

### Task 17: Delete Windows-only files and pubspec entries

**Files:**
- Delete: `windows/` (entire folder)
- Delete: `lib/core/services/windows_google_auth.dart`
- Delete: `lib/core/services/windows_tray_service.dart`
- Delete: `lib/core/services/windows_v2ray_service.dart`
- Delete: `lib/core/services/windows_vpn_service.dart`
- Delete: `lib/core/services/windows_wireguard_service.dart`
- Delete: `lib/features/premium/windows_checkout.dart`
- Delete: `lib/widgets/connection_map_widget.dart`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Find every import of the files being deleted**

Run: `grep -rln "windows_google_auth\|windows_tray_service\|windows_v2ray_service\|windows_vpn_service\|windows_wireguard_service\|windows_checkout\|connection_map_widget" lib --include=*.dart`

Note every importing file — these imports (and the code that uses them) get cleaned up in Task 18, not this task. This task only deletes the files themselves; leave the dangling imports as a to-do for Task 18 (running `flutter analyze` after this step will surface them as missing-file errors, which is expected and confirms nothing was missed).

- [ ] **Step 2: Delete the files and folder**

```bash
git rm -r windows
git rm lib/core/services/windows_google_auth.dart lib/core/services/windows_tray_service.dart lib/core/services/windows_v2ray_service.dart lib/core/services/windows_vpn_service.dart lib/core/services/windows_wireguard_service.dart lib/features/premium/windows_checkout.dart lib/widgets/connection_map_widget.dart
```

- [ ] **Step 3: Remove Windows entries from `pubspec.yaml`**

Remove the `window_manager`, `tray_manager`, and `flutter_secure_storage` dependency lines, and the `windows:` sub-block under `flutter_launcher_icons:` (the `generate: true` / `image_path` / `icon_size` block noted in the spec).

**Correction (discovered during execution):** `flutter_secure_storage` is NOT
Windows-only — it's used unconditionally in `lib/core/api_client.dart`,
`lib/core/services/notification_service.dart`, and `lib/services/api_service.dart`
for cross-platform token storage. It was removed here in error and restored in
a follow-up commit. Only `window_manager` and `tray_manager` were correctly
Windows-only.

- [ ] **Step 4: Run `flutter pub get`**

Run: `flutter pub get`
Expected: succeeds with the three dependencies removed.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "Remove Windows-only files, folder, and pubspec dependencies"
```

(Analyze errors from the now-dangling imports found in Step 1 are expected at this point — Task 18 fixes them. Do not run `flutter analyze` as a gate for this task's commit.)

### Task 18: Sweep `Platform.isWindows` / Windows-only branches from remaining files

**Files:** (from the spec's inventory, re-verified fresh at this task's start per Step 1 below)
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

- [ ] **Step 1: Re-verify the file list**

Run: `grep -rl "Platform.isWindows\|dart:io" lib --include=*.dart`

Compare against the list above. Files earlier phases (1-4) already touched may have shifted line numbers but should still appear here if they had Windows branches; add any new file this turn up that isn't in the list above, drop any that no longer match (e.g. a `dart:io` import used for something unrelated to Windows, like a generic `Platform` check for mobile — confirm with `grep -n "Platform\." <file>` before assuming it's Windows-only).

- [ ] **Step 2: For each file, remove the Windows branch**

For every `if (Platform.isWindows) { ... } else { ... }` (or ternary/switch equivalent), delete the Windows branch and un-nest the remaining (mobile/web) branch so it always executes. For a bare `if (Platform.isWindows) { return ...; }` with no else, delete the whole block. Remove the now-unused `dart:io` import from any file where `Platform` was its only use (check with `grep -n "Platform\." <file>` — if no other `Platform.` reference remains after the edit, remove the import).

- [ ] **Step 3: Remove the dangling Windows-file imports found in Task 17 Step 1**

Delete the `import` lines for `windows_google_auth.dart`, `windows_tray_service.dart`, `windows_v2ray_service.dart`, `windows_vpn_service.dart`, `windows_wireguard_service.dart`, `windows_checkout.dart`, and `connection_map_widget.dart` from whichever files Task 17 Step 1 found, and remove the code blocks that used them (they were necessarily inside a `Platform.isWindows` branch already being deleted in Step 2, so this should already be handled — use this step as a final check).

- [ ] **Step 4: Run static analysis on the whole project**

Run: `flutter analyze`
Expected: zero errors, zero warnings related to missing files or unused imports.

- [ ] **Step 5: Full build verification**

Run: `flutter build apk --debug` (or `flutter build ios --debug --no-codesign` if on macOS; at minimum run the Android build since this is a Windows-removal check, not a re-skin check)
Expected: build succeeds.

- [ ] **Step 6: Manual smoke test**

Run the app on Android (emulator or device) and click through Home, Servers, Premium, Settings, and trigger a payment options screen open — confirm nothing crashes from a removed Windows code path being unexpectedly reached at runtime.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Remove Platform.isWindows branches from remaining files"
```

---

## Final verification

- [ ] Run `flutter analyze` at the repo root — zero errors/warnings.
- [ ] Run `flutter test` — the default `test/widget_test.dart` still passes.
- [ ] Run `flutter build apk --debug` — succeeds.
- [ ] Manual full click-through: onboarding → sign-in → Home → Servers → Premium → Settings → Support → About → Privacy/Terms → drawer items, in both light and dark mode.
- [ ] Confirm `windows/` folder and all `windows_*.dart` files are gone: `grep -rl "Platform.isWindows" lib` returns nothing, `Test-Path windows` (or `ls windows`) fails.
