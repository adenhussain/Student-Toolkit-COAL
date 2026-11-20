;=====================================================================
; mini_timer.asm  -  small always-on-top timer window
;
;   +-----------------------------+
;   |  COAL                    x  |
;   |  24:13               ( || ) |
;   +-----------------------------+
;
; WS_EX_TOPMOST keeps it above every other window, so the student can
; study in a browser or PDF and still see the time. It has no title
; bar: dragging anywhere moves it (WM_NCHITTEST answers HTCAPTION),
; the round button starts / pauses, x closes it, and a double-click
; brings the main window back. Rounded corners come from a window
; region (CreateRoundRectRgn).
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

MiniProc        PROTO :DWORD, :DWORD, :DWORD, :DWORD
MiniPaint       PROTO :DWORD
MiniButtonRects PROTO :DWORD, :DWORD

MINI_W          = 250
MINI_H          = 86
GLYPH_PLAY      = 0E768h
GLYPH_PAUSE     = 0E769h
GLYPH_CLOSE     = 0E711h

.data
hMiniWnd    DWORD 0
szMiniClass BYTE "STKMiniTimer", 0
szMiniTitle BYTE "Student Toolkit timer", 0
miniBuf     BYTE 32 DUP(0)
playR       RECT <>             ; round play / pause button
closeR      RECT <>             ; small x

.code
;---------------------------------------------------------------------
; RegisterMiniTimer
;---------------------------------------------------------------------
RegisterMiniTimer PROC
    LOCAL wc:WNDCLASSEX
    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.style, CS_HREDRAW OR CS_VREDRAW
    mov wc.lpfnWndProc, OFFSET MiniProc
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
    mov wc.lpszClassName, OFFSET szMiniClass
    INVOKE RegisterClassExA, ADDR wc
    ret
RegisterMiniTimer ENDP

;---------------------------------------------------------------------
; ToggleMiniTimer - opens it near the bottom-right corner, or closes it
;---------------------------------------------------------------------
ToggleMiniTimer PROC USES ebx esi edi
    cmp hMiniWnd, 0
    je  OpenIt
    INVOKE CloseMiniTimer
    ret
OpenIt:
    INVOKE ScaleDpi, MINI_W
    mov esi, eax
    INVOKE ScaleDpi, MINI_H
    mov edi, eax
    INVOKE ScaleDpi, 24
    mov ebx, eax
    INVOKE GetSystemMetrics, SM_CXSCREEN
    sub eax, esi
    sub eax, ebx
    mov ebx, eax                    ; x = screen width - w - 24
    INVOKE GetSystemMetrics, SM_CYSCREEN
    sub eax, edi
    push eax
    INVOKE ScaleDpi, 80             ; stay above the taskbar
    mov ecx, eax
    pop eax
    sub eax, ecx                    ; y
    INVOKE CreateWindowExA, WS_EX_TOPMOST OR WS_EX_TOOLWINDOW,
           ADDR szMiniClass, ADDR szMiniTitle, WS_POPUP,
           ebx, eax, esi, edi, NULL, NULL, hInstance, NULL
    mov hMiniWnd, eax
    ; rounded corners
    INVOKE ScaleDpi, 28
    inc esi
    inc edi
    INVOKE CreateRoundRectRgn, 0, 0, esi, edi, eax, eax
    INVOKE SetWindowRgn, hMiniWnd, eax, TRUE
    INVOKE ShowWindow, hMiniWnd, SW_SHOW
    INVOKE UpdateWindow, hMiniWnd
    ret
ToggleMiniTimer ENDP

;---------------------------------------------------------------------
; CloseMiniTimer / RefreshMiniTimer
;---------------------------------------------------------------------
CloseMiniTimer PROC
    cmp hMiniWnd, 0
    je  @F
    INVOKE DestroyWindow, hMiniWnd
    mov hMiniWnd, 0
@@: ret
CloseMiniTimer ENDP

RefreshMiniTimer PROC
    cmp hMiniWnd, 0
    je  @F
    INVOKE InvalidateRect, hMiniWnd, NULL, FALSE
@@: ret
RefreshMiniTimer ENDP

;---------------------------------------------------------------------
; MiniButtonRects - where the play button and the x are
;---------------------------------------------------------------------
MiniButtonRects PROC USES ebx ecx edx, clientW:DWORD, clientH:DWORD
    ; play: 44px circle on the right, a little below the centre
    INVOKE ScaleDpi, 44
    mov ebx, eax                    ; size
    INVOKE ScaleDpi, 20
    mov ecx, clientW
    sub ecx, eax
    mov playR.right, ecx
    sub ecx, ebx
    mov playR.left, ecx
    mov eax, clientH
    sub eax, ebx
    shr eax, 1
    mov ecx, eax
    INVOKE ScaleDpi, 8
    add ecx, eax
    mov playR.top, ecx
    add ecx, ebx
    mov playR.bottom, ecx
    ; x: 20px square in the top-right corner
    INVOKE ScaleDpi, 8
    mov ecx, clientW
    sub ecx, eax
    mov closeR.right, ecx
    INVOKE ScaleDpi, 20
    mov ebx, eax
    sub ecx, ebx
    mov closeR.left, ecx
    INVOKE ScaleDpi, 6
    mov closeR.top, eax
    add eax, ebx
    mov closeR.bottom, eax
    ret
MiniButtonRects ENDP

;---------------------------------------------------------------------
; MiniPaint - course, time, play/pause button, x
;---------------------------------------------------------------------
MiniPaint PROC USES ebx esi edi, hWnd:DWORD
    LOCAL ps:PAINTSTRUCT, rc:RECT, r:RECT, memDC:DWORD, hBmp:DWORD, oldBmp:DWORD

    INVOKE BeginPaint, hWnd, ADDR ps
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE CreateCompatibleDC, ps.hdc
    mov memDC, eax
    INVOKE CreateCompatibleBitmap, ps.hdc, rc.right, rc.bottom
    mov hBmp, eax
    INVOKE SelectObject, memDC, hBmp
    mov oldBmp, eax

    ; card with a lavender edge
    INVOKE FillSolid, memDC, ADDR rc, curTheme.clrSideActText
    INVOKE FillRound, memDC, 1, 1, rc.right, rc.bottom, 14,
           curTheme.clrCard, curTheme.clrSideActive
    INVOKE MiniButtonRects, rc.right, rc.bottom

    ; course name
    INVOKE ScaleDpi, 18
    mov r.left, eax
    INVOKE ScaleDpi, 10
    mov r.top, eax
    INVOKE ScaleDpi, 32
    mov r.bottom, eax
    mov eax, closeR.left
    mov r.right, eax
    INVOKE TimerCourseName
    mov edx, eax                    ; (ADDR r below uses EAX)
    INVOKE DrawTextIn, memDC, edx, ADDR r, hFontSmall, curTheme.clrMuted,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS

    ; time
    INVOKE FormatTimeLeft, ADDR miniBuf
    mov eax, r.bottom
    mov r.top, eax
    mov eax, rc.bottom
    sub eax, 6
    mov r.bottom, eax
    mov eax, playR.left
    mov r.right, eax
    INVOKE DrawTextIn, memDC, ADDR miniBuf, ADDR r, hFontTitle, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE

    ; play / pause circle
    INVOKE FillRound, memDC, playR.left, playR.top, playR.right, playR.bottom, 22,
           curTheme.clrAccent, curTheme.clrAccent
    mov edx, GLYPH_PLAY
    cmp tmRunning, 0
    je  @F
    mov edx, GLYPH_PAUSE
@@: INVOKE DrawGlyph, memDC, edx, ADDR playR, hFontIcon, curTheme.clrAccentText,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    ; x
    INVOKE DrawGlyph, memDC, GLYPH_CLOSE, ADDR closeR, hFontIcon, curTheme.clrMuted,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE

    INVOKE BitBlt, ps.hdc, 0, 0, rc.right, rc.bottom, memDC, 0, 0, SRCCOPY
    INVOKE SelectObject, memDC, oldBmp
    INVOKE DeleteObject, hBmp
    INVOKE DeleteDC, memDC
    INVOKE EndPaint, hWnd, ADDR ps
    ret
MiniPaint ENDP

;---------------------------------------------------------------------
; MiniProc - messages for the mini timer
;---------------------------------------------------------------------
MiniProc PROC USES ebx, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL pt:POINT, rc:RECT

    cmp uMsg, WM_ERASEBKGND
    je  OnErase
    cmp uMsg, WM_PAINT
    je  OnPaint
    cmp uMsg, WM_NCHITTEST
    je  OnHitTest
    cmp uMsg, WM_LBUTTONDOWN
    je  OnClick
    cmp uMsg, WM_NCLBUTTONDBLCLK
    je  OnDoubleClick
    cmp uMsg, WM_DESTROY
    je  OnDestroy
    INVOKE DefWindowProcA, hWnd, uMsg, wParam, lParam
    ret

OnErase:
    mov eax, 1
    ret
OnPaint:
    INVOKE MiniPaint, hWnd
    xor eax, eax
    ret

OnHitTest:
    ; over a button -> normal client click; anywhere else -> drag
    mov eax, lParam
    movsx ecx, ax
    mov pt.x, ecx
    sar eax, 16
    mov pt.y, eax
    INVOKE ScreenToClient, hWnd, ADDR pt
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE MiniButtonRects, rc.right, rc.bottom
    mov eax, pt.x
    mov ecx, pt.y
    cmp eax, playR.left
    jl  CheckClose
    cmp eax, playR.right
    jg  CheckClose
    cmp ecx, playR.top
    jl  CheckClose
    cmp ecx, playR.bottom
    jg  CheckClose
    mov eax, HTCLIENT
    ret
CheckClose:
    cmp eax, closeR.left
    jl  Drag
    cmp eax, closeR.right
    jg  Drag
    cmp ecx, closeR.top
    jl  Drag
    cmp ecx, closeR.bottom
    jg  Drag
    mov eax, HTCLIENT
    ret
Drag:
    mov eax, HTCAPTION
    ret

OnClick:
    mov eax, lParam
    movsx ecx, ax
    sar eax, 16
    cmp ecx, playR.left
    jl  ClickClose
    cmp ecx, playR.right
    jg  ClickClose
    INVOKE TimerStartPause
    xor eax, eax
    ret
ClickClose:
    INVOKE CloseMiniTimer
    xor eax, eax
    ret

OnDoubleClick:
    INVOKE RestoreMain
    xor eax, eax
    ret

OnDestroy:
    mov hMiniWnd, 0
    xor eax, eax
    ret
MiniProc ENDP

END
