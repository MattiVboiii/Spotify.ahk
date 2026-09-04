# Spotify.ahk (fork)

An [AutoHotkey](https://www.autohotkey.com/) v1 wrapper for the [Spotify Web API](https://developer.spotify.com/documentation/web-api), focused on controlling Spotify’s volume and playback.

This is a maintained fork of [CloakerSmoker/Spotify.ahk](https://github.com/CloakerSmoker/Spotify.ahk) with reliability fixes and simpler hotkey setup.

> **Premium required** for playback control. Spotify’s Connect Web API only controls Premium users’ playback.

## Quick start

1. Install [AutoHotkey v1.1](https://www.autohotkey.com/) (not v2).
2. Clone or download this repo.
3. Edit **`Config.ahk`** — set your keys and volume step.
4. Run **`Example Hotkeys.ahk`**.
5. On first launch, authorize in the browser tab that opens. Tokens are stored in Windows Credential Manager afterward.

### Config example

```ahk
VolumeDownKey      := "F13"
VolumeUpKey        := "F14"
VolumeIncrement    := 2
ShowVolumeTip      := true

PlayPauseKey       := "Media_Play_Pause"
NextTrackKey       := "Media_Next"
PreviousTrackKey   := "Media_Prev"
```

Leave a key as `""` to disable it. Any AutoHotkey [hotkey syntax](https://www.autohotkey.com/docs/v1/Hotkeys.htm) works (modifiers, media keys, mouse buttons, etc.).

## What’s improved in this fork

- Safer handling when nothing is playing (empty / 204 responses)
- Debounced volume control with cache resync
- Configurable hotkeys via `Config.ahk` (no script editing required for keys)
- Fixes: playlist delete URL, create-playlist auth/debug popup, recently-played mapping, export artists typo

## Library usage

```ahk
#Include %A_ScriptDir%\Spotify.ahk
spoofy := new Spotify

spoofy.Player.SetVolume(50)
spoofy.Player.NextTrack()
spoofy.Player.PlayPause()
```

More examples: `Example Hotkeys.ahk`, `ExportSpotifyPlaylist.ahk`  
Upstream docs (incomplete): https://cloakersmoker.github.io/Spotify.ahk/index.html

## Auth note (existing users)

Spotify deprecated Implicit Grant. This project uses PKCE. If you used an older build, re-authorize once when prompted.

## Credits

- Original library: [CloakerSmoker/Spotify.ahk](https://github.com/CloakerSmoker/Spotify.ahk)
- [AHKhttp](https://github.com/zhamlin/AHKhttp) (zhamlin), [AHKsock](https://github.com/jleb/AHKsock) (jleb), [Crypt](https://autohotkey.com/board/topic/67155-ahk-l-crypt-ahk-cryptography-class-encryption-hashing/) (Deo)

## License

GPL-3.0 (same as upstream)
