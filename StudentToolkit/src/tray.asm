;=====================================================================
; tray.asm  -  system tray icon, Windows notifications, sound chimes
;
; The tray icon (next to the clock) stays while the main window is
; open. Windows tells us about clicks on it with our own message
; WM_TRAY:
;   left click        -> bring Student Toolkit to the front
;   right click       -> menu: Open / Start-Pause timer / Mini timer / Exit
; Notifications (NIF_INFO) appear as Windows toasts:
;   - a Pomodoro or break has finished
;   - a badge was unlocked
;   - at login: deadlines due today or tomorrow
; Chimes are short Beep(frequency, duration) melodies stored as tables.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

TRAY_ID         = 1
IDM_TRAY_OPEN   = 1
IDM_TRAY_TIMER  = 2
IDM_TRAY_MINI   = 3
IDM_TRAY_EXIT   = 4

.data
nid         NOTIFYICONDATAA <>
trayAdded   DWORD 0

szTrayTip       BYTE "Student Toolkit", 0
szTrayOpen      BYTE "Open Student Toolkit", 0
szTrayStart     BYTE "Start timer", 0
szTrayPause     BYTE "Pause timer", 0
szTrayMini      BYTE "Mini timer", 0
szTrayExit      BYTE "Exit", 0

; chimes: pairs of (frequency Hz, length ms), ending with 0
chimeDone   DWORD 523, 110, 659, 110, 784, 220, 0          ; rising C-E-G
chimeBreak  DWORD 784, 140, 659, 140, 523, 200, 0          ; falling G-E-C
chimeBadge  DWORD 659, 90, 784, 90, 988, 90, 1319, 260, 0  ; little fanfare
chimeTable  DWORD OFFSET chimeDone, OFFSET chimeBreak, OFFSET chimeBadge

szDueTitle      BYTE "Coming up", 0
szFmtDueToday   BYTE "%s is due today.", 0
szFmtDueTmrw    BYTE "%s is due tomorrow.", 0
szFmtDueMore    BYTE "  (+%d more due soon)", 0
dueBuf          BYTE 160 DUP(0)
dueBuf2         BYTE 48 DUP(0)

.code
;---------------------------------------------------------------------
; TrayAdd - puts our icon in the notification area
;---------------------------------------------------------------------
TrayAdd PROC USES edi, hWnd:DWORD
    ; start from an all-zero structure
    mov edi, OFFSET nid
    mov ecx, SIZEOF NOTIFYICONDATAA
    xor eax, eax
    cld
    rep stosb
    mov nid.nidSize, SIZEOF NOTIFYICONDATAA
    mov eax, hWnd
    mov nid.nidWnd, eax
    mov nid.nidID, TRAY_ID
    mov nid.nidFlags, NIF_MESSAGE OR NIF_ICON OR NIF_TIP
    mov nid.nidCallback, WM_TRAY
    INVOKE LoadImageA, hInstance, IDI_APPICON, IMAGE_ICON, 16, 16, 0
    mov nid.nidIcon, eax
    INVOKE Str_copy, ADDR szTrayTip, ADDR nid.nidTip
    INVOKE Shell_NotifyIconA, NIM_ADD, ADDR nid
    mov trayAdded, eax
    ret
TrayAdd ENDP

;---------------------------------------------------------------------
; TrayRemove - takes the icon away (logout / exit)
;---------------------------------------------------------------------
TrayRemove PROC
    cmp trayAdded, 0
    je  @F
    mov nid.nidFlags, 0
    INVOKE Shell_NotifyIconA, NIM_DELETE, ADDR nid
    mov trayAdded, 0
@@: ret
TrayRemove ENDP

;---------------------------------------------------------------------
; TrayNotify - shows a Windows notification with a title and a text
;---------------------------------------------------------------------
TrayNotify PROC pTitle:DWORD, pText:DWORD
    cmp trayAdded, 0
    je  Done
    mov nid.nidFlags, NIF_INFO
    INVOKE Str_copy, pTitle, ADDR nid.nidInfoTitle
    INVOKE Str_copy, pText, ADDR nid.nidInfo
    mov nid.nidTimeout, 8000
    mov nid.nidInfoFlags, NIIF_INFO
    INVOKE Shell_NotifyIconA, NIM_MODIFY, ADDR nid
Done:
    ret
TrayNotify ENDP

;---------------------------------------------------------------------
; RestoreMain - brings the main window back to the front
;---------------------------------------------------------------------
RestoreMain PROC
    cmp hMainWnd, 0
    je  Done
    INVOKE IsIconic, hMainWnd
    cmp eax, 0
    je  @F
    INVOKE ShowWindow, hMainWnd, SW_RESTORE
@@: INVOKE SetForegroundWindow, hMainWnd
Done:
    ret
RestoreMain ENDP

;---------------------------------------------------------------------
; TrayCallback - a mouse action on the tray icon (lParam = message)
;---------------------------------------------------------------------
TrayCallback PROC USES ebx, hWnd:DWORD, lParam:DWORD
    LOCAL pt:POINT, hMenu:DWORD

    mov eax, lParam
    cmp eax, WM_LBUTTONUP
    je  Open
    cmp eax, WM_LBUTTONDBLCLK
    je  Open
    cmp eax, WM_RBUTTONUP
    je  ShowMenu
    ret
Open:
    INVOKE RestoreMain
    ret

ShowMenu:
    INVOKE CreatePopupMenu
    mov hMenu, eax
    INVOKE AppendMenuA, hMenu, MF_STRING, IDM_TRAY_OPEN, ADDR szTrayOpen
    mov edx, OFFSET szTrayStart
    cmp tmRunning, 0
    je  @F
    mov edx, OFFSET szTrayPause
@@: INVOKE AppendMenuA, hMenu, MF_STRING, IDM_TRAY_TIMER, edx
    INVOKE AppendMenuA, hMenu, MF_STRING, IDM_TRAY_MINI, ADDR szTrayMini
    INVOKE AppendMenuA, hMenu, MF_SEPARATOR, 0, NULL
    INVOKE AppendMenuA, hMenu, MF_STRING, IDM_TRAY_EXIT, ADDR szTrayExit
    INVOKE GetCursorPos, ADDR pt
    ; Windows needs our window in front, or the menu won't close
    INVOKE SetForegroundWindow, hWnd
    INVOKE TrackPopupMenu, hMenu, TPM_RETURNCMD OR TPM_RIGHTBUTTON,
           pt.x, pt.y, 0, hWnd, NULL
    mov ebx, eax
    INVOKE DestroyMenu, hMenu
    cmp ebx, IDM_TRAY_OPEN
    je  Open
    cmp ebx, IDM_TRAY_TIMER
    jne @F
    INVOKE TimerStartPause
    ret
@@: cmp ebx, IDM_TRAY_MINI
    jne @F
    INVOKE ToggleMiniTimer
    ret
@@: cmp ebx, IDM_TRAY_EXIT
    jne @F
    INVOKE SendMessageA, hMainWnd, WM_CLOSE, 0, 0
@@: ret
TrayCallback ENDP

;---------------------------------------------------------------------
; PlayChime - plays one of the chimes (if sounds are on)
;---------------------------------------------------------------------
PlayChime PROC USES esi, kind:DWORD
    cmp userData.soundOn, 0
    je  Done
    mov eax, kind
    mov esi, chimeTable[eax*4]
NoteLoop:
    mov eax, [esi]
    cmp eax, 0
    je  Done
    INVOKE Beep, eax, DWORD PTR [esi + 4]
    add esi, 8
    jmp NoteLoop
Done:
    ret
PlayChime ENDP

;---------------------------------------------------------------------
; NotifyDueDeadlines - after login: "Quiz 3 is due tomorrow."
;---------------------------------------------------------------------
NotifyDueDeadlines PROC USES ebx ecx esi edi
    LOCAL today:DWORD, count:DWORD, first:DWORD, firstDays:DWORD

    INVOKE TodayDay
    mov today, eax
    mov count, 0
    mov first, 0
    mov esi, OFFSET userData.deadlines
    mov ecx, userData.deadlineCount
    jecxz Check
DlLoop:
    cmp (DEADLINE PTR [esi]).isDone, 0
    jne Next
    mov eax, (DEADLINE PTR [esi]).dueDay
    sub eax, today
    cmp eax, 0
    jl  Next                        ; overdue items are on the Deadlines screen
    cmp eax, 1
    jg  Next
    inc count
    cmp first, 0
    jne Next
    mov first, esi                  ; list is sorted: the first is the soonest
    mov firstDays, eax
Next:
    add esi, SIZEOF DEADLINE
    loop DlLoop
Check:
    cmp count, 0
    je  Done
    mov esi, first
    mov edx, OFFSET szFmtDueToday
    cmp firstDays, 0
    je  @F
    mov edx, OFFSET szFmtDueTmrw
@@: INVOKE wsprintf, ADDR dueBuf, edx, ADDR (DEADLINE PTR [esi]).dtitle
    mov eax, count
    dec eax
    cmp eax, 0
    je  @F
    INVOKE wsprintf, ADDR dueBuf2, ADDR szFmtDueMore, eax
    INVOKE StrAppend, ADDR dueBuf, ADDR dueBuf2
@@: INVOKE TrayNotify, ADDR szDueTitle, ADDR dueBuf
Done:
    ret
NotifyDueDeadlines ENDP

END
