#Requires AutoHotkey v2.0

XTERNAL_TELEMETRY_API_URL := "http://157.230.201.82/api/v1/xternal"
TELEMETRY_STATE_PATH := APPDATA_DIR "\telemetry.json"
TELEMETRY_HEARTBEAT_INTERVAL_MS := 45000

TelemetryStarted := false
TelemetryState := Map(
    "install_id", "",
    "session_id", "",
    "session_token", ""
)

StartTelemetry() {
    global TelemetryStarted, TelemetryState, TELEMETRY_HEARTBEAT_INTERVAL_MS

    if (TelemetryStarted)
        return

    if !IsTelemetryEnabled()
        return

    TelemetryLoadState()

    if !TelemetryIsUuid(TelemetryState["install_id"])
        return

    TelemetryState["session_id"] := ""
    TelemetryState["session_token"] := ""
    TelemetrySaveState()

    TelemetryStarted := true
    SetTimer(TelemetryCreateSession, -1000)
    SetTimer(TelemetryHeartbeat, TELEMETRY_HEARTBEAT_INTERVAL_MS)
}

StopTelemetry() {
    global TelemetryStarted, TelemetryState

    if (!TelemetryStarted)
        return

    SetTimer(TelemetryCreateSession, 0)
    SetTimer(TelemetryHeartbeat, 0)

    sessionId := TelemetryState["session_id"]
    sessionToken := TelemetryState["session_token"]

    if (TelemetryIsUuid(sessionId) && sessionToken != "")
        TelemetryHttpRequest("DELETE", "/sessions/" sessionId, "", sessionToken)

    TelemetryState["session_id"] := ""
    TelemetryState["session_token"] := ""
    TelemetrySaveState()
    TelemetryStarted := false
}

DisableTelemetry() {
    global TelemetryState, TELEMETRY_STATE_PATH

    StopTelemetry()

    try {
        if FileExist(TELEMETRY_STATE_PATH)
            FileDelete(TELEMETRY_STATE_PATH)
    } catch {
    }

    TelemetryState := Map(
        "install_id", "",
        "session_id", "",
        "session_token", ""
    )
}

SetTelemetryEnabled(enabled) {
    global SETTINGS

    if (!SETTINGS.Has("telemetry") || !(SETTINGS["telemetry"] is Map))
        SETTINGS["telemetry"] := Map()

    SETTINGS["telemetry"]["enabled"] := enabled ? 1 : 0
    SaveSettingsFile()

    if (enabled)
        StartTelemetry()
    else
        DisableTelemetry()
}

IsTelemetryEnabled() {
    global SETTINGS

    if (!SETTINGS.Has("telemetry") || !(SETTINGS["telemetry"] is Map))
        return true

    if (!SETTINGS["telemetry"].Has("enabled"))
        return true

    return SETTINGS["telemetry"]["enabled"] ? true : false
}

TelemetryOnExit(ExitReason, ExitCode) {
    StopTelemetry()
    return 0
}

TelemetryCreateSession() {
    global TelemetryState, FULL_VER

    if !IsTelemetryEnabled()
        return

    if !TelemetryIsUuid(TelemetryState["install_id"])
        return

    payload := Map(
        "install_id", TelemetryState["install_id"],
        "app_version", FULL_VER
    )
    response := TelemetryHttpRequest("POST", "/sessions", JSON.stringify(payload))

    if !TelemetryIsSuccessful(response.status)
        return

    try {
        data := JSON.parse(response.text)

        if (!data.Has("session_id") || !data.Has("session_token"))
            return

        if !TelemetryIsUuid(data["session_id"])
            return

        TelemetryState["session_id"] := data["session_id"]
        TelemetryState["session_token"] := data["session_token"]
        TelemetrySaveState()
    } catch {
    }
}

TelemetryHeartbeat() {
    global TelemetryState

    if !IsTelemetryEnabled() {
        DisableTelemetry()
        return
    }

    sessionId := TelemetryState["session_id"]
    sessionToken := TelemetryState["session_token"]

    if (!TelemetryIsUuid(sessionId) || sessionToken = "") {
        TelemetryCreateSession()
        return
    }

    response := TelemetryHttpRequest("POST", "/sessions/" sessionId "/heartbeat", "", sessionToken)

    if TelemetryIsSuccessful(response.status)
        return

    if (response.status = 401 || response.status = 404 || response.status = 409) {
        TelemetryState["session_id"] := ""
        TelemetryState["session_token"] := ""
        TelemetrySaveState()
    }
}

TelemetryLoadState() {
    global TelemetryState, TELEMETRY_STATE_PATH

    TelemetryState := Map(
        "install_id", "",
        "session_id", "",
        "session_token", ""
    )

    if FileExist(TELEMETRY_STATE_PATH) {
        try {
            data := JSON.parse(FileRead(TELEMETRY_STATE_PATH))

            for key, _ in TelemetryState {
                if data.Has(key)
                    TelemetryState[key] := data[key]
            }
        } catch {
        }
    }

    if !TelemetryIsUuid(TelemetryState["install_id"]) {
        TelemetryState["install_id"] := TelemetryGenerateUuid()
        TelemetryState["session_id"] := ""
        TelemetryState["session_token"] := ""
    }

    if !TelemetryIsUuid(TelemetryState["session_id"])
        TelemetryState["session_id"] := ""
}

TelemetrySaveState() {
    global TelemetryState, TELEMETRY_STATE_PATH, APPDATA_DIR

    try {
        if !DirExist(APPDATA_DIR)
            DirCreate(APPDATA_DIR)

        state := Map(
            "install_id", TelemetryState["install_id"],
            "session_id", TelemetryState["session_id"],
            "session_token", TelemetryState["session_token"]
        )

        file := FileOpen(TELEMETRY_STATE_PATH, "w")
        file.Write(JSON.stringify(state, 4))
        file.Close()
    } catch {
    }
}

TelemetryHttpRequest(method, endpoint, body := "", sessionToken := "") {
    global XTERNAL_TELEMETRY_API_URL, FULL_VER

    try {
        request := CreateHttpRequest()
        request.Open(method, XTERNAL_TELEMETRY_API_URL endpoint, false)
        request.SetRequestHeader("Accept", "application/json")
        request.SetRequestHeader("User-Agent", "OpenMacro-XTernal/" FULL_VER)

        if (body != "")
            request.SetRequestHeader("Content-Type", "application/json")

        if (sessionToken != "")
            request.SetRequestHeader("Authorization", "Bearer " sessionToken)

        request.Send(body)
        return { status: request.Status, text: request.ResponseText }
    } catch {
        return { status: 0, text: "" }
    }
}

TelemetryIsSuccessful(status) {
    return status >= 200 && status < 300
}

TelemetryIsUuid(value) {
    return value is String
        && RegExMatch(value, "i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
}

TelemetryGenerateUuid() {
    uuidBuffer := Buffer(16, 0)
    createResult := DllCall("Rpcrt4.dll\UuidCreate", "Ptr", uuidBuffer.Ptr, "UInt")

    if (createResult != 0 && createResult != 1824)
        return ""

    stringPtr := 0
    stringResult := DllCall("Rpcrt4.dll\UuidToStringW", "Ptr", uuidBuffer.Ptr, "Ptr*", &stringPtr, "UInt")

    if (stringResult != 0 || !stringPtr)
        return ""

    value := StrLower(StrGet(stringPtr, "UTF-16"))
    DllCall("Rpcrt4.dll\RpcStringFreeW", "Ptr*", &stringPtr)
    return value
}
