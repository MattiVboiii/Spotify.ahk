/*
Example hotkeys for Spotify.ahk
Edit Config.ahk to change keys and volume behavior.
*/

#Requires AutoHotkey v1.1
#SingleInstance Force

#Include %A_ScriptDir%\Config.ahk
#Include %A_ScriptDir%\Spotify.ahk

spoofy := new Spotify

CurrentVolume := -1
ShuffleMode := ""
RepeatMode := ""

BindHotkey(VolumeDownKey, "VolumeDown")
BindHotkey(VolumeUpKey, "VolumeUp")
BindHotkey(PlayPauseKey, "PlayPause")
BindHotkey(NextTrackKey, "NextTrack")
BindHotkey(PreviousTrackKey, "PreviousTrack")
BindHotkey(ShuffleKey, "ToggleShuffle")
BindHotkey(RepeatKey, "CycleRepeat")

return


; =====================================
; Hotkey handlers
; =====================================

VolumeDown:
AdjustVolume(-VolumeIncrement)
return

VolumeUp:
AdjustVolume(VolumeIncrement)
return

PlayPause:
try spoofy.Player.PlayPause()
return

NextTrack:
try spoofy.Player.NextTrack()
return

PreviousTrack:
try spoofy.Player.LastTrack()
return

ToggleShuffle:
EnsurePlaybackState()
if (ShuffleMode = "")
    return
ShuffleMode := !ShuffleMode
try spoofy.Player.SetShuffle(ShuffleMode)
return

CycleRepeat:
EnsurePlaybackState()
if (RepeatMode = "")
    return
; 1 = track, 2 = context, 3 = off
RepeatMode := (RepeatMode = 1 ? 2 : (RepeatMode = 2 ? 3 : 1))
try spoofy.Player.SetRepeatMode(RepeatMode)
return


; =====================================
; Volume (debounced + cached)
; =====================================

AdjustVolume(Delta) {
    global spoofy, CurrentVolume, ShowVolumeTip, VolumeDebounceMs, VolumeResyncMs

    if (CurrentVolume < 0) {
        try
            PlaybackInfo := spoofy.Player.GetCurrentPlaybackInfo()
        catch e
            return

        if (!IsObject(PlaybackInfo) || !IsObject(PlaybackInfo.Device))
            return

        Volume := PlaybackInfo.Device.Volume
        if (Volume = "" || Volume = "null")
            return

        CurrentVolume := Volume
    }

    CurrentVolume += Delta
    if (CurrentVolume < 0)
        CurrentVolume := 0
    else if (CurrentVolume > 100)
        CurrentVolume := 100

    if (ShowVolumeTip) {
        ToolTip, % "Spotify  " CurrentVolume "%"
        SetTimer, ClearVolumeTip, -700
    }

    SetTimer, ApplyVolume, % -VolumeDebounceMs
    SetTimer, ResetVolumeCache, % -VolumeResyncMs
}

ApplyVolume:
if (CurrentVolume >= 0) {
    try
        spoofy.Player.SetVolume(CurrentVolume)
    catch e
        CurrentVolume := -1
}
return

ResetVolumeCache:
CurrentVolume := -1
return

ClearVolumeTip:
ToolTip
return


; =====================================
; Helpers
; =====================================

BindHotkey(Key, LabelName) {
    if (Key = "" || Key = "false" || Key = "off")
        return
    Hotkey, %Key%, %LabelName%, On
}

EnsurePlaybackState() {
    global spoofy, ShuffleMode, RepeatMode
    if (ShuffleMode != "" && RepeatMode != "")
        return
    try
        Info := spoofy.Player.GetCurrentPlaybackInfo()
    catch e
        return
    if (!IsObject(Info))
        return
    ShuffleMode := Info.shuffle_state
    RepeatMode := (Info.repeat_state = "track" ? 1 : (Info.repeat_state = "context" ? 2 : 3))
}
