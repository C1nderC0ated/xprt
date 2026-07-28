# DCX neo — Android Optimization Toolkit

<img width="224" height="117" alt="image" src="https://github.com/user-attachments/assets/36b493c2-fd83-4c39-a224-6f3d3a6d60d3" />

DCX neo is a Windows batch (`.bat`) front-end for **ADB**. Instead of typing
dozens of `adb shell` commands by hand, you pick options from a text menu and
DCX neo runs the right performance, battery and diagnostic tweaks for you. It
also covers the SystemUI-Tuner and SetEdit ground without root: status bar,
quick-settings tiles, the volume cap, and a settings explorer with
snapshot/diff, profiles, and live key watch.

> **Developed by AnOrmaluser12 · Updated by S1nt3r**

---

## ⚠️ Disclaimer — read this first

**Use DCX neo at your own risk.** It changes live system settings, properties
and `device_config` flags. Most changes are reversible and **a reboot usually
fixes anything that misbehaves**, but a few are device-dependent — see the
warnings on [Gaming](#gaming) and the [Troubleshooting](#troubleshooting)
table. Before applying a lot of changes, make a [Backup](#backup--restore).
DCX neo is a community tool, not affiliated with Google or any manufacturer.

---

## Table of contents

- [Requirements](#requirements) · [Setup](#setup) · [First run](#first-run)
- [Menu reference](#menu-reference): [Main](#main-menu) · [Gaming](#gaming) · [Battery](#battery) · [Optimize](#optimize-android) · [Auto](#auto-setup) · [CheckSetting](#checksetting-diagnostics) · [Tweaks](#tweaks) · [Backup & Restore](#backup--restore) · [Benchmark](#benchmark) · [App Manager](#app-manager) · [Wireless ADB](#wireless-adb) · [Settings Tools](#settings-tools)
- [What actually works](#what-actually-works-vs-placebo) · [Persistence & root](#persistence--root) · [Troubleshooting](#troubleshooting) · [Credits](#credits)

---

## Requirements

| Requirement | Notes |
|---|---|
| **Windows PC** | Runs in `cmd.exe`. Windows 10/11 recommended. |
| **ADB** | On your `PATH`, **or** as `adb.exe` in an `adb\` folder next to `DCX.bat` — DCX adds that folder to `PATH` itself, so it works even on images that disable current-directory executable lookup. |
| **Android device** | **USB debugging** enabled and the PC authorised. |
| **USB cable** | Or Wi-Fi — the built-in **Wireless ADB** menu (option 13) handles pairing/connecting. |

---

## Setup

1. **Install ADB** — download **Android SDK Platform Tools** from Google, then
   add it to your `PATH`, or drop `adb.exe` (and its DLLs) into an `adb\`
   folder next to `DCX.bat` (the Release already contains one; DCX `cd`s into it automatically).
2. **Enable USB debugging** — Settings → About phone → tap **Build number**
   ×7 → Developer options → **USB debugging**. Connect and tap **Allow** on the RSA prompt.
3. **Run** `DCX.bat` (double-click or from `cmd`).

---

## First run

On startup DCX neo sets up ANSI colours, verifies ADB, and waits up to 10 s for
an authorised device. If more than one is attached it asks which to target; if
none appears you can jump straight to **[W] Wireless ADB setup** or **[R]etry**
instead of exiting. It then prints your device model and Android API level, e.g.
`Device: Pixel 7   API level: 34`, and opens the main menu. The Main, Gaming,
Battery and Optimize screens show a live header with **uptime** and **CPU load**.

> Earlier builds got as far as the device line and then **closed instead of
> opening the menu** — see [Troubleshooting](#troubleshooting) if you're on an older copy.

---

## Menu reference

### Main menu

| # | Option | What it does |
|---|---|---|
| 1 | **Gaming** | GMS (full or safe subset), GPU renderer, ANGLE, display scaler, TCP/DNS… |
| 2 | **Battery** | Two pages of battery / background toggles + diagnostics. |
| 3 | **Optimize Android** | One-shot maintenance (dexopt, fstrim, cache, compile…). |
| 4 | **Auto** | Applies a batch of safe optimisations in one go. |
| 5 | **CheckSetting** | Full device diagnostic report. |
| 6 | **Tweaks** | Status bar, quick-settings tiles, volume cap, font scale, night modes, DeviceConfig sync and more — the SystemUI-Tuner-style toggles. |
| 7 | **Reboot** | Reboots the device. |
| 8 | **Exit** | Closes DCX neo (stops the ADB server when appropriate). |
| 9 | **Shell** | Interactive `adb shell`. |
| 10 | **Benchmark** | Quick CPU + storage micro-benchmark. |
| 11 / 12 | **Backup / Restore** | Save / re-apply toggleable settings. |
| 13 | **Wireless ADB** | Pair (Android 11+), connect by IP, enable via USB (`adb tcpip`) with auto-IP, disconnect. |
| 14 | **App Mgr** | Background restriction + debloat (remove/restore apps). |
| 15 | **Settings Tools** | Explorer, snapshot & diff, profiles, watch a key — these work on *any* settings key, not just the curated ones. |

---

### Gaming

| # | Option | What it does |
|---|---|---|
| 1 | **Toggle GMS** | Full disable/enable of Google Mobile Services (warns + confirms — disabling breaks push, Maps, sign-in, Pay…). Does **not** change Do Not Disturb / `zen_mode`. Also offers a **safe subset**: disable ads/telemetry-adjacent packages only (`adservices`, `as.oss`, mainline telemetry, federatedcompute, partnersetup, feedback, turbo) while keeping Play Services running. Reversible. |
| 2 | **Thermal override (temporary)** | `cmd thermalservice override-status` (0–6) to relax throttling. Usually clears on reboot — not a permanent cooling profile. Validated input. |
| 3 | **Toggle Package Verifier** | Play Protect package verification on/off. |
| 4 | **Toggle Game-Overlay** | Game Manager downscale + optional `game_overlay` DeviceConfig (14+ may need root). |
| 5 | **Performance props (debug/OEM dump)** | Large dump of debug/OEM `setprop`s — volatile and mixed; not a guaranteed FPS mode. Lasting bits are mainly `low_power` off + thermal reset. No longer switches off SQLite durability — [that trade isn't worth making](#what-actually-works-vs-placebo). |
| 6 | **TCP / DNS / network mode** | TCP receive-window hint, **Private DNS** (Cloudflare / Google / AdGuard / Quad9 / your own DoT hostname / back to automatic), preferred network mode (LTE/5G), full revert. ⚠️ see below. |
| 7 | **GPU Renderer** | Switch HWUI renderer: `skiagl` (default) / `skiavk` (Skia Vulkan) / clear. |
| 8 | **Force ANGLE for All Apps** | Route all GLES apps through ANGLE. ⚠️ see below. |
| 9 | **Display Scaler** | Lower render resolution + matching DPI (`wm size` / `wm density`) for more GPU headroom and lower power. Safe presets are computed live from the panel's native resolution (85 / 75 / 67 / 50 %), plus custom and one-tap reset. A separate **UI size (DPI-only)** mode changes element size without touching resolution — a stand-in for the **Smallest width** developer option that some OEMs (e.g. Huawei EMUI/HarmonyOS) disable. Reversible, no root, persists across reboot; **included in Backup/Restore** (override or `wm size`/`wm density` reset). |
| 10 | **Back** | — |

> **⚠️ Two of these are device-dependent (from real-world testing):**
> - **TCP / DNS / network mode** applies only a harmless TCP receive-window hint
>   by default (plus optional DNS / preferred-network). Earlier versions also
>   wrote deprecated Wi-Fi keys (`wifi_sleep_policy`, `wifi_idle_ms`…) that
>   **killed Wi-Fi on Android 15** — only **Revert** recovered it, not a reboot.
>   Those are gone; Revert still clears any leftovers from an old run.
> - **Force ANGLE** can **crash most apps on launch** on non-Pixel GPUs (e.g.
>   MediaTek). It's opt-in (Y/N) and **persists across reboots**, so a reboot
>   won't fix a crash loop — return here and **Disable**/**Delete**.

**GPU Renderer**, **ANGLE** and the **Display Scaler** are the genuinely
effective graphics switches. Verify a renderer change with
`adb shell dumpsys gfxinfo <package> | findstr Pipeline`, and a resolution
change with `adb shell wm size` / `adb shell wm density`.

---

### Battery

Two pages.

**Page 1**

| # | Option | What it does |
|---|---|---|
| 1 | **Toggle Power Saver** | `low_power` / `low_power_sticky` — real battery saver. |
| 2 | **Toggle Animation** | Animation scales + related accessibility/blur flags. Off also pins long-press timeouts (see Tweaks). |
| 3 | **Wi-Fi/BT scan and related** | `wifi_scan_always_enabled`, BT scan-always, scoring/netstats — not an OEM “auto Wi-Fi” switch. |
| 4 | **Toggle Sync (placebo key)** | Writes `master_sync_status` only — placebo on modern Android; kept for Backup round-trip. |
| 5 | **Samsung motion (OEM)** | OneUI motion-gesture keys. Placebo on non-Samsung devices. |
| 6 | **ZRAM preference (reboot)** | `zram_enabled` StorageManager preference; needs reboot; may no-op if the OEM has no zram toggle. |
| 7 | **Aggressive saver constants** | Not OEM “Extreme power saving” — tweaks `battery_saver_constants`, power mode, related flags. |
| 8 | **Toggle Send Error** | Crash/diagnostic reporting keys (`send_action_app_error` + OEM extras). |
| 9 | **ART lock profiling (dev)** | `device_config … disable_lock_profiling` — developer/debug only, not battery/FPS. |
| 10 | **Toggle Logs/etc** | Broad log/metric silencing. Does **not** freeze DeviceConfig server sync (that lives under Tweaks), no longer switches off SQLite durability ([why](#what-actually-works-vs-placebo)), and no longer deletes your `gpu_debug_layers` value. **On** now reverts everything **Off** sets, including `persist.*` props that survive reboot. |
| 11 | **Next Page** | — |
| 12 | **Back** | — |

**Page 2:**

| # | Option | What it does |
|---|---|---|
| 1 | **Toggle Log (For User Apps)** | Silence logging for third-party apps. |
| 2 | **Universal Toggle Logs/etc** | Sets/clears every `log.tag*` prop (`S` = Off; On clears them). |
| 3 | **Toggle Deviceidle Whitelist** | Add/remove Doze-whitelist apps (system-app removal is guarded with a protected list). |
| 4 | **Hibernate App** | Hibernate a specific package. **Android 14+ (API 34+) only** — earlier APIs are refused in-menu. |
| 5 | **Refresh Rate Lock** | Lock 60/90/120 Hz, adaptive (1–120), or restore. |
| 6 | **Force Doze Now** | Force deep idle now; unforce; or show state. |
| 7 | **App Hibernation (system-wide)** | Enable/disable Android 12+ system-wide hibernation. |
| 8 | **Account Sync Toggle** | Writes `master_sync_status` only — **placebo on modern Android** (UI says so). Real Auto sync is not rootless-writable; kept for Backup/Restore round-trip. See [What works vs placebo](#what-actually-works-vs-placebo). |
| 9 | **Voice Hotword Toggle** | Disable the always-on "Hey Google" pipeline. |
| A | **Wake-Lock Audit** | Battery-drain diagnostic (below). |
| B | **Toggle Finish Activities** | toggles `always_finish_activities` via ADB (many Android builds report the value correctly but only fully honor it when enabled through Developer Options). |
| C | **Per-app battery restrict** | One screen for a package: show inactive / standby-bucket / hibernation, then Light / Medium / Heavy / Unrestrict. Lighter than **Hibernate App** (no appops flood). Heavy needs API 34+. |
| 0 | **Back** | — |

**Wake-Lock Audit** collects the key battery dumps into one `%TEMP%` report —
held wake locks (`dumpsys power`), top holders since charge (`batterystats`),
Doze state (`deviceidle`), top wakeups (`alarm`) and CPU consumers
(`cpuinfo`) — then opens it in Notepad, paginates, or summarises, with a guide
for spotting the app draining your battery. The five dumps take ≈5 s with
progress shown; **0** or **Q** also work as Back on the report menu.

---

### Optimize Android

| # | Option | What it does |
|---|---|---|
| 1 | **Run bg-dexopt-job** | Trigger the background dexopt job. |
| 2 | **Run Fstrim** | Trim the filesystem. Runs **silently** (no output on success is normal); shows free space before/after. On some devices it only completes while charging + idle. |
| 3 | **Run Kill-all** | Force-stop background apps (skips the foreground app and protected packages). |
| 4 | **Run Compile App** | Compile a single package — pick a mode (`speed` / `speed-profile` / `verify` / `quicken` / `everything` / `everything-profile`) and name; both are validated and the package must be installed. |
| 5 | **Run Clear Cache** | Trim or wipe app caches (wipe needs root). |
| 6 | **Run Tweak SurfaceFlinger** | Refresh-rate-specific SF timing tweaks (below). |
| 7 | **Run Clear Last Used** | Reset app usage stats. |
| 8 | **Compile All Apps** | Recompile **every** app (modes below). |
| 9 | **Animation Speed** | Set all three animation scales (0 / 0.5 / 0.75 / 1.0 / custom). Custom input is validated to the documented 0–2 range (comma decimals like `1,5` accepted). |
| 0 | **Back** | — |

**Compile All Apps — modes:** `everything-profile` (**recommended** — heavy
but profile-aware), `everything` (heaviest standard), `speed` (hot methods
only), `speed-profile` (Android default), and **heaviest optimization** (full
all-method compile + layouts + dexopt; uses the most storage/time). Compiling
all apps can take **5–30+ min** and warms the device — keep it on a charger.

**Tweak SurfaceFlinger:** pick a refresh rate (**60/90/120/144 Hz**), then a
profile (**Balance / Low-latency / Conserving offsets**). These write volatile
`debug.sf.*` phase-offset props — they do **not** lock Hz (use Battery →
Refresh Rate Lock for that). **Remove** clears those known props with an empty
`setprop` (this boot) and offers an optional reboot. *(Until recently that clear
silently did nothing — see [Troubleshooting](#troubleshooting).)*

> **Dexopt/compile are version-aware** (no choice needed). On **API ≤ 33** DCX
> neo uses the classic `pm compile` / `pm bg-dexopt-job` path. On **API ≥ 34**
> dexopt is ART Service, so it uses `pm compile -m <mode> -f -a` (dropping
> removed flags like `--check-prof` / `--compile-layouts`) and prefers
> `pm art dexopt-packages -r bg-dexopt`, falling back to `pm bg-dexopt-job`
> where a build doesn't expose `pm art`.

---

### Auto Setup

Runs a curated batch in one pass: logging cleanup (WindowManager trace
channels, dropbox rate limits), dexopt, a temporary thermal override, the
universal log silencer, and experimental SurfaceFlinger phase offsets (volatile;
**not** a refresh-rate lock — see Optimize). Fastest way to a sensible baseline.

> Auto Setup deliberately does **not** enable ANGLE (earlier versions did on
> Android 12+, which crashed apps on some non-Pixel devices). ANGLE is opt-in
> only (Gaming → Force ANGLE), so Auto stays safe for every device.

---

### CheckSetting (diagnostics)

Generates a timestamped report at `%TEMP%\dcx_report_<timestamp>.txt` (never
overwritten, so you can compare before/after). It covers hardware (SoC, ABI,
model), software (version, patch, build), memory, storage, live state (uptime,
CPU, battery level/temp/voltage/health), display, **current values of the
tweaks DCX neo can change** (including `master_sync_status` labelled as placebo
and DeviceConfig `sync_disabled_for_tests`), network mode, Doze whitelist and
top RAM consumers. Open it in Notepad, paginate with `MORE`, show an inline
summary, or **Diff vs previous report** (`fc` against the last CheckSetting run;
path remembered in `%TEMP%\dcx_last_report_path.txt`). Generation is ~50 device
queries (≈8 s) and prints step-by-step progress; the window can't take input
until it finishes. On the report menu, **0** or **Q** also work as Back.

---

### Tweaks

SystemUI Tuner and SetEdit territory, with no root and no companion app — the
`adb shell` user already holds `WRITE_SECURE_SETTINGS`, which is exactly the
permission those apps ask you to grant them.

**Every write here is undo-protected**: the previous value is captured to
`%USERPROFILE%\dcx_backups\dcx_explorer_undo_<timestamp>.bat` before anything
changes, and all of these keys are also covered by [Backup](#backup--restore).
The Tweaks menu shows the session/last undo and last backup paths; **[14] Undo /
backups hub** opens them in Notepad, runs undo/restore (DCX stays open), or opens the backups folder.

| # | Option | What it does |
|---|---|---|
| 1 | **Clock — show seconds** | `secure clock_seconds`. Applies live — SystemUI watches the key. Heavily skinned clocks (some OneUI) ignore it. |
| 2 | **Battery percent** | `system status_bar_show_battery_percent`. Live on AOSP-based status bars. |
| 3 | **Icon blacklist** | `secure icon_blacklist` — hide status bar icons (rotate, alarm, bluetooth, DND, VPN…). 15-slot picker plus free text; icons that answer to two names write both. Re-hiding an icon can't pile up duplicates. |
| 4 | **Demo mode** | Freezes the status bar into a clean fixed state — full signal, no clutter, 12:00 — for screenshots. Purely cosmetic; ends on exit or reboot. |
| 5 | **QS tile editor** | `secure sysui_qs_tiles`. Add the tiles Android ships but doesn't show: `dream`, `font_scaling`, `qr_code_scanner`, `onehanded`, `reverse`, `hearing_devices`, `notes`, `reduce_brightness`… Add at the end or the front, remove, reset. Applies live. Existing OEM `custom(pkg/cls)` tiles are preserved (paren-aware split); typing a new `custom(...)` spec is still declined toward Shell. |
| 6 | **Volume cap** | The **software** safe-media-volume cap. ⚠️ see below. |
| 7 | **Heads-up notifications** | `global heads_up_notifications_enabled` — pop-ups on/off for every app at once. |
| 8 | **Font scale** | `system font_scale`, clamped 0.5–2.0 (outside that, layouts clip and dialogs lose buttons). Comma decimals accepted: `1,15` → `1.15`. |
| 9 | **Long-press timeout** | `secure long_press_timeout`. ⚠️ Battery → Animation → **Off** also pins this key to 250 and **On** deletes it — whichever you run last wins. |
| 10 | **Stay awake while charging** | `global stay_on_while_plugged_in`, a bitmask: AC=1, USB=2, wireless=4, dock=8 (add them; 0 = off). Rough on an OLED panel over time. |
| 11 | **Night** | Two different features share the name: **dark theme** (`cmd uimode night`) and **night light**, the warm blue-light filter (`night_display_*`). Both live here, labelled apart. |
| 12 | **More device tweaks** | Camera gestures (double-tap power, twist to flip), charging sounds/vibration, storage low-space warning, battery-saver auto-trigger, freeform windows (needs a reboot), default install location. |
| 13 | **DeviceConfig server sync** | `device_config set_sync_disabled_for_tests` — freezes **remote DeviceConfig flag updates**, not Google/account sync. Modes: `none` (default), `until_reboot`, `persistent` (survives reboot; confirm). Previously a silent side effect of Battery → Logs Off. Some builds (EMUI 14 among them) implement the setter but **not** the readback; DCX says so rather than displaying a mode it never read, and Backup skips the key instead of guessing. |
| 14 | **Undo / backups hub** | Open or run the session/last undo `.bat` (DCX stays open), open the backups folder, or open the last Backup file. Paths are shown on the Tweaks menu itself. |
| 15 | **Back** | — |

> **⚠️ Volume cap — what it is, and what it isn't.** It lifts the **software**
> cap and the *"raise above safe level?"* nag (the EU hearing-safety rule) by
> writing `global audio_safe_volume_state`. It does **not** raise the hardware
> amplifier ceiling — that lives in vendor gain tables (the engineering menu)
> and needs root. Android reads the key **once at boot** and re-writes it back
> to *active* after every boot on a capped device, so this is a **per-boot**
> switch: set it, reboot, and that session runs uncapped. To re-arm it after
> each reboot without walking the menus, keep a
> [Profile](#settings-tools). On Android 14+ a *sound dose* regime replaces the
> old cap entirely; the screen offers its live levers instead.

> **Dark theme won't budge?** Some ROMs lock night mode, and the uimode service
> then refuses the change **silently**. DCX prints the mode the device reports
> back rather than claiming success — if the readout doesn't move, that's the honest answer, not a bug.

---

### Backup & Restore

**Backup** reads the first-class Settings / `device_config` / props / Display
Scaler (`wm`) / DeviceConfig sync targets DCX neo toggles — **62 capture helpers**,
including every [Tweaks](#tweaks) key and the main Battery/Gaming switches
(not every Logs Off metric key) — and writes a **stand-alone restore
`.bat`** to `%USERPROFILE%\dcx_backups\dcx_backup_<timestamp>.bat`.

**ADB path:** those `.bat` files live under `%USERPROFILE%\dcx_backups` — *not* next to DCX’s local `adb\` folder. New backup/undo scripts:

- **Embed** the full `adb.exe` path DCX was using, also write
  `%USERPROFILE%\dcx_backups\dcx_adb_path.txt`, and fall back to `PATH`.
- **Stop with an error** (and wait for a key) if adb still can’t be found —
  they no longer silently no-op.
- Accept **`/nopause`** when DCX launches them from the menu so control returns
  to Tweaks / Restore without closing the shared console. Double-clicking a
  `.bat` still pauses with *Press any key to close this window*.
- Put helpers (`:dcx_do`, `:dcx_hold`, `:dcx_report`) **before** `:dcx_main` so
  restore lines stay in the main body and the hold always runs.

Re-run **Backup** (or any Tweaks write) once under this DCX to refresh older
scripts that still call bare `adb`, use `1) Add …` help text inside an `if`
block, or append restores after `:dcx_hold`.

```bat
@echo off
setlocal
set "DCX_NOPAUSE="
if /i "%~1"=="/nopause" set "DCX_NOPAUSE=1"
set "ADB=C:\...\DCX\adb\adb.exe"   :: embedded by DCX
...
echo Using adb: %ADB%
goto :dcx_main
:dcx_do
"%ADB%" shell %* >nul 2>&1
...
:dcx_hold
if defined DCX_NOPAUSE exit /b 0
pause
...
:dcx_main
set "DCX_OK=0" & set "DCX_FAIL=0"
call :dcx_do "settings put global window_animation_scale '1.0'"
goto :dcx_report
:: -> [OK] Restored n settings, none failed.
::    or [WARN] n restored, m FAILED - listed above.
```

Captured values are quoted; any settings/`device_config` key unset at backup
time becomes a `delete` (properties still become a comment) — so a restore
returns you to the exact prior state and never pins a property to an empty string.
Values are also read with delayed expansion **off**, so a value containing `!`
is captured whole; older files could store `Hi!There!` as `Hi` and then restore
that shortened text over your setting (see [Troubleshooting](#troubleshooting)).

**Backup refuses to run without the device attached, on purpose.** Reading a key
that the device doesn't answer for looks *identical* to a key that's genuinely
unset — both come back empty — and unset is recorded as *"delete this on
restore"*. A backup taken with the cable out would therefore be a file that
**erases** your settings instead of restoring them, so DCX checks the device is
there first and declines rather than write that.

**And it only says `Backup complete.` once it has checked the file is really
there** with real content in it. `%USERPROFILE%\dcx_backups` is exactly the sort
of folder antivirus and Controlled Folder Access guard; if the writes are
blocked, you get a clear failure and how to fix it — not a backup you *think*
you have and find out about later. **Restore reports what actually happened.** 
It's a long run of ADB writes — if the cable is pulled, wireless ADB drops or 
authorisation expires part-way, the rest silently do nothing. Newer backup files 
count every write and end with `[OK] n restored` or `[WARN] n restored, m FAILED`
naming the failures; DCX also re-checks the device is still connected afterwards, 
which covers backup files made before this existed. Restoring twice is harmless.

Because it's a normal batch file you can run it directly without DCX neo (double-click 
holds the window until you press a key), edit out lines you don't want, or share it to 
reproduce settings elsewhere. **Restore** lists backups (newest first), confirms, then 
applies the chosen one with `/nopause` so DCX stays open. Both can open the backups folder in Explorer.

---

### Benchmark

A quick, repeatable micro-benchmark (lower is better): a timed CPU loop, a
~10 MB random write and a ~10 MB sequential read (both via `dd`). Run it before
and after optimising to compare. Uses a portable shell loop, so it works on devices that lack `seq`.

---

### App Manager

App-level controls (background restriction + debloat), main menu **14**. **Everything here is reversible.**

| # | Option | What it does |
|---|---|---|
| 1 | **Restrict app background** | Deny `RUN_IN_BACKGROUND` for a package you name (stops it running in the background; saves battery). |
| 2 | **Allow app background** | Undo the above for a package. |
| 3 | **Debloat by package name** | Remove an app for the current user (`pm uninstall -k --user 0`). The name is checked against the Android package-name charset (a letter, then letters/digits/dots/underscores) *before* anything runs, then checked to be installed, then confirmed; data kept. |
| 4 | **Suggested bloatware** | Auto-detects your brand and lists only **vetted, safe-to-remove** packages that are **actually installed** (cross-vendor Facebook, optional Google apps, plus Xiaomi / Transsion / Samsung / Huawei sets). |
| 5 | **List installed packages** | Dump all packages — or user/updated apps (`-3`) where bloat usually lives — to Notepad. |
| 6 | **Restore a removed app** | Bring a debloated app back (`pm install-existing`). |
| 7 | **Back** | — |

**How removal works (and why it's safe).** Debloat uses `pm uninstall -k --user 0`: 
the app is removed only for the current user and its data is **kept** (`-k`). 
The APK stays in `/system`, so you can restore it any time via **option 6** or 
a **factory reset**. OTA updates may also bring packages back.

> **⚠️ Debloat warnings**
> - Only remove apps you recognise — removing a critical package can cause a
>   **bootloop**. DCX neo hard-blocks known offenders, including
>   **`com.hoffnung`** (looks like bloat on Transsion Tecno/Infinix/itel
>   phones but bootloops them), plus system UI, phone, settings, telephony
>   providers, and Huawei core services (`com.huawei.hwid`, push, FIDO/`hwasm`, OTA).
> - The **Suggested** lists only ever show packages that are both
>   community-vetted as safe *and* installed, and every removal asks for
>   confirmation. Lists are sourced from UAD-NG and community debloat guides.
> - If something breaks after a debloat, use **Restore** (option 6) or reboot;
>   a factory reset restores everything.

---

### Wireless ADB

Run DCX over Wi-Fi with no cable. Reachable from the main menu (**13**) or from the startup screen when no USB device is found (**[W]**).

| # | Option | What it does |
|---|---|---|
| 1 | **Pair with code** | Android 11+ one-time pairing: enter the `ip:port` **and 6-digit code** from Developer options → Wireless debugging → *Pair device with pairing code* (keep that dialog open — the code dies when it closes). |
| 2 | **Connect** | Connect to `ip[:port]`. On Android 11+ use the ip:port from the **main** Wireless-debugging screen — it's a **different port** than the pairing one, and changes after a reboot or re-toggle. Plain IP assumes port 5555. |
| 3 | **Enable over USB** | Classic method for any Android version: flips adbd to TCP/IP on port 5555 (`adb tcpip 5555`) while the cable is attached, auto-detects the phone's Wi-Fi IP from `ip route`, and offers to connect immediately. Reverts on reboot or via option 5. |
| 4 | **Disconnect** | Drop all Wi-Fi connections (USB unaffected). |
| 5 | **Back to USB** | `adb usb` for devices switched with option 3. |
| 6 | **Help** | Where to find the ports/code, per-version notes (incl. Huawei EMUI/HarmonyOS builds that hide the pairing dialog — option 3 works there). |
| 7 | **Select target device** | Pick which attached device DCX talks to when more than one is present. Sets `ANDROID_SERIAL`, so every later adb call follows without any `-s` flags. |
| 8 | **Back** | — |

> **Security note:** while Wireless debugging is on, any PC paired with the phone on the same network can run adb commands. Turn it off when done.

> **More than one device attached?** adb refuses to act when it cannot tell which device
> you mean — every command fails with *more than one device/emulator*. DCX now picks a
> target instead of walking into that: on startup, and again whenever this menu changes the
> connection list, it enumerates the authorised devices and sets `ANDROID_SERIAL` to the one
> you choose. One device is selected silently; two or more get a picker that labels each
> entry **USB** or **Wi-Fi**. The header then shows which transport is in use.
>
> This matters most for a case DCX creates itself: **Enable over USB** runs `adb tcpip 5555`
> and connects over Wi-Fi *while the cable is still attached*, so the same phone appears
> twice — once by USB serial, once as `ip:5555`. Either entry works; the picker just makes
> you say which. Pull the cable, or use **Disconnect**, if you would rather have one.

The old standalone `wirelessadb.bat` is **removed** — this menu replaces it
(that script only did `adb connect`, with no Android 11+ pairing support).
`opencmd.bat` remains if you want to use ADB separately from DCX neo.

---

### Settings Tools

The generic half. These work on **any** key in the settings provider, including
every key DCX has no menu row for — the [Tweaks](#tweaks) list is curated, this
one isn't. Reachable from the main menu (**15**).

| # | Option | What it does |
|---|---|---|
| 1 | **Settings explorer** | `list` / `get` / `put` / `delete` across `system`, `secure` and `global`. Every write echoes the exact command, asks to confirm, shows a read-back, and saves the old value to an undo script first. Keys and values are whitelist-validated — anything with spaces or shell metacharacters is declined toward **Shell** rather than mangled. |
| 2 | **Snapshot & diff** | Dump all three tables to `%USERPROFILE%\dcx_snapshots\`, flip a toggle in the device's own UI, dump again, diff. This tells you **exactly which key that toggle writes** — the fastest way to find OEM-specific settings DCX doesn't know about. |
| 3 | **Profiles** | Plain text in `%USERPROFILE%\dcx_profiles\`: `namespace`\|`key`\|`value` (or `DELETE`). **Save Tweaks-only** or **Save full stack** (Tweaks + Battery/Gaming keys: animation, refresh, ANGLE, low_power, zram, scan-always, hotword, etc.). Optional friendly filename. Apply re-writes every listed key in one pass — re-arm the volume cap or a whole stack after reboot. Comments (`#`) ignored; each line re-validated on apply. |
| 4 | **Watch a key** | Poll one known `namespace`/`key` once per second while you flip a toggle on the phone. Auto-stops when the value changes (or press **Q**). Faster than snapshot/diff when you already know which table to watch. |
| 5 | **Back** | — |

---

## What actually works vs. placebo

Android only reads a specific set of settings, properties and `device_config`
flags. Many "optimization scripts" set hundreds of made-up keys (e.g.
`persist.sys.cpu.governor`, `debug.cpufreq.max_freq`) that **Android never
reads** — they're stored but do nothing. DCX neo focuses on commands with a **real, documented effect**:

- **`pm compile` / `pm bg-dexopt-job` / `pm art dexopt-packages` / `fstrim`** —
  maintenance; the **most noticeable** wins (chosen per Android version).
- **Animation scales** — the classic "make it feel faster" tweak.
- **`debug.hwui.renderer`** (`skiagl`/`skiavk`) — the actual HWUI renderer.
- **`angle_gl_driver_all_angle`** — the official ANGLE switch (real, but
  device-dependent — see the Gaming warning).
- **`min_refresh_rate` / `peak_refresh_rate`** — real refresh-rate control.
- **`wm size` / `wm density`** — real logical-resolution and DPI control
  (Display Scaler). Lowering the render resolution is a genuine, no-root way to
  gain GPU headroom and cut power draw; `wm size reset` / `wm density reset` fully revert it.
- **`deviceidle force-idle`, app hibernation, `hotword_detection_enabled`,
  `persist.log.tag "*:S"`** — real battery/log switches.
- **`cmd appops … RUN_IN_BACKGROUND deny`, `pm uninstall -k --user 0`** —
  background restriction and (reversible) debloat (App Manager).
- **`clock_seconds`, `icon_blacklist`, `sysui_qs_tiles`** — real SystemUI
  tunables. SystemUI *observes* these keys, so they apply live with no restart:
  the tile list still reads from `sysui_qs_tiles` on current AOSP, content observer and all.
- **`audio_safe_volume_state`** — real, but honestly **per-boot**; Android
  re-arms it at every boot (see [Tweaks](#tweaks)).

> **Not every toggle is effective.** The **Account Sync** switch writes
> `master_sync_status`, which is a **placebo on modern Android** — nothing
> reads it, and the real master-sync state lives in the sync framework
> (`adb shell dumpsys content` → *Auto sync*), unreachable via `settings`
> without root (on Android 17, writing `master_sync_status 0` left *Auto sync:
> true* unchanged). It's kept only so Backup/Restore round-trips the value.

> **Other honesty labels (Battery / Gaming / Optimize):** Samsung **Motion**
> is OEM-only; **ZRAM** is a boot preference (may no-op); **Wi-Fi/BT scan**
> is not an OEM “auto Wi-Fi” switch; SurfaceFlinger profiles are experimental
> phase offsets (not Hz lock); **Performance props** are a debug/OEM dump.

> **Some famous tweaks are dead, and DCX won't ship them as decoration.**
> `policy_control` (the old immersive-mode key) — the framework class that
> implemented it is **gone from AOSP**, so it stores fine and does nothing on
> Android 11+. `sysui_qqs_count` — modern SystemUI no longer reads it.
> Tethering flags sit behind carrier entitlement checks that `settings` can't
> touch. All three would look like features and be placebo, so they aren't in
> the menus. If you want them anyway, **Settings Tools → Explorer** will write
> any key you like — declining a menu row isn't blocking you.

> **And some tweaks are removed because they're harmful, not because they're
> fake.** DCX no longer writes `debug.sqlite.journalmode OFF`,
> `debug.sqlite.syncmode OFF` or `debug.sqlite.wal.syncmode OFF` (they were in
> Battery → **Logs Off** and Gaming → **Performance props**). Those switch off
> SQLite's durability for **every database on the device**: `journalmode=OFF`
> removes the rollback journal, so a transaction interrupted by a crash, a
> kernel panic or a battery pull can't be rolled back and leaves a **corrupt
> database**; `syncmode=OFF` and its WAL counterpart stop SQLite calling
> `fsync`, so data an app believes is committed can vanish. What you'd be
> trading away is contacts, messages and app state — for write throughput you
> won't notice. `debug.sqlite.journalsizelimit` stays: it only caps the journal
> **file size** after commit and costs nothing in integrity. Both revert paths
> (Logs On, Performance Off) now clear the three props, so if you ran an older
> DCX and haven't rebooted, either one restores `fsync` immediately. Same
> reasoning already retired `debug.force_low_ram` from Logs Off and the
> vsync-disabling props from Performance Mode.

> CPU/GPU frequency and governor changes are **not** possible via `setprop` —
> they live in kernel sysfs and need **root**. Neither is the **speaker
> amplifier ceiling**: the engineering-menu "max volume" sliders edit vendor
> gain tables, root only. DCX neo doesn't pretend otherwise.

---

## Persistence & root

- `settings put` and `device_config put` values (animation scales, refresh
  rate, ANGLE, sync, hotword…) **persist** across reboots without root —
  **except on Android 14+**, where most `device_config put` writes from the
  shell need root (DCX warns once via `_dcfg_warn` when that applies).
  `device_config set_sync_disabled_for_tests` is covered by Backup/Restore.
- `setprop`-based changes (e.g. GPU renderer) apply immediately but **reset on
  reboot**; making them permanent needs root (Magisk module or `build.prop`).
- **Android 14+** routes dexopt through **ART Service**; DCX neo detects this
  at startup and adjusts the compile/dexopt commands automatically (details in
  [Optimize Android](#optimize-android)).
- Two keys are **deliberately not permanent**, because Android won't let them
  be: the **volume cap** is re-armed at every boot, and **freeform windows**
  need a reboot to take effect at all. For the first, keep a **Profile**
  ([Settings Tools](#settings-tools) → 3) and apply it after a reboot — that's
  the no-root, no-daemon equivalent of SetEdit's on-device boot queue.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| **"ADB not found"** on launch | Install Platform Tools and add to `PATH`, or put `adb.exe` in an `adb\` folder next to `DCX.bat`. |
| **"ADB not found" even though `adb\` is right there next to `DCX.bat`** | Fixed. DCX `cd`s into `adb\` and then calls bare `adb`, which worked only because cmd searches the current directory for executables. Windows images that set `NoDefaultCurrentDirectoryInExePath=1` — hardened and enterprise builds do — turn that off, so every one of the ~1500 adb calls failed and the error told you to install the Platform Tools you already had. DCX now puts that folder on `PATH` explicitly instead of trusting the current directory. Verified both ways: with the variable set the old code reported *ADB not found* and the new code finds it, and nothing changes on a normal image. |
| **"No authorised device found"** | Enable USB debugging, replug, tap **Allow** on the phone. Check `adb devices` shows `device` (not `unauthorized`). No cable? Press **[W]** for Wireless ADB. |
| **Stuck in the paginated report view — Q works but 0 does nothing** | Working as designed, now signposted. The paginated view is Windows' own **MORE** pager, and it only understands its own keys: **SPACE** next page, **ENTER** one line, **Q** quit. `0` is a DCX *menu* key, so it means nothing to MORE. Both report screens now spell the keys out before paging **and** put them in the window title, where they stay visible on every page instead of scrolling away. |
| **CheckSetting / Wake-Lock Audit ignored keypresses and had no way out** | Fixed. Those two report menus were the only ones without the tight re-ask every other menu has, and they had no `cls` — so *any* miss redrew the whole block, including the phantom empty line the console hands `set /p` right after ~50 adb probes. Your first keypress looked ignored, and repeated misses stacked copies of the menu until **Back** scrolled off screen. Reproduced: the old menu spun in an infinite redraw loop and had to be killed; the fixed one re-asks in place. Both now redraw only on a real return and accept **0** or **Q** as Back. |
| **CheckSetting / Wake-Lock Audit look frozen while generating** | Partly by design, now visible. The report is ~50 device queries (≈8 s) and ~5 dumps (≈5 s), and batch has no way to accept a keypress mid-run — so the window genuinely can't respond until it finishes. It now says so up front and prints step-by-step progress (`[3/6] display and graphics…`) instead of sitting blank. There is no mid-run abort; close the window if you must. |
| **"Clear"/"Remove"/"On" said it worked but the property was still set** | Fixed — and it hit four features. `adb shell setprop KEY ""` **never clears anything**: cmd strips the quotes, adb re-joins the arguments, and the phone gets `setprop KEY` with one argument, so it prints `usage:` to a swallowed stderr and changes nothing. Affected **SF → Remove**, **Universal Toggle Logs → On**, **Toggle Logs/etc → On** (`persist.log.tag`) and **GPU Renderer → Clear override** — all reporting success. Now `''`, which survives the round trip; verified on-device. Same quote-stripping as the `sysui_qs_tiles` restore bug. |
| **DeviceConfig server sync shows "none" / always warns the change didn't apply** | Some builds (EMUI 14 included) implement the setter but not the getter — `get_sync_disabled_for_tests` answers *"Invalid command"*. DCX used to read that as `none`, so the screen showed a mode it had never read, the verifier reported a failure it couldn't know about, and **Backup wrote a restore line for a value it never captured**. It now detects the unreadable case, says so, reports `[NOTE] cannot confirm` instead of a false warning, and skips the key in Backup. |
| **DCX closed by itself right after detecting the device — the main menu never appeared** | Fixed; the big one. After picking the target the script fell *through* into `:pick_device` a second time, and that pass wasn't a `call`, so its `exit /b` ended the batch file. The menu was unreachable on a normal USB start — the only way in was the no-device → **[W]** Wireless ADB → **Back** detour, which is why it looked like "works over Wi-Fi, closes over USB". One `goto` fixes it; the two-device picker also no longer appears twice. |
| **Wireless connect says "failed to authenticate" / "connection refused"** | Pair this PC first (Wireless ADB → option 1), or the port went stale — it changes on reboot/re-toggle, so grab it fresh from the Wireless-debugging screen. |
| **Something feels broken after tweaking** | **Reboot** — most live tweaks reset on reboot and that clears it. |
| **A tweak "didn't do anything"** | Read the value back via **CheckSetting** (graphics: `dumpsys gfxinfo <pkg> \| findstr Pipeline`). Some keys need root or a newer Android. |
| **CheckSetting report or Wake-Lock Audit saved empty / blank** | Fixed — a bare `)` in an echo annotation like `(first 15)` closed the redirected `( … ) > file` block early; annotations are now escaped (same fix covers the background-dexopt failure list). |
| **CheckSetting/Wake-Lock report shows `can't create nul` / `findstr` errors, or a blank section** | Fixed — the `\| findstr` filtering leaked to the Android shell; it now runs Android-side (`adb shell "… 2>/dev/null \| grep …"`). **This originally only covered the generated report.** Wake-Lock Audit → **[3] Show summary only** kept the old form (`adb shell dumpsys power ^<nul 2^>nul ^\| findstr …`): those carets belong inside a `for /f ('…')` clause, and out in the open they make `<`, `>` and `\|` literal, so the whole string was handed to adb and run on the *phone* — which has no `findstr` and no `nul` device. That view now uses `grep` Android-side like the rest, so it prints wake locks instead of shell errors. |
| **Box characters / logo turn into `?????` after a report or backup (until relaunch)** | Fixed — the timestamp used `powershell Get-Date`, which resets the console code page on exit; it's now built in pure `cmd` from `%date%`/`%time%`. The two places that still need PowerShell (SurfaceFlinger Hz math, quick-settings tile tokenizer) each run `chcp 65001` immediately afterwards, so the code page is restored rather than left for the next `:logo` redraw to repair. |
| **First apply in a menu jumps back without pausing (second time is fine)** | Fixed — an `adb shell` forwards stdin, so `pause` ate a keystroke; every `adb shell` before a pause now reads stdin from `nul` (`<nul`). |
| **DeviceConfig flags stopped updating after Logs Off / Sync Off** | Fixed — `set_sync_disabled_for_tests persistent` was a silent side effect of those toggles. It now lives only under **Tweaks → DeviceConfig server sync**; pick **Allow sync (none)** to undo a leftover freeze. |
| **QS tile Add/Remove crashed or wrecked the list on Huawei/OEM** | Fixed — lists with `custom(pkg/cls)` tokens are split paren-aware and written with shell quoting. |
| **Force Doze "did nothing" / the device stayed awake** | Doze only holds when the phone is **unplugged**, and the adb cable counts as charging. Fixed — *Force* now sends `dumpsys battery unplug` **before** `deviceidle force-idle`, and *Undo* pairs `deviceidle unforce` with `dumpsys battery reset`, matching the documented Android sequence. While forced, the battery UI shows a spoofed *unplugged* state until you pick **Undo**. Both options refuse if no device is attached. Note: some ROMs (e.g. EMUI) run their own power management that can override AOSP doze — if state stays `ACTIVE`, that's the ROM, not DCX. |
| **App-hibernation crashed the script when I typed a package name** | Fixed — a package name containing `)` closed a `for … do ( )` loop early at parse time; the one in-loop use now expands the name late (`!pkgv2!`) so parentheses are safe. Same class as the CheckSetting `(first 15)` annotation fix. |
| **Clear Caches said "complete" but nothing was wiped** | Fixed — on a non-rooted device `su` did nothing silently; it now probes for root first and says *Root is not available — nothing was wiped*. |
| **Clear Last Used printed a wall of `No shell command implementation`** | Fixed — that `usagestats` subcommand is missing on many builds; the per-package error is now suppressed Android-side. |
| **A restore said it worked when it didn't / partially failed** | Fixed — restore is a long run of ADB writes, and if the cable is pulled, wireless ADB drops or authorisation expires part-way, the rest silently no-op. It used to print *Restore complete.* regardless, leaving a half-restored device you believed was fine. Backup files now count what actually landed and report `[OK] n restored` or `[WARN] n restored, m FAILED` with the failures listed; DCX prevents adb quote-stripping, which prevents partial failure, and also re-checks the device is still connected afterwards, which catches the disconnect case for backup files made before this change. Restoring twice is harmless. |
| **Clear Last Used / Log for user apps took ~30 seconds** | Fixed — those three actions ran one `adb shell` per package, and on a 269-package device that's ~27 s of pure USB round-trip for work the phone finishes in milliseconds. They now run the loop inside a single device shell session: same packages, same per-package progress lines, without the transport cost. Clear Last Used also pauses before returning to Optimize so a leftover keystroke can't skip the menu prompt. |
| **Most apps crash after enabling ANGLE** | Common on non-Pixel GPUs; **a reboot won't help** (it persists). Gaming → Force ANGLE → **Disable**/**Delete**. |
| **Name lookups stopped working after setting Private DNS** | Some networks (hotel/captive portals, some corporate Wi-Fi, a few mobile carriers) block outbound DNS-over-TLS, and Android then fails lookups rather than falling back. Gaming → **TCP / DNS / network mode** → **Private DNS** → **Automatic (device default)** puts it straight back. That option exists on its own precisely so you don't have to use **Revert**, which would also drop the TCP hint and network mode. |
| **Wi-Fi died after TCP / DNS / network mode (old Network Boost)** | Gaming → **TCP / DNS / network mode** → **Revert** (clears any old Wi-Fi keys). |
| **ART Service printed a wall of text** | Not errors — older versions dumped a line per package. Current builds show a summary (optimised/failed) and only real failures; a few failures are normal. The heading said *"Failed entries (first 15)"* while actually paging through every one of them — the cap is now real, and if there are more it says how many it withheld rather than truncating quietly. |
| **App Manager → List installed packages showed an old list** | Fixed — only `1`/`2`/`3` were handled with no re-ask, so any other key ran no `pm list` and fell through to opening the file. That file has a fixed temp name, so you got the *previous* run's packages, unmarked — and debloat decisions get made off it. Invalid input now re-asks, the file is cleared before each dump, and an empty result says so. |
| **DCX said a package was installed when it wasn't (or acted on the wrong one)** | Fixed — the probe was a *substring* match, so `com.foo` matched `com.foobar`'s line. All ten call sites now match the whole line. Note the one-character fix (`findstr /x`) alone would have been worse than the bug: adb output can arrive LF-only, which makes findstr see one long line and report *every* package as missing. The output is normalised with `find /v ""` first — the trick Snapshot already uses — verified under both LF-only and CRLF. |
| **Back from Clear Cache landed in the wrong menu** | Fixed — every screen under **Optimize → Clear Cache** exited two levels up to Optimize, so *Back* skipped its own parent and finishing a trim or wipe dumped you out of the section. Each screen now returns to the one it came from. |
| **A backup restored a shortened value** | Fixed; worth knowing if you have old backups. Capture ran with delayed expansion on, which **eats `!`** — `Hi!There!` was stored as `Hi`, and that shortened text is what a restore wrote back over your setting. The four capture helpers now read with it off. Rare (few Android values contain `!`), but re-run **Backup** for a clean file. |
| **A Tweaks change wasn't in the undo script / "this change will NOT be recorded"** | The undo script is rewritten in place before each capture, and the old code checked only that the temp file *existed*, not that it had survived — so a failed rewrite could silently replace a populated undo script with an empty one. It now requires the rewrite to still carry its `:dcx_main` label, keeps the original on any doubt, and **says so** when a write won't be undoable. If you see that warning, check `%USERPROFILE%\dcx_backups` isn't blocked by antivirus or Controlled Folder Access. |
| **Logs On didn't fully undo Logs Off** | Fixed — `persist.debug.trace_layouts` was set by Logs Off and never reverted, and `persist.*` survives reboot, so one Logs Off pinned it off for good. Logs Off also used to `delete` your `gpu_debug_layers` value, which nothing could restore; that delete is gone, since the master switch beside it already disables the feature. |
| **"Unknown option: --compile-layouts" / "Unknown command"** | Expected on Android 12+ (removed; gone on 14+ under ART Service). DCX neo skips it automatically and continues. |
| **Bootloop / something broke after debloat** | Boot to recovery and **factory reset** restores every removed app (they're never deleted from `/system`). To revert a single app, use **App Mgr → Restore**. |
| **Volume cap is back after a reboot** | By design, not a bug — Android re-writes `audio_safe_volume_state` to *active* at boot on a capped device. Re-apply it, or keep a **Profile** (Settings Tools → 3) and apply that after each reboot. |
| **Dark theme won't switch** | Some ROMs lock night mode and the service ignores the request **silently**. The readout on the Night screen is the device's own answer — if it doesn't move, the ROM refused. |
| **A quick-settings tile I added never appeared** | The spec was wrong. SystemUI drops unknown tile specs instead of breaking the panel, so a typo costs you the tile quietly. Use the names listed on the Tile editor screen. |
| **Clock seconds / battery percent did nothing** | Heavily skinned status bars (some OneUI, EMUI) don't read the AOSP keys. The key is set; the skin ignores it. Nothing to fix. |
| **Freeform windows did nothing** | It needs a **reboot** — it's a developer-options key. The screen offers one. |
| **A profile line was skipped when I applied it** | Deliberate. Profiles are hand-editable, so every line is re-validated: a bad namespace, key or value prints `skip - …` and the rest of the profile still runs. |
| **A value with `&` or `\|` was accepted by a prompt that should have rejected it** | Fixed. The charset checks were built as `echo(value \| findstr …`, and a pipe makes cmd hand the *already-expanded* text to a child that parses it again — so `1&echo hi` split at the `&`, findstr saw only `1` and reported **valid**, while the half after the `&` ran inside the pipe with its output swallowed. The check passed the bad value *and* executed part of it. The package-name and DoT-hostname validators are now pipe-free (`for /f "delims=…"`, which never builds a command line), and every remaining prompt runs the pipe-free `:_tw_safechk` first so `&`, `\|`, `<`, `>` can't reach the pipe. Verified: the same input that used to be accepted is now rejected at every prompt. |
| **A package name with odd characters did something strange, or the window closed** | Fixed — package names are free text, and they used to reach `adb shell … %pkg%` through *immediate* expansion, so a name containing `&`, `\|`, `<` or `>` was parsed by cmd as an operator instead of passed as data. Every use is now late-expanded (`!pkg!`), which makes those characters literal, and a charset check runs before the value reaches adb at all. Note the old "is it installed?" probe could never have caught this: that line expanded the value too. |
| **Backup/undo `.bat` flashes and closes / says `Add was unexpected at this time.`** | Fixed — help text used `1) Add …` inside an `if ( )` block (cmd treated `1)` as the end of the block), and undo lines could land *after* `:dcx_hold` so a double-click exited before any restores. New scripts use `[1]`/`[2]`/`[3]`, put helpers before `:dcx_main`, and always pause unless `/nopause`. Re-run **Backup** or a Tweaks write to regenerate; or use Tweaks → **[14]** on the repaired session undo. |
| **Running undo/restore from DCX closed the whole DCX window** | Fixed — DCX now launches those scripts with `cmd /c … /nopause` so the child cannot take over (or kill) the menu console. |
| **Standalone backup/undo can’t find adb / restores nothing** | Fixed — scripts embed DCX’s `adb.exe` path (plus `dcx_adb_path.txt` / PATH). If adb is still missing they print `[ERROR]` and wait. Regenerate under current DCX if an old file still calls bare `adb`. |
| **Want to undo everything** | **Restore** a backup, or run the undo script a Tweaks/Explorer write left in `dcx_backups\`, or reboot for non-persistent changes. |
| **Every command says `more than one device/emulator`** | Fixed — DCX now sets `ANDROID_SERIAL` to a device you pick, so adb stops guessing. It asks on startup and after any Wireless-ADB change; you can re-pick any time from **Wireless ADB → [7] Select target device**. The usual cause is *Enable over USB*, which deliberately leaves the phone connected by cable **and** Wi-Fi at once. |
| **SurfaceFlinger tweak says it could not compute the offsets** | Working as intended. That screen needs PowerShell for the phase-offset arithmetic; if it is unavailable the values would come out empty and get written to `setprop` as blanks. DCX now checks and refuses instead — your current SF properties are left untouched. |
| **Colours / alignment look wrong** | Use Windows Terminal or a recent `cmd.exe`; very old consoles don't render ANSI colours or box characters. |

---

## Credits

- **AnOrmaluser12** — original author ([@AnOrmaluser12](https://github.com/AnOrmaluser12))
- **S1nt3r** — updates and fixes

DCX is provided **as-is, with no warranty**. You are responsible for any changes you apply to your device.

---

## License & Media Notice

This project's source code is licensed under the **GNU GPLv3**.

Exception: the image file [4152900.jpg] is excluded from the GPL-3.0 license.
It is owned by its respective creator and is included strictly for personal, non-commercial display. 
If you fork or reuse this project, you must remove or replace this image.
