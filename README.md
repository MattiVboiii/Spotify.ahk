# Spotify.ahk

Disclaimer: Some features of Spotify.ahk will not work for non-premium users, this is not a limition of Spotify.ahk, but a limit in Spotify's Connect Web API as stated in its documentation.
```
Note:
  With Connect Web API you can only control Spotify Premium users’ playback.
``` 

## REQUIRED UPDATE FOR EXISTING USERS

Before 2025-10-17, Spotify.ahk used Spotify's "Implicit grant" authorization flow, which was deprecated by Spotify in February 2025, and will be (or already has been) disabled by them on November 27th of 2025.

As of 2025-10-17, Spotify.ahk *has* been updated to a modern authorization flow, and should be November 27th-proof (and should also actually be more secure. thanks Spotify). However, this change comes with effectively 0 testing (I don't run Windows or AutoHotkey anymore), so mileage will vary.

Anyways, if you're running this code and get some wacky crazy error message: Updating *should* fix it. You'll have to do the web authorization again, but then things should be fine.

### README

An AutoHotkey wrapper for the Spotify web API designed to allow control over Spotify's internal volume slider and provide various other functionality.

Uses a slightly modified version of the [AHKhttp library by zhamlin](https://github.com/zhamlin/AHKhttp), the [AHKsock library by jleb](https://github.com/jleb/AHKsock) and the [Crypt library by Deo](https://autohotkey.com/board/topic/67155-ahk-l-crypt-ahk-cryptography-class-encryption-hashing/)

### Documentation can now be found [here](https://cloakersmoker.github.io/Spotify.ahk/index.html), however it is not complete.

#### How to use
Create a new Spotify object, and call methods from the various nested classes. Examples can been seen in the Example Hotkeys file and throughout the documentation.

When you create a new Spotify object for the first time, a Spotify app authorization page will open in your default browser, and you will be prompted to authorize `Spotify.ahk`.
While you can choose not to authorize Spotify.ahk, all functionality will be lost without valid authorization. 

You will only rarely need to do web authorization thanks to Spotify's refreshable user authorization.
