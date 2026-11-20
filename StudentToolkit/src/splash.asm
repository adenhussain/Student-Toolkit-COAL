;=====================================================================
; splash.asm  -  start-up splash screen
;
;   +------------------------------------------+
;   |               (graduation cap)            |
;   |            Student Toolkit_               |   <- typed letter by
;   |   CGPA planner and smart study planner    |      letter
;   |   [=================            ]  72%    |   <- loading bar
;   |   Preparing the study planner...          |
;   +------------------------------------------+
;
; A borderless popup (WS_POPUP) with rounded corners. A Windows timer
; ticks every 30 ms: the first ticks reveal the title one character
; at a time, then the bar fills. After about 2 seconds (or a click)
; the splash closes and the login window opens.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

SplashProc      PROTO :DWORD, :DWORD, :DWORD, :DWORD
SplashPaint     PROTO :DWORD
SplashFinish    PROTO

SPLASH_W        = 540
SPLASH_H        = 330
SPLASH_TICKS    = 70            ; 70 x 30 ms = about 2 seconds
TYPE_TICKS      = 2             ; one more letter every 2 ticks
TIMER_SPLASH    = 3
GLYPH_CAP       = 0E7BEh

.data
hSplash     DWORD 0
splashTick  DWORD 0
szSplashClass BYTE "STKSplash", 0
szSplashTitle BYTE "Student Toolkit", 0
szSplashSub BYTE "CGPA planner and smart study planner  |  x86 assembly", 0
szStep0     BYTE "Loading your courses...", 0
szStep1     BYTE "Reading the grading table...", 0
szStep2     BYTE "Preparing the study planner...", 0
szStep3     BYTE "Waking up the Pomodoro timer...", 0
szStep4     BYTE "Ready!", 0
splashSteps DWORD OFFSET szStep0, OFFSET szStep1, OFFSET szStep2, OFFSET szStep3, OFFSET szStep4
szFmtPct    BYTE "%d%%", 0
typed       BYTE 32 DUP(0)
pctBuf      BYTE 16 DUP(0)

.code
;---------------------------------------------------------------------
; ShowSplash - registers the class and opens the splash in the centre
;---------------------------------------------------------------------
ShowSplash PROC USES ebx esi edi
    LOCAL wc:WNDCLASSEX

    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.style, 0
    mov wc.lpfnWndProc, OFFSET SplashProc
    mov wc.cbClsExtra, 0
    mov wc.cbWndExtra, 0
    mov eax, hInstance
    mov wc.hInstance, eax
    INVOKE LoadIconA, hInstance, IDI_APPICON
    mov wc.hIcon, eax
    mov wc.hIconSm, eax
    INVOKE LoadCursorA, NULL, IDC_ARROW
    mov wc.hCursor, eax
    mov wc.hbrBackground, NULL
    mov wc.lpszMenuName, NULL
    mov wc.lpszClassName, OFFSET szSplashClass
    INVOKE RegisterClassExA, ADDR wc

    INVOKE ScaleDpi, SPLASH_W
    mov esi, eax
    INVOKE ScaleDpi, SPLASH_H
    mov edi, eax
    INVOKE GetSystemMetrics, SM_CXSCREEN
    sub eax, esi
    sar eax, 1
    mov ebx, eax
    INVOKE GetSystemMetrics, SM_CYSCREEN
    sub eax, edi
    sar eax, 1
    INVOKE CreateWindowExA, WS_EX_TOPMOST, ADDR szSplashClass, ADDR szSplashTitle,
           WS_POPUP, ebx, eax, esi, edi, NULL, NULL, hInstance, NULL
    mov hSplash, eax
    ; rounded corners
    INVOKE ScaleDpi, 36
    inc esi
    inc edi
    INVOKE CreateRoundRectRgn, 0, 0, esi, edi, eax, eax
    INVOKE SetWindowRgn, hSplash, eax, TRUE
    mov splashTick, 0
    INVOKE ShowWindow, hSplash, SW_SHOW
    INVOKE UpdateWindow, hSplash
    INVOKE SetTimer, hSplash, TIMER_SPLASH, 30, NULL
    ret
ShowSplash ENDP

;---------------------------------------------------------------------
; SplashFinish - close the splash, open the login window
;---------------------------------------------------------------------
SplashFinish PROC
    cmp hSplash, 0
    je  @F
    INVOKE KillTimer, hSplash, TIMER_SPLASH
    INVOKE DestroyWindow, hSplash
    mov hSplash, 0
    INVOKE ShowLoginWindow
@@: ret
SplashFinish ENDP

;---------------------------------------------------------------------
; SplashPaint
;---------------------------------------------------------------------
SplashPaint PROC USES ebx esi edi, hWnd:DWORD
    LOCAL ps:PAINTSTRUCT, rc:RECT, r:RECT, memDC:DWORD, hBmp:DWORD, oldBmp:DWORD,
          letters:DWORD, pct:DWORD, barX1:DWORD, barX2:DWORD, barY1:DWORD, barY2:DWORD

    INVOKE BeginPaint, hWnd, ADDR ps
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE CreateCompatibleDC, ps.hdc
    mov memDC, eax
    INVOKE CreateCompatibleBitmap, ps.hdc, rc.right, rc.bottom
    mov hBmp, eax
    INVOKE SelectObject, memDC, hBmp
    mov oldBmp, eax

    ; background: lavender edge, white card
    INVOKE FillSolid, memDC, ADDR rc, curTheme.clrSideActive
    INVOKE ScaleDpi, 6
    mov ecx, rc.right
    sub ecx, eax
    mov edx, rc.bottom
    sub edx, eax
    INVOKE FillRound, memDC, eax, eax, ecx, edx, 16, curTheme.clrCard, curTheme.clrCard

    ; logo
    mov r.left, 0
    mov eax, rc.right
    mov r.right, eax
    INVOKE ScaleDpi, 44
    mov r.top, eax
    INVOKE ScaleDpi, 104
    mov r.bottom, eax
    INVOKE DrawGlyph, memDC, GLYPH_CAP, ADDR r, hFontLogo, curTheme.clrSideActText,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE

    ; title typed letter by letter (with a cursor bar while typing)
    mov eax, splashTick
    xor edx, edx
    mov ecx, TYPE_TICKS
    div ecx
    mov letters, eax
    INVOKE Str_length, ADDR szSplashTitle
    cmp letters, eax
    jbe @F
    mov letters, eax
@@: mov ecx, letters
    mov esi, OFFSET szSplashTitle
    mov edi, OFFSET typed
    cld
    rep movsb                       ; copy the first 'letters' characters
    INVOKE Str_length, ADDR szSplashTitle
    cmp letters, eax
    jae @F
    mov BYTE PTR [edi], '_'         ; typing cursor
    inc edi
@@: mov BYTE PTR [edi], 0
    INVOKE ScaleDpi, 108
    mov r.top, eax
    INVOKE ScaleDpi, 152
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR typed, ADDR r, hFontTitle, curTheme.clrText,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, 152
    mov r.top, eax
    INVOKE ScaleDpi, 178
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR szSplashSub, ADDR r, hFontSmall, curTheme.clrMuted,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE

    ; loading bar
    mov eax, splashTick
    imul eax, eax, 100
    xor edx, edx
    mov ecx, SPLASH_TICKS
    div ecx
    cmp eax, 100
    jbe @F
    mov eax, 100
@@: mov pct, eax
    INVOKE ScaleDpi, 70
    mov barX1, eax
    mov ecx, rc.right
    sub ecx, eax
    mov barX2, ecx
    INVOKE ScaleDpi, 216
    mov barY1, eax
    INVOKE ScaleDpi, 228
    mov barY2, eax
    INVOKE FillRound, memDC, barX1, barY1, barX2, barY2, 6, curTheme.clrBg, curTheme.clrBorder
    mov eax, barX2
    sub eax, barX1
    mul pct
    mov ecx, 100
    div ecx
    cmp eax, 12
    jb  NoFill
    add eax, barX1
    INVOKE FillRound, memDC, barX1, barY1, eax, barY2, 6, curTheme.clrAccent, curTheme.clrAccent
NoFill:
    ; step text and percent
    mov eax, barX1
    mov r.left, eax
    mov eax, barX2
    mov r.right, eax
    INVOKE ScaleDpi, 236
    mov r.top, eax
    INVOKE ScaleDpi, 262
    mov r.bottom, eax
    mov eax, pct
    xor edx, edx
    mov ecx, 25
    div ecx                         ; step 0..4
    mov ecx, splashSteps[eax*4]     ; (ADDR r below uses EAX)
    INVOKE DrawTextIn, memDC, ecx, ADDR r, hFontSmall, curTheme.clrMuted,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE wsprintf, ADDR pctBuf, ADDR szFmtPct, pct
    INVOKE DrawTextIn, memDC, ADDR pctBuf, ADDR r, hFontSmall, curTheme.clrSideActText,
           DT_RIGHT OR DT_VCENTER OR DT_SINGLELINE

    INVOKE BitBlt, ps.hdc, 0, 0, rc.right, rc.bottom, memDC, 0, 0, SRCCOPY
    INVOKE SelectObject, memDC, oldBmp
    INVOKE DeleteObject, hBmp
    INVOKE DeleteDC, memDC
    INVOKE EndPaint, hWnd, ADDR ps
    ret
SplashPaint ENDP

;---------------------------------------------------------------------
; SplashProc
;---------------------------------------------------------------------
SplashProc PROC hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    cmp uMsg, WM_ERASEBKGND
    je  OnErase
    cmp uMsg, WM_PAINT
    je  OnPaint
    cmp uMsg, WM_TIMER
    je  OnTimer
    cmp uMsg, WM_LBUTTONDOWN
    je  OnClick
    INVOKE DefWindowProcA, hWnd, uMsg, wParam, lParam
    ret
OnErase:
    mov eax, 1
    ret
OnPaint:
    INVOKE SplashPaint, hWnd
    xor eax, eax
    ret
OnTimer:
    inc splashTick
    cmp splashTick, SPLASH_TICKS + 8    ; short pause on 100%
    jae OnClick
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    xor eax, eax
    ret
OnClick:                                ; a click skips the splash
    INVOKE SplashFinish
    xor eax, eax
    ret
SplashProc ENDP

END
