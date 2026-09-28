# Spotify Volume (fork of Spotify.ahk)

AutoHotkey **v2** script for **Spotify’s own volume** (not Windows volume), plus optional playback hotkeys.

Fork of [CloakerSmoker/Spotify.ahk](https://github.com/CloakerSmoker/Spotify.ahk).

> **Premium required.** Spotify’s Connect API only controls Premium accounts.

## Quick start

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone or download this repo.
3. Copy **`Config.example.ahk`** → **`Config.ahk`** (or run the script once — it creates that file for you).
4. Edit **`Config.ahk`** — set your volume keys and anything else you want.
5. Run **`Spotify Volume.ahk`**.
6. Authorize in the browser the first time (tokens are stored in Windows Credential Manager).

Tray icon: **Reload** · **Open Config…** · **Re-authorize…** · **Check for Updates…** · **Add/Remove Startup** · **Exit**

## What’s different from the original

The upstream project is a general Spotify Web API library. This fork is a ready-to-run volume/playback hotkey app on top of a trimmed copy of that library:

- **`Spotify Volume.ahk`** — volume (and optional media) hotkeys out of the box
- **`Config.ahk`** — all keys and options in one file (`Config.example.ahk` is the template; your `Config.ahk` is personal and gitignored)
- Optional **mute, seek, shuffle, repeat, like/unlike**
- On-screen tip for volume and/or the current track
- Can **wake Spotify / pick a Connect device** if nothing is active
- Optional **admin / UI Access** mode so hotkeys still work over fullscreen games
- Tray helpers: reload, edit config, Windows startup shortcut, re-authorize
- Optional **update check** against [GitHub Releases](https://github.com/MattiVboiii/Spotify.ahk/releases) (prompts once per new version)
- **AutoHotkey v2 only** — library kept to playback + volume (no playlist APIs)

## Config

Sections in `Config.ahk` match the comments in the file:

| #   | Section  | Examples                                                    |
| --- | -------- | ----------------------------------------------------------- |
| 1   | Volume   | keys, step size, scroll smoothing                           |
| 2   | Playback | play/pause, next/prev, shuffle, repeat, like                |
| 3   | Seek     | skip forward/back by N seconds                              |
| 4   | Tip      | where the on-screen tip appears, show track name or not     |
| 5   | Device   | auto-connect / launch Spotify when idle                     |
| 6   | Games    | `ElevateMode` for fullscreen                                |
| 7   | Auth     | optional own Spotify app client id                          |
| 8   | Updates  | `CheckForUpdates` — prompt once when a newer release exists |

```ahk
; Volume
VolumeDownKey := "F13"
VolumeUpKey   := "F14"
MuteKey       := "F15"
VolumeIncrement := 2

; Playback (leave "" to disable)
PlayPauseKey     := "Media_Play_Pause"
NextTrackKey     := "Media_Next"
PreviousTrackKey := "Media_Prev"
ShuffleKey := "^s"
RepeatKey  := "^r"
SaveTrackKey := "^l"

; Seek
SeekBackwardKey := "^Left"
SeekForwardKey  := "^Right"
SeekStepMs := 10000   ; 10 seconds

; Tip
TipPosition     := "bottom"   ; bottom | top | center
NowPlayingTipOn := "volume"   ; volume | playback | both | off

AutoActivateDevice := true
ElevateMode := ""             ; "" | "uia" | "admin"
; SpotifyClientId := ""

CheckForUpdates := true       ; false to disable
```

Modifiers: `^` Ctrl · `!` Alt · `+` Shift · `#` Win.  
Full key list: [AutoHotkey v2 hotkeys](https://www.autohotkey.com/docs/v2/Hotkeys.htm).

Mouse-wheel volume keys (e.g. `!WheelDown`) speed up while you scroll quickly.

### Fullscreen games

If hotkeys don’t work over a game:

```ahk
ElevateMode := "uia"     ; needs AutoHotkey installed under Program Files
; ElevateMode := "admin" ; shows a UAC prompt on start
```

Borderless / windowed mode is usually more reliable than exclusive fullscreen.

### Updates

Version lives in the root **`VERSION`** file (bump that when tagging a release).

On startup (a few seconds after launch), the script checks the latest [GitHub release](https://github.com/MattiVboiii/Spotify.ahk/releases). If a newer version exists, it prompts once for that version (Yes opens the release page). Set `CheckForUpdates := false` to turn this off, or use the tray **Check for Updates…** item anytime.

## Autostart

Tray → **Add to Startup**, or: `Win+R` → `shell:startup` → shortcut to `Spotify Volume.ahk`.

## Using the library alone

```ahk
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\Spotify.ahk
spoofy := Spotify()

spoofy.Player.SetVolume(50)
spoofy.Player.PlayPause()
spoofy.Player.PreviousTrack()
spoofy.Player.SeekTo(30000)
spoofy.Player.ToggleSaveCurrentlyPlaying()
```

## Auth

Uses PKCE. To force a new login: tray **Re-authorize…**, or delete the `Spotify.ahk` entry in Windows Credential Manager.

To use your own Spotify app: set `SpotifyClientId` and add `http://127.0.0.1:8000/callback` as a redirect URI in the [Dashboard](https://developer.spotify.com/dashboard).

## Credits

- [CloakerSmoker/Spotify.ahk](https://github.com/CloakerSmoker/Spotify.ahk)
- [JSON.ahk](https://github.com/thqby/ahk2_lib) (thqby / HotKeyIt)

## License

GPL-3.0 (same as upstream)
