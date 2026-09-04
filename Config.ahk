; ============================================================
; Spotify.ahk – user settings
; Edit this file, then run Example Hotkeys.ahk
; Leave a key blank ("") to disable that hotkey.
; ============================================================

; --- Volume ---
VolumeDownKey      := "F13"   ; e.g. "F13", "!WheelDown", "^Down"
VolumeUpKey        := "F14"
VolumeIncrement    := 2       ; percent per step (1–100)
ShowVolumeTip      := true    ; tooltip while adjusting
VolumeDebounceMs   := 100     ; coalesce rapid changes before API call
VolumeResyncMs     := 2500    ; re-read Spotify volume after idle

; --- Playback (optional) ---
PlayPauseKey       := ""      ; e.g. "Media_Play_Pause"
NextTrackKey       := ""      ; e.g. "Media_Next"
PreviousTrackKey   := ""      ; e.g. "Media_Prev"
ShuffleKey         := ""
RepeatKey          := ""
