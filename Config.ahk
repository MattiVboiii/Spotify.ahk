; ============================================================
; Spotify Volume – settings
; ============================================================
; 1. Edit the values below
; 2. Save this file
; 3. Run "Spotify Volume.ahk" (double-click it)
;
; Leave a key as "" to turn that control OFF.
;
; How to write a key:
;   "F13"              – function key F13 (common for mouse side buttons
;                        or tools like PowerToys / mouse software)
;   "F1" … "F24"       – any function key
;   "Media_Play_Pause" – keyboard play/pause key
;   "Media_Next"       – next-track key
;   "Media_Prev"       – previous-track key
;   "^Up"              – Ctrl + Up arrow
;   "!Down"            – Alt + Down arrow
;   "+F1"              – Shift + F1
;   "#a"               – Win + A
;   "!WheelDown"       – Alt + mouse wheel down
;
; Modifiers:  ^ = Ctrl   ! = Alt   + = Shift   # = Windows key
; Full list: https://www.autohotkey.com/docs/v2/Hotkeys.htm
; ============================================================

#Requires AutoHotkey v2.0

; --- Volume (Spotify's volume, not Windows) ---
VolumeDownKey      := "F13"   ; key that lowers volume
VolumeUpKey        := "F14"   ; key that raises volume
MuteKey            := ""      ; e.g. "F15" or "^m" — mute / unmute
VolumeIncrement    := 2       ; how many % each press changes (1–100)
ShowVolumeTip      := true    ; tooltip for volume, mute, shuffle, repeat, like
VolumeDebounceMs   := 100     ; wait this many ms after the last press before
                              ; talking to Spotify (smooths fast scrolling)
VolumeResyncMs     := 2500    ; after this idle time, re-read state from Spotify
                              ; (volume / shuffle / repeat changed in the app)

; --- Playback (optional – set a key, or leave "" to disable) ---
PlayPauseKey       := ""      ; e.g. "Media_Play_Pause" or "^Space"
NextTrackKey       := ""      ; e.g. "Media_Next"
PreviousTrackKey   := ""      ; e.g. "Media_Prev"
ShuffleKey         := ""      ; toggles shuffle on/off
RepeatKey          := ""      ; cycles: repeat track → repeat context → off
SaveTrackKey       := ""      ; like / unlike the current track
