;=====================================================================
; activity.asm  -  activity log (an audit trail like real software)
;
; Every important action adds one line to data\<username>.log:
;   2026-11-07 15:42   Logged in
;   2026-11-07 15:44   Course saved: COAL
;   2026-11-07 16:10   Pomodoro finished: COAL (25 min)
;
; The file is opened with OPEN_ALWAYS (create it if missing) and the
; file pointer is moved to the end before writing, so old lines are
; kept. File > View activity log opens it in Notepad.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

BuildLogPath    PROTO

.data
logPath     BYTE 300 DUP(0)
logLine     BYTE 256 DUP(0)
logText     BYTE 200 DUP(0)
szLogExt    BYTE ".log", 0
szDataFolder BYTE "data\", 0
szFmtLine   BYTE "%04d-%02d-%02d %02d:%02d   %s", 13, 10, 0
szOpen      BYTE "open", 0

.code
;---------------------------------------------------------------------
; BuildLogPath - logPath = data folder + username + ".log"
; (the data folder is the folder part of the save file's path)
;---------------------------------------------------------------------
BuildLogPath PROC USES ecx edi
    INVOKE GetModuleFileNameA, NULL, ADDR logPath, SIZEOF logPath
    mov edi, OFFSET logPath
    add edi, eax
FindSlash:
    cmp edi, OFFSET logPath
    je  CutHere
    dec edi
    cmp BYTE PTR [edi], '\'
    jne FindSlash
    inc edi
CutHere:
    mov BYTE PTR [edi], 0
    INVOKE StrAppend, ADDR logPath, ADDR szDataFolder
    INVOKE StrAppend, ADDR logPath, ADDR userData.userName
    INVOKE StrAppend, ADDR logPath, ADDR szLogExt
    ret
BuildLogPath ENDP

;---------------------------------------------------------------------
; LogEvent - appends "date time   text" to the log
;---------------------------------------------------------------------
LogEvent PROC USES ebx ecx edx esi edi, pText:DWORD
    LOCAL sysTime:SYSTEMTIME, written:DWORD

    cmp userData.userName, 0
    je  Done                        ; nobody logged in
    INVOKE BuildLogPath
    INVOKE GetLocalTime, ADDR sysTime
    movzx eax, sysTime.wYear
    movzx ebx, sysTime.wMonth
    movzx ecx, sysTime.wDay
    movzx edx, sysTime.wHour
    movzx esi, sysTime.wMinute
    INVOKE wsprintf, ADDR logLine, ADDR szFmtLine, eax, ebx, ecx, edx, esi, pText

    ; open (or create) the file and write at its end
    INVOKE CreateFileA, ADDR logPath, GENERIC_WRITE, FILE_SHARE_READ, NULL,
           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL
    cmp eax, INVALID_HANDLE_VALUE
    je  Done
    mov ebx, eax
    INVOKE SetFilePointer, ebx, 0, NULL, FILE_END
    INVOKE Str_length, ADDR logLine
    mov ecx, eax
    INVOKE WriteFile, ebx, ADDR logLine, ecx, ADDR written, NULL
    INVOKE CloseHandle, ebx
Done:
    ret
LogEvent ENDP

;---------------------------------------------------------------------
; LogEventFmt - like LogEvent, with one value put into the text
;   LogEventFmt "Course saved: %s", ADDR name
;---------------------------------------------------------------------
LogEventFmt PROC pFmt:DWORD, arg:DWORD
    INVOKE wsprintf, ADDR logText, pFmt, arg
    INVOKE LogEvent, ADDR logText
    ret
LogEventFmt ENDP

;---------------------------------------------------------------------
; OpenActivityLog - shows the log in Notepad (or the default editor)
;---------------------------------------------------------------------
OpenActivityLog PROC
    INVOKE BuildLogPath
    INVOKE ShellExecuteA, hMainWnd, ADDR szOpen, ADDR logPath, NULL, NULL, SW_SHOWNORMAL
    ret
OpenActivityLog ENDP

END
