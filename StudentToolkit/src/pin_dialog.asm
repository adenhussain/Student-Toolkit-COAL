;=====================================================================
; pin_dialog.asm  -  "Change PIN" popup (opened from Settings)
;
;   Current PIN       [ **** ]
;   New PIN [ **** ]  |  Confirm new PIN [ **** ]
;                              [Cancel] [Change PIN]
;
; Checks, in order:
;   1. new PIN is 4 to 6 digits          (IsValidPin, login.asm)
;   2. new PIN and confirm PIN match     (byte-by-byte compare)
;   3. new PIN differs from the current one
;   4. current PIN is right              (ChangePin, data.asm)
; ChangePin then makes a new key from the new PIN and encrypts the
; whole save file again. The typed PINs are wiped from memory after.
; Same behaviour as the other popups: modal, Enter = OK, Esc = Cancel.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

PinDlgProc      PROTO :DWORD, :DWORD, :DWORD, :DWORD
ClosePinDialog  PROTO
LayoutPinDialog PROTO :DWORD
PaintPinDialog  PROTO :DWORD
SubmitPin       PROTO
PdError         PROTO :DWORD, :DWORD
SameText        PROTO :DWORD, :DWORD
WipePinBufs     PROTO

PDLG_STYLE      = WS_POPUP OR WS_CAPTION OR WS_SYSMENU OR WS_CLIPCHILDREN
IDC_PD_OLD      = 4501
IDC_PD_NEW      = 4502
IDC_PD_CONFIRM  = 4503

; layout at 100% scale
PD_WIDTH        = 480
PD_PAD          = 32
PD_ROW0         = 100           ; current PIN
PD_ROW1         = 174           ; new PIN + confirm
PD_LABEL_H      = 20
PD_BOX_OFF      = 24
PD_BOX_H        = 40
PD_EDIT_H       = 22
PD_BTN_TOP      = PD_ROW1 + 74 + 26
PD_BTN_H        = 42
PD_HEIGHT       = PD_BTN_TOP + PD_BTN_H + 26

.data
hPinDlg         DWORD 0
pdFocus         DWORD -1        ; 0 / 1 / 2 = focused box, -1 = none
hPdBrush        DWORD 0
hPdOld          DWORD 0
hPdNew          DWORD 0
hPdConfirm      DWORD 0
hPdOk           DWORD 0
hPdCancel       DWORD 0
pdError         BYTE 128 DUP(0)
pdOldBuf        BYTE 16 DUP(0)
pdNewBuf        BYTE 16 DUP(0)
pdConfirmBuf    BYTE 16 DUP(0)

szPdClass       BYTE "STKPinDialog", 0
szPdCaption     BYTE "Change PIN", 0
szPdSub         BYTE "Your data file is encrypted again with the new PIN.", 0
szPdLblOld      BYTE "Current PIN", 0
szPdLblNew      BYTE "New PIN  (4 to 6 digits)", 0
szPdLblConfirm  BYTE "Confirm new PIN", 0
szPdOk          BYTE "Change PIN", 0
szPdCancel      BYTE "Cancel", 0
szPdErrNew      BYTE "The new PIN must be 4 to 6 digits.", 0
szPdErrMatch    BYTE "The two new PINs don't match.", 0
szPdErrSame     BYTE "The new PIN is the same as the current one.", 0
szPdErrOld      BYTE "The current PIN is wrong.", 0
szPdErrSave     BYTE "Could not save the file. Your PIN was not changed.", 0
szPdDone        BYTE "Your PIN was changed.", 13, 10, 13, 10
                BYTE "Use the new PIN the next time you log in.", 0
szLogPin        BYTE "PIN changed", 0

.code
;---------------------------------------------------------------------
; RegisterPinDialog
;---------------------------------------------------------------------
RegisterPinDialog PROC
    LOCAL wc:WNDCLASSEX

    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.style, CS_HREDRAW OR CS_VREDRAW
    mov wc.lpfnWndProc, OFFSET PinDlgProc
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
    mov wc.lpszClassName, OFFSET szPdClass
    INVOKE RegisterClassExA, ADDR wc
    ret
RegisterPinDialog ENDP

;---------------------------------------------------------------------
; OpenPinDialog - centred over the main window, modal
;---------------------------------------------------------------------
OpenPinDialog PROC USES ebx esi edi
    LOCAL r:RECT, mainR:RECT

    cmp hPinDlg, 0
    jne Done
    mov pdFocus, -1
    mov pdError, 0

    mov r.left, 0
    mov r.top, 0
    INVOKE ScaleDpi, PD_WIDTH
    mov r.right, eax
    INVOKE ScaleDpi, PD_HEIGHT
    mov r.bottom, eax
    INVOKE AdjustWindowRectEx, ADDR r, PDLG_STYLE, FALSE, 0
    mov esi, r.right
    sub esi, r.left
    mov edi, r.bottom
    sub edi, r.top

    INVOKE GetWindowRect, hMainWnd, ADDR mainR
    mov ebx, mainR.left
    add ebx, mainR.right
    sub ebx, esi
    sar ebx, 1
    mov eax, mainR.top
    add eax, mainR.bottom
    sub eax, edi
    sar eax, 1
    jns @F
    xor eax, eax
@@: INVOKE CreateWindowExA, 0, ADDR szPdClass, ADDR szPdCaption, PDLG_STYLE,
           ebx, eax, esi, edi, hMainWnd, NULL, hInstance, NULL
    mov hPinDlg, eax
    mov hActiveDialog, eax

    INVOKE EnableWindow, hMainWnd, FALSE
    INVOKE ShowWindow, hPinDlg, SW_SHOW
    INVOKE UpdateWindow, hPinDlg
    INVOKE SetFocus, hPdOld
Done:
    ret
OpenPinDialog ENDP

;---------------------------------------------------------------------
; ClosePinDialog
;---------------------------------------------------------------------
ClosePinDialog PROC
    cmp hPinDlg, 0
    je  @F
    INVOKE WipePinBufs
    INVOKE EnableWindow, hMainWnd, TRUE
    INVOKE SetForegroundWindow, hMainWnd
    INVOKE DestroyWindow, hPinDlg
@@: ret
ClosePinDialog ENDP

;---------------------------------------------------------------------
; WipePinBufs - overwrites the typed PINs in memory with zeros
;---------------------------------------------------------------------
WipePinBufs PROC USES ecx edi
    mov edi, OFFSET pdOldBuf        ; the three buffers sit next to each other
    mov ecx, SIZEOF pdOldBuf * 3
    xor eax, eax
    cld
    rep stosb
    ret
WipePinBufs ENDP

;---------------------------------------------------------------------
; SameText - are two strings equal?  Returns: EAX = 1 / 0
;---------------------------------------------------------------------
SameText PROC USES esi edi, pA:DWORD, pB:DWORD
    mov esi, pA
    mov edi, pB
NextChar:
    mov al, [esi]
    cmp al, [edi]
    jne Different
    cmp al, 0
    je  Equal                       ; both ended together
    inc esi
    inc edi
    jmp NextChar
Equal:
    mov eax, 1
    ret
Different:
    xor eax, eax
    ret
SameText ENDP

;---------------------------------------------------------------------
; PdError - red message, cursor to the field
;---------------------------------------------------------------------
PdError PROC pMsg:DWORD, hField:DWORD
    INVOKE Str_copy, pMsg, ADDR pdError
    INVOKE InvalidateRect, hPinDlg, NULL, FALSE
    INVOKE MessageBeep, MB_OK
    INVOKE SetFocus, hField
    INVOKE SendMessageA, hField, EM_SETSEL, 0, -1   ; select it to retype
    ret
PdError ENDP

;---------------------------------------------------------------------
; SubmitPin - runs the checks, then changes the PIN
;---------------------------------------------------------------------
SubmitPin PROC
    INVOKE GetWindowTextA, hPdOld, ADDR pdOldBuf, SIZEOF pdOldBuf
    INVOKE GetWindowTextA, hPdNew, ADDR pdNewBuf, SIZEOF pdNewBuf
    INVOKE GetWindowTextA, hPdConfirm, ADDR pdConfirmBuf, SIZEOF pdConfirmBuf

    INVOKE IsValidPin, ADDR pdOldBuf
    test eax, eax
    jz  OldWrong                    ; a badly formed PIN can't be right
    INVOKE IsValidPin, ADDR pdNewBuf
    test eax, eax
    jnz @F
    INVOKE PdError, ADDR szPdErrNew, hPdNew
    jmp Finish
@@: INVOKE SameText, ADDR pdNewBuf, ADDR pdConfirmBuf
    test eax, eax
    jnz @F
    INVOKE PdError, ADDR szPdErrMatch, hPdConfirm
    jmp Finish
@@: INVOKE SameText, ADDR pdNewBuf, ADDR pdOldBuf
    test eax, eax
    jz  @F
    INVOKE PdError, ADDR szPdErrSame, hPdNew
    jmp Finish

@@: INVOKE ChangePin, ADDR pdOldBuf, ADDR pdNewBuf
    cmp eax, 1
    je  Changed
    cmp eax, 2
    jne OldWrong
    INVOKE PdError, ADDR szPdErrSave, hPdOld
    jmp Finish
OldWrong:
    INVOKE PdError, ADDR szPdErrOld, hPdOld
    jmp Finish

Changed:
    INVOKE LogEvent, ADDR szLogPin
    INVOKE MessageBoxA, hPinDlg, ADDR szPdDone, ADDR szPdCaption, MB_OK OR MB_ICONINFORMATION
    INVOKE ClosePinDialog
    ret
Finish:
    INVOKE WipePinBufs
    ret
SubmitPin ENDP

;---------------------------------------------------------------------
; LayoutPinDialog - places every control
;---------------------------------------------------------------------
LayoutPinDialog PROC USES ebx esi edi, hWnd:DWORD
    LOCAL rc:RECT, edgeL:DWORD, edgeR:DWORD, mid:DWORD, gap:DWORD,
          inset:DWORD, editH:DWORD, posY:DWORD, boxH:DWORD

    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE ScaleDpi, PD_PAD
    mov edgeL, eax
    mov ecx, rc.right
    sub ecx, eax
    mov edgeR, ecx
    add eax, ecx
    shr eax, 1
    mov mid, eax
    INVOKE ScaleDpi, 8
    mov gap, eax
    INVOKE ScaleDpi, 12
    mov inset, eax
    INVOKE ScaleDpi, PD_EDIT_H
    mov editH, eax

    ; current PIN (left half)
    INVOKE ScaleDpi, PD_ROW0 + PD_BOX_OFF + (PD_BOX_H - PD_EDIT_H) / 2
    mov posY, eax
    mov ebx, edgeL
    add ebx, inset
    mov esi, mid                    ; esi = width of a left-half text box
    sub esi, gap                    ; (ECX would be lost: API calls may
    sub esi, ebx                    ;  change EAX, ECX and EDX)
    sub esi, inset
    INVOKE MoveWindow, hPdOld, ebx, posY, esi, editH, TRUE

    ; new PIN (left half) and confirm (right half)
    INVOKE ScaleDpi, PD_ROW1 + PD_BOX_OFF + (PD_BOX_H - PD_EDIT_H) / 2
    mov posY, eax
    INVOKE MoveWindow, hPdNew, ebx, posY, esi, editH, TRUE
    mov ebx, mid
    add ebx, gap
    add ebx, inset
    mov ecx, edgeR
    sub ecx, ebx
    sub ecx, inset
    INVOKE MoveWindow, hPdConfirm, ebx, posY, ecx, editH, TRUE

    ; buttons, right-aligned
    INVOKE ScaleDpi, PD_BTN_TOP
    mov posY, eax
    INVOKE ScaleDpi, PD_BTN_H
    mov boxH, eax
    INVOKE ScaleDpi, PD_PAD + 150
    mov ebx, rc.right
    sub ebx, eax
    INVOKE ScaleDpi, 150
    INVOKE MoveWindow, hPdOk, ebx, posY, eax, boxH, TRUE
    INVOKE ScaleDpi, 12 + 110
    sub ebx, eax
    INVOKE ScaleDpi, 110
    INVOKE MoveWindow, hPdCancel, ebx, posY, eax, boxH, TRUE
    ret
LayoutPinDialog ENDP

;---------------------------------------------------------------------
; PaintPinDialog - heading, labels, boxes, error
;---------------------------------------------------------------------
PaintPinDialog PROC USES ebx esi edi, hWnd:DWORD
    LOCAL ps:PAINTSTRUCT, rc:RECT, r:RECT, memDC:DWORD, hBmp:DWORD,
          oldBmp:DWORD, edgeL:DWORD, edgeR:DWORD, mid:DWORD, gap:DWORD,
          focused:DWORD, boxT:DWORD, boxB:DWORD

    INVOKE BeginPaint, hWnd, ADDR ps
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE CreateCompatibleDC, ps.hdc
    mov memDC, eax
    INVOKE CreateCompatibleBitmap, ps.hdc, rc.right, rc.bottom
    mov hBmp, eax
    INVOKE SelectObject, memDC, hBmp
    mov oldBmp, eax
    INVOKE FillSolid, memDC, ADDR rc, curTheme.clrCard

    INVOKE ScaleDpi, PD_PAD
    mov edgeL, eax
    mov ecx, rc.right
    sub ecx, eax
    mov edgeR, ecx
    add eax, ecx
    shr eax, 1
    mov mid, eax
    INVOKE ScaleDpi, 8
    mov gap, eax

    ; heading
    mov eax, edgeL
    mov r.left, eax
    mov eax, edgeR
    mov r.right, eax
    INVOKE ScaleDpi, 22
    mov r.top, eax
    INVOKE ScaleDpi, 58
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR szPdCaption, ADDR r, hFontTitle, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, 58
    mov r.top, eax
    INVOKE ScaleDpi, 82
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR szPdSub, ADDR r, hFontSmall, curTheme.clrMuted,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS

    ; labels
    mov eax, mid
    sub eax, gap
    mov r.right, eax
    INVOKE ScaleDpi, PD_ROW0
    mov r.top, eax
    INVOKE ScaleDpi, PD_ROW0 + PD_LABEL_H
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR szPdLblOld, ADDR r, hFontSmall, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, PD_ROW1
    mov r.top, eax
    INVOKE ScaleDpi, PD_ROW1 + PD_LABEL_H
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR szPdLblNew, ADDR r, hFontSmall, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS
    mov eax, mid
    add eax, gap
    mov r.left, eax
    mov eax, edgeR
    mov r.right, eax
    INVOKE DrawTextIn, memDC, ADDR szPdLblConfirm, ADDR r, hFontSmall, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS

    ; field boxes: current (left, row 0), new (left, row 1), confirm (right, row 1)
    mov esi, mid
    sub esi, gap                    ; right edge of a left-half box
    mov focused, 0
    cmp pdFocus, 0
    jne @F
    mov focused, 1
@@: INVOKE ScaleDpi, PD_ROW0 + PD_BOX_OFF
    mov boxT, eax
    INVOKE ScaleDpi, PD_ROW0 + PD_BOX_OFF + PD_BOX_H
    mov boxB, eax
    INVOKE DrawFieldBox, memDC, edgeL, boxT, esi, boxB, focused

    INVOKE ScaleDpi, PD_ROW1 + PD_BOX_OFF
    mov boxT, eax
    INVOKE ScaleDpi, PD_ROW1 + PD_BOX_OFF + PD_BOX_H
    mov boxB, eax
    mov focused, 0
    cmp pdFocus, 1
    jne @F
    mov focused, 1
@@: INVOKE DrawFieldBox, memDC, edgeL, boxT, esi, boxB, focused
    mov focused, 0
    cmp pdFocus, 2
    jne @F
    mov focused, 1
@@: mov edi, mid
    add edi, gap
    INVOKE DrawFieldBox, memDC, edi, boxT, edgeR, boxB, focused

    ; error
    cmp pdError, 0
    je  NoError
    mov r.left, 0
    mov eax, rc.right
    mov r.right, eax
    INVOKE ScaleDpi, PD_BTN_TOP - 28
    mov r.top, eax
    INVOKE ScaleDpi, PD_BTN_TOP - 4
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR pdError, ADDR r, hFontSmall, CLR_DANGER_TX,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
NoError:
    INVOKE BitBlt, ps.hdc, 0, 0, rc.right, rc.bottom, memDC, 0, 0, SRCCOPY
    INVOKE SelectObject, memDC, oldBmp
    INVOKE DeleteObject, hBmp
    INVOKE DeleteDC, memDC
    INVOKE EndPaint, hWnd, ADDR ps
    ret
PaintPinDialog ENDP

;---------------------------------------------------------------------
; PinDlgProc - messages for the Change PIN popup
;---------------------------------------------------------------------
PinDlgProc PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    cmp uMsg, WM_CREATE
    je  OnCreate
    cmp uMsg, WM_ERASEBKGND
    je  OnErase
    cmp uMsg, WM_PAINT
    je  OnPaint
    cmp uMsg, WM_CTLCOLOREDIT
    je  OnFieldColor
    cmp uMsg, WM_DRAWITEM
    je  OnDrawItem
    cmp uMsg, WM_COMMAND
    je  OnCommand
    cmp uMsg, WM_CLOSE
    je  OnClose
    cmp uMsg, WM_DESTROY
    je  OnDestroy
    INVOKE DefWindowProcA, hWnd, uMsg, wParam, lParam
    ret

OnCreate:
    INVOKE CreateSolidBrush, curTheme.clrCard
    mov hPdBrush, eax
    INVOKE CreateField, hWnd, IDC_PD_OLD, ES_PASSWORD OR ES_NUMBER, PIN_MAX
    mov hPdOld, eax
    INVOKE CreateField, hWnd, IDC_PD_NEW, ES_PASSWORD OR ES_NUMBER, PIN_MAX
    mov hPdNew, eax
    INVOKE CreateField, hWnd, IDC_PD_CONFIRM, ES_PASSWORD OR ES_NUMBER, PIN_MAX
    mov hPdConfirm, eax
    INVOKE CreatePastelButton, hWnd, ADDR szPdOk, IDOK, BTN_PRIMARY
    mov hPdOk, eax
    INVOKE CreatePastelButton, hWnd, ADDR szPdCancel, IDCANCEL, BTN_SECONDARY
    mov hPdCancel, eax
    INVOKE LayoutPinDialog, hWnd
    xor eax, eax
    ret

OnErase:
    mov eax, 1
    ret

OnPaint:
    INVOKE PaintPinDialog, hWnd
    xor eax, eax
    ret

OnFieldColor:
    INVOKE GdiSetTextColor, wParam, curTheme.clrText
    INVOKE SetBkColor, wParam, curTheme.clrCard
    mov eax, hPdBrush
    ret

OnDrawItem:
    INVOKE DrawPastelButton, lParam, curTheme.clrCard
    mov eax, TRUE
    ret

OnCommand:
    mov eax, wParam
    mov ebx, eax
    and eax, 0FFFFh
    shr ebx, 16
    cmp eax, IDOK
    jne @F
    INVOKE SubmitPin
    jmp CommandDone
@@: cmp eax, IDCANCEL
    jne @F
    INVOKE ClosePinDialog
    jmp CommandDone
@@: ; which box got / lost the focus?  field number = id - IDC_PD_OLD
    cmp eax, IDC_PD_OLD
    jb  CommandDone
    cmp eax, IDC_PD_CONFIRM
    ja  CommandDone
    lea ecx, [eax - IDC_PD_OLD]
    cmp ebx, EN_SETFOCUS
    jne @F
    mov pdFocus, ecx
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp CommandDone
@@: cmp ebx, EN_KILLFOCUS
    jne CommandDone
    cmp ecx, pdFocus
    jne CommandDone
    mov pdFocus, -1
    INVOKE InvalidateRect, hWnd, NULL, FALSE
CommandDone:
    xor eax, eax
    ret

OnClose:
    INVOKE ClosePinDialog
    xor eax, eax
    ret

OnDestroy:
    INVOKE DeleteObject, hPdBrush
    mov hPinDlg, 0
    mov eax, hWnd
    cmp eax, hActiveDialog
    jne @F
    mov hActiveDialog, 0
@@: xor eax, eax
    ret
PinDlgProc ENDP

END
