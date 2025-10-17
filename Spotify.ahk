#MaxThreads 2
class Spotify {
	static SHOULD_CHECK_CONNECTION_BEFORE_REQUEST := false
	
	__New() {
		this.Util := new Util(this)
		this.Player := new Player(this)
		this.Library := new Library(this)
		this.Albums := new Albums(this)
		this.Artists := new Artists(this)
		this.Tracks := new Tracks(this)
		this.Playlists := new Playlists(this)
		this.CurrentUser := new user(JSON.load(this.Util.CustomCall("GET", "me")), this, true)
		this.Users := new Users(this)
	}

	class PKCE {
        class Crypto {
            static BCRYPT_RNG_ALG_HANDLE := 0x00000081
            static hHeap := DllCall("kernel32.dll\GetProcessHeap")

            Allocate(Size) {
                return DllCall("kernel32.dll\HeapAlloc", "Ptr", this.hHeap, "UInt", 0, "Ptr", Size, "Ptr")
            }

            Free(Ptr) {
                DllCall("kernel32.dll\HeapFree", "Ptr", this.hHeap, "UInt", 0, "Ptr", Ptr)
            }

            GenerateRandomString(Length) {
				local Buffer

                VarSetCapacity(Buffer, Length, 0)
                DllCall("bcrypt.dll\BCryptGenRandom", "Ptr", this.BCRYPT_RNG_ALG_HANDLE, "Ptr", &Buffer, "UInt", Length, "UInt", 0)

                Result := ""

                loop, % Length {
                    Value := NumGet(&Buffer + 0, A_Index - 1, "UChar")

                    Result .= SubStr("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", Mod(Value, 62), 1)
                }

                return Result
            }

            static BCRYPT_SHA256_ALG_HANDLE := 0x00000041

            SHA2_256(pInput, InputSize) {
                DllCall("bcrypt.dll\BCryptCreateHash"
                    , "Ptr", this.BCRYPT_SHA256_ALG_HANDLE
                    , "Ptr*", hHash
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

            static CRYPT_STRING_BASE64 := 0x1
            static CRYPT_STRING_NOCRLF := 0x40000000

            Base64Encode(pInput, InputSize) {
                DllCall("crypt32.dll\CryptBinaryToStringW"
                    , "Ptr", pInput
                    , "UInt", InputSize
                    , "UInt", this.CRYPT_STRING_BASE64
                    , "Ptr", 0
                    , "UInt*", ResultSize)

                VarSetCapacity(ResultBuffer, ResultSize, 0)
                DllCall("crypt32.dll\CryptBinaryToStringW"
                    , "Ptr", pInput
                    , "UInt", InputSize
                    , "UInt", this.CRYPT_STRING_BASE64
                    , "Ptr", &ResultBuffer
                    , "UInt*", ResultSize)

                return StrGet(&ResultBuffer + 0, ResultSize - 1, "UTF-16")
            }
        }

		class ILoveGeekTheyAreTheBest {
			; 0BSD License

			; Copyright (c) 2023 Philip Taylor

			; Permission to use, copy, modify, and/or distribute this software for
			; any purpose with or without fee is hereby granted.

			; THE SOFTWARE IS PROVIDED “AS IS” AND THE AUTHOR DISCLAIMS ALL
			; WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES
			; OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE
			; FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY
			; DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
			; AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
			; OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

			CredWrite(name, username, password)
			{
				VarSetCapacity(cred, 24 + A_PtrSize * 7, 0)
				cbPassword := StrLen(password)*2
				NumPut(1         , cred,  4+A_PtrSize*0, "UInt") ; Type = CRED_TYPE_GENERIC
				NumPut(&name     , cred,  8+A_PtrSize*0, "Ptr")  ; TargetName = name
				NumPut(cbPassword, cred, 16+A_PtrSize*2, "UInt") ; CredentialBlobSize
				NumPut(&password , cred, 16+A_PtrSize*3, "UInt") ; CredentialBlob
				NumPut(3         , cred, 16+A_PtrSize*4, "UInt") ; Persist = CRED_PERSIST_ENTERPRISE (roam across domain)
				NumPut(&username , cred, 24+A_PtrSize*6, "Ptr")  ; UserName
				return DllCall("Advapi32.dll\CredWriteW"
				, "Ptr", &cred ; [in] PCREDENTIALW Credential
				, "UInt", 0    ; [in] DWORD        Flags
				, "UInt") ; BOOL
			}

			CredDelete(name)
			{
				return DllCall("Advapi32.dll\CredDeleteW"
				, "WStr", name ; [in] LPCWSTR TargetName
				, "UInt", 1    ; [in] DWORD   Type,
				, "UInt", 0    ; [in] DWORD   Flags
				, "UInt") ; BOOL
			}

			CredRead(name)
			{
				DllCall("Advapi32.dll\CredReadW"
				, "Str", name   ; [in]  LPCWSTR      TargetName
				, "UInt", 1     ; [in]  DWORD        Type = CRED_TYPE_GENERIC (https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentiala)
				, "UInt", 0     ; [in]  DWORD        Flags
				, "Ptr*", pCred ; [out] PCREDENTIALW *Credential
				, "UInt") ; BOOL
				if !pCred
					return
				name := StrGet(NumGet(pCred + 8 + A_PtrSize * 0, "UPtr"), 256, "UTF-16")
				username := StrGet(NumGet(pCred + 24 + A_PtrSize * 6, "UPtr"), 256, "UTF-16")
				len := NumGet(pCred + 16 + A_PtrSize * 2, "UInt")
				password := StrGet(NumGet(pCred + 16 + A_PtrSize * 3, "UPtr"), len/2, "UTF-16")
				DllCall("Advapi32.dll\CredFree", "Ptr", pCred)
				return {"name": name, "username": username, "password": password}
			}
		}

        __New() {
            this.Crypto := new Spotify.PKCE.Crypto()
            this.Authorized := false
        }

        GenerateCodeChallenge() {
            this.CodeVerifier := this.Crypto.GenerateRandomString(128)

            ;this.CodeVerifier := "Definitelysuperrandomdatathatisverylongandsuperveextremelyrandom"

            VarSetCapacity(CodeVerifierBuffer, 128, 0)
            StrPut(this.CodeVerifier, &CodeVerifierBuffer, "UTF-8")

            pHash := this.Crypto.SHA2_256(&CodeVerifierBuffer, StrPut(this.CodeVerifier, "UTF-8") - 1)

            ; Hex := ""

            ; loop, 32 {
            ;     Hex .= Format("{:02x}", NumGet(pHash + A_Index - 1, 0, "UChar"))
            ; }
            ; MsgBox, % "Hex: " Hex

            this.CodeChallenge := this.Crypto.Base64Encode(pHash, 32)
            this.CodeChallenge := StrReplace(this.CodeChallenge, "=", "")
            this.CodeChallenge := StrReplace(this.CodeChallenge, "+", "-")
            this.CodeChallenge := StrReplace(this.CodeChallenge, "/", "_")

            ; MsgBox, % "Code Verifier: " this.CodeVerifier "`nCode Challenge: " this.CodeChallenge

            this.Crypto.Free(pHash)

            return this.CodeChallenge
        }

		HasSavedTokens() {
			return IsObject(Spotify.PKCE.ILoveGeekTheyAreTheBest.CredRead("Spotify.ahk"))
		}

		LoadSavedTokens() {
			Credential := Spotify.PKCE.ILoveGeekTheyAreTheBest.CredRead("Spotify.ahk")
			Tokens := JSON.Load(Credential.Password)

			;MsgBox, % "Load: " JSON.Dump(Tokens)

			this.AccessToken := Tokens.AccessToken
			this.AccessTokenExpiration := Tokens.AccessTokenExpiration
			this.RefreshToken := Tokens.RefreshToken
		}

		SaveTokens() {
			Tokens := {}
			Tokens.AccessToken := this.AccessToken
			Tokens.AccessTokenExpiration := this.AccessTokenExpiration
			Tokens.RefreshToken := this.RefreshToken

			;MsgBox, % "Save: " JSON.Dump(Tokens)

			Spotify.PKCE.ILoveGeekTheyAreTheBest.CredWrite("Spotify.ahk", A_UserName, JSON.Dump(Tokens))
		}

        SetAccessTokenExpiration(ExpiresInSeconds) {
            Expiration := A_Now
            EnvAdd, Expiration, %ExpiresInSeconds%, seconds
            this.AccessTokenExpiration := Expiration
        }
        IsAccessTokenExpired() {
            return A_Now > this.AccessTokenExpiration
        }

		static CLIENT_ID := "9fe26296bb7b4330ac59339efd2742b0"

		RequestTokens(ErrorMessage, Parameters) {
			BodyParameters := "client_id=" . this.CLIENT_ID . "&"

			for Key, Value in Parameters {
				BodyParameters .= Key "=" Value "&"
			}

			BodyParameters := SubStr(BodyParameters, 1, -1)

			;MsgBox, % BodyParameters

			Request := ComObjCreate("WinHttp.WinHttpRequest.5.1")
			Request.Open("POST", "https://accounts.spotify.com/api/token", false)
			Request.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded")
			Request.Send(BodyParameters)
			
			if (Request.Status != 200) {
				throw Exception("Spotify.ahk: " ErrorMessage ": status " Request.Status ", response: " Request.ResponseText)
			}

            Response := JSON.Load(Request.ResponseText)

        	;MsgBox, % "Access Token: " Response.access_token "`nRefresh Token: " Response.refresh_token

            this.AccessToken := Response.access_token
            this.SetAccessTokenExpiration(Response.expires_in - 1)

            this.RefreshToken := Response.refresh_token

			this.SaveTokens()

            this.Authorized := true
		}

        AuthorizationCallback(self, ByRef Request, ByRef Response) {            
			Response.status := 200
            
            if (Request.queries["error"]) {
				Response.SetBodyText("Authorization failed: " Request.queries["error"])
                throw Exception("Spotify.ahk: Web authorization failed: " Request.queries["error"])
            }
			else {
				Response.SetBodyText("Spotify.ahk: Authorization successful! You can close this tab/window.")
				this.AuthorizationCode := Request.queries["code"]
            }
        }

        RequestUserAuthorization() {
            this.GenerateCodeChallenge()

            Routes := {}
			Routes["/callback"] := this["AuthorizationCallback"].Bind(this)
            
			Server := new HttpServer()
			Server.SetPaths(Routes)
			Server.Serve(8000)

			Run, % "https://accounts.spotify.com/en/authorize?client_id=" this.CLIENT_ID "&response_type=code&code_challenge_method=S256&code_challenge=" this.CodeChallenge "&redirect_uri=http:%2F%2F127.0.0.1:8000%2Fcallback&scope=user-modify-playback-state%20user-read-currently-playing%20user-read-playback-state%20user-library-modify%20user-library-read%20user-read-email%20user-read-private%20user-read-birthdate%20user-follow-read%20user-follow-modify%20playlist-read-private%20playlist-read-collaborative%20playlist-modify-public%20playlist-modify-private%20user-read-recently-played%20user-top-read"

            Timeout := A_TickCount + (5 * 60 * 1000) ; 5 minute timeout

            while (!this.AuthorizationCode) {
                Sleep, 50

                if (A_TickCount > Timeout) {
                    throw Exception("Spotify.ahk: Web authorization timed out")
                    break
                }
            }

			Parameters := {}
			Parameters.grant_type := "authorization_code"
			Parameters.code := this.AuthorizationCode
			Parameters.code_verifier := this.CodeVerifier
			Parameters.redirect_uri := "http%3A%2F%2F127%2E0%2E0%2E1%3A8000%2Fcallback"
			this.RequestTokens("Could not complete initial web authorization", Parameters)

			AHKSock_Listen(8000) ; AHKhttp doesn't know how to shut down
        }

        RequestAccessFromRefreshToken() {
			Parameters := {}
			Parameters.grant_type := "refresh_token"
			Parameters.refresh_token := this.RefreshToken
			this.RequestTokens("Failed to refresh access token", Parameters)
        }

        AuthenticateRequest(Request) {
            if (!this.Authorized) {
                if (this.HasSavedTokens()) {
					this.LoadSavedTokens()
					this.Authorized := true ; trust the saved tokens
                }
                else {
                    this.RequestUserAuthorization()
                }
            }

            try {
				if (this.IsAccessTokenExpired()) {
					this.RequestAccessFromRefreshToken()
				}
			}
			catch {
				MsgBox, % "Spotify.ahk: Something went wrong while attempting to re-authorize with Spotify, trying web authorization"
				this.RequestUserAuthorization()
			}

            Request.SetRequestHeader("Authorization", "Bearer " this.AccessToken)
        }
    }
}

class Util {
	static MAX_RETRY := 3

	__New(ByRef ParentObject) {
		this.ParentObject := ParentObject
		this.PKCE := new Spotify.PKCE()
		
		if (!this.PKCE.HasSavedTokens()) {
			RegRead, LegacyRefreshToken, % "HKCU\Software\SpotifyAHK", refreshToken

			if (ErrorLevel || !LegacyRefreshToken) {
				; No legacy token, just start fresh
			}
			else {
				MsgBox, % "Spotify.ahk: Old install detected, you will need to re-authorize to migrate to the new authorization system"
			}
		}
	}
	
	; API token operations
	
	IsInternetConnected(CheckURL := "http://api.spotify.com/v1/"){
		return DllCall("Wininet.dll\InternetCheckConnection", "Str", CheckURL, "UInt", 1, "UInt", 0)
	}
	
	; API call method with auto-auth/timeout check/base URL
	
	CustomCall(method, url, HeaderArray := "", noTimeOut := false, body := "", noErr := false) {
		if (Spotify.SHOULD_CHECK_CONNECTION_BEFORE_REQUEST && !this.IsInternetConnected()) {
			Throw Exception("No internet connection")
		}
		
		if !((InStr(url, "https://api.spotify.com")) || (InStr(url, "https://accounts.spotify.com/api/"))) {
			url := "https://api.spotify.com/v1/" . url
		}
		if !(HeaderArray) {
			HeaderArray := {}
		}
		
		SpotifyWinHttp := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		SpotifyWinHttp.Open(method, url, false)
		
		for index, SubHeaderArray in HeaderArray {
			SpotifyWinHttp.SetRequestHeader(SubHeaderArray[1], SubHeaderArray[2])
		}

		this.PKCE.AuthenticateRequest(SpotifyWinHttp)
		
		SpotifyWinHttp.Send(body)
		
		if (SpotifyWinHttp.Status > 299 && !noErr) {
			ErrorObject := JSON.Load(SpotifyWinHttp.ResponseText).Error
			ErrorMessage := ""
			
			if (ErrorObject) {
				if (ErrorObject.Reason) {
					ErrorMessage .= ErrorObject.Reason ": "
				}
				
				ErrorMessage .= ErrorObject.Message
			}
			else {
				ErrorMessage := SpotifyWinHttp.Status . " not 2xx for request """ . method . ":" . url . """."
			}
			
			throw {message: ErrorMessage, what: "HTTP response code not 2xx", file: A_LineFile, line: A_LineNumber}
		}
		
		return SpotifyWinHttp.ResponseText
	}
}
class Player {
	__New(ByRef ParentObject) {
		this.ParentObject := ParentObject
	}
	SaveCurrentlyPlaying() {
		/*
		* Gets the currently playing track, then tells it to save itself (10/10 OOP, I know)
		* Requires something to be playing
		* returns the text response from the API, which is empty unless there is an error
		*/
		return this.GetCurrentPlaybackInfo().Track.Save()
	}
	UnSaveCurrentlyPlaying() {
		/*
		* Gets the currently playing track, then tells it to unsave itself
		* Requires something to be playing
		* returns the text response from the API, which is empty unless there is an error
		*/
		return this.GetCurrentPlaybackInfo().track.UnSave()
	}
	SetVolume(volume) {
		/*
		* Sets the volume of playback on the active device to the percent (0-100) passed 
		*/
		return this.ParentObject.Util.CustomCall("PUT", "me/player/volume?volume_percent=" . volume)
	}
	GetCurrentPlaybackInfo() {
		/*
		* Calls me/player, which returns a whole bunch of different objects
		* Translates JSON versions of track/device/context objects into custom objects
		* Alters the original response object, so any extra info that can't be turned into an object is still returned
		*/
		Resp := JSON.load(this.ParentObject.Util.CustomCall("GET", "me/player"))
		Resp.Track := new track(Resp["item"], this.ParentObject)
		Resp.Device := new device(Resp["device"], this.ParentObject)
		Resp.Context := new context(Resp["context"], this.ParentObject)
		return Resp
	}
	ChangeContext(ContextURI) {
		/*
		* OLD - I should probably remove this
		* Change playback to a different context (AKA playlist/album/just read whatever Spotify says is a context)
		* Only to be directly called until I finish with the playlist object
		*/
		return this.ParentObject.Util.CustomCall("PUT", "me/player/play",, false, JSON.Dump({"context_uri": ContextURI}))
	}
	
	GetDeviceList() {
		/*
		* Gets an array of device objects from the API
		* Translates them into our device class, and returns an array of custom device objects
		*/
		Resp := JSON.Load(this.ParentObject.Util.CustomCall("GET", "me/player/devices"))
		RetVar := []
		for k, v in Resp["devices"] {
			RetVar.Push(new device(v, this.ParentObject))
		}
		return RetVar
	}
	GetRecentlyPlayed() {
		/*
		* Gets an array of tracks alongside other info from the API
		* You might also want to read this Spotify API docs page
		* https://developer.spotify.com/documentation/web-api/reference/player/get-recently-played/
		* WARNING, EVERYTHING IS WRAPPED IN A PAGING OBJECT, the return object is structured as follows
		* Paging Object
		* |-> ["items"] (An array of the below objects)
		* |   |-> [1] Play History Object
		* |   |       |-> ["track"] (A simplified track object)
		* |   |       |-> ["context"] (A context object the track was played in)
		* |   |       |-> ["played_at"] (A UTC timestamp formatted YYYY-MM-DDTHH:MM:SSZ) - Note, I've got no clue what T or Z mean
		* |   |-> [2] Another Play History Object (They are numerically indexed, you can loop through with a for loop)
		* I really like how easy it is to follow what this returns with that nice graphic, I think I'll do it more
		* Builds the play history objects out of functional custom objects
		*/
		Resp := JSON.Load(this.ParentObject.Util.CustomCall("GET", "me/player/recently-played?limit=50"))
		for k, v in Resp["items"] {
			v := {"track": new track(v["track"], this.ParentObject), "context": new context(v["context"], this.ParentObject), "played_at": v["played_at"]}
		}
		return Resp
	}
	SeekTime(TimeInMS) {
		/*
		* Tells the API to jump to the specified time in MS on the currently playing track
		*/
		return this.ParentObject.Util.CustomCall("PUT", "me/player/seek?position_ms=" . TimeInMS)
	}
	SetRepeatMode(mode) {
		/*
		* Tells the API to change the repeat mode
		* Passing 1 for mode will have the currently playing track repeat
		* Passing 2 for mode will have the currently playing context repeat
		* Passing 3 or any other value that isn't 1/2 will turn off repeat
		*/
		return this.ParentObject.Util.CustomCall("PUT", "me/player/repeat?state=" . (mode = 1 ? "track" : (mode = 2 ? "context" : "off")))
	}
	SetShuffle(mode) {
		/*
		* Tells the API to change the shuffle mode to true/false, depending on what it it passed
		*/
		return this.ParentObject.Util.CustomCall("PUT", "me/player/shuffle?state=" . (mode ? "true" : "false"))
	}
	NextTrack() {
		/*
		* Figure this one out on your own
		*/
		return this.ParentObject.Util.CustomCall("POST", "me/player/next")
	}
	LastTrack() {
		/*
		* Figure this one out on your own
		*/
		return this.ParentObject.Util.CustomCall("POST", "me/player/previous")
	}
	PausePlayback() {
		/*
		* Figure this one out on your own
		*/
		return this.ParentObject.Util.CustomCall("PUT", "me/player/pause")
	}
	ResumePlayback() {
		/*
		* Figure this one out on your own
		*/
		return this.ParentObject.Util.CustomCall("PUT", "me/player/play")
	}
	PlayPause() {
		/*
		* Figure this one out on your own
		*/
		return ((this.GetCurrentPlaybackInfo()["is_playing"] = 0) ? (this.ResumePlayback()) : (this.PausePlayback()))
	}
}
class Library {
	__New(ByRef ParentObject) {
		this.ParentObject := ParentObject
	}
	CheckSavedForTrack(TrackID) {
		return this.ParentObject.Util.CustomCall("GET", "me/tracks/contains?ids=" . TrackID)
	}
	GetSavedAlbums() {
		resp := JSON.load(this.ParentObject.Util.CustomCall("GET", "me/albums?limit=1"))
		RetVar := []
		RetVar[1] := ""
		RetVar.SetCapacity(resp["total"])
		loop, % Ceil(resp["total"]/50) {
			for k, v in JSON.Load(this.ParentObject.Util.CustomCall("GET", "me/albums?limit=50&offset="  . ((A_Index - 1 ) * 50)))["items"] {
				alb := new album(v["album"], this.ParentObject)
				alb.added_at := v["added_at"]
				RetVar.Push(alb)
			}
		}
		RetVar.RemoveAt(1)
		return RetVar
	}
	GetSavedTracks() {
		resp := JSON.load(this.ParentObject.Util.CustomCall("GET", "me/tracks?limit=1"))
		RetVar := []
		RetVar[1] := ""
		RetVar.SetCapacity(resp["total"])
		loop, % Ceil(resp["total"]/50) {
			for k, v in JSON.Load(this.ParentObject.Util.CustomCall("GET", "me/tracks?limit=50&offset="  . ((A_Index - 1 ) * 50)))["items"] {
				trk := new track(v["track"], this.ParentObject)
				trk.added_at := v["added_at"]
				RetVar.Push(trk)
			}
		}
		RetVar.RemoveAt(1)
		return RetVar
	}
}

class Tracks {
	__New(ByRef ParentObject) {
		this.ParentObject := ParentObject
	}
	GetTrack(TrackID) {
		return new track(JSON.Load(this.ParentObject.Util.CustomCall("GET", "tracks/" . TrackID)), this.ParentObject)
	}
}
class Albums {
	__New(ByRef ParentObject) {
		this.ParentObject := ParentObject
	}
	GetAlbum(AlbumID) {
		return new album(JSON.Load(this.ParentObject.Util.CustomCall("GET", "albums/" . AlbumID)), this.ParentObject)
	}
}

class Artists {
	__New(ByRef ParentObject) {
		this.ParentObject := ParentObject
	}
	GetArtist(ArtistID) {
		return new artist(JSON.Load(this.ParentObject.Util.CustomCall("GET", "artists/" . ArtistID)), this.ParentObject)
	}
}
class Playlists {
	__New(ByRef ParentObject) {
		this.ParentObject := ParentObject
	}
	GetPlaylist(PlaylistID) {
		return new playlist(JSON.Load(this.ParentObject.Util.CustomCall("GET", "playlists/" . PlaylistID)), this.ParentObject)
	}
	GetPlaylistTracks(PlaylistID) {
		; get first page (up to 100 tracks)
		PlaylistObject := new playlist(JSON.Load(this.ParentObject.Util.CustomCall("GET", "playlists/" . PlaylistID)), this.ParentObject)
		offset := 100
		loop {
			; get next 100 tracks (if any)
			TrackObject := JSON.Load(this.ParentObject.Util.CustomCall("GET", "playlists/" . PlaylistID . "/tracks?offset=" . offset))
			; add tracks to playlist object
			PlaylistObject.AddTracksPage(TrackObject.items)
			offset += 100
		} until !TrackObject.items.MaxIndex()
		return PlaylistObject
	}
	CreatePlaylist(name, description, public := true) {
		headers := {1:{1:"Authorization", 2:"Bearer " . this.ParentObject.Util.token}, 2:{1:"Content-Type", 2:"application/json"}}
		body := "{""name"":""" . name . """, ""description"":""" . description """, ""public"":" . public . "}"
		MsgBox, % body
		return new playlist(JSON.Load(this.ParentObject.Util.CustomCall("POST", "users/" . this.ParentObject.CurrentUser.id . "/playlists", headers,, body)), this.ParentObject)
	}
}
class Users {
	__New(ByRef ParentObject) {
		this.ParentObject := ParentObject
	}
	GetUser(UserID) {
		return new user(JSON.Load(this.ParentObject.Util.CustomCall("GET", "users/" . UserID)), this.ParentObject)
	}
}

class playlist {
	__New(PlaylistObj, ByRef Parent := "") {
		this.SpotifyObj := Parent
		this.json := PlaylistObj
		this.description := (this.json["description"] = "null" ? "" : this.json["description"])
		this.id := this.json["id"]
		this.name := this.json["name"]
		this.uri := this.json["uri"]
		this.owner := new user(this.json["owner"], this.SpotifyObj)
		this.public := (this.json["public"] = "null" ? true : (this.json["public"] = "true" ? true : false))
		this.tracks := []
		for k, v in this.json["tracks"]["items"] {
			this.tracks.Push(new track(v["track"], this.SpotifyObj))
		}
		this.uri := this.json["uri"]
	}
	AddTrack(TrackIDOrTrackOBJ) {
		if (IsObject(TrackIDOrTrackOBJ)) {
			tid := TrackIDOrTrackOBJ.id
		}
		else {
			tid := TrackIDOrTrackOBJ
		}
		this.SpotifyObj.Util.CustomCall("POST", "playlists/" . this.id . "/tracks?uris=spotify:track:" . tid)
	}
	RemoveTrack(TrackIDOrTrackOBJ) {
		if (IsObject(TrackIDOrTrackOBJ)) {
			tid := TrackIDOrTrackOBJ.id
		}
		else {
			tid := TrackIDOrTrackOBJ
		}
		this.SpotifyObj.Util.CustomCall("DELETE", "playlists/" . this.id . "/tracks",, false, JSON.Dump({"tracks": [{"uri": "spotify:track:" . tid}]}))
	}
	Play() {
		return this.SpotifyObj.Util.CustomCall("PUT", "me/player/play",, false, JSON.Dump({"context_uri": "spotify:playlist:" . this.id}))
	}
	Delete() {
		this.SpotifyObj.Util.CustomCall("DELETE", "https://api.spotify.com/v1/playlists/" . this.id "/followers")
		return
	}
	GetAllTracks() {
		; get first page (up to 100 tracks)
		offset := 100
		loop {
			; get next 100 tracks (if any)
			TracksObject := JSON.Load(this.SpotifyObj.Util.CustomCall("GET", "playlists/" . this.id . "/tracks?limit=100&offset=" . offset))
			; add tracks to playlist object
			for k, v in TracksObject.items {
				this.tracks.Push(new track(v["track"], this.SpotifyObj))
			}
			offset += 100
		} until !TracksObject.items.MaxIndex()
		return this.tracks
	}
	; Fuck me, all these classes feel so half-baked, what the hell am I even doing?
}

class track {
	__New(ResponseTrackObj, ByRef Parent := "") {
		this.SpotifyObj := Parent
		this.json := ResponseTrackObj
		this.id := this.json["id"]
		this.album := new album(this.json["album"], this.SpotifyObj) ; TODO -- Album objects
		this.artists := []
		for k, v in this.json["artists"] {
			this.artists.Push(new artist(v, this.SpotifyObj))
		}
		this.duration := this.json["duration_ms"]
		this.explicit := this.json["explicit"]
		this.name := this.json["name"]
	}
	IsSaved[] {
		Get {
			return (this.SpotifyObj.Util.CustomCall("GET", "me/tracks/contains?ids=" . this.id) ~= "true" ? true : false)
		}
	}

	Save() {
		return this.SpotifyObj.Util.CustomCall("PUT", "me/tracks?ids=" . this.id)
	}
	
	UnSave() {
		return this.SpotifyObj.Util.CustomCall("DELETE", "me/tracks?ids=" . this.id)
	}
	
	Play() {
		return this.SpotifyObj.Util.CustomCall("PUT", "me/player/play",, false, JSON.Dump({"uris": ["spotify:track:" . this.id]}))
	}
}

class album {
	__New(Albumjson, ByRef Parent := "") {
		this.SpotifyObj := Parent
		this.json := Albumjson
		this.artists := this.json["artists"]
		this.genres := this.json["genres"]
		this.id := this.json["id"]
		this.images := this.json["images"]
		this.name := this.json["name"]
		this.uri := this.json["uri"]
		this.tracks := []
		this.context := new context({"uri": this.uri}, this.SpotifyObj)
		for k, v in this.json["tracks"]["items"] {
			this.tracks.Push(new track(v, this.SpotifyObj))
		}
	}
	;__Get(this, key) {
	;	this.key := this.SpotifyObj.Albums.GetAlbum(this.id).key
	;}
	
	IsSaved[] {
		Get {
			return (this.SpotifyObj.Util.CustomCall("GET", "me/albums/contains?ids=" . this.id) ~= "true" ? true : false)
		}
	}
	
	Play() {
		return this.context.SwitchTo()
	}
	
	Save() {
		return this.SpotifyObj.Util.CustomCall("PUT", "me/albums?ids=" . this.id)
	}
	
	UnSave() {
		return this.SpotifyObj.Util.CustomCall("DELETE", "me/albums?ids=" . this.id)
	}
}

class device {
	__New(Devicejson, ByRef Parent := "") {
		this.SpotifyObj := Parent
		this.json := Devicejson
		this.id := this.json["id"]
		this.IsActive := this.json["is_active"]
		this.IsPrivate := this.json["is_private_session"]
		this.name := this.json["name"]
		this.type  := this.json["type"]
		this.volume := this.json["volume_percent"]
	}
	
	SwitchTo() {
		return this.SpotifyObj.Util.CustomCall("PUT", "me/player",, false, JSON.Dump({"device_ids": [this.id]}))
	}
}

class context {
	__New(Contextjson, ByRef Parent := "") {
		this.SpotifyObj := Parent
		this.json := Contextjson
		this.uri := this.json["uri"]
		this.type := this.json["type"]
	}
	
	SwitchTo() {
		return this.SpotifyObj.Util.CustomCall("PUT", "me/player/play",, false, JSON.Dump({"context_uri": this.uri}))
	}
}
class artist {
	__New(Artistjson, ByRef Parent := "") {
		this.SpotifyObj := Parent
		this.json := Artistjson
		this.genres := this.json["genres"]
		this.id := this.json["id"]
		this.images := this.json["images"]
		this.name := this.json["name"]
		this.uri := this.json["uri"]
	}
	
	GetAlbums() {
		resp := JSON.load(this.SpotifyObj.Util.CustomCall("GET", "https://api.spotify.com/v1/artists/" . this.id . "/albums?limit=1"))
		RetVar := []
		RetVar[1] := ""
		RetVar.SetCapacity(resp["total"])
		loop, % Ceil(resp["total"]/50) {
			for k, v in JSON.Load(this.SpotifyObj.Util.CustomCall("GET", "artists/" . this.id . "/albums?limit=50&offset="  . ((A_Index - 1 ) * 50)))["items"] {
				RetVar.Push(new album(v, this.SpotifyObj))
			}
		}
		RetVar.RemoveAt(1)
		return RetVar
	}	
	; Jesus, I have just fucking ruined the global namespace. TODO -- Nest these somewhere
	; TODO -- Get a plugin that actually makes "TODO --" do something
}
class user {
	__New(Userjson, ByRef Parent := "", isCur := false) {
		this.SpotifyObj := Parent
		this.json := Userjson
		this.isCur := isCur
		this.birthdate := this.json["birthdate"]
		this.name := this.json["display_name"]
		this.email := this.json["email"]
		this.id := this.json["id"]
		this.subscriptionLevel := this.json["product"]
	}
	GetPlaylists() {
		; I don't know why, but I couldn't return the array of playlists generated by this function properly, so ignore the stuff with RetVer
		; Maybe some limitation on pushing large objects onto an array
		resp := JSON.load(this.SpotifyObj.Util.CustomCall("GET", "users/" . this.id . "/playlists?limit=1"))
		RetVar := []
		RetVar[1] := ""
		RetVar.SetCapacity(resp["total"])
		loop, % Ceil(resp["total"]/50) {
			for k, v in JSON.load(this.SpotifyObj.Util.CustomCall("GET", "users/" . this.id . "/playlists?limit=50&offset=" . ((A_Index - 1 ) * 50)))["items"] {
				RetVar.Push(new playlist(v, this.SpotifyObj))
			}
		}
		RetVar.RemoveAt(1)
		return RetVar
	}
	GetTop(ArtistsOrTracks := "tracks") {
		if !(this.isCur) {
			return ""
		}
		RetVar := []
		for k, v in JSON.load(this.SpotifyObj.Util.CustomCall("GET", "me/top/" . ArtistsOrTracks))["items"] {
			if (ArtistsOrTracks = "artists") {
				RetVar.Push(new artist(v, this.SpotifyObj))
			}
			else {
				RetVar.Push(new track(v, this.SpotifyObj))
			}
		}
		return RetVar
	}
}

#Include <AHKsock>
#Include <AHKhttp>
#Include <crypt>
#Include <json>
