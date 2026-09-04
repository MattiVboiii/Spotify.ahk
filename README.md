# Spotify Volume (fork of Spotify.ahk)

AutoHotkey **v2** hotkeys for **Spotify’s own volume** (not Windows volume), with optional playback controls. Built on a trimmed [Spotify Web API](https://developer.spotify.com/documentation/web-api) wrapper.

Fork of [CloakerSmoker/Spotify.ahk](https://github.com/CloakerSmoker/Spotify.ahk) — reliability fixes, `Config.ahk` setup, AHK v2 only.

> **Premium required.** Spotify’s Connect Web API only controls Premium users’ playback.

## Quick start

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone or download this repo.
3. Edit **`Config.ahk`** — volume keys, step size, optional playback keys.
4. Run **`Spotify Volume.ahk`**.
5. On first launch, authorize in the browser. Tokens go to Windows Credential Manager.

Tray icon (system tray): **Reload**, **Re-authorize…**, **Exit**.

### Config example

```ahk
VolumeDownKey      := "F13"              ; or "^Down", "!WheelDown", …
VolumeUpKey        := "F14"
MuteKey            := "F15"
VolumeIncrement    := 2
ShowVolumeTip      := true

PlayPauseKey       := "Media_Play_Pause" ; or "" to disable
NextTrackKey       := "Media_Next"
PreviousTrackKey   := "Media_Prev"
ShuffleKey         := "^s"
RepeatKey          := "^r"
SaveTrackKey       := "^l"               ; like / unlike current track
```

Modifiers: `^` Ctrl · `!` Alt · `+` Shift · `#` Win. Leave a key as `""` to disable it. See [AutoHotkey v2 hotkeys](https://www.autohotkey.com/docs/v2/Hotkeys.htm).

## Autostart on Windows login (`shell:startup`)

So the script runs every time you sign in:

1. Make sure **`Spotify Volume.ahk`** works when you double-click it (AutoHotkey v2 installed, authorized once).
2. Press `Win + R`, type `shell:startup`, press Enter.  
   That opens your personal Startup folder, usually:  
   `%AppData%\Microsoft\Windows\Start Menu\Programs\Startup`
3. Create a **shortcut** to the script there (don’t move the whole repo):
   - Right-click `Spotify Volume.ahk` → **Show more options** (Windows 11) → **Create shortcut**, _or_ right-drag the file into the Startup folder and choose **Create shortcuts here**.
   - Move/copy that shortcut into the Startup folder if it isn’t there already.
4. Optional: rename the shortcut to something clear, e.g. `Spotify Volume`.
5. Sign out and back in (or reboot) to confirm it starts. You should see the AutoHotkey tray icon.

To stop autostart later, delete the shortcut from the Startup folder.

> Keep the repo folder where the shortcut points. If you move the project, update or recreate the shortcut.

## What’s in this fork

- Volume-first hotkeys with debounce + cache resync
- Optional mute, shuffle, repeat, and like/unlike
- Configurable keys in `Config.ahk`
- AutoHotkey v2 only
- Safe handling when nothing is playing / no active device
- Corrupt-token recovery and HTTP retries (401 / 429 / 5xx)
- Tray menu for reload and re-authorize
- No playlist/export features (playback + volume only)

## Library usage

```ahk
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\Spotify.ahk
spoofy := Spotify()

spoofy.Player.SetVolume(50)
spoofy.Player.PlayPause()
spoofy.Player.PreviousTrack()
spoofy.Player.ToggleSaveCurrentlyPlaying()
```

Focused on playback + volume (no playlist/library browsing APIs). Main script: `Spotify Volume.ahk`.

## Auth note

Uses PKCE. If you authorized an older build (or scopes changed), use the tray **Re-authorize…** item (or delete the `Spotify.ahk` credential in Windows Credential Manager).

## Credits

- Original library: [CloakerSmoker/Spotify.ahk](https://github.com/CloakerSmoker/Spotify.ahk)
- [JSON.ahk](https://github.com/thqby/ahk2_lib) (thqby / HotKeyIt)

## License

GPL-3.0 (same as upstream)
