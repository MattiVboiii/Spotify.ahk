/*
Spotify Volume — Spotify volume + optional playback via hotkeys.
Edit Config.ahk (same section order as below), then Reload from tray.

  1. Volume
  2. Playback
  3. Seek
  4. Tip
  5. Device / cache
  6. Elevation / config bootstrap
  7. Tray
  8. Updates
  9. Utilities
*/

#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1

#Include *i %A_ScriptDir%\Config.ahk
#Include %A_ScriptDir%\Spotify.ahk

; --- Runtime state (statics; no global spam) ---

class App {
    static Version := "0.0.0"
    static GitHubRepo := "MattiVboiii/Spotify.ahk"
}

class Cfg {
    ; Defaults — LoadConfig() overwrites from Config.ahk (same section order)
    ; 1. Volume
    static VolumeDownKey := "F13"
    static VolumeUpKey := "F14"
    static MuteKey := ""
    static VolumeIncrement := 2
    static VolumeDebounceMs := 100
    static VolumeResyncMs := 2500
    static WheelAccelWindowMs := 400
    static WheelAccelMax := 5
    ; 2. Playback
    static PlayPauseKey := ""
    static PlayPauseDebounceMs := 300
    static NextTrackKey := ""
    static PreviousTrackKey := ""
    static ShuffleKey := ""
    static RepeatKey := ""
    static SaveTrackKey := ""
    ; 3. Seek
    static SeekForwardKey := ""
    static SeekBackwardKey := ""
    static SeekStepMs := 10000
    ; 4. Tip
    static ShowVolumeTip := true
    static TipPosition := "bottom"
    static TipDurationMs := 900
    static TipOpacity := 230
    static NowPlayingTipOn := "volume"
    ; 5–8
    static AutoActivateDevice := true
    static ElevateMode := ""
    static SpotifyClientId := ""
    static CheckForUpdates := true
}

; --- Avoid naming this "Volume" (clashes with SetVolume parameter names) ---
class Vol {
    static current := -1
    static beforeMute := -1
    static wheelLevel := 1
    static wheelLastTick := 0
}

class Playback {
    static shuffle := ""
    static repeat := ""
    static cache := false
    static cacheAt := 0
    static hasCache := false
    static pendingPlayPause := false
}

; --- Bootstrap ---

OnError(ScriptError)
App.Version := ReadAppVersion()
LoadConfig()
MaybeElevate()
EnsureConfigFile()

if Cfg.SpotifyClientId != ""
    Spotify.PKCE.CLIENT_ID := Cfg.SpotifyClientId

try
    spoofy := Spotify()
catch as err {
    MsgBox("Could not start Spotify Volume:`n`n" err.Message, "Spotify Volume", "Iconx")
    ExitApp
}

if IsObject(spoofy.CurrentUser) && spoofy.CurrentUser.subscriptionLevel = "free"
    MsgBox(
        "Spotify Premium is required for Connect API volume/playback control.`n`n"
        . "Free accounts can authorize but player commands will fail.",
        "Spotify Volume", "Icon!"
    )

SetupTray()
BindHotkeys()
ScheduleUpdateCheck()

; =============================================================================
; 1. Volume
; =============================================================================

AdjustVolume(Delta) {
    try {
        if InStr(A_ThisHotkey, "Wheel") {
            if (A_TickCount - Vol.wheelLastTick) <= Cfg.WheelAccelWindowMs
                Vol.wheelLevel := Min(Vol.wheelLevel + 1, Cfg.WheelAccelMax)
            else
                Vol.wheelLevel := 1
            Vol.wheelLastTick := A_TickCount
            Delta *= Vol.wheelLevel
        }

        if !EnsureVolumeCache() {
            Tip.Show("Spotify: no active device")
            return
        }

        ; Volume up while muted → unmute
        if Vol.beforeMute >= 0 && Vol.current = 0 && Delta > 0
            Vol.beforeMute := -1

        Vol.current := Clamp(Vol.current + Delta, 0, 100)
        if Vol.current > 0
            Vol.beforeMute := -1

        Tip.Show(FormatVolumeTip(Vol.current))
        if Cfg.VolumeDebounceMs <= 0
            ApplyVolume()
        else
            SetTimer(ApplyVolume, -Cfg.VolumeDebounceMs)
        SetTimer(ResetVolumeCache, -Cfg.VolumeResyncMs)
    } catch as err
        Tip.Show(FriendlyError(err))
}

ToggleMute() {
    try {
        if !EnsureVolumeCache() {
            Tip.Show("Spotify: no active device")
            return
        }
        if Vol.current = 0 && Vol.beforeMute >= 0 {
            Vol.current := Vol.beforeMute
            Vol.beforeMute := -1
        } else {
            Vol.beforeMute := Vol.current > 0 ? Vol.current : 50
            Vol.current := 0
        }
        Tip.Show(FormatVolumeTip(Vol.current))
        ApplyVolumeNow()
    } catch as err
        Tip.Show(FriendlyError(err))
}

EnsureVolumeCache() {
    if Vol.current >= 0
        return true
    if !EnsureActiveDevice()
        return false
    Info := FetchPlayback(false)
    if !IsObject(Info) || !IsObject(Info.Device) || !IsNumber(Info.Device.volume)
        return false
    Vol.current := Clamp(Integer(Info.Device.volume), 0, 100)
    return true
}

ApplyVolume() {
    global spoofy
    if Vol.current < 0
        return
    try
        spoofy.Player.SetVolume(Vol.current)
    catch as err {
        Vol.current := -1
        InvalidatePlaybackCache()
        Tip.Show(FriendlyError(err))
    }
}

ApplyVolumeNow() {
    SetTimer(ApplyVolume, 0)
    Defer(ApplyVolume)
    SetTimer(ResetVolumeCache, -Cfg.VolumeResyncMs)
}

ResetVolumeCache() {
    Vol.current := -1
    InvalidatePlaybackCache()
}

; =============================================================================
; 2. Playback
; =============================================================================

PlayPause() {
    Playback.pendingPlayPause := true
    if Cfg.PlayPauseDebounceMs <= 0 {
        FlushPlayPause()
        return
    }
    SetTimer(FlushPlayPause, -Cfg.PlayPauseDebounceMs)
}

FlushPlayPause() {
    if !Playback.pendingPlayPause
        return
    Playback.pendingPlayPause := false
    Defer(() => RunOnActiveDevice((P) => P.PlayPause(), true))
}

NextTrack() {
    Defer(() => RunOnActiveDevice((P) => P.NextTrack(), true))
}

PreviousTrack() {
    Defer(() => RunOnActiveDevice((P) => P.PreviousTrack(), true))
}

ToggleShuffle() {
    Defer(DoToggleShuffle)
}

DoToggleShuffle() {
    global spoofy
    try {
        if !EnsurePlaybackState() {
            Tip.Show("Spotify: nothing playing")
            return
        }
        NewMode := !Playback.shuffle
        spoofy.Player.SetShuffle(NewMode)
        Playback.shuffle := NewMode
        Tip.Show(NewMode ? "Shuffle on" : "Shuffle off")
        SchedulePlaybackResync()
    } catch as err {
        ResetPlaybackCache()
        Tip.Show(FriendlyError(err))
    }
}

CycleRepeat() {
    Defer(DoCycleRepeat)
}

DoCycleRepeat() {
    global spoofy
    static Labels := Map(1, "Repeat track", 2, "Repeat context", 3, "Repeat off")
    try {
        if !EnsurePlaybackState() {
            Tip.Show("Spotify: nothing playing")
            return
        }
        ; 1 = track, 2 = context, 3 = off
        NewMode := Mod(Playback.repeat, 3) + 1
        spoofy.Player.SetRepeatMode(NewMode)
        Playback.repeat := NewMode
        Tip.Show(Labels[NewMode])
        SchedulePlaybackResync()
    } catch as err {
        ResetPlaybackCache()
        Tip.Show(FriendlyError(err))
    }
}

ToggleSaveTrack() {
    Defer(DoToggleSaveTrack)
}

DoToggleSaveTrack() {
    global spoofy
    try {
        if !EnsureActiveDevice() {
            Tip.Show("Spotify: no active device")
            return
        }
        Result := spoofy.Player.ToggleSaveCurrentlyPlaying()
        if Result = "" {
            Tip.Show("Spotify: nothing playing")
            return
        }
        Tip.Show(Result ? "Added to Liked Songs" : "Removed from Liked Songs")
    } catch as err
        Tip.Show(FriendlyError(err))
}

; =============================================================================
; 3. Seek
; =============================================================================

SeekRelative(DeltaMs) {
    Defer(DoSeek.Bind(DeltaMs))
}

DoSeek(DeltaMs) {
    global spoofy
    try {
        Info := FetchPlayback(false)
        if !HasTrack(Info) {
            if !EnsureActiveDevice() {
                Tip.Show("Spotify: no active device")
                return
            }
            Info := FetchPlayback(true)
        }
        if !IsObject(Info) || !IsObject(Info.Track) {
            Tip.Show("Spotify: nothing playing")
            return
        }

        Progress := Info.HasOwnProp("progress_ms") ? Integer(Info.progress_ms) : 0
        Duration := Info.Track.duration_ms > 0 ? Info.Track.duration_ms : Progress + Abs(DeltaMs)
        spoofy.Player.SeekTo(Clamp(Progress + DeltaMs, 0, Max(Duration - 1, 0)))

        Tip.Show((DeltaMs < 0 ? "<<" : ">>") " " Round(Abs(DeltaMs) / 1000) "s")
        InvalidatePlaybackCache()
        SchedulePlaybackResync()
    } catch as err
        Tip.Show(FriendlyError(err))
}

; =============================================================================
; 4. Tip
; =============================================================================

class Tip {
    static Window := 0
    static Visible := false
    static W := 0
    static H := 0
    static X := 0
    static Y := 0
    static MarginX := 14
    static MarginY := 10
    static FontName := "Segoe UI"
    static FontSize := 11

    static Show(Text) {
        if !Cfg.ShowVolumeTip
            return

        if !Tip.Window {
            ; WS_EX_NOACTIVATE | click-through | composited
            Tip.Window := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x20 +E0x02000000")
            Tip.Window.BackColor := "1A1A1A"
            Tip.Window.MarginX := Tip.MarginX
            Tip.Window.MarginY := Tip.MarginY
            Tip.Window.SetFont("s" Tip.FontSize " cWhite", Tip.FontName)
            Tip.Window.Add("Text", "vTipText Center BackgroundTrans", Text)
            WinSetTransparent(Cfg.TipOpacity, Tip.Window)
            Tip.Visible := false
        }

        Size := Tip.Measure(Text)
        NeedW := Max(Size.w, 1) + Tip.MarginX * 2
        NeedH := Max(Size.h, 1) + Tip.MarginY * 2

        ; Prefetch width for "100%" so scrolling 2% → 100% doesn't resize
        if RegExMatch(Text, "s)^Spotify  \d+%") {
            Pad := Tip.Measure(RegExReplace(Text, "s)^(Spotify  )\d+%", "$1100"))
            NeedW := Max(NeedW, Pad.w + Tip.MarginX * 2)
            NeedH := Max(NeedH, Pad.h + Tip.MarginY * 2)
        }

        Ctrl := Tip.Window["TipText"]

        ; Same size — text only (no Move = no flicker)
        if Tip.Visible && NeedW <= Tip.W && NeedH <= Tip.H {
            Ctrl.Value := Text
            Tip.ScheduleHide()
            return
        }

        if Tip.Visible {
            Tip.W := Max(Tip.W, NeedW)
            Tip.H := Max(Tip.H, NeedH)
            Hwnd := Tip.Window.Hwnd
            DllCall("SendMessage", "Ptr", Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0) ; WM_SETREDRAW off
            Ctrl.Value := Text
            Ctrl.Move(Tip.MarginX, Tip.MarginY, Tip.W - Tip.MarginX * 2, Tip.H - Tip.MarginY * 2)
            Tip.Window.Move(Tip.X, Tip.Y, Tip.W, Tip.H)
            DllCall("SendMessage", "Ptr", Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0) ; WM_SETREDRAW on
            DllCall("RedrawWindow", "Ptr", Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0105)
        } else {
            Tip.W := NeedW
            Tip.H := NeedH
            Tip.X := (A_ScreenWidth - Tip.W) // 2
            switch Cfg.TipPosition {
                case "top":
                    Tip.Y := 80
                case "center", "middle":
                    Tip.Y := (A_ScreenHeight - Tip.H) // 2
                default:
                    Tip.Y := A_ScreenHeight - Tip.H - 80
            }
            Ctrl.Value := Text
            Ctrl.Move(Tip.MarginX, Tip.MarginY, Tip.W - Tip.MarginX * 2, Tip.H - Tip.MarginY * 2)
            Tip.Window.Show("NoActivate x" Tip.X " y" Tip.Y " w" Tip.W " h" Tip.H)
            Tip.Visible := true
        }
        Tip.ScheduleHide()
    }

    ; SetTimer rejects bare class methods — wrap in a closure
    static ScheduleHide() {
        SetTimer((*) => Tip.Hide(), -Cfg.TipDurationMs)
    }

    static Hide(*) {
        if Tip.Window
            Tip.Window.Hide()
        Tip.Visible := false
    }

    static Measure(Text) {
        Hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        LogPixels := DllCall("GetDeviceCaps", "Ptr", Hdc, "Int", 90) ; LOGPIXELSY
        Height := -DllCall("MulDiv", "Int", Tip.FontSize, "Int", LogPixels, "Int", 72)
        HFont := DllCall(
            "CreateFontW",
            "Int", Height, "Int", 0, "Int", 0, "Int", 0, "Int", 400,
            "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0,
            "WStr", Tip.FontName, "Ptr"
        )
        Prev := DllCall("SelectObject", "Ptr", Hdc, "Ptr", HFont, "Ptr")

        MaxW := 0
        TotalH := 0
        SizeBuf := Buffer(8, 0)
        for Line in StrSplit(Text, "`n") {
            DllCall("GetTextExtentPoint32W", "Ptr", Hdc, "WStr", Line, "Int", StrLen(Line), "Ptr", SizeBuf)
            MaxW := Max(MaxW, NumGet(SizeBuf, 0, "Int"))
            TotalH += NumGet(SizeBuf, 4, "Int")
        }
        if TotalH = 0 {
            DllCall("GetTextExtentPoint32W", "Ptr", Hdc, "WStr", " ", "Int", 1, "Ptr", SizeBuf)
            TotalH := NumGet(SizeBuf, 4, "Int")
        }

        DllCall("SelectObject", "Ptr", Hdc, "Ptr", Prev)
        DllCall("DeleteObject", "Ptr", HFont)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", Hdc)
        return { w: MaxW, h: TotalH }
    }
}

FormatVolumeTip(Level) {
    Line := "Spotify  " Level "%"
    if !NowPlayingEnabled("volume")
        return Line
    Np := Playback.hasCache ? FormatNowPlaying(Playback.cache) : ""
    return Np = "" ? Line : Line "`n" Np
}

FormatNowPlaying(Info) {
    if !IsObject(Info) || !IsObject(Info.Track) || Info.Track.name = ""
        return ""
    return Info.Track.artist != "" ? Info.Track.artist " — " Info.Track.name : Info.Track.name
}

ShowNowPlayingFromCache(Force := false) {
    try {
        if Force
            Sleep(350) ; Spotify metadata lags briefly after skip
        Text := FormatNowPlaying(FetchPlayback(Force))
        if Text != ""
            Tip.Show(Text)
    } catch {
    }
}

NowPlayingEnabled(Context) {
    switch Cfg.NowPlayingTipOn {
        case "both", "all":
            return true
        case "volume":
            return Context = "volume"
        case "playback", "media":
            return Context = "playback"
        default:
            return false
    }
}

; =============================================================================
; 5. Device / cache
; =============================================================================

FetchPlayback(Force := false) {
    global spoofy

    if !Force && Playback.hasCache && (A_TickCount - Playback.cacheAt) < Cfg.VolumeResyncMs
        return Playback.cache

    Info := spoofy.Player.GetCurrentPlaybackInfo()
    Playback.cache := Info
    Playback.cacheAt := A_TickCount
    Playback.hasCache := true

    if IsObject(Info) {
        if IsObject(Info.Device) && IsNumber(Info.Device.volume)
            Vol.current := Clamp(Integer(Info.Device.volume), 0, 100)
        Playback.shuffle := Info.HasOwnProp("shuffle_state") ? !!Info.shuffle_state : false
        if Info.HasOwnProp("repeat_state")
            Playback.repeat := (Info.repeat_state = "track" ? 1 : (Info.repeat_state = "context" ? 2 : 3))
        else
            Playback.repeat := 3
    }
    return Info
}

InvalidatePlaybackCache() {
    Playback.cache := false
    Playback.hasCache := false
    Playback.cacheAt := 0
}

ResetPlaybackCache() {
    Playback.shuffle := ""
    Playback.repeat := ""
    InvalidatePlaybackCache()
}

SchedulePlaybackResync() {
    SetTimer(ResetPlaybackCache, -Cfg.VolumeResyncMs)
}

EnsureActiveDevice() {
    global spoofy

    try
        Info := FetchPlayback(false)
    catch as err {
        ; Surface network/auth; empty player is fine
        if err.Extra = "offline" || err.Extra = 429 || (IsNumber(err.Extra) && err.Extra >= 400 && err.Extra != 404)
            throw err
        Info := false
    }

    if HasActiveDevice(Info)
        return true
    if !Cfg.AutoActivateDevice
        return false

    try {
        DeviceId := PickTransferDevice()
        if DeviceId = "" {
            Run("spotify:")
            DeviceId := WaitForDevice(8000)
        }
        if DeviceId = ""
            return false
        spoofy.Player.TransferPlayback(DeviceId, true)
        Sleep(400)
        InvalidatePlaybackCache()
        return HasActiveDevice(FetchPlayback(true))
    } catch {
        return false
    }
}

PickTransferDevice() {
    global spoofy
    Devices := spoofy.Player.GetDevices()
    if !IsObject(Devices) || Devices.Length = 0
        return ""
    for Dev in Devices {
        if IsObject(Dev) && Dev.HasOwnProp("is_active") && Dev.is_active && Dev.HasOwnProp("id") && Dev.id
            return Dev.id
    }
    for Dev in Devices {
        if IsObject(Dev) && Dev.HasOwnProp("id") && Dev.id
            return Dev.id
    }
    return ""
}

WaitForDevice(TimeoutMs) {
    Deadline := A_TickCount + TimeoutMs
    while A_TickCount < Deadline {
        try {
            Id := PickTransferDevice()
            if Id != ""
                return Id
        }
        Sleep(500)
    }
    return ""
}

EnsurePlaybackState() {
    if Playback.shuffle != "" && Playback.repeat != ""
        return true
    try {
        if !EnsureActiveDevice()
            return false
        FetchPlayback(false)
    } catch
        return false
    return Playback.shuffle != "" && Playback.repeat != ""
}

RunOnActiveDevice(Action, ShowNowPlaying := false) {
    global spoofy
    try {
        if !EnsureActiveDevice() {
            Tip.Show("Spotify: no active device")
            return
        }
        Action.Call(spoofy.Player)
        InvalidatePlaybackCache()
        if ShowNowPlaying && NowPlayingEnabled("playback")
            ShowNowPlayingFromCache(true)
    } catch as err
        Tip.Show(FriendlyError(err))
}

HasActiveDevice(Info) {
    return IsObject(Info) && IsObject(Info.Device) && Info.Device.id != ""
}

HasTrack(Info) {
    return IsObject(Info) && IsObject(Info.Track) && Info.Track.id != ""
}

; =============================================================================
; 6. Elevation / config bootstrap
; =============================================================================

LoadConfig() {
    ; 1. Volume
    Cfg.VolumeDownKey := ConfigKey("VolumeDownKey", "F13")
    Cfg.VolumeUpKey := ConfigKey("VolumeUpKey", "F14")
    Cfg.MuteKey := ConfigKey("MuteKey", "")
    Cfg.VolumeIncrement := ConfigInt("VolumeIncrement", 2, 1, 100)
    Cfg.VolumeDebounceMs := ConfigInt("VolumeDebounceMs", 100, 0)
    Cfg.VolumeResyncMs := ConfigInt("VolumeResyncMs", 2500, 500)
    Cfg.WheelAccelWindowMs := ConfigInt("WheelAccelWindowMs", 400, 50)
    Cfg.WheelAccelMax := ConfigInt("WheelAccelMax", 5, 1, 20)
    ; 2. Playback
    Cfg.PlayPauseKey := ConfigKey("PlayPauseKey", "")
    Cfg.PlayPauseDebounceMs := ConfigInt("PlayPauseDebounceMs", 300, 0)
    Cfg.NextTrackKey := ConfigKey("NextTrackKey", "")
    Cfg.PreviousTrackKey := ConfigKey("PreviousTrackKey", "")
    Cfg.ShuffleKey := ConfigKey("ShuffleKey", "")
    Cfg.RepeatKey := ConfigKey("RepeatKey", "")
    Cfg.SaveTrackKey := ConfigKey("SaveTrackKey", "")
    ; 3. Seek
    Cfg.SeekForwardKey := ConfigKey("SeekForwardKey", "")
    Cfg.SeekBackwardKey := ConfigKey("SeekBackwardKey", "")
    Cfg.SeekStepMs := ConfigInt("SeekStepMs", 10000, 1000)
    ; 4. Tip
    Cfg.ShowVolumeTip := ConfigBool("ShowVolumeTip", true)
    Cfg.TipPosition := ConfigLower("TipPosition", "bottom")
    Cfg.TipDurationMs := ConfigInt("TipDurationMs", 900, 200)
    Cfg.TipOpacity := ConfigInt("TipOpacity", 230, 50, 255)
    Cfg.NowPlayingTipOn := NormalizeNowPlayingTip()
    ; 5–8. Device / Games / Auth / Updates
    Cfg.AutoActivateDevice := ConfigBool("AutoActivateDevice", true)
    Cfg.ElevateMode := ElevateMode ?? ""
    Cfg.SpotifyClientId := Trim(String(SpotifyClientId ?? ""))
    Cfg.CheckForUpdates := ConfigBool("CheckForUpdates", true)
}

MaybeElevate() {
    Mode := StrLower(Trim(String(Cfg.ElevateMode)))
    if Mode = "" || Mode = "off" || Mode = "false" || Mode = "0"
        return

    CmdLine := DllCall("GetCommandLine", "Str")
    AlreadyRestarted := RegExMatch(CmdLine, "i)(?:^|\s)/restart(?!\S)")
    RunningUIA := InStr(A_AhkPath, "_UIA")

    try {
        if Mode = "admin" || Mode = "administrator" || Mode = "runas" {
            if A_IsAdmin || AlreadyRestarted
                return
            if A_IsCompiled
                Run('*RunAs "' A_ScriptFullPath '" /restart')
            else
                Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"')
            ExitApp
        }
        if Mode = "uia" || Mode = "uiaccess" || Mode = "ui" {
            if RunningUIA || AlreadyRestarted
                return
            Run('*UIAccess "' A_ScriptFullPath '" /restart')
            ExitApp
        }
        MsgBox(
            "Unknown ElevateMode in Config.ahk: " Cfg.ElevateMode
            . "`n`nUse uia, admin, or blank.",
            "Spotify Volume", "Icon!"
        )
    } catch as err {
        MsgBox(
            "Could not elevate for games (" Cfg.ElevateMode "):`n`n" err.Message
            . "`n`nFor uia, AutoHotkey must be installed under Program Files."
            . "`nTry ElevateMode := admin instead, or leave it blank."
            . "`n`nContinuing without elevation.",
            "Spotify Volume", "Icon!"
        )
    }
}

EnsureConfigFile() {
    ConfigPath := A_ScriptDir "\Config.ahk"
    ExamplePath := A_ScriptDir "\Config.example.ahk"
    if FileExist(ConfigPath) || !FileExist(ExamplePath)
        return
    try {
        FileCopy(ExamplePath, ConfigPath)
        MsgBox(
            "Created Config.ahk from Config.example.ahk.`n`n"
            . "Edit your hotkeys, then choose Reload from the tray icon.",
            "Spotify Volume", "Iconi"
        )
    }
}

BindHotkeys() {
    BindHotkey(Cfg.VolumeDownKey, (*) => AdjustVolume(-Cfg.VolumeIncrement))
    BindHotkey(Cfg.VolumeUpKey, (*) => AdjustVolume(Cfg.VolumeIncrement))
    BindHotkey(Cfg.MuteKey, (*) => ToggleMute())
    BindHotkey(Cfg.PlayPauseKey, (*) => PlayPause())
    BindHotkey(Cfg.NextTrackKey, (*) => NextTrack())
    BindHotkey(Cfg.PreviousTrackKey, (*) => PreviousTrack())
    BindHotkey(Cfg.ShuffleKey, (*) => ToggleShuffle())
    BindHotkey(Cfg.RepeatKey, (*) => CycleRepeat())
    BindHotkey(Cfg.SaveTrackKey, (*) => ToggleSaveTrack())
    BindHotkey(Cfg.SeekForwardKey, (*) => SeekRelative(Cfg.SeekStepMs))
    BindHotkey(Cfg.SeekBackwardKey, (*) => SeekRelative(-Cfg.SeekStepMs))
}

BindHotkey(Key, Callback) {
    if Key = "" || Key = "false" || Key = "off"
        return
    try
        Hotkey(Key, Callback)
    catch as err
        MsgBox("Invalid hotkey in Config.ahk:`n`n" Key "`n`n" err.Message, "Spotify Volume", "Icon!")
}

; =============================================================================
; 7. Tray
; =============================================================================

SetupTray() {
    A_IconTip := "Spotify Volume " App.Version
    Tray := A_TrayMenu
    Tray.Delete()
    Tray.Add("Reload", (*) => Reload())
    Tray.Add("Open Config…", TrayOpenConfig)
    Tray.Add("Re-authorize…", TrayReAuthorize)
    Tray.Add("Check for Updates…", (*) => RunUpdateCheck(true))
    Tray.Add()
    if FileExist(A_Startup "\Spotify Volume.lnk")
        Tray.Add("Remove from Startup", TrayRemoveStartup)
    else
        Tray.Add("Add to Startup", TrayAddStartup)
    Tray.Add()
    Tray.Add("Exit", (*) => ExitApp())
    Tray.Default := "Reload"
}

TrayOpenConfig(*) {
    ConfigPath := A_ScriptDir "\Config.ahk"
    ExamplePath := A_ScriptDir "\Config.example.ahk"
    if !FileExist(ConfigPath) && FileExist(ExamplePath) {
        try FileCopy(ExamplePath, ConfigPath)
    }
    if !FileExist(ConfigPath) {
        MsgBox("Config.ahk not found.", "Spotify Volume", "Iconx")
        return
    }
    try Run('notepad.exe "' ConfigPath '"')
    catch
        Run('"' ConfigPath '"')
}

TrayAddStartup(*) {
    try {
        FileCreateShortcut(A_ScriptFullPath, A_Startup "\Spotify Volume.lnk", A_ScriptDir, , "Spotify Volume hotkeys")
        Tip.Show("Added to Startup")
        SetupTray()
    } catch as err
        MsgBox("Could not create Startup shortcut:`n`n" err.Message, "Spotify Volume", "Iconx")
}

TrayRemoveStartup(*) {
    try {
        LinkPath := A_Startup "\Spotify Volume.lnk"
        if FileExist(LinkPath)
            FileDelete(LinkPath)
        Tip.Show("Removed from Startup")
        SetupTray()
    } catch as err
        MsgBox("Could not remove Startup shortcut:`n`n" err.Message, "Spotify Volume", "Iconx")
}

TrayReAuthorize(*) {
    global spoofy
    if MsgBox("Clear saved Spotify tokens and authorize again?", "Spotify Volume", "YesNo Icon?") != "Yes"
        return
    try spoofy.Util.PKCE.ClearSavedTokens()
    Reload()
}

; =============================================================================
; 8. Updates
; =============================================================================

ScheduleUpdateCheck() {
    if !Cfg.CheckForUpdates
        return
    ; Defer so auth / tips are not blocked on startup
    SetTimer(() => RunUpdateCheck(false), -3000)
}

RunUpdateCheck(Manual := false) {
    try {
        Release := FetchLatestRelease()
        if !IsObject(Release) || Release.version = "" {
            if Manual
                MsgBox("Could not reach GitHub releases.", "Spotify Volume", "Icon!")
            return
        }

        Current := NormalizeVersion(App.Version)
        Latest := NormalizeVersion(Release.version)
        if Current = "" || Latest = "" {
            if Manual
                MsgBox("Could not reach GitHub releases.", "Spotify Volume", "Icon!")
            return
        }

        ; Same or older remote → stay quiet (startup and tray)
        if CompareVersions(Latest, Current) <= 0
            return

        ; Startup: prompt once per remote version
        if !Manual && Latest = ReadLastSeenRelease()
            return
        WriteLastSeenRelease(Latest)

        Answer := MsgBox(
            "A newer Spotify Volume is available.`n`n"
            . "Current:  " Current "`n"
            . "Latest:   " Latest "`n`n"
            . "Open the release page?",
            "Spotify Volume", "YesNo Iconi"
        )
        if Answer = "Yes" && Release.url != ""
            Run(Release.url)
    } catch {
        if Manual
            MsgBox("Could not check for updates.", "Spotify Volume", "Icon!")
    }
}

FetchLatestRelease() {
    Req := ComObject("WinHttp.WinHttpRequest.5.1")
    Req.Open("GET", "https://api.github.com/repos/" App.GitHubRepo "/releases/latest", false)
    Req.SetRequestHeader("User-Agent", "Spotify.ahk/" App.Version)
    Req.SetRequestHeader("Accept", "application/vnd.github+json")
    Req.Send()
    if Req.Status != 200
        return false
    Data := JSON.Load(Req.ResponseText)
    if !IsObject(Data) || !Data.HasOwnProp("tag_name")
        return false
    Tag := NormalizeVersion(Data.tag_name)
    Url := Data.HasOwnProp("html_url") ? Trim(String(Data.html_url)) : ""
    if Url = ""
        Url := "https://github.com/" App.GitHubRepo "/releases/latest"
    return { version: Tag, url: Url }
}

NormalizeVersion(Value) {
    Text := Trim(String(Value), " `t`r`n")
    Text := RegExReplace(Text, "^\x{FEFF}")  ; BOM
    Text := RegExReplace(Text, "^[vV]")
    if RegExMatch(Text, "^(?<ver>\d+(?:\.\d+)*)", &Match)
        return Match["ver"]
    return Text
}

CompareVersions(A, B) {
    A := NormalizeVersion(A)
    B := NormalizeVersion(B)
    if A = B
        return 0
    AParts := StrSplit(A, ".")
    BParts := StrSplit(B, ".")
    MaxLen := Max(AParts.Length, BParts.Length)
    loop MaxLen {
        Av := VersionPart(AParts, A_Index)
        Bv := VersionPart(BParts, A_Index)
        if Av < Bv
            return -1
        if Av > Bv
            return 1
    }
    return 0
}

VersionPart(Parts, Index) {
    if Index < 1 || Index > Parts.Length
        return 0
    Part := Parts[Index]
    if !IsInteger(Part)
        return 0
    return Integer(Part)
}

UpdateStatePath() {
    Dir := A_AppData "\Spotify Volume"
    if !DirExist(Dir)
        DirCreate(Dir)
    return Dir "\updates.ini"
}

ReadLastSeenRelease() {
    try
        return NormalizeVersion(IniRead(UpdateStatePath(), "Updates", "LastSeenRelease", ""))
    catch
        return ""
}

WriteLastSeenRelease(Version) {
    try IniWrite(NormalizeVersion(Version), UpdateStatePath(), "Updates", "LastSeenRelease")
}

ReadAppVersion() {
    try {
        Version := NormalizeVersion(FileRead(A_ScriptDir "\VERSION"))
        if Version != ""
            return Version
    }
    return "0.0.0"
}

; =============================================================================
; 9. Utilities
; =============================================================================

Defer(Callback) {
    SetTimer(Callback, -1)
}

FriendlyError(err) {
    ; Error.Message / .Extra are inherited — do not use HasOwnProp
    try Extra := err.Extra
    catch
        Extra := ""
    try Msg := err.Message
    catch
        Msg := ""

    if Extra = 429 || InStr(Msg, "rate", false)
        return "Spotify: rate limited"
    if Extra = "offline" || InStr(Msg, "internet", false) || InStr(Msg, "WinHttp", false)
        return "Spotify: offline"
    if Extra = "no_device" || InStr(Msg, "NO_ACTIVE_DEVICE") || InStr(Msg, "No active device")
        return "Spotify: no active device"
    if InStr(Msg, "PREMIUM_REQUIRED")
        return "Spotify: Premium required"
    if Extra = 401 || InStr(Msg, "token", false) || InStr(Msg, "authoriz", false)
        return "Spotify: re-authorize needed"
    return "Spotify: unavailable"
}

ConfigKey(Name, Default := "") {
    return %Name% ?? Default
}

ConfigBool(Name, Default) {
    return !!(%Name% ?? Default)
}

ConfigLower(Name, Default) {
    return StrLower(Trim(String(%Name% ?? Default)))
}

ConfigInt(Name, Default, MinVal := unset, MaxVal := unset) {
    Value := ToNumber(%Name% ?? Default, Default)
    if IsSet(MinVal) && IsSet(MaxVal)
        return Clamp(Value, MinVal, MaxVal)
    if IsSet(MinVal)
        return Max(Value, MinVal)
    if IsSet(MaxVal)
        return Min(Value, MaxVal)
    return Value
}

NormalizeNowPlayingTip() {
    Value := StrLower(Trim(String(NowPlayingTipOn ?? "")))
    if Value = "" {
        if IsSet(ShowNowPlayingTip)
            return ShowNowPlayingTip ? "playback" : "off"
        return "volume"
    }
    if Value = "true" || Value = "1" || Value = "on"
        return "both"
    if Value = "false" || Value = "0" || Value = "none" || Value = "no"
        return "off"
    return Value
}

ToNumber(Value, Fallback) {
    try {
        if IsNumber(Value)
            return Value + 0
        return Integer(Value)
    } catch
        return Fallback
}

ScriptError(err, mode) {
    global spoofy
    if !IsSet(spoofy)
        return false
    try Tip.Show(FriendlyError(err))
    return true
}
