/*
Spotify Volume — control Spotify’s volume (and optional playback) via hotkeys.
Edit Config.ahk to change keys and behavior.
*/

#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1

#Include %A_ScriptDir%\Config.ahk
#Include %A_ScriptDir%\Spotify.ahk

; Survive unexpected errors without killing the script mid-hotkey
OnError(ScriptError)

; --- Config defaults / sanitizing ---
VolumeDownKey := VolumeDownKey ?? "F13"
VolumeUpKey := VolumeUpKey ?? "F14"
MuteKey := MuteKey ?? ""
VolumeIncrement := Clamp(ToNumber(VolumeIncrement ?? 2, 2), 1, 100)
ShowVolumeTip := !!(ShowVolumeTip ?? true)
VolumeDebounceMs := Max(ToNumber(VolumeDebounceMs ?? 100, 100), 0)
VolumeResyncMs := Max(ToNumber(VolumeResyncMs ?? 2500, 2500), 500)
PlayPauseKey := PlayPauseKey ?? ""
NextTrackKey := NextTrackKey ?? ""
PreviousTrackKey := PreviousTrackKey ?? ""
ShuffleKey := ShuffleKey ?? ""
RepeatKey := RepeatKey ?? ""
SaveTrackKey := SaveTrackKey ?? ""

try
	spoofy := Spotify()
catch as err {
	MsgBox("Could not start Spotify Volume:`n`n" err.Message, "Spotify Volume", "Iconx")
	ExitApp
}

if IsObject(spoofy.CurrentUser) && spoofy.CurrentUser.subscriptionLevel = "free"
	MsgBox("Spotify Premium is required for Connect API volume/playback control.`n`nFree accounts can authorize but player commands will fail.", "Spotify Volume", "Icon!")

CurrentVolume := -1
VolumeBeforeMute := -1
ShuffleMode := ""
RepeatMode := ""

SetupTray()
BindHotkeys()


; =====================================
; Hotkey handlers
; =====================================

PlayPause() {
	global spoofy
	try spoofy.Player.PlayPause()
	catch
		ShowTip("Spotify: unavailable")
}

NextTrack() {
	global spoofy
	try spoofy.Player.NextTrack()
	catch
		ShowTip("Spotify: unavailable")
}

PreviousTrack() {
	global spoofy
	try spoofy.Player.PreviousTrack()
	catch
		ShowTip("Spotify: unavailable")
}

ToggleShuffle() {
	global spoofy, ShuffleMode
	EnsurePlaybackState()
	if ShuffleMode = "" {
		ShowTip("Spotify: nothing playing")
		return
	}

	NewMode := !ShuffleMode
	try {
		spoofy.Player.SetShuffle(NewMode)
		ShuffleMode := NewMode
		ShowTip(ShuffleMode ? "Shuffle on" : "Shuffle off")
		SchedulePlaybackResync()
	} catch {
		ResetPlaybackCache()
		ShowTip("Spotify: unavailable")
	}
}

CycleRepeat() {
	global spoofy, RepeatMode
	static Labels := Map(1, "Repeat track", 2, "Repeat context", 3, "Repeat off")

	EnsurePlaybackState()
	if RepeatMode = "" {
		ShowTip("Spotify: nothing playing")
		return
	}

	; 1 = track, 2 = context, 3 = off
	NewMode := Mod(RepeatMode, 3) + 1
	try {
		spoofy.Player.SetRepeatMode(NewMode)
		RepeatMode := NewMode
		ShowTip(Labels[RepeatMode])
		SchedulePlaybackResync()
	} catch {
		ResetPlaybackCache()
		ShowTip("Spotify: unavailable")
	}
}

ToggleSaveTrack() {
	global spoofy
	try {
		Result := spoofy.Player.ToggleSaveCurrentlyPlaying()
		if Result = "" {
			ShowTip("Spotify: nothing playing")
			return
		}
		ShowTip(Result ? "Added to Liked Songs" : "Removed from Liked Songs")
	} catch
		ShowTip("Spotify: unavailable")
}

ToggleMute() {
	global CurrentVolume, VolumeBeforeMute

	if !EnsureVolumeCache() {
		ShowTip("Spotify: no active device")
		return
	}

	if CurrentVolume = 0 && VolumeBeforeMute >= 0 {
		CurrentVolume := VolumeBeforeMute
		VolumeBeforeMute := -1
	} else {
		VolumeBeforeMute := CurrentVolume > 0 ? CurrentVolume : 50
		CurrentVolume := 0
	}

	ShowTip("Spotify  " CurrentVolume "%")
	ApplyVolumeNow()
}


; =====================================
; Volume (debounced + cached)
; =====================================

AdjustVolume(Delta) {
	global CurrentVolume, VolumeBeforeMute, VolumeDebounceMs, VolumeResyncMs

	if !EnsureVolumeCache() {
		ShowTip("Spotify: no active device")
		return
	}

	; Volume up while muted → unmute
	if VolumeBeforeMute >= 0 && CurrentVolume = 0 && Delta > 0
		VolumeBeforeMute := -1

	CurrentVolume := Clamp(CurrentVolume + Delta, 0, 100)
	if CurrentVolume > 0
		VolumeBeforeMute := -1

	ShowTip("Spotify  " CurrentVolume "%")
	SetTimer(ApplyVolume, -VolumeDebounceMs)
	SetTimer(ResetVolumeCache, -VolumeResyncMs)
}

EnsureVolumeCache() {
	global spoofy, CurrentVolume

	if CurrentVolume >= 0
		return true

	try
		PlaybackInfo := spoofy.Player.GetCurrentPlaybackInfo()
	catch
		return false

	if !IsObject(PlaybackInfo) || !IsObject(PlaybackInfo.Device)
		return false

	Volume := PlaybackInfo.Device.volume
	if !IsNumber(Volume)
		return false

	CurrentVolume := Clamp(Integer(Volume), 0, 100)
	return true
}

ApplyVolume() {
	global spoofy, CurrentVolume
	if CurrentVolume < 0
		return
	try
		spoofy.Player.SetVolume(CurrentVolume)
	catch {
		CurrentVolume := -1
		ShowTip("Spotify: unavailable")
	}
}

ApplyVolumeNow() {
	global VolumeResyncMs
	SetTimer(ApplyVolume, 0)
	ApplyVolume()
	SetTimer(ResetVolumeCache, -VolumeResyncMs)
}

ResetVolumeCache() {
	global CurrentVolume
	CurrentVolume := -1
}


; =====================================
; Helpers
; =====================================

BindHotkeys() {
	global VolumeDownKey, VolumeUpKey, MuteKey, VolumeIncrement
	global PlayPauseKey, NextTrackKey, PreviousTrackKey
	global ShuffleKey, RepeatKey, SaveTrackKey

	BindHotkey(VolumeDownKey, (*) => AdjustVolume(-VolumeIncrement))
	BindHotkey(VolumeUpKey, (*) => AdjustVolume(VolumeIncrement))
	BindHotkey(MuteKey, (*) => ToggleMute())
	BindHotkey(PlayPauseKey, (*) => PlayPause())
	BindHotkey(NextTrackKey, (*) => NextTrack())
	BindHotkey(PreviousTrackKey, (*) => PreviousTrack())
	BindHotkey(ShuffleKey, (*) => ToggleShuffle())
	BindHotkey(RepeatKey, (*) => CycleRepeat())
	BindHotkey(SaveTrackKey, (*) => ToggleSaveTrack())
}

BindHotkey(Key, Callback) {
	if Key = "" || Key = "false" || Key = "off"
		return
	try
		Hotkey(Key, Callback)
	catch as err
		MsgBox("Invalid hotkey in Config.ahk:`n`n" Key "`n`n" err.Message, "Spotify Volume", "Icon!")
}

ShowTip(Text) {
	global ShowVolumeTip
	if !ShowVolumeTip
		return
	ToolTip(Text)
	SetTimer(ClearTip, -900)
}

ClearTip() {
	ToolTip()
}

EnsurePlaybackState() {
	global spoofy, ShuffleMode, RepeatMode
	if ShuffleMode != "" && RepeatMode != ""
		return

	try
		Info := spoofy.Player.GetCurrentPlaybackInfo()
	catch
		return
	if !IsObject(Info)
		return

	ShuffleMode := Info.HasOwnProp("shuffle_state") ? !!Info.shuffle_state : false
	if Info.HasOwnProp("repeat_state") {
		RepeatMode := (Info.repeat_state = "track" ? 1 : (Info.repeat_state = "context" ? 2 : 3))
	} else {
		RepeatMode := 3
	}
}

SchedulePlaybackResync() {
	global VolumeResyncMs
	SetTimer(ResetPlaybackCache, -VolumeResyncMs)
}

ResetPlaybackCache() {
	global ShuffleMode, RepeatMode
	ShuffleMode := ""
	RepeatMode := ""
}

SetupTray() {
	A_IconTip := "Spotify Volume"
	Tray := A_TrayMenu
	Tray.Delete()
	Tray.Add("Reload", (*) => Reload())
	Tray.Add("Re-authorize…", TrayReAuthorize)
	Tray.Add()
	Tray.Add("Exit", (*) => ExitApp())
	Tray.Default := "Reload"
}

TrayReAuthorize(*) {
	global spoofy
	if MsgBox("Clear saved Spotify tokens and authorize again?", "Spotify Volume", "YesNo Icon?") != "Yes"
		return
	try spoofy.Util.PKCE.ClearSavedTokens()
	Reload()
}

ToNumber(Value, Fallback) {
	try {
		if IsNumber(Value)
			return Value + 0
		return Integer(Value)
	} catch
		return Fallback
}

; Return true = keep script alive (only after successful startup)
ScriptError(err, mode) {
	global spoofy
	if !IsSet(spoofy)
		return false
	try ShowTip("Spotify: error")
	return true
}
