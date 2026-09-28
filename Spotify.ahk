#Requires AutoHotkey v2.0
#MaxThreads 4

; =============================================================================
; Spotify Web API (playback + volume only) — PKCE auth
; =============================================================================
; Usage:
;   spoofy := Spotify()
;   spoofy.Player.SetVolume(50)
;   spoofy.Player.PlayPause()
; =============================================================================

class Spotify {
	static SHOULD_CHECK_CONNECTION_BEFORE_REQUEST := false

	__New() {
		this.Util := Spotify.Util(this)
		this.Player := Spotify.Player(this)
		this.CurrentUser := Spotify.User({}, this)
		try {
			Me := this.Util.CustomCall("GET", "me")
			if Me
				this.CurrentUser := Spotify.User(JSON.Load(Me), this)
		}
	}


	; -------------------------------------------------------------------------
	; HTTP + retries
	; -------------------------------------------------------------------------
	class Util {
		static MAX_RETRY := 3

		__New(Parent) {
			this.Parent := Parent
			this.PKCE := Spotify.PKCE()
			if !this.PKCE.HasSavedTokens() {
				try Legacy := RegRead("HKCU\Software\SpotifyAHK", "refreshToken")
				catch
					Legacy := ""
				if Legacy
					MsgBox("Spotify.ahk: Old install detected — please re-authorize to migrate to PKCE.")
			}
		}

		IsInternetConnected(Url := "http://api.spotify.com/v1/") {
			return DllCall("Wininet.dll\InternetCheckConnection", "Str", Url, "UInt", 1, "UInt", 0)
		}

		CustomCall(Method, Url, Body := "", NoErr := false) {
			if Spotify.SHOULD_CHECK_CONNECTION_BEFORE_REQUEST && !this.IsInternetConnected()
				throw Error("No internet connection", -1, "offline")

			if !(InStr(Url, "https://api.spotify.com") || InStr(Url, "https://accounts.spotify.com/api/"))
				Url := "https://api.spotify.com/v1/" Url

			LastError := "", LastStatus := 0
			Loop Spotify.Util.MAX_RETRY {
				try {
					Req := ComObject("WinHttp.WinHttpRequest.5.1")
					Req.Open(Method, Url, false)
					this.PKCE.AuthenticateRequest(Req)
					if Body != ""
						Req.SetRequestHeader("Content-Type", "application/json")
					Req.Send(Body)
					Status := Req.Status
					LastStatus := Status
				} catch as err {
					LastError := err.Message
					if A_Index < Spotify.Util.MAX_RETRY {
						Sleep(200 * A_Index)
						continue
					}
					throw Error(err.Message, -1, "offline")
				}

				if Status = 401 && A_Index < Spotify.Util.MAX_RETRY {
					try this.PKCE.RequestAccessFromRefreshToken()
					catch {
						this.PKCE.Authorized := false
						this.PKCE.ClearSavedTokens()
						this.PKCE.RequestUserAuthorization()
					}
					continue
				}

				if Status = 429 && A_Index < Spotify.Util.MAX_RETRY {
					try RetryAfter := Integer(Req.GetResponseHeader("Retry-After"))
					catch
						RetryAfter := 1
					Sleep(Clamp(RetryAfter, 1, 10) * 1000)
					continue
				}

				if (Status = 500 || Status = 502 || Status = 503 || Status = 504) && A_Index < Spotify.Util.MAX_RETRY {
					Sleep(300 * A_Index)
					continue
				}

				if Status > 299 && !NoErr
					throw Error(FormatHttpError(Req, Method, Url), -1, Status)

				return Req.ResponseText
			}

			Extra := LastStatus = 429 ? 429 : (LastStatus > 0 ? LastStatus : "offline")
			throw Error(LastError != "" ? LastError : "Spotify.ahk: Request failed after retries", -1, Extra)
		}
	}


	; -------------------------------------------------------------------------
	; Player endpoints
	; -------------------------------------------------------------------------
	class Player {
		__New(Parent) {
			this.Parent := Parent
		}

		Call(Method, Path, Body := "") {
			return this.Parent.Util.CustomCall(Method, Path, Body)
		}

		; true = saved, false = unsaved, "" = nothing playing
		ToggleSaveCurrentlyPlaying() {
			Info := this.GetCurrentPlaybackInfo()
			if !Info || !IsObject(Info.Track) || !Info.Track.id
				return ""
			if Info.Track.IsSaved {
				Info.Track.UnSave()
				return false
			}
			Info.Track.Save()
			return true
		}

		SetVolume(Percent) {
			try Percent := Integer(Percent)
			catch
				Percent := 0
			return this.Call("PUT", "me/player/volume?volume_percent=" Clamp(Percent, 0, 100))
		}

		GetCurrentPlaybackInfo() {
			Resp := ParseJsonObject(this.Call("GET", "me/player"))
			if !Resp
				return false
			Resp.Track := Spotify.Track(Resp.HasOwnProp("item") ? Resp.item : "", this.Parent)
			Resp.Device := Spotify.Device(Resp.HasOwnProp("device") ? Resp.device : "", this.Parent)
			if !Resp.HasOwnProp("progress_ms")
				Resp.progress_ms := 0
			return Resp
		}

		GetDevices() {
			Resp := ParseJsonObject(this.Call("GET", "me/player/devices"))
			if !Resp || !Resp.HasOwnProp("devices") || !IsObject(Resp.devices)
				return []
			return Resp.devices
		}

		TransferPlayback(DeviceId, Play := true) {
			if DeviceId = ""
				throw Error("Spotify.ahk: Missing device id", -1, "no_device")
			Body := '{"device_ids":["' DeviceId '"],"play":' (Play ? "true" : "false") "}"
			return this.Call("PUT", "me/player", Body)
		}

		SeekTo(PositionMs) {
			try PositionMs := Integer(PositionMs)
			catch
				PositionMs := 0
			return this.Call("PUT", "me/player/seek?position_ms=" Max(PositionMs, 0))
		}

		SetRepeatMode(Mode) {
			State := Mode = 1 ? "track" : (Mode = 2 ? "context" : "off")
			return this.Call("PUT", "me/player/repeat?state=" State)
		}

		SetShuffle(Mode) {
			return this.Call("PUT", "me/player/shuffle?state=" (Mode ? "true" : "false"))
		}

		NextTrack() {
			return this.Call("POST", "me/player/next")
		}

		PreviousTrack() {
			return this.Call("POST", "me/player/previous")
		}

		PausePlayback() {
			return this.Call("PUT", "me/player/pause")
		}

		ResumePlayback() {
			return this.Call("PUT", "me/player/play")
		}

		PlayPause() {
			Info := this.GetCurrentPlaybackInfo()
			if !Info
				return false
			Playing := Info.HasOwnProp("is_playing") ? Info.is_playing : false
			return Playing ? this.PausePlayback() : this.ResumePlayback()
		}
	}


	; -------------------------------------------------------------------------
	; Models
	; -------------------------------------------------------------------------
	class Track {
		__New(Obj, Parent := "") {
			this.SpotifyObj := Parent
			this.id := "", this.name := "", this.artist := "", this.duration_ms := 0
			if !IsObject(Obj)
				return
			this.id := Obj.HasOwnProp("id") ? Obj.id : ""
			this.name := Obj.HasOwnProp("name") ? Obj.name : ""
			try this.duration_ms := Obj.HasOwnProp("duration_ms") ? Integer(Obj.duration_ms) : 0
			catch
				this.duration_ms := 0
			if Obj.HasOwnProp("artists") && IsObject(Obj.artists) && Obj.artists.Length >= 1 {
				First := Obj.artists[1]
				if IsObject(First) && First.HasOwnProp("name")
					this.artist := First.name
			}
		}

		IsSaved {
			get {
				if this.id = ""
					return false
				try
					return (this.SpotifyObj.Util.CustomCall("GET", "me/tracks/contains?ids=" this.id) ~= "true")
				catch
					return false
			}
		}

		Save() {
			return this.id = "" ? false : this.SpotifyObj.Util.CustomCall("PUT", "me/tracks?ids=" this.id)
		}

		UnSave() {
			return this.id = "" ? false : this.SpotifyObj.Util.CustomCall("DELETE", "me/tracks?ids=" this.id)
		}
	}

	class Device {
		__New(Obj, Parent := "") {
			this.SpotifyObj := Parent
			this.id := "", this.name := "", this.volume := ""
			if !IsObject(Obj)
				return
			this.id := Obj.HasOwnProp("id") ? Obj.id : ""
			this.name := Obj.HasOwnProp("name") ? Obj.name : ""
			this.volume := Obj.HasOwnProp("volume_percent") ? Obj.volume_percent : ""
		}
	}

	class User {
		__New(Obj, Parent := "") {
			this.SpotifyObj := Parent
			this.id := "", this.name := "", this.subscriptionLevel := ""
			if !IsObject(Obj)
				return
			this.id := Obj.HasOwnProp("id") ? Obj.id : ""
			this.name := Obj.HasOwnProp("display_name") ? Obj.display_name : ""
			this.subscriptionLevel := Obj.HasOwnProp("product") ? Obj.product : ""
		}
	}


	; -------------------------------------------------------------------------
	; PKCE auth + Credential Manager
	; -------------------------------------------------------------------------
	class PKCE {
		static CLIENT_ID := "9fe26296bb7b4330ac59339efd2742b0"
		static CREDENTIAL_NAME := "Spotify.ahk"
		static REDIRECT_URI := "http://127.0.0.1:8000/callback"
		static SCOPES := "user-modify-playback-state user-read-currently-playing "
			. "user-read-playback-state user-read-private "
			. "user-library-read user-library-modify"

		__New() {
			this.Crypto := Spotify.PKCE.Crypto()
			this.Authorized := false
			this.AccessToken := ""
			this.RefreshToken := ""
			this.AccessTokenExpiration := ""
		}

		GenerateCodeChallenge() {
			this.CodeVerifier := this.Crypto.GenerateRandomString(128)
			Buf := Buffer(StrPut(this.CodeVerifier, "UTF-8"))
			StrPut(this.CodeVerifier, Buf, "UTF-8")
			pHash := this.Crypto.SHA2_256(Buf.Ptr, StrPut(this.CodeVerifier, "UTF-8") - 1)
			Challenge := this.Crypto.Base64Encode(pHash, 32)
			this.Crypto.Free(pHash)
			this.CodeChallenge := StrReplace(StrReplace(StrReplace(Challenge, "=", ""), "+", "-"), "/", "_")
			return this.CodeChallenge
		}

		HasSavedTokens() {
			try
				return IsObject(Spotify.PKCE.CredentialStore.CredRead(Spotify.PKCE.CREDENTIAL_NAME))
			catch
				return false
		}

		ClearSavedTokens() {
			try Spotify.PKCE.CredentialStore.CredDelete(Spotify.PKCE.CREDENTIAL_NAME)
		}

		LoadSavedTokens() {
			Credential := Spotify.PKCE.CredentialStore.CredRead(Spotify.PKCE.CREDENTIAL_NAME)
			if !IsObject(Credential) || Credential.password = ""
				throw Error("Spotify.ahk: No saved tokens")
			try Tokens := JSON.Load(Credential.password)
			catch
				throw Error("Spotify.ahk: Corrupt saved tokens")
			if !IsObject(Tokens)
				|| !Tokens.HasOwnProp("AccessToken") || Tokens.AccessToken = ""
				|| !Tokens.HasOwnProp("RefreshToken") || Tokens.RefreshToken = ""
				|| !Tokens.HasOwnProp("AccessTokenExpiration") || Tokens.AccessTokenExpiration = ""
				throw Error("Spotify.ahk: Incomplete saved tokens")
			this.AccessToken := Tokens.AccessToken
			this.AccessTokenExpiration := Tokens.AccessTokenExpiration
			this.RefreshToken := Tokens.RefreshToken
		}

		SaveTokens() {
			Spotify.PKCE.CredentialStore.CredWrite(
				Spotify.PKCE.CREDENTIAL_NAME,
				A_UserName,
				JSON.Dump({
					AccessToken: this.AccessToken,
					AccessTokenExpiration: this.AccessTokenExpiration,
					RefreshToken: this.RefreshToken
				})
			)
		}

		SetAccessTokenExpiration(ExpiresInSeconds) {
			try Seconds := Integer(ExpiresInSeconds)
			catch
				Seconds := 3600
			if Seconds < 30
				Seconds := 30
			this.AccessTokenExpiration := DateAdd(A_Now, Seconds - 1, "Seconds")
		}

		IsAccessTokenExpired() {
			if this.AccessTokenExpiration = "" || this.AccessToken = ""
				return true
			try
				return A_Now > this.AccessTokenExpiration
			catch
				return true
		}

		RequestTokens(ErrorMessage, Parameters) {
			Body := "client_id=" Spotify.PKCE.CLIENT_ID "&"
			for Key, Value in Parameters.OwnProps()
				Body .= Key "=" Value "&"
			Body := SubStr(Body, 1, -1)

			Req := ComObject("WinHttp.WinHttpRequest.5.1")
			Req.Open("POST", "https://accounts.spotify.com/api/token", false)
			Req.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded")
			Req.Send(Body)

			if Req.Status != 200
				throw Error("Spotify.ahk: " ErrorMessage ": status " Req.Status ", response: " Req.ResponseText)

			Response := JSON.Load(Req.ResponseText)
			if !IsObject(Response) || !Response.HasOwnProp("access_token") || Response.access_token = ""
				throw Error("Spotify.ahk: " ErrorMessage ": missing access_token")

			this.AccessToken := Response.access_token
			this.SetAccessTokenExpiration(Response.HasOwnProp("expires_in") ? Response.expires_in : 3600)
			if Response.HasOwnProp("refresh_token") && Response.refresh_token
				this.RefreshToken := Response.refresh_token
			if this.RefreshToken = ""
				throw Error("Spotify.ahk: " ErrorMessage ": missing refresh_token")

			try this.SaveTokens()
			this.Authorized := true
		}

		RequestUserAuthorization() {
			this.GenerateCodeChallenge()
			AuthUrl := "https://accounts.spotify.com/en/authorize"
				. "?client_id=" Spotify.PKCE.CLIENT_ID
				. "&response_type=code"
				. "&code_challenge_method=S256"
				. "&code_challenge=" this.CodeChallenge
				. "&redirect_uri=" UriEncode(Spotify.PKCE.REDIRECT_URI)
				. "&scope=" UriEncode(Spotify.PKCE.SCOPES)
			this.AuthorizationCode := OAuthCallback.WaitForCode(8000, 5 * 60 * 1000, () => Run(AuthUrl))
			this.RequestTokens("Could not complete initial web authorization", {
				grant_type: "authorization_code",
				code: this.AuthorizationCode,
				code_verifier: this.CodeVerifier,
				redirect_uri: UriEncode(Spotify.PKCE.REDIRECT_URI)
			})
		}

		RequestAccessFromRefreshToken() {
			if this.RefreshToken = ""
				throw Error("Spotify.ahk: No refresh token")
			this.RequestTokens("Failed to refresh access token", {
				grant_type: "refresh_token",
				refresh_token: this.RefreshToken
			})
		}

		AuthenticateRequest(Request) {
			if !this.Authorized {
				Loaded := false
				if this.HasSavedTokens() {
					try {
						this.LoadSavedTokens()
						this.Authorized := true
						Loaded := true
					} catch {
						this.ClearSavedTokens()
					}
				}
				if !Loaded
					this.RequestUserAuthorization()
			}

			try {
				if this.IsAccessTokenExpired()
					this.RequestAccessFromRefreshToken()
			} catch {
				this.Authorized := false
				this.ClearSavedTokens()
				MsgBox("Spotify.ahk: Re-authorization needed. Opening browser…")
				this.RequestUserAuthorization()
			}

			if this.AccessToken = ""
				throw Error("Spotify.ahk: Missing access token after authentication")
			Request.SetRequestHeader("Authorization", "Bearer " this.AccessToken)
		}

		class Crypto {
			static BCRYPT_RNG_ALG_HANDLE := 0x00000081
			static BCRYPT_SHA256_ALG_HANDLE := 0x00000041
			static CRYPT_STRING_BASE64 := 0x1
			static CRYPT_STRING_NOCRLF := 0x40000000
			static hHeap := DllCall("kernel32.dll\GetProcessHeap", "Ptr")

			Allocate(Size) {
				return DllCall("kernel32.dll\HeapAlloc", "Ptr", Spotify.PKCE.Crypto.hHeap, "UInt", 0, "Ptr", Size, "Ptr")
			}

			Free(Ptr) {
				DllCall("kernel32.dll\HeapFree", "Ptr", Spotify.PKCE.Crypto.hHeap, "UInt", 0, "Ptr", Ptr)
			}

			GenerateRandomString(Length) {
				Buf := Buffer(Length, 0)
				DllCall("bcrypt.dll\BCryptGenRandom", "Ptr", Spotify.PKCE.Crypto.BCRYPT_RNG_ALG_HANDLE, "Ptr", Buf, "UInt", Length, "UInt", 0)
				Result := "", Alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
				Loop Length
					Result .= SubStr(Alphabet, Mod(NumGet(Buf, A_Index - 1, "UChar"), 62) + 1, 1)
				return Result
			}

			SHA2_256(pInput, InputSize) {
				hHash := 0
				DllCall("bcrypt.dll\BCryptCreateHash", "Ptr", Spotify.PKCE.Crypto.BCRYPT_SHA256_ALG_HANDLE, "Ptr*", &hHash, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 0)
				DllCall("bcrypt.dll\BCryptHashData", "Ptr", hHash, "Ptr", pInput, "UInt", InputSize, "UInt", 0)
				pResult := this.Allocate(32)
				DllCall("bcrypt.dll\BCryptFinishHash", "Ptr", hHash, "Ptr", pResult, "UInt", 32, "UInt", 0)
				DllCall("bcrypt.dll\BCryptDestroyHash", "Ptr", hHash)
				return pResult
			}

			Base64Encode(pInput, InputSize) {
				Flags := Spotify.PKCE.Crypto.CRYPT_STRING_BASE64 | Spotify.PKCE.Crypto.CRYPT_STRING_NOCRLF
				ResultSize := 0
				DllCall("crypt32.dll\CryptBinaryToStringW", "Ptr", pInput, "UInt", InputSize, "UInt", Flags, "Ptr", 0, "UInt*", &ResultSize)
				ResultBuffer := Buffer(ResultSize * 2, 0)
				DllCall("crypt32.dll\CryptBinaryToStringW", "Ptr", pInput, "UInt", InputSize, "UInt", Flags, "Ptr", ResultBuffer, "UInt*", &ResultSize)
				return StrGet(ResultBuffer, "UTF-16")
			}
		}

		; Credential Manager helpers (0BSD — Copyright (c) 2023 Philip Taylor)
		class CredentialStore {
			static CredWrite(Name, Username, Password) {
				NameBuf := Buffer(StrPut(Name, "UTF-16")), StrPut(Name, NameBuf, "UTF-16")
				UserBuf := Buffer(StrPut(Username, "UTF-16")), StrPut(Username, UserBuf, "UTF-16")
				cbPassword := StrLen(Password) * 2
				PassBuf := Buffer(cbPassword + 2, 0), StrPut(Password, PassBuf, "UTF-16")

				Cred := Buffer(24 + A_PtrSize * 7, 0)
				NumPut("UInt", 1, Cred, 4)                           ; CRED_TYPE_GENERIC
				NumPut("Ptr", NameBuf.Ptr, Cred, 8)
				NumPut("UInt", cbPassword, Cred, 16 + A_PtrSize * 2)
				NumPut("Ptr", PassBuf.Ptr, Cred, 16 + A_PtrSize * 3)
				NumPut("UInt", 3, Cred, 16 + A_PtrSize * 4)          ; CRED_PERSIST_ENTERPRISE
				NumPut("Ptr", UserBuf.Ptr, Cred, 24 + A_PtrSize * 6)
				return DllCall("Advapi32.dll\CredWriteW", "Ptr", Cred, "UInt", 0, "Int")
			}

			static CredDelete(Name) {
				return DllCall("Advapi32.dll\CredDeleteW", "WStr", Name, "UInt", 1, "UInt", 0, "Int")
			}

			static CredRead(Name) {
				pCred := 0
				DllCall("Advapi32.dll\CredReadW", "Str", Name, "UInt", 1, "UInt", 0, "Ptr*", &pCred, "Int")
				if !pCred
					return false
				NameOut := StrGet(NumGet(pCred, 8, "Ptr"), "UTF-16")
				Username := StrGet(NumGet(pCred, 24 + A_PtrSize * 6, "Ptr"), "UTF-16")
				Len := NumGet(pCred, 16 + A_PtrSize * 2, "UInt")
				Password := StrGet(NumGet(pCred, 16 + A_PtrSize * 3, "Ptr"), Len / 2, "UTF-16")
				DllCall("Advapi32.dll\CredFree", "Ptr", pCred)
				return { name: NameOut, username: Username, password: Password }
			}
		}
	}
}


; =============================================================================
; Shared helpers
; =============================================================================

ParseJsonObject(Text) {
	if !Text
		return false
	try Parsed := JSON.Load(Text)
	catch
		return false
	return IsObject(Parsed) ? Parsed : false
}

UriEncode(Str) {
	Out := "", Buf := Buffer(StrPut(Str, "UTF-8"))
	StrPut(Str, Buf, "UTF-8")
	Loop Buf.Size - 1 {
		B := NumGet(Buf, A_Index - 1, "UChar"), Ch := Chr(B)
		if (B >= 0x41 && B <= 0x5A) || (B >= 0x61 && B <= 0x7A) || (B >= 0x30 && B <= 0x39) || InStr("-_.~", Ch)
			Out .= Ch
		else
			Out .= Format("%{:02X}", B)
	}
	return Out
}

Clamp(Value, MinVal, MaxVal) {
	if Value < MinVal
		return MinVal
	if Value > MaxVal
		return MaxVal
	return Value
}

FormatHttpError(Req, Method, Url) {
	try {
		Parsed := JSON.Load(Req.ResponseText)
		if IsObject(Parsed) && Parsed.HasOwnProp("error") {
			Err := Parsed.error, Msg := ""
			if Err.HasOwnProp("reason") && Err.reason
				Msg .= Err.reason ": "
			if Err.HasOwnProp("message")
				Msg .= Err.message
			if Msg
				return Msg
		}
	}
	try
		return Req.Status ' not 2xx for request "' Method ":" Url '".'
	catch
		return "Spotify.ahk: HTTP request failed"
}

#Include %A_ScriptDir%\lib\JSON.ahk
#Include %A_ScriptDir%\lib\OAuthCallback.ahk
