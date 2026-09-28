; ============================================================
; Spotify Volume – settings (template)
; ============================================================
; Copy this file to Config.ahk (or run the script once to create it).
; Edit Config.ahk, then Reload from the tray icon.
;
; Leave any key as "" to disable it.
;
; Key syntax:  "F13"  "^Up"  "!WheelDown"  "Media_Play_Pause"
; Modifiers:   ^ Ctrl   ! Alt   + Shift   # Win
; Docs: https://www.autohotkey.com/docs/v2/Hotkeys.htm
; ============================================================

#Requires AutoHotkey v2.0

; --- 1. Volume ------------------------------------------------
VolumeDownKey := "F13"
VolumeUpKey := "F14"
MuteKey := ""          ; e.g. "F15" or "^m"
VolumeIncrement := 2           ; % per press (1–100)
VolumeDebounceMs := 100         ; ms after last press before API call
VolumeResyncMs := 2500        ; ms idle before re-reading Spotify state
WheelAccelWindowMs := 400         ; wheel: stack accel if pressed within this ms
WheelAccelMax := 5           ; wheel: max VolumeIncrement multiplier

; --- 2. Playback ----------------------------------------------
PlayPauseKey := ""         ; e.g. "Media_Play_Pause" or "^Space"
PlayPauseDebounceMs := 300        ; ignore rapid play/pause repeats
NextTrackKey := ""         ; e.g. "Media_Next"
PreviousTrackKey := ""         ; e.g. "Media_Prev"
ShuffleKey := ""         ; toggle shuffle
RepeatKey := ""         ; cycle: track → context → off
SaveTrackKey := ""         ; like / unlike current track

; --- 3. Seek --------------------------------------------------
SeekBackwardKey := ""             ; e.g. "^Left"
SeekForwardKey := ""             ; e.g. "^Right"
SeekStepMs := 10000          ; 10000 = 10 seconds

; --- 4. On-screen tip -----------------------------------------
ShowVolumeTip := true
TipPosition := "bottom"       ; "bottom" | "top" | "center"
TipDurationMs := 900
TipOpacity := 230            ; 50–255
; Artist — track under the tip:
;   "volume" | "playback" | "both" | "off"
NowPlayingTipOn := "volume"

; --- 5. Device ------------------------------------------------
; Transfer to a Connect device (or launch spotify:) if nothing is active.
AutoActivateDevice := true

; --- 6. Games / fullscreen ------------------------------------
; Exclusive fullscreen / admin apps can block normal AHK hotkeys.
;   "uia"   – UI Access (recommended; AHK in Program Files)
;   "admin" – Run as Administrator (UAC on start)
;   ""      – off
; Prefer borderless/windowed when possible.
; Leave blank unless you need hotkeys over exclusive fullscreen / admin games.
ElevateMode := ""              ; "" | "uia" | "admin"

; --- 7. Auth (optional) ---------------------------------------
; Blank = built-in PKCE client. Or set your Dashboard app client id.
SpotifyClientId := ""

; --- 8. Updates -----------------------------------------------
; On startup, check GitHub releases once per new version.
CheckForUpdates := true
