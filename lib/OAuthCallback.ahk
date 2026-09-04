#Requires AutoHotkey v2.0

; Minimal localhost HTTP listener for OAuth redirect callbacks.
class OAuthCallback {
	static WaitForCode(Port, TimeoutMs := 300000, OnReady := 0) {
		if err := DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", Buffer(408, 0), "Int")
			throw OSError(err, -1, "WSAStartup")

		try {
			listenSock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr") ; AF_INET, SOCK_STREAM, IPPROTO_TCP
			if listenSock = -1
				throw OSError(DllCall("ws2_32\WSAGetLastError"), -1, "socket")

			try {
				opt := Buffer(4, 0)
				NumPut("Int", 1, opt)
				DllCall("ws2_32\setsockopt", "Ptr", listenSock, "Int", 0xFFFF, "Int", 4, "Ptr", opt, "Int", 4) ; SOL_SOCKET, SO_REUSEADDR

				addr := Buffer(16, 0)
				NumPut("UShort", 2, addr, 0) ; AF_INET
				NumPut("UShort", DllCall("ws2_32\htons", "UShort", Port, "UShort"), addr, 2)
				NumPut("UInt", 0, addr, 4) ; INADDR_ANY

				if DllCall("ws2_32\bind", "Ptr", listenSock, "Ptr", addr, "Int", 16, "Int") != 0
					throw OSError(DllCall("ws2_32\WSAGetLastError"), -1, "bind")
				if DllCall("ws2_32\listen", "Ptr", listenSock, "Int", 1, "Int") != 0
					throw OSError(DllCall("ws2_32\WSAGetLastError"), -1, "listen")

				if OnReady
					OnReady.Call()

				deadline := A_TickCount + TimeoutMs
				while A_TickCount < deadline {
					fds := Buffer(A_PtrSize = 8 ? 16 : 8, 0)
					NumPut("UInt", 1, fds, 0)
					NumPut("Ptr", listenSock, fds, A_PtrSize = 8 ? 8 : 4)

					timeout := Buffer(8, 0)
					NumPut("Int", 0, timeout, 0)      ; tv_sec
					NumPut("Int", 100000, timeout, 4) ; tv_usec = 100ms

					ready := DllCall("ws2_32\select", "Int", 0, "Ptr", fds, "Ptr", 0, "Ptr", 0, "Ptr", timeout, "Int")
					if ready = 0 {
						Sleep(10)
						continue
					}
					if ready = -1
						throw OSError(DllCall("ws2_32\WSAGetLastError"), -1, "select")

					client := DllCall("ws2_32\accept", "Ptr", listenSock, "Ptr", 0, "Ptr", 0, "Ptr")
					if client = -1
						throw OSError(DllCall("ws2_32\WSAGetLastError"), -1, "accept")

					try {
						return OAuthCallback.HandleRequest(client, OAuthCallback.RecvRequest(client))
					} finally {
						DllCall("ws2_32\closesocket", "Ptr", client)
					}
				}
				throw Error("Spotify.ahk: Web authorization timed out")
			} finally {
				DllCall("ws2_32\closesocket", "Ptr", listenSock)
			}
		} finally {
			DllCall("ws2_32\WSACleanup")
		}
	}

	static RecvRequest(sock) {
		data := ""
		buf := Buffer(4096, 0)
		deadline := A_TickCount + 10000
		while A_TickCount < deadline {
			n := DllCall("ws2_32\recv", "Ptr", sock, "Ptr", buf, "Int", buf.Size, "Int", 0, "Int")
			if n > 0 {
				data .= StrGet(buf, n, "UTF-8")
				if InStr(data, "`r`n`r`n")
					break
			} else if n = 0 {
				break
			} else if DllCall("ws2_32\WSAGetLastError") = 10035 { ; WSAEWOULDBLOCK
				Sleep(10)
			} else {
				break
			}
		}
		return data
	}

	static HandleRequest(sock, request) {
		path := ""
		if RegExMatch(request, "i)^GET\s+(\S+)", &m)
			path := m[1]

		queries := Map()
		if (qPos := InStr(path, "?")) {
			for part in StrSplit(SubStr(path, qPos + 1), "&") {
				if (eq := InStr(part, "="))
					queries[SubStr(part, 1, eq - 1)] := OAuthCallback.UriDecode(SubStr(part, eq + 1))
				else if part != ""
					queries[part] := ""
			}
		}

		if queries.Has("error") {
			OAuthCallback.SendResponse(sock, 400, "Authorization failed: " queries["error"])
			throw Error("Spotify.ahk: Web authorization failed: " queries["error"])
		}

		if !queries.Has("code") || queries["code"] = "" {
			OAuthCallback.SendResponse(sock, 400, "Spotify.ahk: Missing authorization code.")
			throw Error("Spotify.ahk: Web authorization failed: missing code")
		}

		OAuthCallback.SendResponse(sock, 200, "Spotify.ahk: Authorization successful! You can close this tab/window.")
		return queries["code"]
	}

	static SendResponse(sock, status, body) {
		bodyBytes := StrPut(body, "UTF-8") - 1
		bodyBuf := Buffer(bodyBytes)
		StrPut(body, bodyBuf, "UTF-8")
		header := Format(
			"HTTP/1.1 {} {}`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: {}`r`nConnection: close`r`n`r`n",
			status,
			status = 200 ? "OK" : "Bad Request",
			bodyBytes
		)
		headerBuf := Buffer(StrPut(header, "UTF-8") - 1)
		StrPut(header, headerBuf, "UTF-8")
		DllCall("ws2_32\send", "Ptr", sock, "Ptr", headerBuf, "Int", headerBuf.Size, "Int", 0)
		DllCall("ws2_32\send", "Ptr", sock, "Ptr", bodyBuf, "Int", bodyBuf.Size, "Int", 0)
	}

	static UriDecode(str) {
		str := StrReplace(str, "+", " ")
		while RegExMatch(str, "i)%[\da-f]{2}", &m)
			str := StrReplace(str, m[0], Chr(Integer("0x" SubStr(m[0], 2))))
		return str
	}
}
