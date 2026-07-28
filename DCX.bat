@echo off
setlocal EnableDelayedExpansion
chcp 65001 > nul
mode 100,37
title DCX Menu
:: ============================================================
:: FIX: ESC and colour codes MUST be defined BEFORE first use.
:: Previously the ADB-not-found message referenced %ESC% which
:: was still empty at that point, so colours never rendered.
:: ============================================================
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set g=%ESC%[92m
set r=%ESC%[91m
set red=%ESC%[04m
set l=%ESC%[1m
set w=%ESC%[0m
set b=%ESC%[94m
set m=%ESC%[95m
set p=%ESC%[35m
set c=%ESC%[35m
set d=%ESC%[96m
set u=%ESC%[0m
set z=%ESC%[91m
set n=%ESC%[96m
set y=%ESC%[40;33m
set g2=%ESC%[102m
set r2=%ESC%[101m
set t=%ESC%[40m
set gold=%ESC%[93m
:: Safely navigate to adb folder if it exists
if exist adb\ cd adb
:: Put that folder on PATH explicitly instead of trusting the current directory.
:: DCX calls bare "adb" ~1500 times and relied on cmd searching the current directory -
:: which it normally does, but NOT when NoDefaultCurrentDirectoryInExePath=1, a setting
:: hardened and enterprise Windows images do apply. There the bundled adb\ sits right
:: here and EVERY call still failed, with a message telling the user to go install the
:: Platform Tools they already have. %CD% is correct on this line because it is a
:: top-level statement: cmd expands it when the line runs, i.e. after the cd above.
:: (Inside a ( ) block it would expand at parse time and still name the old directory.)
if exist adb.exe set "PATH=%CD%;%PATH%"
:: Verify ADB is available
adb version > nul 2>&1
if %errorlevel% neq 0 (
    echo [%r%^^!%w%] ADB not found^^!
    echo     Please install ADB and ensure it is in your PATH
    echo     or place this script next to an 'adb' folder.
    echo.
    echo Press any key to exit...
    pause > nul
    exit /b
)
:: Full path to the adb.exe DCX is actually using. Backup/undo .bat files live
:: in %%USERPROFILE%%\dcx_backups - they do NOT see the local adb\ folder -
:: so generators embed this path (and refresh dcx_adb_path.txt).
call :_resolve_adb
call :logo
echo                         %m%DCX Developed By AnOrmaluser12, Updated By S1nt3r%d%
echo                                    %r%Use It At Your Own Risk%w%
echo                         %y%A Restart Is Required If Something Is Misbehaving%w%
echo.
echo.
echo                                  %w%Press Any Button To Continue
pause > nul
title Connecting . . .
adb start-server > nul 2>&1

:startup_wait
:: ============================================================
:: NEW: Wait for a device and verify it is connected/authorised
:: before issuing further adb shell calls. Previously the script
:: charged ahead even with no device, producing silent failures.
:: ============================================================
echo.
echo [%b%i%w%] Waiting for an authorised device (max 10s)...
set "DEVICE_OK=0"
for /l %%i in (1,1,10) do (
    if "!DEVICE_OK!"=="0" (
        for /f "skip=1 tokens=1,2" %%a in ('adb devices ^<nul') do (
            if "%%b"=="device" set "DEVICE_OK=1"
        )
        if "!DEVICE_OK!"=="0" timeout /t 1 /nobreak > nul
    )
)
if "%DEVICE_OK%"=="0" (
    cls
    call :logo
    echo [%r%^^!%w%] No authorised device found.
    echo     - Enable USB debugging on the device
    echo     - Approve the RSA fingerprint prompt
    echo     - Check the cable / driver
    echo.
    echo     Run 'adb devices' manually to verify.
    echo.
    echo     No cable handy? Wireless ADB can connect over Wi-Fi instead.
    echo.
    echo    [W] Wireless ADB setup    [R] Retry    [X] Exit
    choice /c WRX /n >nul
    if errorlevel 3 (
        adb kill-server > nul 2>&1
        exit /b
    )
    if errorlevel 2 goto startup_wait
    rem Wireless path skips the probe below - give SDK/MODEL safe
    rem defaults; :wadb_back re-runs :detect_device once connected.
    set "SDK=0"
    set "MODEL=(not connected yet)"
    goto wirelessadb
)
rem  A device answered - now decide WHICH one, before any adb shell runs. With two
rem  attached (phone + tablet, an emulator, or the USB/Wi-Fi pair "Enable over USB"
rem  creates) every call below would otherwise fail with "more than one device".
call :pick_device
rem  MUST jump over :pick_device. Without this the routine is entered a SECOND time by
rem  fall-through - and that pass is not a `call`, so its `exit /b` runs at top level and
rem  ENDS THE SCRIPT. :detect_device and :menu were unreachable on the normal USB start;
rem  the only way in was the no-device -> [W] Wireless ADB -> Back detour.
goto detect_device

:pick_device
:: Decides WHICH attached device every later adb call talks to, by setting ANDROID_SERIAL.
::
:: Why this is needed. adb refuses to act when more than one device is attached - every
:: command dies with "more than one device/emulator" - and DCX had no targeting at all:
:: no -s, no ANDROID_SERIAL, across ~1500 adb calls. The startup probe only checked that
:: AT LEAST ONE device was authorised, so it happily reported a healthy device and then
:: every menu failed.
::
:: The case that makes this urgent is one DCX creates itself. Wireless ADB -> "Enable over
:: USB" runs `adb tcpip 5555` and connects over Wi-Fi WHILE THE CABLE IS STILL IN, so the
:: same phone appears twice: once by USB serial, once as ip:5555. From that moment the whole
:: tool stops working, through its own documented workflow.
::
:: ANDROID_SERIAL is why this costs one routine instead of 1500 edits: adb reads it from the
:: environment, and a batch `set` is inherited by every child process. No call site changes.
::
:: Returns 1 when nothing is attached, so callers can keep their existing no-device paths.
:: Clear last run's arrays first - re-picking after a disconnect would otherwise leave
:: _pd_s[3] behind from a three-device run and quietly outlive the list it described.
for /f "delims==" %%v in ('set _pd_s[ 2^>nul') do set "%%v="
for /f "delims==" %%v in ('set _pd_d[ 2^>nul') do set "%%v="
set "_pd_n=0"
for /f "skip=1 tokens=1,2,*" %%a in ('adb devices -l ^<nul 2^>nul') do (
    if "%%b"=="device" (
        set /a _pd_n+=1
        set "_pd_s[!_pd_n!]=%%a"
        set "_pd_d[!_pd_n!]=%%c"
    )
)
if "%_pd_n%"=="0" (
    set "ANDROID_SERIAL="
    exit /b 1
)
if "%_pd_n%"=="1" (
    set "ANDROID_SERIAL=!_pd_s[1]!"
    exit /b 0
)

:_pd_ask
cls
call :logo
echo.
echo  %y%More than one device is attached.%w% adb cannot guess which one you mean, so
echo  pick the target - everything DCX does from here goes to it.
echo.
for /l %%i in (1,1,%_pd_n%) do call :_pd_row %%i
echo.
echo  If one entry is USB and another is Wi-Fi with the same model, that is the SAME
echo  phone reached two ways - either works, and "Enable over USB" leaves it like this.
echo.
set "_pd_c=" & set /p _pd_c="Device number >> "
if not defined _pd_c goto _pd_ask
:: safechk before the probe below: it is pipe-free, so it rejects & | < > before they
:: can reach a pipe that would re-parse them. Same order as the Tweaks screens.
call :_tw_safechk _pd_c || goto _pd_ask
echo(!_pd_c!| findstr /r /x /c:"[0-9][0-9]*" >nul || goto _pd_ask
if !_pd_c! LSS 1 goto _pd_ask
:: "01" passes all three checks above - findstr accepts it, and 01 compares as 1 - but
:: _pd_s[01] is not a variable that exists, so the assignment would silently blank
:: ANDROID_SERIAL and hand adb straight back the ambiguity this routine exists to remove.
:: Range checks are not enough; require the entry itself. (set /a would be worse: it reads
:: a leading zero as octal.)
if not defined _pd_s[!_pd_c!] goto _pd_ask
if !_pd_c! GTR %_pd_n% goto _pd_ask
set "ANDROID_SERIAL=!_pd_s[%_pd_c%]!"
if not defined ANDROID_SERIAL goto _pd_ask
echo.
echo  [%g%+%w%] Targeting !ANDROID_SERIAL!
timeout /t 1 /nobreak > nul
exit /b 0

:_hdr_via
:: Sets _hdr_suffix to "   via USB" / "   via Wi-Fi" when a target is pinned, empty otherwise.
:: Deliberately a routine rather than an if-block in the caller: classifying the serial needs
:: a pipe, and a pipe inside ( ) runs both sides in subshells - which is the sort of thing
:: that works right up until it does not. :_pd_row keeps the same top-level shape.
set "_hdr_suffix="
if not defined ANDROID_SERIAL exit /b
set "_hdr_suffix=   via USB"
echo(!ANDROID_SERIAL!| findstr /c:":" >nul && set "_hdr_suffix=   via Wi-Fi"
exit /b

:_pd_row
:: %1 = index. Labels the transport so a USB/Wi-Fi pair of the same phone is obvious.
set "_pd_i=%~1"
set "_pd_via=USB  "
echo(!_pd_s[%_pd_i%]!| findstr /c:":" >nul && set "_pd_via=Wi-Fi"
echo     %g%[%w%%_pd_i%%g%]%w% !_pd_via!  !_pd_s[%_pd_i%]!   !_pd_d[%_pd_i%]!
exit /b

:detect_device
:: Retrieve the current Android API level safely
set "SDK="
for /f "delims=" %%i in ('adb shell getprop ro.build.version.sdk 2^>nul ^<nul') do set "SDK=%%i"
:: Strip trailing CR if any
if defined SDK set "SDK=%SDK:~0,3%"
if defined SDK for /f "tokens=* delims= " %%a in ("%SDK%") do set "SDK=%%a"
:: Normalise: if detection failed, default to 0 so numeric `if %SDK% GEQ N`
:: comparisons later never break on an empty value.
if not defined SDK set "SDK=0"
:: Capture device model for friendlier messages
set "MODEL="
for /f "delims=" %%i in ('adb shell getprop ro.product.model 2^>nul ^<nul') do set "MODEL=%%i"
call :_hdr_via
echo [%g%+%w%] Device: %MODEL%   API level: %SDK%!_hdr_suffix!
timeout /t 1 /nobreak > nul
goto menu

:menu
cls
title Main Menu
call :logo
echo          ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
for /f "tokens=3,4,5,6,7 delims= " %%a in ('adb shell uptime ^<nul 2^>nul') do echo           [%g%+%w%]Uptime: %%a %%b %%c
set "cpucheck=N/A"
for /f "tokens=2 delims=:" %%i in ('adb shell dumpsys cpuinfo ^<nul 2^>nul ^| findstr /C:"Load:"') do set "cpucheck=%%i"
echo           [%g%+%w%]%cpucheck% LOAD
echo          ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
echo.
echo.
echo                           %r%Gaming%w%         %gold%Battery%w%   %g%Optimize Android%w%
echo                             [1]            [2]            [3]
echo.
echo                            %d%Auto%w%       %d%CheckSetting%w%      %d%Tweaks%w%
echo                             [4]            [5]            [6]
echo.
echo.
echo                           %b%Reboot%w%          %b%Exit%w%           %b%Shell%w%
echo                             [7]            [8]            [9]
echo.
echo.
echo                          %m%Benchmark%w%        %m%Backup%w%         %b%Restore%w%
echo                             [10]           [11]           [12]
echo.
echo                         %gold%Wireless ADB%w%     %gold%App Mgr%w%     %gold%Settings Tools%w%
echo                             [13]           [14]           [15]
echo.

:menu_ask
:: FIX (press-twice): re-prompt WITHOUT redrawing on empty/invalid input so a
:: phantom empty line handed to set /p right after the uptime/cpuinfo probes is
:: absorbed instead of being treated as a miss that redraws (re-runs the probes).
:: Same fix validated on :dispscaler.
set "kb=" & set /p kb="                            Choose An Option >> "
if not defined kb goto menu_ask
if "!kb!"=="1" goto Gaming
if "!kb!"=="2" goto Battery
if "!kb!"=="3" goto Optimize
if "!kb!"=="4" goto Auto
if "!kb!"=="5" goto Check
if "!kb!"=="6" goto tweaks
if "!kb!"=="7" goto reboot
if "!kb!"=="8" goto exitscript
if "!kb!"=="9" goto shell
if "!kb!"=="10" goto benchmark
if "!kb!"=="11" goto backup
if "!kb!"=="12" goto restore
if "!kb!"=="13" goto wirelessadb
if "!kb!"=="14" goto appmgr
if "!kb!"=="15" goto settools
goto menu_ask
:: ===================================================================
:: NEW: Backup / Restore of toggleable settings
::
:: Backup dumps current values of first-class Settings / device_config /
:: props / wm overrides DCX toggles (not every Logs Off metric key), into
:: a stand-alone .bat file in %USERPROFILE%\dcx_backups\. The format stays
:: human-readable and you can edit it before restoring - deleting a line just
:: skips that key. :restore `call`s it and then checks BOTH its exit code and
:: whether the device is still attached, because a restore that lost the device
:: half way must not report success.
:: ===================================================================
:backup
cls
title Backup Settings
call :logo
echo.
:: FIX (safeguard): verify the device is actually attached BEFORE reading ~50 keys off
:: it. :_bk_settings cannot tell "the device did not answer" from "this key is unset" -
:: both come back empty, and empty is written as a `delete` line. So a backup taken with
:: the cable out looks complete and is in fact an instruction to WIPE every managed
:: setting on restore. The startup check is not enough: DCX runs long sessions and the
:: cable can leave at any point after it.
set "_dvst="
for /f "delims=" %%d in ('adb get-state 2^>nul') do set "_dvst=%%d"
if /i not "%_dvst%"=="device" (
    echo  %r%No device connected - backup refused.%w%
    echo.
    echo  Backup reads the CURRENT value of every key DCX manages. A key the device
    echo  does not answer for is indistinguishable from one that is genuinely unset,
    echo  and unset is recorded as "delete this on restore". Writing that file now
    echo  would hand you a backup that erases your settings instead of restoring them.
    echo.
    echo  Reconnect the device ^(check: adb devices^) and try again.
    echo.
    pause > nul
    goto menu
)
set "BACKUPDIR=%USERPROFILE%\dcx_backups"
if not exist "%BACKUPDIR%" mkdir "%BACKUPDIR%"
:: Locale-safe, filename-safe timestamp from %date%/%time% (sanitize separators).
:: Avoids PowerShell here so the console code page is not reset mid-run.
set "TS=%date%_%time%"
set "TS=%TS::=-%"
set "TS=%TS:/=-%"
set "TS=%TS:\=-%"
set "TS=%TS:.=-%"
set "TS=%TS:,=-%"
set "TS=%TS: =_%"
set "BAKFILE=%BACKUPDIR%\dcx_backup_%TS%.bat"
echo  Saving current settings to:
echo    %BAKFILE%
echo.
:: Build a restore script. Each captured value becomes a put/setprop
:: command; missing values become delete to clear any stale override.
:: FIX: the literal ')' in the comment line below must be escaped as '^)'.
:: It was previously '^^)', which inside this ( ... ) block collapses to a
:: literal caret + an UNescaped ')' that closed the block early, aborting
:: the whole backup with ". was unexpected at this time." (no file written).
call :_bk_write_adb_boot "%BAKFILE%"
(
    echo :: DCX Settings Backup created %date% %time%
    echo :: Stand-alone restore - same device connected. Edit to skip keys.
    echo :: Labels BEFORE :dcx_main so restore lines stay in :dcx_main.
    echo :: Every restore line goes through :dcx_do ^(counts OK/FAIL^).
    echo goto :dcx_main
    echo.
    echo :dcx_do
    echo :: Runs one restore command and records whether it landed. Uses %%ADB%%
    echo :: from the header ^(not bare adb - this file is not next to adb\^).
    echo "%%ADB%%" shell %%* ^>nul 2^>^&1
    echo if errorlevel 1 ^(
    echo     set /a DCX_FAIL+=1
    echo     echo   [FAIL] %%*
    echo ^) else ^(
    echo     set /a DCX_OK+=1
    echo ^)
    echo goto :eof
    echo.
    echo :dcx_hold
    echo if defined DCX_NOPAUSE exit /b 0
    echo echo.
    echo echo ----------------------------------------
    echo echo Press any key to close this window . . .
    echo pause
    echo exit /b 0
    echo.
    echo :dcx_report
    echo echo.
    echo if "%%DCX_FAIL%%"=="0" ^(
    echo     echo [OK] Restored %%DCX_OK%% settings, none failed.
    echo ^) else ^(
    echo     echo [WARN] %%DCX_OK%% restored, %%DCX_FAIL%% FAILED - listed above.
    echo     echo        The device may be in a mixed state. Reconnect it and run this
    echo     echo        file again - restoring twice is harmless.
    echo ^)
    echo echo.
    echo call :dcx_hold
    echo exit /b %%DCX_FAIL%%
    echo.
    echo :dcx_main
    echo echo Restoring DCX-managed settings...
    echo set "DCX_OK=0" ^& set "DCX_FAIL=0"
) >> "%BAKFILE%" < nul
:: Helper macro for capturing settings (Settings.X namespace)
:: We capture each key by reading current value and building the
:: corresponding put or delete line.
call :_bk_settings global window_animation_scale     "%BAKFILE%"
call :_bk_settings global transition_animation_scale "%BAKFILE%"
call :_bk_settings global animator_duration_scale    "%BAKFILE%"
call :_bk_settings system min_refresh_rate           "%BAKFILE%"
call :_bk_settings system peak_refresh_rate          "%BAKFILE%"
call :_bk_settings global angle_gl_driver_all_angle  "%BAKFILE%"
call :_bk_settings global master_sync_status         "%BAKFILE%"
call :_bk_settings global hotword_detection_enabled  "%BAKFILE%"
call :_bk_settings global preferred_network_mode     "%BAKFILE%"
call :_bk_settings global preferred_network_mode1    "%BAKFILE%"
call :_bk_settings global private_dns_mode           "%BAKFILE%"
call :_bk_settings global private_dns_specifier      "%BAKFILE%"
call :_bk_settings global mobile_data_always_on      "%BAKFILE%"
call :_bk_settings global tcp_default_init_rwnd      "%BAKFILE%"
call :_bk_settings global wifi_idle_ms               "%BAKFILE%"
call :_bk_settings global wifi_sleep_policy          "%BAKFILE%"
call :_bk_settings global low_power                  "%BAKFILE%"
call :_bk_settings secure clock_seconds              "%BAKFILE%"
call :_bk_settings system status_bar_show_battery_percent "%BAKFILE%"
call :_bk_settings global audio_safe_volume_state    "%BAKFILE%"
call :_bk_settings secure audio_safe_csd_as_a_feature_enabled "%BAKFILE%"
call :_bk_settings secure icon_blacklist             "%BAKFILE%"
call :_bk_settings global heads_up_notifications_enabled "%BAKFILE%"
call :_bk_settings system font_scale                 "%BAKFILE%"
call :_bk_settings secure long_press_timeout         "%BAKFILE%"
call :_bk_settings global stay_on_while_plugged_in   "%BAKFILE%"
call :_bk_settings secure ui_night_mode              "%BAKFILE%"
call :_bk_settings secure night_display_activated    "%BAKFILE%"
call :_bk_settings secure night_display_auto_mode    "%BAKFILE%"
call :_bk_settings secure night_display_color_temperature "%BAKFILE%"
call :_bk_settings global sysui_demo_allowed         "%BAKFILE%"
call :_bk_settings secure sysui_qs_tiles             "%BAKFILE%"
call :_bk_settings secure camera_gesture_disabled    "%BAKFILE%"
call :_bk_settings secure camera_double_tap_power_gesture_disabled "%BAKFILE%"
call :_bk_settings secure camera_double_twist_to_flip_enabled "%BAKFILE%"
call :_bk_settings global charging_sounds_enabled    "%BAKFILE%"
call :_bk_settings global charging_vibration_enabled "%BAKFILE%"
call :_bk_settings global sys_storage_threshold_percentage "%BAKFILE%"
call :_bk_settings global sys_storage_threshold_max_bytes "%BAKFILE%"
call :_bk_settings global low_power_trigger_level    "%BAKFILE%"
call :_bk_settings global default_install_location   "%BAKFILE%"
call :_bk_settings global enable_freeform_support    "%BAKFILE%"
call :_bk_settings global force_resizable_activities "%BAKFILE%"
call :_bk_settings global zram_enabled               "%BAKFILE%"
call :_bk_settings global wifi_scan_always_enabled   "%BAKFILE%"
call :_bk_settings global bluetooth_scan_always_enabled "%BAKFILE%"
call :_bk_settings global always_finish_activities   "%BAKFILE%"
call :_bk_settings global package_verifier_enable    "%BAKFILE%"
call :_bk_settings global low_power_sticky           "%BAKFILE%"
call :_bk_settings global disable_window_blurs       "%BAKFILE%"
call :_bk_settings global reduce_motion              "%BAKFILE%"
call :_bk_settings secure reduce_motion              "%BAKFILE%"
call :_bk_settings secure accessibility_disable_animations "%BAKFILE%"
call :_bk_settings global enable_back_animation      "%BAKFILE%"
call :_bk_settings global fancy_ime_animations       "%BAKFILE%"
call :_bk_settings secure multi_press_timeout        "%BAKFILE%"
call :_bk_devcfg   app_hibernation app_hibernation_enabled "%BAKFILE%"
call :_bk_dcfgsync "%BAKFILE%"
call :_bk_wm       "%BAKFILE%"
call :_bk_prop     debug.hwui.renderer        "%BAKFILE%"
call :_bk_prop     debug.renderengine.backend "%BAKFILE%"
call :_bk_prop     persist.log.tag            "%BAKFILE%"
:: Close :dcx_main with goto :dcx_report. Helpers (:dcx_do / :dcx_hold / :dcx_report)
:: were written ABOVE :dcx_main so this append stays inside the restore body.
>>"%BAKFILE%" echo goto :dcx_report
:: FIX (safeguard): "Backup complete." used to print no matter what. The file is built
:: by ~50 append redirections into %USERPROFILE%\dcx_backups - exactly the kind of path
:: Controlled Folder Access and antivirus guard. When that happens every append no-ops
:: silently and the user is told they have a backup they do not have -
:: worse than a failed backup they know about, because they will rely on it later.
:: Checking for a real restore line proves the settings were captured, not just that
:: the header was written.
set "_bkok=0"
if exist "%BAKFILE%" findstr /b /c:"call :dcx_do" "%BAKFILE%" >nul 2>&1 && set "_bkok=1"
if "%_bkok%"=="0" (
    echo  %r%Backup FAILED%w% - no usable restore file was written.
    echo    Tried: !BAKFILE!
    echo.
    echo  That folder is often blocked by antivirus or Controlled Folder Access.
    echo  Allow it, or run DCX from another location, then try again.
    echo.
    pause > nul
    goto menu
)
echo  %g%Backup complete.%w%
echo    !BAKFILE!
>"%BACKUPDIR%\dcx_last_backup.txt" echo !BAKFILE!
echo.
if defined DCX_ADB (
    echo  %y%Note:%w% restore .bat embeds adb path:
    echo    !DCX_ADB!
    echo  It will also try PATH / dcx_adb_path.txt. Double-clicking from
    echo  Explorer does NOT use DCX's local adb\ folder automatically.
) else (
    echo  %y%Warning:%w% could not embed a full adb path. Put platform-tools on
    echo  PATH before running the restore .bat outside DCX.
)
echo.
echo  %b%[%w%1%b%]%w% Open backups folder in Explorer
echo  %b%[%w%2%b%]%w% View this backup in Notepad
echo  %b%[%w%3%b%]%w% Back to main menu
set "bk=" & set /p bk="Choose An Option >> "
if "!bk!"=="1" (
    start "" "%BACKUPDIR%"
    goto menu
)
if "!bk!"=="2" (
    start "" notepad "%BAKFILE%"
    goto menu
)
goto menu
:: -------------------------------------------------------------------
:: Helper subroutines used by :backup
::
:: _bk_settings  <namespace> <key> <outfile>
::   Reads the current value of a settings put/delete key. If null,
::   writes a `delete`; otherwise writes a `put` with the value.
:: -------------------------------------------------------------------
:: ===========================================================================
:: _resolve_adb / _bk_write_adb_boot
:: Backup and undo .bat files are written to %%USERPROFILE%%\dcx_backups. DCX
:: itself often runs after "cd adb", so bare "adb" works inside DCX but NOT when
:: those scripts are double-clicked ^(cwd has no adb\ folder, PATH may be empty^).
:: Capture the full adb.exe path and emit an explicit locator that fails loudly.
:: ===========================================================================
:_resolve_adb
set "DCX_ADB="
for /f "delims=" %%A in ('where adb 2^>nul') do (
    set "DCX_ADB=%%~fA"
    goto _resolve_adb_done
)

:_resolve_adb_done
if not defined DCX_ADB for %%A in (adb.exe) do set "DCX_ADB=%%~fA"
if defined DCX_ADB if not exist "!DCX_ADB!" set "DCX_ADB="
set "_bd=%USERPROFILE%\dcx_backups"
if not exist "%_bd%" mkdir "%_bd%"
if defined DCX_ADB >"%_bd%\dcx_adb_path.txt" echo !DCX_ADB!
exit /b 0

:_bk_write_adb_boot
:: %1 = outfile. Overwrites with @echo off + ADB resolve + start-server.
:: Disable delayed expansion while echoing so "!ADB!" is not eaten by DCX.
:: Scripts accept /nopause so DCX can call them without the child holding/closing
:: the shared console session.
setlocal DisableDelayedExpansion
set "OUT=%~1"
set "BAKED=%DCX_ADB%"
(
    echo @echo off
    echo setlocal
    echo :: DCX-generated restore/undo. Stored under dcx_backups - NOT next to adb\.
    echo :: Pass /nopause when launched from DCX so control returns to the menu.
    echo set "DCX_NOPAUSE="
    echo if /i "%%~1"=="/nopause" set "DCX_NOPAUSE=1"
    echo set "ADB="
    if defined BAKED echo if exist "%BAKED%" set "ADB=%BAKED%"
    echo if not defined ADB if exist "%%~dp0dcx_adb_path.txt" ^(
    echo   set /p ADB=^<"%%~dp0dcx_adb_path.txt"
    echo ^)
    echo if defined ADB if not exist "%%ADB%%" set "ADB="
    echo if not defined ADB ^(
    echo   where adb ^> "%%TEMP%%\dcx_where_adb.txt" 2^>nul
    echo   set /p ADB=^<"%%TEMP%%\dcx_where_adb.txt"
    echo ^)
    echo if defined ADB if not exist "%%ADB%%" set "ADB="
    echo if not defined ADB ^(
    echo   echo [ERROR] adb.exe not found.
    echo   echo   This script lives in %%USERPROFILE%%\dcx_backups and does not see
    echo   echo   the adb\ folder next to DCX.bat. Fix one of:
    echo   echo     [1] Add platform-tools to PATH
    echo   echo     [2] Re-run Backup / a Tweaks write from DCX - embeds adb path
    echo   echo     [3] Edit set ADB= near the top of this file
    echo   call :dcx_hold
    echo   exit /b 1
    echo ^)
    echo "%%ADB%%" version ^>nul 2^>^&1
    echo if errorlevel 1 ^(
    echo   echo [ERROR] Cannot run adb: "%%ADB%%"
    echo   call :dcx_hold
    echo   exit /b 1
    echo ^)
    echo echo Using adb: %%ADB%%
    echo "%%ADB%%" start-server ^>nul 2^>^&1
) > "%OUT%"
endlocal
exit /b 0

:_bk_write_hold_footer
:: Append :dcx_hold helper to %1 ^(shared by backup + undo generators^).
setlocal DisableDelayedExpansion
set "OUT=%~1"
(
    echo.
    echo :dcx_hold
    echo if defined DCX_NOPAUSE exit /b 0
    echo echo.
    echo echo ----------------------------------------
    echo echo Press any key to close this window . . .
    echo pause
    echo exit /b 0
) >> "%OUT%"
endlocal
exit /b 0
:: ===========================================================================
:: _dcfg_warn - one-time honest warning about device_config writes on Android 14+.
:: Per the AOSP change in Android 14 (API 34), "shell can no longer write most
:: device_config flags by default - the CLI needs superuser privileges." So every
:: "device_config put" DCX sends returns cleanly but writes NOTHING on 14+ without
:: root, which would otherwise look like success. This helper says so once, and only
:: when it actually applies (SDK>=34 AND no root). Reads (device_config get) are
:: unaffected, so the readouts elsewhere stay truthful. Call it at the top of any menu
:: that leans on device_config put.
:_dcfg_warn
if defined _DCFGWARNED goto :eof
:: only relevant on Android 14+ (API 34). A non-numeric SDK skips the compare safely.
set "_dcfg_hi="
for /f "delims=0123456789" %%n in ("%SDK%") do set "_dcfg_hi=%%n"
if defined _dcfg_hi goto :eof
if %SDK% LSS 34 goto :eof
:: SDK>=34: does the device have root? (device_config put works with su.)
adb shell "su -c 'echo _DCXROOT'" <nul 2>nul | findstr /C:"_DCXROOT" >nul
if not errorlevel 1 goto :eof
:: SDK>=34 and no root -> warn once.
set "_DCFGWARNED=1"
echo.
echo  %gold%Note (Android %SDK%):%w% since Android 14, changing hidden "device_config"
echo  flags over ADB needs root. Without it these writes are accepted but may%w%
echo  %gold%not actually stick%w% - the on-screen result can look done while nothing
echo  changed. Values DCX only *reads* are still accurate.
echo  For the app-hibernation case there is a no-root path: Developer Options ^>
echo  %gold%Disable child process restrictions%w%.
echo.
goto :eof

:_bk_settings
:: FIX (robustness): enabledelayedexpansion + quote the value in the generated
:: line. The old unquoted `%_val%` let a value containing a CMD metacharacter
:: (& | < >) break backup GENERATION (echo `a&b` ran `b` as a command and wrote
:: a truncated line). DCX-managed values don't contain those, but the backup
:: also captures whatever the device currently holds under these keys.
:: FIX (value truncated at '!'): the capture ran with delayed expansion already ON, and
:: `set "_val=%%v"` then EATS any '!' in the device's value - "Hi!There!" was stored as
:: "Hi". That is not a display glitch: the truncated text is what gets written into the
:: backup, so restoring it SILENTLY REWRITES the setting to the shortened value. Read the
:: value with delayed expansion OFF, then turn it on for the substitutions below. Same
:: split applied to :_bk_devcfg, :_bk_prop and :_tw_prof_add.
setlocal DisableDelayedExpansion
set "_ns=%~1"
set "_key=%~2"
set "_out=%~3"
set "_val="
for /f "delims=" %%v in ('adb shell settings get %_ns% %_key% 2^>nul ^<nul') do set "_val=%%v"
setlocal EnableDelayedExpansion
if "!_val!"=="" set "_val=null"
:: FIX (found by the new [FAIL] report, on a real restore): adb strips ONE level of
:: quoting. cmd removes the quotes around the value when building adb's argv, adb
:: re-joins argv with spaces, and the ANDROID shell then sees the value BARE - so a
:: value holding ( ) ; & | breaks there, not here. The real case is sysui_qs_tiles,
:: whose value contains custom(com.huawei.calculator/.quicksetting.QuickSettingService):
:: restoring it always failed silently, and the old flat "Done." never said so.
:: Fix: pass the whole remote command as ONE double-quoted argument (cmd hands adb a
:: single string) and single-quote the value inside it (the device shell keeps it
:: whole). Any literal quote in the value is escaped POSIX-style as '\''.
set "_sv=!_val:'='\''!"
if /i "!_val!"=="null" (
    >>"%_out%" echo call :dcx_do "settings delete %_ns% %_key%"
) else (
    >>"%_out%" echo call :dcx_do "settings put %_ns% %_key% '!_sv!'"
)
endlocal
endlocal
exit /b

:_bk_devcfg
:: FIX (robustness): same as :_bk_settings - delayed expansion + quoted value, and the
:: same DisableDelayedExpansion read so a '!' in the value is not eaten.
setlocal DisableDelayedExpansion
set "_ns=%~1"
set "_key=%~2"
set "_out=%~3"
set "_val="
for /f "delims=" %%v in ('adb shell device_config get %_ns% %_key% 2^>nul ^<nul') do set "_val=%%v"
setlocal EnableDelayedExpansion
if "!_val!"=="" set "_val=null"
:: single-quote for the device shell - see the note in :_bk_settings.
set "_sv=!_val:'='\''!"
if /i "!_val!"=="null" (
    >>"%_out%" echo call :dcx_do "device_config delete %_ns% %_key%"
) else (
    >>"%_out%" echo call :dcx_do "device_config put %_ns% %_key% '!_sv!'"
)
endlocal
endlocal
exit /b

:_bk_wm
:: Capture Display Scaler overrides (wm size / wm density). No override -> reset
:: on restore so a later scale does not survive a Restore to "stock panel".
setlocal enabledelayedexpansion
set "_out=%~1"
set "_osz="
set "_odz="
for /f "tokens=2 delims=:" %%a in ('adb shell wm size ^<nul 2^>nul ^| findstr /C:"Override size"') do set "_osz=%%a"
for /f "tokens=2 delims=:" %%a in ('adb shell wm density ^<nul 2^>nul ^| findstr /C:"Override density"') do set "_odz=%%a"
set "_osz=!_osz: =!"
set "_odz=!_odz: =!"
if defined _osz (
    >>"%_out%" echo call :dcx_do "wm size !_osz!"
) else (
    >>"%_out%" echo call :dcx_do "wm size reset"
)
if defined _odz (
    >>"%_out%" echo call :dcx_do "wm density !_odz!"
) else (
    >>"%_out%" echo call :dcx_do "wm density reset"
)
endlocal
exit /b

:_bk_dcfgsync
:: Captures device_config get_sync_disabled_for_tests (none/persistent/
:: until_reboot). Not a settings put key - Tweaks owns this toggle.
:: FIX (fabricated capture): an unreadable answer used to be recorded as 'none', so the
:: backup carried a restore line for a value it had never read - on a build without the
:: getter that silently writes "none" onto the device at restore time. Emit a comment
:: instead, the same way :_bk_prop handles a property that was unset at backup time.
setlocal enabledelayedexpansion
set "_out=%~1"
call :_dcfgsync_read
if errorlevel 1 (
    >>"%_out%" echo :: device_config sync mode was not readable on this device - not restoring
) else (
    >>"%_out%" echo call :dcx_do "device_config set_sync_disabled_for_tests '!DCS_VAL!'"
)
endlocal
exit /b

:_bk_prop
:: (1) An UNSET prop makes getprop return empty, and the old code then emitted
::     `setprop key ""` as a restore line. That does not set the prop to empty - the
::     quotes never reach the phone, so setprop gets one argument and just prints its
::     usage text (see the note under :_sf_clear_props). Either way it is not a
::     restore, so emit a comment instead and leave the prop alone.
:: (2) Delayed expansion so a metachar value cannot corrupt the generated line, and
::     DisableDelayedExpansion on the read so a '!' in the value is not eaten - see
::     the note in :_bk_settings.
setlocal DisableDelayedExpansion
set "_key=%~1"
set "_out=%~2"
set "_val="
for /f "delims=" %%v in ('adb shell getprop %_key% 2^>nul ^<nul') do set "_val=%%v"
setlocal EnableDelayedExpansion
:: single-quote for the device shell - see the note in :_bk_settings.
set "_sv=!_val:'='\''!"
if "!_val!"=="" (
    >>"%_out%" echo :: prop %_key% was unset at backup time - not restoring
) else (
    >>"%_out%" echo call :dcx_do "setprop %_key% '!_sv!'"
)
endlocal
endlocal
exit /b
:: ===================================================================
:: Restore from backup file
:: ===================================================================
:restore
cls
title Restore Settings
call :logo
echo.
set "BACKUPDIR=%USERPROFILE%\dcx_backups"
if not exist "%BACKUPDIR%" (
    echo  %r%No backups folder found.%w%
    echo  Run option [11] Backup first to create one.
    echo.
    pause > nul
    goto menu
)
echo  Available backups in %BACKUPDIR%:
echo  %y%Note:%w% older restore .bats that call bare "adb" need PATH or a
echo  re-Backup from this DCX ^(new files embed the adb.exe path^).
echo.
set "i=0"
:: Numbered listing - newest first
for /f "delims=" %%f in ('dir /b /o-d "%BACKUPDIR%\dcx_backup_*.bat" 2^>nul') do (
    set /a i+=1
    setlocal enabledelayedexpansion
    set "_idx=  [!i!]"
    echo    !_idx:~-5! %%f
    endlocal
    set "_bk_%%f=defined"
    call set "_bk_n_%%i%%=%%f"
)
if "%i%"=="0" (
    echo  %r%No backup files found.%w%
    echo.
    pause > nul
    goto menu
)
echo.
echo    [0] Cancel
echo.
set "ri=" & set /p ri="Pick a backup to restore >> "
if "!ri!"=="0" goto menu
:: Look up the chosen filename
call set "_chosen=%%_bk_n_%ri%%%"
if "%_chosen%"=="" (
    echo  %r%Invalid selection.%w%
    pause > nul
    goto restore
)
set "RESTOREFILE=%BACKUPDIR%\%_chosen%"
echo.
echo  About to apply settings from:
echo    %RESTOREFILE%
echo.
echo  %y%This will overwrite your current values for every key listed.%w%
echo.
echo    [Y] Proceed and restore
echo    [N] Cancel
choice /c:YN /n > nul
if errorlevel 2 goto menu
cls
echo  Running restore ^(output below^)...
echo.
:: Nested cmd.so a buggy/old restore .bat that uses "exit" ^(no /b^) or otherwise
:: kills its interpreter cannot take DCX's console down with it. /nopause keeps
:: the hold in DCX so you always see the summary.
cmd /c ""%RESTOREFILE%" /nopause"
set "_rrc=%errorlevel%"
set "_rdev="
for /f "delims=" %%d in ('adb get-state 2^>nul') do set "_rdev=%%d"
echo.
echo  ----------------------------------------
if not "%_rrc%"=="0" (
    echo  %r%Restore finished with %_rrc% failed write^(s^)%w% - they are listed above.
    echo  The device may be in a mixed state. Reconnect it and restore again;
    echo  restoring twice is harmless.
) else if /i not "%_rdev%"=="device" (
    echo  %r%The device is no longer connected.%w% The restore may have stopped part-way.
    echo  Reconnect the device and run the restore again - restoring twice is harmless.
) else (
    echo  %g%Restore complete.%w% Some changes may need a reboot to fully apply.
)
echo  ----------------------------------------
echo.
echo  Press any key to return to the main menu . . .
pause >nul
goto menu

:benchmark
cls
title Benchmark
echo [%g%+%w%] Quick device benchmark - lower is better.
echo.
echo  This runs three quick checks:
echo    1. CPU loop time
echo    2. Storage random write
echo    3. Storage sequential read
echo.
echo  Total time: about 10-15 seconds.
echo.
echo.
echo [%b%1/3%w%] CPU loop test (1M iterations)...
:: FIX: 'seq' is not on every Android. Use a portable POSIX shell loop.
:: We also reduce iterations from 8M to 1M for sane wait times.
adb shell "time sh -c 'i=0; while [ $i -lt 1000000 ]; do i=$((i+1)); done'" <nul
echo.
echo [%b%2/3%w%] Storage random write (10MB)...
adb shell "time dd if=/dev/urandom of=/data/local/tmp/_dcx_bench bs=64k count=160 2>&1 | tail -1" <nul
echo.
echo [%b%3/3%w%] Storage sequential read (10MB)...
adb shell "time dd if=/data/local/tmp/_dcx_bench of=/dev/null bs=64k 2>&1 | tail -1" <nul
adb shell rm -f /data/local/tmp/_dcx_bench <nul
echo.
echo.
echo [%g%Done%w%] Numbers vary - run twice after optimization for comparison.
echo.
echo Press Any Button To Go Back
pause > nul
goto menu

:shell
@echo off
cls
title Shell
adb shell
goto menu

:exitscript
@echo off
cls
title Exit
call :logo
echo.
echo.
echo.
echo.
echo.
echo                   %d%Thanks For Using My Script, Goodbye And Have A Good Day^^!^^!%w%
echo.
echo.
timeout /t 3 /nobreak > nul
adb shell cmd notification post -S bigtext -t '⚙DCX⚙' 'Tag' 'Restart = Remove All Settings Applied, Please Use This Script At Least Once A Month To Keep Your Device Smooth, Bye^^!^^!' <nul > nul 2>&1
adb kill-server
exit /b

:reboot
adb reboot
timeout /t 1 /nobreak > nul
adb disconnect
goto menu
:: ===================================================================
:: NEW: Wireless ADB (pair / connect / manage Wi-Fi debugging)
::
:: Two ways onto Wi-Fi, depending on Android version:
::
::   Android 11+ : Developer options -> Wireless debugging. The
::     "Pair device with pairing code" dialog shows a ONE-TIME
::     ip:port + 6-digit code -> option [1]. Pairing is per-PC and
::     only needed once. The port for CONNECTING afterwards is the
::     DIFFERENT one shown on the main Wireless-debugging screen.
::
::   Android 10 and below (or builds that hide pairing): connect the
::     USB cable once and use option [3] - it flips adbd to TCP/IP on
::     port 5555 and auto-detects the phone's Wi-Fi IP.
::
:: Honest notes: the Android 11+ connect port is random and changes
:: after a reboot or re-toggling Wireless debugging, so reconnects
:: need the fresh port. While the mode is on, any PC paired with the
:: phone on the same network can run adb - turn it off when done.
:: ===================================================================
:wirelessadb
cls
title Wireless ADB
call :logo
echo                            %b%[%w% Wireless ADB %b%]%w%
echo.
echo  Run DCX over Wi-Fi - no cable needed. PC and phone must be on the
echo  same network.
echo.
echo  Currently attached (USB and Wi-Fi entries both show here):
for /f "skip=1 delims=" %%i in ('adb devices ^<nul 2^>nul') do echo     %%i
echo.
echo                 %g%[%w%1%g%]%w% Pair with code       (Android 11+, once per PC)
echo                 %g%[%w%2%g%]%w% Connect to IP[:port]
echo                 %g%[%w%3%g%]%w% Enable over USB      (adb tcpip 5555 + auto-IP)
echo                 %g%[%w%4%g%]%w% Disconnect all Wi-Fi connections
echo                 %g%[%w%5%g%]%w% Switch device back to USB mode
echo                 %g%[%w%6%g%]%w% Help - where the ports and code live
echo                 %g%[%w%7%g%]%w% Select target device  (when more than one is attached)
echo                 %g%[%w%8%g%]%w% Back
set "wa=" & set /p wa="Choose An Option >> "
if "!wa!"=="1" goto wadb_pair
if "!wa!"=="2" goto wadb_connect
if "!wa!"=="3" goto wadb_tcpip
if "!wa!"=="4" goto wadb_disconnect
if "!wa!"=="5" goto wadb_usb
if "!wa!"=="6" goto wadb_help
if "!wa!"=="7" (
    call :pick_device
    goto wirelessadb
)
if "!wa!"=="8" goto wadb_back
goto wirelessadb

:wadb_back
rem  The attached-device list may have changed while in this menu (a connect, a
rem  disconnect, or tcpip adding a second entry for the same phone), so re-resolve
rem  the target before handing control back.
call :pick_device
:: If we arrived from the no-device startup path, the model/API probe
:: was skipped (SDK defaulted to 0) - run it now that a device may be
:: attached. Re-probing on a genuine API-0 is harmless.
if "!SDK!"=="0" goto detect_device
goto menu

:wadb_pair
cls
title Wireless ADB : pair
call :logo
echo  On the phone: Developer options -^> Wireless debugging -^>
echo  %g%Pair device with pairing code%w%. Keep that dialog OPEN - the
echo  code and port stop working the moment it closes.
echo.
set "WIP=" & set /p WIP="Pairing ip:port (blank = cancel) >> "
if "!WIP!"=="" goto wirelessadb
echo !WIP!| findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*:[0-9][0-9]*$" >nul || goto wadb_pair_bad
set "WCODE=" & set /p WCODE="6-digit pairing code (blank = cancel) >> "
if "!WCODE!"=="" goto wirelessadb
echo !WCODE!| findstr /r "^[0-9][0-9][0-9][0-9][0-9][0-9]$" >nul || goto wadb_pair_bad
echo.
adb pair !WIP! !WCODE!
echo.
echo  If it said "Successfully paired": this PC is trusted now, but you
echo  are NOT connected yet. The connect port is the DIFFERENT one on
echo  the main Wireless-debugging screen -^> option [2].
echo.
echo Press Any Button To Go Back
pause > nul
goto wirelessadb

:wadb_pair_bad
echo [%r%^^!%w%] Expected ip:port like 192.168.1.23:37123 and a 6-digit code.
timeout /t 2 /nobreak >nul
goto wadb_pair

:wadb_connect
cls
title Wireless ADB : connect
call :logo
echo  Enter the ip:port from the MAIN Wireless-debugging screen
echo  (Android 11+), or just the phone's IP if you used option [3]
echo  (port 5555 is assumed then).
echo.
set "WIP=" & set /p WIP="ip[:port] (blank = cancel) >> "
if "!WIP!"=="" goto wirelessadb
if "!WIP!"=="!WIP::=!" set "WIP=!WIP!:5555"
echo !WIP!| findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*:[0-9][0-9]*$" >nul || goto wadb_connect_bad
echo.
adb connect !WIP!
echo.
echo  Now attached:
for /f "skip=1 delims=" %%i in ('adb devices ^<nul 2^>nul') do echo     %%i
echo.
echo  "failed to authenticate" / "connection refused" usually means this
echo  PC isn't paired with the phone yet -^> option [1] first, or the
echo  port went stale (it changes on reboot/re-toggle).
echo.
echo Press Any Button To Go Back
pause > nul
goto wirelessadb

:wadb_connect_bad
echo [%r%^^!%w%] Expected an IPv4 address like 192.168.1.23 or 192.168.1.23:41235.
timeout /t 2 /nobreak >nul
goto wadb_connect

:wadb_tcpip
cls
title Wireless ADB : enable over USB
call :logo
echo  Flips the USB-connected device's adbd into TCP/IP mode on port
echo  5555 - the classic method: works on any Android version, no
echo  pairing needed. %y%Needs the cable attached for this one step.%w%
echo  Reverts on reboot, or via option [5].
echo.
echo    [Y] Enable    [N] Cancel
choice /c:YN /n >nul
if errorlevel 2 goto wirelessadb
adb tcpip 5555
timeout /t 2 /nobreak >nul
:: Read the phone's Wi-Fi IP so the user doesn't have to dig through
:: Settings. `ip route` lines look like:
::   192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.42
:: Prefer a wlan line; the shift-walk helper grabs the token after
:: 'src' no matter where in the line it sits.
set "WDEVIP="
for /f "delims=" %%l in ('adb shell ip route ^<nul 2^>nul ^| findstr /C:"wlan"') do if not defined WDEVIP call :_wadb_src %%l
if not defined WDEVIP for /f "delims=" %%l in ('adb shell ip route ^<nul 2^>nul ^| findstr /C:" src "') do if not defined WDEVIP call :_wadb_src %%l
echo.
if defined WDEVIP (
    echo  Phone Wi-Fi IP detected: %g%!WDEVIP!%w%
    echo.
    echo    [Y] Connect to !WDEVIP!:5555 now    [N] Not yet
    choice /c:YN /n >nul
    if errorlevel 2 goto wirelessadb
    adb connect !WDEVIP!:5555
    echo.
    echo  You can unplug the cable now. If the list shows the device
    echo  twice, USB and Wi-Fi are both attached - that's normal.
    for /f "skip=1 delims=" %%i in ('adb devices ^<nul 2^>nul') do echo     %%i
) else (
    echo  Could not auto-detect the IP - the phone may be off Wi-Fi.
    echo  Find it under Settings -^> About phone -^> Status, then use
    echo  option [2].
)
echo.
echo Press Any Button To Go Back
pause > nul
goto wirelessadb
:: _wadb_src <route line tokens...>
::   Walks the arguments until it finds 'src' and keeps the next one.
:_wadb_src
if "%~1"=="" exit /b
if "%~1"=="src" (
    set "WDEVIP=%~2"
    exit /b
)
shift
goto _wadb_src

:wadb_disconnect
cls
title Wireless ADB : disconnect
adb disconnect
echo Done - all Wi-Fi connections dropped. USB is unaffected.
echo Press Any Button To Go Back
pause > nul
goto wirelessadb

:wadb_usb
cls
title Wireless ADB : back to USB
:: Only meaningful for devices switched with option [3]; for the
:: Android 11+ mode just turn the Wireless-debugging toggle off.
adb usb 2>nul
echo Done - adbd is back on USB; any Wi-Fi connection to it dropped.
echo (Android 11+ Wireless debugging: turn the toggle off on the phone.)
echo Press Any Button To Go Back
pause > nul
goto wirelessadb

:wadb_help
cls
title Wireless ADB : help
call :logo
echo  %g%Android 11 and newer%w% - Developer options -^> %g%Wireless debugging%w%:
echo    - Toggle it ON while the phone is on your Wi-Fi.
echo    - "Pair device with pairing code" shows ip:port + a 6-digit
echo      code -^> option [1]. One-time per PC; keep the dialog open.
echo    - The MAIN screen's "IP address and Port" is what option [2]
echo      wants. That port is random and %y%changes after a reboot or
echo      re-toggle%w% - grab it fresh each time.
echo.
echo  %g%Android 10 and older%w% (pairing does not exist there):
echo    - Plug in USB once, use option [3], unplug. Port is fixed 5555.
echo.
echo  %g%Huawei EMUI / HarmonyOS%w%: same place in Developer options; some
echo    builds hide the pairing dialog - option [3] over USB works too.
echo.
echo  %y%Security note:%w% while wireless debugging is on, any PC paired
echo  with the phone on the same network can run adb commands. Turn it
echo  off when you're done.
echo.
echo Press Any Button To Go Back
pause > nul
goto wirelessadb

:check
cls
title Device Info ^& Diagnostics
call :logo
echo.
echo  Generating full device report - about 50 device queries, ~10 seconds.
echo  %y%The window cannot accept input until this finishes.%w%
echo.
:: Progress goes to 1>CON so it reaches the screen even though the whole block below is
:: redirected into the report file. Verified: CON writes cannot leak into the report.
:: Without this the screen sits blank for the whole run and looks hung.
:: Remember the previous report path (if any) so the menu can offer a diff.
set "PREV_REPORT="
if exist "%TEMP%\dcx_last_report_path.txt" (
    set /p PREV_REPORT=<"%TEMP%\dcx_last_report_path.txt"
)
if not defined PREV_REPORT set "PREV_REPORT=" 
:: Locale-safe, filename-safe timestamp from %date%/%time%.
set "TS=%date%_%time%"
set "TS=%TS::=-%"
set "TS=%TS:/=-%"
set "TS=%TS:\=-%"
set "TS=%TS:.=-%"
set "TS=%TS:,=-%"
set "TS=%TS: =_%"
set "REPORT=%TEMP%\dcx_report_%TS%.txt"
(
    echo ===========================================================
    echo  DCX Device Diagnostic Report - %date% %time%
    echo ===========================================================
    echo.
    echo    [1/6] hardware and software... 1>CON
    echo [Hardware]
    for /f "delims=" %%i in ('adb shell getprop ro.product.manufacturer 2^>nul ^<nul') do echo   Manufacturer        : %%i
    for /f "delims=" %%i in ('adb shell getprop ro.product.model 2^>nul ^<nul')        do echo   Model               : %%i
    for /f "delims=" %%i in ('adb shell getprop ro.product.device 2^>nul ^<nul')       do echo   Device codename     : %%i
    for /f "delims=" %%i in ('adb shell getprop ro.product.cpu.abi 2^>nul ^<nul')      do echo   CPU ABI             : %%i
    for /f "delims=" %%i in ('adb shell getprop ro.hardware 2^>nul ^<nul')             do echo   SoC platform        : %%i
    for /f "delims=" %%i in ('adb shell getprop ro.board.platform 2^>nul ^<nul')       do echo   Board platform      : %%i
    echo.
    echo [Software]
    for /f "delims=" %%i in ('adb shell getprop ro.build.version.release 2^>nul ^<nul')        do echo   Android version     : %%i
    echo   API level           : %SDK%
    for /f "delims=" %%i in ('adb shell getprop ro.build.version.security_patch 2^>nul ^<nul') do echo   Security patch      : %%i
    for /f "delims=" %%i in ('adb shell getprop ro.build.version.incremental 2^>nul ^<nul')    do echo   Build incremental   : %%i
    for /f "delims=" %%i in ('adb shell getprop ro.build.type 2^>nul ^<nul')                   do echo   Build type          : %%i
    echo.
    echo    [2/6] memory and storage... 1>CON
    echo [Memory]
    for /f "tokens=2" %%i in ('adb shell "cat /proc/meminfo 2>/dev/null | grep MemTotal"')     do echo   Total RAM           : %%i kB
    for /f "tokens=2" %%i in ('adb shell "cat /proc/meminfo 2>/dev/null | grep MemAvailable"') do echo   Available RAM       : %%i kB
    for /f "tokens=2" %%i in ('adb shell "cat /proc/meminfo 2>/dev/null | grep MemFree"')      do echo   Free RAM            : %%i kB
    for /f "tokens=2" %%i in ('adb shell "cat /proc/meminfo 2>/dev/null | grep Buffers"')      do echo   Buffers             : %%i kB
    for /f "tokens=2" %%i in ('adb shell "cat /proc/meminfo 2>/dev/null | grep '^Cached'"')      do echo   Cached              : %%i kB
    for /f "tokens=2" %%i in ('adb shell "cat /proc/meminfo 2>/dev/null | grep SwapTotal"')    do echo   Swap total          : %%i kB
    for /f "tokens=2" %%i in ('adb shell "cat /proc/meminfo 2>/dev/null | grep SwapFree"')     do echo   Swap free           : %%i kB
    echo.
    echo [Storage]
    adb shell "df -h /data 2>/dev/null" <nul
    echo.
    echo [State]
    for /f "tokens=3,4,5,6,7 delims= " %%a in ('adb shell uptime ^<nul 2^>nul') do echo   Uptime              : %%a %%b %%c
    for /f "delims=" %%i in ('adb shell "dumpsys cpuinfo 2>/dev/null | grep 'Load:'"')      do echo   %%i
    for /f "delims=" %%i in ('adb shell "dumpsys battery 2>/dev/null | grep 'level:'"')       do echo   Battery            %%i
    for /f "delims=" %%i in ('adb shell "dumpsys battery 2>/dev/null | grep 'temperature:'"') do echo   Battery temp       %%i ^(deci-degrees C^)
    for /f "delims=" %%i in ('adb shell "dumpsys battery 2>/dev/null | grep 'voltage:'"')     do echo   Battery voltage    %%i
    for /f "delims=" %%i in ('adb shell "dumpsys battery 2>/dev/null | grep 'status:'"')      do echo   Battery status     %%i
    for /f "delims=" %%i in ('adb shell "dumpsys battery 2>/dev/null | grep 'health:'"')      do echo   Battery health     %%i
    echo.
    echo    [3/6] display and graphics... 1>CON
    echo [Display]
    for /f "tokens=2 delims=:=" %%i in ('adb shell "dumpsys SurfaceFlinger 2>/dev/null | grep refresh-rate"') do echo   Display refresh    : %%i Hz
    for /f "delims=" %%i in ('adb shell wm size 2^>nul ^<nul')                                              do echo   %%i
    for /f "delims=" %%i in ('adb shell wm density 2^>nul ^<nul')                                           do echo   %%i
    echo.
    echo [Graphics renderer - current values]
    for /f "delims=" %%i in ('adb shell getprop debug.hwui.renderer 2^>nul ^<nul')   do echo   debug.hwui.renderer        : "%%i" ^(skiagl=default, skiavk=Skia Vulkan, empty=auto^)
    for /f "delims=" %%i in ('adb shell getprop ro.hwui.renderer 2^>nul ^<nul')      do echo   ro.hwui.renderer           : "%%i"
    for /f "delims=" %%i in ('adb shell settings get global angle_gl_driver_all_angle 2^>nul ^<nul') do echo   angle_gl_driver_all_angle  : %%i ^(1=force ANGLE for all GLES apps, 0/null=off^)
    for /f "delims=" %%i in ('adb shell getprop persist.log.tag 2^>nul ^<nul')       do echo   persist.log.tag            : "%%i" ^(set to "*:S" to silence all logs^)
    echo.
    echo    [4/6] animation, refresh and saver keys... 1>CON
    echo [Animation / Refresh - current values]
    for /f "delims=" %%i in ('adb shell settings get global window_animation_scale 2^>nul ^<nul')     do echo   window_animation_scale     : %%i
    for /f "delims=" %%i in ('adb shell settings get global transition_animation_scale 2^>nul ^<nul') do echo   transition_animation_scale : %%i
    for /f "delims=" %%i in ('adb shell settings get global animator_duration_scale 2^>nul ^<nul')    do echo   animator_duration_scale    : %%i
    for /f "delims=" %%i in ('adb shell settings get system min_refresh_rate 2^>nul ^<nul')           do echo   min_refresh_rate ^(Hz^)      : %%i
    for /f "delims=" %%i in ('adb shell settings get system peak_refresh_rate 2^>nul ^<nul')          do echo   peak_refresh_rate ^(Hz^)     : %%i
    echo.
    echo [Battery savers / Sync - current values]
    for /f "delims=" %%i in ('adb shell settings get global master_sync_status 2^>nul ^<nul')          do echo   master_sync_status         : %%i  ^(placebo on modern Android; Backup round-trip only^)
    for /f "delims=" %%i in ('adb shell device_config get_sync_disabled_for_tests 2^>nul ^<nul') do echo   sync_disabled_for_tests   : %%i  ^(none/persistent/until_reboot - DeviceConfig server sync^)
    for /f "delims=" %%i in ('adb shell settings get global hotword_detection_enabled 2^>nul ^<nul')   do echo   hotword_detection_enabled  : %%i  ^(1=on, 0=off^)
    for /f "delims=" %%i in ('adb shell device_config get app_hibernation app_hibernation_enabled 2^>nul ^<nul') do echo   app_hibernation_enabled    : %%i
    echo.
    echo    [5/6] network and power state... 1>CON
    echo [Network]
    for /f "delims=" %%i in ('adb shell settings get global preferred_network_mode 2^>nul ^<nul') do echo   Preferred network mode      : %%i
    for /f "delims=" %%i in ('adb shell settings get global private_dns_mode 2^>nul ^<nul')       do echo   Private DNS mode           : %%i
    for /f "delims=" %%i in ('adb shell settings get global private_dns_specifier 2^>nul ^<nul')  do echo   Private DNS host           : %%i
    echo.
    echo [Power state]
    for /f "delims=" %%i in ('adb shell settings get global low_power 2^>nul ^<nul') do echo   Battery saver         : %%i
    adb shell "cmd power get-mode 2>/dev/null" <nul
    echo.
    echo    [6/6] doze whitelist, RAM and focused app... 1>CON
    echo [Doze whitelist - first 20 entries]
    adb shell "dumpsys deviceidle whitelist 2>/dev/null" <nul
    echo.
    echo [Top 10 RAM consumers]
    adb shell "dumpsys meminfo --oom 2>/dev/null | head -40" <nul
    echo.
    echo [Currently focused app]
    adb shell "dumpsys activity activities 2>/dev/null | grep ResumedActivity" <nul
    echo.
    echo ===========================================================
    echo  End of report
    echo ===========================================================
) > "%REPORT%" < nul
>"%TEMP%\dcx_last_report_path.txt" echo %REPORT%
:: FIX (report hygiene): the ~10s report is generated ONCE above; the menu is a
:: separate :check_menu label so open-in-notepad / paginate / invalid input
:: re-show the menu instead of re-running every adb dump AND writing another
:: timestamped temp file each time. (Re-entering :check fresh still makes a new
:: dated report, which is the intended before/after-compare behavior.)
:check_menu
cls
call :logo
echo  %g%Report saved to:%w%
echo    %REPORT%
if defined PREV_REPORT if exist "!PREV_REPORT!" (
    echo  %g%Previous report:%w%
    echo    !PREV_REPORT!
)
echo.
echo  %b%[%w%1%b%]%w% Open report in Notepad (scrollable, searchable)
echo  %b%[%w%2%b%]%w% Show report in this window (paginated with MORE)
echo  %b%[%w%3%b%]%w% Show short summary here ^& go back
echo  %b%[%w%4%b%]%w% Diff vs previous report
echo  %b%[%w%5%b%]%w% Back to main menu        %d%(0 or Q also work)%w%
echo.
echo  %d%Feeling stuck? %g%0%d% or %g%Q%d% leaves this screen. Inside the paginated view
echo  it is %g%Q%d% ^(that is Windows' MORE pager, it only takes its own keys^).%w%
echo.

:check_menu_ask
:: FIX (keypress ignored / screen flooded): this menu had no tight re-ask and no cls, so
:: ANY miss redrew the whole block - including the phantom empty line the console hands
:: set /p right after the ~50 adb probes above. The first keypress looked ignored, and a
:: few misses stacked copies of the menu until the Back option scrolled away, which is
:: what "hard stuck with no way out" actually was. Re-ask in place instead, redraw only
:: on a real return, and accept 0/Q as Back. Same guard :menu_ask and :Gaming_ask use.
set "ck=" & set /p ck="Choose An Option >> "
if not defined ck goto check_menu_ask
if "!ck!"=="1" goto check_open
if "!ck!"=="2" goto check_paginate
if "!ck!"=="3" goto check_summary
if "!ck!"=="4" goto check_diff
if "!ck!"=="5" goto menu
if "!ck!"=="0" goto menu
if /i "!ck!"=="q" goto menu
goto check_menu_ask

:check_diff
if not defined PREV_REPORT goto check_diff_none
if not exist "!PREV_REPORT!" goto check_diff_none
if /i "!PREV_REPORT!"=="!REPORT!" goto check_diff_none
set "DIFFOUT=%TEMP%\dcx_report_diff.txt"
echo Comparing:
echo   OLD: !PREV_REPORT!
echo   NEW: !REPORT!
echo.
fc /n "!PREV_REPORT!" "!REPORT!" > "!DIFFOUT!" 2>&1
echo  %g%Diff saved to:%w%
echo    !DIFFOUT!
echo.
echo  %b%[%w%1%b%]%w% Open diff in Notepad
echo  %b%[%w%2%b%]%w% Show diff here (MORE)
echo  %b%[%w%3%b%]%w% Back
:: "ckd", not "cd" - a variable named cd shadows cmd's dynamic %CD% (current directory)
:: for this process and every child it spawns. See the note in :dispscaler_custom.
set "ckd=" & set /p ckd="Choose An Option >> "
if "!ckd!"=="1" (start "" notepad "!DIFFOUT!" & goto check_menu)
if "!ckd!"=="2" (cls & title Report diff  -  SPACE=next page   Q=quit back to menu & more "!DIFFOUT!" & pause >nul & goto check_menu)
goto check_menu

:check_diff_none
echo  %y%No previous report to diff against.%w%
echo  Run CheckSetting once, change something, run it again - then use Diff.
timeout /t 3 /nobreak >nul
goto check_menu

:check_open
start "" notepad "%REPORT%"
goto check_menu

:check_paginate
cls
:: The keys go in the TITLE because it stays visible on every page - an echoed hint
:: scrolls away after the first screenful. MORE is Windows' own pager and only accepts
:: its own keys, so Q quits here; 0 is a DCX menu key and does nothing inside MORE.
title Device Diagnostics  -  SPACE=next page   ENTER=one line   Q=quit back to menu
echo  %d%[i]%w% Paging with MORE:  %g%SPACE%w% next page   %g%ENTER%w% one line   %g%Q%w% quit back to the menu.
echo.
more "%REPORT%"
echo.
echo Press Any Button To Go Back
pause > nul
goto check_menu

:check_summary
cls
call :logo
echo                            %b%[%w% Quick Summary %b%]%w%
echo.
for /f "delims=" %%i in ('adb shell getprop ro.product.model 2^>nul ^<nul') do echo   Device: %%i  ^(API %SDK%^)
for /f "tokens=2" %%i in ('adb shell cat /proc/meminfo ^<nul ^| findstr "MemAvailable"') do echo   Free RAM: %%i kB
for /f "delims=" %%i in ('adb shell dumpsys battery ^<nul ^| findstr /C:"level:"')       do echo  %%i
for /f "delims=" %%i in ('adb shell dumpsys battery ^<nul ^| findstr /C:"temperature:"') do echo  %%i (deci-degrees C)
for /f "tokens=3,4,5,6,7 delims= " %%a in ('adb shell uptime ^<nul 2^>nul') do echo   Uptime: %%a %%b %%c
echo.
echo   Full report still saved at: %REPORT%
echo.
echo Press Any Button To Go Back
pause > nul
goto menu

:Auto
cls
title Auto Setup
call :logo
echo.
echo.
echo %g%Easy To Use And Safe For Daily Use If You Don't Know Anything About This Script%w%
echo.
echo.
echo %b%[%w%1%b%]%w% Run Auto Setup
echo %b%[%w%2%b%]%w% Go Back
set "kb=" & set /p kb="Choose An Option >> "
if "!kb!"=="1" goto setupautorun
if "!kb!"=="2" goto menu
:: FIX: guard against invalid input - previously any other key fell
:: straight through into :setupautorun and ran Auto Setup unprompted.
goto Auto

:setupautorun
cls && title SurfaceFlinger Setup^^!
call :logo
echo.
echo.
echo [%g%+%w%] Check Refresh Rate
timeout /t 1 /nobreak > nul
set "refresh_rate="
:: FIX: match CheckSetting - SurfaceFlinger prints refresh-rate=<n>, so take
:: tokens=2 delims==. The old tokens=3 delims=space often grabbed "Hz".
for /f "tokens=2 delims=:=" %%i in ('adb shell "dumpsys SurfaceFlinger 2>/dev/null | grep refresh-rate"') do (
    set "refresh_rate=%%i"
)
if defined refresh_rate set "refresh_rate=!refresh_rate: Hz=!"
if defined refresh_rate set "refresh_rate=!refresh_rate:Hz=!"
if defined refresh_rate set "refresh_rate=!refresh_rate: =!"
echo(!refresh_rate!| findstr /r /x /c:"[0-9][0-9]*\.*[0-9]*" >nul || set "refresh_rate="
if not defined refresh_rate (
    echo [%r%^^!%w%] Could not detect refresh rate. Auto setup cannot continue.
    pause > nul
    goto menu
)
echo [%b%^^!%w%]Refresh rate : !refresh_rate!
timeout /t 1 /nobreak > nul
:: One PowerShell launch instead of nine. This block used to spawn a process per number -
:: seven divisions and two setup steps - which is several seconds of pure process creation
:: for arithmetic that takes microseconds. The formulas are copied verbatim, including the
:: -1 / +1 / -2 terms sitting INSIDE their Round() calls, so the values are identical.
:: Not rewritten in pure cmd on purpose: "set /a" is 32-bit signed, and final*114 overflows
:: below about 53 Hz, so integer math would trade three seconds for a silent wrong answer.
:: The refresh rate goes in through the environment rather than the command line, so a stray
:: character in it can never reach PowerShell's parser.
:: Clear first: one for/f now produces all eight values, so if PowerShell fails the loop
:: simply does not run - and stale values from a previous pass, or empty ones, would be
:: written straight to setprop below. Blank them, then refuse to continue without them.
set "final=" & set "eaglpos=" & set "apsofs=" & set "elfpsofsasdasx="
set "elrdur=" & set "sfelpoassd=" & set "rgsmplsa=" & set "rgstis="
set "PT_RR=!refresh_rate!"
for /f "tokens=1-8" %%a in ('powershell -NoProfile -Command "$r=[double]$env:PT_RR; $f=[math]::Round([math]::Round(1/$r,10)*1000000000,0); @($f,[math]::Round($f/18.518520,0),[math]::Round($f/8.771929,0),[math]::Round($f/4.7619050,0),[math]::Round($f/3.7037029-1,0),[math]::Round($f/3.3333336900,0),[math]::Round($f/1.851852+1,0),[math]::Round($f/0.8771929-2,0)) -join ' '"') do (
    set "final=%%a"
    set "eaglpos=%%b"
    set "apsofs=%%c"
    set "elfpsofsasdasx=%%d"
    set "elrdur=%%e"
    set "sfelpoassd=%%f"
    set "rgsmplsa=%%g"
    set "rgstis=%%h"
)
set "PT_RR="
echo [%g%+%w%] Check Result . . . .
echo.
timeout /t 1 /nobreak > nul
echo.
echo.
echo [%y%i%w%] Experimental SF phase offsets ^(volatile; NOT a refresh-rate lock^).
echo [%b%^^!%w%] SurfaceFlinger Setup. . .
chcp 65001 >nul
if not defined rgstis (
    echo.
    echo  [%r%x%w%] Could not compute the SurfaceFlinger offsets ^(PowerShell unavailable?^).
    echo      Nothing was written - your current SF properties are untouched.
    echo.
    pause > nul
    goto menu
)
timeout /t 2 /nobreak > nul
::elrdur
adb shell setprop debug.sf.region_sampling_duration_ns %elrdur% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %elrdur% <nul
adb shell setprop debug.sf.early.app.duration %elrdur% <nul
adb shell setprop debug.sf.early.sf.duration %elrdur% <nul
adb shell setprop debug.sf.earlyGl.app.duration %elrdur% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %elrdur% <nul
::apsofs
adb shell setprop debug.sf.early_app_phase_offset_ns %apsofs% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %apsofs% <nul
::sfelpoassd
adb shell setprop debug.sf.early_gl_phase_offset_ns %sfelpoassd% <nul
adb shell setprop debug.sf.early_phase_offset_ns %sfelpoassd% <nul
::eaglpos
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %eaglpos% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %eaglpos% <nul
::elfpsofsasdasx
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %elfpsofsasdasx% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %elfpsofsasdasx% <nul
::rgstis
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %rgstis% <nul
::rgsmplsa
adb shell setprop debug.sf.region_sampling_period_ns %rgsmplsa% <nul
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %rgsmplsa% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %rgsmplsa% <nul
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %rgsmplsa% <nul
adb shell setprop debug.sf.late.app.duration %rgsmplsa% <nul
adb shell setprop debug.sf.late.sf.duration %rgsmplsa% <nul
echo [%g%+%w%] Done ^^!
echo.
echo.
timeout /t 2 /nobreak > nul
echo [^^!] SurfaceFlinger Setup Is Complete, 2nd Setup Is Ready^^!
echo [^^!] Please Wait^^!
timeout /t 10 /nobreak > nul
set count=0
title 2nd Setup
cls
call :logo
call :run_bgdexopt
cls
call :logo
set /a count+=1
echo Done %b%%count%%w%/5
timeout /t 1 /nobreak > nul
cls
call :logo
adb shell dumpsys battery reset <nul
cls
call :logo
set /a count+=1
echo Done %b%%count%%w%/5
timeout /t 1 /nobreak > nul
cls
call :logo
adb shell sm fstrim <nul
cls
call :logo
set /a count+=1
echo Done %b%%count%%w%/5
timeout /t 1 /nobreak > nul
cls
call :logo
adb shell am kill-all <nul
adb shell am kill --user 0 all <nul
adb shell am kill --user 0 current <nul
adb shell cmd looper_stats disable <nul
call :dropbox_lowprio
adb shell cmd dropbox set-rate-limit 20000000000000 <nul
adb shell cmd autofill set log_level off <nul
adb shell cmd thermalservice override-status 1 <nul
:: ----- NEW SAFE OPTIMIZATIONS (from the .sh script, vetted) -----
:: Universal log silencer (REAL, persists across reboots)
adb shell setprop persist.log.tag '*:S' <nul > nul 2>&1
adb shell setprop log.tag '*:S' <nul > nul 2>&1
:: NOTE: ANGLE-for-all-apps is intentionally NOT applied here.
:: It is device/GPU dependent and is known to crash many apps on
:: non-Pixel hardware (e.g. MediaTek GPUs). It remains available as a
:: deliberate, reversible choice under Gaming -> Force ANGLE for All
:: Apps, with a warning. Auto Setup must stay safe for every device.
:: ---------------------------------------------------------------
adb shell setprop log.tag.stats_log S <nul
adb shell setprop log.tag.APM_AudioPolicyManager S <nul
adb shell setprop log.tag.ALL S <nul
adb shell settings put global settings_enable_monitor_phantom_procs false <nul
adb shell simpleperf --log fatal --log-to-android-buffer 0 <nul > nul 2>&1
adb shell cmd autofill set max_visible_datasets 0 <nul
adb shell cmd voiceinteraction set-debug-hotword-logging false <nul
call :wm_silence_logs
adb shell dumpsys binder_calls_stats --disable <nul > nul 2>&1
adb shell dumpsys binder_calls_stats --disable-detailed-tracking <nul > nul 2>&1
adb shell settings put global binder_calls_stats sampling_interval=500000000,detailed_tracking=disable,enabled=false,upload_data=false <nul
adb shell dumpsys batterystats disable full-history <nul > nul 2>&1
adb shell ime tracing stop <nul
cls
call :logo
set /a count+=1
echo Done %b%%count%%w%/5
timeout /t 1 /nobreak > nul
cls
call :logo
adb shell logcat -c <nul
cls
call :logo
set /a count+=1
echo Done %b%%count%%w%/5
timeout /t 1 /nobreak > nul
cls
call :logo
echo Auto Setup steps finished. Press any key to go back.
adb shell cmd notification post -S bigtext -t 'Auto Setup Is Complete⚙️' 'Tag' 'Auto Setup Is A Bunch Of Tweaks That Can Be Use For Daily Or Dont Know Anything About This Script' <nul > nul 2>&1
pause > Nul
goto menu

:Optimize
cls
title Optimize Android
mode 100,37
call :logo
echo          ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
for /f "tokens=3,4,5,6,7 delims= " %%a in ('adb shell uptime ^<nul 2^>nul') do echo           [%g%+%w%]Uptime: %%a %%b %%c
set "cpucheck=N/A"
for /f "tokens=2 delims=:" %%i in ('adb shell dumpsys cpuinfo ^<nul 2^>nul ^| findstr /C:"Load:"') do set "cpucheck=%%i"
echo           [%g%+%w%]%cpucheck% LOAD
echo          ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
echo.
echo.
echo                                     %g%[%w%1%g%]%w% Run bg-dexopt-job
echo                                     %g%[%w%2%g%]%w% Run Fstrim
echo                                     %g%[%w%3%g%]%w% Run Kill-all
echo                                     %g%[%w%4%g%]%w% Run Compile App
echo                                     %g%[%w%5%g%]%w% Run Clear Cache
echo                                     %g%[%w%6%g%]%w% Run Tweak SurfaceFlinger
echo                                     %g%[%w%7%g%]%w% Run Clear Last Used
echo                                     %g%[%w%8%g%]%w% Compile All Apps
echo                                     %g%[%w%9%g%]%w% Animation Speed
echo                                     %g%[%w%0%g%]%w% Back
echo.

:Optimize_ask
:: FIX (press-twice): re-prompt without redrawing on empty/invalid input,
:: so a phantom empty line after the probes doesn't re-run them (see :dispscaler).
set "kb=" & set /p kb="Choose An Option >> "
if not defined kb goto Optimize_ask
if "!kb!"=="1" goto dexopt
if "!kb!"=="2" goto fstrim
if "!kb!"=="3" goto killall
if "!kb!"=="4" goto compile
if "!kb!"=="5" goto cache
if "!kb!"=="6" goto sftmenu
if "!kb!"=="7" goto lstused
if "!kb!"=="8" goto compileall
if "!kb!"=="9" goto animspeed
if "!kb!"=="0" goto menu
goto Optimize_ask
:: ===================================================================
:: NEW: Compile All Apps  (from Compile.bat + smooth_android.sh)
:: This re-compiles EVERY installed app with the chosen ART mode and
:: then runs the background dexopt job. Modes:
::   everything         - heaviest, slowest, may regress some apps
::   everything-profile - heavy but respects each app's usage profile
::                        (recommended balance, see smooth_android.sh)
::   speed              - optimise hot methods only (fast)
::   speed-profile      - default Android behaviour
:: NOTE: this takes 5-30+ minutes on most devices. The phone may feel
:: warm and slow during the run. Leave it plugged in.
:: ===================================================================
:compileall
cls
title Compile All Apps
call :logo
echo.
echo  This recompiles EVERY installed app. Takes 5-30+ minutes and the
echo  device will be warm. Plug it in before starting.
echo.
echo                                     %g%[%w%1%g%]%w% everything-profile (recommended)
echo                                     %g%[%w%2%g%]%w% everything         (heaviest)
echo                                     %g%[%w%3%g%]%w% speed              (fast)
echo                                     %g%[%w%4%g%]%w% speed-profile      (default)
echo                                     %g%[%w%5%g%]%w% heaviest optimization, will reduce the available storage space
echo                                     %g%[%w%6%g%]%w% Back
set "ca=" & set /p ca="Choose An Option >> "
if "!ca!"=="1" set "ca_mode=everything-profile" & goto compileall_run
if "!ca!"=="2" set "ca_mode=everything"         & goto compileall_run
if "!ca!"=="3" set "ca_mode=speed"              & goto compileall_run
if "!ca!"=="4" set "ca_mode=speed-profile"      & goto compileall_run
if "!ca!"=="5" goto compileall_heaviest
if "!ca!"=="6" goto Optimize
goto compileall

:compileall_run
cls
title Compile All Apps : %ca_mode%
echo Compiling all installed packages with mode "%ca_mode%"...
echo This may take a long time. Do not unplug the device.
echo.
call :dexopt_all_mode %ca_mode% 0
echo.
echo Running background dexopt job...
call :run_bgdexopt
echo.
echo Finished the compile/dexopt pass. See the status lines above.
echo Press any key to go back.
pause > nul
goto Optimize
:: ===================================================================
:: NEW: Heaviest optimization
:: Forces full "everything" AOT compilation of every app while
:: ignoring usage profiles (--check-prof false = compile ALL methods,
:: not just the profiled hot ones), then also AOT-compiles the
:: layout XML resources (--compile-layouts), then runs the dexopt job.
::
:: This produces the largest possible amount of compiled native code,
:: so it uses the MOST storage and takes the LONGEST. Best paired with
:: plenty of free space and the device on a charger.
:: ===================================================================
:compileall_heaviest
cls
title Compile All Apps : Heaviest
echo  %r%Heaviest optimization%w% - this will:
echo    1. Compile ALL methods of EVERY app (ignores usage profiles)
echo    2. AOT-compile layout resources
echo    3. Run the background dexopt job
echo.
echo  %y%This uses significantly more storage and is the slowest mode.%w%
echo  Make sure you have free space and the device is charging.
echo.
echo    [Y] Start
echo    [N] Back
choice /c:YN /n > nul
if errorlevel 2 goto compileall
cls
title Compile All Apps : Heaviest (running)
echo [1/3] Full compilation of all apps...
echo This may take a long time. Do not unplug the device.
:: On Android 13 and below this passes --check-prof false (compile ALL
:: methods, not just profiled ones). On Android 14+ that flag was
:: removed, so the helper drops it and uses the ART-Service-routed form.
call :dexopt_all_mode everything 1
echo.
echo [2/3] Compiling layout resources (if supported)...
:: --compile-layouts is a STANDALONE mode: it cannot be combined with
:: -f / -m / --check-prof (doing so throws "Unknown option"). It also
:: only exists on Android 10-11 - the view compiler was removed in
:: Android 12+, and is handled by ART Service from 14+. So we run it on
:: its own and detect non-support.
adb shell pm compile -a --compile-layouts <nul > "%TEMP%\dcx_layouts.txt" 2>&1
findstr /I /C:"Unknown option" /C:"Error:" /C:"Usage:" "%TEMP%\dcx_layouts.txt" > nul
if errorlevel 1 (
    echo   Layout resources compiled.
) else (
    echo   [skipped] --compile-layouts is not supported on this device.
    echo   That's expected on Android 12+ - the view compiler was removed
    echo   and ART Service handles layout optimization during normal dexopt.
)
del "%TEMP%\dcx_layouts.txt" > nul 2>&1
echo.
echo [3/3] Running background dexopt job...
call :run_bgdexopt
echo.
echo Finished the heaviest compile/dexopt pass. See the status lines above.
echo Press any key to go back.
pause > nul
goto Optimize
:: ===================================================================
:: NEW: Animation Speed  (from smooth_android.sh)
:: Animations have three independent scales in Android:
::   window_animation_scale     - opening/closing windows
::   transition_animation_scale - activity transitions
::   animator_duration_scale    - ValueAnimator-driven animations
:: Common values:
::   1.0   default
::   0.75  noticeably snappier without looking glitchy (rec.)
::   0.5   feels fast, animations almost a flash
::   0     animations off (instant but jarring; some apps glitch)
:: ===================================================================
:animspeed
cls
title Animation Speed
call :logo
echo.
echo  Current scales:
for /f "delims=" %%i in ('adb shell settings get global window_animation_scale 2^>nul ^<nul')     do echo    window_animation_scale     = %%i
for /f "delims=" %%i in ('adb shell settings get global transition_animation_scale 2^>nul ^<nul') do echo    transition_animation_scale = %%i
for /f "delims=" %%i in ('adb shell settings get global animator_duration_scale 2^>nul ^<nul')    do echo    animator_duration_scale    = %%i
echo.
echo                                     %g%[%w%1%g%]%w% 0     (off, instant)
echo                                     %g%[%w%2%g%]%w% 0.5   (very fast)
echo                                     %g%[%w%3%g%]%w% 0.75  (snappy, recommended)
echo                                     %g%[%w%4%g%]%w% 1.0   (default)
echo                                     %g%[%w%5%g%]%w% Custom
echo                                     %g%[%w%6%g%]%w% Back
set "as=" & set /p as="Choose An Option >> "
if "!as!"=="1" set "asv=0"    & goto animspeed_apply
if "!as!"=="2" set "asv=0.5"  & goto animspeed_apply
if "!as!"=="3" set "asv=0.75" & goto animspeed_apply
if "!as!"=="4" set "asv=1.0"  & goto animspeed_apply
if "!as!"=="5" goto animspeed_custom
if "!as!"=="6" goto Optimize
goto animspeed

:animspeed_custom
echo Enter a decimal value between 0 and 2 (e.g. 0.5):
set "asv=" & set /p asv="Value (blank = cancel) >> "
if "!asv!"=="" goto animspeed
:: FIX: the value used to go into three "settings put" completely unchecked -
:: empty/garbage/quote input broke the commands or stored junk scales. Accept
:: a comma decimal (1,5 -> 1.5), then gate to the documented 0-2 range
:: (accepts 0, 1, 2, 0.75, .5, 2.0 and the like).
set "asv=!asv:,=.!"
echo !asv!| findstr /r /x /c:"[0-2]" /c:"[01]\.[0-9][0-9]*" /c:"2\.0*" /c:"\.[0-9][0-9]*" >nul || goto animspeed_custom_bad
goto animspeed_apply

:animspeed_custom_bad
echo [%r%^^!%w%] Invalid value. Use a number between 0 and 2, e.g. 0.5, 0.75, 1.
timeout /t 2 /nobreak >nul
goto animspeed_custom

:animspeed_apply
adb shell settings put global window_animation_scale %asv% <nul
adb shell settings put global transition_animation_scale %asv% <nul
adb shell settings put global animator_duration_scale %asv% <nul
call :_act_reset
call :_settings_verify global window_animation_scale %asv%
call :_settings_verify global transition_animation_scale %asv%
call :_settings_verify global animator_duration_scale %asv%
call :_act_summary
pause > nul
goto animspeed

:lstused
cls
call :logo
title Clear Last Used Is Running^^!
:: FIX: this was one "adb shell" per package. Measured on a real device (Android 12,
:: 269 packages): ~99 ms per round trip = ~26.6 SECONDS spent entirely on transport,
:: for work the device finishes in milliseconds. The loop now runs INSIDE the device
:: shell - one connection, same work, same per-package progress, because the device
:: echoes each name back and the Windows side just prints it. Verified to return the
:: identical 269-package set as the old parse before it was changed.
::
:: The other option - chaining every command into ONE Windows-built string with ";" -
:: does NOT work here: "pm list package" is the FULL list, and 269 packages is ~20k
:: characters against cmd's 8191-char command line. cmd truncates it silently, so
:: packages past the cut are skipped with no error at all.
::
:: Two details that matter: "${p#package:}" strips the prefix ON THE DEVICE, so the
:: name never crosses the adb transport mid-loop (no CRLF to trip over); and the
:: redirects are ">/dev/null 2>/dev/null", never "2>&1" - an "&" inside a quoted adb
:: argument inside a for /f IN clause is exactly the nested-quoting boundary that has
:: bitten this script before, and "2>/dev/null" needs no "&" to do the same job.
for /f "delims=" %%a in ('adb shell "pm list packages | while read p; do p=${p#package:}; cmd usagestats clear-last-used-timestamps $p >/dev/null 2>/dev/null; echo $p; done" ^<nul') do (
echo %%a ━ clear last used^^!
)
echo.
echo.
echo Per-package clear finished. Running cleanup commands...
adb shell cmd activity clear-debug-app <nul
adb shell cmd activity clear-exit-info <nul
adb shell cmd activity clear-watch-heap all <nul
adb shell cmd blob_store clear-all-sessions <nul
adb shell cmd blob_store clear-all-blobs <nul
echo.
echo Done. Press any key to return to Optimize.
pause > nul
goto Optimize

:sftmenu
title SF Menu
cls
echo.
echo.
call :logo
echo  %y%Note:%w% profiles write volatile debug.sf.* phase offsets. They do NOT
echo  lock refresh rate - use Battery - Refresh Rate Lock for Hz. Reboot clears them.
echo.
echo                                      [%g%1%w%] 60hz
echo                                      [%g%2%w%] 90hz
echo                                      [%g%3%w%] 120hz
echo                                      [%g%4%w%] 144hz
echo                                      [%g%5%w%] Remove
echo                                      [%g%6%w%] Back
set "opt=" & set /p opt="Choose An Option >> "
if "!opt!"=="1" goto sf60
if "!opt!"=="2" goto sf90
if "!opt!"=="3" goto sf120
if "!opt!"=="4" goto sf144
if "!opt!"=="5" goto removesf
if "!opt!"=="6" goto Optimize
goto sftmenu

:sf60
cls
title 60hz menu
echo.
echo.
call :logo
echo                                      [%g%1%w%] Balance offsets
echo                                      [%g%2%w%] Low-latency offsets
echo                                      [%g%3%w%] Conserving offsets
echo                                      [%g%4%w%] Back
echo.
echo.
set "opt=" & set /p opt="Choose An Option >> "
if "!opt!"=="1" goto sf60balance
if "!opt!"=="2" goto sf60gaming
if "!opt!"=="3" goto sf60battery
if "!opt!"=="4" goto sftmenu
:: FIX: invalid input previously fell into :sf60battery
goto sf60

:sf60battery
cls
title 60hz SF : Battery Saver Mode
set chm=6500000
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %chm% <nul
adb shell setprop debug.sf.region_sampling_period_ns %chm% <nul
adb shell setprop debug.sf.late.app.duration %chm% <nul
adb shell setprop debug.sf.late.sf.duration %chm% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %chm% <nul
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %chm% <nul
::3100000
set chh=3500000
adb shell setprop debug.sf.earlyGl.app.duration %chh% <nul
adb shell setprop debug.sf.early.sf.duration %chh% <nul
adb shell setprop debug.sf.region_sampling_duration_ns %chh% <nul
adb shell setprop debug.sf.early.app.duration %chh% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %chh% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %chh% <nul
::13900000
set chb=14000000
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %chb% <nul
::1400000
set chbb=1300000
adb shell setprop debug.sf.early_app_phase_offset_ns %chbb% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %chbb% <nul
::700000
set chn=750000
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %chn% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %chn% <nul
::4700000
set chsss=4000000
adb shell setprop debug.sf.early_gl_phase_offset_ns %chsss% <nul
adb shell setprop debug.sf.early_phase_offset_ns %chsss% <nul
::3000000
set chbay=2800000
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %chbay% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %chbay% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:sf60gaming
cls
title 60hz SF : Gaming Mode
call :logo
set chm=8500000
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %chm% <nul
adb shell setprop debug.sf.region_sampling_period_ns %chm% <nul
adb shell setprop debug.sf.late.app.duration %chm% <nul
adb shell setprop debug.sf.late.sf.duration %chm% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %chm% <nul
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %chm% <nul
::3100000
set chh=5100000
adb shell setprop debug.sf.earlyGl.app.duration %chh% <nul
adb shell setprop debug.sf.early.sf.duration %chh% <nul
adb shell setprop debug.sf.region_sampling_duration_ns %chh% <nul
adb shell setprop debug.sf.early.app.duration %chh% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %chh% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %chh% <nul
::13900000
set chb=15000000
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %chb% <nul
::1400000
set chbb=1550000
adb shell setprop debug.sf.early_app_phase_offset_ns %chbb% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %chbb% <nul
::700000
set chn=800000
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %chn% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %chn% <nul
::4700000
set chsss=4800000
adb shell setprop debug.sf.early_gl_phase_offset_ns %chsss% <nul
adb shell setprop debug.sf.early_phase_offset_ns %chsss% <nul
::3000000
set chbay=3200000
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %chbay% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %chbay% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:sf60balance
cls
title 60hz SF : Balance Mode
call :logo
::6500000
set chm=6500000
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %chm% <nul
adb shell setprop debug.sf.region_sampling_period_ns %chm% <nul
adb shell setprop debug.sf.late.app.duration %chm% <nul
adb shell setprop debug.sf.late.sf.duration %chm% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %chm% <nul
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %chm% <nul
::3100000
set chh=2900000
adb shell setprop debug.sf.earlyGl.app.duration %chh% <nul
adb shell setprop debug.sf.early.sf.duration %chh% <nul
adb shell setprop debug.sf.region_sampling_duration_ns %chh% <nul
adb shell setprop debug.sf.early.app.duration %chh% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %chh% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %chh% <nul
::13900000
set chb=13000000
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %chb% <nul
::1400000
set chbb=1350000
adb shell setprop debug.sf.early_app_phase_offset_ns %chbb% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %chbb% <nul
::700000
set chn=750000
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %chn% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %chn% <nul
::4700000
set chsss=4500000
adb shell setprop debug.sf.early_gl_phase_offset_ns %chsss% <nul
adb shell setprop debug.sf.early_phase_offset_ns %chsss% <nul
::3000000
set chbay=3200000
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %chbay% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %chbay% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:sf90
cls
call :logo
title 90hz menu
echo                                      [%g%1%w%] Balance offsets
echo                                      [%g%2%w%] Low-latency offsets
echo                                      [%g%3%w%] Conserving offsets
echo                                      [%g%4%w%] Back
echo.
echo.
set "opt=" & set /p opt="Choose An Option >> "
if "!opt!"=="1" goto sf90balance
if "!opt!"=="2" goto sf90gaming
if "!opt!"=="3" goto sf90battery
if "!opt!"=="4" goto sftmenu
:: FIX: invalid input previously fell into :sf90battery
goto sf90

:sf90battery
cls
title 90hz SF : Battery Mode
call :logo
::Battery Saver Mode 90Hz
set px=533333
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %px% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %px% <nul
set pxl=4733333
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %pxl% <nul
adb shell setprop debug.sf.late.app.duration %pxl% <nul
adb shell setprop debug.sf.late.sf.duration %pxl% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %pxl% <nul
adb shell setprop debug.sf.region_sampling_period_ns %pxl% <nul
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %pxl% <nul
set chxl=2533333
adb shell setprop debug.sf.earlyGl.app.duration %chxl% <nul
adb shell setprop debug.sf.early.sf.duration %chxl% <nul
adb shell setprop debug.sf.region_sampling_duration_ns %chxl% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %chxl% <nul
adb shell setprop debug.sf.early.app.duration %chxl% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %chxl% <nul
set dhbx=13333333
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %dhbx% <nul
set dhbxz=753333
adb shell setprop debug.sf.early_app_phase_offset_ns %dhbxz% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %dhbxz% <nul
set xcxz=2800000
adb shell setprop debug.sf.early_gl_phase_offset_ns %xcxz% <nul
adb shell setprop debug.sf.early_phase_offset_ns %xcxz% <nul
set xcfs=1733333
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %xcfs% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %xcfs% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:sf90gaming
cls
title 90hz SF : Gaming Mode
call :logo
::Gaming Mode 90Hz
set px=653333
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %px% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %px% <nul
set pxl=5533333
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %pxl% <nul
adb shell setprop debug.sf.late.app.duration %pxl% <nul
adb shell setprop debug.sf.late.sf.duration %pxl% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %pxl% <nul
adb shell setprop debug.sf.region_sampling_period_ns %pxl% <nul
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %pxl% <nul
set chxl=2933333
adb shell setprop debug.sf.earlyGl.app.duration %chxl% <nul
adb shell setprop debug.sf.early.sf.duration %chxl% <nul
adb shell setprop debug.sf.region_sampling_duration_ns %chxl% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %chxl% <nul
adb shell setprop debug.sf.early.app.duration %chxl% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %chxl% <nul
set dhbx=15333333
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %dhbx% <nul
set dhbxz=883333
adb shell setprop debug.sf.early_app_phase_offset_ns %dhbxz% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %dhbxz% <nul
set xcxz=3833333
adb shell setprop debug.sf.early_gl_phase_offset_ns %xcxz% <nul
adb shell setprop debug.sf.early_phase_offset_ns %xcxz% <nul
set xcfs=2333333
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %xcfs% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %xcfs% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:sf90balance
cls
title 90hz SF : Balance Mode
call :logo
set px=533333
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %px% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %px% <nul
::**
set pxl=4833333
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %pxl% <nul
adb shell setprop debug.sf.late.app.duration %pxl% <nul
adb shell setprop debug.sf.late.sf.duration %pxl% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %pxl% <nul
adb shell setprop debug.sf.region_sampling_period_ns %pxl% <nul
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %pxl% <nul
::***
set chxl=2533333
adb shell setprop debug.sf.earlyGl.app.duration %chxl% <nul
adb shell setprop debug.sf.early.sf.duration %chxl% <nul
adb shell setprop debug.sf.region_sampling_duration_ns %chxl% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %chxl% <nul
adb shell setprop debug.sf.early.app.duration %chxl% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %chxl% <nul
::****
set dhbx=11333333
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %dhbx% <nul
set dhbxz=833333
adb shell setprop debug.sf.early_app_phase_offset_ns %dhbxz% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %dhbxz% <nul
::*****
set xcxz=3333333
adb shell setprop debug.sf.early_gl_phase_offset_ns %xcxz% <nul
adb shell setprop debug.sf.early_phase_offset_ns %xcxz% <nul
::******
set xcfs=1833333
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %xcfs% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %xcfs% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:sf120
cls
title 120hz menu
call :logo
echo                                      [%g%1%w%] Balance offsets
echo                                      [%g%2%w%] Low-latency offsets
echo                                      [%g%3%w%] Conserving offsets
echo                                      [%g%4%w%] Back
echo.
echo.
set "opt=" & set /p opt="Choose An Option >> "
if "!opt!"=="1" goto sf120balance
if "!opt!"=="2" goto sf120gaming
if "!opt!"=="3" goto sf120battery
if "!opt!"=="4" goto sftmenu
:: FIX: invalid input previously fell into :sf120gaming
goto sf120

:sf120gaming
cls
title 120hz SF : Gaming Mode
call :logo
::Gaming Mode 120Hz
set qk=3666666
adb shell setprop debug.sf.region_sampling_duration_ns %qk% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %qk% <nul
adb shell setprop debug.sf.early.app.duration %qk% <nul
adb shell setprop debug.sf.early.sf.duration %qk% <nul
adb shell setprop debug.sf.earlyGl.app.duration %qk% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %qk% <nul
set fsk=1666666
adb shell setprop debug.sf.early_app_phase_offset_ns %fsk% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %fsk% <nul
set erl=3866666
adb shell setprop debug.sf.early_gl_phase_offset_ns %erl% <nul
adb shell setprop debug.sf.early_phase_offset_ns %erl% <nul
set pos=586666
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %pos% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %pos% <nul
set fpsos=2766666
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %fpsos% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %fpsos% <nul
set tons=19666666
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %tons% <nul
set ltsdur=5966666
adb shell setprop debug.sf.late.app.duration %ltsdur% <nul
adb shell setprop debug.sf.late.sf.duration %ltsdur% <nul
adb shell setprop debug.sf.region_sampling_period_ns %ltsdur% <nul
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %ltsdur% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %ltsdur% <nul
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %ltsdur% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:sf120battery
cls
title 120hz SF : Battery Mode
call :logo
::Battery Saver Mode 120Hz
set qk=2066666
adb shell setprop debug.sf.region_sampling_duration_ns %qk% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %qk% <nul
adb shell setprop debug.sf.early.app.duration %qk% <nul
adb shell setprop debug.sf.early.sf.duration %qk% <nul
adb shell setprop debug.sf.earlyGl.app.duration %qk% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %qk% <nul
set fsk=796666
adb shell setprop debug.sf.early_app_phase_offset_ns %fsk% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %fsk% <nul
set erl=2166666
adb shell setprop debug.sf.early_gl_phase_offset_ns %erl% <nul
adb shell setprop debug.sf.early_phase_offset_ns %erl% <nul
set pos=396666
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %pos% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %pos% <nul
set fpsos=1166666
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %fpsos% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %fpsos% <nul
set tons=8466666
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %tons% <nul
set ltsdur=3966666
adb shell setprop debug.sf.late.app.duration %ltsdur% <nul
adb shell setprop debug.sf.late.sf.duration %ltsdur% <nul
adb shell setprop debug.sf.region_sampling_period_ns %ltsdur% <nul
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %ltsdur% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %ltsdur% <nul
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %ltsdur% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:sf120balance
cls
title 120hz SF : Balance Mode
call :logo
::p1
set qk=1966666
adb shell setprop debug.sf.region_sampling_duration_ns %qk% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %qk% <nul
adb shell setprop debug.sf.early.app.duration %qk% <nul
adb shell setprop debug.sf.early.sf.duration %qk% <nul
adb shell setprop debug.sf.earlyGl.app.duration %qk% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %qk% <nul
::p2
set fsk=896666
adb shell setprop debug.sf.early_app_phase_offset_ns %fsk% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %fsk% <nul
::p3
set erl=2466666
adb shell setprop debug.sf.early_gl_phase_offset_ns %erl% <nul
adb shell setprop debug.sf.early_phase_offset_ns %erl% <nul
::p4
set pos=446666
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %pos% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %pos% <nul
::p5
set fpsos=1466666
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %fpsos% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %fpsos% <nul
::p6
set tons=4666666
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %tons% <nul
::p7
set ltsdur=4466666
adb shell setprop debug.sf.late.app.duration %ltsdur% <nul
adb shell setprop debug.sf.late.sf.duration %ltsdur% <nul
adb shell setprop debug.sf.region_sampling_period_ns %ltsdur% <nul
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %ltsdur% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %ltsdur% <nul
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %ltsdur% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu
::========================================
:: 144hz SurfaceFlinger Tweaks
:: Frame period = 6,944,444 ns (1s / 144)
:: Values derived proportionally from 120hz
::========================================
:sf144
cls
title 144hz menu
call :logo
echo                                      [%g%1%w%] Balance offsets
echo                                      [%g%2%w%] Low-latency offsets
echo                                      [%g%3%w%] Conserving offsets
echo                                      [%g%4%w%] Back
echo.
echo.
set "opt=" & set /p opt="Choose An Option >> "
if "!opt!"=="1" goto sf144balance
if "!opt!"=="2" goto sf144gaming
if "!opt!"=="3" goto sf144battery
if "!opt!"=="4" goto sftmenu
goto sf144

:sf144gaming
cls
title 144hz SF : Gaming Mode
call :logo
:: Gaming Mode 144Hz - optimised for maximum throughput, minimal SF latency
:: early group (render duration)
set v144_early=3055555
adb shell setprop debug.sf.region_sampling_duration_ns %v144_early% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %v144_early% <nul
adb shell setprop debug.sf.early.app.duration %v144_early% <nul
adb shell setprop debug.sf.early.sf.duration %v144_early% <nul
adb shell setprop debug.sf.earlyGl.app.duration %v144_early% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %v144_early% <nul
:: early phase offsets
set v144_earlyoff=1388888
adb shell setprop debug.sf.early_app_phase_offset_ns %v144_earlyoff% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %v144_earlyoff% <nul
:: early GL phase
set v144_earlygl=3222222
adb shell setprop debug.sf.early_gl_phase_offset_ns %v144_earlygl% <nul
adb shell setprop debug.sf.early_phase_offset_ns %v144_earlygl% <nul
:: high-fps early app phase
set v144_hfearly=488888
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %v144_hfearly% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %v144_hfearly% <nul
:: high-fps early GL phase
set v144_hfearlygl=2305555
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %v144_hfearlygl% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %v144_hfearlygl% <nul
:: region sampling timer timeout
set v144_timer=16388888
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %v144_timer% <nul
:: late group (VSYNC window)
set v144_late=4972222
adb shell setprop debug.sf.late.app.duration %v144_late% <nul
adb shell setprop debug.sf.late.sf.duration %v144_late% <nul
adb shell setprop debug.sf.region_sampling_period_ns %v144_late% <nul
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %v144_late% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %v144_late% <nul
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %v144_late% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:sf144battery
cls
title 144hz SF : Battery Mode
call :logo
:: Battery Mode 144Hz - reduced render budget to ease GPU/SF pressure
set v144_early=1722222
adb shell setprop debug.sf.region_sampling_duration_ns %v144_early% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %v144_early% <nul
adb shell setprop debug.sf.early.app.duration %v144_early% <nul
adb shell setprop debug.sf.early.sf.duration %v144_early% <nul
adb shell setprop debug.sf.earlyGl.app.duration %v144_early% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %v144_early% <nul
set v144_earlyoff=663888
adb shell setprop debug.sf.early_app_phase_offset_ns %v144_earlyoff% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %v144_earlyoff% <nul
set v144_earlygl=1805555
adb shell setprop debug.sf.early_gl_phase_offset_ns %v144_earlygl% <nul
adb shell setprop debug.sf.early_phase_offset_ns %v144_earlygl% <nul
set v144_hfearly=330555
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %v144_hfearly% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %v144_hfearly% <nul
set v144_hfearlygl=972222
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %v144_hfearlygl% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %v144_hfearlygl% <nul
set v144_timer=7055555
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %v144_timer% <nul
set v144_late=3305555
adb shell setprop debug.sf.late.app.duration %v144_late% <nul
adb shell setprop debug.sf.late.sf.duration %v144_late% <nul
adb shell setprop debug.sf.region_sampling_period_ns %v144_late% <nul
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %v144_late% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %v144_late% <nul
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %v144_late% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:sf144balance
cls
title 144hz SF : Balance Mode
call :logo
:: Balance Mode 144Hz - smooth at full refresh rate without gaming overhead
set v144_early=1638888
adb shell setprop debug.sf.region_sampling_duration_ns %v144_early% <nul
adb shell setprop debug.sf.cached_set_render_duration_ns %v144_early% <nul
adb shell setprop debug.sf.early.app.duration %v144_early% <nul
adb shell setprop debug.sf.early.sf.duration %v144_early% <nul
adb shell setprop debug.sf.earlyGl.app.duration %v144_early% <nul
adb shell setprop debug.sf.earlyGl.sf.duration %v144_early% <nul
set v144_earlyoff=747222
adb shell setprop debug.sf.early_app_phase_offset_ns %v144_earlyoff% <nul
adb shell setprop debug.sf.early_gl_app_phase_offset_ns %v144_earlyoff% <nul
set v144_earlygl=2055555
adb shell setprop debug.sf.early_gl_phase_offset_ns %v144_earlygl% <nul
adb shell setprop debug.sf.early_phase_offset_ns %v144_earlygl% <nul
set v144_hfearly=372222
adb shell setprop debug.sf.high_fps_early_app_phase_offset_ns %v144_hfearly% <nul
adb shell setprop debug.sf.high_fps_early_gl_app_phase_offset_ns %v144_hfearly% <nul
set v144_hfearlygl=1222222
adb shell setprop debug.sf.high_fps_early_gl_phase_offset_ns %v144_hfearlygl% <nul
adb shell setprop debug.sf.high_fps_early_phase_offset_ns %v144_hfearlygl% <nul
set v144_timer=3888888
adb shell setprop debug.sf.region_sampling_timer_timeout_ns %v144_timer% <nul
set v144_late=3722222
adb shell setprop debug.sf.late.app.duration %v144_late% <nul
adb shell setprop debug.sf.late.sf.duration %v144_late% <nul
adb shell setprop debug.sf.region_sampling_period_ns %v144_late% <nul
adb shell setprop debug.sf.phase_offset_threshold_for_next_vsync_ns %v144_late% <nul
adb shell setprop debug.sf.high_fps_late_app_phase_offset_ns %v144_late% <nul
adb shell setprop debug.sf.high_fps_late_sf_phase_offset_ns %v144_late% <nul
echo Done , Press Any Button To Go Back
pause > nul
goto sftmenu

:removesf
cls
title Remove SF offsets
call :logo
echo.
echo  Clears the debug.sf.* phase-offset / duration props that DCX Auto and
echo  Optimize - SurfaceFlinger write. Empty setprop resets them for this boot;
echo  a reboot also clears any leftovers.
echo.
echo  [%g%Y%w%] Clear now    [%g%N%w%] Cancel
choice /c:YN /n >nul
if errorlevel 2 goto sftmenu
echo.
call :_sf_clear_props
echo.
echo  Cleared. Optional reboot finishes any stuck SF state.
echo  [%g%R%w%] Reboot now    [%g%B%w%] Back without reboot
choice /c:RB /n >nul
if errorlevel 2 goto sftmenu
adb reboot <nul
goto sftmenu

:_sf_clear_props
:: Props written by :setupautorun and the SF Hz profile menus.
for %%P in (
    debug.sf.region_sampling_duration_ns
    debug.sf.cached_set_render_duration_ns
    debug.sf.early.app.duration
    debug.sf.early.sf.duration
    debug.sf.earlyGl.app.duration
    debug.sf.earlyGl.sf.duration
    debug.sf.early_app_phase_offset_ns
    debug.sf.early_gl_app_phase_offset_ns
    debug.sf.early_gl_phase_offset_ns
    debug.sf.early_phase_offset_ns
    debug.sf.high_fps_early_app_phase_offset_ns
    debug.sf.high_fps_early_gl_app_phase_offset_ns
    debug.sf.high_fps_early_gl_phase_offset_ns
    debug.sf.high_fps_early_phase_offset_ns
    debug.sf.region_sampling_timer_timeout_ns
    debug.sf.region_sampling_period_ns
    debug.sf.phase_offset_threshold_for_next_vsync_ns
    debug.sf.high_fps_late_app_phase_offset_ns
    debug.sf.high_fps_late_sf_phase_offset_ns
    debug.sf.late.app.duration
    debug.sf.late.sf.duration
) do (
    adb shell setprop %%P '' <nul >nul 2>&1
    echo  cleared %%P
)
exit /b
:: ===========================================================================
:: WHY '' AND NOT "" - read this before "tidying" any setprop clear.
:: `adb shell setprop KEY ""` DOES NOT CLEAR ANYTHING. cmd strips the quotes
:: when it builds adb's argv, adb re-joins argv with spaces, and the Android
:: shell then receives `setprop KEY` with ONE argument - so it prints
::   usage: setprop NAME VALUE
:: to stderr and changes nothing. Every such line in DCX was silently failing:
:: SF offset Remove, Universal Logs On, Logs On (persist.log.tag), and GPU
:: Renderer Clear all reported success while leaving the property set.
:: Single quotes survive that round trip - cmd passes '' through literally and
:: the device shell turns it into a genuine empty argument. Verified on a real
:: device: "" left the value untouched, '' cleared it.
:: Same quote-stripping mechanic the :_bk_settings note describes.
:: ===========================================================================
:dexopt
@echo off
cls
title bg-dexopt-job is running
call :logo
echo.
echo.
call :run_bgdexopt
echo %c%Done%w%, Press Any Button To Go Back
pause > nul
goto Optimize

:fstrim
@echo off
cls
title fstrim is running
call :logo
echo.
echo  fstrim tells the kernel which storage blocks are free so flash can
echo  stay fast. It runs %y%silently%w% - Android prints nothing on success,
echo  which is why it can look like "nothing happened". That's normal.
echo.
echo  Free space on /data BEFORE:
for /f "delims=" %%i in ('adb shell df -h /data 2^>nul ^<nul ^| findstr /v "Filesystem"') do echo    %%i
echo.
echo  Running 'sm fstrim'...
:: FIX (press-once regression): fstrim is the only routine in this menu that runs a
:: bare "adb shell sm fstrim" with no stdin redirect before its pause. Every other adb
:: call reached from a menu already ends in <nul for this reason (see :forcedoze), and
:: fstrim is the one that regressed. Without the redirect the adb process can leave a
:: stray end-of-line in the console buffer, and the following "pause" consumes that
:: phantom newline instead of waiting - so run #1 returns on its own, run #2 waits. The
:: <nul brings fstrim back in line with the rest of the script.
adb shell sm fstrim <nul
echo  Trigger sent.
echo.
echo  Free space on /data AFTER:
for /f "delims=" %%i in ('adb shell df -h /data 2^>nul ^<nul ^| findstr /v "Filesystem"') do echo    %%i
echo.
echo  %b%Note:%w% fstrim reclaims at the flash level, so the df numbers may
echo  not change. On some devices the trim only fully runs while the
echo  phone is %b%charging and idle/screen-off%w%; if so, leave it plugged in
echo  and locked for a few minutes and it will complete on its own.
echo.
echo %c%Done%w%, Press Any Button To Go Back
pause > nul
goto Optimize

:killall
@echo off
cls
title kill process
:: FIX: detect the current foreground package so we don't kill it
:: (force-stopping the focused app loses unsaved data in messengers,
:: notes, browsers, etc.)
:: FIX: the resumed-activity field is named differently across Android
:: versions - "mResumedActivity" (older), "ResumedActivity:" and
:: "topResumedActivity=" (Android 13+, incl. API 36 on Pixel). Match the
:: shared substring "ResumedActivity" and pull the package out of the
:: ActivityRecord{...} brace regardless of prefix or the '='/':' separator:
:: after '{' the layout is always "<hash> u0 <pkg>/<activity> t<id>}", so
:: the package is token 3, then split on '/'. The old code matched only
:: "mResumedActivity" with tokens=2 - it found nothing on Android 16 (field
:: renamed) and, even when it matched, tokens=2 grabbed "ActivityRecord{<hash>"
:: instead of the package, so the focused app was never actually skipped.
set "FG_PKG="
for /f "tokens=2 delims={" %%a in ('adb shell dumpsys activity activities 2^>nul ^<nul ^| findstr /C:"ResumedActivity"') do (
    if not defined FG_PKG (
        for /f "tokens=3 delims= " %%b in ("%%a") do (
            for /f "tokens=1 delims=/" %%c in ("%%b") do set "FG_PKG=%%c"
        )
    )
)
if defined FG_PKG echo [%b%i%w%] Foreground app detected, will be skipped: %FG_PKG%
echo.
:: Critical packages we never force-stop even on third-party list
:: (some OEMs ship important apps as user-installed APKs)
set "PROTECT=com.android.systemui com.google.android.inputmethod.latin com.android.inputmethod.latin com.android.vending"
for /f "tokens=2 delims=:" %%a in ('adb shell pm list package -3 ^<nul') do (
    set "PKG=%%a"
    set "SKIP=0"
    if defined FG_PKG (
        if "!PKG!"=="!FG_PKG!" set "SKIP=1"
    )
    for %%p in (%PROTECT%) do (
        if "!PKG!"=="%%p" set "SKIP=1"
    )
    if "!SKIP!"=="1" (
        echo Skip  !PKG!  ^(protected^)
    ) else (
        echo Kill  !PKG!
        adb shell am force-stop !PKG! <nul > nul 2>&1
    )
)
adb shell am kill-all <nul > nul 2>&1
echo %d%Done%w%, Press Any Button To Go Back
pause > nul
goto Optimize

:compile
@echo off
cls
title Compile App
echo.
echo.
echo Enter The Mode You Want ^^!
echo Valid modes: speed, speed-profile, verify, quicken, everything, everything-profile
echo Recommended: speed (best performance, slower install)
echo.
set "mode=" & set /p mode="Choose A Mode >> "
:: FIX: validate mode against the list ART actually accepts
set "modeok=0"
for %%m in (speed speed-profile verify quicken everything everything-profile) do (
    if /i "!mode!"=="%%m" set "modeok=1"
)
:: The accepted set lives in THREE places - the "Valid modes" line above, the for-loop
:: whitelist, and this error - and they have to say the same thing. This one used to list
:: five of the six, silently dropping everything-profile, so a user who typo'd was told an
:: option existed less than it did. The loop is the source of truth; keep both texts equal
:: to it whenever a mode is added or removed.
:: (Comment hoisted OUT of the if-block: a "::" inside ( ) makes cmd print "The system
:: cannot find the drive specified." on every run through this path.)
if "%modeok%"=="0" (
    echo [%r%^^!%w%] Invalid mode. Use one of: speed, speed-profile, verify, quicken,
    echo     everything, everything-profile.
    pause > nul
    goto Optimize
)
set "package=" & set /p package="Put Your Package Name Here >> "
if "!package!"=="" (
    echo [%r%^^!%w%] Package name cannot be empty.
    pause > nul
    goto Optimize
)
set "_PKGCHK=!package!"
call :_pkg_ok || (
    echo  [%r%x%w%] Invalid package name. Letters, digits, dots and underscores only.
    timeout /t 2 /nobreak > nul
    goto Optimize
)
:: Verify the package actually exists on the device
:: FIX (prefix collision): a bare findstr /C: is a SUBSTRING match, so "com.foo" matched
:: the line for "com.foobar" and DCX reported an uninstalled package as present. /x pins
:: it to the whole line - but /x alone is a trap: adb output can arrive LF-only, and
:: findstr then treats the whole stream as ONE line, so /x would find nothing and every
:: package would read as "not installed". `find /v ""` re-terminates the lines as CRLF
:: first (the same normalisation :tw_snap_take already relies on). Verified both ways.
adb shell pm list packages 2>nul <nul | find /v "" | findstr /x /c:"package:!package!" > nul
if errorlevel 1 (
    echo [%r%^^!%w%] Package "!package!" is not installed on the device.
    pause > nul
    goto Optimize
)
echo.
echo Compiling !package! with mode %mode%...
adb shell cmd package compile -m %mode% -f !package! <nul
if errorlevel 1 (
    echo [%r%^^!%w%] Compile reported a failure for !package!.
) else (
    echo [%g%+%w%] Compile finished for !package! ^(mode %mode%^).
)
echo Press Any Button To Go Back
pause > nul
goto Optimize

:cache
:: FIX: was `mode 45,12` - a 45x12 console truncated the sub-menus and made the
:: window jarringly resize vs every other screen. Match the standard size.
mode 100,37
cls
title Clear Cache
echo [1] %c%Clear Cache%w%
echo [2] %c%Back%w%
set "k=" & set /p k="Choose An Option >> "
if "!k!"=="1" goto sdgb
if "!k!"=="2" goto Optimize
:: FIX: guard against invalid input - previously fell through to :sdgb
goto cache

:sdgb
cls
title Clear App Cache
echo.
echo [1] %c%Trim system cache (no root)%w%
echo [2] %r%Wipe all app cache folders (root required)%w%
echo [3] %c%Back%w%
echo.
set "k=" & set /p k="Choose an option >> "
:: FIX (navigation): every screen under Clear Cache used to exit two levels up to
:: :Optimize, so "Back" from a sub-screen skipped its own parent and finishing an action
:: dumped you out of the section entirely. Each now returns to the screen it came from.
if "!k!"=="1" goto cache_trim
if "!k!"=="2" goto cache_wipe
if "!k!"=="3" goto cache
goto sdgb

:cache_trim
cls
echo Trimming system cache (may take a moment)...
adb shell pm trim-caches 1200G <nul
if errorlevel 1 (
    echo [%r%^^!%w%] trim-caches reported a failure. Nothing else was changed.
) else (
    echo [%g%+%w%] Trim requested. Press any key.
)
pause > nul
goto sdgb

:cache_wipe
cls
echo This requires ROOT and will remove ALL app cache files.
echo.
echo [C] Cancel
echo [Y] Yes, wipe all app caches (requires root)
choice /c:CY /n > nul
if errorlevel 2 goto cache_wipe_go
echo Cancelled.
pause > nul
goto sdgb

:cache_wipe_go
echo.
adb shell "su -c 'echo _DCXROOT'" <nul 2>nul | findstr /C:"_DCXROOT" >nul
if not errorlevel 1 goto cache_wipe_root_ok
echo [%r%^^!%w%] Root is not available on this device - nothing was wiped.
echo      This wipe needs a rooted device such as Magisk.
echo.
echo Press Any Button To Go Back
pause > nul
goto sdgb

:cache_wipe_root_ok
echo Wiping all app cache folders...
:: FIX: was `rm -rf \$p/*` - the backslash makes the inner su-shell treat $p as
:: the literal string "$p" (proved via a rootless `sh -c` proxy: \$p -> RESULT=$p/x,
:: $p -> RESULT=/data/local/tmp/x), so the old command matched nothing and wiped
:: nothing. Plain $p expands to each cache dir. (Root-only path; unchanged otherwise.)
adb shell "su -c 'for p in /data/data/*/cache; do rm -rf $p/*; done'" <nul
echo Cache wipe complete. A reboot is recommended.
pause > nul
goto sdgb
:: battery
:Battery
@echo off
cls
title Battery Mode
cls
echo                                                                                            Page%g%[%w%1/2%g%]
call :logo
echo          ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
for /f "tokens=3,4,5,6,7 delims= " %%a in ('adb shell uptime ^<nul 2^>nul') do echo           [%g%+%w%]Uptime: %%a %%b %%c
set "cpucheck=N/A"
for /f "tokens=2 delims=:" %%i in ('adb shell dumpsys cpuinfo ^<nul 2^>nul ^| findstr /C:"Load:"') do set "cpucheck=%%i"
echo           [%g%+%w%]%cpucheck% LOAD
echo          ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
echo.
echo.
echo                                     %gold%[%w%1%gold%]%w% Toggle Power Saver
echo                                     %gold%[%w%2%gold%]%w% Toggle Animation
echo                                     %gold%[%w%3%gold%]%w% Wi-Fi/BT scan and related
echo                                     %gold%[%w%4%gold%]%w% Toggle Sync ^(placebo key^)
echo                                     %gold%[%w%5%gold%]%w% Samsung motion ^(OEM^)
echo                                     %gold%[%w%6%gold%]%w% ZRAM preference ^(reboot^)
echo                                     %gold%[%w%7%gold%]%w% Aggressive saver constants
echo                                     %gold%[%w%8%gold%]%w% Toggle Send Error
echo                                     %gold%[%w%9%gold%]%w% ART lock profiling ^(dev^)
echo                                     %gold%[%w%10%gold%]%w% Toggle Logs/etc
echo                                     %gold%[%w%11%gold%]%w% Next Page
echo                                     %gold%[%w%12%gold%]%w% Back

:Battery_ask
:: FIX (press-twice): re-prompt without redrawing on empty/invalid input,
:: so a phantom empty line after the probes doesn't re-run them (see :dispscaler).
:: Also rename this menu's var "set" -> "opt": it never actually collided with
:: the set command, but a variable literally named "set" is a footgun to read.
set "opt=" & set /p opt="Choose An Option >> "
if not defined opt goto Battery_ask
if "!opt!"=="1" goto saverpower
if "!opt!"=="2" goto animation
if "!opt!"=="3" goto autowifi
if "!opt!"=="4" goto sync
if "!opt!"=="5" goto motion
if "!opt!"=="6" goto zram
if "!opt!"=="7" goto extremepower
if "!opt!"=="8" goto senderror
if "!opt!"=="9" goto toggleprofilling
if "!opt!"=="10" goto togglelogs
if "!opt!"=="11" goto nextpage
if "!opt!"=="12" goto menu
:: FIX: guard against invalid input - previously fell through to :nextpage
goto Battery_ask

:nextpage
cls
title Battery Mode
echo                                                                                            Page%g%[%w%2/2%g%]
echo.
echo.
call :logo
echo                                     %gold%[%w%1%gold%]%w% Toggle Log (For User Apps)
echo                                     %gold%[%w%2%gold%]%w% Universal Toggle Logs\etc
echo                                     %gold%[%w%3%gold%]%w% Toggle Deviceidle Whitelist
echo                                     %gold%[%w%4%gold%]%w% Hibernate App
echo                                     %gold%[%w%5%gold%]%w% Refresh Rate Lock
echo                                     %gold%[%w%6%gold%]%w% Force Doze Now
echo                                     %gold%[%w%7%gold%]%w% App Hibernation (system-wide)
echo                                     %gold%[%w%8%gold%]%w% Account Sync Toggle
echo                                     %gold%[%w%9%gold%]%w% Voice Hotword Toggle
echo                                     %gold%[%w%A%gold%]%w% Wake-Lock Audit  (battery drain diagnostic)
echo                                     %gold%[%w%B%gold%]%w% Toggle Finish Activities
echo                                     %gold%[%w%C%gold%]%w% Per-app battery restrict
echo                                     %gold%[%w%0%gold%]%w% Back
echo.
echo.
set "ksd=" & set /p ksd="Choose An Option >> "
if "!ksd!"=="1" goto logappsuser
if "!ksd!"=="2" goto universallogs
if "!ksd!"=="3" goto Deviceidle
if "!ksd!"=="4" goto hibernateapp
if "!ksd!"=="5" goto refreshlock
if "!ksd!"=="6" goto forcedoze
if "!ksd!"=="7" goto apphibernation
if "!ksd!"=="8" goto syncmaster
if "!ksd!"=="9" goto hotwordtoggle
if /i "!ksd!"=="A" goto wakelockaudit
if /i "!ksd!"=="B" goto finishact
if /i "!ksd!"=="C" goto appbattery
if "!ksd!"=="0" goto Battery
:: guard against invalid input
goto nextpage
:: ===================================================================
:: Per-app battery restrict - one screen for inactive / standby / hibernation.
:: Lighter than full :hibernateapp (no appops flood / profile wipe). Reversible.
:: ===================================================================
:appbattery
cls
title Per-app battery restrict
call :logo
echo.
echo  Restrict one package without the full Hibernate App hammer.
echo  Levels use real ADB commands: set-inactive, standby-bucket,
echo  bg-restriction-level, and ^(API 34+^) app_hibernation set-state.
echo.
set "BPKG=" & set /p BPKG="Package name >> "
if not defined BPKG goto nextpage
set "BPKG=!BPKG:"=!"
:: Route through the shared :_pkg_ok rather than repeating the charset inline. It is the
:: same rule, and since :_pkg_ok went pipe-free this is also the only form that actually
:: rejects a name containing & | < > - the inline `echo(!BPKG!| findstr` used to report
:: such a name as valid AND execute the part after the metacharacter.
set "_PKGCHK=!BPKG!"
call :_pkg_ok || (
    echo  %r%Invalid package name.%w%
    timeout /t 2 /nobreak >nul
    goto appbattery
)
adb shell pm list packages <nul 2>nul | find /v "" | findstr /x /c:"package:!BPKG!" >nul
if errorlevel 1 (
    echo  %r%Package not installed:%w% !BPKG!
    timeout /t 2 /nobreak >nul
    goto appbattery
)

:appbattery_menu
cls
title Per-app battery - !BPKG!
call :logo
echo.
echo  Package: %g%!BPKG!%w%
echo  Current:
set "_inact=" & set "_bucket=" & set "_hib="
for /f "delims=" %%i in ('adb shell am get-inactive !BPKG! 2^>nul ^<nul') do set "_inact=%%i"
for /f "delims=" %%i in ('adb shell am get-standby-bucket !BPKG! 2^>nul ^<nul') do set "_bucket=%%i"
if %SDK% GEQ 34 for /f "delims=" %%i in ('adb shell cmd app_hibernation get-state !BPKG! 2^>nul ^<nul') do set "_hib=%%i"
echo    inactive        : !_inact!
echo    standby-bucket  : !_bucket!
if %SDK% GEQ 34 (echo    hibernation     : !_hib!) else (echo    hibernation     : ^(needs API 34+^))
echo.
echo    %g%[%w%1%g%]%w% Light   - inactive on, standby rare
echo    %g%[%w%2%g%]%w% Medium  - restricted bucket + bg-restriction
echo    %g%[%w%3%g%]%w% Heavy   - hibernation state ^(API 34+^) + medium
echo    %g%[%w%4%g%]%w% Unrestrict - active / unrestricted / hibernation off
echo    %g%[%w%5%g%]%w% Back
set "ab=" & set /p ab="Choose An Option >> "
if not defined ab goto appbattery_menu
if "!ab!"=="1" goto appbattery_light
if "!ab!"=="2" goto appbattery_med
if "!ab!"=="3" goto appbattery_heavy
if "!ab!"=="4" goto appbattery_clear
if "!ab!"=="5" goto nextpage
goto appbattery_menu

:appbattery_light
adb shell am set-inactive !BPKG! true <nul
adb shell am set-standby-bucket !BPKG! rare <nul
echo.
echo  Applied Light restrict.
goto appbattery_done

:appbattery_med
adb shell am set-inactive !BPKG! true <nul
adb shell am set-standby-bucket !BPKG! restricted <nul
adb shell cmd activity set-bg-restriction-level --user 0 !BPKG! restricted <nul
echo.
echo  Applied Medium restrict.
goto appbattery_done

:appbattery_heavy
if %SDK% LSS 34 (
    echo  %y%API %SDK% - heavy hibernation needs 34+. Applying Medium instead.%w%
    goto appbattery_med
)
adb shell am set-inactive !BPKG! true <nul
adb shell am set-standby-bucket !BPKG! restricted <nul
adb shell cmd activity set-bg-restriction-level --user 0 !BPKG! hibernation <nul
adb shell cmd app_hibernation set-state !BPKG! true <nul
adb shell cmd deviceidle whitelist -!BPKG! <nul >nul 2>&1
echo.
set "_hib="
for /f "delims=" %%i in ('adb shell cmd app_hibernation get-state !BPKG! 2^>nul ^<nul') do set "_hib=%%i"
if /i "!_hib!"=="true" (echo [%g%+%w%] hibernation state = true) else (echo [%y%WARN%w%] hibernation readout = "!_hib!")
goto appbattery_done

:appbattery_clear
adb shell am set-inactive !BPKG! false <nul
adb shell am set-standby-bucket !BPKG! active <nul
adb shell cmd activity set-bg-restriction-level --user 0 !BPKG! unrestricted <nul
if %SDK% GEQ 34 adb shell cmd app_hibernation set-state !BPKG! false <nul
echo.
echo  Cleared restrictions ^(reboot recommended if the app still misbehaves^).
goto appbattery_done

:appbattery_done
echo.
echo  Press any key . . .
pause >nul
goto appbattery_menu
:: ===================================================================
:: Finish Activities  (always_finish_activities - developer setting)
:: HONEST CAVEAT: documented global setting, but a well-known Android
:: quirk means setting it over ADB flips the toggle and "settings get"
:: reports the new value, yet on many builds it does NOT fully take
:: effect the way manually toggling in Developer Options does. We apply
:: it, read it back, and say so - same honesty as the device_config
:: warning. Reversible (0 = off, the Android default).
:finishact
cls
title Finish Activities
call :logo
echo.
echo  Current:
for /f "delims=" %%i in ('adb shell settings get global always_finish_activities 2^>nul ^<nul') do echo    always_finish_activities = %%i
echo.
echo  Destroys each activity as soon as you leave it. Can trim background
echo  memory, at the cost of slower app resume.
echo.
echo                                     %gold%[%w%1%gold%]%w% Turn ON  (1)
echo                                     %gold%[%w%2%gold%]%w% Turn OFF (0, default)
echo                                     %gold%[%w%0%gold%]%w% Back
echo.
set "fa=" & set /p fa="Choose An Option >> "
if "!fa!"=="1" goto finishact_on
if "!fa!"=="2" goto finishact_off
if "!fa!"=="0" goto nextpage
goto finishact

:finishact_on
adb shell settings put global always_finish_activities 1 <nul
call :_finishact_readback
goto finishact_done

:finishact_off
adb shell settings put global always_finish_activities 0 <nul
call :_finishact_readback
goto finishact_done

:_finishact_readback
set "_fav="
for /f "delims=" %%i in ('adb shell settings get global always_finish_activities 2^>nul ^<nul') do set "_fav=%%i"
echo.
echo   Device now reports: always_finish_activities = !_fav!
echo   %gold%Note:%w% over ADB this flag reliably reports on/off, but on many builds it
echo   may not fully engage the way toggling it in Developer Options does. If you
echo   need it to truly take effect, set it there. Setting it back to 0 here always
echo   restores the default.
goto :eof

:finishact_done
echo.
echo Press Any Button To Go Back
pause > nul
goto nextpage
:: ===================================================================
:: NEW: Wake-Lock Audit  (battery drain diagnostic)
:: Wake locks prevent CPU/screen sleep. A misbehaving app holding a
:: partial wake lock can drain 20-40% battery/hour. This gathers the
:: four most useful dumps into one report.
:: ===================================================================
:wakelockaudit
cls
title Wake-Lock Audit
call :logo
echo.
echo  Generating wake-lock + battery-stats report - 5 dumps, ~5-10 seconds.
echo  %y%The window cannot accept input until this finishes.%w%
echo.
:: Progress via 1>CON so it reaches the screen despite the block redirect - see :check.
:: Locale-safe, filename-safe timestamp from %date%/%time% (sanitize separators).
set "TS=%date%_%time%"
set "TS=%TS::=-%"
set "TS=%TS:/=-%"
set "TS=%TS:\=-%"
set "TS=%TS:.=-%"
set "TS=%TS:,=-%"
set "TS=%TS: =_%"
set "WLREPORT=%TEMP%\dcx_wakelocks_%TS%.txt"
(
    echo ===========================================================
    echo  DCX Wake-Lock Audit - %date% %time%
    echo ===========================================================
    echo.
    echo    [1/5] held wake locks ^(this one is the slowest^)... 1>CON
    echo [Section 1] Currently held wake locks
    echo  ^(Each entry = something keeping CPU awake right now.
    echo   PARTIAL_WAKE_LOCK is the most common battery drain.^)
    echo -----------------------------------------------------------
    adb shell "dumpsys power 2>/dev/null | grep -E 'Wake Locks:|PARTIAL_WAKE_LOCK|SCREEN_BRIGHT|FULL_WAKE_LOCK'" <nul
    echo.
    echo.
    echo    [2/5] battery stats since last charge... 1>CON
    echo [Section 2] Top wake-lock holders since last full charge
    echo  ^(Look at "Wake lock" totals - highest = biggest drainers.^)
    echo -----------------------------------------------------------
    adb shell "dumpsys batterystats --charged 2>/dev/null | head -200" <nul
    echo.
    echo.
    echo    [3/5] doze state... 1>CON
    echo [Section 3] Doze ^(deep sleep^) state
    echo  ^(mState=IDLE means doze is active. ACTIVE = apps can run.^)
    echo -----------------------------------------------------------
    adb shell "dumpsys deviceidle 2>/dev/null | grep -E 'mState=|mLightState=|mActiveIdleOpCount|mScreenOn|mCharging'" <nul
    echo.
    echo.
    echo    [4/5] alarms and wakeups... 1>CON
    echo [Section 4] Top alarms ^(background wakeups^)
    echo -----------------------------------------------------------
    adb shell "dumpsys alarm 2>/dev/null | grep -E 'Top Alarms|wakeups in last|act=' | head -50" <nul
    echo.
    echo.
    echo    [5/5] CPU consumers... 1>CON
    echo [Section 5] Process CPU consumers ^(last sample^)
    echo -----------------------------------------------------------
    adb shell "dumpsys cpuinfo 2>/dev/null | head -25" <nul
    echo.
    echo ===========================================================
    echo  Quick interpretation:
    echo    - PARTIAL_WAKE_LOCK in Section 1 = active drainers
    echo    - In Section 2, an app with ^>1h "Wake lock" since charge
    echo      is the prime suspect
    echo    - High wakeup count in Section 4 = app pinging too often
    echo    - If mState ^^!= IDLE while screen is off, doze is blocked
    echo ===========================================================
) > "%WLREPORT%" < nul
:: FIX (report hygiene): generate once above; :wakelockaudit_menu re-shows the
:: menu so notepad / paginate / summary / invalid input don't re-run the ~10s
:: report and write another timestamped temp file each time.
:wakelockaudit_menu
cls
call :logo
echo  %g%Report saved to:%w%
echo    %WLREPORT%
echo.
echo  %b%[%w%1%b%]%w% Open in Notepad (searchable)
echo  %b%[%w%2%b%]%w% Show paginated (MORE)
echo  %b%[%w%3%b%]%w% Show summary only
echo  %b%[%w%4%b%]%w% Back                     %d%(0 or Q also work)%w%
echo.
echo  %d%Feeling stuck? %g%0%d% or %g%Q%d% leaves this screen. Inside the paginated view
echo  it is %g%Q%d% ^(that is Windows' MORE pager, it only takes its own keys^).%w%

:wakelockaudit_menu_ask
:: Same fix as :check_menu_ask - tight re-ask so the phantom empty line after the dumps
:: cannot look like an ignored keypress, cls on redraw so misses do not stack menus.
set "wl=" & set /p wl="Choose An Option >> "
if not defined wl goto wakelockaudit_menu_ask
if "!wl!"=="0" goto nextpage
if /i "!wl!"=="q" goto nextpage
if "!wl!"=="1" (
    start "" notepad "%WLREPORT%"
    goto wakelockaudit_menu
)
if "!wl!"=="2" (
    cls
    title Wake-Lock Audit  -  SPACE=next page   ENTER=one line   Q=quit back to menu
    echo  %d%[i]%w% Paging with MORE:  %g%SPACE%w% next page   %g%ENTER%w% one line   %g%Q%w% quit back to the menu.
    echo.
    more "%WLREPORT%"
    echo.
    echo Press Any Button To Go Back
    pause > nul
    goto wakelockaudit_menu
)
if not "!wl!"=="3" goto _skwl3
    cls
    echo Currently held wake locks:
    echo.
    :: FIX: these two lines carried the ^< ^> ^| escaping that only belongs INSIDE a
    :: for /f ('...') clause. Out here the carets make the operators LITERAL, so the
    :: whole string was handed to adb as arguments and forwarded to the ANDROID shell -
    :: which has no `findstr` and no `nul` device, so the summary printed shell errors
    :: instead of wake locks. Filter on the device with grep, exactly as Sections 1 and 3
    :: of the report above already do; <nul stays on the Windows side (press-twice guard).
    adb shell "dumpsys power 2>/dev/null | grep -E 'PARTIAL_WAKE_LOCK'" <nul
    echo.
    echo Doze state:
    adb shell "dumpsys deviceidle 2>/dev/null | grep -E 'mState=|mScreenOn'" <nul
    echo.
    echo Full report at: %WLREPORT%
    echo.
    pause > nul
    goto wakelockaudit_menu

:_skwl3
if "!wl!"=="4" goto nextpage
:: nothing was printed on this path, so the menu is still on screen - re-ask in place
:: rather than redrawing it under itself.
goto wakelockaudit_menu_ask
:: ===================================================================
:: NEW: Refresh Rate Lock  (from Extra_Boost.bat / Power_Saving.bat)
:: Uses REAL Settings.System keys that Android honours:
::   min_refresh_rate  - lower bound (also gates "smooth" mode)
::   peak_refresh_rate - upper bound for default mode
:: Lock to 60 -> better battery. Lock to 90/120 -> always smooth.
:: Setting both to the SAME value forces that exact rate.
:: ===================================================================
:refreshlock
cls
title Refresh Rate Lock
call :logo
echo.
echo  Current:
for /f "delims=" %%i in ('adb shell settings get system min_refresh_rate 2^>nul ^<nul')   do echo    min_refresh_rate  = %%i Hz
for /f "delims=" %%i in ('adb shell settings get system peak_refresh_rate 2^>nul ^<nul')  do echo    peak_refresh_rate = %%i Hz
echo.
echo                                     %g%[%w%1%g%]%w% Lock to 60 Hz   (battery)
echo                                     %g%[%w%2%g%]%w% Lock to 90 Hz
echo                                     %g%[%w%3%g%]%w% Lock to 120 Hz  (smooth)
echo                                     %g%[%w%4%g%]%w% Adaptive (1 to 120 Hz)
echo                                     %g%[%w%5%g%]%w% Restore defaults
echo                                     %g%[%w%6%g%]%w% Back
set "rl=" & set /p rl="Choose An Option >> "
if "!rl!"=="1" (
    adb shell settings put system min_refresh_rate 60 <nul
    adb shell settings put system peak_refresh_rate 60 <nul
    call :_act_reset
    call :_settings_verify system min_refresh_rate 60
    call :_settings_verify system peak_refresh_rate 60
    call :_act_summary
    pause > nul
    goto refreshlock
)
if "!rl!"=="2" (
    adb shell settings put system min_refresh_rate 90 <nul
    adb shell settings put system peak_refresh_rate 90 <nul
    call :_act_reset
    call :_settings_verify system min_refresh_rate 90
    call :_settings_verify system peak_refresh_rate 90
    call :_act_summary
    echo ^(Falls back if your panel doesn't support 90.^)
    pause > nul
    goto refreshlock
)
if "!rl!"=="3" (
    adb shell settings put system min_refresh_rate 120 <nul
    adb shell settings put system peak_refresh_rate 120 <nul
    call :_act_reset
    call :_settings_verify system min_refresh_rate 120
    call :_settings_verify system peak_refresh_rate 120
    call :_act_summary
    echo ^(Falls back if your panel doesn't support 120.^)
    pause > nul
    goto refreshlock
)
if "!rl!"=="4" (
    adb shell settings put system min_refresh_rate 1 <nul
    adb shell settings put system peak_refresh_rate 120 <nul
    call :_act_reset
    call :_settings_verify system min_refresh_rate 1
    call :_settings_verify system peak_refresh_rate 120
    call :_act_summary
    pause > nul
    goto refreshlock
)
if not "!rl!"=="5" goto _skrl5
    adb shell settings delete system min_refresh_rate <nul
    adb shell settings delete system peak_refresh_rate <nul
    call :_act_reset
    call :_settings_verify system min_refresh_rate DELETE
    call :_settings_verify system peak_refresh_rate DELETE
    call :_act_summary
    pause > nul
    goto refreshlock

:_skrl5
if "!rl!"=="6" goto nextpage
goto refreshlock
:: ===================================================================
:: NEW: Force Doze Now  (from Power_Saving.bat)
:: `dumpsys deviceidle force-idle` immediately puts the device into
:: deep idle (doze) - useful right before locking the phone and
:: putting it down. Wakes up normally on user interaction.
:: ===================================================================
:forcedoze
cls
title Force Doze Now
call :logo
echo.
echo  Immediately forces the device into deep idle (doze) mode.
echo  Forcing also marks the battery "unplugged" - doze cannot hold while charging,
echo  and the adb cable counts as charging. Option 2 undoes both.
echo  Wakes up normally when you unlock or receive a high-priority push.
echo.
echo                                     %g%[%w%1%g%]%w% Force doze now
echo                                     %g%[%w%2%g%]%w% Unforce (restore scheduling + real battery state)
echo                                     %g%[%w%3%g%]%w% Show current state
echo                                     %g%[%w%4%g%]%w% Back
set "fd=" & set /p fd="Choose An Option >> "
if not "!fd!"=="1" goto _skfd1
    :: FIX (audit: doze sequence incomplete): the canonical Android sequence is a PAIR -
    :: "dumpsys battery unplug" and only then "deviceidle force-idle". Doze cannot hold
    :: while the device believes it is charging, and the adb cable itself counts as
    :: charging - so force-idle alone can refuse to enter or exit immediately, which
    :: reads as "nothing happened". The unplug is a software spoof only; option 2 pairs
    :: "unforce" with "battery reset" to restore the real state. Every call drains its
    :: stdin with <nul (the fstrim press-once guard). Do not split either pair.
    set "_dvst="
    for /f "delims=" %%d in ('adb get-state 2^>nul') do set "_dvst=%%d"
    if /i not "%_dvst%"=="device" (
        echo  %r%No device connected - nothing was sent.%w%  Check: adb devices
        pause > nul
        goto forcedoze
    )
    adb shell dumpsys battery unplug <nul
    adb shell dumpsys deviceidle force-idle <nul
    echo Doze forced. The device now reports "unplugged" so idle can hold with the
    echo cable in. Use option 2 when done - until then the battery UI shows the
    echo spoofed state.
    pause > nul
    goto forcedoze

:_skfd1
if not "!fd!"=="2" goto _skfd2
    :: undo BOTH halves: leave forced idle, then restore the real battery/charging state.
    set "_dvst="
    for /f "delims=" %%d in ('adb get-state 2^>nul') do set "_dvst=%%d"
    if /i not "%_dvst%"=="device" (
        echo  %r%No device connected - nothing was sent.%w%  Check: adb devices
        pause > nul
        goto forcedoze
    )
    adb shell dumpsys deviceidle unforce <nul
    adb shell dumpsys battery reset <nul
    echo Returned to normal scheduling and restored the real battery state.
    pause > nul
    goto forcedoze

:_skfd2
if "!fd!"=="3" (
    cls
    for /f "delims=" %%i in ('adb shell dumpsys deviceidle ^<nul ^| findstr /C:"mState=" /C:"mLightState="') do echo   %%i
    echo.
    pause > nul
    goto forcedoze
)
if "!fd!"=="4" goto nextpage
goto forcedoze
:: ===================================================================
:: NEW: App Hibernation toggle (Android 12+, from Power_Saving.bat)
:: Hibernates unused apps - revokes runtime permissions, removes
:: optimised code, clears cache. App keeps installed but uses ~0
:: resources until launched again.
:: ===================================================================
:apphibernation
cls
title App Hibernation
call :logo
echo.
echo  Android 12+ feature. When ON, the system hibernates apps the
echo  user hasn't opened in a long time (revokes permissions, removes
echo  optimised code). Saves storage + RAM on devices with many
echo  rarely-used apps.
echo.
if "%SDK%"=="" goto _aph_show
if %SDK% LSS 31 (
    echo  %r%Warning:%w% your device is API %SDK% - app hibernation needs API 31+.
)

:_aph_show
call :_dcfg_warn
echo.
echo  Current:
for /f "delims=" %%i in ('adb shell device_config get app_hibernation app_hibernation_enabled 2^>nul ^<nul') do echo    app_hibernation_enabled = %%i
echo.
echo                                     %g%[%w%1%g%]%w% Enable
echo                                     %g%[%w%2%g%]%w% Disable
echo                                     %g%[%w%3%g%]%w% Back
set "ah=" & set /p ah="Choose An Option >> "
if "!ah!"=="1" (
    adb shell device_config put app_hibernation app_hibernation_enabled true <nul
    call :_act_reset
    call :_dcfg_verify app_hibernation app_hibernation_enabled true
    call :_act_summary
    pause > nul
    goto apphibernation
)
if "!ah!"=="2" (
    adb shell device_config put app_hibernation app_hibernation_enabled false <nul
    call :_act_reset
    call :_dcfg_verify app_hibernation app_hibernation_enabled false
    call :_act_summary
    pause > nul
    goto apphibernation
)
if "!ah!"=="3" goto nextpage
goto apphibernation
:: ===================================================================
:: NEW: Account Sync toggle (from Balanced.bat)
:: Writes master_sync_status only. On modern Android nothing reads that key -
:: real Auto sync lives in SyncManager and is not rootless-writable. Kept so
:: Backup/Restore can round-trip the value. See README "placebo".
:: ===================================================================
:syncmaster
cls
title Account Sync Toggle
call :logo
echo.
echo  Writes global master_sync_status only.
echo  %y%Placebo on modern Android:%w% nothing reads this key. Real Auto sync
echo  lives in the sync framework ^(dumpsys content^) and needs root to change.
echo  Kept so Backup/Restore can round-trip the stored value.
echo.
echo  Current:
for /f "delims=" %%i in ('adb shell settings get global master_sync_status 2^>nul ^<nul') do echo    master_sync_status = %%i  (1=on, 0=off)
echo.
echo                                     %g%[%w%1%g%]%w% Set master_sync_status = 1
echo                                     %g%[%w%2%g%]%w% Set master_sync_status = 0
echo                                     %g%[%w%3%g%]%w% Back
set "sm=" & set /p sm="Choose An Option >> "
if "!sm!"=="1" (
    adb shell settings put global master_sync_status 1 <nul
    echo Value set to 1. Real Auto sync is unchanged on modern Android.
    pause > nul
    goto syncmaster
)
if "!sm!"=="2" (
    adb shell settings put global master_sync_status 0 <nul
    echo Value set to 0. Real Auto sync is unchanged on modern Android.
    pause > nul
    goto syncmaster
)
if "!sm!"=="3" goto nextpage
goto syncmaster
:: ===================================================================
:: NEW: Voice Hotword toggle (from Balanced.bat)
:: Disables passive voice listening ("Hey Google" / "Alexa" / "Bixby").
:: Real Settings.Global key. Saves battery because the always-on mic
:: pipeline stays parked. You can still launch the assistant manually.
:: ===================================================================
:hotwordtoggle
cls
title Voice Hotword Toggle
call :logo
echo.
echo  Disables the always-on "Hey Google" / hotword pipeline.
echo  You can still tap the assistant icon to use voice input.
echo  Real battery save on devices with continuous mic listening.
echo.
echo  Current:
for /f "delims=" %%i in ('adb shell settings get global hotword_detection_enabled 2^>nul ^<nul') do echo    hotword_detection_enabled = %%i  (1=on, 0=off)
echo.
echo                                     %g%[%w%1%g%]%w% Enable hotword
echo                                     %g%[%w%2%g%]%w% Disable hotword
echo                                     %g%[%w%3%g%]%w% Back
set "hw=" & set /p hw="Choose An Option >> "
if "!hw!"=="1" (
    adb shell settings put global hotword_detection_enabled 1 <nul
    call :_act_reset
    call :_settings_verify global hotword_detection_enabled 1
    call :_act_summary
    pause > nul
    goto hotwordtoggle
)
if "!hw!"=="2" (
    adb shell settings put global hotword_detection_enabled 0 <nul
    call :_act_reset
    call :_settings_verify global hotword_detection_enabled 0
    call :_act_summary
    pause > nul
    goto hotwordtoggle
)
if "!hw!"=="3" goto nextpage
goto hotwordtoggle

:hibernateapp
if "%SDK%"=="" (
    cls
    call :logo
    echo [%r%^^!%w%] Could not detect API level. Cannot safely continue.
    echo Press Any Button To Go Back
    pause > nul
    goto nextpage
)
if %SDK% LSS 34 (
    cls
    call :logo
    echo [%r%^^!%w%] Your API Level Is %SDK% , Some Adb Commands Won't Work.
    echo Press Any Button To Go Back
    pause > nul
    goto nextpage
)
goto nexthibernateappphase

:nexthibernateappphase
cls
call :logo
title Set App To Hibernate
echo.
echo                                     %gold%[%w%1%gold%]%w% Set App To Hibernate
echo                                     %gold%[%w%2%gold%]%w% Set App To Stock
echo                                     %gold%[%w%3%gold%]%w% Back
echo.
echo.
set "ksd=" & set /p ksd="Choose An Option >> "
if "!ksd!"=="1" goto sethibdernatephs
if "!ksd!"=="2" goto stockpackage
if "!ksd!"=="3" goto nextpage
:: FIX: guard against invalid input - previously fell through to :stockpackage
goto nexthibernateappphase

:stockpackage
cls
title Revert Your Package To Stock
call :logo
set "pkgv2=" & set /p pkgv2="Put Your Package Name Here >> "
if "!pkgv2!"=="" goto nexthibernateappphase
set "_PKGCHK=!pkgv2!"
call :_pkg_ok || (
    echo  [%r%x%w%] Invalid package name. Letters, digits, dots and underscores only.
    timeout /t 2 /nobreak > nul
    goto nexthibernateappphase
)
echo.
echo [#] Set !pkgv2! To Stock . . . .
echo.
adb shell cmd appops reset !pkgv2! <nul
adb shell cmd activity set-bg-restriction-level --user 0 !pkgv2! unrestricted <nul
adb shell cmd activity set-inactive !pkgv2! false <nul
adb shell cmd activity set-standby-bucket !pkgv2! active <nul
adb shell cmd app_hibernation set-state !pkgv2! false <nul
adb shell cmd dropbox remove-low-priority !pkgv2! <nul
adb shell cmd tare set-vip 0 !pkgv2! true <nul
echo.
set "_hib="
for /f "delims=" %%i in ('adb shell cmd app_hibernation get-state !pkgv2! 2^>nul ^<nul') do set "_hib=%%i"
if /i "!_hib!"=="false" (
    echo [%g%+%w%] !pkgv2! hibernation state = false
) else if /i "!_hib!"=="true" (
    echo [%y%WARN%w%] !pkgv2! still reports hibernated - reboot may be required.
) else (
    echo [#] !pkgv2! marked stock; hibernation readout was "!_hib!"
)
echo [#] Reboot recommended to finish the process.
echo.
echo Press Any Button To Go Back
pause > nul
goto nextpage

:sethibdernatephs
cls
title Set Your Package Here
call :logo
set "pkgv2=" & set /p pkgv2="Put Your Package Name Here >> "
if "!pkgv2!"=="" (
    echo invalid package. . . .
    timeout /t 2 /nobreak > nul
    goto nexthibernateappphase
)
set "_PKGCHK=!pkgv2!"
call :_pkg_ok || (
    echo  [%r%x%w%] Invalid package name. Letters, digits, dots and underscores only.
    timeout /t 2 /nobreak > nul
    goto nexthibernateappphase
)
echo.
echo [#] Set !pkgv2! To Hibernate . . . .
echo.
for %%b in (
    FOREGROUND_SERVICE_SPECIAL_USE
    INSTANT_APP_START_FOREGROUND
    RUN_ANY_IN_BACKGROUND
    RUN_IN_BACKGROUND
    START_FOREGROUND
    WAKE_LOCK
) do (
    rem !pkgv2! (delayed): this is the only !pkgv2! sitting INSIDE a ( ) block (the
    rem for %%b ... do (...) loop). pkgv2 is typed by the user; a ")" in it would close
    rem the do-block early at parse time and break the script. Delayed expansion keeps
    rem the block structure intact. The bare !pkgv2! statements outside any block
    rem (below) are not a cmd-parse risk.
    rem NB: rem, not "::" - a "::" inside ( ) makes cmd print "The system cannot find
    rem the drive specified." once per line, every time this loop runs.
    adb shell cmd appops set !pkgv2! %%b ignore <nul > nul 2>&1
)
adb shell cmd activity service-restart-backoff disable !pkgv2! <nul
adb shell cmd activity set-bg-restriction-level --user 0 !pkgv2! hibernation <nul
adb shell cmd activity set-foreground-service-delegate --user 0 !pkgv2! stop <nul
adb shell cmd activity set-inactive !pkgv2! true <nul
adb shell cmd activity set-standby-bucket !pkgv2! restricted <nul
adb shell cmd app_hibernation set-state !pkgv2! true <nul
adb shell cmd deviceidle sys-whitelist -!pkgv2! <nul
adb shell cmd deviceidle whitelist -!pkgv2! <nul
adb shell cmd dropbox add-low-priority !pkgv2! <nul
adb shell cmd package art clear-app-profiles !pkgv2! <nul
adb shell cmd package log-visibility --disable !pkgv2! <nul
adb shell cmd shortcut clear-shortcuts !pkgv2! <nul
adb shell cmd tare set-vip 0 !pkgv2! false <nul
adb shell cmd usagestats clear-last-used-timestamps !pkgv2! <nul
adb shell am force-stop !pkgv2! <nul
adb shell am kill !pkgv2! <nul
adb shell am stop-app !pkgv2! <nul
adb shell cmd activity force-stop !pkgv2! <nul
adb shell cmd activity kill !pkgv2! <nul
echo.
set "_hib="
for /f "delims=" %%i in ('adb shell cmd app_hibernation get-state !pkgv2! 2^>nul ^<nul') do set "_hib=%%i"
if /i "!_hib!"=="true" (
    echo [%g%+%w%] !pkgv2! hibernation state = true
) else if /i "!_hib!"=="false" (
    echo [%y%WARN%w%] !pkgv2! hibernation state still false - commands may be ignored on this OEM.
) else (
    echo [%y%WARN%w%] Could not read hibernation state ^(got "!_hib!"^) - applied best-effort.
)
echo.
echo Press Any Button To Go Back
pause > nul
goto nextpage

:Deviceidle
title Toggle Deviceidle Whitelist
cls
call :logo
echo.
echo.
echo                                     [%d%1%w%] Remove System App From Whitelist
echo                                     [%d%2%w%] Revert
echo                                     [%d%3%w%] Back
set "ksd=" & set /p ksd="Choose An Option >> "
if "!ksd!"=="1" goto devicesysdel
if "!ksd!"=="2" goto devicesysrev
if "!ksd!"=="3" goto nextpage
:: FIX: guard against invalid input - previously fell through to :devicesysdel
goto Deviceidle

:devicesysdel
cls
call :logo
title Toggle Deviceidle Whitelist : Remove System App From Whitelist
echo.
echo  %r%======================== WARNING ========================%w%
echo.
echo  Removing system apps from the Doze (deviceidle) whitelist
echo  can break:
echo    - Alarms and timers (Clock, Calendar reminders)
echo    - Push notifications across the OS
echo    - Background sync, find-my-device, system updates
echo    - Foreground services some OEM apps rely on
echo.
echo  You can always recover with option [2] Revert.
echo.
echo  %r%=========================================================%w%
echo.
echo  [%g%Y%w%] Continue
echo  [%g%N%w%] Cancel
choice /c:YN /n > nul
if errorlevel 2 goto Deviceidle
cls
call :logo
title Removing system apps from Doze whitelist...
:: FIX: previous protected list was just "gms shell ims downloads" -
:: too narrow. Expanded to cover more critical components.
:: FIX (temp hygiene): write to %TEMP%, not temp.txt in the CURRENT directory -
:: DCX may be launched from a read-only or shared location. Read it back with
:: `type` so the quoted %TEMP% path is honored (for /f in ("path") would treat a
:: quoted path as a literal string, not a filename).
:: FIX (parser): the old Windows-side filter `findstr /R "...,[0-9]*$"` had
:: two ways to match NOTHING and finish "Done" without removing anything:
:: (1) findstr's $ anchor only matches right before a CR, and adb output
:: piped on Windows can arrive LF-only; (2) builds whose dump prints bare
:: package names without the ",uid" suffix never matched at all. Filter on
:: the DEVICE instead, where line endings and tools are deterministic:
:: grep keeps real package lines (with or without ",uid"), sed strips the
:: uid. toybox grep/sed ship on every Android 6+ build DCX targets; if one
:: is somehow missing the file comes back empty and the loop is a no-op -
:: the same fail-safe as before, never a wrong removal.
adb shell "dumpsys deviceidle sys-whitelist | grep -E '^[[:blank:]]*[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+(,[0-9]+)?[[:blank:]]*$' | sed 's/[[:blank:]]//g; s/,.*//'" > "%TEMP%\dcx_idle_whitelist.txt" <nul
set "_rm=0" & set "_prot=0"
for /f "delims=" %%A in ('type "%TEMP%\dcx_idle_whitelist.txt"') do (
    echo %%A | findstr /I "gms gsf shell ims downloads providers settings systemui inputmethod telecom telephony bluetooth dialer mms phone alarm calendar fused" > nul
    if errorlevel 1 (
        adb shell cmd deviceidle sys-whitelist -%%A <nul
        echo Removed: %%A
        set /a _rm+=1
    ) else (
        echo [%r%#%w%] %%A Is Protected
        set /a _prot+=1
    )
)
del "%TEMP%\dcx_idle_whitelist.txt" > nul 2>&1
echo.
if "!_rm!"=="0" (
    echo [%y%WARN%w%] Removed 0 packages ^(list empty, all protected, or filter matched nothing^).
) else (
    echo [%g%+%w%] Removed !_rm! package^(s^), protected !_prot!.
)
echo Done, Press Any Button To Go Back
pause > nul
goto nextpage

:devicesysrev
title Toggle Deviceidle Whitelist : Revert
cls
call :logo
echo.
echo.
echo                           [%y%=%w%]All System Apps Is Revert Back To Deviceidle
adb shell cmd deviceidle sys-whitelist reset <nul
echo Press Any Button To Go Back
pause > nul
goto nextpage

:universallogs
cls
title Universal Toggle Logs\etc
echo.
echo.
call :logo
echo.
echo.
echo                                     [%d%1%w%] Off
echo                                     [%d%2%w%] On
echo                                     [%d%3%w%] Back
set "ksd=" & set /p ksd="Choose An Option >> "
if "!ksd!"=="1" goto offlogsuni
if "!ksd!"=="2" goto onlogsuni
if "!ksd!"=="3" goto nextpage
:: FIX: guard against invalid input - previously fell through to :offlogsuni
goto universallogs

:offlogsuni
cls
title Universal Toggle Logs\etc : Off
call :logo
for /f "tokens=1 delims=:" %%a in ('adb shell getprop ^<nul ^| findstr "log.tag"') do (
    set "prop=%%a"
    set "prop=!prop: =!"
    set "prop=!prop:[=!"
    set "prop=!prop:]=!"
    adb shell setprop !prop! S <nul
)
echo Press Any Button To Go Back
pause > nul
goto nextpage

:onlogsuni
cls
title Universal toggle Logs\etc : On
call :logo
echo  Clearing log.tag* props set by Off ^(empty = platform default^)...
for /f "tokens=1 delims=:" %%a in ('adb shell getprop ^<nul ^| findstr "log.tag"') do (
    set "prop=%%a"
    set "prop=!prop: =!"
    set "prop=!prop:[=!"
    set "prop=!prop:]=!"
    adb shell setprop !prop! '' <nul >nul 2>&1
)
echo.
echo  Cleared. A reboot finishes restoring default log levels.
echo                       [%r%^^!%w%] Please Restart Device To Finish The Process
echo.
echo Press Any Button To Go Back
pause > nul
goto nextpage

:logappsuser
cls
title Toggle Log For User Apps
echo.
echo.
call :logo
echo.
echo.
echo                                     [%d%1%w%] Off
echo                                     [%d%2%w%] On
echo                                     [%d%3%w%] Back
set "ksd=" & set /p ksd="Choose An Option >> "
if "!ksd!"=="1" goto offlogsuserapp
if "!ksd!"=="2" goto onlogsuserapp
if "!ksd!"=="3" goto nextpage
:: FIX: guard against invalid input - previously fell through to :offlogsuserapp
goto logappsuser

:offlogsuserapp
cls
title Log For User Apps : Off
call :logo
:: Same in-device loop as :lstused - see the note there before changing the shape of
:: this line (why it is not one adb call per package, why not one long ";" string, and
:: why the redirects are "2>/dev/null" rather than "2>&1").
for /f "delims=" %%a in ('adb shell "pm list packages | while read p; do p=${p#package:}; cmd package log-visibility --disable $p >/dev/null 2>/dev/null; echo $p; done" ^<nul') do (
echo Log disabled : %%a
)
echo.
echo.
echo Done , Press Any Button To Go Back
pause > nul
goto nextpage

:onlogsuserapp
cls
title Log For User Apps : On
call :logo
:: Same in-device loop as :lstused - see the note there before changing the shape of
:: this line (why it is not one adb call per package, why not one long ";" string, and
:: why the redirects are "2>/dev/null" rather than "2>&1").
for /f "delims=" %%a in ('adb shell "pm list packages | while read p; do p=${p#package:}; cmd package log-visibility --enable $p >/dev/null 2>/dev/null; echo $p; done" ^<nul') do (
echo Log enabled : %%a
)
echo.
echo.
echo Done , Press Any Button To Go Back
pause > nul
goto nextpage

:togglelogs
cls
title Toggle Logs/etc
echo.
echo.
echo Toggle Your Logs/etc Here
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offlogss
if "!toggle!"=="2" goto onlogss
if "!toggle!"=="3" goto Battery
:: guard against invalid input
goto togglelogs

:offlogss
cls
title Logs/etc : Off
cls
echo.
echo.
echo Do You Want To Use Custom Debug.prop From Tecno Pova 6 Neo?
echo.
echo.
echo [1] Skip And Continue
echo [2] Yes
echo [3] Back
set "conx=" & set /p conx="Choose An Option >> "
if "!conx!"=="1" goto skiplogv
if "!conx!"=="2" goto mainlogv
if "!conx!"=="3" goto Battery
:: FIX: guard against invalid input - previously fell through to :mainlogv
goto offlogss

:mainlogv
cls
::debugprop from tecno pova 6 neo
adb shell setprop debug.ae.dump.enable false <nul
adb shell setprop debug.ae.dump.stat 0 <nul
adb shell setprop debug.ae.dump_level 0 <nul
adb shell setprop debug.ae.log.enable false <nul
adb shell setprop debug.ae.log.level 0 <nul
adb shell setprop debug.ae.logi.enable false <nul
adb shell setprop debug.af.log.enable false <nul
adb shell setprop debug.bq.dump false <nul
adb shell setprop debug.camera.dump false <nul
adb shell setprop debug.stagefright.mediacodec.trace 0 <nul
adb shell setprop debug.sf.log_transaction false <nul
adb shell setprop debug.sf.stats false <nul
adb shell setprop debug.mtkcam.systrace.level 0 <nul
adb shell setprop debug.dump.enable false <nul
adb shell setprop debug.dump 0 <nul
adb shell setprop debug.camera.log 0 <nul
adb shell setprop debug.ae.stat.log.level 0 <nul
adb shell setprop debug.ae.stat.perf.enable false <nul
adb shell setprop debug.af.systrace 0 <nul
adb shell setprop debug.awb.systrace.db.enable false <nul
adb shell setprop debug.flicker.systrace false <nul
adb shell setprop debug.flicker.log 0 <nul
adb shell setprop debug.pdsystrace 0 <nul
adb shell setprop debug.syncawbsystrace.enable false <nul
adb shell setprop debug.trace.print.video false <nul
adb shell setprop debug.trace.print.audio false <nul
adb shell setprop debug.trace.info false <nul
adb shell setprop debug.gpu.dump.texture false <nul
adb shell setprop debug.sf.cpupolicy.log false <nul
adb shell setprop debug.hwc.wdt_trace false <nul
adb shell setprop debug.apusys.loglevel 0 <nul
adb shell setprop debug.awb.latency.log.level 0 <nul
adb shell setprop debug.awb_alg.log.level 0 <nul
adb shell setprop debug.edma.loglevel 0 <nul
adb shell setprop debug.ae.pline.table.log 0 <nul
adb shell setprop debug.ae_alg.log.level 0 <nul
adb shell setprop debug.atms.dump false <nul
adb shell setprop debug.eis.dumpdisplay false <nul
adb shell setprop debug.featureProfile.dump false <nul
adb shell setprop debug.flk_dump 0 <nul
adb shell setprop debug.fpipe.force.dump 0 <nul
adb shell setprop debug.hwc.dump_buf_log_enable false <nul
adb shell setprop debug.ai3a_log.enable false <nul
adb shell setprop debug.aiawb.ga.log.enable false <nul
adb shell setprop debug.alsflk.log 0 <nul
adb shell setprop debug.awb.p1ggm.log.enable false <nul
adb shell setprop debug.awb.sa.log.enable false <nul
adb shell setprop debug.mediatek.vklayer.dump_analysis_enabled false <nul
adb shell setprop debug.mediatek.vklayer.dump_blas_info_enabled false <nul
adb shell setprop debug.mediatek.vklayer.dump_debug_enabled false <nul
adb shell setprop debug.mediatek.vklayer.dump_debug_mem_at_QSubmit false <nul
adb shell setprop debug.mediatek.vklayer.dump_debug_mem_enabled false <nul
adb shell setprop debug.loglevel 0 <nul
adb shell setprop debug.log.enable false <nul
adb shell setprop debug.thread_raw.log false <nul
adb shell setprop debug.apusyslog false <nul
adb shell setprop debug.neuropilot.gpu.systrace false <nul
adb shell setprop debug.neuron.runtime.ProfilingLevel 0 <nul
adb shell setprop debug.neuron.runtime.EnableDebugger false <nul
adb shell setprop debug.hwc.aibld_dump_enable false <nul
adb shell setprop debug.tkflow.bokeh.log 0 <nul
adb shell setprop debug.tone.log.enable false <nul
adb shell setprop debug.vpustream.loglevel 0 <nul
adb shell setprop debug.smvrb.loglevel 0 <nul
adb shell setprop debug.pipeline.trace 0 <nul
adb shell setprop debug.mtk_tflite.vlog 0 <nul
adb shell setprop debug.sensors.color.log 0 <nul
adb shell setprop debug.P1STT.log 0 <nul
adb shell setprop debug.af_alg.log.level 0 <nul
adb shell setprop debug.awb.sa.log.level 0 <nul
adb shell setprop debug.gpud.gl.state.error.dump 0 <nul
adb shell setprop debug.gpud.log 0 <nul
adb shell setprop debug.3alog.enable false <nul
adb shell setprop debug.STEREO.Log 0 <nul
adb shell setprop debug.STEREO.dump 0 <nul
adb shell setprop debug.ThreadPool.log 0 <nul
adb shell setprop debug.edma.loglevel 0 <nul
adb shell setprop debug.sync3A.log 0 <nul
adb shell setprop debug.camera.3dnr.log.level 0 <nul
adb shell setprop debug.sync3AWrapper.log 0 <nul
adb shell setprop debug.sf.wdlog 0 <nul
adb shell setprop debug.sf.display_dejitter_log 0 <nul
adb shell setprop debug.sensors.flicker.log 0 <nul
adb shell setprop debug.tpi.s.log 0 <nul
adb shell setprop debug.pip.logLevel 0 <nul
adb shell setprop debug.EntryPool.log 0 <nul
adb shell setprop debug.log.rpt 0 <nul
adb shell setprop debug.ltm.smth.log.enable false <nul
adb shell setprop debug.fsc.log_level 0 <nul
adb shell setprop debug.gpunn.enable_profiler false <nul
adb shell setprop debug.hal3av3.log 0 <nul
adb shell setprop debug.pq.enable.trace false <nul
adb shell setprop debug.pd.dump.enable false <nul
adb shell setprop debug.p2f.dump.enable false <nul
adb shell setprop debug.neuron.runtime.DumpVerbose 0 <nul
adb shell setprop debug.vendor.sys.camfilelock.log 0 <nul
adb shell setprop debug.smvr.log.level 0 <nul
adb shell setprop debug.statistic_buf.enable false <nul
adb shell setprop debug.sync3AMgr.log false <nul
adb shell setprop debug.tpi.s.async.log false <nul
adb shell setprop debug.tpi.s.dump false <nul
adb shell setprop debug.tsfcore.filedump.enable false <nul
adb shell setprop debug.gpud.wsframebuffer.log 0 <nul
adb shell setprop debug.hmplog 0 <nul
adb shell setprop debug.hwui.memory_dump_disable 1 <nul
adb shell setprop debug.trace.p2.Cropper 0 <nul
adb shell setprop debug.trace.p2.CaptureNode 0 <nul
adb shell setprop debug.trace.p2.LMVInfo 0 <nul
adb shell setprop debug.trace.p2.Streaming_VSDOF 0 <nul
adb shell setprop debug.systrace.p2 0 <nul
adb shell setprop debug.sf.show_msync2_trace false <nul
::debugprop from tecno pova 6 neo
:skiplogv
cls
call :_dcfg_warn
::if something is wrong , revert this prop by reboot
:: NEW: universal log silencer (real, persistent across reboots).
:: This is what `persist.log.tag "*:S"` from the user's .sh actually
:: does - silences ALL logcat tags at the "Silent" level. The
:: existing per-tag setprops below remain as a belt-and-braces.
adb shell setprop persist.log.tag '*:S' <nul > nul 2>&1
adb shell setprop log.tag '*:S' <nul > nul 2>&1
adb shell setprop debug.vendor.gpu.record_sbwc false <nul
adb shell setprop debug.egl.blobcache.multifile false <nul
adb shell setprop debug.tracefpunwindoff 1 <nul
adb shell setprop log.tag.LAUNCHER_TRACE S <nul > nul 2>&1
adb shell device_config put systemui com.android.systemui.coroutine_tracing false <nul
adb shell setprop persist.log.tag.DisplayPowerController S <nul > nul 2>&1
adb shell setprop debug.met_log_d.user null <nul
adb shell cmd wifi set-verbose-logging disabled <nul > nul 2>&1
adb shell device_config put profcollect_native_boot enabled false <nul
adb shell setprop debug.sf.boot_animation false <nul
adb shell setprop debug.sf.edge_extension_shader false <nul
adb shell setprop debug.perf_event_max_sample_rate 1 <nul
adb shell setprop debug.perf_event_mlock_kb 2 <nul
adb shell setprop debug.perf_cpu_time_max_percent 1 <nul
adb shell setprop security.perf_harden 0 <nul
adb shell setprop debug.lldb-rpc-server 0 <nul
adb shell setprop debug.MB.running 0 <nul
adb shell setprop debug.hwc.otf 0 <nul
adb shell setprop debug.art.monitor.app false <nul
::if something is wrong , revert this propt by reboot
adb shell setprop sys.wifitracing.started 0 <nul > nul 2>&1
adb shell setprop debug.rs.script 0 <nul
adb shell setprop debug.rs.shader 0 <nul
adb shell setprop debug.sensors 0 <nul
adb shell setprop debug.hwui.profile false <nul
adb shell setprop debug.layout false <nul
adb shell setprop debug.generate-debug-info false <nul
adb shell setprop debug.egl.traceGpuCompletion false <nul
adb shell setprop debug.rs.shader.attributes 0 <nul
adb shell setprop debug.rs.shader.uniforms 0 <nul
adb shell setprop debug.rs.visual 0 <nul
adb shell setprop debug.egl.callstack false <nul
adb shell setprop debug.orientation.log false <nul
adb shell setprop debug.ld.all 0 <nul
adb shell setprop debug.hwui.level 0 <nul
adb shell setprop debug.contacts.ksad 0 <nul
adb shell setprop debug.sf.layerdump 0 <nul
adb shell setprop debug.ldbase 0 <nul
adb shell setprop debug.perfmond.atrace 0 <nul
adb shell setprop debug.sf.enable_transaction_tracing false <nul
adb shell setprop debug.gles.layers 0 <nul
adb shell setprop debug.angle.validation false <nul
adb shell setprop debug.sf.layer_history_trace false <nul
adb shell setprop debug.sf.layer_caching_highlight false <nul
adb shell setprop debug.jni.logging 0 <nul
adb shell setprop debug.orientation.log false <nul
adb shell setprop debug.track-associations 0 <nul
adb shell setprop debug.tracing.screen_state 0 <nul
adb shell setprop debug.synclog 0 <nul
adb shell setprop debug.sys.looper_stats_enabled 0 <nul
adb shell setprop debug.velocitytracker.alt 0 <nul
adb shell setprop debug.tflite.trace 0 <nul
adb shell setprop debug.adbd.logging 0 <nul
adb shell setprop debug.sf.enable_egl_image_tracker false <nul
adb shell setprop debug.stagefright.omx-debug 0 <nul
adb shell setprop debug.stagefright.profilecodec 0 <nul
adb shell setprop debug.debuggerd.wait_for_gdb false <nul
adb shell setprop debug.cp2.scan_all_packages 0 <nul
adb shell setprop debug.tracing.screen_brightness 0 <nul
adb shell setprop debug.servicemanager.log_calls 0 <nul
adb shell setprop debug.hwui.print_config 0 <nul
adb shell setprop debug.choreographer.frametime false <nul
adb shell setprop debug.sf.vsp_trace false <nul
adb shell setprop debug.egl.trace 0 <nul
adb shell setprop debug.egl.finish false <nul
adb shell setprop debug.sf.trace_hint_sessions false <nul
adb shell setprop debug.sf.vsync_trace_detailed_info false <nul
adb shell setprop debug.atrace.tags.enableflags 0 <nul
adb shell setprop debug.debuggerd.wait_for_debugger false <nul
adb shell setprop debug.hwui.capture_skp_enabled false <nul
adb shell setprop debug.renderengine.skia_atrace_enabled 0 <nul
adb shell setprop debug.mdpcomp.logs 0 <nul
adb shell setprop debug.graphics.gpu.profiler.perfetto 0 <nul
adb shell setprop debug.NewDatabasePerformanceTests.enable_wal false <nul
adb shell setprop debug.hwui.skia_atrace_enabled 0 <nul
adb shell setprop debug.rs.profile 0 <nul
adb shell setprop debug.sf.dump 0 <nul
adb shell setprop debug.debuggerd.disable 1 <nul
adb shell setprop debug.hwc_dump_en 0 <nul
adb shell setprop persist.traced.enable 0 <nul > nul 2>&1
adb shell setprop debug.hwc.logvsync 0 <nul
adb shell setprop debug.malloc 0 <nul
adb shell setprop debug.enable.wl_log 0 <nul
adb shell setprop debug.sensors.logging.slpi false <nul
adb shell setprop debug.tracing.battery_status 0 <nul
adb shell setprop debug.hwui.trace_gpu_resources false <nul
adb shell setprop debug.hwui.skia_use_perfetto_track_events false <nul
adb shell setprop debug.hwui.skia_tracing_enabled false <nul
adb shell setprop debug.hwui.skip_eglmanager_telemetry true <nul
adb shell setprop persist.traced_perf.enable false <nul > nul 2>&1
adb shell setprop debug.renderengine.skia_use_perfetto_track_events false <nul
adb shell setprop debug.tracing.ctl.renderengine.skia_tracing_enabled false <nul
adb shell setprop debug.hwui.skp_filename false <nul
:: REMOVED (harmful): debug.sqlite.journalmode OFF / syncmode OFF / wal.syncmode OFF.
:: These switch off SQLite's durability for EVERY database on the device. journalmode=OFF
:: removes the rollback journal, so a transaction interrupted by a crash, a kernel panic
:: or a battery pull cannot be rolled back and leaves a CORRUPT database; syncmode=OFF
:: (and its WAL counterpart) stop SQLite calling fsync, so committed data that the app
:: believes is on disk can vanish. The cost is contacts, messages, app state - not logs.
:: wal.syncmode goes with the other two on purpose: modern Android databases mostly run
:: in WAL mode, so removing syncmode while leaving wal.syncmode would look fixed and
:: leave the same hole open. journalsizelimit is kept - it only caps the journal FILE
:: SIZE after commit and costs nothing in integrity.
adb shell setprop debug.sqlite.journalsizelimit 1mb <nul
adb shell setprop debug.sf.dump.external false <nul
adb shell setprop debug.sf.dump.primary false <nul
adb shell setprop debug.sf.dump.png 0 <nul
adb shell setprop debug.checkjni 0 <nul
adb shell setprop debug.apidump.detailed false <nul
adb shell setprop debug.renderengine.skia_tracing_enabled false <nul
adb shell setprop debug.adpf_cts_verbose_logging false <nul
adb shell setprop debug.tracing.plug_type 0 <nul
adb shell setprop debug.tracing.profile_boot_classpath 0 <nul
adb shell setprop debug.tracing.profile_system_server 0 <nul
adb shell setprop debug.tracing.mnc 0 <nul
adb shell setprop debug.tracing.mcc 0 <nul
adb shell setprop debug.tracing.device_state 0 <nul
adb shell setprop debug.logging.enabled false <nul
adb shell setprop debug.nn.fuzzer.dumpspec 0 <nul
adb shell setprop debug.nn.fuzzer.log 0 <nul
adb shell setprop debug.nn.fuzzer.detectleak 0 <nul
adb shell setprop debug.perfetto.sdk_sysprop_guard_generation 0 <nul
adb shell setprop debug.libbase.property_test false <nul
adb shell setprop debug.tracing.ctl.perfetto.sdk_sysprop_guard_generation false <nul
adb shell setprop debug.tracing.ctl.hwui.skia_use_perfetto_track_events false <nul
adb shell setprop debug.tracing.ctl.hwui.skia_tracing_enabled false <nul
adb shell setprop debug.sf.dump.enable false <nul
adb shell setprop debug.hwc.enable_vds_dump 0 <nul
adb shell setprop debug.power.loghint 0 <nul
adb shell setprop debug.surface_trace 0 <nul
adb shell setprop debug.sf.ddms 0 <nul
adb shell setprop debug.sensors.diag_buffer_log false <nul
adb shell setprop debug.systemui.latency_tracking 0 <nul
adb shell setprop debug.hwc.trace_hint_sessions false <nul
adb shell setprop debug.vulkan.enable_callback false <nul
adb shell setprop debug.angle.enable_vulkan_api_dump_layer 0 <nul
adb shell setprop debug.angle.capture.enabled 0 <nul
adb shell setprop debug.force_remoteinput_history false <nul
adb shell setprop persist.debug.trace_layouts false <nul > nul 2>&1
adb shell setprop debug.atrace.prefer_sdk false <nul
adb shell setprop debug.tracing.desktop_mode_visible_tasks 0 <nul
adb shell setprop debug.msg_enable 0 <nul
adb shell setprop debug.hwc.normalize_hint_session_durations false <nul
adb shell setprop db.log.detailed 0 <nul > nul 2>&1
adb shell setprop debug.mdlogger.Running 0 <nul
adb shell setprop debug.sf.sa_log 0 <nul
adb shell setprop debug.hwc.fakevsync 0 <nul
adb shell setprop debug.rs.reduce-split-accum 1 <nul
adb shell setprop debug.hwui.nv_profiling false <nul
adb shell setprop debug.hwui.filter_test_overhead false <nul
adb shell setprop debug.trace.enable 0 <nul
adb shell setprop debug.sf.treble_testing_override false <nul
adb shell setprop debug.sf.kernel_idle_timer_update_overlay false <nul
adb shell setprop debug.choreographer.janklog false <nul
adb shell setprop debug.sf.hwc_hotplug_error_via_neg_vsync 0 <nul
adb shell setprop debug.firebase.analytics.app none <nul
adb shell setprop debug.atrace.user_initiated 0 <nul
adb shell setprop debug.stagefright.rtp false <nul
adb shell setprop debug.incremental.enforce_readlogs_max_interval_for_system_dataloaders false <nul
adb shell setprop debug.Stats false <nul
adb shell setprop debug.AnalysisOrder false <nul
adb shell setprop debug.DumpLiveExprs false <nul
adb shell setprop debug.DumpLiveVars false <nul
adb shell setprop debug.DumpCFG false <nul
adb shell setprop debug.ViewCFG false <nul
adb shell setprop debug.DumpCalls false <nul
adb shell setprop debug.ReportStmts false <nul
adb shell setprop debug.DumpDominators false <nul
adb shell setprop debug.DumpCallGraph false <nul
adb shell setprop debug.ConfigDumper false <nul
adb shell setprop debug.DumpControlDependencies false <nul
adb shell setprop debug.ExprInspection false <nul
adb shell setprop debug.adservices.consent_manager_debug_mode null <nul
adb shell setprop debug.vulkan.layers '' <nul
:::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: REMOVED: debug.force_low_ram true
:: This was actively HARMFUL here. It forces low-RAM mode
:: (smaller heap, aggressive process killing, fewer caches)
:: which slows the device down. It's still set deliberately
:: inside :onsvpp (Extreme Power Saver) where it belongs.
adb shell device_config put device_personalization_services SpeechRecognitionService__clear_logging_events_if_too_much_memory true <nul
:::::::::::::::::::::::::::::::::::::::::::::::::::::::
::changed
adb shell setprop debug.sf.prime_shader_cache.transparent_image_dimmed_layers false <nul
adb shell setprop debug.sf.prime_shader_cache.solid_dimmed_layers false <nul
adb shell setprop debug.sf.prime_shader_cache.shadow_layers false <nul
adb shell setprop debug.egl.force_msaa false <nul
adb shell setprop debug.sf.showupdates 0 <nul
adb shell setprop debug.sf.showcpu 0 <nul
adb shell setprop debug.sf.showbackground 0 <nul
adb shell setprop debug.sf.showfps 0 <nul
adb shell setprop debug.rs.debug 0 <nul
adb shell setprop debug.sf.show_refresh_rate_overlay_spinner 0 <nul
adb shell setprop debug.sf.show_refresh_rate_overlay_render_rate 0 <nul
adb shell setprop debug.sf.show_refresh_rate_overlay_in_middle 0 <nul
adb shell setprop debug.hwc.showfps 0 <nul
adb shell setprop debug.hwui.overdraw false <nul
adb shell setprop debug.hwui.webview_overlays_enabled false <nul
adb shell setprop debug.sf.enable_hwc_vds false <nul
adb shell setprop debug.hwui.profile.maxframes 0 <nul
adb shell setprop debug.hwui.show_non_rect_clip hide <nul
adb shell setprop debug.hwui.show_layers_updates false <nul
adb shell setprop debug.assert 0 <nul
adb shell setprop debug.hwui.show_dirty_regions false <nul
adb shell setprop debug.angle.capture.frame_start 0 <nul
adb shell setprop debug.rs.reduce 1 <nul
adb shell setprop debug.sf.gpuoverlay 0 <nul
adb shell setprop debug.stagefright.fps false <nul
adb shell setprop debug.sf.disable_hwc_vds 1 <nul
adb shell setprop debug.hwc.simulate 0 <nul
adb shell setprop debug.enable_remote_input false <nul
adb shell setprop debug.angle.markers 0 <nul
adb shell setprop debug.stagefright.experiments false <nul
adb shell setprop debug.stagefright.enableshaping 0 <nul
adb shell setprop debug.sf.show_predicted_vsync false <nul
::changed
call :dropbox_lowprio
adb shell cmd dropbox set-rate-limit 20000000000000 <nul
adb shell device_config put runtime_native metrics.reporting-mods 0 <nul
adb shell device_config put runtime_native metrics.reporting-mods-server 0 <nul
adb shell device_config put runtime_native metrics.write-to-statsd false <nul
adb shell device_config put runtime_native metrics.reporting-num-mods 0 <nul
adb shell device_config put runtime_native metrics.reporting-num-mods-server 0 <nul
adb shell device_config put runtime_native metrics.reporting-spec S <nul
adb shell device_config put runtime_native metrics.reporting-spec-server S <nul
adb shell device_config put odad enable_fa_stats_log_logging false <nul
adb shell device_config put device_personalization_services StatsLog__active_users_logger_enabled false <nul
adb shell device_config put device_personalization_services StatsLog__active_users_logger_non_persistent false <nul
adb shell device_config put device_personalization_services StatsLog__enable_new_logger_api false <nul
adb shell device_config put adservices cobalt_logging_enabled false <nul
adb shell device_config put adservices enable_logged_topic false <nul
adb shell device_config put adservices adservice_error_logging_enabled false <nul
adb shell device_config put adservices measurement_enable_app_package_name_logging false <nul
adb shell device_config put adservices measurement_enable_source_debug_report false <nul
adb shell device_config put adservices fledge_app_package_name_logging_enabled false <nul
adb shell device_config put adservices fledge_auction_server_enable_debug_reporting false <nul
adb shell device_config put adservices fledge_auction_server_api_usage_metrics_enabled false <nul
adb shell device_config put adservices enable_ad_services_system_api false <nul
adb shell device_config put bluetooth INIT_gd_hal_snoop_logger_filtering false <nul
adb shell device_config put bluetooth INIT_gd_hal_snoop_logger_socket false <nul
adb shell device_config put odad westworld_logging false <nul
adb shell device_config put odad log_error_model_id_westworld_enabled false <nul
adb shell device_config put odad log_model_id_westworld false <nul
adb shell device_config put odad log_model_version_westworld false <nul
adb shell device_config put odad log_classification_latency_westworld false <nul
adb shell device_config put odad moirai_additional_metrics_enabled false <nul
adb shell device_config put odad mismatch_metrics_v2_enabled false <nul
adb shell device_config put on_device_personalization odp_enable_client_error_logging false <nul
adb shell device_config put on_device_personalization fcp_enable_client_error_logging false <nul
adb shell device_config put on_device_personalization odp_background_jobs_logging_enabled false <nul
adb shell device_config put on_device_personalization fcp_enable_background_jobs_logging false <nul
adb shell device_config put device_personalization_services AutofillVC__enable_clearcut_log false <nul
adb shell device_config put device_personalization_services Captions__enable_clearcut_logging false <nul
adb shell device_config put device_personalization_services PlatformLogging__enable_metric_wise_populations false <nul
adb shell device_config put device_personalization_services Superpacks__use_logging_listener false <nul
adb shell device_config put device_personalization_services Overview__enable_pir_clearcut_logging false <nul
adb shell device_config put device_personalization_services Overview__enable_pir_westworld_logging false <nul
adb shell cmd display ab-logging-disable <nul > nul 2>&1
adb shell cmd display dwb-logging-disable <nul > nul 2>&1
adb shell cmd display dmd-logging-disable <nul > nul 2>&1
adb shell settings put global netstats_sample_enabled 0 <nul
adb shell settings put global sqlite_compatibility_wal_flags legacy_compatibility_wal_enabled=false,wal_syncmode=OFF <nul
adb shell settings put global foreground_service_starts_logging_enabled_uri false <nul
adb shell settings put global activity_starts_logging_enabled_uri false <nul
adb shell settings put global nene_log 0 <nul
adb shell settings put global wifi_link_speed_metrics_enabled 0 <nul
adb shell settings put global wifi_is_unusable_event_metrics_enabled 0 <nul
adb shell settings put global wait_for_debugger 0 <nul
adb shell settings put global contacts_database_wal_enabled 0 <nul
adb shell settings put global logcat_for_system_server_anr 0 <nul
adb shell settings put global enable_gnss_raw_meas_full_tracking 0 <nul
adb shell settings put global force_enable_pss_profiling 0 <nul
adb shell settings put global verbose_logging_level_disabled 1 <nul
adb shell settings put global enable_gpu_debug_layers 0 <nul
:: FIX (unrecoverable delete): this used to `settings delete global gpu_debug_layers`.
:: That key holds a developer's chosen GPU debug-layer LIST, the delete threw the value
:: away, and Logs On has nothing to restore it from - the one destructive, non-revertible
:: write in this whole path. It was also redundant: enable_gpu_debug_layers 0 on the line
:: above is the master switch, and the list does nothing while that is off. Dropped.
adb shell settings put global sys_traced 0 <nul
adb shell settings put global autofill_logging_level 0 <nul
adb shell settings put global dropbox_max_files 1 <nul
adb shell settings put global activity_starts_logging_enabled 0 <nul
adb shell settings put global enable_diskstats_logging 0 <nul
adb shell settings put global foreground_service_starts_logging_enabled 0 <nul
adb shell settings put global wifi_verbose_logging_enabled 0 <nul
adb shell settings put global enable_automatic_system_server_heap_dumps 0 <nul
adb shell settings put global settings_enable_monitor_phantom_procs false <nul
adb shell settings put global enable_opengl_traces false <nul
adb shell settings put global dropbox:dumpsys:procstats disabled <nul
adb shell settings put global dropbox:dumpsys:usagestats disabled <nul
adb shell settings put global battery_stats_constants track_cpu_times_by_proc_state=false,track_cpu_active_cluster_time=false,read_binary_cpu_time=false,max_history_files=0,max_history_buffer_kb=0 <nul
adb shell settings put global chained_battery_attribution_enabled 0 <nul
adb shell settings put global kernel_cpu_thread_reader num_buckets=0,collected_uids=,minimum_total_cpu_usage_millis=999999999 <nul
adb shell settings put global sys_uidcpupower 0 <nul
adb shell settings put global netstats_augment_enabled 0 <nul
adb shell settings put global netstats_combine_subtype_enabled 0 <nul
adb shell settings put global settings_enable_spa_metrics false <nul
adb shell settings put global settings_adb_metrics_writer false <nul
adb shell device_config put systemui enable_notification_memory_monitoring false <nul
adb shell device_config put interaction_jank_monitor enabled false <nul
adb shell settings put system anr_debugging_mechanism 0 <nul
adb shell settings put system remote_control 0 <nul
adb shell cmd looper_stats disable <nul > nul 2>&1
adb shell settings put global looper_stats enabled=false,sampling_interval=999999999 <nul
adb shell simpleperf --log fatal --log-to-android-buffer 0 <nul > nul 2>&1
adb shell cmd autofill set log_level off <nul
adb shell cmd autofill set max_visible_datasets 0 <nul
adb shell cmd activity clear-debug-app <nul
adb shell cmd activity clear-exit-info <nul
adb shell cmd device_policy clear-freeze-period-record <nul > nul 2>&1
adb shell cmd otadexopt cleanup <nul
adb shell cmd voiceinteraction set-debug-hotword-logging false <nul
call :wm_silence_logs
adb shell dumpsys binder_calls_stats --disable <nul > nul 2>&1
adb shell dumpsys binder_calls_stats --disable-detailed-tracking <nul > nul 2>&1
adb shell dumpsys procstats --stop-testing <nul > nul 2>&1
adb shell settings put global binder_calls_stats sampling_interval=500000000,detailed_tracking=disable,enabled=false,upload_data=false <nul
adb shell dumpsys batterystats disable full-history <nul > nul 2>&1
adb shell ime tracing stop <nul
adb shell logcat -c <nul
adb shell logcat -G 64kb <nul
adb shell wm tracing level critical <nul > nul 2>&1
adb shell wm tracing size 1 <nul > nul 2>&1
echo Done , Press Any Button To Go Back
pause > nul
goto Battery

:onlogss
cls
title Logs/etc : On
call :_dcfg_warn
:: NEW: revert universal log silencer
:: '' not "" - see the note under :_sf_clear_props; "" never clears anything.
adb shell setprop persist.log.tag '' <nul > nul 2>&1
adb shell setprop log.tag '' <nul > nul 2>&1
:: FIX (revert-completeness): Logs Off writes persist.debug.trace_layouts false and
:: nothing here undid it. persist.* SURVIVES REBOOT, so one Logs Off pinned it off
:: permanently - the restart prompted at the end of this path does not cover it.
:: Every other persist.* prop that path sets is reverted (persist.log.tag,
:: persist.log.tag.DisplayPowerController, persist.traced.enable,
:: persist.traced_perf.enable), so this was an omission, not a policy.
adb shell setprop persist.debug.trace_layouts '' <nul > nul 2>&1
:: Clear the SQLite durability props an OLDER DCX set in Logs Off, for anyone who ran it
:: before they were removed and has not rebooted since - see the note in :skiplogv.
adb shell setprop debug.sqlite.journalmode '' <nul > nul 2>&1
adb shell setprop debug.sqlite.syncmode '' <nul > nul 2>&1
adb shell setprop debug.sqlite.wal.syncmode '' <nul > nul 2>&1
adb shell logcat -G 256kb <nul
adb shell device_config put adservices enable_ad_services_system_api true <nul
adb shell device_config put odad mismatch_metrics_v2_enabled true <nul
adb shell device_config put adservices fledge_auction_server_api_usage_metrics_enabled true <nul
adb shell device_config put adservices enable_logged_topic true <nul
adb shell settings delete global settings_adb_metrics_writer <nul > nul 2>&1
adb shell settings delete global settings_enable_spa_metrics <nul > nul 2>&1
adb shell device_config put device_personalization_services SpeechRecognitionService__clear_logging_events_if_too_much_memory false <nul
adb shell settings delete global netstats_augment_enabled <nul > nul 2>&1
adb shell settings delete global netstats_combine_subtype_enabled <nul > nul 2>&1
adb shell device_config put interaction_jank_monitor enabled true <nul
adb shell device_config delete systemui enable_notification_memory_monitoring <nul > nul 2>&1
adb shell settings delete global sys_uidcpupower <nul > nul 2>&1
adb shell settings delete global contacts_database_wal_enabled <nul > nul 2>&1
adb shell settings delete global kernel_cpu_thread_reader <nul > nul 2>&1
adb shell device_config put bluetooth INIT_gd_hal_snoop_logger_filtering true <nul
adb shell device_config put bluetooth INIT_gd_hal_snoop_logger_socket true <nul
adb shell device_config put device_personalization_services AutofillVC__enable_clearcut_log true <nul
adb shell settings delete global chained_battery_attribution_enabled <nul > nul 2>&1
adb shell device_config put odad moirai_additional_metrics_enabled true <nul
adb shell device_config put odad log_classification_latency_westworld true <nul
:: FIX (revert-completeness): was `put ...track_cpu_times_by_proc_state=false`,
:: which re-pinned a non-default value instead of reverting. Delete so battery
:: stats tracking returns to the platform default (:offlogss pinned it to
:: max_history_files=0 etc).
adb shell settings delete global battery_stats_constants <nul > nul 2>&1
adb shell device_config put adservices fledge_auction_server_enable_debug_reporting true <nul
adb shell device_config put adservices fledge_app_package_name_logging_enabled true <nul
adb shell device_config put adservices mdd_network_stats_logging_sample_interval 100 <nul
adb shell device_config put adservices mdd_api_logging_sample_interval 100 <nul
adb shell device_config put device_personalization_services Overview__enable_pir_westworld_logging true <nul
adb shell device_config put device_personalization_services Overview__enable_pir_clearcut_logging true <nul
adb shell settings delete global dropbox:dumpsys:procstats <nul > nul 2>&1
adb shell settings delete global dropbox:dumpsys:usagestats <nul > nul 2>&1
adb shell setprop security.perf_harden 1 <nul
adb shell settings delete global enable_opengl_traces <nul > nul 2>&1
adb shell device_config put odad log_model_version_westworld true <nul
adb shell device_config put odad log_model_id_westworld true <nul
adb shell device_config put odad log_error_model_id_westworld_enabled true <nul
adb shell device_config put device_personalization_services Superpacks__use_logging_listener true <nul
adb shell device_config put on_device_personalization fcp_enable_background_jobs_logging true <nul
adb shell device_config put device_personalization_services Captions__enable_clearcut_logging true <nul
adb shell device_config put device_personalization_services PlatformLogging__enable_metric_wise_populations true <nul
adb shell device_config put runtime_native metrics.reporting-spec 1,5,30,60,600 <nul
adb shell device_config put runtime_native metrics.reporting-spec-server 1,10,60,3600,* <nul
adb shell device_config put runtime_native metrics.write-to-statsd true <nul
adb shell device_config put runtime_native metrics.reporting-num-mods 100 <nul
adb shell device_config put runtime_native metrics.reporting-num-mods-server 100 <nul
adb shell device_config put runtime_native metrics.reporting-mods 2 <nul
adb shell device_config put runtime_native metrics.reporting-mods-server 2 <nul
adb shell settings delete global netstats_sample_enabled <nul > nul 2>&1
adb shell settings delete global bluetooth_disabled_profiles <nul > nul 2>&1
adb shell wm tracing level trim <nul > nul 2>&1
adb shell settings delete global binder_calls_stats <nul > nul 2>&1
adb shell settings delete global foreground_service_starts_logging_enabled_uri <nul > nul 2>&1
adb shell settings delete global activity_starts_logging_enabled_uri <nul > nul 2>&1
adb shell device_config delete profcollect_native_boot enabled <nul > nul 2>&1
adb shell setprop persist.log.tag.DisplayPowerController '' <nul
adb shell device_config delete systemui com.android.systemui.coroutine_tracing <nul > nul 2>&1
adb shell settings delete global nene_log <nul > nul 2>&1
adb shell settings delete global wifi_link_speed_metrics_enabled <nul > nul 2>&1
adb shell settings delete global wifi_is_unusable_event_metrics_enabled <nul > nul 2>&1
adb shell settings delete global wait_for_debugger <nul > nul 2>&1
adb shell settings delete global contacts_database_wal_enabled <nul > nul 2>&1
adb shell settings delete global logcat_for_system_server_anr <nul > nul 2>&1
adb shell settings delete global enable_gnss_raw_meas_full_tracking <nul > nul 2>&1
adb shell settings delete global force_enable_pss_profiling <nul > nul 2>&1
adb shell settings delete global verbose_logging_level_disabled <nul > nul 2>&1
adb shell settings delete global enable_gpu_debug_layers <nul > nul 2>&1
adb shell cmd autofill set max_visible_datasets 10 <nul
adb shell settings delete global sys_traced <nul > nul 2>&1
adb shell settings delete system user_log_enabled <nul > nul 2>&1
adb shell settings delete system window_orientation_listener_log <nul > nul 2>&1
adb shell settings delete global enable_automatic_system_server_heap_dumps <nul > nul 2>&1
adb shell settings delete global sys.wifitracing.started <nul > nul 2>&1
adb shell settings delete global opengl_trace <nul > nul 2>&1
adb shell settings delete global settings_enable_monitor_phantom_procs <nul > nul 2>&1
adb shell settings delete global dropbox_max_files <nul > nul 2>&1
adb shell settings delete global dropbox:dumpsys:usagestats <nul > nul 2>&1
adb shell settings delete global dropbox:dumpsys:procstats <nul > nul 2>&1
adb shell settings delete global activity_starts_logging_enabled <nul > nul 2>&1
adb shell settings delete global enable_diskstats_logging <nul > nul 2>&1
adb shell settings delete global sys.lmk.reportkills <nul > nul 2>&1
adb shell settings delete global foreground_service_starts_logging_enabled <nul > nul 2>&1
adb shell settings delete global wifi_verbose_logging_enabled <nul > nul 2>&1
adb shell settings delete global enable_automatic_system_server_heap_dumps <nul > nul 2>&1
adb shell cmd looper_stats enable <nul
adb shell settings delete system anr_debugging_mechanism <nul > nul 2>&1
adb shell setprop persist.traced.enable 1 <nul > nul 2>&1
adb shell settings delete global idle_loglevel <nul > nul 2>&1
adb shell settings delete global persist.sampling_profiler <nul > nul 2>&1
adb shell settings delete system Logcat.live <nul > nul 2>&1
adb shell settings delete system remote_control <nul > nul 2>&1
adb shell settings delete system log.closeguard.Animation <nul > nul 2>&1
call :dropbox_lowprio
adb shell cmd dropbox set-rate-limit 2000 <nul
adb shell setprop persist.traced_perf.enable 1 <nul > nul 2>&1
:: FIX: copy-paste bug - this is the On/restore path so it must re-ENABLE
:: (true). It was `false`, identical to :offlogss, so the key never reverted.
adb shell device_config put odad enable_fa_stats_log_logging true <nul
adb shell device_config put device_personalization_services StatsLog__active_users_logger_enabled true <nul
adb shell device_config put device_personalization_services StatsLog__active_users_logger_non_persistent true <nul
adb shell device_config put device_personalization_services StatsLog__enable_new_logger_api true <nul
adb shell device_config put adservices cobalt_logging_enabled true <nul
adb shell device_config put adservices adservice_error_logging_enabled true <nul
adb shell device_config put odad westworld_logging true <nul
adb shell device_config put adservices measurement_enable_source_debug_report true <nul
adb shell cmd display ab-logging-enable <nul > nul 2>&1
adb shell cmd display dwb-logging-enable <nul > nul 2>&1
adb shell cmd display dmd-logging-enable <nul > nul 2>&1
adb shell device_config put on_device_personalization odp_enable_client_error_logging true <nul
adb shell device_config put adservices measurement_enable_app_package_name_logging true <nul
adb shell device_config put on_device_personalization fcp_enable_client_error_logging true <nul
:: FIX (revert-completeness): :offlogss pins these PERSISTENT keys that this
:: On/restore path never undid, so log/metric collection stayed disabled after
:: toggling back On. settings survive reboot, so the restart prompt below does
:: NOT cover them. DeviceConfig server sync is no longer touched here - it lives
:: under Tweaks > DeviceConfig server sync.
adb shell settings delete global looper_stats <nul > nul 2>&1
adb shell settings delete global sqlite_compatibility_wal_flags <nul > nul 2>&1
adb shell settings delete global autofill_logging_level <nul > nul 2>&1
adb shell device_config put on_device_personalization odp_background_jobs_logging_enabled true <nul > nul 2>&1
adb shell logcat -c <nul
echo.
echo.
echo [%r%^^!%w%] Please Restart Device To Finish The Process
echo.
echo.
timeout /t 2 /nobreak > nul
echo Done , Press Any Button To Go Back
pause > nul
goto Battery

:saverpower
@echo off
cls
title Toggle Power Saver
echo.
echo.
echo Toggle Your Power Saver Here
echo.
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offsv
if "!toggle!"=="2" goto onsv
if "!toggle!"=="3" goto Battery
:: guard against invalid input
goto saverpower

:offsv
@echo off
cls
title Power Saver : Off
adb shell settings delete global low_power <nul
adb shell settings delete global low_power_sticky <nul
call :_act_reset
call :_settings_verify global low_power DELETE
call :_act_summary
echo Press Any Button To Go Back
pause > nul
goto Battery

:onsv
@echo off
cls
title Power Saver : On
adb shell settings put global low_power 1 <nul
adb shell settings put global low_power_sticky 0 <nul
call :_act_reset
call :_settings_verify global low_power 1
call :_act_summary
echo Press Any Button To Go Back
pause > nul
goto Battery

:animation
@echo off
cls
title Toggle Animation
echo.
echo.
echo Toggle Your Animation Here
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offani
if "!toggle!"=="2" goto onani
if "!toggle!"=="3" goto Battery
:: guard against invalid input
goto animation

:offani
@echo off
cls
title Animation : Off
adb shell settings put global enable_back_animation 0 <nul
adb shell settings put global fancy_ime_animations 0 <nul
adb shell settings put secure accessibility_disable_animations 1 <nul
adb shell settings put global fade_duration 0 <nul
adb shell settings put global reduce_motion 1 <nul
adb shell settings put secure reduce_motion 1 <nul
adb shell settings put secure long_press_timeout 250 <nul
adb shell settings put secure multi_press_timeout 250 <nul
adb shell settings put global enable_back_animation 0 <nul
adb shell settings put global window_animation_scale 0.0 <nul
adb shell settings put global transition_animation_scale 0.0 <nul
adb shell settings put global animator_duration_scale 0.0 <nul
adb shell settings put secure accessibility_disable_animations 1 <nul
adb shell settings put global disable_window_blurs 1 <nul
call :_act_reset
call :_settings_verify global window_animation_scale 0.0
call :_settings_verify global transition_animation_scale 0.0
call :_settings_verify global animator_duration_scale 0.0
call :_act_summary
echo Press Any Button To Go Back
pause > nul
goto Battery

:onani
@echo off
cls
title Animation : On
adb shell settings delete global reduce_motion <nul > nul 2>&1
adb shell settings delete global enable_back_animation <nul > nul 2>&1
adb shell settings delete global fancy_ime_animations <nul > nul 2>&1
adb shell settings delete secure accessibility_disable_animations <nul > nul 2>&1
adb shell settings delete global recent_app_transition_duration_scale <nul > nul 2>&1
adb shell settings delete global recent_app_transition_scale <nul > nul 2>&1
adb shell settings delete global app_transition_animation_duration_scale <nul > nul 2>&1
adb shell settings delete global app_transition_animation_scale <nul > nul 2>&1
adb shell settings delete global reduce_transitions <nul > nul 2>&1
adb shell settings delete global shadow_animation_scale <nul > nul 2>&1
adb shell settings delete global remove_animations <nul > nul 2>&1
adb shell settings delete global fade_duration <nul > nul 2>&1
adb shell settings delete secure reduce_motion <nul > nul 2>&1
:: FIX (revert-completeness): :offani pins secure long_press_timeout and
:: multi_press_timeout to 250; restoring animations ("On") must delete them
:: so tap / long-press timing returns to the platform default (400 / 300 ms).
adb shell settings delete secure long_press_timeout <nul > nul 2>&1
adb shell settings delete secure multi_press_timeout <nul > nul 2>&1
adb shell settings delete global animator_slow_preview <nul > nul 2>&1
adb shell settings delete global animation_scale_animator_duration <nul > nul 2>&1
adb shell settings delete global animation_scale_window_transition <nul > nul 2>&1
adb shell settings delete global activity_open_enter_animation <nul > nul 2>&1
adb shell settings delete global activity_open_exit_animation <nul > nul 2>&1
adb shell settings delete global activity_close_enter_animation <nul > nul 2>&1
adb shell settings delete global activity_close_exit_animation <nul > nul 2>&1
adb shell settings delete global app_transition_scale <nul > nul 2>&1
adb shell settings delete global app_transition_duration_scale <nul > nul 2>&1
adb shell settings delete global app_close_animate_level <nul > nul 2>&1
adb shell settings delete global windows_anim_duration_scale <nul > nul 2>&1
adb shell settings delete global windows_anim_scale <nul > nul 2>&1
adb shell settings delete global windows_transition_anim_scale <nul > nul 2>&1
adb shell settings delete global windows_transition_animation_duration_scale <nul > nul 2>&1
adb shell settings delete global window_animation_duration_scale <nul > nul 2>&1
adb shell settings delete global transition_animation_duration_scale <nul > nul 2>&1
adb shell settings delete global display_animation_duration_scale <nul > nul 2>&1
adb shell settings delete global display_animation_scale <nul > nul 2>&1
adb shell settings delete global window_move_animation_duration_scale <nul > nul 2>&1
adb shell settings delete global window_move_animation_scale <nul > nul 2>&1
adb shell settings put global window_animation_scale 1.0 <nul > nul 2>&1
adb shell settings put global transition_animation_scale 1.0 <nul > nul 2>&1
adb shell settings put global animator_duration_scale 1.0 <nul > nul 2>&1
adb shell settings put global disable_window_blurs 0 <nul > nul 2>&1
adb shell settings delete global accessibility_reduce_transparency <nul > nul 2>&1
adb shell device_config delete systemui window_cornerRadius <nul > nul 2>&1
adb shell device_config delete systemui window_blur <nul > nul 2>&1
adb shell device_config delete systemui window_shadow <nul > nul 2>&1
adb shell device_config delete systemui reduce_animations <nul > nul 2>&1
adb shell device_config delete battery_saver reduce_animations <nul > nul 2>&1
call :_act_reset
call :_settings_verify global window_animation_scale 1.0
call :_settings_verify global transition_animation_scale 1.0
call :_settings_verify global animator_duration_scale 1.0
call :_act_summary
echo.
echo.
echo [%r%^^!%w%] Please Restart Device To Finish The Process
echo.
echo.
timeout /t 2 /nobreak > nul
echo Press Any Button To Go Back
pause > nul
goto Battery
::wifisettings
:autowifi
@echo off
cls
title Wi-Fi/BT scan and related
echo.
echo.
echo  Toggles wifi/bt scan-always and related scoring/netstats keys.
echo  Not an OEM "auto Wi-Fi" switch. Some watchdog keys are ignored on modern stacks.
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offaut
if "!toggle!"=="2" goto onaut
if "!toggle!"=="3" goto Battery
:: guard against invalid input
goto autowifi

:offaut
@echo off
cls
title Auto Wifi : Off
adb shell settings put global wifi_supplicant_scan_interval_ms 240000 <nul
adb shell settings put global wifi_networks_available_notification_on 0 <nul
adb shell settings put global wifi_watchdog_on 0 <nul
adb shell settings put global wifi_watchdog_poor_network_test_enabled 0 <nul
adb shell settings put global wifi_scan_always_enabled 0 <nul > nul 2>&1
adb shell settings put global bluetooth_scan_always_enabled 0 <nul > nul 2>&1
adb shell settings put global network_recommendations_enabled 0 <nul > nul 2>&1
adb shell settings put global netstats_enabled 0 <nul > nul 2>&1
adb shell settings put global network_scoring_ui_enabled 0 <nul > nul 2>&1
adb shell settings put global wifi_watchdog_poor_network_test_enabled 0 <nul > nul 2>&1
call :_act_reset
call :_settings_verify global wifi_scan_always_enabled 0
call :_settings_verify global bluetooth_scan_always_enabled 0
call :_act_summary
echo Press Any Button To Go Back
pause > nul
goto Battery

:onaut
@echo off
cls
title Auto Wifi : On
adb shell settings delete global wifi_supplicant_scan_interval_ms <nul > nul 2>&1
adb shell settings delete global wifi_networks_available_notification_on <nul > nul 2>&1
adb shell settings delete global wifi_watchdog_on <nul > nul 2>&1
adb shell settings delete global wifi_watchdog_poor_network_test_enabled <nul > nul 2>&1
adb shell settings put global wifi_scan_always_enabled 1 <nul > nul 2>&1
adb shell settings put global bluetooth_scan_always_enabled 1 <nul > nul 2>&1
adb shell settings delete global network_recommendations_enabled <nul > nul 2>&1
adb shell settings put global netstats_enabled 1 <nul > nul 2>&1
adb shell settings put global network_scoring_ui_enabled 1 <nul > nul 2>&1
adb shell settings delete global wifi_watchdog_poor_network_test_enabled <nul > nul 2>&1
call :_act_reset
call :_settings_verify global wifi_scan_always_enabled 1
call :_settings_verify global bluetooth_scan_always_enabled 1
call :_act_summary
echo Press Any Button To Go Back
pause > nul
goto Battery
::sync
:sync
cls
title Toggle Sync
echo.
echo.
echo Toggle master_sync_status ^(placebo on modern Android^)
echo Real Auto sync is not rootless-writable - see Account Sync on page 2.
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offsync
if "!toggle!"=="2" goto onsync
if "!toggle!"=="3" goto Battery
:: guard against invalid input
goto sync

:offsync
@echo off
cls
title Sync : Off
:: FIX (consistency): unify on master_sync_status - the key :syncmaster uses,
:: the backup captures, and CheckSetting displays. Placebo on modern Android;
:: DeviceConfig sync is no longer touched here (Tweaks > DeviceConfig server sync).
adb shell settings put global master_sync_status 0 <nul
echo Value set. Real Auto sync is unchanged on modern Android.
echo Press Any Button To Go Back
pause > nul
goto Battery

:onsync
@echo off
cls
title Sync : On
:: FIX (consistency): see :offsync - unify on master_sync_status.
adb shell settings put global master_sync_status 1 <nul
echo Value set. Real Auto sync is unchanged on modern Android.
echo Press Any Button To Go Back
pause > nul
goto Battery
::motion
:motion
@echo off
cls
title Samsung motion (OEM)
echo.
echo.
echo  Samsung OneUI motion-gesture keys ^(master_motion / air_motion_*^).
echo  Placebo on non-Samsung devices - AOSP does not read them.
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offmotion
if "!toggle!"=="2" goto onmotion
if "!toggle!"=="3" goto Battery
:: guard against invalid input
goto motion

:offmotion
@echo off
cls
title Motion : Off
adb shell settings put system master_motion 0 <nul > nul 2>&1
adb shell settings put system motion_engine 0 <nul > nul 2>&1
adb shell settings put system air_motion_engine 0 <nul > nul 2>&1
adb shell settings put system air_motion_wake_up 0 <nul > nul 2>&1
echo Press Any Button To Go Back
pause > nul
goto Battery

:onmotion
@echo off
cls
title Motion : On
:: FIX: "settings remove" is not a real verb (stock verbs: get/put/delete/
:: reset/list), so Motion "On" silently reverted nothing - the error was
:: hidden by >nul 2>&1. "delete" restores the OEM default as intended.
adb shell settings delete system master_motion <nul > nul 2>&1
adb shell settings delete system motion_engine <nul > nul 2>&1
adb shell settings delete system air_motion_engine <nul > nul 2>&1
adb shell settings delete system air_motion_wake_up <nul > nul 2>&1
echo Press Any Button To Go Back
pause > nul
goto Battery
::zram
:zram
@echo off
cls
title ZRAM preference
echo.
echo.
echo  Sets global zram_enabled ^(StorageManager preference^). Needs reboot;
echo  no-op if the OEM has no zram toggle ^(e.g. Samsung RAM Plus uses other keys^).
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offzram
if "!toggle!"=="2" goto onzram
if "!toggle!"=="3" goto Battery
:: guard against invalid input
goto zram

:offzram
@echo off
cls
title ZRAM : Off
adb shell settings put global zram_enabled 0 <nul
call :_act_reset
call :_settings_verify global zram_enabled 0
call :_act_summary
echo Reboot may be required for this to apply.
echo Press Any Button To Go Back
pause > nul
goto Battery

:onzram
@echo off
cls
title ZRAM : On
adb shell settings put global zram_enabled 1 <nul
call :_act_reset
call :_settings_verify global zram_enabled 1
call :_act_summary
echo Reboot may be required for this to apply.
echo Press Any Button To Go Back
pause > nul
goto Battery
::extreme
:extremepower
@echo off
cls
title Aggressive saver constants
echo.
echo.
echo  Not OEM "Extreme power saving". Tweaks battery_saver_constants,
echo  power mode, and related debug/AM flags. device_config bits need root on 14+.
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offsvpp
if "!toggle!"=="2" goto onsvpp
if "!toggle!"=="3" goto Battery
:: guard against invalid input
goto extremepower

:offsvpp
@echo off
cls
title Extreme Power Saver : Off
adb shell device_config delete activity_manager bg_current_drain_auto_restrict_abusive_apps_enabled <nul
adb shell device_config delete activity_manager bg_auto_restrict_abusive_apps <nul
adb shell cmd power set-adaptive-power-saver-enabled false <nul
adb shell cmd power set-mode 0 <nul
adb shell settings put global battery_tip_constants app_restriction_enabled=true <nul
adb shell settings delete global battery_saver_constants <nul > nul 2>&1
adb shell settings delete global protect_battery <nul > nul 2>&1
adb shell settings delete global activity_manager_constants <nul > nul 2>&1
:: FIX (revert-completeness): :onsvpp forces the device into low-RAM mode
:: (debug.force_low_ram true), which persists until reboot and degrades
:: every app launched afterward. Clear it so "Off" starts reverting
:: immediately; the reboot prompted below completes it. (The debug.rs.*
:: RenderScript props :onsvpp sets are no-ops on Android 12+ and have no
:: clean default to restore, so they are left to the reboot.)
adb shell setprop debug.force_low_ram false <nul > nul 2>&1
echo.
echo.
echo [%r%^^!%w%] Please Restart Device To Finish The Process
echo.
echo.
timeout /t 2 /nobreak > nul
echo Press Any Button To Go Back
pause > nul
goto Battery

:onsvpp
@echo off
cls
title Extreme Power Saver : On
call :_dcfg_warn
:: FIX: this ran BOTH "cmd battery reset" and "dumpsys battery reset" -
:: two interfaces to the same operation (clears any fake-battery state so
:: the saver reads the real battery). One call is enough; dumpsys is kept
:: because it exists on older builds where the "cmd" service shell may not.
adb shell dumpsys battery reset <nul
adb shell device_config put activity_manager bg_current_drain_auto_restrict_abusive_apps_enabled true <nul
adb shell device_config put activity_manager bg_auto_restrict_abusive_apps 1 <nul
adb shell settings put global activity_manager_constants power_check_interval=990000,power_check_max_cpu_1=2,power_check_max_cpu_2=2,power_check_max_cpu_3=2,power_check_max_cpu_4=2 <nul
adb shell settings put global battery_saver_constants advertise_is_enabled=false,enable_datasaver=false,enable_night_mode=true,disable_launch_boost=true,disable_vibration=true,disable_animation=true,disable_soundtrigger=true,defer_full_backup=true,defer_keyvalue_backup=true,enable_firewall=false,location_mode=2,enable_brightness_adjustment=false,adjust_brightness_factor=0.5,force_all_apps_standby=true,force_background_check=true,disable_optional_sensors=true,disable_aod=true,enable_quick_doze=true <nul
adb shell settings put global battery_tip_constants reduced_battery_enabled=true,battery_saver_tip_enabled=true,high_usage_period_ms=120000,app_restriction_enabled=true,battery_tip_enabled=false,summary_enabled=false,high_usage_enabled=true,high_usage_app_count=1,high_usage_battery_draining=15,reduced_battery_percent=5,low_battery_enabled=true,low_battery_hour=1 <nul
adb shell cmd power set-mode 1 <nul
adb shell cmd power set-adaptive-power-saver-enabled true <nul
adb shell setprop debug.rs.max-threads 2 <nul
adb shell setprop debug.rs.precision rs_fp_relaxed <nul
adb shell setprop debug.force_low_ram true <nul
echo Press Any Button To Go Back
pause > nul
goto Battery

:senderror
cls
title Toggle Send Error
echo.
echo.
echo Toggle Your Send Error Here
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offerr
if "!toggle!"=="2" goto onerr
if "!toggle!"=="3" goto Battery
:: guard against invalid input
goto senderror

:offerr
cls
title Send Error : Off
adb shell settings put secure send_action_app_error 0 <nul > nul 2>&1
adb shell settings put global send_action_app_error 0 <nul > nul 2>&1
adb shell settings put global enable_diagnostic_data 0 <nul > nul 2>&1
adb shell settings put system send_security_reports 0 <nul > nul 2>&1
adb shell settings put secure upload_debug_log_pref 0 <nul > nul 2>&1
adb shell settings put secure upload_log_pref 0 <nul > nul 2>&1
adb shell settings put system profiler.force_disable_ulog 1 <nul > nul 2>&1
adb shell settings put system profiler.force_disable_err_rpt 1 <nul > nul 2>&1
adb shell settings put secure usage_metrics_marketing_enabled 0 <nul > nul 2>&1
adb shell settings put secure USAGE_METRICS_UPLOAD_ENABLED 0 <nul > nul 2>&1
echo Done , Press Any Button To Go Back
pause > nul
goto Battery

:onerr
cls
title Send Error : On
adb shell settings put secure send_action_app_error 1 <nul > nul 2>&1
adb shell settings put global send_action_app_error 1 <nul > nul 2>&1
adb shell settings put global enable_diagnostic_data 1 <nul > nul 2>&1
adb shell settings put system send_security_reports 1 <nul > nul 2>&1
adb shell settings delete secure upload_debug_log_pref <nul > nul 2>&1
adb shell settings delete secure upload_log_pref <nul > nul 2>&1
adb shell settings delete system profiler.force_disable_ulog <nul > nul 2>&1
adb shell settings delete system profiler.force_disable_err_rpt <nul > nul 2>&1
adb shell settings delete secure usage_metrics_marketing_enabled <nul > nul 2>&1
adb shell settings delete secure USAGE_METRICS_UPLOAD_ENABLED <nul > nul 2>&1
echo Done , Press Any Button To Go Back
pause > nul
goto Battery

:toggleprofilling
cls
title ART lock profiling (developer)
echo.
echo.
echo  ART runtime_native_boot disable_lock_profiling - developer/debug only.
echo  Not a battery or FPS toggle. device_config writes need root on Android 14+.
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offprof
if "!toggle!"=="2" goto onprof
if "!toggle!"=="3" goto Battery
:: guard against invalid input
goto toggleprofilling

:offprof
cls
title Lock Profiling : Off
call :_dcfg_warn
adb shell device_config put runtime_native_boot disable_lock_profiling true <nul
echo Done , Press Any Button To Go Back
pause > nul
goto Battery

:onprof
cls
title Lock Profiling : ON
call :_dcfg_warn
adb shell device_config put runtime_native_boot disable_lock_profiling false <nul
echo Done , Press Any Button To Go Back
pause > nul
goto Battery
:: gaming
:Gaming
@echo off
title Gaming Mode
cls
call :logo
echo          ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
for /f "tokens=3,4,5,6,7 delims= " %%a in ('adb shell uptime ^<nul 2^>nul') do echo           [%g%+%w%]Uptime: %%a %%b %%c
set "cpucheck=N/A"
for /f "tokens=2 delims=:" %%i in ('adb shell dumpsys cpuinfo ^<nul 2^>nul ^| findstr /C:"Load:"') do set "cpucheck=%%i"
echo           [%g%+%w%]%cpucheck% LOAD
echo          ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
echo.
echo.
echo                                     %r%[%w%1%r%]%w% Toggle GMS
echo                                     %r%[%w%2%r%]%w% Thermal override ^(temporary^)
echo                                     %r%[%w%3%r%]%w% Toggle Package Verifier
echo                                     %r%[%w%4%r%]%w% Toggle Game-Overlay
echo                                     %r%[%w%5%r%]%w% Performance props ^(debug/OEM dump^)
echo                                     %r%[%w%6%r%]%w% TCP / DNS / network mode
echo                                     %r%[%w%7%r%]%w% GPU Renderer (Skia GL/Vulkan)
echo                                     %r%[%w%8%r%]%w% Force ANGLE for All Apps
echo                                     %r%[%w%9%r%]%w% Display Scaler (Resolution / DPI)
echo                                     %r%[%w%10%r%]%w% Back

:Gaming_ask
:: FIX (press-twice): re-prompt without redrawing on empty/invalid input,
:: so a phantom empty line after the probes doesn't re-run them (see :dispscaler).
set "game=" & set /p game="Choose An Option >> "
if not defined game goto Gaming_ask
if "!game!"=="1" goto gms
if "!game!"=="2" goto thermal
if "!game!"=="3" goto package
if "!game!"=="4" goto overlay
if "!game!"=="5" goto performance
if "!game!"=="6" goto netboost
if "!game!"=="7" goto gpurenderer
if "!game!"=="8" goto angleall
if "!game!"=="9" goto dispscaler
if "!game!"=="10" goto menu
:: FIX: invalid input previously fell into :gms
goto Gaming_ask
:: ===================================================================
:: NEW: Display Scaler (REAL, no-root)  -  wm size / wm density
::
:: Lowering the render resolution is one of the most effective
:: no-root ways to gain GPU headroom in games and cut power draw:
:: fewer pixels to shade every frame. We scale density by the SAME
:: factor so dp stays constant -> the UI keeps the exact same size,
:: the image is just rendered with fewer pixels (slightly softer).
::
::   wm size  WxH   /  wm size reset     - logical resolution
::   wm density N   /  wm density reset  - DPI
::
:: Both are official commands (Android 4.3+/API 18+), persist across
:: reboot WITHOUT root, and are fully reversible. Presets are computed
:: live from the panel's TRUE physical resolution so they always fit
:: the device. Because DCX drives this over USB, even an unusable
:: on-screen result is recoverable from here via Reset.
:: ===================================================================
:dispscaler
cls
title Display Scaler (Resolution / DPI)
call :logo
:: Read the panel's TRUE native resolution + density as the baseline.
set "PW=" & set "PH=" & set "PD=" & set "PDR=" & set "SZ=" & set "OVR=" & set "OVRD="
for /f "tokens=2 delims=:" %%a in ('adb shell wm size ^<nul 2^>nul ^| findstr /C:"Physical size"') do set "SZ=%%a"
for /f "tokens=1,2 delims=x " %%a in ("%SZ%") do ( set "PW=%%a" & set "PH=%%b" )
for /f "tokens=2 delims=:" %%a in ('adb shell wm density ^<nul 2^>nul ^| findstr /C:"Physical density"') do set "PDR=%%a"
for /f "tokens=* delims= " %%a in ("%PDR%") do set "PD=%%a"
for /f "tokens=2 delims=:" %%a in ('adb shell wm size ^<nul 2^>nul ^| findstr /C:"Override size"') do set "OVR=%%a"
for /f "tokens=2 delims=:" %%a in ('adb shell wm density ^<nul 2^>nul ^| findstr /C:"Override density"') do set "OVRD=%%a"
:: Validate we actually parsed numbers before doing any maths.
if not defined PW goto dispscaler_err
if not defined PH goto dispscaler_err
if not defined PD goto dispscaler_err
echo !PW!!PH!!PD!| findstr /r "[^0-9]" >nul && goto dispscaler_err
set /a W85=PW*85/100, H85=PH*85/100, D85=PD*85/100
set /a W75=PW*75/100, H75=PH*75/100, D75=PD*75/100
set /a W67=PW*67/100, H67=PH*67/100, D67=PD*67/100
set /a W50=PW*50/100, H50=PH*50/100, D50=PD*50/100
echo.
echo  Native : %g%%PW%x%PH%%w% @ %g%%PD% dpi%w%   (the panel's real resolution)
if defined OVR echo  Active override :%gold%%OVR%%w% /%gold%%OVRD%%w% dpi
echo.
echo  Lowering the render resolution gives games more GPU headroom and
echo  saves battery. Density is scaled to match, so the UI keeps the same
echo  size - the image is just drawn with fewer pixels (slightly softer).
echo  All reversible, no root, and applied over USB.
echo.
echo                    %g%[%w%1%g%]%w% 85%% scale  -^> %W85%x%H85% @ %D85% dpi   (subtle, very safe)
echo                    %g%[%w%2%g%]%w% 75%% scale  -^> %W75%x%H75% @ %D75% dpi   (recommended)
echo                    %g%[%w%3%g%]%w% 67%% scale  -^> %W67%x%H67% @ %D67% dpi   (big FPS gain)
echo                    %g%[%w%4%g%]%w% 50%% scale  -^> %W50%x%H50% @ %D50% dpi   (max, looks soft)
echo                    %g%[%w%5%g%]%w% Custom resolution / density
echo                    %g%[%w%6%g%]%w% UI size only (DPI, keeps resolution)
echo                    %g%[%w%7%g%]%w% Reset to native (fixes any weirdness)
echo                    %g%[%w%8%g%]%w% Back

:dispscaler_ask
:: FIX (input "eaten" / press-twice): re-prompt WITHOUT redrawing on empty or
:: invalid input. A blank read here is usually a phantom empty line the console
:: hands set /p right after the slow `wm size`/`wm density` probes above; the old
:: `goto dispscaler` treated it as a miss and redrew the whole menu (re-running
:: those probes), so the user's real keypress only landed on the second try.
:: Absorbing it with a tight re-ask makes the first keypress register, and stray
:: keys no longer re-run the adb probes. The preset vars (W85.. ND) stay in scope.
set "ds="
set /p ds="Choose An Option >> "
if not defined ds goto dispscaler_ask
if "!ds!"=="1" ( set "NW=%W85%" & set "NH=%H85%" & set "ND=%D85%" & goto dispscaler_set )
if "!ds!"=="2" ( set "NW=%W75%" & set "NH=%H75%" & set "ND=%D75%" & goto dispscaler_set )
if "!ds!"=="3" ( set "NW=%W67%" & set "NH=%H67%" & set "ND=%D67%" & goto dispscaler_set )
if "!ds!"=="4" ( set "NW=%W50%" & set "NH=%H50%" & set "ND=%D50%" & goto dispscaler_set )
if "!ds!"=="5" goto dispscaler_custom
if "!ds!"=="6" goto dispscaler_dpi
if "!ds!"=="7" goto dispscaler_reset
if "!ds!"=="8" goto Gaming
goto dispscaler_ask

:dispscaler_set
:: expects NW NH ND set by the caller
cls
title Display Scaler : apply
call :logo
echo  About to set:
echo     Resolution : %g%%NW%x%NH%%w%   (native %PW%x%PH%)
echo     Density    : %g%%ND% dpi%w%   (native %PD%)
echo.
echo  %y%The UI keeps the same size%w% - only the render resolution changes,
echo  so games get more GPU headroom and the panel uses less power. A
echo  lower resolution looks slightly softer. Fully reversible.
echo.
echo  %g%Applied over USB%w% - even if the screen looks wrong you can come
echo  straight back here and choose Reset.
echo.
echo    [Y] Apply    [N] Cancel
choice /c:YN /n >nul
if errorlevel 2 goto dispscaler
adb shell wm size %NW%x%NH% <nul
adb shell wm density %ND% <nul
echo.
echo  Applied. If anything looks off, come back and choose Reset.
pause >nul
goto dispscaler

:dispscaler_custom
cls
title Display Scaler : custom
call :logo
echo  Native resolution: %g%%PW%x%PH%%w%    native density: %g%%PD% dpi%w%
echo.
echo  Enter a custom WIDTH, HEIGHT and DENSITY. Tip: keep the same
echo  width:height ratio as native to avoid stretching, and scale density
echo  by the same factor to keep the UI size consistent.
echo.
:: FIX (reserved name): this used a variable literally called CD. %CD% is cmd's DYNAMIC
:: current-directory pseudo-variable, and a real environment variable of that name
:: SHADOWS it - for the rest of the session and, because the environment is inherited,
:: inside every child process DCX spawns (notepad, powershell, the restore/undo .bat it
:: runs through `cmd /c`). Nothing in DCX reads %CD% as a path today, so this was latent
:: rather than broken - but a density like "320" masquerading as the working directory is
:: the kind of thing that is invisible until it is very confusing. Renamed to CDPI.
set "CW=" & set "CH=" & set "CDPI="
set /p "CW=Width  (blank = cancel) >> "
if "!CW!"=="" goto dispscaler
set /p "CH=Height (blank = cancel) >> "
if "!CH!"=="" goto dispscaler
set "CDPI=" & set /p "CDPI=Density dpi (blank = cancel) >> "
if "!CDPI!"=="" goto dispscaler
echo !CW!| findstr /r "^[1-9][0-9]*$" >nul || goto dispscaler_custom_bad
echo !CH!| findstr /r "^[1-9][0-9]*$" >nul || goto dispscaler_custom_bad
echo !CDPI!| findstr /r "^[1-9][0-9]*$" >nul || goto dispscaler_custom_bad
:: sane bounds so a typo can't leave the UI unusable
if %CW% LSS 320 goto dispscaler_custom_bad
if %CH% LSS 320 goto dispscaler_custom_bad
if %CW% GTR 8000 goto dispscaler_custom_bad
if %CH% GTR 8000 goto dispscaler_custom_bad
if %CDPI% LSS 80 goto dispscaler_custom_bad
if %CDPI% GTR 900 goto dispscaler_custom_bad
set "NW=%CW%" & set "NH=%CH%" & set "ND=%CDPI%"
goto dispscaler_set

:dispscaler_custom_bad
echo [%r%^^!%w%] Invalid values. Width/height 320-8000, density 80-900, digits only.
timeout /t 2 /nobreak >nul
goto dispscaler_custom
:: -------------------------------------------------------------------
:: UI size (DPI only) - changes element size WITHOUT touching the
:: resolution. This is the working stand-in for the developer-options
:: "Smallest width" entry, which some OEMs (notably Huawei EMUI/
:: HarmonyOS) leave present but non-functional. Lower dpi = smaller UI
:: / more content. Presets are a percentage of the panel's native
:: density, so 85%% lands on the common 'stock UI is too big' fix.
:: -------------------------------------------------------------------
:dispscaler_dpi
cls
title Display Scaler : UI size (DPI)
call :logo
:: Re-read the panel's native (physical) density as the 100%% baseline.
set "PDR=" & set "PD=" & set "OVRD="
for /f "tokens=2 delims=:" %%a in ('adb shell wm density ^<nul 2^>nul ^| findstr /C:"Physical density"') do set "PDR=%%a"
for /f "tokens=* delims= " %%a in ("%PDR%") do set "PD=%%a"
for /f "tokens=2 delims=:" %%a in ('adb shell wm density ^<nul 2^>nul ^| findstr /C:"Override density"') do set "OVRD=%%a"
if not defined PD goto dispscaler_err
echo !PD!| findstr /r "[^0-9]" >nul && goto dispscaler_err
set /a U110=PD*110/100, U90=PD*90/100, U85=PD*85/100, U80=PD*80/100
echo.
echo  Changes ONLY the DPI (UI element size); resolution stays native.
echo  This is the reliable replacement for the developer-options
echo  "Smallest width" entry that some OEMs (e.g. Huawei) disable.
echo.
echo  Native density (100%% UI) : %g%%PD% dpi%w%
if defined OVRD echo  Active override           : %gold%%OVRD% dpi%w%
echo.
echo  Lower %% = smaller UI, more content fits.
echo.
echo                    %g%[%w%1%g%]%w% 110%% UI -^> %U110% dpi   (bigger)
echo                    %g%[%w%2%g%]%w% 100%% UI -^> %PD% dpi   (native)
echo                    %g%[%w%3%g%]%w% 90%%  UI -^> %U90% dpi
echo                    %g%[%w%4%g%]%w% 85%%  UI -^> %U85% dpi   (fix for over-large stock UI)
echo                    %g%[%w%5%g%]%w% 80%%  UI -^> %U80% dpi   (smallest)
echo                    %g%[%w%6%g%]%w% Custom dpi
echo                    %g%[%w%7%g%]%w% Reset to native dpi
echo                    %g%[%w%8%g%]%w% Back

:dispscaler_dpi_ask
:: FIX (input "eaten" / press-twice): same tight re-ask as :dispscaler - absorb a
:: phantom empty read so the first keypress registers, and don't re-run the
:: density probe on stray keys. Preset vars (U110.. PD) stay in scope.
set "du="
set /p du="Choose An Option >> "
if not defined du goto dispscaler_dpi_ask
if "!du!"=="1" ( set "ND=%U110%" & goto dispscaler_dpi_set )
if "!du!"=="2" ( set "ND=%PD%" & goto dispscaler_dpi_set )
if "!du!"=="3" ( set "ND=%U90%" & goto dispscaler_dpi_set )
if "!du!"=="4" ( set "ND=%U85%" & goto dispscaler_dpi_set )
if "!du!"=="5" ( set "ND=%U80%" & goto dispscaler_dpi_set )
if "!du!"=="6" goto dispscaler_dpi_custom
if "!du!"=="7" goto dispscaler_dpi_reset
if "!du!"=="8" goto dispscaler
goto dispscaler_dpi_ask

:dispscaler_dpi_set
:: expects ND (target density) set by the caller
cls
title Display Scaler : apply UI size
call :logo
echo  About to set density to %g%%ND% dpi%w%   (native %PD%), resolution unchanged.
echo.
echo  Lower dpi = smaller UI / more content. Fully reversible, no root.
echo  %g%Applied over USB%w% - if it looks wrong, come back and Reset.
echo.
echo    [Y] Apply    [N] Cancel
choice /c:YN /n >nul
if errorlevel 2 goto dispscaler_dpi
adb shell wm density %ND% <nul
echo.
echo  Done - density is now %ND% dpi. This persists across reboot.
pause >nul
goto dispscaler_dpi

:dispscaler_dpi_custom
cls
title Display Scaler : custom dpi
call :logo
echo  Native density: %g%%PD% dpi%w%   (lower = smaller UI, higher = bigger)
echo.
:: CDPI, not CD - see the note in :dispscaler_custom (%CD% is cmd's current directory).
set "CDPI="
set /p "CDPI=Density dpi (blank = cancel) >> "
if "!CDPI!"=="" goto dispscaler_dpi
echo !CDPI!| findstr /r "^[1-9][0-9]*$" >nul || goto dispscaler_dpi_custom_bad
if %CDPI% LSS 80 goto dispscaler_dpi_custom_bad
if %CDPI% GTR 900 goto dispscaler_dpi_custom_bad
set "ND=%CDPI%"
goto dispscaler_dpi_set

:dispscaler_dpi_custom_bad
echo [%r%^^!%w%] Invalid density. Use a whole number 80-900.
timeout /t 2 /nobreak >nul
goto dispscaler_dpi_custom

:dispscaler_dpi_reset
cls
title Display Scaler : reset dpi
call :logo
echo  Restoring native density (%PD% dpi)...
adb shell wm density reset <nul
adb shell settings delete secure display_density_forced <nul > nul 2>&1
echo.
echo  %y%Heads up:%w% native density can be larger than you like on some
echo  phones. If the UI is now too big, pick a UI-size preset above
echo  (e.g. 85%%) instead of leaving it at native.
pause >nul
goto dispscaler_dpi

:dispscaler_reset
cls
title Display Scaler : reset
call :logo
echo  Restoring the panel's native resolution and density...
adb shell wm size reset <nul
adb shell wm density reset <nul
:: Some OEM builds (notably Huawei EMUI/HarmonyOS, and older Sony/LG)
:: do NOT actually clear the forced override on 'reset' - the value is
:: left behind in the settings DB and survives a reboot. Delete the
:: backing keys directly so the native size/density really come back.
adb shell settings delete global display_size_forced <nul > nul 2>&1
adb shell settings delete secure display_density_forced <nul > nul 2>&1
echo.
echo  Done - back to native (%PW%x%PH% @ %PD% dpi).
echo  %y%If the UI still looks the wrong size, reboot once to apply.%w%
pause >nul
goto dispscaler

:dispscaler_err
cls
title Display Scaler
call :logo
echo [%r%^^!%w%] Could not read the display size/density from this device.
echo     'wm size' / 'wm density' returned something unexpected, so the
echo     presets can't be computed safely.
echo.
echo  You can still force a manual reset:
echo     adb shell wm size reset
echo     adb shell wm density reset
echo.
echo Press Any Button To Go Back
pause >nul
goto Gaming
:: ===================================================================
:: NEW: GPU Renderer toggle (REAL Android property `debug.hwui.renderer`)
:: This is the actual HWUI pipeline switch. Valid values:
::   skiagl   - Skia OpenGL  (Android default since 9)
::   skiavk   - Skia Vulkan  (works Android 13+, may be unstable on
::                            some GPUs / cause blurry fonts)
::   <empty>  - let the framework pick the default
:: WARNING on non-rooted devices: setprop applies live but does NOT
:: survive reboot. To make it permanent without root, the value must
:: be set in /system/build.prop (requires root or a Magisk module).
:: ===================================================================
:gpurenderer
cls
title GPU Renderer (HWUI)
call :logo
echo.
echo  Current value:
for /f "delims=" %%i in ('adb shell getprop debug.hwui.renderer 2^>nul ^<nul') do echo    debug.hwui.renderer = "%%i"
echo.
echo  This switches the HWUI rendering pipeline used by the system UI
echo  and most apps that draw with the framework.
echo.
echo    skiavk = Skia + Vulkan        (faster on Android 13+, may have
echo                                   font/scroll artefacts on weak GPUs)
echo    skiagl = Skia + OpenGL ES     (default, most compatible)
echo.
echo  %y%Note:%w% on non-rooted phones the change is live but resets on reboot.
echo.
echo                                     %g%[%w%1%g%]%w% Skia Vulkan (skiavk)
echo                                     %g%[%w%2%g%]%w% Skia OpenGL  (skiagl - default)
echo                                     %g%[%w%3%g%]%w% Clear override (let framework decide)
echo                                     %g%[%w%4%g%]%w% Back
set "gpur=" & set /p gpur="Choose An Option >> "
if "!gpur!"=="1" goto gpurenderer_vk
if "!gpur!"=="2" goto gpurenderer_gl
if "!gpur!"=="3" goto gpurenderer_clear
if "!gpur!"=="4" goto Gaming
goto gpurenderer

:gpurenderer_vk
cls
title GPU Renderer : Skia Vulkan
adb shell setprop debug.hwui.renderer skiavk <nul
adb shell setprop debug.renderengine.backend skiavkthreaded <nul
echo Renderer set to skiavk (Skia + Vulkan).
echo.
echo To verify after relaunching an app:
echo   adb shell dumpsys gfxinfo ^<package^> ^| findstr Pipeline
echo Expected: "Skia (Vulkan)"
echo.
echo A reboot - or at least restarting SystemUI - is needed for the
echo change to take full effect.
pause > nul
goto gpurenderer

:gpurenderer_gl
cls
title GPU Renderer : Skia GL
adb shell setprop debug.hwui.renderer skiagl <nul
adb shell setprop debug.renderengine.backend skiaglthreaded <nul
echo Renderer set to skiagl (Skia + OpenGL ES, default).
pause > nul
goto gpurenderer

:gpurenderer_clear
cls
title GPU Renderer : Clear
:: An empty value makes Android fall back to the framework default.
:: '' not "" - with "" the quotes never reach the device and setprop just prints
:: its usage text, so "Clear override" used to report success and clear nothing.
:: See the note under :_sf_clear_props.
adb shell setprop debug.hwui.renderer '' <nul
adb shell setprop debug.renderengine.backend '' <nul
echo Renderer override cleared. Framework default in effect after reboot.
pause > nul
goto gpurenderer
:: ===================================================================
:: NEW: Force ANGLE for All Apps (REAL Settings.Global setting)
:: ANGLE is Google's GLES-on-Vulkan translation layer. Enabling it
:: forces apps that use OpenGL ES to actually run through Vulkan -
:: better performance on modern GPUs, more consistent behaviour.
:: This is the OFFICIAL Android way (per AOSP docs):
::   settings put global angle_gl_driver_all_angle 1   (on)
::   settings put global angle_gl_driver_all_angle 0   (off)
:: Setting PERSISTS across reboots, unlike the renderer toggle above.
:: Caveats:
::   - Requires the GoogleANGLE APK to be installed (most modern Android
::     ships with it as a system app; Android 16+ uses ANGLE by default
::     for many apps anyway).
::   - On non-root, only debuggable apps will actually load ANGLE -
::     others fall back to native. So benefit is partial.
::   - A few games are known to break under ANGLE; disable if you see
::     glitches in a specific game.
:: ===================================================================
:angleall
cls
title Force ANGLE for All Apps
call :logo
echo.
echo  Current value:
for /f "delims=" %%i in ('adb shell settings get global angle_gl_driver_all_angle 2^>nul ^<nul') do echo    angle_gl_driver_all_angle = %%i  (1=ON, 0=OFF, null=default)
echo.
echo  Forces every GLES app to load through ANGLE (GLES-on-Vulkan).
echo.
echo  %r%WARNING - device compatibility risk:%w%
echo  On many non-Pixel devices (especially MediaTek GPUs) this CRASHES
echo  apps on launch. It has been reported to break most apps on some
echo  phones. Only enable it if you are ready to revert.
echo.
echo  %y%The setting persists across reboots - a reboot will NOT fix a%w%
echo  %y%crash loop. You must come back here and Disable/Delete it.%w%
echo.
echo                                     %g%[%w%1%g%]%w% Enable  (ANGLE for all apps)
echo                                     %g%[%w%2%g%]%w% Disable (native driver)
echo                                     %g%[%w%3%g%]%w% Delete setting (Android default)
echo                                     %g%[%w%4%g%]%w% Back
set "ang=" & set /p ang="Choose An Option >> "
if "!ang!"=="1" goto angleall_on
if "!ang!"=="2" goto angleall_off
if "!ang!"=="3" goto angleall_del
if "!ang!"=="4" goto Gaming
goto angleall

:angleall_on
cls
title ANGLE for All Apps : ON (confirm)
echo  %r%Are you sure?%w% On some devices this crashes most apps and can
echo  only be undone from this menu (a reboot will not help).
echo.
echo  Tip: test a few apps right after enabling. If they crash, come
echo  straight back and choose Disable or Delete.
echo.
echo    [Y] Enable ANGLE now
echo    [N] Cancel
choice /c:YN /n > nul
if errorlevel 2 goto angleall
adb shell settings put global angle_gl_driver_all_angle 1 <nul
echo.
call :_act_reset
call :_settings_verify global angle_gl_driver_all_angle 1
call :_act_summary
echo If apps start crashing, return here and Disable/Delete.
pause > nul
goto angleall

:angleall_off
cls
title ANGLE for All Apps : OFF
adb shell settings put global angle_gl_driver_all_angle 0 <nul
call :_act_reset
call :_settings_verify global angle_gl_driver_all_angle 0
call :_act_summary
pause > nul
goto angleall

:angleall_del
cls
title ANGLE for All Apps : Delete (default)
adb shell settings delete global angle_gl_driver_all_angle <nul
call :_act_reset
call :_settings_verify global angle_gl_driver_all_angle DELETE
call :_act_summary
pause > nul
goto angleall
:: ===================================================================
:: NEW FEATURE: Network Boost
:: Tunes TCP buffers and DNS for lower latency in online games.
:: All changes are non-destructive (settings put global) and can be
:: undone with option [4] which deletes the keys.
:: ===================================================================
:netboost
cls
title Network Boost
call :logo
echo.
echo  TCP init-window hint + private DNS + preferred network mode.
echo  Modest effect - not a magic latency boost. DNS often helps more than TCP.
echo  %y%Note:%w% old Wi-Fi power tweaks were removed (could break Wi-Fi on
echo  Android 15). Revert still clears any leftovers from an old run.
echo.
echo                                     %g%[%w%1%g%]%w% Apply TCP hint (safe)
echo                                     %g%[%w%2%g%]%w% Private DNS (pick a provider, or your own)
echo                                     %g%[%w%3%g%]%w% Preferred network mode
echo                                     %g%[%w%4%g%]%w% Revert (remove all)
echo                                     %g%[%w%5%g%]%w% Back
set "nb=" & set /p nb="Choose An Option >> "
if "!nb!"=="1" goto netboost_apply
if "!nb!"=="2" goto netboost_dns
if "!nb!"=="3" goto netboost_prefmode
if "!nb!"=="4" goto netboost_revert
if "!nb!"=="5" goto Gaming
goto netboost
:: -----------------------------------------------------------------
:: NEW: Preferred network mode toggle
:: The .sh script had `persist.radio.force_lte true` and similar -
:: these are FAKE. The real Android setting is:
::   settings put global preferred_network_mode N
:: Common values (from Android source, RILConstants.java):
::   9  = LTE / GSM / WCDMA      (LTE preferred, fall back to 3G/2G)
::   12 = LTE only
::   20 = LTE / NR / WCDMA       (5G preferred, fall back to LTE/3G)
::   1  = GSM only (2G)
:: Note: some operators / SIM cards override this on the radio side.
:: Both `preferred_network_mode` (legacy/default) and `..._mode1` are
:: written ON PURPOSE: the suffixed key is per-SUBSCRIPTION and subIds
:: are 1-based, so mode1 is the FIRST SIM's usual subId - not a second
:: slot. On devices where the active subId isn't 1 (SIM swaps bump it)
:: the extra key is inert, and "Restore default" deletes both keys, so
:: this stays fully reversible either way.
:: -----------------------------------------------------------------
:netboost_prefmode
cls
title Network Boost : Preferred mode
call :logo
echo  Current preferred_network_mode:
for /f "delims=" %%i in ('adb shell settings get global preferred_network_mode 2^>nul ^<nul') do echo    %%i
echo.
echo                                     %g%[%w%1%g%]%w% LTE preferred (9)  -^> fall back 3G/2G
echo                                     %g%[%w%2%g%]%w% LTE only (12)
echo                                     %g%[%w%3%g%]%w% 5G preferred (20)  -^> fall back LTE/3G
echo                                     %g%[%w%4%g%]%w% Restore default (delete)
echo                                     %g%[%w%5%g%]%w% Back
set "pm=" & set /p pm="Choose An Option >> "
if "!pm!"=="1" (
    adb shell settings put global preferred_network_mode 9 <nul
    adb shell settings put global preferred_network_mode1 9 <nul
    call :_act_reset
    call :_settings_verify global preferred_network_mode 9
    call :_act_summary
    pause > nul
    goto netboost_prefmode
)
if "!pm!"=="2" (
    adb shell settings put global preferred_network_mode 12 <nul
    adb shell settings put global preferred_network_mode1 12 <nul
    call :_act_reset
    call :_settings_verify global preferred_network_mode 12
    call :_act_summary
    echo WARNING: voice calls only work if VoLTE is active.
    pause > nul
    goto netboost_prefmode
)
if "!pm!"=="3" (
    adb shell settings put global preferred_network_mode 20 <nul
    adb shell settings put global preferred_network_mode1 20 <nul
    call :_act_reset
    call :_settings_verify global preferred_network_mode 20
    call :_act_summary
    pause > nul
    goto netboost_prefmode
)
if not "!pm!"=="4" goto _skpm4
    adb shell settings delete global preferred_network_mode <nul
    adb shell settings delete global preferred_network_mode1 <nul
    call :_act_reset
    call :_settings_verify global preferred_network_mode DELETE
    call :_act_summary
    pause > nul
    goto netboost_prefmode

:_skpm4
if "!pm!"=="5" goto netboost
goto netboost_prefmode

:netboost_apply
cls
title Network Boost : Apply
echo Applying TCP receive-window hint...
echo.
:: IMPORTANT: earlier versions also wrote several Wi-Fi power keys
:: (wifi_sleep_policy, wifi_suspend_optimizations_enabled, wifi_idle_ms,
:: mobile_data_always_on, tether_offload_disabled). Those are DEPRECATED
:: Settings.Global keys and were found to BREAK Wi-Fi connectivity on
:: Android 15 (Tecno/MediaTek) - a reboot did not recover it, only
:: reverting did. They have been removed from this step. Revert still
:: clears them so anyone who applied the old version can clean up.
::
:: What remains is the one genuinely safe, real key: the initial TCP
:: receive window. Effect is modest; it does not touch the Wi-Fi stack.
adb shell "settings put global tcp_default_init_rwnd 60" <nul > nul 2>&1
call :_act_reset
call :_settings_verify global tcp_default_init_rwnd 60
call :_act_summary
echo.
echo This change is safe and does not alter Wi-Fi behaviour.
echo If you want lower latency, the DNS option (Cloudflare) often helps
echo more than buffer tuning on modern networks.
pause > nul
goto netboost

:ShowPrivateDns
:: Prints what Private DNS is set to right now, before anything offers to change it.
:: `settings get` returns the literal string "null" for an unset key, which is not the same
:: as "off" - saying so beats printing a bare null and letting the user guess.
set "_pdmode=" & set "_pdspec="
for /f "delims=" %%i in ('adb shell settings get global private_dns_mode 2^>nul ^<nul')      do set "_pdmode=%%i"
for /f "delims=" %%i in ('adb shell settings get global private_dns_specifier 2^>nul ^<nul') do set "_pdspec=%%i"
if not defined _pdmode set "_pdmode=null"
if /i "!_pdmode!"=="null" (
    echo   Currently: not set - the device is using its default
) else if /i "!_pdmode!"=="hostname" (
    if /i "!_pdspec!"=="null" set "_pdspec=none stored"
    echo   Currently: hostname mode -^> !_pdspec!
) else (
    echo   Currently: !_pdmode!
)
goto :eof

:_host_ok
:: Validates !_HCHK! as a DNS-over-TLS hostname; errorlevel 1 if it is not one.
::
:: This is free text the user types, on its way into an adb command line - the same shape
:: that let a package name containing ^& ^| ^< ^> be parsed as an operator instead of passed
:: as data. Charset first, so no metacharacter survives; every use afterwards is delayed
:: (!var!) so even that stays literal. The required dot is the correctness half: a DoT
:: server is a domain name, and catching a single label here beats a confusing failure
:: from Android two screens later.
::
:: PIPE-FREE ON PURPOSE - see the long note in :_pkg_ok. The old `echo(!_HCHK!| findstr`
:: form reported a hostname containing "&" as VALID and executed the tail of it inside
:: the pipe, so the guard this comment describes was not actually being enforced.
if not defined _HCHK exit /b 1
set "_HCHK=!_HCHK:"=!"
if not defined _HCHK exit /b 1
set "_h_bad="
for /f "delims=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" %%c in ("!_HCHK!") do set "_h_bad=%%c"
if defined _h_bad exit /b 1
:: a DoT server is a domain name - require at least one dot
if "!_HCHK!"=="!_HCHK:.=!" exit /b 1
:: must start with a letter or digit, not a dot or a hyphen
set "_h_bad="
for /f "delims=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" %%c in ("!_HCHK:~0,1!") do set "_h_bad=%%c"
if defined _h_bad exit /b 1
exit /b 0

:netboost_dns
cls
title Network Boost : Private DNS
call :logo
echo.
echo   Private DNS (DNS-over-TLS). Encrypts lookups and applies system-wide, on
echo   Wi-Fi and mobile data alike. It is a device setting, not a per-app one.
echo.
call :ShowPrivateDns
echo.
echo                                     %g%[%w%1%g%]%w% Cloudflare   one.one.one.one
echo                                     %g%[%w%2%g%]%w% Google       dns.google
echo                                     %g%[%w%3%g%]%w% AdGuard      dns.adguard.com   (blocks ads/trackers)
echo                                     %g%[%w%4%g%]%w% Quad9        dns.quad9.net     (blocks known-malicious)
echo                                     %g%[%w%5%g%]%w% Custom hostname
echo                                     %g%[%w%6%g%]%w% Automatic (device default)
echo                                     %g%[%w%0%g%]%w% Back
echo.
echo   %y%If your network blocks external DNS, lookups can fail entirely.%w%
echo   Option 6 puts it straight back - you do not need Revert, which also
echo   removes the TCP and network-mode changes.
echo.
set "pd=" & set /p pd="Choose >> "
if "!pd!"=="1" ( set "_pdhost=one.one.one.one"  & goto _pdns_apply )
if "!pd!"=="2" ( set "_pdhost=dns.google"       & goto _pdns_apply )
if "!pd!"=="3" ( set "_pdhost=dns.adguard.com"  & goto _pdns_apply )
if "!pd!"=="4" ( set "_pdhost=dns.quad9.net"    & goto _pdns_apply )
if "!pd!"=="5" goto _pdns_custom
if "!pd!"=="6" goto _pdns_auto
if "!pd!"=="0" goto netboost
goto netboost_dns

:_pdns_custom
echo.
echo   Enter the DoT hostname your provider gave you - for example dns.nextdns.io
echo   or a personal resolver. Letters, digits, dots and hyphens only.
echo.
set "_pdhost=" & set /p _pdhost="Hostname (blank = cancel) >> "
if not defined _pdhost goto netboost_dns
set "_HCHK=!_pdhost!"
call :_host_ok || (
    echo.
    echo  [%r%x%w%] That is not a hostname. Letters, digits, dots and hyphens, and it
    echo      needs at least one dot - dns.google, not just "google".
    pause > nul
    goto netboost_dns
)

:_pdns_apply
echo.
echo Setting Private DNS to !_pdhost! . . .
adb shell settings put global private_dns_mode hostname <nul
adb shell settings put global private_dns_specifier !_pdhost! <nul
call :_act_reset
call :_settings_verify global private_dns_mode hostname
call :_settings_verify global private_dns_specifier !_pdhost!
call :_act_summary
echo.
call :ShowPrivateDns
echo.
pause > nul
goto netboost_dns

:_pdns_auto
:: The DNS half of Revert on its own. Reverting used to be reachable only through
:: "Revert (remove all)", which also strips the TCP hint, the network mode and the Wi-Fi
:: keys - so undoing one DNS experiment quietly undid four other things too.
echo.
echo Restoring automatic DNS . . .
adb shell settings put global private_dns_mode opportunistic <nul
adb shell settings delete global private_dns_specifier <nul
call :_act_reset
call :_settings_verify global private_dns_mode opportunistic
call :_act_summary
echo.
call :ShowPrivateDns
echo.
pause > nul
goto netboost_dns

:netboost_revert
cls
title Network Boost : Revert
adb shell settings delete global tcp_default_init_rwnd <nul > nul 2>&1
adb shell settings delete global tether_offload_disabled <nul > nul 2>&1
adb shell settings delete global mobile_data_always_on <nul > nul 2>&1
adb shell settings delete global wifi_idle_ms <nul > nul 2>&1
adb shell settings delete global wifi_suspend_optimizations_enabled <nul > nul 2>&1
adb shell settings delete global wifi_sleep_policy <nul > nul 2>&1
adb shell settings put global private_dns_mode opportunistic <nul > nul 2>&1
adb shell settings delete global private_dns_specifier <nul > nul 2>&1
adb shell settings delete global preferred_network_mode <nul > nul 2>&1
adb shell settings delete global preferred_network_mode1 <nul > nul 2>&1
call :_act_reset
call :_settings_verify global tcp_default_init_rwnd DELETE
call :_settings_verify global private_dns_mode opportunistic
call :_act_summary
pause > nul
goto netboost
:: gms
:gms
@echo off
cls
title Toggle GMS
call :logo
echo.
echo  Full Off disables Play Services itself and breaks most Google-dependent apps.
echo  Safe subset only disables ads/telemetry-adjacent packages and keeps GMS running.
echo.
echo [%r%1%w%] Disable GMS entirely ^(dangerous^)
echo [%r%2%w%] Enable GMS ^(undo full Off^)
echo [%g%3%w%] Safe subset Off - ads/telemetry packages only
echo [%g%4%w%] Safe subset On  - re-enable those packages
echo [%r%5%w%] Back
set "toggle=" & set /p toggle="Choose An Option >> "
if "!toggle!"=="1" goto offgms
if "!toggle!"=="2" goto ongms
if "!toggle!"=="3" goto gms_safe_off
if "!toggle!"=="4" goto gms_safe_on
if "!toggle!"=="5" goto Gaming
goto gms

:offgms
@echo off
cls
title GMS : Off (confirmation)
echo.
echo  %r%========================== WARNING ==========================%w%
echo.
echo   Disabling Google Mobile Services will break most apps that
echo   rely on Google Play Services, including:
echo.
echo     - Push notifications (WhatsApp, Telegram, Gmail, banking)
echo     - Google Maps and any app using its location services
echo     - Sign-in via Google in third-party apps
echo     - In-app purchases, ads, Firebase, Crashlytics
echo     - Find My Device, Google Pay, Play Store updates
echo.
echo   %y%Only proceed if you understand the impact.%w%
echo.
echo  %r%=============================================================%w%
echo.
echo  [%g%Y%w%] Yes, disable GMS now
echo  [%g%N%w%] No, take me back
choice /c:YN /n > nul
if errorlevel 2 goto Gaming
cls
title GMS : Off
adb shell am force-stop com.google.android.gms <nul
adb shell pm disable-user --user 0 com.google.android.gms <nul
:: zen_mode intentionally NOT touched - earlier builds forced DND (zen_mode 2)
:: on Off and cleared it on On, which overwrote the user's Do Not Disturb state.
adb shell cmd appops set com.google.android.gms RUN_ANY_IN_BACKGROUND ignore <nul
adb shell cmd appops set com.google.android.gms RUN_IN_BACKGROUND ignore <nul
adb shell cmd appops set com.google.android.gms WAKE_LOCK ignore <nul
adb shell cmd appops set com.google.android.gms START_FOREGROUND ignore <nul
adb shell cmd appops set com.google.android.gms INSTANT_APP_START_FOREGROUND ignore <nul
adb shell am set-inactive --user 0 com.google.android.gms true <nul
adb shell am set-standby-bucket --user 0 com.google.android.gms never <nul
echo.
adb shell pm list packages -d <nul 2>nul | find /v "" | findstr /x /c:"package:com.google.android.gms" >nul
if not errorlevel 1 (
    echo [%g%+%w%] com.google.android.gms is disabled-user.
) else (
    echo [%y%WARN%w%] GMS not listed as disabled - OEM may have blocked the disable.
)
echo Press Any Button To Go Back
pause > nul
goto Gaming

:ongms
@echo off
cls
adb shell pm enable com.google.android.gms <nul
adb shell cmd appops set com.google.android.gms RUN_ANY_IN_BACKGROUND allow <nul
adb shell cmd appops set com.google.android.gms RUN_IN_BACKGROUND allow <nul
adb shell cmd appops set com.google.android.gms WAKE_LOCK allow <nul
adb shell cmd appops set com.google.android.gms START_FOREGROUND allow <nul
adb shell cmd appops set com.google.android.gms INSTANT_APP_START_FOREGROUND allow <nul
adb shell am set-inactive --user 0 com.google.android.gms false <nul
adb shell am set-standby-bucket --user 0 com.google.android.gms active <nul
title GMS : On
echo.
adb shell pm list packages -d <nul 2>nul | find /v "" | findstr /x /c:"package:com.google.android.gms" >nul
if errorlevel 1 (
    echo [%g%+%w%] com.google.android.gms is enabled.
) else (
    echo [%y%WARN%w%] GMS still listed as disabled - enable may not have landed.
)
echo Press Any Button To Go Back
pause > nul
goto Gaming
:: ===================================================================
:: GMS safe subset - ads/telemetry-adjacent packages only.
:: Keeps com.google.android.gms enabled. Only acts on packages that are
:: actually installed. Reversible via Safe subset On.
:: ===================================================================
:gms_safe_off
cls
title GMS safe subset : Off
call :logo
echo.
echo  Will disable-user these packages if installed ^(Play Services stays up^):
echo    adservices.api, as.oss, mainline.telemetry, mainline.adservices,
echo    federatedcompute, partnersetup, feedback, apps.turbo
echo.
echo  [%g%Y%w%] Disable them now    [%g%N%w%] Cancel
choice /c:YN /n >nul
if errorlevel 2 goto gms
call :_act_reset
call :_gms_safe_one disable-user com.google.android.adservices.api
call :_gms_safe_one disable-user com.google.android.as.oss
call :_gms_safe_one disable-user com.google.mainline.telemetry
call :_gms_safe_one disable-user com.google.mainline.adservices
call :_gms_safe_one disable-user com.google.android.federatedcompute
call :_gms_safe_one disable-user com.google.android.partnersetup
call :_gms_safe_one disable-user com.google.android.feedback
call :_gms_safe_one disable-user com.google.android.apps.turbo
call :_act_summary
echo.
echo  Play Services ^(com.google.android.gms^) was not touched.
pause >nul
goto gms

:gms_safe_on
cls
title GMS safe subset : On
call :logo
echo.
echo  Re-enabling the safe-subset packages if present...
echo.
call :_act_reset
call :_gms_safe_one enable com.google.android.adservices.api
call :_gms_safe_one enable com.google.android.as.oss
call :_gms_safe_one enable com.google.mainline.telemetry
call :_gms_safe_one enable com.google.mainline.adservices
call :_gms_safe_one enable com.google.android.federatedcompute
call :_gms_safe_one enable com.google.android.partnersetup
call :_gms_safe_one enable com.google.android.feedback
call :_gms_safe_one enable com.google.android.apps.turbo
call :_act_summary
pause >nul
goto gms

:_gms_safe_one
:: %1 = disable-user ^| enable    %2 = package
adb shell pm list packages 2>nul <nul | find /v "" | findstr /x /c:"package:%~2" >nul
if errorlevel 1 (
    echo  skip  %~2 ^(not installed^)
    exit /b 0
)
if /i "%~1"=="enable" (
    adb shell pm enable --user 0 %~2 <nul >nul 2>&1
) else (
    adb shell pm disable-user --user 0 %~2 <nul >nul 2>&1
)
if errorlevel 1 (
    echo  [%r%FAIL%w%] %~1 %~2
    set /a DCX_VFAIL+=1
    exit /b 1
)
echo  [%g%OK%w%] %~1 %~2
set /a DCX_VOK+=1
exit /b 0
:: thermal
:thermal
@echo off
cls
title Thermal override (temporary)
echo.
echo.
echo  Temporary thermalservice override-status ^(usually clears on reboot^).
echo  Not a permanent cooling profile.
echo.
echo [%r%1%w%] Process To Setting Thermal
echo [%r%2%w%] Go Back
set "kb=" & set /p kb="Choose An Option >> "
if "!kb!"=="1" goto settingthermal
if "!kb!"=="2" goto Gaming
:: FIX: guard against invalid input - previously fell through to :settingthermal
goto thermal

:settingthermal
@echo off
cls
echo Put A Number Between 0 To 6 To Change
echo How Thermal Service Work^^!
echo.
echo  0 = NONE     (no throttling)
echo  1 = LIGHT
echo  2 = MODERATE
echo  3 = SEVERE
echo  4 = CRITICAL
echo  5 = EMERGENCY
echo  6 = SHUTDOWN (do not use)
echo.
set "kb=" & set /p kb=">> "
:: FIX: validate input - previously any garbage was accepted
set "valid=0"
for %%v in (0 1 2 3 4 5 6) do if "!kb!"=="%%v" set "valid=1"
if "%valid%"=="0" (
    echo [%r%^^!%w%] Invalid value. Must be a number between 0 and 6.
    timeout /t 2 /nobreak > nul
    goto thermal
)
cls
adb shell cmd thermalservice override-status %kb% <nul
echo Press Any Button To Go Back.
pause > nul
goto Gaming
:: Package verifier
:package
@echo off
cls
title Toggle Package Verifier
echo.
echo.
echo Toggle Your Package Verifier Here
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "kb=" & set /p kb="Choose An Option >> "
if "!kb!"=="1" goto offpck
if "!kb!"=="2" goto onpck
if "!kb!"=="3" goto Gaming
:: guard against invalid input
goto package

:offpck
@echo off
cls
title Package Verifier : Off
adb shell settings put global package_verifier_enable 0 <nul
call :_act_reset
call :_settings_verify global package_verifier_enable 0
call :_act_summary
echo Press Any Button To Go Back
pause > nul
goto Gaming

:onpck
@echo off
cls
title Package Verifier : On
adb shell settings put global package_verifier_enable 1 <nul
call :_act_reset
call :_settings_verify global package_verifier_enable 1
call :_act_summary
echo Press Any Button To Go Back
pause > nul
goto Gaming
:: game-overlay
:overlay
@echo off
cls
title Setting Game-Overlay
echo.
echo.
echo %b%[Remove]%w%  1
echo %b%[Low]%w%     2   (downscale 0.55)
echo %b%[Medium]%w%  3   (downscale 0.75)
echo %b%[Back]  %w%  4
set "kb=" & set /p kb="Choose An Option >> "
if "!kb!"=="1" goto removeset
if "!kb!"=="2" goto low
if "!kb!"=="3" goto med
if "!kb!"=="4" goto Gaming
:: guard against invalid input
goto overlay

:removeset
cls
title Remove Settings
set "package=" & set /p package="Put Your Package Name Here >> "
if "!package!"=="" goto Gaming
set "_PKGCHK=!package!"
call :_pkg_ok || (
    echo  [%r%x%w%] Invalid package name. Letters, digits, dots and underscores only.
    timeout /t 2 /nobreak > nul
    goto Gaming
)
adb shell device_config delete game_overlay !package! <nul > nul
adb shell cmd game reset --user 0 !package! <nul
cls
echo.
echo.
echo [%r%^^!%w%] If !package! Is Glitching , Please Clear !package! Cache And Try it again.
echo.
echo.
echo !package! Settings Is Removed , Press Any Button To Go Back
pause > nul
goto Gaming

:low
@echo off
cls
title Low Settings
call :_dcfg_warn
set "package=" & set /p package="Put Your Package Name Here >> "
if "!package!"=="" goto Gaming
set "_PKGCHK=!package!"
call :_pkg_ok || (
    echo  [%r%x%w%] Invalid package name. Letters, digits, dots and underscores only.
    timeout /t 2 /nobreak > nul
    goto Gaming
)
adb shell device_config put game_overlay !package! mode=1 <nul
adb shell cmd game downscale 0.55 !package! <nul
cls
echo.
echo.
echo [%r%^^!%w%] If !package! Is Glitching , Please Clear !package! Cache And Try it again.
echo.
echo.
echo Press Any Button To Go Back
pause > nul
goto Gaming

:med
@echo off
cls
title Medium Settings
call :_dcfg_warn
set "package=" & set /p package="Put Your Package Name Here >> "
if "!package!"=="" goto Gaming
set "_PKGCHK=!package!"
call :_pkg_ok || (
    echo  [%r%x%w%] Invalid package name. Letters, digits, dots and underscores only.
    timeout /t 2 /nobreak > nul
    goto Gaming
)
adb shell device_config put game_overlay !package! mode=1 <nul
adb shell device_config get game_overlay !package! <nul
adb shell cmd game downscale 0.75 !package! <nul
cls
echo.
echo.
echo [%r%^^!%w%] If !package! Is Glitching , Please Clear !package! Cache And Try it again.
echo.
echo.
echo Press Any Button To Go Back
pause > nul
goto Gaming
:: Performance
:performance
@echo off
cls
title Performance props (debug/OEM)
echo.
echo.
echo  Writes a large dump of debug/OEM props. Most are volatile and
echo  device-dependent - not a guaranteed FPS mode. Lasting bits are
echo  mainly low_power off + thermal reset; Samsung-only keys no-op elsewhere.
echo.
echo [%r%1%w%] Toggle
echo [%r%2%w%] Back
set "kb=" & set /p kb="Choose An Option >> "
if "!kb!"=="1" goto toggleperf
if "!kb!"=="2" goto Gaming
:: FIX: guard against invalid input - previously fell through to :toggleperf
goto performance

:toggleperf
cls
title Performance Mode
echo.
echo.
echo [%r%1%w%] Off
echo [%r%2%w%] On
echo [%r%3%w%] Back
set "kb=" & set /p kb="Choose An Option >> "
if "!kb!"=="1" goto offperf
if "!kb!"=="2" goto onperf
if "!kb!"=="3" goto Gaming
:: guard against invalid input
goto toggleperf

:offperf
@echo off
cls
title Performance Mode : Off
:: FIX: revert by REMOVING the override so the platform default returns.
:: The old code set the ratio to 80 on "Off" instead of deleting it, so
:: toggling Off did not actually revert anything.
adb shell device_config delete storage_native_boot target_dirty_ratio <nul > nul 2>&1
adb shell device_config delete storage_native_boot target_dirty_background_ratio <nul > nul 2>&1
adb shell logcat -G 256kb <nul
adb shell settings delete global activity_manager_constants <nul > nul 2>&1
adb shell device_config delete runtime_native_boot iorap_readahead_enable <nul > nul 2>&1
adb shell device_config delete surface_flinger_native_boot max_frame_buffer_acquired_buffers <nul > nul 2>&1
adb shell device_config delete surface_flinger_native_boot adpf_cpu_hint <nul > nul 2>&1
:: FIX (revert-completeness): :onperf pins PERSISTENT power state that
:: survives reboot; "Off" must undo it or the device stays in the
:: performance profile forever. (debug.* setprops are volatile - the
:: reboot prompted below clears those - so only persistent state is
:: reverted here. set-mode is NOT forced: "1" would turn low-power mode
:: ON, the opposite of a revert; un-pinning low_power is enough.)
adb shell cmd thermalservice reset <nul > nul 2>&1
adb shell cmd power set-adaptive-power-saver-enabled true <nul > nul 2>&1
adb shell settings delete global low_power <nul > nul 2>&1
adb shell settings delete system multicore_packet_scheduler <nul > nul 2>&1
adb shell settings delete global sem_enhanced_cpu_responsiveness <nul > nul 2>&1
:: Clear the SQLite durability props an OLDER DCX set here, for anyone who ran Performance
:: On before they were removed and has not rebooted since. They are volatile, so this is
:: only about not making the user wait for a reboot to get fsync back. Empty = platform
:: default. Same "Revert still clears leftovers from an old run" habit as Network Boost.
adb shell setprop debug.sqlite.journalmode '' <nul > nul 2>&1
adb shell setprop debug.sqlite.syncmode '' <nul > nul 2>&1
adb shell setprop debug.sqlite.wal.syncmode '' <nul > nul 2>&1
if "%SDK%"=="" (
    adb shell settings delete global device_idle_constants <nul > nul 2>&1
) else if %SDK% GEQ 31 (
    adb shell device_config delete device_idle inactive_to <nul > nul 2>&1
) else (
    adb shell settings delete global device_idle_constants <nul > nul 2>&1
)
echo.
echo.
echo [%r%^^!%w%] Please Restart Device To Finish The Process
echo.
echo.
timeout /t 2 /nobreak > nul
echo Press Any Button To Go Back
pause > nul
goto Gaming

:onperf
@echo off
cls
title Performance Mode : On
call :_dcfg_warn
echo.
echo.
echo [%r%^^!%w%] All Powersaving Is Disabled
echo [%r%^^!%w%] If You Want To Enable Power Saver Again, You Need To Disable Performance Mode
echo [%r%^^!%w%] And Enable Power Saver Mode In Battery Mode
::disable powersaver
adb shell cmd power set-mode 0 <nul > nul 2>&1
adb shell cmd thermalservice override-status 0 <nul
adb shell settings put global low_power 0 <nul
if "%SDK%"=="" (
    adb shell settings put global device_idle_constants inactive_to=300000 <nul > nul 2>&1
) else if %SDK% GEQ 31 (
    adb shell device_config put device_idle inactive_to 300000 <nul > nul 2>&1
) else (
    adb shell settings put global device_idle_constants inactive_to=300000 <nul > nul 2>&1
)
adb shell cmd power set-adaptive-power-saver-enabled false <nul
adb shell setprop debug.power_management_mode pref_max <nul
adb shell cmd shortcut reset-all-throttling <nul > nul 2>&1
:: FIX: 256mb log buffer in "performance" mode is counter-productive.
:: A buffer that big stalls the system on flush. 1mb is sufficient.
adb shell logcat -G 1mb <nul
adb shell setprop debug.rs.rsov 1 <nul
adb shell setprop debug.rs.default-CPU-driver 0 <nul
adb shell setprop debug.renderengine.graphite true <nul
adb shell setprop debug.hwc.hdr_nbm_enable 0 <nul
:: FIX: removed debug.choreographer.vsync false  - disabling vsync
:: causes screen tearing and breaks frame pacing. Not a real
:: performance improvement; modern GPUs need vsync for stability.
:: REMOVED (harmful): debug.sqlite.journalmode / syncmode / wal.syncmode OFF - same
:: reasoning as the copy in :skiplogv. Trading database integrity for write throughput is
:: not a performance mode, it is a corruption risk, and it is the user's contacts and
:: messages on the line. journalsizelimit is harmless and stays.
adb shell setprop debug.sqlite.journalsizelimit 1mb <nul
adb shell setprop debug.hwui.disable_draw_defer true <nul
adb shell setprop debug.hwui.disable_draw_reorder false <nul
adb shell setprop debug.sf.disable_client_composition_cache 1 <nul
adb shell setprop debug.hwui.initialize_gl_always true <nul
adb shell setprop debug.sf.drop_missed_frames 1 <nul
adb shell setprop debug.sf.allowed_actual_deviation 0 <nul
adb shell setprop debug.hwui.render_dirty_regions false <nul
adb shell setprop debug.hwc.flattenning_enabled false <nul
adb shell setprop debug.hwc.test_plan false <nul
:: FIX: removed debug.hwui.disable_vsync true - same reason as above.
adb shell setprop debug.incremental.always_enable_read_timeouts_for_system_dataloaders false <nul
adb shell setprop debug.incremental.enable_read_timeouts_after_install false <nul
adb shell setprop debug.sf.treat_170m_as_sRGB 0 <nul
adb shell setprop debug.sf.fp16_client_target 1 <nul
adb shell setprop debug.soundtrigger_middleware.use_mock_hal 0 <nul
adb shell setprop debug.extractor.ignore_version false <nul
adb shell setprop debug.art.monitor.app false <nul
adb shell setprop debug.sf.vrr_timeout_hint_enabled false <nul
adb shell setprop debug.sf.enable_hole_punch_pip false <nul
adb shell setprop debug.hwc.force_gpu 1 <nul
adb shell setprop debug.sf.framedrop 0 <nul
adb shell setprop debug.hwui.clip_surfaceviews true <nul
adb shell setprop debug.hwui.resample_gainmap_regions false <nul
adb shell setprop debug.egl.blobcache.multifile true <nul
adb shell setprop debug.egl.blobcache.multifile_limit 16777216 <nul
adb shell setprop debug.sf.enable_layer_command_batching 1 <nul
adb shell setprop debug.sf.use_content_detection_v2 false <nul
adb shell setprop debug.adpf.use_report_actual_duration false <nul
adb shell setprop debug.sf.hint_margin_us 550 <nul
adb shell setprop debug.sf.cached_set_max_defer_render_attmpts 2 <nul
adb shell setprop debug.sf.layer_caching_active_layer_timeout_ms 1200 <nul
adb shell setprop debug.sf.cache_source_crop_only_moved true <nul
adb shell setprop debug.sf.multithreaded_present 1 <nul
adb shell setprop debug.sf.hwc_hdcp_via_neg_vsync false <nul
adb shell setprop debug.sf.enable_layer_lifecycle_manager false <nul
adb shell setprop debug.sf.send_early_power_session_hint true <nul
adb shell setprop debug.sf.send_late_power_session_hint false <nul
adb shell setprop debug.sf.hwc.min.duration 0 <nul
adb shell setprop debug.sf.use_frame_rate_priority 1 <nul
adb shell setprop debug.sf.enable_cached_set_render_scheduling true <nul
adb shell setprop debug.sf.enable_layer_caching 0 <nul
adb shell setprop debug.sf.max_igbp_list_size 7 <nul
adb shell setprop debug.hwc.fakevsync 0 <nul
adb shell setprop debug.enable.sglscale 1 <nul
adb shell setprop debug.enable.gamed 1 <nul
adb shell setprop debug.enabletr true <nul
adb shell setprop debug.sf.enable_adpf_cpu_hint true <nul
adb shell setprop debug.rs.precision rs_fp_full <nul
adb shell setprop debug.hwui.high_performance_mode true <nul
adb shell settings put system multicore_packet_scheduler 1 <nul
adb shell settings put global sem_enhanced_cpu_responsiveness 1 <nul
adb shell settings put global activity_manager_constants max_cached_processes=12,power_check_interval=80000,power_check_max_cpu_1=85,power_check_max_cpu_2=85,power_check_max_cpu_3=60,power_check_max_cpu_4=15 <nul
adb shell setprop debug.cpurend.vsync false <nul
adb shell setprop debug.sf.hw 1 <nul
adb shell setprop debug.rs.max-threads 8 <nul
adb shell setprop debug.sf.vsync_reactor_ignore_present_fences true <nul
adb shell setprop debug.sf.disable_hwc_vds 1 <nul
adb shell setprop debug.sf.enable_hwc_vds false <nul
adb shell setprop debug.hwui.target_cpu_time_percent 35 <nul
adb shell setprop debug.egl.hw 1 <nul
adb shell setprop debug.rs.reduce-split-accum 1 <nul
adb shell setprop debug.choreographer.skipwarning 16500000 <nul
adb shell setprop debug.sf.luma_sampling 0 <nul
adb shell setprop debug.gr.numframebuffers 3 <nul
adb shell setprop debug.hwui.skip_empty_damage true <nul
adb shell setprop debug.composition.type dyn <nul
adb shell setprop debug.hwui.use_buffer_age true <nul
adb shell setprop debug.hwui.use_partial_updates true <nul
adb shell setprop debug.egl.swapinterval 0 <nul
adb shell setprop debug.gralloc.map_fb_memory 1 <nul
adb shell setprop debug.gralloc.enable_fb_ubwc 1 <nul
adb shell setprop debug.sf.swaprect 1 <nul
adb shell setprop debug.hwui.filter_test_overhead false <nul
adb shell setprop debug.hwui.fps_divisor 1 <nul
adb shell setprop debug.graphics.game_default_frame_rate.disabled true <nul
adb shell setprop debug.sf.latch_unsignaled 1 <nul
adb shell setprop debug.sf.auto_latch_unsignaled true <nul
adb shell setprop debug.sf.disable_backpressure 1 <nul
adb shell setprop debug.sf.enable_advanced_sf_phase_offset 1 <nul
adb shell setprop debug.gralloc.gfx_ubwc_disable 0 <nul
adb shell setprop debug.hwc.bq_count 3 <nul
adb shell setprop debug.hwc.compose_level 0 <nul
adb shell setprop debug.hwui.use_hint_manager true <nul
adb shell setprop debug.hwui.render_ahead 3 <nul
adb shell setprop debug.sf.enable_gl_backpressure 0 <nul
adb shell setprop debug.sf.vsync_reactor_ignore_present_fences true <nul
adb shell setprop debug.sf.set_idle_timer_ms 3500 <nul
adb shell setprop debug.sf.frame_rate_multiple_threshold 120 <nul
adb shell setprop debug.sf.use_phase_offsets_as_durations 0 <nul
adb shell setprop debug.c2.use_dmabufheaps 1 <nul
adb shell setprop debug.sf.prime_shader_cache.image_layers true <nul
adb shell setprop debug.sf.prime_shader_cache.solid_layers true <nul
adb shell setprop debug.mdpcomp.idletime 5000 <nul
adb shell setprop debug.mdpcomp.maxpermixer 3 <nul
adb shell device_config put runtime_native_boot iorap_readahead_enable true <nul
adb shell setprop debug.media.c2.large.audio.frame false <nul
::this device config from google, i don't try do any gimmick device config here, source : https://cs.android.com/search?q=surface_flinger_native_boot&sq=
adb shell device_config put surface_flinger_native_boot max_frame_buffer_acquired_buffers 3 <nul
adb shell device_config put surface_flinger_native_boot adpf_cpu_hint true <nul
::this device config from google, i don't try do any gimmick device config here, source : https://cs.android.com/search?q=surface_flinger_native_boot&sq=
:: FIX: set an ABSOLUTE target so repeating "On" is idempotent. The old
:: code did `current+10` every run (unbounded growth on repeated toggles)
:: and, because of the early-out above, did nothing at all when the key
:: was previously unset. 35 is a modestly elevated write-back ratio - a
:: sane performance default without much extra crash-data-loss risk;
:: "Off" now deletes the key to truly revert (see :offperf).
echo storage_native_boot/target_dirty_ratio : 35
echo storage_native_boot/target_dirty_background_ratio : 5
adb shell device_config put storage_native_boot target_dirty_ratio 35 <nul
adb shell device_config put storage_native_boot target_dirty_background_ratio 5 <nul
echo Press Any Button To Go Back
pause > nul
goto Gaming

:appmgr
cls
title App Manager
call :logo
echo                            %b%[%w% App Manager %b%]%w%
echo.
echo   Background control + debloat. Every action here is reversible.
echo.
echo                 %g%[%w%1%g%]%w% Restrict app background (deny RUN_IN_BACKGROUND)
echo                 %g%[%w%2%g%]%w% Allow app background (revert)
echo                 %g%[%w%3%g%]%w% Debloat - remove an app by package name
echo                 %g%[%w%4%g%]%w% Debloat - suggested bloatware (auto-detect brand)
echo                 %g%[%w%5%g%]%w% List installed packages (to Notepad)
echo                 %g%[%w%6%g%]%w% Restore a removed app
echo                 %g%[%w%7%g%]%w% Back
set "am=" & set /p am="Choose An Option >> "
if "!am!"=="1" goto appmgr_restrict
if "!am!"=="2" goto appmgr_allow
if "!am!"=="3" goto appmgr_debloat_input
if "!am!"=="4" goto appmgr_suggest
if "!am!"=="5" goto appmgr_listpkgs
if "!am!"=="6" goto appmgr_restore_input
if "!am!"=="7" goto menu
goto appmgr
:: ===================================================================
:: Restrict / Allow background  (cmd appops RUN_IN_BACKGROUND)
:: ===================================================================
:appmgr_restrict
cls
title Restrict Background
call :logo
echo  Denies RUN_IN_BACKGROUND for an app so it can't run in the
echo  background (saves battery). Reversible with "Allow background".
echo  Tip: use "List installed packages" first if you don't know the name.
echo.
set "pkg=" & set /p pkg="Package name (blank = cancel) >> "
if "!pkg!"=="" goto appmgr
set "_PKGCHK=!pkg!"
call :_pkg_ok || (
    echo  [%r%x%w%] Invalid package name. Letters, digits, dots and underscores only.
    timeout /t 2 /nobreak > nul
    goto appmgr
)
adb shell pm list packages < nul 2>nul | find /v "" | findstr /x /c:"package:!pkg!" >nul
if errorlevel 1 (
    echo [%r%^^!%w%] "!pkg!" is not installed.
    pause >nul
    goto appmgr_restrict
)
adb shell cmd appops set !pkg! RUN_IN_BACKGROUND deny <nul
echo.
set "_ao="
for /f "delims=" %%i in ('adb shell cmd appops get !pkg! RUN_IN_BACKGROUND 2^>nul ^<nul') do set "_ao=%%i"
echo  Device reports: !_ao!
echo(!_ao!| findstr /I /C:"deny" >nul
if errorlevel 1 (echo [%r%^^!%w%] Restrict may not have landed.) else (echo [%g%+%w%] Background denied for !pkg!.)
pause >nul
goto appmgr

:appmgr_allow
cls
title Allow Background
call :logo
echo  Re-allows RUN_IN_BACKGROUND for an app (undo of Restrict).
echo.
set "pkg=" & set /p pkg="Package name (blank = cancel) >> "
if "!pkg!"=="" goto appmgr
set "_PKGCHK=!pkg!"
call :_pkg_ok || (
    echo  [%r%x%w%] Invalid package name. Letters, digits, dots and underscores only.
    timeout /t 2 /nobreak > nul
    goto appmgr
)
adb shell pm list packages < nul 2>nul | find /v "" | findstr /x /c:"package:!pkg!" >nul
if errorlevel 1 (
    echo [%r%^^!%w%] "!pkg!" is not installed.
    pause >nul
    goto appmgr_allow
)
adb shell cmd appops set !pkg! RUN_IN_BACKGROUND allow <nul
echo.
set "_ao="
for /f "delims=" %%i in ('adb shell cmd appops get !pkg! RUN_IN_BACKGROUND 2^>nul ^<nul') do set "_ao=%%i"
echo  Device reports: !_ao!
echo(!_ao!| findstr /I /C:"allow" >nul
if errorlevel 1 (echo [%r%^^!%w%] Allow may not have landed.) else (echo [%g%+%w%] Background allowed for !pkg!.)
pause >nul
goto appmgr
:: ===================================================================
:: Debloat by package name  (pm uninstall -k --user 0)
:: -k keeps app data; reversible via Restore or factory reset.
:: A short hard-block list refuses known bootloop-causing packages.
:: ===================================================================
:appmgr_debloat_input
cls
title Debloat by Package
call :logo
echo  %r%Removes an app for the current user%w% (pm uninstall -k --user 0).
echo  Data is kept (-k) and it's reversible via Restore or a factory
echo  reset, but removing a critical package can cause a bootloop.
echo.
echo  %y%Only remove apps you recognise.%w% Never remove system UI, phone,
echo  or anything you can't identify. On Transsion (Tecno/Infinix) phones
echo  never remove com.hoffnung - it looks like bloat but bootloops.
echo.
set "pkg=" & set /p pkg="Package name (blank = cancel) >> "
if "!pkg!"=="" goto appmgr
set "_PKGCHK=!pkg!"
call :_pkg_ok || (
    echo  [%r%x%w%] Invalid package name. Letters, digits, dots and underscores only.
    timeout /t 2 /nobreak > nul
    goto appmgr
)
set "BLOCKED=0"
for %%c in (com.android.systemui com.hoffnung com.android.phone com.android.settings com.miui.daemon com.android.systemui.plugins com.android.providers.telephony com.huawei.hwid com.huawei.android.pushagent com.huawei.hwasm com.huawei.android.hwouc com.huawei.systemserver) do if /i "!pkg!"=="%%c" set "BLOCKED=1"
if "%BLOCKED%"=="1" (
    echo [%r%BLOCKED%w%] "!pkg!" is a critical package and will not be removed.
    pause >nul
    goto appmgr_debloat_input
)
adb shell pm list packages < nul 2>nul | find /v "" | findstr /x /c:"package:!pkg!" >nul
if errorlevel 1 (
    echo [%r%^^!%w%] "!pkg!" is not installed.
    pause >nul
    goto appmgr_debloat_input
)
echo.
echo  About to remove: !pkg!
echo    [Y] Remove    [N] Cancel
choice /c:YN /n >nul
if errorlevel 2 goto appmgr
adb shell pm uninstall -k --user 0 !pkg! <nul
echo.
echo Done. To bring it back: App Manager -^> Restore (or a factory reset).
pause >nul
goto appmgr

:appmgr_restore_input
cls
title Restore Removed App
call :logo
echo  Reinstalls an app removed with Debloat (pm install-existing).
echo  Works as long as it was removed with -k and not fully wiped.
echo.
set "pkg=" & set /p pkg="Package name to restore (blank = cancel) >> "
if "!pkg!"=="" goto appmgr
set "_PKGCHK=!pkg!"
call :_pkg_ok || (
    echo  [%r%x%w%] Invalid package name. Letters, digits, dots and underscores only.
    timeout /t 2 /nobreak > nul
    goto appmgr
)
adb shell cmd package install-existing !pkg! <nul
echo.
adb shell pm list packages 2>nul <nul | find /v "" | findstr /x /c:"package:!pkg!" >nul
if errorlevel 1 (
    echo [%r%^^!%w%] Restore did not land - "!pkg!" is not installed for this user.
    echo      It may never have been a system/preloaded package, or the APK is gone.
) else (
    echo [%g%+%w%] !pkg! is present for the current user.
)
pause >nul
goto appmgr
:: ===================================================================
:: List installed packages to a file and open it (read-only, safe).
:: ===================================================================
:appmgr_listpkgs
cls
title Installed Packages
call :logo
echo  [%g%1%w%] All packages
echo  [%g%2%w%] User + updated apps only (-3) - usually where bloat lives
echo  [%g%3%w%] Back
set "lp=" & set /p lp="Choose An Option >> "
if not defined lp goto appmgr_listpkgs
if "!lp!"=="3" goto appmgr
:: FIX (stale list): only 1/2/3 were handled and there was no re-ask, so any other key
:: ran NO adb command and fell straight through to `start notepad` below. %PKGLIST% is a
:: FIXED temp filename, so from the second visit onward that opened the PREVIOUS run's
:: list with nothing marking it stale - and debloat decisions get made off this list.
:: Re-ask on anything else, and delete the file first so a dump that fails cannot leave
:: old data on screen.
if not "!lp!"=="1" if not "!lp!"=="2" goto appmgr_listpkgs
set "PKGLIST=%TEMP%\dcx_installed_packages.txt"
del "%PKGLIST%" > nul 2>&1
:: `find /v ""` also fixes the file Notepad opens: adb's LF-only output renders as one
:: enormous line in older Notepad builds.
if "!lp!"=="1" adb shell pm list packages < nul 2>nul | find /v "" > "%PKGLIST%"
if "!lp!"=="2" adb shell pm list packages -3 < nul 2>nul | find /v "" > "%PKGLIST%"
:: An empty file still passes `if exist`, so prove a real package line landed - same
:: shape as the _bkok guard in :backup. Covers "file missing" too (findstr exits 2).
findstr /b /c:"package:" "%PKGLIST%" >nul 2>&1 || goto appmgr_listpkgs_none
start "" notepad "%PKGLIST%"
echo Opened in Notepad. Use these names with Restrict / Debloat.
pause >nul
goto appmgr

:appmgr_listpkgs_none
echo.
echo  %r%No packages were listed.%w% Is the device still connected? ^(check: adb devices^)
pause >nul
goto appmgr
:: ===================================================================
:: Suggested bloatware - auto-detect brand, only offer packages that
:: are (a) on a vetted safe-to-remove list AND (b) actually installed.
:: Package lists are sourced from UAD-NG and community debloat guides.
:: ===================================================================
:appmgr_suggest
cls
title Suggested Bloatware
call :logo
set "BRAND="
for /f "delims=" %%i in ('adb shell getprop ro.product.brand 2^>nul ^<nul') do set "BRAND=%%i"
set "MANU="
for /f "delims=" %%i in ('adb shell getprop ro.product.manufacturer 2^>nul ^<nul') do set "MANU=%%i"
set "PKGDUMP=%TEMP%\dcx_pkgs.txt"
:: `find /v ""` normalises adb's possibly LF-only output to CRLF so the /x whole-line
:: match in :_remove_present_set works - see the note at :compile.
adb shell pm list packages < nul 2>nul | find /v "" > "%PKGDUMP%"
echo  Detected brand: %BRAND%   manufacturer: %MANU%
echo.
echo  These groups only remove well-documented, safe-to-remove apps that
echo  are actually installed. Removal is for the current user (-k keeps
echo  data) and reversible via Restore or a factory reset. Critical
echo  packages (system UI, telephony, etc) are never listed.
echo.
echo                 %g%[%w%1%g%]%w% Facebook bloat (any brand)
echo                 %g%[%w%2%g%]%w% Optional Google apps (YouTube, Drive, Meet...)
set "BRANDCAT=0"
echo %BRAND% %MANU%| findstr /I "xiaomi redmi poco" >nul && set "BRANDCAT=Xiaomi"
echo %BRAND% %MANU%| findstr /I "tecno infinix itel transsion" >nul && set "BRANDCAT=Transsion"
echo %BRAND% %MANU%| findstr /I "samsung" >nul && set "BRANDCAT=Samsung"
echo %BRAND% %MANU%| findstr /I "huawei honor" >nul && set "BRANDCAT=Huawei"
if not "%BRANDCAT%"=="0" echo                 %g%[%w%3%g%]%w% %BRANDCAT% bloat
echo                 %g%[%w%4%g%]%w% Back
set "sg=" & set /p sg="Choose An Option >> "
if "!sg!"=="1" goto appmgr_bloat_fb
if "!sg!"=="2" goto appmgr_bloat_google
if "!sg!"=="3" goto appmgr_bloat_brand
if "!sg!"=="4" goto appmgr
goto appmgr_suggest

:appmgr_bloat_fb
set "BLOATDESC=Facebook background services + the Facebook app (pure bloat)."
set "BLOATSET=com.facebook.katana com.facebook.appmanager com.facebook.services com.facebook.system"
goto _remove_present_set

:appmgr_bloat_google
set "BLOATDESC=Optional Google apps - no bootloop, you just lose those apps."
set "BLOATSET=com.google.android.apps.tachyon com.google.android.youtube com.google.android.apps.youtube.music com.google.android.apps.docs com.google.android.videos com.google.android.apps.wellbeing"
goto _remove_present_set

:appmgr_bloat_brand
if "%BRANDCAT%"=="Xiaomi" set "BLOATDESC=MIUI/HyperOS ads, analytics and optional stock apps."
if "%BRANDCAT%"=="Xiaomi" set "BLOATSET=com.miui.analytics com.miui.msa.global com.miui.systemAdSolution com.xiaomi.mipicks com.mi.globalbrowser com.miui.yellowpage com.miui.videoplayer com.miui.player com.mi.globalminusscreen"
if "%BRANDCAT%"=="Transsion" set "BLOATDESC=Transsion (Tecno/Infinix/itel) preinstalled bloat."
if "%BRANDCAT%"=="Transsion" set "BLOATSET=com.transsion.ossettingsext com.afmobi.boomplayer com.funbase.xradio com.transsion.fmradio com.infinix.xshare com.transsnet.store com.transsion.carlcare net.bat.store com.talpa.hibrowser com.transsion.smartpanel com.transsion.magazineservice.xos com.transsion.healthlife com.transsion.tecnospot com.transsion.magicshow com.transsion.statisticalsales com.transsion.plat.appupdate com.transsion.batterylab com.rlk.weathers"
if "%BRANDCAT%"=="Samsung" set "BLOATDESC=Samsung Free / Bixby / tips (optional)."
if "%BRANDCAT%"=="Samsung" set "BLOATSET=com.samsung.android.app.spage com.samsung.android.bixby.agent com.samsung.android.app.tips com.samsung.android.game.gamehome"
if "%BRANDCAT%"=="Huawei" set "BLOATDESC=Huawei/Honor (EMUI/HarmonyOS) optional apps and promo services."
if "%BRANDCAT%"=="Huawei" set "BLOATSET=com.huawei.search com.huawei.hitouch com.huawei.intelligent com.huawei.browser com.huawei.android.thememanager com.huawei.health com.huawei.tips com.huawei.hiskytone com.huawei.vassistant com.huawei.appmarket com.huawei.fastapp com.huawei.android.totemweather com.huawei.hifolder com.huawei.parentcontrol com.huawei.bd"
if "%BRANDCAT%"=="0" goto appmgr_suggest
goto _remove_present_set
:: -------------------------------------------------------------------
:: Shared remover: shows which of %BLOATSET% are installed (using the
:: %PKGDUMP% list), then removes them all after one confirmation.
:: -------------------------------------------------------------------
:_remove_present_set
cls
title Debloat : review
call :logo
echo  %BLOATDESC%
echo.
if not exist "%PKGDUMP%" adb shell pm list packages < nul 2>nul | find /v "" > "%PKGDUMP%"
echo  Installed packages from this group (these will be removed):
echo.
set "_found="
set "_n=0"
for %%p in (%BLOATSET%) do (
    findstr /x /c:"package:%%p" "%PKGDUMP%" >nul
    if not errorlevel 1 (
        echo     %%p
        set "_found=!_found! %%p"
        set /a _n+=1
    )
)
echo.
if "%_n%"=="0" (
    echo  None of this group's packages are installed. Nothing to do.
    pause >nul
    goto appmgr_suggest
)
echo  Total: %_n% package(s). Removed for the current user only (-k keeps
echo  data). Restore later via App Manager -^> Restore, or a factory reset.
echo.
echo    [Y] Remove these now
echo    [N] Cancel
choice /c:YN /n >nul
if errorlevel 2 goto appmgr_suggest
echo.
for %%p in (%_found%) do (
    echo Removing %%p ...
    adb shell pm uninstall -k --user 0 %%p <nul
)
echo.
echo Done.
pause >nul
goto appmgr_suggest
:: ===================================================================
:: NEW: Tweaks and Settings  (main menu 14)
::
:: Feature parity targets: zacharee/Tweaker (SystemUI Tuner) and
:: MuntashirAkon/SetEdit. Mechanics verified against AOSP main
:: (SoundDoseHelper.java, Clock.java, AudioManagerShellCommand.java);
:: details in CHANGES-tweaks-tier1.md. All adb calls carry <nul so
:: they never eat the next set /p (house press-twice guard).
:: ===================================================================
:tweaks
cls
title Tweaks and Settings
call :logo
echo.
echo                              %m%Tweaks and Settings%w%
echo.
echo   %d%Status bar%w%
echo    %g%[%w%1%g%]%w% Clock - show seconds
echo    %g%[%w%2%g%]%w% Battery percent
echo    %g%[%w%3%g%]%w% Icon blacklist - hide status bar icons
echo    %g%[%w%4%g%]%w% Demo mode - clean bar for screenshots
echo.
echo   %d%Quick settings%w%
echo    %g%[%w%5%g%]%w% Tile editor - add the tiles Android hides
echo.
echo   %d%System%w%
echo    %g%[%w%6%g%]%w% Volume cap (safe media volume)
echo    %g%[%w%7%g%]%w% Heads-up notifications
echo    %g%[%w%8%g%]%w% Font scale
echo    %g%[%w%9%g%]%w% Long-press timeout
echo    %g%[%w%10%g%]%w% Stay awake while charging
echo    %g%[%w%11%g%]%w% Night - dark theme / night light
echo    %g%[%w%12%g%]%w% More device tweaks
echo    %g%[%w%13%g%]%w% DeviceConfig server sync (advanced)
echo.
echo   %d%Undo / backups%w%
set "BACKUPDIR=%USERPROFILE%\dcx_backups"
if defined EXP_UNDO (
    echo    Session undo: !EXP_UNDO!
) else if exist "%BACKUPDIR%\dcx_last_undo.txt" (
    set "_lu="
    set /p _lu=<"%BACKUPDIR%\dcx_last_undo.txt"
    echo    Last undo: !_lu!
) else (
    echo    No undo script yet this session.
)
if exist "%BACKUPDIR%\dcx_last_backup.txt" (
    set "_lb="
    set /p _lb=<"%BACKUPDIR%\dcx_last_backup.txt"
    echo    Last backup: !_lb!
)
echo    %g%[%w%14%g%]%w% Undo / backups hub - open or run last undo
echo.
echo    %g%[%w%15%g%]%w% Back to main menu
set "tw=" & set /p tw="Choose An Option >> "
if not defined tw goto tweaks
if "!tw!"=="1" goto tw_clock
if "!tw!"=="2" goto tw_batpct
if "!tw!"=="3" goto tw_icons
if "!tw!"=="4" goto tw_demo
if "!tw!"=="5" goto tw_qs
if "!tw!"=="6" goto tw_safevol
if "!tw!"=="7" goto tw_headsup
if "!tw!"=="8" goto tw_font
if "!tw!"=="9" goto tw_lpt
if "!tw!"=="10" goto tw_stay
if "!tw!"=="11" goto tw_night
if "!tw!"=="12" goto tw_more
if "!tw!"=="13" goto tw_dcfgsync
if "!tw!"=="14" goto tw_undo_hub
if "!tw!"=="15" goto menu
goto tweaks

:tw_undo_hub
cls
title Undo / Backups
call :logo
set "BACKUPDIR=%USERPROFILE%\dcx_backups"
if not exist "%BACKUPDIR%" mkdir "%BACKUPDIR%"
set "UNDOFILE="
if defined EXP_UNDO if exist "!EXP_UNDO!" set "UNDOFILE=!EXP_UNDO!"
if not defined UNDOFILE if exist "%BACKUPDIR%\dcx_last_undo.txt" (
    set /p UNDOFILE=<"%BACKUPDIR%\dcx_last_undo.txt"
)
set "BAKLAST="
if exist "%BACKUPDIR%\dcx_last_backup.txt" set /p BAKLAST=<"%BACKUPDIR%\dcx_last_backup.txt"
echo.
echo  Folder: %BACKUPDIR%
echo  Session/last undo:
if defined UNDOFILE (echo    !UNDOFILE!) else (echo    ^(none yet^))
echo  Last backup:
if defined BAKLAST (echo    !BAKLAST!) else (echo    ^(none yet^))
echo.
echo    %g%[%w%1%g%]%w% Open undo script in Notepad
echo    %g%[%w%2%g%]%w% Run undo script now ^(restores captured values^)
echo    %g%[%w%3%g%]%w% Open backups folder
echo    %g%[%w%4%g%]%w% Open last backup in Notepad
echo    %g%[%w%5%g%]%w% Back
set "uh=" & set /p uh="Choose An Option >> "
if not defined uh goto tw_undo_hub
if "!uh!"=="1" goto tw_undo_open
if "!uh!"=="2" goto tw_undo_run
if "!uh!"=="3" (start "" "%BACKUPDIR%" & goto tw_undo_hub)
if "!uh!"=="4" goto tw_bak_open
if "!uh!"=="5" goto tweaks
goto tw_undo_hub

:tw_undo_open
if not defined UNDOFILE goto tw_undo_missing
if not exist "!UNDOFILE!" goto tw_undo_missing
start "" notepad "!UNDOFILE!"
goto tw_undo_hub

:tw_undo_run
if not defined UNDOFILE goto tw_undo_missing
if not exist "!UNDOFILE!" goto tw_undo_missing
echo.
echo  About to run: !UNDOFILE!
set "ok=" & set /p ok="Run undo? (y = yes) >> "
if /i not "!ok!"=="y" goto tw_undo_hub
echo.
cmd /c ""!UNDOFILE!" /nopause"
echo.
echo  ----------------------------------------
echo  Undo finished ^(exit code %errorlevel%^).
echo  Press any key to continue . . .
pause >nul
goto tw_undo_hub

:tw_bak_open
if not defined BAKLAST goto tw_bak_missing
if not exist "!BAKLAST!" goto tw_bak_missing
start "" notepad "!BAKLAST!"
goto tw_undo_hub

:tw_undo_missing
echo  %y%No undo script found yet.%w% Change something in Tweaks / Explorer first.
timeout /t 2 /nobreak >nul
goto tw_undo_hub

:tw_bak_missing
echo  %y%No backup path recorded yet.%w% Use Main Menu - Backup first.
timeout /t 2 /nobreak >nul
goto tw_undo_hub

:tw_dcfgsync
cls
title DeviceConfig Server Sync
call :logo
call :_dcfg_warn
echo.
:: Show what the device actually reports - and say so plainly when it reports nothing,
:: rather than printing a mode DCX never read. See :_dcfgsync_read.
call :_dcfgsync_read
if errorlevel 1 (
    echo  device_config get_sync_disabled_for_tests = %r%not readable on this build%w%
    echo  This Android build does not implement the getter, so DCX cannot show the
    echo  current mode or confirm a change. The setter below may still work - it just
    echo  cannot be verified, and Backup will skip this key rather than guess.
) else (
    echo  device_config get_sync_disabled_for_tests = "!DCS_VAL!"
)
echo.
echo  This is NOT Google/account sync. It freezes remote DeviceConfig flag
echo  updates from the server ^(OEM/feature flags^). "persistent" survives
echo  reboot until you set it back to none. Was previously buried inside
echo  Battery - Logs Off, which froze sync as a silent side effect.
echo.
echo    %g%[%w%1%g%]%w% Allow sync (none) - default / undo
echo    %g%[%w%2%g%]%w% Disable until reboot (until_reboot)
echo    %g%[%w%3%g%]%w% Disable permanently (persistent)
echo    %g%[%w%4%g%]%w% Back
set "dc=" & set /p dc="Choose An Option >> "
if not defined dc goto tw_dcfgsync
if "!dc!"=="1" (call :_tw_undo_dcfgsync & adb shell device_config set_sync_disabled_for_tests none <nul >nul 2>&1 & call :_dcfgsync_verify none & goto tw_dcfgsync)
if "!dc!"=="2" (call :_tw_undo_dcfgsync & adb shell device_config set_sync_disabled_for_tests until_reboot <nul >nul 2>&1 & call :_dcfgsync_verify until_reboot & goto tw_dcfgsync)
if "!dc!"=="3" (
    echo.
    echo  %y%Warning:%w% persistent stays frozen across reboot until you pick [1].
    echo    [Y] Freeze DeviceConfig sync permanently    [N] Cancel
    choice /c:YN /n >nul
    if errorlevel 2 goto tw_dcfgsync
    call :_tw_undo_dcfgsync
    adb shell device_config set_sync_disabled_for_tests persistent <nul >nul 2>&1
    call :_dcfgsync_verify persistent
    goto tw_dcfgsync
)
if "!dc!"=="4" goto tweaks
goto tw_dcfgsync

:tw_clock
cls
title Clock Seconds
call :logo
echo.
:: SystemUI registers secure/clock_seconds as a live TunerService tunable
:: (AOSP Clock.java) - changes apply instantly, no restart needed. Values
:: are read back from the device, so display them quote-wrapped after
:: stripping quotes (same metachar fix class as :_bk_settings).
set "cs="
for /f "delims=" %%i in ('adb shell settings get secure clock_seconds 2^>nul ^<nul') do set "cs=%%i"
if "!cs!"=="" set "cs=null"
set "cs=!cs:"=!"
echo  clock_seconds (secure) = "!cs!"   (1 = seconds shown, 0/null = device default)
echo  Applies live. Skinned OEM clocks (some OneUI) may ignore this key.
echo.
echo    %g%[%w%1%g%]%w% Show seconds
echo    %g%[%w%2%g%]%w% Hide seconds
echo    %g%[%w%3%g%]%w% Reset to device default (delete key)
echo    %g%[%w%4%g%]%w% Back
set "tc=" & set /p tc="Choose An Option >> "
if not defined tc goto tw_clock
if "!tc!"=="1" (call :_tw_undo_add secure clock_seconds & adb shell settings put secure clock_seconds 1 <nul & goto tw_clock)
if "!tc!"=="2" (call :_tw_undo_add secure clock_seconds & adb shell settings put secure clock_seconds 0 <nul & goto tw_clock)
if "!tc!"=="3" (call :_tw_undo_add secure clock_seconds & adb shell settings delete secure clock_seconds >nul 2>&1 <nul & goto tw_clock)
if "!tc!"=="4" goto tweaks
goto tw_clock

:tw_batpct
cls
title Battery Percent
call :logo
echo.
set "bp="
for /f "delims=" %%i in ('adb shell settings get system status_bar_show_battery_percent 2^>nul ^<nul') do set "bp=%%i"
if "!bp!"=="" set "bp=null"
set "bp=!bp:"=!"
echo  status_bar_show_battery_percent (system) = "!bp!"   (1 = shown, 0/null = default)
echo  Applies live on AOSP-based status bars; heavy OEM skins may override.
echo.
echo    %g%[%w%1%g%]%w% Show percent
echo    %g%[%w%2%g%]%w% Hide percent
echo    %g%[%w%3%g%]%w% Reset to device default (delete key)
echo    %g%[%w%4%g%]%w% Back
set "tb=" & set /p tb="Choose An Option >> "
if not defined tb goto tw_batpct
if "!tb!"=="1" (call :_tw_undo_add system status_bar_show_battery_percent & adb shell settings put system status_bar_show_battery_percent 1 <nul & goto tw_batpct)
if "!tb!"=="2" (call :_tw_undo_add system status_bar_show_battery_percent & adb shell settings put system status_bar_show_battery_percent 0 <nul & goto tw_batpct)
if "!tb!"=="3" (call :_tw_undo_add system status_bar_show_battery_percent & adb shell settings delete system status_bar_show_battery_percent >nul 2>&1 <nul & goto tw_batpct)
if "!tb!"=="4" goto tweaks
goto tw_batpct

:tw_safevol
cls
title Volume Cap
call :logo
echo.
echo  Controls the SOFTWARE safe-media-volume cap/warning (EU hearing rule).
echo  It does NOT raise the hardware amplifier limit - that lives in vendor
echo  gain tables (engineering menu) and needs root.
echo.
set "svs="
for /f "delims=" %%i in ('adb shell settings get global audio_safe_volume_state 2^>nul ^<nul') do set "svs=%%i"
if "!svs!"=="" set "svs=null"
set "svs=!svs:"=!"
set "svtxt=unknown value"
if /i "!svs!"=="null" set "svtxt=not configured - system decides at boot"
if "!svs!"=="0" set "svtxt=not configured - system decides at boot"
if "!svs!"=="1" set "svtxt=disabled - no cap on this device/region"
if "!svs!"=="2" set "svtxt=inactive - cap off for the boot that reads this"
if "!svs!"=="3" set "svtxt=active - cap enforced"
echo  audio_safe_volume_state (global) = "!svs!"
echo    !svtxt!
if %SDK% GEQ 34 (
    echo.
    echo  Sound dose - the Android 14+ regime that replaces the cap where enabled:
    for /f "delims=" %%i in ('adb shell cmd audio get-sound-dose-value 2^>nul ^<nul') do echo    %%i
)
echo.
echo  The state key is read ONCE at boot, and Android re-writes it to 3
echo  after every boot on capped devices - plus after ~20h of music - so
echo  option 1 is a per-boot switch, not a permanent one.
echo.
echo    %g%[%w%1%g%]%w% Disable cap for next boot   (set state 2, then reboot)
echo    %g%[%w%2%g%]%w% Re-enable cap               (set state 3)
echo    %g%[%w%3%g%]%w% Reset to system default     (delete key)
echo    %g%[%w%4%g%]%w% Reset accumulated sound dose        - Android 14+
echo    %g%[%w%5%g%]%w% Sound-dose "CSD as a feature" off   - Android 14+
echo    %g%[%w%6%g%]%w% Back
set "sv=" & set /p sv="Choose An Option >> "
if not defined sv goto tw_safevol
if "!sv!"=="1" goto tw_safevol_off
if "!sv!"=="2" (call :_tw_undo_add global audio_safe_volume_state & adb shell settings put global audio_safe_volume_state 3 <nul & goto tw_safevol)
if "!sv!"=="3" (call :_tw_undo_add global audio_safe_volume_state & adb shell settings delete global audio_safe_volume_state >nul 2>&1 <nul & goto tw_safevol)
if "!sv!"=="4" goto tw_safevol_dose
if "!sv!"=="5" goto tw_safevol_csdoff
if "!sv!"=="6" goto tweaks
goto tw_safevol

:tw_safevol_off
call :_tw_undo_add global audio_safe_volume_state
adb shell settings put global audio_safe_volume_state 2 <nul
echo.
echo  Done - state set to 2 (inactive). Takes effect at the NEXT boot.
echo  Re-run this after each reboot if you want the cap to stay off.
set "rb=" & set /p rb="Reboot device now? (y = yes, anything else = back) >> "
if /i "!rb!"=="y" adb reboot <nul
goto tw_safevol

:tw_safevol_dose
if %SDK% LSS 34 (
    echo [%r%^^!%w%] Needs Android 14 or newer - this device reports API %SDK%.
    timeout /t 2 /nobreak >nul
    goto tw_safevol
)
adb shell cmd audio set-sound-dose-value 0.0 <nul
echo  Accumulated sound dose reset to 0. Applies live.
timeout /t 2 /nobreak >nul
goto tw_safevol

:tw_safevol_csdoff
if %SDK% LSS 34 (
    echo [%r%^^!%w%] Needs Android 14 or newer - this device reports API %SDK%.
    timeout /t 2 /nobreak >nul
    goto tw_safevol
)
:: Only matters where CSD is available-but-not-enforced; harmless elsewhere.
call :_tw_undo_add secure audio_safe_csd_as_a_feature_enabled
adb shell settings put secure audio_safe_csd_as_a_feature_enabled 0 <nul
echo  audio_safe_csd_as_a_feature_enabled (secure) set to 0.
timeout /t 2 /nobreak >nul
goto tw_safevol

:tw_explorer
cls
title Settings Explorer
call :logo
echo.
echo  Namespaces: system / secure / global.  Values are limited to the
echo  charset  A-Z a-z 0-9 _ . , : / = + -  (no spaces or shell chars);
echo  anything fancier: use the Shell option in the main menu.
echo.
echo    %g%[%w%1%g%]%w% List keys (optional substring filter)
echo    %g%[%w%2%g%]%w% Get a key
echo    %g%[%w%3%g%]%w% Put a key    (previous value saved to an undo script)
echo    %g%[%w%4%g%]%w% Delete a key (same undo protection)
echo    %g%[%w%5%g%]%w% Back
set "tx=" & set /p tx="Choose An Option >> "
if not defined tx goto tw_explorer
if "!tx!"=="1" goto tw_exp_list
if "!tx!"=="2" goto tw_exp_get
if "!tx!"=="3" goto tw_exp_put
if "!tx!"=="4" goto tw_exp_del
if "!tx!"=="5" goto settools
goto tw_explorer

:tw_exp_list
call :_tw_askns
if not defined EXP_NS goto tw_explorer
set "EXP_FLT=" & set /p EXP_FLT="Filter substring (blank = list all) >> "
if not defined EXP_FLT goto tw_exp_list_go
set "EXP_FLT=!EXP_FLT:"=!"
if not defined EXP_FLT goto tw_exp_list_go
call :_tw_safechk EXP_FLT || goto tw_exp_bad
echo(!EXP_FLT!| findstr /r /x /c:"[a-zA-Z0-9_.-][a-zA-Z0-9_.-]*" >nul || goto tw_exp_bad

:tw_exp_list_go
echo  ---- %EXP_NS% ----
if defined EXP_FLT (
    adb shell settings list %EXP_NS% <nul 2>nul | findstr /i /c:"%EXP_FLT%" | more
) else (
    adb shell settings list %EXP_NS% <nul 2>nul | more
)
echo  ---- end of %EXP_NS% ----
echo  Press any key . . .
pause >nul
goto tw_explorer

:tw_exp_get
call :_tw_askns
if not defined EXP_NS goto tw_explorer
call :_tw_askkey
if not defined EXP_KEY goto tw_explorer
set "EXP_OLD="
for /f "delims=" %%v in ('adb shell settings get %EXP_NS% %EXP_KEY% 2^>nul ^<nul') do set "EXP_OLD=%%v"
if "!EXP_OLD!"=="" set "EXP_OLD=null"
:: Value comes from the device and can contain cmd metacharacters - strip
:: quotes, then keep it inside quotes when echoing (:_bk_settings fix class).
set "EXP_OLD=!EXP_OLD:"=!"
echo.
echo  %EXP_NS% %EXP_KEY% = "!EXP_OLD!"
echo  Press any key . . .
pause >nul
goto tw_explorer

:tw_exp_put
call :_tw_askns
if not defined EXP_NS goto tw_explorer
call :_tw_askkey
if not defined EXP_KEY goto tw_explorer
set "EXP_OLD="
for /f "delims=" %%v in ('adb shell settings get %EXP_NS% %EXP_KEY% 2^>nul ^<nul') do set "EXP_OLD=%%v"
if "!EXP_OLD!"=="" set "EXP_OLD=null"
set "EXP_OLD=!EXP_OLD:"=!"
echo  Current value: "!EXP_OLD!"
set "EXP_VAL=" & set /p EXP_VAL="New value (blank = cancel) >> "
if not defined EXP_VAL goto tw_explorer
set "EXP_VAL=!EXP_VAL:"=!"
if not defined EXP_VAL goto tw_explorer
call :_tw_safechk EXP_VAL || goto tw_exp_bad
echo(!EXP_VAL!| findstr /r /x /c:"[a-zA-Z0-9_.,:/=+-][a-zA-Z0-9_.,:/=+-]*" >nul || goto tw_exp_bad
echo.
echo  Command: adb shell settings put %EXP_NS% %EXP_KEY% !EXP_VAL!
set "ok=" & set /p ok="Run it? (y = yes, anything else = cancel) >> "
if /i not "!ok!"=="y" goto tw_explorer
call :_tw_undo_add %EXP_NS% %EXP_KEY%
adb shell settings put %EXP_NS% %EXP_KEY% !EXP_VAL! <nul
set "EXP_NEW="
for /f "delims=" %%v in ('adb shell settings get %EXP_NS% %EXP_KEY% 2^>nul ^<nul') do set "EXP_NEW=%%v"
if "!EXP_NEW!"=="" set "EXP_NEW=null"
set "EXP_NEW=!EXP_NEW:"=!"
echo  Read-back: %EXP_NS% %EXP_KEY% = "!EXP_NEW!"
echo  Undo script: %EXP_UNDO%
echo  Press any key . . .
pause >nul
goto tw_explorer

:tw_exp_del
call :_tw_askns
if not defined EXP_NS goto tw_explorer
call :_tw_askkey
if not defined EXP_KEY goto tw_explorer
set "EXP_OLD="
for /f "delims=" %%v in ('adb shell settings get %EXP_NS% %EXP_KEY% 2^>nul ^<nul') do set "EXP_OLD=%%v"
if "!EXP_OLD!"=="" set "EXP_OLD=null"
set "EXP_OLD=!EXP_OLD:"=!"
echo  Current value: "!EXP_OLD!"
echo.
echo  Command: adb shell settings delete %EXP_NS% %EXP_KEY%
set "ok=" & set /p ok="Run it? (y = yes, anything else = cancel) >> "
if /i not "!ok!"=="y" goto tw_explorer
call :_tw_undo_add %EXP_NS% %EXP_KEY%
for /f "delims=" %%i in ('adb shell settings delete %EXP_NS% %EXP_KEY% 2^>nul ^<nul') do echo  %%i
echo  Undo script: %EXP_UNDO%
echo  Press any key . . .
pause >nul
goto tw_explorer

:tw_exp_bad
echo [%r%^^!%w%] Not allowed - stick to letters, digits and _ . , : / = + -
timeout /t 2 /nobreak >nul
goto tw_explorer
:: -------------------------------------------------------------------
:: Explorer helpers
::
:: _tw_askns / _tw_askkey  ask for a namespace / whitelist-checked key;
:: an empty EXP_NS / EXP_KEY on return means cancelled or invalid.
:: -------------------------------------------------------------------
:_tw_askns
set "EXP_NS="
set "tn=" & set /p tn="Namespace (1=system 2=secure 3=global, blank=cancel) >> "
if "!tn!"=="1" set "EXP_NS=system"
if "!tn!"=="2" set "EXP_NS=secure"
if "!tn!"=="3" set "EXP_NS=global"
exit /b

:_tw_askkey
set "EXP_KEY="
set "tk=" & set /p tk="Key name (blank = cancel) >> "
if not defined tk exit /b
set "tk=!tk:"=!"
if not defined tk exit /b
call :_tw_safechk tk || exit /b
echo(!tk!| findstr /r /x /c:"[a-zA-Z0-9_.-][a-zA-Z0-9_.-]*" >nul || exit /b
set "EXP_KEY=!tk!"
exit /b

:_tw_safechk
:: %1 = NAME of a variable (callers strip double quotes first). Fails with
:: errorlevel 1 if the value holds a cmd metachar that would make the
:: `echo(!var!| findstr` whitelist probe itself unsafe. Each check runs
:: inside a quoted comparison, so the hostile char never sits in command
:: position. A caret needs no check: it self-escapes identically in the
:: probe and in the final adb line, and `^&`-style combos are caught by
:: the checks below before the caret matters.
if not defined %~1 exit /b 1
if not "!%~1:&=_!"=="!%~1!" exit /b 1
if not "!%~1:|=_!"=="!%~1!" exit /b 1
if not "!%~1:<=_!"=="!%~1!" exit /b 1
if not "!%~1:>=_!"=="!%~1!" exit /b 1
exit /b 0

:_tw_undo_ensure
:: Lazily create a session undo .bat with :dcx_do / :dcx_report defined UP TOP
:: and a :dcx_main section that grows. New restore lines are inserted before
:: the trailing "goto :dcx_report" so the file stays runnable after every write.
if defined EXP_UNDO exit /b 0
set "BACKUPDIR=%USERPROFILE%\dcx_backups"
if not exist "%BACKUPDIR%" mkdir "%BACKUPDIR%"
set "TS=%date%_%time%"
set "TS=%TS::=-%"
set "TS=%TS:/=-%"
set "TS=%TS:\=-%"
set "TS=%TS:.=-%"
set "TS=%TS:,=-%"
set "TS=%TS: =_%"
set "EXP_UNDO=%BACKUPDIR%\dcx_explorer_undo_%TS%.bat"
call :_bk_write_adb_boot "%EXP_UNDO%"
(
    echo :: DCX Settings-Explorer / Tweaks undo - restores values before writes.
    echo :: Safe to re-run. Uses %%ADB%% from the header ^(not bare adb^).
    echo :: Labels BEFORE :dcx_main so appended call :dcx_do lines stay in :dcx_main.
    echo goto :dcx_main
    echo.
    echo :dcx_do
    echo "%%ADB%%" shell %%* ^>nul 2^>^&1
    echo if errorlevel 1 ^(
    echo     set /a DCX_FAIL+=1
    echo     echo   [FAIL] %%*
    echo ^) else ^(
    echo     set /a DCX_OK+=1
    echo ^)
    echo goto :eof
    echo.
    echo :dcx_hold
    echo if defined DCX_NOPAUSE exit /b 0
    echo echo.
    echo echo ----------------------------------------
    echo echo Press any key to close this window . . .
    echo pause
    echo exit /b 0
    echo.
    echo :dcx_report
    echo echo.
    echo if "%%DCX_FAIL%%"=="0" ^(
    echo     echo [OK] Restored %%DCX_OK%% settings, none failed.
    echo ^) else ^(
    echo     echo [WARN] %%DCX_OK%% restored, %%DCX_FAIL%% FAILED - listed above.
    echo ^)
    echo echo.
    echo call :dcx_hold
    echo exit /b %%DCX_FAIL%%
    echo.
    echo :dcx_main
    echo set "DCX_OK=0" ^& set "DCX_FAIL=0"
    echo goto :dcx_report
) >> "%EXP_UNDO%"
>"%BACKUPDIR%\dcx_last_undo.txt" echo !EXP_UNDO!
exit /b 0

:_tw_undo_add
:: Capture settings namespace/key into the session undo script before a write.
call :_tw_undo_ensure
call :_tw_undo_prep || goto _tw_undo_broken
call :_bk_settings %~1 %~2 "%EXP_UNDO%"
call :_tw_undo_finish
exit /b

:_tw_undo_dcfgsync
:: Capture DeviceConfig sync mode into the same undo script.
call :_tw_undo_ensure
call :_tw_undo_prep || goto _tw_undo_broken
call :_bk_dcfgsync "%EXP_UNDO%"
call :_tw_undo_finish
exit /b

:_tw_undo_broken
:: Reached only when :_tw_undo_prep could not rewrite the undo script. Appending anyway
:: would put the restore line AFTER "goto :dcx_report", where it never runs - an undo
:: file that looks populated and restores nothing. Skip the append and SAY SO: the write
:: the caller is about to make will not be undoable, and staying quiet about that is the
:: exact failure this guard exists to prevent.
echo  [%y%WARN%w%] Could not update the undo script - this change will NOT be recorded.
echo         Check %USERPROFILE%\dcx_backups is writable ^(antivirus / Controlled
echo         Folder Access are the usual cause^).
exit /b 1

:_tw_undo_prep
:: Drop the trailing "goto :dcx_report" under :dcx_main so the next
:: call :dcx_do line is appended inside :dcx_main ^(not after :dcx_hold^).
if not defined EXP_UNDO exit /b 1
if not exist "%EXP_UNDO%" exit /b 1
:: FIX (silent undo loss): redirection CREATES the .tmp before findstr runs, and the old
:: guard tested only existence - so a findstr that failed for any reason left a 0-byte
:: .tmp that `move /y` then copied over the real undo script, wiping every captured
:: value with no message. Require the rewritten file to still carry its :dcx_main label
:: before trusting it; on any doubt keep the original untouched and fail to the caller.
del "%EXP_UNDO%.tmp" > nul 2>&1
findstr /v /b /c:"goto :dcx_report" "%EXP_UNDO%" > "%EXP_UNDO%.tmp" 2>nul
findstr /b /c:":dcx_main" "%EXP_UNDO%.tmp" >nul 2>&1 || goto _tw_undo_prep_fail
move /y "%EXP_UNDO%.tmp" "%EXP_UNDO%" >nul || goto _tw_undo_prep_fail
exit /b 0

:_tw_undo_prep_fail
del "%EXP_UNDO%.tmp" > nul 2>&1
exit /b 1

:_tw_undo_finish
>>"%EXP_UNDO%" echo goto :dcx_report
exit /b 0

:tw_snapshot
cls
title Settings Snapshot
call :logo
set "SNAPDIR=%USERPROFILE%\dcx_snapshots"
if not exist "%SNAPDIR%" mkdir "%SNAPDIR%"
echo.
echo  Dump all three settings tables, poke something in the device UI,
echo  dump again, diff - and you know exactly which key that toggle writes.
echo  Folder: %SNAPDIR%
echo.
echo    %g%[%w%1%g%]%w% Take a snapshot now (system + secure + global)
echo    %g%[%w%2%g%]%w% Diff the two most recent snapshots
echo    %g%[%w%3%g%]%w% Open snapshots folder
echo    %g%[%w%4%g%]%w% Back
set "sn=" & set /p sn="Choose An Option >> "
if not defined sn goto tw_snapshot
if "!sn!"=="1" goto tw_snap_take
if "!sn!"=="2" goto tw_snap_diff
if "!sn!"=="3" (start "" "%SNAPDIR%" & goto tw_snapshot)
if "!sn!"=="4" goto settools
goto tw_snapshot

:tw_snap_take
set "TS=%date%_%time%"
set "TS=%TS::=-%"
set "TS=%TS:/=-%"
set "TS=%TS:\=-%"
set "TS=%TS:.=-%"
set "TS=%TS:,=-%"
set "TS=%TS: =_%"
echo  Dumping...
:: `find /v ""` re-terminates adb's LF-only lines as CRLF (documented DCX
:: failure mode) so fc behaves later; `sort` gives a stable key order.
for %%n in (system secure global) do (
    adb shell settings list %%n <nul 2>nul | find /v "" | sort > "%SNAPDIR%\%%n_%TS%.txt"
)
echo  Done:
dir /b "%SNAPDIR%\*_%TS%.txt"
echo  Press any key . . .
pause >nul
goto tw_snapshot

:tw_snap_diff
set "SNP1="
set "SNP2="
for /f "delims=" %%f in ('dir /b /o-d /a-d "%SNAPDIR%\global_*.txt" 2^>nul') do (
    if not defined SNP1 (set "SNP1=%%f") else if not defined SNP2 set "SNP2=%%f"
)
if not defined SNP2 (
    echo [%r%^^!%w%] Need at least two snapshots first.
    timeout /t 2 /nobreak >nul
    goto tw_snapshot
)
set "TSNEW=!SNP1:~7,-4!"
set "TSOLD=!SNP2:~7,-4!"
set "TS=%date%_%time%"
set "TS=%TS::=-%"
set "TS=%TS:/=-%"
set "TS=%TS:\=-%"
set "TS=%TS:.=-%"
set "TS=%TS:,=-%"
set "TS=%TS: =_%"
set "DIFFOUT=%SNAPDIR%\diff_%TS%.txt"
> "%DIFFOUT%" echo DCX settings diff:  %TSOLD%  -^>  %TSNEW%
for %%n in (system secure global) do (
    >>"%DIFFOUT%" echo.
    >>"%DIFFOUT%" echo ===== %%n =====
    fc /l "%SNAPDIR%\%%n_%TSOLD%.txt" "%SNAPDIR%\%%n_%TSNEW%.txt" >>"%DIFFOUT%" 2>&1
)
cls
call :logo
echo  Comparing %TSOLD%  (older)
echo         to %TSNEW%  (newer)
echo.
more < "%DIFFOUT%"
echo.
echo  Saved to: %DIFFOUT%
echo    %g%[%w%1%g%]%w% Open in Notepad
echo    %g%[%w%2%g%]%w% Back
set "sd=" & set /p sd="Choose An Option >> "
if "!sd!"=="1" (start "" notepad "%DIFFOUT%" & goto tw_snapshot)
if "!sd!"=="2" goto tw_snapshot
goto tw_snapshot
:: ===================================================================
:: NEW (Tier 2): icon blacklist, demo mode, heads-up, font scale,
:: long-press timeout, stay-awake, night modes, profiles.
::
:: Keys verified against AOSP main and zacharee/Tweaker @ 0053893:
::   secure icon_blacklist            BlacklistPersistenceHandler.kt:9
::   global heads_up_notifications_enabled   Settings.java:17467
::   system font_scale                Settings.java:5135 (default 1.0)
::   secure long_press_timeout        Settings.java:9273
::   global stay_on_while_plugged_in  Settings.java:13420; bits from
::                                    BatteryManager: AC=1 USB=2
::                                    WIRELESS=4 DOCK=8
::   cmd uimode night [yes^|no^|auto]   UiModeManagerService.java:2150
::   secure night_display_*           Settings.java:11493-11507
::   global sysui_demo_allowed + broadcast com.android.systemui.demo
::                                    DemoController.kt:41-51
:: Animation scales are NOT here - Optimize > Animation Speed already
:: owns those three keys.
:: ===================================================================
:tw_icons
cls
title Icon Blacklist
call :logo
echo.
set "IBCUR="
for /f "delims=" %%i in ('adb shell settings get secure icon_blacklist 2^>nul ^<nul') do set "IBCUR=%%i"
if "!IBCUR!"=="" set "IBCUR=null"
set "IBCUR=!IBCUR:"=!"
echo  icon_blacklist (secure) = "!IBCUR!"
echo  A comma-separated list of status bar slots to hide. Applies live on
echo  AOSP-based status bars. Slot names are OEM-dependent - an unknown
echo  name is simply ignored by SystemUI, it does not break anything.
echo.
echo    %g%[%w%1%g%]%w% Hide an icon
echo    %g%[%w%2%g%]%w% Show an icon again
echo    %g%[%w%3%g%]%w% Clear the list (delete key - every icon returns)
echo    %g%[%w%4%g%]%w% Back
set "ic=" & set /p ic="Choose An Option >> "
if not defined ic goto tw_icons
if "!ic!"=="1" goto tw_ib_add
if "!ic!"=="2" goto tw_ib_del
if "!ic!"=="3" goto tw_ib_clear
if "!ic!"=="4" goto tweaks
goto tw_icons

:tw_ib_add
cls
title Icon Blacklist : hide
call :logo
echo.
:: Slot vocabulary = Tweaker's AOSP-general category (IconBlacklistFragment
:: .kt:167-225). Some icons answer to two names across versions, so those
:: entries write both.
echo  Pick a slot to hide:
echo    %g%[%w%1%g%]%w% rotate           (auto-rotate lock)
echo    %g%[%w%2%g%]%w% alarm            (alarm + alarm_clock)
echo    %g%[%w%3%g%]%w% bluetooth
echo    %g%[%w%4%g%]%w% volume
echo    %g%[%w%5%g%]%w% headset
echo    %g%[%w%6%g%]%w% cast
echo    %g%[%w%7%g%]%w% hotspot
echo    %g%[%w%8%g%]%w% location
echo    %g%[%w%9%g%]%w% managed_profile  (work profile badge)
echo    %g%[%w%10%g%]%w% vpn
echo    %g%[%w%11%g%]%w% nfc             (nfc + nfc_on)
echo    %g%[%w%12%g%]%w% dnd             (zen + dnd + do_not_disturb)
echo    %g%[%w%13%g%]%w% data_saver
echo    %g%[%w%14%g%]%w% ime             (keyboard switcher)
echo    %g%[%w%15%g%]%w% mute
echo    %g%[%w%16%g%]%w% Type a slot name myself
echo    %g%[%w%17%g%]%w% Back
set "IBSEL=" & set /p IBSEL="Choose An Option >> "
if not defined IBSEL goto tw_ib_add
set "IBTOK="
if "!IBSEL!"=="1" set "IBTOK=rotate"
if "!IBSEL!"=="2" set "IBTOK=alarm,alarm_clock"
if "!IBSEL!"=="3" set "IBTOK=bluetooth"
if "!IBSEL!"=="4" set "IBTOK=volume"
if "!IBSEL!"=="5" set "IBTOK=headset"
if "!IBSEL!"=="6" set "IBTOK=cast"
if "!IBSEL!"=="7" set "IBTOK=hotspot"
if "!IBSEL!"=="8" set "IBTOK=location"
if "!IBSEL!"=="9" set "IBTOK=managed_profile"
if "!IBSEL!"=="10" set "IBTOK=vpn"
if "!IBSEL!"=="11" set "IBTOK=nfc,nfc_on"
if "!IBSEL!"=="12" set "IBTOK=zen,dnd,do_not_disturb"
if "!IBSEL!"=="13" set "IBTOK=data_saver"
if "!IBSEL!"=="14" set "IBTOK=ime"
if "!IBSEL!"=="15" set "IBTOK=mute"
if "!IBSEL!"=="16" goto tw_ib_custom
if "!IBSEL!"=="17" goto tw_icons
if not defined IBTOK goto tw_ib_add
goto tw_ib_addgo

:tw_ib_custom
echo.
echo  Slot names are lowercase letters, digits and _ (comma-separate a few).
set "IBTOK=" & set /p IBTOK="Slot name (blank = cancel) >> "
if not defined IBTOK goto tw_ib_add
set "IBTOK=!IBTOK:"=!"
if not defined IBTOK goto tw_ib_add
call :_tw_safechk IBTOK || goto tw_ib_bad
echo(!IBTOK!| findstr /r /x /c:"[a-z0-9_,][a-z0-9_,]*" >nul || goto tw_ib_bad
goto tw_ib_addgo

:tw_ib_addgo
call :_tw_undo_add secure icon_blacklist
:: Rebuild rather than blind-append: drop any token we are about to add, so
:: re-hiding an icon cannot pile up duplicates. IBTOK may carry several
:: names (nfc,nfc_on), hence the inner loop; `if defined` reads runtime
:: state, so it stays correct inside a parenthesized block.
set "IBNEW="
if "!IBCUR!"=="null" goto _tw_ib_addput
for %%t in (!IBCUR!) do (
    set "IBHIT="
    for %%u in (!IBTOK!) do if /i "%%t"=="%%u" set "IBHIT=1"
    if not defined IBHIT set "IBNEW=!IBNEW!,%%t"
)

:_tw_ib_addput
set "IBNEW=!IBNEW!,!IBTOK!"
set "IBNEW=!IBNEW:~1!"
adb shell settings put secure icon_blacklist !IBNEW! <nul
goto tw_icons

:tw_ib_del
cls
title Icon Blacklist : restore
call :logo
echo.
if "!IBCUR!"=="null" goto tw_ib_empty
:: Clear any stale IBT_n from an earlier, longer list before renumbering.
for /f "delims==" %%v in ('set IBT_ 2^>nul') do set "%%v="
set "IBN=0"
echo  Currently hidden:
for %%t in (!IBCUR!) do (
    set /a IBN+=1
    set "IBT_!IBN!=%%t"
    echo     %g%[%w%!IBN!%g%]%w% %%t
)
echo     %g%[%w%0%g%]%w% Back
set "IBPICK=" & set /p IBPICK="Restore which? >> "
if not defined IBPICK goto tw_ib_del
if "!IBPICK!"=="0" goto tw_icons
call :_tw_safechk IBPICK || goto tw_ib_del
echo(!IBPICK!| findstr /r /x /c:"[0-9][0-9]*" >nul || goto tw_ib_del
set "IBTOK="
if defined IBT_!IBPICK! for /f "delims=" %%v in ("!IBPICK!") do set "IBTOK=!IBT_%%v!"
if not defined IBTOK goto tw_ib_del
call :_tw_undo_add secure icon_blacklist
set "IBNEW="
for %%t in (!IBCUR!) do if not "%%t"=="!IBTOK!" set "IBNEW=!IBNEW!,%%t"
if not defined IBNEW goto tw_ib_clear
set "IBNEW=!IBNEW:~1!"
adb shell settings put secure icon_blacklist !IBNEW! <nul
goto tw_icons

:tw_ib_empty
echo  The blacklist is empty - nothing to restore.
timeout /t 2 /nobreak >nul
goto tw_icons

:tw_ib_clear
call :_tw_undo_add secure icon_blacklist
adb shell settings delete secure icon_blacklist >nul 2>&1 <nul
goto tw_icons

:tw_ib_bad
echo [%r%^^!%w%] Not allowed - lowercase letters, digits, _ and commas only.
timeout /t 2 /nobreak >nul
goto tw_ib_add

:tw_headsup
cls
title Heads-up Notifications
call :logo
echo.
set "HUV="
for /f "delims=" %%i in ('adb shell settings get global heads_up_notifications_enabled 2^>nul ^<nul') do set "HUV=%%i"
if "!HUV!"=="" set "HUV=null"
set "HUV=!HUV:"=!"
echo  heads_up_notifications_enabled (global) = "!HUV!"
echo    (1/null = pop-ups shown, 0 = notifications go straight to the shade)
echo  Applies to every app at once. Per-app control lives in the device's
echo  own notification settings, not here.
echo.
echo    %g%[%w%1%g%]%w% Enable pop-ups
echo    %g%[%w%2%g%]%w% Disable pop-ups
echo    %g%[%w%3%g%]%w% Reset to device default (delete key)
echo    %g%[%w%4%g%]%w% Back
set "hu=" & set /p hu="Choose An Option >> "
if not defined hu goto tw_headsup
if "!hu!"=="1" (call :_tw_undo_add global heads_up_notifications_enabled & adb shell settings put global heads_up_notifications_enabled 1 <nul & goto tw_headsup)
if "!hu!"=="2" (call :_tw_undo_add global heads_up_notifications_enabled & adb shell settings put global heads_up_notifications_enabled 0 <nul & goto tw_headsup)
if "!hu!"=="3" (call :_tw_undo_add global heads_up_notifications_enabled & adb shell settings delete global heads_up_notifications_enabled >nul 2>&1 <nul & goto tw_headsup)
if "!hu!"=="4" goto tweaks
goto tw_headsup

:tw_font
cls
title Font Scale
call :logo
echo.
set "FSV="
for /f "delims=" %%i in ('adb shell settings get system font_scale 2^>nul ^<nul') do set "FSV=%%i"
if "!FSV!"=="" set "FSV=null"
set "FSV=!FSV:"=!"
echo  font_scale (system) = "!FSV!"   (1.0 = platform default)
echo  Applies live. DCX accepts 0.5 - 2.0 only: outside that range app
echo  layouts start clipping and some dialogs lose their buttons.
echo.
echo    %g%[%w%1%g%]%w% 0.85  (small)
echo    %g%[%w%2%g%]%w% 1.0   (default)
echo    %g%[%w%3%g%]%w% 1.15  (large)
echo    %g%[%w%4%g%]%w% 1.30  (larger)
echo    %g%[%w%5%g%]%w% Custom (0.5 - 2.0)
echo    %g%[%w%6%g%]%w% Reset to device default (delete key)
echo    %g%[%w%7%g%]%w% Back
set "fs=" & set /p fs="Choose An Option >> "
if not defined fs goto tw_font
if "!fs!"=="1" (set "FSNEW=0.85" & goto tw_font_apply)
if "!fs!"=="2" (set "FSNEW=1.0" & goto tw_font_apply)
if "!fs!"=="3" (set "FSNEW=1.15" & goto tw_font_apply)
if "!fs!"=="4" (set "FSNEW=1.30" & goto tw_font_apply)
if "!fs!"=="5" goto tw_font_custom
if "!fs!"=="6" (call :_tw_undo_add system font_scale & adb shell settings delete system font_scale >nul 2>&1 <nul & goto tw_font)
if "!fs!"=="7" goto tweaks
goto tw_font

:tw_font_custom
echo.
echo  Enter a scale between 0.5 and 2.0 (e.g. 1.15).
set "FSNEW=" & set /p FSNEW="Value (blank = cancel) >> "
if not defined FSNEW goto tw_font
set "FSNEW=!FSNEW:"=!"
if not defined FSNEW goto tw_font
:: Cyrillic-locale comma decimal (1,15) normalizes to a dot before it can
:: reach adb - same guard as Optimize > Animation Speed.
set "FSNEW=!FSNEW:,=.!"
call :_tw_safechk FSNEW || goto tw_font_bad
echo(!FSNEW!| findstr /r /x /c:"0\.[5-9][0-9]*" /c:"\.[5-9][0-9]*" /c:"1" /c:"1\.[0-9][0-9]*" /c:"2" /c:"2\.0*" >nul || goto tw_font_bad
goto tw_font_apply

:tw_font_bad
echo [%r%^^!%w%] Invalid value. Use 0.5 to 2.0, e.g. 0.85, 1.0, 1.15.
timeout /t 2 /nobreak >nul
goto tw_font_custom

:tw_font_apply
call :_tw_undo_add system font_scale
adb shell settings put system font_scale !FSNEW! <nul
goto tw_font

:tw_lpt
cls
title Long-press Timeout
call :logo
echo.
set "LPTV="
for /f "delims=" %%i in ('adb shell settings get secure long_press_timeout 2^>nul ^<nul') do set "LPTV=%%i"
if "!LPTV!"=="" set "LPTV=null"
set "LPTV=!LPTV:"=!"
echo  long_press_timeout (secure) = "!LPTV!" ms   (platform default 400)
echo  How long a touch must be held before it counts as a long-press.
echo.
echo  Worth knowing: Battery ^> Animation ^> Off also pins this key to 250,
echo  and Animation ^> On deletes it. Whichever you run last wins.
echo.
echo    %g%[%w%1%g%]%w% 250   (fast - what Animation Off uses)
echo    %g%[%w%2%g%]%w% 400   (platform default)
echo    %g%[%w%3%g%]%w% 1000  (slow)
echo    %g%[%w%4%g%]%w% 1500  (slowest - accessibility)
echo    %g%[%w%5%g%]%w% Custom (10 - 9999 ms)
echo    %g%[%w%6%g%]%w% Reset to device default (delete key)
echo    %g%[%w%7%g%]%w% Back
set "lpt=" & set /p lpt="Choose An Option >> "
if not defined lpt goto tw_lpt
if "!lpt!"=="1" (set "LPTNEW=250" & goto tw_lpt_apply)
if "!lpt!"=="2" (set "LPTNEW=400" & goto tw_lpt_apply)
if "!lpt!"=="3" (set "LPTNEW=1000" & goto tw_lpt_apply)
if "!lpt!"=="4" (set "LPTNEW=1500" & goto tw_lpt_apply)
if "!lpt!"=="5" goto tw_lpt_custom
if "!lpt!"=="6" (call :_tw_undo_add secure long_press_timeout & adb shell settings delete secure long_press_timeout >nul 2>&1 <nul & goto tw_lpt)
if "!lpt!"=="7" goto tweaks
goto tw_lpt

:tw_lpt_custom
echo.
set "LPTNEW=" & set /p LPTNEW="Milliseconds (blank = cancel) >> "
if not defined LPTNEW goto tw_lpt
set "LPTNEW=!LPTNEW:"=!"
if not defined LPTNEW goto tw_lpt
call :_tw_safechk LPTNEW || goto tw_lpt_bad
echo(!LPTNEW!| findstr /r /x /c:"[1-9][0-9]" /c:"[1-9][0-9][0-9]" /c:"[1-9][0-9][0-9][0-9]" >nul || goto tw_lpt_bad
goto tw_lpt_apply

:tw_lpt_bad
echo [%r%^^!%w%] Invalid value. Whole milliseconds, 10 to 9999.
timeout /t 2 /nobreak >nul
goto tw_lpt_custom

:tw_lpt_apply
call :_tw_undo_add secure long_press_timeout
adb shell settings put secure long_press_timeout !LPTNEW! <nul
goto tw_lpt

:tw_stay
cls
title Stay Awake While Charging
call :logo
echo.
set "SAWV="
for /f "delims=" %%i in ('adb shell settings get global stay_on_while_plugged_in 2^>nul ^<nul') do set "SAWV=%%i"
if "!SAWV!"=="" set "SAWV=null"
set "SAWV=!SAWV:"=!"
echo  stay_on_while_plugged_in (global) = "!SAWV!"
echo  Bitmask, add the sources you want:  AC=1  USB=2  wireless=4  dock=8
echo  (0 = off). The screen then never sleeps while charging that way -
echo  handy on a desk, rough on an OLED panel over time.
echo.
echo    %g%[%w%1%g%]%w% Off (0)
echo    %g%[%w%2%g%]%w% AC only (1)
echo    %g%[%w%3%g%]%w% USB only (2)
echo    %g%[%w%4%g%]%w% AC + USB (3)
echo    %g%[%w%5%g%]%w% AC + USB + wireless (7)
echo    %g%[%w%6%g%]%w% Everything incl. dock (15)
echo    %g%[%w%7%g%]%w% Custom (0 - 15)
echo    %g%[%w%8%g%]%w% Reset to device default (delete key)
echo    %g%[%w%9%g%]%w% Back
set "saw=" & set /p saw="Choose An Option >> "
if not defined saw goto tw_stay
if "!saw!"=="1" (set "SAWNEW=0" & goto tw_stay_apply)
if "!saw!"=="2" (set "SAWNEW=1" & goto tw_stay_apply)
if "!saw!"=="3" (set "SAWNEW=2" & goto tw_stay_apply)
if "!saw!"=="4" (set "SAWNEW=3" & goto tw_stay_apply)
if "!saw!"=="5" (set "SAWNEW=7" & goto tw_stay_apply)
if "!saw!"=="6" (set "SAWNEW=15" & goto tw_stay_apply)
if "!saw!"=="7" goto tw_stay_custom
if "!saw!"=="8" (call :_tw_undo_add global stay_on_while_plugged_in & adb shell settings delete global stay_on_while_plugged_in >nul 2>&1 <nul & goto tw_stay)
if "!saw!"=="9" goto tweaks
goto tw_stay

:tw_stay_custom
echo.
set "SAWNEW=" & set /p SAWNEW="Bitmask 0 - 15 (blank = cancel) >> "
if not defined SAWNEW goto tw_stay
set "SAWNEW=!SAWNEW:"=!"
if not defined SAWNEW goto tw_stay
call :_tw_safechk SAWNEW || goto tw_stay_bad
echo(!SAWNEW!| findstr /r /x /c:"[0-9]" /c:"1[0-5]" >nul || goto tw_stay_bad
goto tw_stay_apply

:tw_stay_bad
echo [%r%^^!%w%] Invalid value. A whole number from 0 to 15.
timeout /t 2 /nobreak >nul
goto tw_stay_custom

:tw_stay_apply
call :_tw_undo_add global stay_on_while_plugged_in
adb shell settings put global stay_on_while_plugged_in !SAWNEW! <nul
goto tw_stay

:tw_night
cls
title Night
call :logo
echo.
echo  Two different features share the name "night mode":
echo    Dark theme  - the system-wide dark UI    (cmd uimode night)
echo    Night light - the warm blue-light filter (night_display_*)
echo.
echo  Dark theme, as the device reports it:
for /f "delims=" %%i in ('adb shell cmd uimode night 2^>nul ^<nul') do echo    %%i
set "NDA="
for /f "delims=" %%i in ('adb shell settings get secure night_display_activated 2^>nul ^<nul') do set "NDA=%%i"
if "!NDA!"=="" set "NDA=null"
set "NDA=!NDA:"=!"
echo  night_display_activated (secure) = "!NDA!"   (1 = filter on)
echo.
:: setNightModeInternal only demands MODIFY_DAY_NIGHT_MODE when the ROM
:: locks night mode (UiModeManagerService.java) - it then returns quietly.
:: The command prints the resulting mode, so the line above is the honest
:: read-back rather than a claim of success.
echo  Dark theme is set through the uimode service, which prints the mode it
echo  ended up in - if a ROM locks it, the readout above simply will not move.
echo.
echo    %g%[%w%1%g%]%w% Dark theme on
echo    %g%[%w%2%g%]%w% Dark theme off
echo    %g%[%w%3%g%]%w% Dark theme auto (follow sunset/schedule)
echo    %g%[%w%4%g%]%w% Night light on
echo    %g%[%w%5%g%]%w% Night light off
echo    %g%[%w%6%g%]%w% Night light colour temperature
echo    %g%[%w%7%g%]%w% Back
set "nm=" & set /p nm="Choose An Option >> "
if not defined nm goto tw_night
if "!nm!"=="1" (adb shell cmd uimode night yes <nul & timeout /t 1 /nobreak >nul & goto tw_night)
if "!nm!"=="2" (adb shell cmd uimode night no <nul & timeout /t 1 /nobreak >nul & goto tw_night)
if "!nm!"=="3" (adb shell cmd uimode night auto <nul & timeout /t 1 /nobreak >nul & goto tw_night)
if "!nm!"=="4" (call :_tw_undo_add secure night_display_activated & adb shell settings put secure night_display_activated 1 <nul & goto tw_night)
if "!nm!"=="5" (call :_tw_undo_add secure night_display_activated & adb shell settings put secure night_display_activated 0 <nul & goto tw_night)
if "!nm!"=="6" goto tw_night_temp
if "!nm!"=="7" goto tweaks
goto tw_night

:tw_night_temp
echo.
set "NDT="
for /f "delims=" %%i in ('adb shell settings get secure night_display_color_temperature 2^>nul ^<nul') do set "NDT=%%i"
if "!NDT!"=="" set "NDT=null"
set "NDT=!NDT:"=!"
echo  Current: "!NDT!" K. Lower = warmer/more orange. Typical 2850 - 4800.
set "NDT=" & set /p NDT="Kelvin (blank = cancel) >> "
if not defined NDT goto tw_night
set "NDT=!NDT:"=!"
if not defined NDT goto tw_night
call :_tw_safechk NDT || goto tw_night_bad
echo(!NDT!| findstr /r /x /c:"[1-9][0-9][0-9][0-9]" >nul || goto tw_night_bad
call :_tw_undo_add secure night_display_color_temperature
adb shell settings put secure night_display_color_temperature !NDT! <nul
goto tw_night

:tw_night_bad
echo [%r%^^!%w%] Invalid value. Four digits, e.g. 2850 or 4800.
timeout /t 2 /nobreak >nul
goto tw_night_temp

:tw_demo
cls
title Demo Mode
call :logo
echo.
echo  SystemUI demo mode freezes the status bar into a clean, fixed state -
echo  full signal, no clutter, a set clock - for screenshots. It is purely
echo  cosmetic, changes nothing real, and ends on exit or reboot.
echo.
set "DMA="
for /f "delims=" %%i in ('adb shell settings get global sysui_demo_allowed 2^>nul ^<nul') do set "DMA=%%i"
if "!DMA!"=="" set "DMA=null"
set "DMA=!DMA:"=!"
echo  sysui_demo_allowed (global) = "!DMA!"   (must be 1 for demo mode)
echo  There is no way to read back whether demo mode is currently ON - the
echo  state lives in SystemUI, not in a setting. Look at the device.
echo.
echo    %g%[%w%1%g%]%w% Enter demo mode (clean bar, 12:00, full signal)
echo    %g%[%w%2%g%]%w% Exit demo mode
echo    %g%[%w%3%g%]%w% Set the demo clock
echo    %g%[%w%4%g%]%w% Back
set "dm=" & set /p dm="Choose An Option >> "
if not defined dm goto tw_demo
if "!dm!"=="1" goto tw_demo_enter
if "!dm!"=="2" goto tw_demo_exit
if "!dm!"=="3" goto tw_demo_clock
if "!dm!"=="4" goto tweaks
goto tw_demo

:tw_demo_enter
:: Command set verified from DemoController.kt:44-51 - enter/exit/status/
:: network/clock/battery/bars are the only ones we send.
call :_tw_undo_add global sysui_demo_allowed
adb shell settings put global sysui_demo_allowed 1 <nul
adb shell am broadcast -a com.android.systemui.demo -e command enter <nul >nul 2>&1
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1200 <nul >nul 2>&1
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false <nul >nul 2>&1
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e fully true <nul >nul 2>&1
adb shell am broadcast -a com.android.systemui.demo -e command network -e mobile show -e datatype lte -e level 4 -e fully true <nul >nul 2>&1
adb shell am broadcast -a com.android.systemui.demo -e command status -e volume hide -e bluetooth hide -e location hide -e alarm hide -e sync hide -e tty hide -e eri hide -e mute hide -e speakerphone hide <nul >nul 2>&1
adb shell am broadcast -a com.android.systemui.demo -e command bars -e mode opaque <nul >nul 2>&1
echo  Demo mode requested. Check the device's status bar.
timeout /t 2 /nobreak >nul
goto tw_demo

:tw_demo_exit
adb shell am broadcast -a com.android.systemui.demo -e command exit <nul >nul 2>&1
echo  Exit sent - the real status bar should be back.
timeout /t 2 /nobreak >nul
goto tw_demo

:tw_demo_clock
echo.
set "DMH=" & set /p DMH="Clock as HHMM, e.g. 0930 (blank = cancel) >> "
if not defined DMH goto tw_demo
set "DMH=!DMH:"=!"
if not defined DMH goto tw_demo
call :_tw_safechk DMH || goto tw_demo_bad
echo(!DMH!| findstr /r /x /c:"[01][0-9][0-5][0-9]" /c:"2[0-3][0-5][0-9]" >nul || goto tw_demo_bad
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm !DMH! <nul >nul 2>&1
echo  Clock set to !DMH! (demo mode must already be on).
timeout /t 2 /nobreak >nul
goto tw_demo

:tw_demo_bad
echo [%r%^^!%w%] Invalid time. Four digits, HHMM, e.g. 0930 or 1200.
timeout /t 2 /nobreak >nul
goto tw_demo_clock
:: -------------------------------------------------------------------
:: Profiles - the Windows-side answer to SetEdit's on-device boot queue
:: (setedit/boot/BootUtils.java). A profile is a plain text file, so it
:: is editable, diffable and shareable without DCX being involved.
:: -------------------------------------------------------------------
:tw_profile
cls
title Profiles
call :logo
set "PROFDIR=%USERPROFILE%\dcx_profiles"
if not exist "%PROFDIR%" mkdir "%PROFDIR%"
echo.
echo  A profile is a plain text file, one key per line:
echo      namespace^|key^|value      e.g.  global^|audio_safe_volume_state^|2
echo      namespace^|key^|DELETE     removes the key
echo  Lines starting with # are ignored, so you can annotate freely.
echo.
echo  Apply re-writes every listed key in one pass - re-arm per-boot tweaks
echo  ^(volume cap^) or a whole Tweaks+Battery/Gaming stack after reboot.
echo  Folder: %PROFDIR%
echo.
echo    %g%[%w%1%g%]%w% Save Tweaks-only profile
echo    %g%[%w%2%g%]%w% Save full stack ^(Tweaks + Battery/Gaming keys^)
echo    %g%[%w%3%g%]%w% Apply a profile
echo    %g%[%w%4%g%]%w% Open the profiles folder
echo    %g%[%w%5%g%]%w% Back
set "pr=" & set /p pr="Choose An Option >> "
if not defined pr goto tw_profile
if "!pr!"=="1" (set "PROFMODE=tweaks" & goto tw_prof_save)
if "!pr!"=="2" (set "PROFMODE=stack" & goto tw_prof_save)
if "!pr!"=="3" goto tw_prof_apply
if "!pr!"=="4" (start "" "%PROFDIR%" & goto tw_profile)
if "!pr!"=="5" goto settools
goto tw_profile

:tw_prof_save
echo.
:: FIX (cosmetic): the parens were caret-escaped, but inside a double-quoted set /p
:: prompt a caret is NOT an escape character - it is printed. The prompt literally read
:: "Optional name ^(blank = auto timestamp^) >> ". Quotes already make ( ) safe here.
set "PROFNAME=" & set /p PROFNAME="Optional name (blank = auto timestamp) >> "
set "PROFNAME=!PROFNAME:"=!"
:: safechk first - it is pipe-free, so it strips & | < > before the findstr probe below
:: (which IS a pipe, and would re-parse them) ever sees the value.
if defined PROFNAME call :_tw_safechk PROFNAME || set "PROFNAME="
if defined PROFNAME (
    echo(!PROFNAME!| findstr /r /x /c:"[a-zA-Z0-9_ .-][a-zA-Z0-9_ .-]*" >nul || (
        echo  %r%Name has unsafe characters - using timestamp instead.%w%
        set "PROFNAME="
    )
)
set "TS=%date%_%time%"
set "TS=%TS::=-%"
set "TS=%TS:/=-%"
set "TS=%TS:\=-%"
set "TS=%TS:.=-%"
set "TS=%TS:,=-%"
set "TS=%TS: =_%"
if defined PROFNAME (
    set "PROFF=%PROFDIR%\!PROFNAME!.txt"
) else (
    set "PROFF=%PROFDIR%\profile_%TS%.txt"
)
> "!PROFF!" echo # DCX profile saved %date% %time% mode=!PROFMODE!
>>"!PROFF!" echo # format: namespace^|key^|value   (value DELETE removes the key)
call :_tw_prof_add_tweaks "!PROFF!"
if /i "!PROFMODE!"=="stack" call :_tw_prof_add_stack "!PROFF!"
echo.
echo  Saved: !PROFF!
echo  Edit it in Notepad to trim it down to just the keys you care about.
echo  Press any key . . .
pause >nul
goto tw_profile

:_tw_prof_add_tweaks
call :_tw_prof_add secure clock_seconds "%~1"
call :_tw_prof_add system status_bar_show_battery_percent "%~1"
call :_tw_prof_add global audio_safe_volume_state "%~1"
call :_tw_prof_add secure audio_safe_csd_as_a_feature_enabled "%~1"
call :_tw_prof_add secure icon_blacklist "%~1"
call :_tw_prof_add global heads_up_notifications_enabled "%~1"
call :_tw_prof_add system font_scale "%~1"
call :_tw_prof_add secure long_press_timeout "%~1"
call :_tw_prof_add global stay_on_while_plugged_in "%~1"
call :_tw_prof_add secure night_display_activated "%~1"
call :_tw_prof_add secure night_display_color_temperature "%~1"
call :_tw_prof_add global sysui_demo_allowed "%~1"
call :_tw_prof_add secure sysui_qs_tiles "%~1"
call :_tw_prof_add secure camera_double_tap_power_gesture_disabled "%~1"
call :_tw_prof_add global charging_sounds_enabled "%~1"
call :_tw_prof_add global sys_storage_threshold_percentage "%~1"
call :_tw_prof_add global low_power_trigger_level "%~1"
call :_tw_prof_add global enable_freeform_support "%~1"
exit /b

:_tw_prof_add_stack
:: Battery / Gaming first-class keys - same ones Backup round-trips.
>>"%~1" echo # --- stack: Battery / Gaming ---
call :_tw_prof_add global window_animation_scale "%~1"
call :_tw_prof_add global transition_animation_scale "%~1"
call :_tw_prof_add global animator_duration_scale "%~1"
call :_tw_prof_add system min_refresh_rate "%~1"
call :_tw_prof_add system peak_refresh_rate "%~1"
call :_tw_prof_add global angle_gl_driver_all_angle "%~1"
call :_tw_prof_add global low_power "%~1"
call :_tw_prof_add global low_power_sticky "%~1"
call :_tw_prof_add global zram_enabled "%~1"
call :_tw_prof_add global wifi_scan_always_enabled "%~1"
call :_tw_prof_add global bluetooth_scan_always_enabled "%~1"
call :_tw_prof_add global hotword_detection_enabled "%~1"
call :_tw_prof_add global always_finish_activities "%~1"
call :_tw_prof_add global package_verifier_enable "%~1"
call :_tw_prof_add global disable_window_blurs "%~1"
call :_tw_prof_add global reduce_motion "%~1"
call :_tw_prof_add secure reduce_motion "%~1"
call :_tw_prof_add secure accessibility_disable_animations "%~1"
call :_tw_prof_add global enable_back_animation "%~1"
call :_tw_prof_add global fancy_ime_animations "%~1"
call :_tw_prof_add secure multi_press_timeout "%~1"
call :_tw_prof_add global tcp_default_init_rwnd "%~1"
call :_tw_prof_add global private_dns_mode "%~1"
call :_tw_prof_add global preferred_network_mode "%~1"
exit /b

:_tw_prof_add
:: %1 ns  %2 key  %3 profile file. Unset keys are recorded as DELETE so a
:: profile round-trips "this key was not set" instead of losing it.
:: DisableDelayedExpansion on the read so a '!' in the value is not eaten - see the note
:: in :_bk_settings. Both goto exits below leave via `exit /b`, which pops the scopes.
setlocal DisableDelayedExpansion
set "PVAL="
for /f "delims=" %%v in ('adb shell settings get %~1 %~2 2^>nul ^<nul') do set "PVAL=%%v"
setlocal EnableDelayedExpansion
if "!PVAL!"=="" set "PVAL=null"
set "PVAL=!PVAL:"=!"
if /i "!PVAL!"=="null" goto _tw_prof_del
call :_tw_safechk PVAL || goto _tw_prof_skip
>>"%~3" echo %~1^|%~2^|!PVAL!
endlocal
endlocal
exit /b

:_tw_prof_del
>>"%~3" echo %~1^|%~2^|DELETE
exit /b

:_tw_prof_skip
>>"%~3" echo # %~1^|%~2 skipped - value holds a character DCX will not round-trip
exit /b

:tw_prof_apply
cls
title Profiles : apply
call :logo
echo.
for /f "delims==" %%v in ('set PROF_ 2^>nul') do set "%%v="
set "PROFN=0"
for /f "delims=" %%f in ('dir /b /o-d /a-d "%PROFDIR%\*.txt" 2^>nul') do (
    set /a PROFN+=1
    set "PROF_!PROFN!=%%f"
    echo     %g%[%w%!PROFN!%g%]%w% %%f
)
if "!PROFN!"=="0" goto tw_prof_none
echo     %g%[%w%0%g%]%w% Back
set "PROFSEL=" & set /p PROFSEL="Apply which? >> "
if not defined PROFSEL goto tw_prof_apply
if "!PROFSEL!"=="0" goto tw_profile
call :_tw_safechk PROFSEL || goto tw_prof_apply
echo(!PROFSEL!| findstr /r /x /c:"[0-9][0-9]*" >nul || goto tw_prof_apply
set "PROFF="
if defined PROF_!PROFSEL! for /f "delims=" %%v in ("!PROFSEL!") do set "PROFF=%PROFDIR%\!PROF_%%v!"
if not defined PROFF goto tw_prof_apply
echo.
echo  About to apply: !PROFF!
set "ok=" & set /p ok="Run it? (y = yes, anything else = cancel) >> "
if /i not "!ok!"=="y" goto tw_profile
echo.
:: eol=# drops comment lines; each line is re-validated on the way in,
:: because a profile is a file the user can hand-edit.
for /f "usebackq eol=# tokens=1-3 delims=|" %%a in ("!PROFF!") do call :_tw_prof_apply1 "%%a" "%%b" "%%c"
echo.
if defined EXP_UNDO (
    echo  Done. Undo script: %EXP_UNDO%
) else (
    echo  Done. ^(No writes landed - nothing to undo.^)
)
echo  Press any key . . .
pause >nul
goto tw_profile

:tw_prof_none
echo  No profiles yet - save one first, or drop a .txt into
echo  %PROFDIR%
timeout /t 3 /nobreak >nul
goto tw_profile

:_tw_prof_apply1
set "PNS=%~1"
set "PKEY=%~2"
set "PVAL=%~3"
if not defined PNS exit /b
if not defined PKEY exit /b
if /i "!PNS!"=="system" goto _tw_pa_ns_ok
if /i "!PNS!"=="secure" goto _tw_pa_ns_ok
if /i "!PNS!"=="global" goto _tw_pa_ns_ok
echo    skip - unknown namespace: !PNS!
exit /b

:_tw_pa_ns_ok
:: safechk BEFORE the findstr probe: a profile is a text file the user can hand-edit or
:: receive from someone else, so PKEY is the least trusted value in the script. The probe
:: below is a pipe, and a pipe re-parses the expanded value - a key containing "&" would
:: otherwise be reported valid AND have its tail executed. safechk is pipe-free, so it is
:: safe to run first; it rejects & | < > before they can reach the pipe.
call :_tw_safechk PKEY || goto _tw_pa_badkey
echo(!PKEY!| findstr /r /x /c:"[a-zA-Z0-9_.-][a-zA-Z0-9_.-]*" >nul || goto _tw_pa_badkey
if /i "!PVAL!"=="DELETE" goto _tw_pa_del
if not defined PVAL goto _tw_pa_badval
call :_tw_safechk PVAL || goto _tw_pa_badval
:: FIX: allow () so sysui_qs_tiles custom(...) values round-trip; quote for adb.
echo(!PVAL!| findstr /r /x /c:"[a-zA-Z0-9_.,:/=+()-][a-zA-Z0-9_.,:/=+()-]*" >nul || goto _tw_pa_badval
call :_tw_undo_add !PNS! !PKEY!
set "_sv=!PVAL:'='\''!"
adb shell "settings put !PNS! !PKEY! '!_sv!'" <nul >nul
echo    put    !PNS! !PKEY! = !PVAL!
exit /b

:_tw_pa_del
call :_tw_undo_add !PNS! !PKEY!
adb shell settings delete !PNS! !PKEY! >nul 2>&1 <nul
echo    delete !PNS! !PKEY!
exit /b

:_tw_pa_badkey
echo    skip - bad key name: !PKEY!
exit /b

:_tw_pa_badval
echo    skip - bad or unsafe value for !PKEY!
exit /b
:: ===================================================================
:: NEW (Tier 3): QS tile editor + assorted device tweaks.
::
:: Verified against AOSP main this pass:
::   secure sysui_qs_tiles          Settings.java:11710 (Secure.QS_TILES).
::     Still the source of truth on main: UserTileSpecRepository.kt:229
::     SETTING = Settings.Secure.QS_TILES, and it registers a content
::     observer on it (L101) -> edits apply live. Invalid specs are
::     dropped, never stored empty (TileSpecRepository.kt doc), so a typo
::     degrades instead of wrecking the panel.
::   secure camera_gesture_disabled / camera_double_tap_power_gesture_
::     disabled / camera_double_twist_to_flip_enabled  Settings.java
::     :11012, :11070, :11080
::   global charging_sounds_enabled / charging_vibration_enabled
::     Settings.java:8880, :8887
::   global sys_storage_threshold_percentage / _max_bytes  :15353
::   global low_power_trigger_level  Settings.java:16861 - note the KEY is
::     low_power_trigger_level even though the constant is called
::     LOW_POWER_MODE_TRIGGER_LEVEL.
::   global default_install_location  Settings.java:15582
::   global enable_freeform_support / force_resizable_activities  :13667,
::     :13659
:: ===================================================================
:tw_qs
cls
title Quick Settings Tiles
call :logo
echo.
set "QSCUR="
for /f "delims=" %%i in ('adb shell settings get secure sysui_qs_tiles 2^>nul ^<nul') do set "QSCUR=%%i"
if "!QSCUR!"=="" set "QSCUR=null"
set "QSCUR=!QSCUR:"=!"
echo  sysui_qs_tiles (secure) = "!QSCUR!"
if "!QSCUR!"=="null" echo    (null = the device is using its built-in default list)
echo.
echo  The order here is the order they appear. Android ships more tiles than
echo  it shows - this is how you reach them. Unknown names are dropped by
echo  SystemUI rather than breaking the panel, and the list is never stored
echo  empty, so a typo costs you a tile, not your quick settings.
echo.
echo    %g%[%w%1%g%]%w% Add a tile (at the end)
echo    %g%[%w%2%g%]%w% Add a tile (at the front)
echo    %g%[%w%3%g%]%w% Remove a tile
echo    %g%[%w%4%g%]%w% Reset to the device default (delete key)
echo    %g%[%w%5%g%]%w% Back
set "qs=" & set /p qs="Choose An Option >> "
if not defined qs goto tw_qs
if "!qs!"=="1" (set "QSPOS=end" & goto tw_qs_pick)
if "!qs!"=="2" (set "QSPOS=front" & goto tw_qs_pick)
if "!qs!"=="3" goto tw_qs_del
if "!qs!"=="4" goto tw_qs_reset
if "!qs!"=="5" goto tweaks
goto tw_qs

:tw_qs_pick
cls
title Quick Settings Tiles : add
call :logo
echo.
:: These are the specs present in SystemUI's quick_settings_tiles_stock but
:: absent from quick_settings_tiles_default (AOSP main config.xml) - i.e.
:: exactly the tiles the device has but does not show.
echo  Tiles Android knows about but does not show by default:
echo    %g%[%w%1%g%]%w% location            %g%[%w%9%g%]%w% onehanded
echo    %g%[%w%2%g%]%w% hotspot             %g%[%w%10%g%]%w% qr_code_scanner
echo    %g%[%w%3%g%]%w% saver               %g%[%w%11%g%]%w% dream          (screensaver)
echo    %g%[%w%4%g%]%w% dark                %g%[%w%12%g%]%w% font_scaling
echo    %g%[%w%5%g%]%w% night               %g%[%w%13%g%]%w% hearing_devices
echo    %g%[%w%6%g%]%w% inversion           %g%[%w%14%g%]%w% notes
echo    %g%[%w%7%g%]%w% color_correction    %g%[%w%15%g%]%w% reverse        (reverse charging)
echo    %g%[%w%8%g%]%w% reduce_brightness   %g%[%w%16%g%]%w% work           (work profile)
echo.
echo    %g%[%w%17%g%]%w% Type a spec myself
echo    %g%[%w%18%g%]%w% Back
set "QSSEL=" & set /p QSSEL="Choose An Option >> "
if not defined QSSEL goto tw_qs_pick
set "QSTOK="
if "!QSSEL!"=="1" set "QSTOK=location"
if "!QSSEL!"=="2" set "QSTOK=hotspot"
if "!QSSEL!"=="3" set "QSTOK=saver"
if "!QSSEL!"=="4" set "QSTOK=dark"
if "!QSSEL!"=="5" set "QSTOK=night"
if "!QSSEL!"=="6" set "QSTOK=inversion"
if "!QSSEL!"=="7" set "QSTOK=color_correction"
if "!QSSEL!"=="8" set "QSTOK=reduce_brightness"
if "!QSSEL!"=="9" set "QSTOK=onehanded"
if "!QSSEL!"=="10" set "QSTOK=qr_code_scanner"
if "!QSSEL!"=="11" set "QSTOK=dream"
if "!QSSEL!"=="12" set "QSTOK=font_scaling"
if "!QSSEL!"=="13" set "QSTOK=hearing_devices"
if "!QSSEL!"=="14" set "QSTOK=notes"
if "!QSSEL!"=="15" set "QSTOK=reverse"
if "!QSSEL!"=="16" set "QSTOK=work"
if "!QSSEL!"=="17" goto tw_qs_custom
if "!QSSEL!"=="18" goto tw_qs
if not defined QSTOK goto tw_qs_pick
goto tw_qs_addgo

:tw_qs_custom
echo.
echo  Lowercase letters, digits and _ only. DCX will not take the
echo  custom(package/class) form - that needs brackets and a slash, which
echo  batch will not carry safely; use the Shell option for those.
set "QSTOK=" & set /p QSTOK="Tile spec (blank = cancel) >> "
if not defined QSTOK goto tw_qs_pick
set "QSTOK=!QSTOK:"=!"
if not defined QSTOK goto tw_qs_pick
call :_tw_safechk QSTOK || goto tw_qs_bad
echo(!QSTOK!| findstr /r /x /c:"[a-z0-9_][a-z0-9_]*" >nul || goto tw_qs_bad
goto tw_qs_addgo

:tw_qs_addgo
call :_tw_undo_add secure sysui_qs_tiles
:: Same rebuild-not-append shape as the icon blacklist: drop the spec first
:: so adding an existing tile moves it rather than duplicating it.
:: FIX: OEM lists often hold custom(pkg/cls) tokens. A bare
:: `for %%t in (!QSCUR!)` treats those parentheses as block syntax and
:: aborts or corrupts the list - tokenize paren-aware via :_tw_qs_enum.
set "QSNEW="
if "!QSCUR!"=="null" goto _tw_qs_addput
call :_tw_qs_enum
call :_tw_qs_rebuild_skip

:_tw_qs_addput
if /i "!QSPOS!"=="front" (set "QSNEW=,!QSTOK!!QSNEW!") else (set "QSNEW=!QSNEW!,!QSTOK!")
set "QSNEW=!QSNEW:~1!"
call :_tw_qs_put
goto tw_qs

:tw_qs_del
cls
title Quick Settings Tiles : remove
call :logo
echo.
if "!QSCUR!"=="null" goto tw_qs_empty
call :_tw_qs_enum
if "!QSN!"=="0" goto tw_qs_empty
echo  Current tiles, in display order:
for /l %%i in (1,1,!QSN!) do echo     %g%[%w%%%i%g%]%w% !QST_%%i!
echo     %g%[%w%0%g%]%w% Back
set "QSPICK=" & set /p QSPICK="Remove which? >> "
if not defined QSPICK goto tw_qs_del
if "!QSPICK!"=="0" goto tw_qs
call :_tw_safechk QSPICK || goto tw_qs_del
echo(!QSPICK!| findstr /r /x /c:"[0-9][0-9]*" >nul || goto tw_qs_del
set "QSTOK="
if defined QST_!QSPICK! for /f "delims=" %%v in ("!QSPICK!") do set "QSTOK=!QST_%%v!"
if not defined QSTOK goto tw_qs_del
call :_tw_undo_add secure sysui_qs_tiles
call :_tw_qs_rebuild_skip
:: An empty list is not a valid value - SystemUI would fall back anyway, so
:: removing the last tile is expressed honestly as a reset.
if not defined QSNEW goto tw_qs_reset
set "QSNEW=!QSNEW:~1!"
call :_tw_qs_put
goto tw_qs

:_pkg_ok
:: Validates !_PKGCHK! as an Android package name; errorlevel 1 if it is not one.
::
:: Why this exists. A package name is free text the user types, and it used to reach
:: "adb shell ... %pkg%" through IMMEDIATE expansion - so a name containing & | < > was
:: parsed by cmd as an OPERATOR rather than passed as data, and the line broke or ran
:: something else. Every use is now delayed (!pkg!), which makes those characters literal.
:: This check is the other half: it keeps anything that is not a real package name from
:: reaching adb at all, and it runs BEFORE the "is it installed" probe - because that probe
:: expands the value too, so it could never have protected the thing it was checking.
::
:: Android package names are Java-style: a letter first, then letters, digits, dots and
:: underscores.
::
:: PIPE-FREE ON PURPOSE - do not "simplify" this back to `echo(!_PKGCHK!| findstr ...`.
:: A pipe makes cmd build the child's command line from the ALREADY-EXPANDED value and
:: parse it a second time, so "com.foo&echo hi" split at the &: findstr saw only
:: "com.foo", returned 0, and this routine reported VALID - while the half after the &
:: executed inside the pipe with its output swallowed. The check both passed the bad
:: name and ran part of it, which is the exact opposite of its job. Measured, not
:: theorised. `for /f "delims=<allowed>"` never builds a command line: if the value is
:: made only of allowed characters they are all delimiters, so there is no token at all
:: and the loop body never runs. Anything left over is the first offending character.
if not defined _PKGCHK exit /b 1
set "_PKGCHK=!_PKGCHK:"=!"
if not defined _PKGCHK exit /b 1
set "_pk_bad="
for /f "delims=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._" %%c in ("!_PKGCHK!") do set "_pk_bad=%%c"
if defined _pk_bad exit /b 1
:: shape: must start with a letter, not a digit or a dot
set "_pk_bad="
for /f "delims=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" %%c in ("!_PKGCHK:~0,1!") do set "_pk_bad=%%c"
if defined _pk_bad exit /b 1
exit /b 0

:_tw_qs_enum
:: Split QSCUR into QST_1..QST_n on commas that are NOT inside (...).
:: Needed because Huawei/OEM lists embed custom(component/class) tokens.
for /f "delims==" %%v in ('set QST_ 2^>nul') do set "%%v="
set "QSN=0"
if not defined QSCUR exit /b
if /i "!QSCUR!"=="null" exit /b
set "_qs_tmp=%TEMP%\dcx_qs_tokens.txt"
powershell -NoProfile -Command "$s=$env:QSCUR; if([string]::IsNullOrEmpty($s)){exit 0}; $d=0; $c=''; $l=New-Object System.Collections.Generic.List[string]; foreach($ch in $s.ToCharArray()){ if($ch -eq [char]'('){$d++} elseif($ch -eq [char]')'){$d--} elseif($ch -eq [char]',' -and $d -eq 0){ [void]$l.Add($c); $c=''; continue }; $c+=$ch }; if($c.Length -gt 0){[void]$l.Add($c)}; $l | Set-Content -LiteralPath $env:_qs_tmp -Encoding ascii"
:: PowerShell resets the console code page on exit, which turns the box-drawing UI into
:: "?????" until something sets it back. :setupautorun already restores it after its own
:: PowerShell block; this path did not, and only got away with it because :logo also runs
:: chcp and almost every screen redraws through :logo. "Almost" is not a guarantee, so make
:: it explicit here rather than depend on the caller's redraw path.
chcp 65001 >nul
if not exist "%_qs_tmp%" exit /b
for /f "usebackq delims=" %%t in ("%_qs_tmp%") do (
    set /a QSN+=1
    set "QST_!QSN!=%%t"
)
del "%_qs_tmp%" >nul 2>&1
exit /b

:_tw_qs_rebuild_skip
:: Build QSNEW=,tok,tok from QST_* skipping any token equal to QSTOK.
set "QSNEW="
for /l %%i in (1,1,!QSN!) do (
    set "QSHIT="
    if defined QSTOK if /i "!QST_%%i!"=="!QSTOK!" set "QSHIT=1"
    if not defined QSHIT set "QSNEW=!QSNEW!,!QST_%%i!"
)
exit /b

:_tw_qs_put
:: Write QSNEW with device-shell single-quoting so custom(...) survives adb.
set "_sv=!QSNEW:'='\''!"
adb shell "settings put secure sysui_qs_tiles '!_sv!'" <nul
exit /b

:tw_qs_empty
echo  The device is on its default list - nothing to remove yet.
echo  Add a tile first, which writes the full list out.
timeout /t 3 /nobreak >nul
goto tw_qs

:tw_qs_reset
call :_tw_undo_add secure sysui_qs_tiles
adb shell settings delete secure sysui_qs_tiles >nul 2>&1 <nul
goto tw_qs

:tw_qs_bad
echo [%r%^^!%w%] Not allowed - lowercase letters, digits and _ only.
timeout /t 2 /nobreak >nul
goto tw_qs_pick

:tw_more
cls
title More Device Tweaks
call :logo
echo.
echo                              %m%More Device Tweaks%w%
echo.
echo    %g%[%w%1%g%]%w% Camera gestures (double-tap power, twist to flip)
echo    %g%[%w%2%g%]%w% Charging sounds and vibration
echo    %g%[%w%3%g%]%w% Storage low-space warning
echo    %g%[%w%4%g%]%w% Battery saver auto-trigger level
echo    %g%[%w%5%g%]%w% Freeform windows (needs a reboot)
echo    %g%[%w%6%g%]%w% Default install location
echo    %g%[%w%7%g%]%w% Back
set "mo=" & set /p mo="Choose An Option >> "
if not defined mo goto tw_more
if "!mo!"=="1" goto tw_cam
if "!mo!"=="2" goto tw_chg
if "!mo!"=="3" goto tw_stor
if "!mo!"=="4" goto tw_bsav
if "!mo!"=="5" goto tw_free
if "!mo!"=="6" goto tw_inst
if "!mo!"=="7" goto tweaks
goto tw_more

:tw_cam
cls
title Camera Gestures
call :logo
echo.
set "CG1="
set "CG2="
set "CG3="
for /f "delims=" %%i in ('adb shell settings get secure camera_double_tap_power_gesture_disabled 2^>nul ^<nul') do set "CG1=%%i"
for /f "delims=" %%i in ('adb shell settings get secure camera_double_twist_to_flip_enabled 2^>nul ^<nul') do set "CG2=%%i"
for /f "delims=" %%i in ('adb shell settings get secure camera_gesture_disabled 2^>nul ^<nul') do set "CG3=%%i"
if "!CG1!"=="" set "CG1=null"
if "!CG2!"=="" set "CG2=null"
if "!CG3!"=="" set "CG3=null"
set "CG1=!CG1:"=!"
set "CG2=!CG2:"=!"
set "CG3=!CG3:"=!"
echo  camera_double_tap_power_gesture_disabled = "!CG1!"   (1 = gesture off)
echo  camera_double_twist_to_flip_enabled      = "!CG2!"   (1 = twist flips camera)
echo  camera_gesture_disabled                  = "!CG3!"   (1 = lift-to-launch off)
echo.
echo  Note the naming: two of these are _disabled, one is _enabled, so 1
echo  means opposite things. The menu below says what it does, not the value.
echo.
echo    %g%[%w%1%g%]%w% Double-tap power for camera: OFF
echo    %g%[%w%2%g%]%w% Double-tap power for camera: ON
echo    %g%[%w%3%g%]%w% Twist to flip camera: ON
echo    %g%[%w%4%g%]%w% Twist to flip camera: OFF
echo    %g%[%w%5%g%]%w% Reset all three to device default
echo    %g%[%w%6%g%]%w% Back
set "cg=" & set /p cg="Choose An Option >> "
if not defined cg goto tw_cam
if "!cg!"=="1" (call :_tw_undo_add secure camera_double_tap_power_gesture_disabled & adb shell settings put secure camera_double_tap_power_gesture_disabled 1 <nul & goto tw_cam)
if "!cg!"=="2" (call :_tw_undo_add secure camera_double_tap_power_gesture_disabled & adb shell settings put secure camera_double_tap_power_gesture_disabled 0 <nul & goto tw_cam)
if "!cg!"=="3" (call :_tw_undo_add secure camera_double_twist_to_flip_enabled & adb shell settings put secure camera_double_twist_to_flip_enabled 1 <nul & goto tw_cam)
if "!cg!"=="4" (call :_tw_undo_add secure camera_double_twist_to_flip_enabled & adb shell settings put secure camera_double_twist_to_flip_enabled 0 <nul & goto tw_cam)
if "!cg!"=="5" goto tw_cam_reset
if "!cg!"=="6" goto tw_more
goto tw_cam

:tw_cam_reset
call :_tw_undo_add secure camera_double_tap_power_gesture_disabled
call :_tw_undo_add secure camera_double_twist_to_flip_enabled
call :_tw_undo_add secure camera_gesture_disabled
adb shell settings delete secure camera_double_tap_power_gesture_disabled >nul 2>&1 <nul
adb shell settings delete secure camera_double_twist_to_flip_enabled >nul 2>&1 <nul
adb shell settings delete secure camera_gesture_disabled >nul 2>&1 <nul
goto tw_cam

:tw_chg
cls
title Charging Sounds
call :logo
echo.
set "CH1="
set "CH2="
for /f "delims=" %%i in ('adb shell settings get global charging_sounds_enabled 2^>nul ^<nul') do set "CH1=%%i"
for /f "delims=" %%i in ('adb shell settings get global charging_vibration_enabled 2^>nul ^<nul') do set "CH2=%%i"
if "!CH1!"=="" set "CH1=null"
if "!CH2!"=="" set "CH2=null"
set "CH1=!CH1:"=!"
set "CH2=!CH2:"=!"
echo  charging_sounds_enabled    (global) = "!CH1!"
echo  charging_vibration_enabled (global) = "!CH2!"
echo  The chirp and buzz when you plug in. 1 = on, 0 = off.
echo.
echo    %g%[%w%1%g%]%w% Sound off
echo    %g%[%w%2%g%]%w% Sound on
echo    %g%[%w%3%g%]%w% Vibration off
echo    %g%[%w%4%g%]%w% Vibration on
echo    %g%[%w%5%g%]%w% Reset both to device default
echo    %g%[%w%6%g%]%w% Back
set "ch=" & set /p ch="Choose An Option >> "
if not defined ch goto tw_chg
if "!ch!"=="1" (call :_tw_undo_add global charging_sounds_enabled & adb shell settings put global charging_sounds_enabled 0 <nul & goto tw_chg)
if "!ch!"=="2" (call :_tw_undo_add global charging_sounds_enabled & adb shell settings put global charging_sounds_enabled 1 <nul & goto tw_chg)
if "!ch!"=="3" (call :_tw_undo_add global charging_vibration_enabled & adb shell settings put global charging_vibration_enabled 0 <nul & goto tw_chg)
if "!ch!"=="4" (call :_tw_undo_add global charging_vibration_enabled & adb shell settings put global charging_vibration_enabled 1 <nul & goto tw_chg)
if "!ch!"=="5" goto tw_chg_reset
if "!ch!"=="6" goto tw_more
goto tw_chg

:tw_chg_reset
call :_tw_undo_add global charging_sounds_enabled
call :_tw_undo_add global charging_vibration_enabled
adb shell settings delete global charging_sounds_enabled >nul 2>&1 <nul
adb shell settings delete global charging_vibration_enabled >nul 2>&1 <nul
goto tw_chg

:tw_stor
cls
title Storage Warning
call :logo
echo.
set "STP="
set "STB="
for /f "delims=" %%i in ('adb shell settings get global sys_storage_threshold_percentage 2^>nul ^<nul') do set "STP=%%i"
for /f "delims=" %%i in ('adb shell settings get global sys_storage_threshold_max_bytes 2^>nul ^<nul') do set "STB=%%i"
if "!STP!"=="" set "STP=null"
if "!STB!"=="" set "STB=null"
set "STP=!STP:"=!"
set "STB=!STB:"=!"
echo  sys_storage_threshold_percentage (global) = "!STP!"   (default 10)
echo  sys_storage_threshold_max_bytes  (global) = "!STB!"   (caps the above)
echo.
echo  When free space drops below the percentage, Android nags and starts
echo  refusing installs. On a 512 GB phone the stock 10%% means it panics
echo  with 50 GB free. The max_bytes cap is the sane fix: whichever is
echo  smaller wins.
echo.
echo    %g%[%w%1%g%]%w% Percentage: 10 (stock)
echo    %g%[%w%2%g%]%w% Percentage: 5
echo    %g%[%w%3%g%]%w% Percentage: 2
echo    %g%[%w%4%g%]%w% Cap the warning at 2 GB free  (max_bytes)
echo    %g%[%w%5%g%]%w% Cap the warning at 5 GB free  (max_bytes)
echo    %g%[%w%6%g%]%w% Reset both to device default
echo    %g%[%w%7%g%]%w% Back
set "st=" & set /p st="Choose An Option >> "
if not defined st goto tw_stor
if "!st!"=="1" (call :_tw_undo_add global sys_storage_threshold_percentage & adb shell settings put global sys_storage_threshold_percentage 10 <nul & goto tw_stor)
if "!st!"=="2" (call :_tw_undo_add global sys_storage_threshold_percentage & adb shell settings put global sys_storage_threshold_percentage 5 <nul & goto tw_stor)
if "!st!"=="3" (call :_tw_undo_add global sys_storage_threshold_percentage & adb shell settings put global sys_storage_threshold_percentage 2 <nul & goto tw_stor)
if "!st!"=="4" (call :_tw_undo_add global sys_storage_threshold_max_bytes & adb shell settings put global sys_storage_threshold_max_bytes 2147483648 <nul & goto tw_stor)
if "!st!"=="5" (call :_tw_undo_add global sys_storage_threshold_max_bytes & adb shell settings put global sys_storage_threshold_max_bytes 5368709120 <nul & goto tw_stor)
if "!st!"=="6" goto tw_stor_reset
if "!st!"=="7" goto tw_more
goto tw_stor

:tw_stor_reset
call :_tw_undo_add global sys_storage_threshold_percentage
call :_tw_undo_add global sys_storage_threshold_max_bytes
adb shell settings delete global sys_storage_threshold_percentage >nul 2>&1 <nul
adb shell settings delete global sys_storage_threshold_max_bytes >nul 2>&1 <nul
goto tw_stor

:tw_bsav
cls
title Battery Saver Trigger
call :logo
echo.
set "BSV="
for /f "delims=" %%i in ('adb shell settings get global low_power_trigger_level 2^>nul ^<nul') do set "BSV=%%i"
if "!BSV!"=="" set "BSV=null"
set "BSV=!BSV:"=!"
echo  low_power_trigger_level (global) = "!BSV!" %%   (0/null = never auto-on)
echo.
echo  The battery percentage at which saver switches itself on. This is only
echo  the trigger - Battery ^> Saver On/Off writes low_power itself, so that
echo  screen turns saver on now, this one decides when it does so by itself.
echo.
echo    %g%[%w%1%g%]%w% Never (0)
echo    %g%[%w%2%g%]%w% 5%%
echo    %g%[%w%3%g%]%w% 15%% (common default)
echo    %g%[%w%4%g%]%w% 30%%
echo    %g%[%w%5%g%]%w% 50%%
echo    %g%[%w%6%g%]%w% Custom (0 - 99)
echo    %g%[%w%7%g%]%w% Reset to device default (delete key)
echo    %g%[%w%8%g%]%w% Back
set "bsv=" & set /p bsv="Choose An Option >> "
if not defined bsv goto tw_bsav
if "!bsv!"=="1" (set "BSNEW=0" & goto tw_bsav_apply)
if "!bsv!"=="2" (set "BSNEW=5" & goto tw_bsav_apply)
if "!bsv!"=="3" (set "BSNEW=15" & goto tw_bsav_apply)
if "!bsv!"=="4" (set "BSNEW=30" & goto tw_bsav_apply)
if "!bsv!"=="5" (set "BSNEW=50" & goto tw_bsav_apply)
if "!bsv!"=="6" goto tw_bsav_custom
if "!bsv!"=="7" (call :_tw_undo_add global low_power_trigger_level & adb shell settings delete global low_power_trigger_level >nul 2>&1 <nul & goto tw_bsav)
if "!bsv!"=="8" goto tw_more
goto tw_bsav

:tw_bsav_custom
echo.
set "BSNEW=" & set /p BSNEW="Percentage 0 - 99 (blank = cancel) >> "
if not defined BSNEW goto tw_bsav
set "BSNEW=!BSNEW:"=!"
if not defined BSNEW goto tw_bsav
call :_tw_safechk BSNEW || goto tw_bsav_bad
echo(!BSNEW!| findstr /r /x /c:"[0-9]" /c:"[1-9][0-9]" >nul || goto tw_bsav_bad
goto tw_bsav_apply

:tw_bsav_bad
echo [%r%^^!%w%] Invalid value. A whole number from 0 to 99.
timeout /t 2 /nobreak >nul
goto tw_bsav_custom

:tw_bsav_apply
call :_tw_undo_add global low_power_trigger_level
adb shell settings put global low_power_trigger_level !BSNEW! <nul
goto tw_bsav

:tw_free
cls
title Freeform Windows
call :logo
echo.
set "FW1="
set "FW2="
for /f "delims=" %%i in ('adb shell settings get global enable_freeform_support 2^>nul ^<nul') do set "FW1=%%i"
for /f "delims=" %%i in ('adb shell settings get global force_resizable_activities 2^>nul ^<nul') do set "FW2=%%i"
if "!FW1!"=="" set "FW1=null"
if "!FW2!"=="" set "FW2=null"
set "FW1=!FW1:"=!"
set "FW2=!FW2:"=!"
echo  enable_freeform_support    (global) = "!FW1!"
echo  force_resizable_activities (global) = "!FW2!"
echo.
echo  Desktop-style floating windows. Both are developer-options keys and
echo  need a REBOOT to take effect - nothing will look different until then.
echo  Force-resizable makes apps that declare themselves fixed-size resize
echo  anyway, which some of them handle badly.
echo.
echo    %g%[%w%1%g%]%w% Enable freeform support
echo    %g%[%w%2%g%]%w% Disable freeform support
echo    %g%[%w%3%g%]%w% Force activities resizable: on
echo    %g%[%w%4%g%]%w% Force activities resizable: off
echo    %g%[%w%5%g%]%w% Reset both to device default
echo    %g%[%w%6%g%]%w% Reboot now
echo    %g%[%w%7%g%]%w% Back
set "fw=" & set /p fw="Choose An Option >> "
if not defined fw goto tw_free
if "!fw!"=="1" (call :_tw_undo_add global enable_freeform_support & adb shell settings put global enable_freeform_support 1 <nul & goto tw_free)
if "!fw!"=="2" (call :_tw_undo_add global enable_freeform_support & adb shell settings put global enable_freeform_support 0 <nul & goto tw_free)
if "!fw!"=="3" (call :_tw_undo_add global force_resizable_activities & adb shell settings put global force_resizable_activities 1 <nul & goto tw_free)
if "!fw!"=="4" (call :_tw_undo_add global force_resizable_activities & adb shell settings put global force_resizable_activities 0 <nul & goto tw_free)
if "!fw!"=="5" goto tw_free_reset
if "!fw!"=="6" (adb reboot <nul & goto tw_free)
if "!fw!"=="7" goto tw_more
goto tw_free

:tw_free_reset
call :_tw_undo_add global enable_freeform_support
call :_tw_undo_add global force_resizable_activities
adb shell settings delete global enable_freeform_support >nul 2>&1 <nul
adb shell settings delete global force_resizable_activities >nul 2>&1 <nul
goto tw_free

:tw_inst
cls
title Install Location
call :logo
echo.
set "ILV="
for /f "delims=" %%i in ('adb shell settings get global default_install_location 2^>nul ^<nul') do set "ILV=%%i"
if "!ILV!"=="" set "ILV=null"
set "ILV=!ILV:"=!"
echo  default_install_location (global) = "!ILV!"
echo    0/null = let the system decide, 1 = internal, 2 = external
echo  Only bites on devices with adoptable/removable storage, and an app can
echo  still override it in its manifest - so this is a preference, not a rule.
echo.
echo    %g%[%w%1%g%]%w% System decides (0)
echo    %g%[%w%2%g%]%w% Prefer internal (1)
echo    %g%[%w%3%g%]%w% Prefer external (2)
echo    %g%[%w%4%g%]%w% Reset to device default (delete key)
echo    %g%[%w%5%g%]%w% Back
set "il=" & set /p il="Choose An Option >> "
if not defined il goto tw_inst
if "!il!"=="1" (call :_tw_undo_add global default_install_location & adb shell settings put global default_install_location 0 <nul & goto tw_inst)
if "!il!"=="2" (call :_tw_undo_add global default_install_location & adb shell settings put global default_install_location 1 <nul & goto tw_inst)
if "!il!"=="3" (call :_tw_undo_add global default_install_location & adb shell settings put global default_install_location 2 <nul & goto tw_inst)
if "!il!"=="4" (call :_tw_undo_add global default_install_location & adb shell settings delete global default_install_location >nul 2>&1 <nul & goto tw_inst)
if "!il!"=="5" goto tw_more
goto tw_inst
:: ===================================================================
:: Settings Tools (main menu 15) - generic tooling over the whole
:: settings provider, split out of the Tweaks hub. Tweaks is the
:: curated list; these three work on any key and are the SetEdit
:: analogue, so they earn their own top-level entry rather than
:: sitting three levels down.
:: ===================================================================
:tw_watch
cls
title Watch settings key
call :logo
echo.
echo  Poll one settings key while you flip a toggle on the phone.
echo  Faster than snapshot/diff when you already know the namespace.
echo  Press %g%Q%w% to stop. Auto-stops when the value changes.
echo.
call :_tw_askns
if not defined EXP_NS goto settools
call :_tw_askkey
if not defined EXP_KEY goto settools
set "WATCH_NS=!EXP_NS!"
set "WATCH_KEY=!EXP_KEY!"
set "WATCH_PREV="
for /f "delims=" %%i in ('adb shell settings get !WATCH_NS! !WATCH_KEY! 2^>nul ^<nul') do set "WATCH_PREV=%%i"
if "!WATCH_PREV!"=="" set "WATCH_PREV=null"
set "WATCH_PREV=!WATCH_PREV:"=!"
echo.
echo  Watching %g%!WATCH_NS!/!WATCH_KEY!%w%
echo  Baseline: "!WATCH_PREV!"
echo  Flip the toggle on the device now...
echo.

:_tw_watch_loop
:: Q=quit (errorlevel 1), C=continue/timeout default (errorlevel 2+)
choice /c:QC /n /t 1 /d C >nul
if errorlevel 2 goto _tw_watch_poll
echo  Stopped.
pause >nul
goto settools

:_tw_watch_poll
set "WATCH_NOW="
for /f "delims=" %%i in ('adb shell settings get !WATCH_NS! !WATCH_KEY! 2^>nul ^<nul') do set "WATCH_NOW=%%i"
if "!WATCH_NOW!"=="" set "WATCH_NOW=null"
set "WATCH_NOW=!WATCH_NOW:"=!"
if "!WATCH_NOW!"=="!WATCH_PREV!" goto _tw_watch_loop
echo.
echo  [%g%+%w%] Value changed:
echo     was: "!WATCH_PREV!"
echo     now: "!WATCH_NOW!"
echo.
echo  Namespace/key: !WATCH_NS! !WATCH_KEY!
echo  Tip: save it into a Profile, or write it via Settings explorer.
echo.
pause >nul
goto settools

:settools
cls
title Settings Tools
call :logo
echo.
echo                               %m%Settings Tools%w%
echo.
echo  Generic tools for ANY settings key ^(list / get / put / watch / profile^).
echo  For the curated status-bar and system toggles, use Main Menu - Tweaks.
echo.
echo    %g%[%w%1%g%]%w% Settings explorer - list / get / put / delete
echo    %g%[%w%2%g%]%w% Settings snapshot and diff
echo    %g%[%w%3%g%]%w% Profiles - curated keys or full Battery/Gaming stack
echo    %g%[%w%4%g%]%w% Watch a key - poll while you flip a toggle
echo    %g%[%w%5%g%]%w% Back to main menu
set "sx=" & set /p sx="Choose An Option >> "
if not defined sx goto settools
if "!sx!"=="1" goto tw_explorer
if "!sx!"=="2" goto tw_snapshot
if "!sx!"=="3" goto tw_profile
if "!sx!"=="4" goto tw_watch
if "!sx!"=="5" goto menu
goto settools

:logo
chcp 65001 >nul
echo.
echo.
echo                                     %m%██████╗  ██████╗██╗  ██╗
echo                                     ██╔══██╗██╔════╝╚██╗██╔╝
echo                                     ██║  ██║██║      ╚███╔╝ %w%
echo                                     ██║  ██║██║      ██╔██╗
echo                                     ██████╔╝╚██████╗██╔╝ ██╗
echo                                     ╚═════╝  ╚═════╝╚═╝  ╚═╝
echo.
echo.
exit /b
:: ===================================================================
:: SHARED HELPER: silence all WindowManager debug-trace channels.
:: Used by :setupautorun and :offlogss (previously duplicated 78 lines
:: in each place = 156 redundant lines).
:: `wm logging disable-text` silences the per-channel text output.
:: `wm logging disable` disables the channel entirely.
:: Both calls together fully mute WM tracing on Android 12+.
:: ===================================================================
:wm_silence_logs
for %%C in (
    WM_ERROR
    WM_DEBUG_ORIENTATION
    WM_DEBUG_FOCUS_LIGHT
    WM_DEBUG_BOOT
    WM_DEBUG_RESIZE
    WM_DEBUG_ADD_REMOVE
    WM_DEBUG_CONFIGURATION
    WM_DEBUG_SWITCH
    WM_DEBUG_CONTAINERS
    WM_DEBUG_FOCUS
    WM_DEBUG_IMMERSIVE
    WM_DEBUG_LOCKTASK
    WM_DEBUG_STATES
    WM_DEBUG_TASKS
    WM_DEBUG_STARTING_WINDOW
    WM_SHOW_TRANSACTIONS
    WM_SHOW_SURFACE_ALLOC
    WM_DEBUG_APP_TRANSITIONS
    WM_DEBUG_ANIM
    WM_DEBUG_APP_TRANSITIONS_ANIM
    WM_DEBUG_RECENTS_ANIMATIONS
    WM_DEBUG_DRAW
    WM_DEBUG_REMOTE_ANIMATIONS
    WM_DEBUG_SCREEN_ON
    WM_DEBUG_KEEP_SCREEN_ON
    WM_DEBUG_WINDOW_MOVEMENT
    WM_DEBUG_IME
    WM_DEBUG_WINDOW_ORGANIZER
    WM_DEBUG_SYNC_ENGINE
    WM_DEBUG_WINDOW_TRANSITIONS
    WM_DEBUG_WINDOW_TRANSITIONS_MIN
    WM_DEBUG_WINDOW_INSETS
    WM_DEBUG_CONTENT_RECORDING
    WM_DEBUG_WALLPAPER
    WM_DEBUG_BACK_PREVIEW
    WM_DEBUG_DREAM
    WM_DEBUG_DIMMER
    WM_DEBUG_TPL
    WM_DEBUG_EMBEDDED_WINDOWS
) do (
    adb shell wm logging disable-text %%C <nul > nul 2>&1
    adb shell wm logging disable      %%C <nul > nul 2>&1
)
exit /b
:: ===================================================================
:: SHARED HELPER: mark common system_server dropbox channels as
:: low-priority so they don't spam the dropbox quota. The caller is
:: expected to set the rate-limit afterwards (the value differs).
:: Used by :setupautorun, :skiplogv, :onlogss (saved 21 lines from 3
:: identical occurrences).
:: ===================================================================
:dropbox_lowprio
adb shell cmd dropbox add-low-priority system_server <nul
adb shell cmd dropbox add-low-priority system_server/Subject <nul
adb shell cmd dropbox add-low-priority data_app_wtf <nul
adb shell cmd dropbox add-low-priority storage_trim <nul
adb shell cmd dropbox add-low-priority SYSTEM_BOOT <nul
adb shell cmd dropbox add-low-priority SYSTEM_AUDIT <nul
adb shell cmd dropbox add-low-priority system_server_wtf <nul
adb shell cmd dropbox add-low-priority SYSTEM_LAST_KMSG <nul
exit /b
:: ===================================================================
:: SHARED HELPER: :_settings_verify  ns  key  expected
:: After a settings put/delete - read the key back and report honestly.
:: expected = literal value, or DELETE (null/unset), or * (any set value).
:: ===================================================================
:_act_reset
set "DCX_VOK=0" & set "DCX_VFAIL=0"
exit /b

:_act_summary
if not defined DCX_VOK set "DCX_VOK=0"
if not defined DCX_VFAIL set "DCX_VFAIL=0"
echo.
if "%DCX_VFAIL%"=="0" (
    echo [%g%OK%w%] %DCX_VOK% check^(s^) passed.
) else (
    echo [%y%WARN%w%] %DCX_VOK% passed, %DCX_VFAIL% failed - see above.
)
exit /b

:_settings_verify
set "_sv_got="
for /f "delims=" %%i in ('adb shell settings get %~1 %~2 2^>nul ^<nul') do set "_sv_got=%%i"
if "!_sv_got!"=="" set "_sv_got=null"
if /i "%~3"=="DELETE" (
    if /i "!_sv_got!"=="null" (echo [%g%+%w%] %~2 deleted. & set /a DCX_VOK+=1 & exit /b 0)
    echo [%r%^^!%w%] %~2 still reports "!_sv_got!" - delete may not have landed.
    set /a DCX_VFAIL+=1
    exit /b 1
)
if /i "%~3"=="*" (
    if /i not "!_sv_got!"=="null" (echo [%g%+%w%] %~2 = "!_sv_got!" & set /a DCX_VOK+=1 & exit /b 0)
    echo [%r%^^!%w%] %~2 did not stick ^(device reports null^).
    set /a DCX_VFAIL+=1
    exit /b 1
)
if "!_sv_got!"=="%~3" (echo [%g%+%w%] %~2 = "!_sv_got!" & set /a DCX_VOK+=1 & exit /b 0)
echo [%r%^^!%w%] wanted %~2=%~3, device reports "!_sv_got!".
set /a DCX_VFAIL+=1
exit /b 1
:: ===================================================================
:: SHARED HELPER: :_dcfgsync_verify  expected
:: Read back device_config get_sync_disabled_for_tests after a Tweaks write.
:: ===================================================================
:_dcfgsync_read
:: Reads the sync mode into DCS_VAL. Returns 1 when this device cannot be read.
::
:: Not every build implements the getter. On EMUI 14 / API 31 `device_config
:: get_sync_disabled_for_tests` answers "Invalid command" on stderr and exits 255,
:: while the matching SETTER still returns 0. The old code could not tell that apart
:: from a genuine "none": it mapped every unreadable answer to none and carried on -
:: so the Tweaks screen displayed a mode it had never read, Backup wrote a restore
:: line for a value it had never captured, and the verifier reported the write had
:: failed when it had no way to know either way. Say "unreadable" instead of guessing.
set "DCS_VAL="
set "DCS_OK="
for /f "delims=" %%v in ('adb shell device_config get_sync_disabled_for_tests 2^>nul ^<nul') do set "DCS_VAL=%%v"
if not defined DCS_VAL exit /b 1
set "DCS_VAL=!DCS_VAL:"=!"
if /i "!DCS_VAL!"=="none" set "DCS_OK=1"
if /i "!DCS_VAL!"=="persistent" set "DCS_OK=1"
if /i "!DCS_VAL!"=="until_reboot" set "DCS_OK=1"
if not defined DCS_OK exit /b 1
exit /b 0

:_dcfgsync_verify
call :_dcfgsync_read || goto _dcfgsync_verify_blind
if /i "!DCS_VAL!"=="%~1" (
    echo [%g%+%w%] sync_disabled_for_tests = "!DCS_VAL!"
) else (
    echo [%y%WARN%w%] wanted sync mode %~1, device reports "!DCS_VAL!" - may need root on Android 14+.
)
exit /b

:_dcfgsync_verify_blind
echo [%y%NOTE%w%] this build does not implement the sync-mode readback, so DCX cannot
echo        confirm the change either way. Requested: %~1
exit /b
:: ===================================================================
:: SHARED HELPER: :_dcfg_verify  namespace  key  expected
:: Same idea for device_config get/put. On Android 14+ without root a
:: put often returns cleanly but writes nothing - readback catches that.
:: ===================================================================
:_dcfg_verify
set "_dv_got="
for /f "delims=" %%i in ('adb shell device_config get %~1 %~2 2^>nul ^<nul') do set "_dv_got=%%i"
if "!_dv_got!"=="" set "_dv_got=null"
if "!_dv_got!"=="%~3" (echo [%g%+%w%] %~1/%~2 = "!_dv_got!" & set /a DCX_VOK+=1 & exit /b 0)
echo [%r%^^!%w%] wanted %~1/%~2=%~3, device reports "!_dv_got!".
set /a DCX_VFAIL+=1
exit /b 1
:: ===================================================================
:: SHARED HELPER: dexopt_all_mode  <filter>  <heavy_flag>
::
:: Compiles ALL installed apps with the given compiler filter, picking
:: the right command for the device's Android version:
::
::   Android 13 and below : the package-manager dexopt path.
::     - heavy_flag "1" adds `--check-prof false` (compile every method,
::       not just profiled hot ones) for the Heaviest mode.
::
::   Android 14 and above : dexopt is handled by ART Service. The plain
::     `pm compile -m <filter> -f -a` still works (it is transparently
::     routed to ART Service) but the removed flags `--check-prof` and
::     `--compile-layouts` must NOT be passed - they throw "Unknown
::     option". So on 14+ we drop them.
:: ===================================================================
:dexopt_all_mode
if %SDK% GEQ 34 goto _dexall_art
if "%~2"=="1" goto _dexall_heavy_legacy
echo   [pm dexopt / API %SDK%] pm compile -a -f -m %~1
adb shell pm compile -a -f -m %~1 <nul
exit /b

:_dexall_heavy_legacy
echo   [pm dexopt / API %SDK%] pm compile -a -f --check-prof false -m %~1
adb shell pm compile -a -f --check-prof false -m %~1 <nul
exit /b

:_dexall_art
echo   [ART Service / API %SDK%] pm compile -m %~1 -f -a
adb shell pm compile -m %~1 -f -a <nul
exit /b
:: ===================================================================
:: SHARED HELPER: run_bgdexopt
::
:: Forces the background dexopt job, version-aware:
::
::   Android 13 and below : `pm bg-dexopt-job` (package-manager path).
::
::   Android 14 and above : prefer the native ART Service command
::     `pm art dexopt-packages -r bg-dexopt`. If a particular build
::     doesn't expose `pm art` (older 14 images, some OEMs), fall back
::     to `pm bg-dexopt-job`, which is still routed to ART Service.
:: ===================================================================
:run_bgdexopt
if %SDK% LSS 34 goto _bgdex_legacy
echo   [ART Service / API %SDK%] running background dexopt...
echo   (this can take a while and processes every app - please wait)
adb shell pm art dexopt-packages -r bg-dexopt <nul > "%TEMP%\dcx_bgdex.txt" 2>&1
:: If the command itself is unavailable, fall back to the legacy job.
findstr /I /C:"Unknown command" /C:"Usage:" "%TEMP%\dcx_bgdex.txt" > nul && goto _bgdex_fallback
:: ART Service prints one status line per package (often hundreds).
:: Dumping all of it looks alarming, so instead we summarise: count
:: how many succeeded vs failed, and show ONLY real failure lines.
set "_dx_perf=0"
set "_dx_fail=0"
for /f %%n in ('findstr /I /C:"PERFORMED" "%TEMP%\dcx_bgdex.txt" 2^>nul ^| find /c /v ""') do set "_dx_perf=%%n"
for /f %%n in ('findstr /I /C:"FAILED" "%TEMP%\dcx_bgdex.txt" 2^>nul ^| find /c /v ""') do set "_dx_fail=%%n"
echo.
echo   Background dexopt finished.
echo     Packages optimised : %_dx_perf%
echo     Failures           : %_dx_fail%
:: FIX: the heading promised 15 but `more +0` pages through EVERY failure, so on a device
:: with hundreds the user is told "first 15" and then made to page through the lot. Cap it
:: for real - and say how many were withheld rather than truncating silently, since the
:: full log is kept below anyway. NB: this comment lives OUTSIDE the if-block on purpose -
:: a "::" line inside ( ) makes cmd print "The system cannot find the drive specified."
if not "%_dx_fail%"=="0" (
    echo.
    echo   Failed entries ^(first 15^):
    set "_dx_shown=0"
    for /f "delims=" %%L in ('findstr /I /C:"FAILED" "%TEMP%\dcx_bgdex.txt" 2^>nul') do (
        set /a _dx_shown+=1
        if !_dx_shown! LEQ 15 echo     %%L
    )
    if !_dx_shown! GTR 15 (
        set /a _dx_more=!_dx_shown!-15
        echo     ... and !_dx_more! more - see the full log below.
    )
    echo.
    echo   Note: a few failures are normal - some system packages can't
    echo   be re-compiled. The full log is at:
    echo     !TEMP!\dcx_bgdex.txt
    echo   ^(leaving it in place so you can inspect it^)
) else (
    echo   No failures. All good.
    del "%TEMP%\dcx_bgdex.txt" > nul 2>&1
)
exit /b

:_bgdex_fallback
echo   pm art unavailable on this build - using pm bg-dexopt-job...
adb shell pm bg-dexopt-job <nul
del "%TEMP%\dcx_bgdex.txt" > nul 2>&1
exit /b

:_bgdex_legacy
adb shell pm bg-dexopt-job <nul
exit /b

