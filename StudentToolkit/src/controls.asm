;=====================================================================
; controls.asm  -  reusable pastel controls for every screen
;
;   CreatePastelButton / DrawPastelButton
;       Flat rounded buttons drawn by us (BS_OWNERDRAW), so they use
;       the theme colours instead of the grey Windows look.
;       Styles: BTN_PRIMARY (filled), BTN_LINK (text), BTN_SECONDARY.
;       Hover and pressed states make the colour slightly darker.
;
;   CreateField / DrawFieldBox
;       A text box without the Windows border; the parent window
;       draws a rounded box around it. The box border turns lavender
;       while the field has keyboard focus.
;
;   StrAppend, DarkenColor  -  small helpers
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

PastelBtnProc PROTO :DWORD, :DWORD, :DWORD, :DWORD

HOVER_BIT   = 1                     ; bit 0 of GWL_USERDATA = mouse is over it
SELECTED_BIT = 2                    ; bit 1 = chip is selected (BTN_CHIP)

.data
szBtnClass      BYTE "BUTTON", 0
szEditClass     BYTE "EDIT", 0
oldPastelProc   DWORD 0             ; Windows' own BUTTON handler

.code
;---------------------------------------------------------------------
; StrAppend - adds the string pSource to the end of pTarget
;---------------------------------------------------------------------
StrAppend PROC USES eax, pTarget:DWORD, pSource:DWORD
    INVOKE Str_length, pTarget      ; Irvine32: EAX = length
    add eax, pTarget                ; eax -> the terminating zero
    INVOKE Str_copy, pSource, eax
    ret
StrAppend ENDP

;---------------------------------------------------------------------
; DarkenColor - makes a colour darker by 'amount' on each channel.
; A COLORREF is 00BBGGRRh: we subtract from the red byte (AL), the
; green byte (AH), then rotate the blue byte into AL. A channel that
; would go below 0 stops at 0.
; Returns: EAX = darker colour
;---------------------------------------------------------------------
DarkenColor PROC USES ecx, color:DWORD, amount:DWORD
    mov eax, color
    mov ecx, amount
    sub al, cl                      ; red
    jnc @F
    xor al, al
@@: sub ah, cl                      ; green
    jnc @F
    xor ah, ah
@@: ror eax, 16                     ; blue is now in AL
    sub al, cl
    jnc @F
    xor al, al
@@: rol eax, 16                     ; put the bytes back in place
    ret
DarkenColor ENDP

;---------------------------------------------------------------------
; CreatePastelButton - creates an owner-drawn button
; Returns: EAX = button handle
;---------------------------------------------------------------------
CreatePastelButton PROC USES ebx, hParent:DWORD, pText:DWORD, ctlId:DWORD, btnStyle:DWORD
    INVOKE CreateWindowExA, 0, ADDR szBtnClass, pText,
           WS_CHILD OR WS_VISIBLE OR WS_TABSTOP OR BS_OWNERDRAW,
           0, 0, 0, 0, hParent, ctlId, hInstance, NULL
    mov ebx, eax
    ; style lives in GWL_USERDATA bits 8.., hover flag in bit 0
    mov eax, btnStyle
    shl eax, 8
    INVOKE SetWindowLongA, ebx, GWL_USERDATA, eax
    INVOKE SendMessageA, ebx, WM_SETFONT, hFontBody, FALSE
    INVOKE SetWindowLongA, ebx, GWL_WNDPROC, OFFSET PastelBtnProc
    mov oldPastelProc, eax
    mov eax, ebx
    ret
CreatePastelButton ENDP

;---------------------------------------------------------------------
; PastelBtnProc - hover tracking, hand cursor, no background erase
;---------------------------------------------------------------------
PastelBtnProc PROC USES ebx, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL tme:TRACKMOUSEEVENT

    cmp uMsg, WM_MOUSEMOVE
    je  OnMouseMove
    cmp uMsg, WM_MOUSELEAVE
    je  OnMouseLeave
    cmp uMsg, WM_SETCURSOR
    je  OnSetCursor
    cmp uMsg, WM_ERASEBKGND
    je  OnErase
    jmp PassOn

OnMouseMove:
    INVOKE GetWindowLongA, hWnd, GWL_USERDATA
    test eax, HOVER_BIT
    jnz PassOn                      ; already hovered
    or  eax, HOVER_BIT
    INVOKE SetWindowLongA, hWnd, GWL_USERDATA, eax
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    mov tme.cbSize, SIZEOF TRACKMOUSEEVENT
    mov tme.dwFlags, TME_LEAVE
    mov eax, hWnd
    mov tme.hwndTrack, eax
    mov tme.dwHoverTime, 0
    INVOKE TrackMouseEvent, ADDR tme
    jmp PassOn

OnMouseLeave:
    INVOKE GetWindowLongA, hWnd, GWL_USERDATA
    and eax, NOT HOVER_BIT
    INVOKE SetWindowLongA, hWnd, GWL_USERDATA, eax
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp PassOn

OnSetCursor:
    INVOKE LoadCursorA, NULL, IDC_HAND
    INVOKE SetCursor, eax
    mov eax, TRUE
    ret

OnErase:
    mov eax, 1
    ret

PassOn:
    INVOKE CallWindowProcA, oldPastelProc, hWnd, uMsg, wParam, lParam
    ret
PastelBtnProc ENDP

;---------------------------------------------------------------------
; DrawPastelButton - draws a pastel button (call from WM_DRAWITEM)
; Receives: pDis = DRAWITEMSTRUCT, parentBg = colour behind the button
;---------------------------------------------------------------------
DrawPastelButton PROC USES ebx esi edi, pDis:DWORD, parentBg:DWORD
    LOCAL rc:RECT, hdc:DWORD, btnStyle:DWORD, hovered:DWORD,
          fillColor:DWORD, lineColor:DWORD, textColor:DWORD,
          hFont:DWORD, btnText[64]:BYTE

    mov ebx, pDis
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).hDC
    mov hdc, eax
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).rcItem.left
    mov rc.left, eax
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).rcItem.top
    mov rc.top, eax
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).rcItem.right
    mov rc.right, eax
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).rcItem.bottom
    mov rc.bottom, eax

    INVOKE GetWindowLongA, (DRAWITEMSTRUCT PTR [ebx]).hwndItem, GWL_USERDATA
    mov edx, eax
    and edx, HOVER_BIT
    mov hovered, edx
    shr eax, 8
    mov btnStyle, eax
    INVOKE GetWindowTextA, (DRAWITEMSTRUCT PTR [ebx]).hwndItem, ADDR btnText, SIZEOF btnText

    ; corners show the parent's colour
    INVOKE FillSolid, hdc, ADDR rc, parentBg

    cmp btnStyle, BTN_LINK
    je  StyleLink
    cmp btnStyle, BTN_DANGER_LINK
    je  StyleLink
    cmp btnStyle, BTN_SECONDARY
    je  StyleSecondary
    cmp btnStyle, BTN_CHIP
    je  StyleChip
    cmp btnStyle, BTN_PICKER
    je  StyleSecondary              ; picker: secondary colours

    ; ---- primary: filled accent ----
    mov eax, curTheme.clrAccent
    mov fillColor, eax
    mov lineColor, eax
    mov eax, curTheme.clrAccentText
    mov textColor, eax
    mov eax, hFontBodyBold
    mov hFont, eax
    jmp ApplyStates

StyleChip:
    ; one choice out of a group (e.g. Quiz / Assignment / Exam / Lab)
    INVOKE GetWindowLongA, (DRAWITEMSTRUCT PTR [ebx]).hwndItem, GWL_USERDATA
    test eax, SELECTED_BIT
    jz  StyleSecondary              ; not selected: looks like secondary
    mov eax, curTheme.clrSideActive
    mov fillColor, eax
    mov lineColor, eax
    mov eax, curTheme.clrSideActText
    mov textColor, eax
    mov eax, hFontBodyBold
    mov hFont, eax
    jmp ApplyStates

StyleSecondary:
    mov eax, curTheme.clrCard
    mov fillColor, eax
    mov eax, curTheme.clrBorder
    mov lineColor, eax
    mov eax, curTheme.clrText
    mov textColor, eax
    mov eax, hFontBody
    mov hFont, eax
    jmp ApplyStates

StyleLink:
    mov eax, parentBg
    mov fillColor, eax
    mov lineColor, eax
    mov eax, curTheme.clrAccentText
    cmp btnStyle, BTN_DANGER_LINK
    jne @F
    mov eax, CLR_DANGER_TX          ; red text for "Delete"
@@: mov textColor, eax
    mov eax, hFontBody
    mov hFont, eax

ApplyStates:
    ; mouse over -> a little darker; pressed -> darker still
    mov esi, 0
    cmp hovered, 0
    je  @F
    mov esi, 12
@@: test (DRAWITEMSTRUCT PTR [ebx]).itemState, ODS_SELECTED
    jz  @F
    mov esi, 24
@@: cmp esi, 0
    je  NoShade
    INVOKE DarkenColor, fillColor, esi
    mov fillColor, eax
    cmp btnStyle, BTN_PRIMARY
    jne NoShade
    mov lineColor, eax
NoShade:
    ; keyboard focus (Tab key) -> visible outline
    test (DRAWITEMSTRUCT PTR [ebx]).itemState, ODS_FOCUS
    jz  @F
    mov eax, curTheme.clrSideActText
    mov lineColor, eax
@@:
    INVOKE FillRound, hdc, rc.left, rc.top, rc.right, rc.bottom, 10,
           fillColor, lineColor
    cmp btnStyle, BTN_PICKER
    je  PickerText
    INVOKE DrawTextIn, hdc, ADDR btnText, ADDR rc, hFont, textColor,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    ret

PickerText:
    ; text on the left, a small down arrow on the right
    INVOKE ScaleDpi, 12
    add rc.left, eax
    sub rc.right, eax
    INVOKE DrawGlyph, hdc, 0E70Dh, ADDR rc, hFontIcon, curTheme.clrMuted,
           DT_RIGHT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, 24
    sub rc.right, eax
    INVOKE DrawTextIn, hdc, ADDR btnText, ADDR rc, hFont, textColor,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS
    ret
DrawPastelButton ENDP

;---------------------------------------------------------------------
; SetChipSelected - turns the "selected" look of a chip on or off
;---------------------------------------------------------------------
SetChipSelected PROC hBtn:DWORD, selected:DWORD
    INVOKE GetWindowLongA, hBtn, GWL_USERDATA
    and eax, NOT SELECTED_BIT
    cmp selected, 0
    je  @F
    or  eax, SELECTED_BIT
@@: INVOKE SetWindowLongA, hBtn, GWL_USERDATA, eax
    INVOKE InvalidateRect, hBtn, NULL, FALSE
    ret
SetChipSelected ENDP

;---------------------------------------------------------------------
; CreateField - creates a borderless single-line text box
; extraStyle: ES_PASSWORD, ES_NUMBER, ES_LOWERCASE ...
; Returns: EAX = handle
;---------------------------------------------------------------------
CreateField PROC USES ebx, hParent:DWORD, ctlId:DWORD, extraStyle:DWORD, maxLen:DWORD
    mov eax, WS_CHILD OR WS_VISIBLE OR WS_TABSTOP OR ES_AUTOHSCROLL
    or  eax, extraStyle
    INVOKE CreateWindowExA, 0, ADDR szEditClass, NULL, eax,
           0, 0, 0, 0, hParent, ctlId, hInstance, NULL
    mov ebx, eax
    INVOKE SendMessageA, ebx, WM_SETFONT, hFontBody, FALSE
    INVOKE SendMessageA, ebx, EM_LIMITTEXT, maxLen, 0
    mov eax, ebx
    ret
CreateField ENDP

;---------------------------------------------------------------------
; DrawFieldBox - rounded box drawn around a text field
;---------------------------------------------------------------------
DrawFieldBox PROC hdc:DWORD, x1:DWORD, y1:DWORD, x2:DWORD, y2:DWORD, focused:DWORD
    mov eax, curTheme.clrBorder
    cmp focused, 0
    je  @F
    mov eax, curTheme.clrSideActText
@@: INVOKE FillRound, hdc, x1, y1, x2, y2, 10, curTheme.clrCard, eax
    ret
DrawFieldBox ENDP

END
