#Requires AutoHotkey v2.0
#MaxThreads 4

class Spotify {
	static SHOULD_CHECK_CONNECTION_BEFORE_REQUEST := false

	__New() {
		this.Util := Util(this)
		this.Player := Player(this)
		this.CurrentUser := user({}, this)
		try {
			me := this.Util.CustomCall("GET", "me")
			if me
				this.CurrentUser := user(JSON.Load(me), this)
		}
	}

	class PKCE {
		static CLIENT_ID := "9fe26296bb7b4330ac59339efd2742b0"
		static CREDENTIAL_NAME := "Spotify.ahk"
		static REDIRECT_URI := "http://127.0.0.1:8000/callback"
		static SCOPES := "user-modify-playback-state user-read-currently-playing "
			. "user-read-playback-state user-read-private "
			. "user-library-read user-library-modify"

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
				buf := Buffer(Length, 0)
				DllCall("bcrypt.dll\BCryptGenRandom", "Ptr", Spotify.PKCE.Crypto.BCRYPT_RNG_ALG_HANDLE, "Ptr", buf, "UInt", Length, "UInt", 0)

				Result := ""
				Alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
				Loop Length {
					Value := NumGet(buf, A_Index - 1, "UChar")
					Result .= SubStr(Alphabet, Mod(Value, 62) + 1, 1)
				}
				return Result
			}

			SHA2_256(pInput, InputSize) {
				hHash := 0
				DllCall("bcrypt.dll\BCryptCreateHash"
					, "Ptr", Spotify.PKCE.Crypto.BCRYPT_SHA256_ALG_HANDLE
					, "Ptr*", &hHash
					, "Ptr", 0, "Ptr", 0
					, "Ptr", 0, "Ptr", 0, "UInt", 0)

				DllCall("bcrypt.dll\BCryptHashData"
					, "Ptr", hHash
					, "Ptr", pInput
					, "UInt", InputSize
					, "UInt", 0)

				pResult := this.Allocate(32)
				DllCall("bcrypt.dll\BCryptFinishHash"
					, "Ptr", hHash
					, "Ptr", pResult
					, "UInt", 32
					, "UInt", 0)

				DllCall("bcrypt.dll\BCryptDestroyHash", "Ptr", hHash)
				return pResult
			}

			Base64Encode(pInput, InputSize) {
				Flags := Spotify.PKCE.Crypto.CRYPT_STRING_BASE64 | Spotify.PKCE.Crypto.CRYPT_STRING_NOCRLF
				ResultSize := 0
				DllCall("crypt32.dll\CryptBinaryToStringW"
					, "Ptr", pInput
					, "UInt", InputSize
					, "UInt", Flags
					, "Ptr", 0
					, "UInt*", &ResultSize)

				ResultBuffer := Buffer(ResultSize * 2, 0)
				DllCall("crypt32.dll\CryptBinaryToStringW"
					, "Ptr", pInput
					, "UInt", InputSize
					, "UInt", Flags
					, "Ptr", ResultBuffer
					, "UInt*", &ResultSize)

				return StrGet(ResultBuffer, "UTF-16")
			}
		}

		; Credential Manager helpers (0BSD — Copyright (c) 2023 Philip Taylor)
		class CredentialStore {
			static CredWrite(name, username, password) {
				nameBuf := Buffer(StrPut(name, "UTF-16"))
				StrPut(name, nameBuf, "UTF-16")
				userBuf := Buffer(StrPut(username, "UTF-16"))
				StrPut(username, userBuf, "UTF-16")

				cbPassword := StrLen(password) * 2
				passBuf := Buffer(cbPassword + 2, 0)
				StrPut(password, passBuf, "UTF-16")

				cred := Buffer(24 + A_PtrSize * 7, 0)
				NumPut("UInt", 1, cred, 4)                           ; Type = CRED_TYPE_GENERIC
				NumPut("Ptr", nameBuf.Ptr, cred, 8)                  ; TargetName
				NumPut("UInt", cbPassword, cred, 16 + A_PtrSize * 2) ; CredentialBlobSize
				NumPut("Ptr", passBuf.Ptr, cred, 16 + A_PtrSize * 3) ; CredentialBlob
				NumPut("UInt", 3, cred, 16 + A_PtrSize * 4)          ; Persist = CRED_PERSIST_ENTERPRISE
				NumPut("Ptr", userBuf.Ptr, cred, 24 + A_PtrSize * 6) ; UserName

				return DllCall("Advapi32.dll\CredWriteW", "Ptr", cred, "UInt", 0, "Int")
			}

			static CredDelete(name) {
				return DllCall("Advapi32.dll\CredDeleteW", "WStr", name, "UInt", 1, "UInt", 0, "Int")
			}

			static CredRead(name) {
				pCred := 0
				DllCall("Advapi32.dll\CredReadW", "Str", name, "UInt", 1, "UInt", 0, "Ptr*", &pCred, "Int")
				if !pCred
					return false

				nameOut := StrGet(NumGet(pCred, 8, "Ptr"), "UTF-16")
				username := StrGet(NumGet(pCred, 24 + A_PtrSize * 6, "Ptr"), "UTF-16")
				len := NumGet(pCred, 16 + A_PtrSize * 2, "UInt")
				password := StrGet(NumGet(pCred, 16 + A_PtrSize * 3, "Ptr"), len / 2, "UTF-16")
				DllCall("Advapi32.dll\CredFree", "Ptr", pCred)
				return {name: nameOut, username: username, password: password}
			}
		}

		__New() {
			this.Crypto := Spotify.PKCE.Crypto()
			this.Authorized := false
			this.AccessToken := ""
			this.RefreshToken := ""
			this.AccessTokenExpiration := ""
		}

		GenerateCodeChallenge() {
			this.CodeVerifier := this.Crypto.GenerateRandomString(128)

			CodeVerifierBuffer := Buffer(StrPut(this.CodeVerifier, "UTF-8"))
			StrPut(this.CodeVerifier, CodeVerifierBuffer, "UTF-8")
			InputSize := StrPut(this.CodeVerifier, "UTF-8") - 1

			pHash := this.Crypto.SHA2_256(CodeVerifierBuffer.Ptr, InputSize)
			this.CodeChallenge := this.Crypto.Base64Encode(pHash, 32)
			this.CodeChallenge := StrReplace(StrReplace(StrReplace(this.CodeChallenge, "=", ""), "+", "-"), "/", "_")
			this.Crypto.Free(pHash)
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

			try
				Tokens := JSON.Load(Credential.password)
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
			Tokens := {
				AccessToken: this.AccessToken,
				AccessTokenExpiration: this.AccessTokenExpiration,
				RefreshToken: this.RefreshToken
			}
			Spotify.PKCE.CredentialStore.CredWrite(Spotify.PKCE.CREDENTIAL_NAME, A_UserName, JSON.Dump(Tokens))
		}

		SetAccessTokenExpiration(ExpiresInSeconds) {
			try
				Seconds := Integer(ExpiresInSeconds)
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
			BodyParameters := "client_id=" Spotify.PKCE.CLIENT_ID "&"
			for Key, Value in Parameters.OwnProps()
				BodyParameters .= Key "=" Value "&"
			BodyParameters := SubStr(BodyParameters, 1, -1)

			Request := ComObject("WinHttp.WinHttpRequest.5.1")
			Request.Open("POST", "https://accounts.spotify.com/api/token", false)
			Request.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded")
			Request.Send(BodyParameters)

			if Request.Status != 200
				throw Error("Spotify.ahk: " ErrorMessage ": status " Request.Status ", response: " Request.ResponseText)

			Response := JSON.Load(Request.ResponseText)
			if !IsObject(Response) || !Response.HasOwnProp("access_token") || Response.access_token = ""
				throw Error("Spotify.ahk: " ErrorMessage ": missing access_token")

			this.AccessToken := Response.access_token
			this.SetAccessTokenExpiration(Response.HasOwnProp("expires_in") ? Response.expires_in : 3600)

			if Response.HasOwnProp("refresh_token") && Response.refresh_token
				this.RefreshToken := Response.refresh_token

			; Initial auth must yield a refresh token; refresh responses may omit it
			if this.RefreshToken = ""
				throw Error("Spotify.ahk: " ErrorMessage ": missing refresh_token")

			try this.SaveTokens()
			this.Authorized := true
		}

		RequestUserAuthorization() {
			this.GenerateCodeChallenge()

			authUrl := "https://accounts.spotify.com/en/authorize"
				. "?client_id=" Spotify.PKCE.CLIENT_ID
				. "&response_type=code"
				. "&code_challenge_method=S256"
				. "&code_challenge=" this.CodeChallenge
				. "&redirect_uri=" UriEncode(Spotify.PKCE.REDIRECT_URI)
				. "&scope=" UriEncode(Spotify.PKCE.SCOPES)

			this.AuthorizationCode := OAuthCallback.WaitForCode(8000, 5 * 60 * 1000, () => Run(authUrl))

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
				loaded := false
				if this.HasSavedTokens() {
					try {
						this.LoadSavedTokens()
						this.Authorized := true
						loaded := true
					} catch {
						this.ClearSavedTokens()
					}
				}
				if !loaded
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
	}
}

class Util {
	static MAX_RETRY := 3

	__New(ParentObject) {
		this.ParentObject := ParentObject
		this.PKCE := Spotify.PKCE()

		if !this.PKCE.HasSavedTokens() {
			try LegacyRefreshToken := RegRead("HKCU\Software\SpotifyAHK", "refreshToken")
			catch
				LegacyRefreshToken := ""
			if LegacyRefreshToken
				MsgBox("Spotify.ahk: Old install detected — please re-authorize to migrate to PKCE.")
		}
	}

	IsInternetConnected(CheckURL := "http://api.spotify.com/v1/") {
		return DllCall("Wininet.dll\InternetCheckConnection", "Str", CheckURL, "UInt", 1, "UInt", 0)
	}

	CustomCall(method, url, body := "", noErr := false) {
		if Spotify.SHOULD_CHECK_CONNECTION_BEFORE_REQUEST && !this.IsInternetConnected()
			throw Error("No internet connection")

		if !(InStr(url, "https://api.spotify.com") || InStr(url, "https://accounts.spotify.com/api/"))
			url := "https://api.spotify.com/v1/" url

		LastError := ""
		Loop Util.MAX_RETRY {
			try {
				Req := ComObject("WinHttp.WinHttpRequest.5.1")
				Req.Open(method, url, false)
				this.PKCE.AuthenticateRequest(Req)
				Req.Send(body)
				Status := Req.Status
			} catch as err {
				LastError := err.Message
				if A_Index < Util.MAX_RETRY {
					Sleep(200 * A_Index)
					continue
				}
				throw err
			}

			if Status = 401 && A_Index < Util.MAX_RETRY {
				try this.PKCE.RequestAccessFromRefreshToken()
				catch {
					this.PKCE.Authorized := false
					this.PKCE.ClearSavedTokens()
					this.PKCE.RequestUserAuthorization()
				}
				continue
			}

			if Status = 429 && A_Index < Util.MAX_RETRY {
				RetryAfter := 1
				try RetryAfter := Integer(Req.GetResponseHeader("Retry-After"))
				catch
					RetryAfter := 1
				Sleep(Clamp(RetryAfter, 1, 10) * 1000)
				continue
			}

			; Transient server errors
			if (Status = 500 || Status = 502 || Status = 503 || Status = 504) && A_Index < Util.MAX_RETRY {
				Sleep(300 * A_Index)
				continue
			}

			if Status > 299 && !noErr
				throw Error(FormatHttpError(Req, method, url), -1, "HTTP response code not 2xx")

			return Req.ResponseText
		}

		throw Error(LastError != "" ? LastError : "Spotify.ahk: Request failed after retries")
	}
}

class Player {
	__New(ParentObject) {
		this.ParentObject := ParentObject
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

	SetVolume(volume) {
		try
			volume := Integer(volume)
		catch
			volume := 0
		volume := Clamp(volume, 0, 100)
		return this.ParentObject.Util.CustomCall("PUT", "me/player/volume?volume_percent=" volume)
	}

	GetCurrentPlaybackInfo() {
		try
			ResponseText := this.ParentObject.Util.CustomCall("GET", "me/player")
		catch
			return false

		if !ResponseText
			return false

		try
			Resp := JSON.Load(ResponseText)
		catch
			return false

		if !IsObject(Resp)
			return false

		Resp.Track := track(Resp.HasOwnProp("item") ? Resp.item : "", this.ParentObject)
		Resp.Device := device(Resp.HasOwnProp("device") ? Resp.device : "", this.ParentObject)
		return Resp
	}

	SetRepeatMode(mode) {
		State := (mode = 1 ? "track" : (mode = 2 ? "context" : "off"))
		return this.ParentObject.Util.CustomCall("PUT", "me/player/repeat?state=" State)
	}

	SetShuffle(mode) {
		return this.ParentObject.Util.CustomCall("PUT", "me/player/shuffle?state=" (mode ? "true" : "false"))
	}

	NextTrack() {
		return this.ParentObject.Util.CustomCall("POST", "me/player/next")
	}

	PreviousTrack() {
		return this.ParentObject.Util.CustomCall("POST", "me/player/previous")
	}

	PausePlayback() {
		return this.ParentObject.Util.CustomCall("PUT", "me/player/pause")
	}

	ResumePlayback() {
		return this.ParentObject.Util.CustomCall("PUT", "me/player/play")
	}

	PlayPause() {
		Info := this.GetCurrentPlaybackInfo()
		if !Info
			return false
		Playing := Info.HasOwnProp("is_playing") ? Info.is_playing : false
		return Playing ? this.PausePlayback() : this.ResumePlayback()
	}
}

class track {
	__New(ResponseTrackObj, Parent := "") {
		this.SpotifyObj := Parent
		this.id := ""
		this.name := ""
		if !IsObject(ResponseTrackObj)
			return
		this.id := ResponseTrackObj.HasOwnProp("id") ? ResponseTrackObj.id : ""
		this.name := ResponseTrackObj.HasOwnProp("name") ? ResponseTrackObj.name : ""
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
		if this.id = ""
			return false
		return this.SpotifyObj.Util.CustomCall("PUT", "me/tracks?ids=" this.id)
	}

	UnSave() {
		if this.id = ""
			return false
		return this.SpotifyObj.Util.CustomCall("DELETE", "me/tracks?ids=" this.id)
	}
}

class device {
	__New(Devicejson, Parent := "") {
		this.SpotifyObj := Parent
		this.id := ""
		this.name := ""
		this.volume := ""
		if !IsObject(Devicejson)
			return
		this.id := Devicejson.HasOwnProp("id") ? Devicejson.id : ""
		this.name := Devicejson.HasOwnProp("name") ? Devicejson.name : ""
		this.volume := Devicejson.HasOwnProp("volume_percent") ? Devicejson.volume_percent : ""
	}
}

class user {
	__New(Userjson, Parent := "") {
		this.SpotifyObj := Parent
		this.id := ""
		this.name := ""
		this.subscriptionLevel := ""
		if !IsObject(Userjson)
			return
		this.id := Userjson.HasOwnProp("id") ? Userjson.id : ""
		this.name := Userjson.HasOwnProp("display_name") ? Userjson.display_name : ""
		this.subscriptionLevel := Userjson.HasOwnProp("product") ? Userjson.product : ""
	}
}

UriEncode(str) {
	out := ""
	buf := Buffer(StrPut(str, "UTF-8"))
	StrPut(str, buf, "UTF-8")
	Loop buf.Size - 1 {
		b := NumGet(buf, A_Index - 1, "UChar")
		ch := Chr(b)
		if (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39) || InStr("-_.~", ch)
			out .= ch
		else
			out .= Format("%{:02X}", b)
	}
	return out
}

Clamp(Value, Min, Max) {
	if Value < Min
		return Min
	if Value > Max
		return Max
	return Value
}

FormatHttpError(Req, method, url) {
	try {
		parsed := JSON.Load(Req.ResponseText)
		if IsObject(parsed) && parsed.HasOwnProp("error") {
			err := parsed.error
			msg := ""
			if err.HasOwnProp("reason") && err.reason
				msg .= err.reason ": "
			if err.HasOwnProp("message")
				msg .= err.message
			if msg
				return msg
		}
	}
	try
		return Req.Status ' not 2xx for request "' method ":" url '".'
	catch
		return "Spotify.ahk: HTTP request failed"
}

#Include %A_ScriptDir%\lib\JSON.ahk
#Include %A_ScriptDir%\lib\OAuthCallback.ahk
