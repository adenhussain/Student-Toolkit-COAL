;=====================================================================
; login.asm  -  the login / create-account window
;
; Shown before the main window. Two modes:
;   Log in          : Username, PIN
;   Create account  : Your name, Username, PIN, Confirm PIN
;
; Rules checked before touching any file:
;   name      1-23 characters: letters, spaces, . - '
;   username  3-15 characters: a-z, 0-9, _   (becomes the file name)
;   PIN       4-6 digits
; Three wrong PINs in a row close the program (lockout).
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

LoginWndProc    PROTO :DWORD, :DWORD, :DWORD, :DWORD
SetLoginMode    PROTO :DWORD
LayoutLogin     PROTO :DWORD
PaintLogin      PROTO :DWORD
SubmitLogin     PROTO :DWORD
ShowError       PROTO :DWORD
GetLoginWindowSize PROTO :DWORD
IsValidName     PROTO :DWORD
IsValidUsername PROTO :DWORD

LOGIN_STYLE     = WS_CAPTION OR WS_SYSMENU OR WS_MINIMIZEBOX OR WS_CLIPCHILDREN

IDC_F_NAME      = 2001          ; fields 2001..2004
IDC_L_SWITCH    = 2005
FIELD_COUNT     = 4
F_NAME          = 0
F_USER          = 1
F_PIN           = 2
F_PIN2          = 3
MAX_TRIES       = 3

; layout in pixels at 100% scale
L_WIDTH         = 440           ; client width
L_CARD_M        = 24            ; space around the card
L_PAD           = 28            ; space inside the card
L_FIELD_TOP     = 188
L_FIELD_STEP    = 76
L_LABEL_H       = 20
L_BOX_OFF       = 24            ; box starts below its label
L_BOX_H         = 40
L_EDIT_H        = 22

.data
hLoginWnd   DWORD 0
loginMode   DWORD 0             ; 0 = log in, 1 = create account
loginOk     DWORD 0             ; 1 once a student has logged in
failCount   DWORD 0             ; wrong PINs so far
focusField  DWORD -1            ; field with keyboard focus, -1 = none
hBrushField DWORD 0

hField      DWORD FIELD_COUNT DUP(0)
hBtnMain    DWORD 0
hBtnSwitch  DWORD 0

fieldStyles DWORD 0                             ; name
            DWORD ES_LOWERCASE                  ; username
            DWORD ES_PASSWORD OR ES_NUMBER      ; PIN
            DWORD ES_PASSWORD OR ES_NUMBER      ; confirm PIN
fieldMax    DWORD NAME_LEN - 1, USER_LEN - 1, PIN_MAX, PIN_MAX

szLblName   BYTE "Your name", 0
szLblUser   BYTE "Username", 0
szLblPin    BYTE "PIN  (4 to 6 digits)", 0
szLblPin2   BYTE "Confirm PIN", 0
fieldLabels DWORD OFFSET szLblName, OFFSET szLblUser, OFFSET szLblPin, OFFSET szLblPin2

; which fields each mode shows, top to bottom
modeLoginList   DWORD F_USER, F_PIN
modeCreateList  DWORD F_NAME, F_USER, F_PIN, F_PIN2
; row and column of each listed field
;   column 0 = full width, 1 = left half, 2 = right half
modeLoginRow    DWORD 0, 1
modeLoginCol    DWORD 0, 0
modeCreateRow   DWORD 0, 1, 2, 2          ; PIN and Confirm PIN share row 2
modeCreateCol   DWORD 0, 0, 1, 2
LOGIN_ROWS      = 2
CREATE_ROWS     = 3

; results of FieldGeometry
fgLeft      DWORD 0             ; box left  (real pixels)
fgRight     DWORD 0             ; box right (real pixels)
fgTop       DWORD 0             ; field top (100% scale)

szLoginClass    BYTE "STKLogin", 0
szLoginCaption  BYTE "Student Toolkit", 0
szHeadTitle     BYTE "Student Toolkit", 0
szSubLogin      BYTE "Log in to your study planner", 0
szSubCreate     BYTE "Create your account", 0
szBtnLogin      BYTE "Log in", 0
szBtnCreate     BYTE "Create account", 0
szToCreate      BYTE "New here?  Create an account", 0
szToLogin       BYTE "Already have an account?  Log in", 0
szEmpty         BYTE 0

szErrName   BYTE "Enter your name using letters and spaces.", 0
szErrUser   BYTE "Username: 3 to 15 letters, digits or _", 0
szErrPin    BYTE "PIN must be 4 to 6 digits.", 0
szErrMatch  BYTE "The two PINs don't match.", 0
szErrNoUser BYTE "No account with that username. Create one below.", 0
szErrBadFile BYTE "This account's file is damaged and can't be opened.", 0
szErrTampered BYTE "This file was changed outside Student Toolkit. It can't be trusted.", 0
szErrTaken  BYTE "That username is taken. Pick another.", 0
szErrIO     BYTE "Couldn't save the account file.", 0
szErrPin1   BYTE "Wrong PIN. 1 try left.", 0
szFmtTries  BYTE "Wrong PIN. %d tries left.", 0
szLockTitle BYTE "Account locked", 0
szLockMsg   BYTE "Too many wrong PIN attempts.", 13, 10
            BYTE "Student Toolkit will now close to protect your data.", 0

szLogIn     BYTE "Logged in", 0
errorBuf    BYTE 128 DUP(0)
bufName     BYTE 32 DUP(0)
bufUser     BYTE 32 DUP(0)
bufPin      BYTE 32 DUP(0)
bufPin2     BYTE 32 DUP(0)
fieldBufs   DWORD OFFSET bufName, OFFSET bufUser, OFFSET bufPin, OFFSET bufPin2

GLYPH_BRAND = 0E7BEh            ; graduation cap

.code
;---------------------------------------------------------------------
; RegisterLoginClass
;---------------------------------------------------------------------
RegisterLoginClass PROC
    LOCAL wc:WNDCLASSEX

    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.style, CS_HREDRAW OR CS_VREDRAW
    mov wc.lpfnWndProc, OFFSET LoginWndProc
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
    mov wc.lpszClassName, OFFSET szLoginClass
    INVOKE RegisterClassExA, ADDR wc
    ret
RegisterLoginClass ENDP

;---------------------------------------------------------------------
; ModeList (helper) - fields shown in the current mode
; Returns: ESI = address of the list, ECX = number of fields
;---------------------------------------------------------------------
ModeList PROC
    cmp loginMode, 0
    jne CreateMode
    mov esi, OFFSET modeLoginList
    mov ecx, LENGTHOF modeLoginList
    ret
CreateMode:
    mov esi, OFFSET modeCreateList
    mov ecx, LENGTHOF modeCreateList
    ret
ModeList ENDP

;---------------------------------------------------------------------
; ModeRows (helper) - number of field rows in a mode
; Returns: EAX
;---------------------------------------------------------------------
ModeRows PROC mode:DWORD
    mov eax, LOGIN_ROWS
    cmp mode, 0
    je  @F
    mov eax, CREATE_ROWS
@@: ret
ModeRows ENDP

;---------------------------------------------------------------------
; FieldGeometry (helper) - position of the k-th field of this mode
; Sets fgLeft, fgRight (real pixels) and fgTop (100% scale).
;---------------------------------------------------------------------
FieldGeometry PROC USES ebx ecx edx esi edi, k:DWORD, clientW:DWORD
    ; row and column of field k
    mov esi, OFFSET modeLoginRow
    mov edi, OFFSET modeLoginCol
    cmp loginMode, 0
    je  @F
    mov esi, OFFSET modeCreateRow
    mov edi, OFFSET modeCreateCol
@@: mov ebx, k
    mov eax, [esi + ebx*4]          ; row
    mov ecx, L_FIELD_STEP
    mul ecx
    add eax, L_FIELD_TOP
    mov fgTop, eax
    mov ebx, [edi + ebx*4]          ; column

    ; full-width box edges
    INVOKE ScaleDpi, L_CARD_M + L_PAD
    mov esi, eax                    ; left edge
    mov edi, clientW
    sub edi, eax                    ; right edge
    mov fgLeft, esi
    mov fgRight, edi
    cmp ebx, 0
    je  Done

    ; half width: split at the middle with an 8px gap each side
    lea eax, [esi + edi]
    shr eax, 1                      ; middle
    mov ecx, eax
    INVOKE ScaleDpi, 8
    cmp ebx, 1
    jne RightHalf
    sub ecx, eax
    mov fgRight, ecx
    jmp Done
RightHalf:
    add ecx, eax
    mov fgLeft, ecx
Done:
    ret
FieldGeometry ENDP

;---------------------------------------------------------------------
; LoginClientHeight (helper) - client height at 100% for a mode
; Returns: EAX
;---------------------------------------------------------------------
LoginClientHeight PROC USES ecx edx, mode:DWORD
    INVOKE ModeRows, mode
    mov ecx, L_FIELD_STEP
    mul ecx                         ; rows * step
    add eax, L_FIELD_TOP            ; = top of the error line
    add eax, 28 + 52 + 32 + 16      ; error, button, link, card padding
    add eax, L_CARD_M
    ret
LoginClientHeight ENDP

;---------------------------------------------------------------------
; GetLoginWindowSize - outer window size for a mode
; Returns: EAX = width, ECX = height
;---------------------------------------------------------------------
GetLoginWindowSize PROC mode:DWORD
    LOCAL r:RECT

    mov r.left, 0
    mov r.top, 0
    INVOKE ScaleDpi, L_WIDTH
    mov r.right, eax
    INVOKE LoginClientHeight, mode
    INVOKE ScaleDpi, eax
    mov r.bottom, eax
    ; add the title bar and borders around the client area
    INVOKE AdjustWindowRectEx, ADDR r, LOGIN_STYLE, FALSE, 0
    mov eax, r.right
    sub eax, r.left
    mov ecx, r.bottom
    sub ecx, r.top
    ret
GetLoginWindowSize ENDP

;---------------------------------------------------------------------
; ShowLoginWindow - opens the login window in the middle of the screen
;---------------------------------------------------------------------
ShowLoginWindow PROC USES ebx esi edi
    cmp hLoginWnd, 0
    jne Done

    mov loginOk, 0
    mov failCount, 0
    mov loginMode, 0
    mov focusField, -1
    mov errorBuf, 0
    INVOKE SetTheme, THEME_LAVENDER

    INVOKE GetLoginWindowSize, 0
    mov esi, eax                    ; width
    mov edi, ecx                    ; height
    INVOKE GetSystemMetrics, SM_CXSCREEN
    sub eax, esi
    sar eax, 1
    mov ebx, eax                    ; x
    INVOKE GetSystemMetrics, SM_CYSCREEN
    sub eax, edi
    sar eax, 1                      ; y

    INVOKE CreateWindowExA, 0, ADDR szLoginClass, ADDR szLoginCaption,
           LOGIN_STYLE, ebx, eax, esi, edi, NULL, NULL, hInstance, NULL
    mov hLoginWnd, eax
    mov hActiveDialog, eax          ; Tab / Enter work in it
    INVOKE SetLoginMode, 0
    INVOKE ShowWindow, hLoginWnd, SW_SHOW
    INVOKE UpdateWindow, hLoginWnd
    INVOKE SetFocus, hField[F_USER*4]   ; cursor ready in the username box
Done:
    ret
ShowLoginWindow ENDP

;---------------------------------------------------------------------
; CreateLoginControls (helper) - 4 text fields and 2 buttons
;---------------------------------------------------------------------
CreateLoginControls PROC USES ebx esi, hWnd:DWORD
    INVOKE CreateSolidBrush, curTheme.clrCard
    mov hBrushField, eax

    xor esi, esi
FieldLoop:
    mov ebx, IDC_F_NAME
    add ebx, esi
    INVOKE CreateField, hWnd, ebx, fieldStyles[esi*4], fieldMax[esi*4]
    mov hField[esi*4], eax
    inc esi
    cmp esi, FIELD_COUNT
    jb  FieldLoop

    INVOKE CreatePastelButton, hWnd, ADDR szBtnLogin, IDOK, BTN_PRIMARY
    mov hBtnMain, eax
    INVOKE CreatePastelButton, hWnd, ADDR szToCreate, IDC_L_SWITCH, BTN_LINK
    mov hBtnSwitch, eax
    ret
CreateLoginControls ENDP

;---------------------------------------------------------------------
; SetLoginMode - switches between "Log in" and "Create account"
;---------------------------------------------------------------------
SetLoginMode PROC USES ebx esi, mode:DWORD
    LOCAL showCmd:DWORD

    mov eax, mode
    mov loginMode, eax
    mov errorBuf, 0

    ; name and confirm-PIN fields only appear when creating an account
    mov showCmd, SW_HIDE
    cmp mode, 0
    je  @F
    mov showCmd, SW_SHOW
@@: INVOKE ShowWindow, hField[F_NAME*4], showCmd
    INVOKE ShowWindow, hField[F_PIN2*4], showCmd
    INVOKE SetWindowTextA, hField[F_PIN*4], ADDR szEmpty
    INVOKE SetWindowTextA, hField[F_PIN2*4], ADDR szEmpty

    cmp mode, 0
    jne TextsCreate
    INVOKE SetWindowTextA, hBtnMain, ADDR szBtnLogin
    INVOKE SetWindowTextA, hBtnSwitch, ADDR szToCreate
    jmp TextsDone
TextsCreate:
    INVOKE SetWindowTextA, hBtnMain, ADDR szBtnCreate
    INVOKE SetWindowTextA, hBtnSwitch, ADDR szToLogin
TextsDone:

    ; resize the window for the number of rows and keep it centred
    INVOKE GetLoginWindowSize, mode
    mov esi, eax                    ; width
    mov ebx, ecx                    ; height
    INVOKE GetSystemMetrics, SM_CXSCREEN
    sub eax, esi
    sar eax, 1
    push eax                        ; x
    INVOKE GetSystemMetrics, SM_CYSCREEN
    sub eax, ebx
    sar eax, 1
    jns @F
    xor eax, eax                    ; never above the top of the screen
@@: pop ecx
    INVOKE SetWindowPos, hLoginWnd, NULL, ecx, eax, esi, ebx, SWP_NOZORDER
    INVOKE LayoutLogin, hLoginWnd
    INVOKE InvalidateRect, hLoginWnd, NULL, FALSE

    ; keyboard focus goes to the first field of this mode
    call ModeList
    mov eax, [esi]
    INVOKE SetFocus, hField[eax*4]
    ret
SetLoginMode ENDP

;---------------------------------------------------------------------
; LayoutLogin - places the fields and buttons
;---------------------------------------------------------------------
LayoutLogin PROC USES ebx esi edi, hWnd:DWORD
    LOCAL rc:RECT, boxX1:DWORD, boxW:DWORD, k:DWORD, count:DWORD,
          inset:DWORD, editH:DWORD, posY:DWORD

    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE ScaleDpi, L_CARD_M + L_PAD
    mov boxX1, eax
    mov ebx, rc.right
    sub ebx, eax
    sub ebx, eax
    mov boxW, ebx                   ; width of the buttons
    INVOKE ScaleDpi, 12
    mov inset, eax                  ; text starts 12px inside its box
    INVOKE ScaleDpi, L_EDIT_H
    mov editH, eax

    call ModeList
    mov count, ecx
    mov k, 0
FieldLoop:
    INVOKE FieldGeometry, k, rc.right
    mov eax, fgTop
    add eax, L_BOX_OFF + (L_BOX_H - L_EDIT_H) / 2
    INVOKE ScaleDpi, eax
    mov posY, eax
    mov ebx, fgLeft
    add ebx, inset                  ; text box x
    mov ecx, fgRight
    sub ecx, fgLeft
    sub ecx, inset
    sub ecx, inset                  ; text box width
    mov eax, k
    mov edi, [esi + eax*4]          ; field number
    INVOKE MoveWindow, hField[edi*4], ebx, posY, ecx, editH, TRUE
    inc k
    mov eax, k
    cmp eax, count
    jb  FieldLoop

    ; buttons below the fields
    INVOKE ModeRows, loginMode
    mov ecx, L_FIELD_STEP
    mul ecx
    add eax, L_FIELD_TOP + 28
    mov edi, eax                    ; button top at 100%
    INVOKE ScaleDpi, edi
    mov posY, eax
    INVOKE ScaleDpi, 44
    INVOKE MoveWindow, hBtnMain, boxX1, posY, boxW, eax, TRUE
    add edi, 52
    INVOKE ScaleDpi, edi
    mov posY, eax
    INVOKE ScaleDpi, 32
    INVOKE MoveWindow, hBtnSwitch, boxX1, posY, boxW, eax, TRUE
    ret
LayoutLogin ENDP

;---------------------------------------------------------------------
; PaintLogin - card, logo, titles, field labels and boxes, error text
;---------------------------------------------------------------------
PaintLogin PROC USES ebx esi edi, hWnd:DWORD
    LOCAL ps:PAINTSTRUCT, rc:RECT, r:RECT, memDC:DWORD, hBmp:DWORD,
          oldBmp:DWORD, cardM:DWORD, boxX1:DWORD, boxX2:DWORD,
          k:DWORD, count:DWORD, fTop:DWORD, fieldNo:DWORD, focused:DWORD

    INVOKE BeginPaint, hWnd, ADDR ps
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE CreateCompatibleDC, ps.hdc
    mov memDC, eax
    INVOKE CreateCompatibleBitmap, ps.hdc, rc.right, rc.bottom
    mov hBmp, eax
    INVOKE SelectObject, memDC, hBmp
    mov oldBmp, eax

    ; background and card
    INVOKE FillSolid, memDC, ADDR rc, curTheme.clrBg
    INVOKE ScaleDpi, L_CARD_M
    mov cardM, eax
    mov ecx, rc.right
    sub ecx, eax
    mov edx, rc.bottom
    sub edx, eax
    INVOKE FillRound, memDC, cardM, cardM, ecx, edx, 16,
           curTheme.clrCard, curTheme.clrBorder

    ; logo, title, subtitle (centred)
    INVOKE ScaleDpi, 44
    mov r.top, eax
    INVOKE ScaleDpi, 90
    mov r.bottom, eax
    mov r.left, 0
    mov eax, rc.right
    mov r.right, eax
    INVOKE DrawGlyph, memDC, GLYPH_BRAND, ADDR r, hFontLogo,
           curTheme.clrSideActText, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, 92
    mov r.top, eax
    INVOKE ScaleDpi, 128
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR szHeadTitle, ADDR r, hFontTitle,
           curTheme.clrText, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, 128
    mov r.top, eax
    INVOKE ScaleDpi, 154
    mov r.bottom, eax
    mov edx, OFFSET szSubLogin
    cmp loginMode, 0
    je  @F
    mov edx, OFFSET szSubCreate
@@: INVOKE DrawTextIn, memDC, edx, ADDR r, hFontBody,
           curTheme.clrMuted, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE

    ; fields: label + rounded box
    call ModeList
    mov count, ecx
    mov k, 0
FieldLoop:
    INVOKE FieldGeometry, k, rc.right
    mov eax, fgTop
    mov fTop, eax                   ; field top at 100%
    mov eax, fgLeft
    mov boxX1, eax
    mov eax, fgRight
    mov boxX2, eax
    mov eax, k
    mov eax, [esi + eax*4]
    mov fieldNo, eax

    ; label
    INVOKE ScaleDpi, fTop
    mov r.top, eax
    mov ebx, fTop
    add ebx, L_LABEL_H
    INVOKE ScaleDpi, ebx
    mov r.bottom, eax
    mov eax, boxX1
    mov r.left, eax
    mov eax, boxX2
    mov r.right, eax
    mov ecx, fieldNo
    INVOKE DrawTextIn, memDC, fieldLabels[ecx*4], ADDR r, hFontSmall,
           curTheme.clrText, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE

    ; box
    mov focused, 0
    mov eax, fieldNo
    cmp eax, focusField
    jne @F
    mov focused, 1
@@: mov ebx, fTop
    add ebx, L_BOX_OFF
    INVOKE ScaleDpi, ebx
    mov edi, eax                    ; box top
    add ebx, L_BOX_H
    INVOKE ScaleDpi, ebx            ; box bottom
    INVOKE DrawFieldBox, memDC, boxX1, edi, boxX2, eax, focused

    inc k
    mov eax, k
    cmp eax, count
    jb  FieldLoop

    ; error message under the fields
    cmp errorBuf, 0
    je  NoError
    mov eax, rc.right
    mov r.right, eax
    mov r.left, 0
    INVOKE ModeRows, loginMode
    mov ecx, L_FIELD_STEP
    mul ecx
    add eax, L_FIELD_TOP - 6
    mov ebx, eax
    INVOKE ScaleDpi, ebx
    mov r.top, eax
    add ebx, 28
    INVOKE ScaleDpi, ebx
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR errorBuf, ADDR r, hFontSmall,
           CLR_DANGER_TX, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
NoError:

    INVOKE BitBlt, ps.hdc, 0, 0, rc.right, rc.bottom, memDC, 0, 0, SRCCOPY
    INVOKE SelectObject, memDC, oldBmp
    INVOKE DeleteObject, hBmp
    INVOKE DeleteDC, memDC
    INVOKE EndPaint, hWnd, ADDR ps
    ret
PaintLogin ENDP

;---------------------------------------------------------------------
; ShowError - shows a message under the fields and beeps
;---------------------------------------------------------------------
ShowError PROC pMsg:DWORD
    INVOKE Str_copy, pMsg, ADDR errorBuf
    INVOKE InvalidateRect, hLoginWnd, NULL, FALSE
    INVOKE MessageBeep, MB_OK
    ret
ShowError ENDP

;---------------------------------------------------------------------
; IsValidName - letters, spaces, . - '  and at least one letter
; Returns: EAX = 1 valid, 0 invalid
;---------------------------------------------------------------------
IsValidName PROC USES ebx esi, pStr:DWORD
    mov esi, pStr
    xor ebx, ebx                    ; ebx = letters found
NextChar:
    mov al, [esi]
    cmp al, 0
    je  CheckEnd
    mov ah, al
    or  ah, 20h                     ; lowercase copy for the letter test
    cmp ah, 'a'
    jb  NotLetter
    cmp ah, 'z'
    ja  NotLetter
    inc ebx
    jmp CharOk
NotLetter:
    cmp al, ' '
    je  CharOk
    cmp al, '.'
    je  CharOk
    cmp al, '-'
    je  CharOk
    cmp al, 27h                     ; apostrophe
    je  CharOk
    jmp Invalid
CharOk:
    inc esi
    jmp NextChar
CheckEnd:
    cmp ebx, 0
    je  Invalid
    mov eax, 1
    ret
Invalid:
    xor eax, eax
    ret
IsValidName ENDP

;---------------------------------------------------------------------
; IsValidUsername - 3..15 characters from a-z, 0-9, _
;---------------------------------------------------------------------
IsValidUsername PROC USES ecx esi, pStr:DWORD
    mov esi, pStr
    xor ecx, ecx                    ; length
NextChar:
    mov al, [esi]
    cmp al, 0
    je  CheckLen
    cmp al, '_'
    je  CharOk
    cmp al, '0'
    jb  Invalid
    cmp al, '9'
    jbe CharOk
    cmp al, 'a'
    jb  Invalid
    cmp al, 'z'
    ja  Invalid
CharOk:
    inc ecx
    inc esi
    jmp NextChar
CheckLen:
    cmp ecx, USER_MIN
    jb  Invalid
    cmp ecx, USER_LEN - 1
    ja  Invalid
    mov eax, 1
    ret
Invalid:
    xor eax, eax
    ret
IsValidUsername ENDP

;---------------------------------------------------------------------
; IsValidPin - 4..6 digits
;---------------------------------------------------------------------
IsValidPin PROC USES ecx esi, pStr:DWORD
    mov esi, pStr
    xor ecx, ecx
NextChar:
    mov al, [esi]
    cmp al, 0
    je  CheckLen
    cmp al, '0'
    jb  Invalid
    cmp al, '9'
    ja  Invalid
    inc ecx
    inc esi
    jmp NextChar
CheckLen:
    cmp ecx, PIN_MIN
    jb  Invalid
    cmp ecx, PIN_MAX
    ja  Invalid
    mov eax, 1
    ret
Invalid:
    xor eax, eax
    ret
IsValidPin ENDP

;---------------------------------------------------------------------
; WipePins (helper) - overwrites the typed PINs in memory with zeros
;---------------------------------------------------------------------
WipePins PROC USES ecx edi
    xor eax, eax
    cld
    mov edi, OFFSET bufPin
    mov ecx, SIZEOF bufPin
    rep stosb
    mov edi, OFFSET bufPin2
    mov ecx, SIZEOF bufPin2
    rep stosb
    ret
WipePins ENDP

;---------------------------------------------------------------------
; SubmitLogin - runs when "Log in" / "Create account" is pressed
; (or Enter is pressed in any field)
;---------------------------------------------------------------------
SubmitLogin PROC USES ebx esi, hWnd:DWORD
    LOCAL msgBuf[64]:BYTE

    ; read all four fields into their buffers
    xor esi, esi
ReadLoop:
    INVOKE GetWindowTextA, hField[esi*4], fieldBufs[esi*4], 32
    inc esi
    cmp esi, FIELD_COUNT
    jb  ReadLoop

    ; ---- check the typed values ----
    cmp loginMode, 0
    je  CheckUser
    INVOKE IsValidName, ADDR bufName
    test eax, eax
    jnz CheckUser
    INVOKE ShowError, ADDR szErrName
    INVOKE SetFocus, hField[F_NAME*4]
    jmp Done

CheckUser:
    INVOKE IsValidUsername, ADDR bufUser
    test eax, eax
    jnz CheckPin
    INVOKE ShowError, ADDR szErrUser
    INVOKE SetFocus, hField[F_USER*4]
    jmp Done

CheckPin:
    INVOKE IsValidPin, ADDR bufPin
    test eax, eax
    jnz PinOk
    INVOKE ShowError, ADDR szErrPin
    INVOKE SetFocus, hField[F_PIN*4]
    jmp Done

PinOk:
    cmp loginMode, 0
    je  DoLogin

    ; ---- create account ----
    INVOKE Str_compare, ADDR bufPin, ADDR bufPin2
    je  PinsMatch
    INVOKE SetWindowTextA, hField[F_PIN2*4], ADDR szEmpty
    INVOKE ShowError, ADDR szErrMatch
    INVOKE SetFocus, hField[F_PIN2*4]
    jmp Done
PinsMatch:
    INVOKE CreateUser, ADDR bufName, ADDR bufUser, ADDR bufPin
    cmp eax, ACC_OK
    je  Success
    cmp eax, ACC_EXISTS
    jne CreateFailed
    INVOKE ShowError, ADDR szErrTaken
    INVOKE SetFocus, hField[F_USER*4]
    jmp Done
CreateFailed:
    INVOKE ShowError, ADDR szErrIO
    jmp Done

    ; ---- log in ----
DoLogin:
    INVOKE LoadUser, ADDR bufUser, ADDR bufPin
    cmp eax, ACC_OK
    je  Success
    cmp eax, ACC_NO_USER
    jne NotNoUser
    INVOKE ShowError, ADDR szErrNoUser
    jmp Done
NotNoUser:
    cmp eax, ACC_TAMPERED
    jne NotTampered
    INVOKE MessageBeep, MB_ICONHAND
    INVOKE ShowError, ADDR szErrTampered
    jmp Done
NotTampered:
    cmp eax, ACC_BAD_FILE
    jne WrongPin
    INVOKE ShowError, ADDR szErrBadFile
    jmp Done

WrongPin:
    inc failCount
    cmp failCount, MAX_TRIES
    jae Lockout
    INVOKE SetWindowTextA, hField[F_PIN*4], ADDR szEmpty
    INVOKE SetFocus, hField[F_PIN*4]
    mov eax, MAX_TRIES
    sub eax, failCount              ; tries left
    cmp eax, 1
    jne SeveralLeft
    INVOKE ShowError, ADDR szErrPin1
    jmp Done
SeveralLeft:
    INVOKE wsprintf, ADDR msgBuf, ADDR szFmtTries, eax
    INVOKE ShowError, ADDR msgBuf
    jmp Done

Lockout:
    INVOKE WipePins
    INVOKE MessageBeep, MB_ICONHAND
    INVOKE MessageBoxA, hWnd, ADDR szLockMsg, ADDR szLockTitle, MB_OK OR MB_ICONSTOP
    INVOKE DestroyWindow, hWnd      ; loginOk = 0 -> program ends
    jmp Done

Success:
    INVOKE WipePins
    mov loginOk, 1
    INVOKE LogEvent, ADDR szLogIn
    INVOKE StartMainWindow
    INVOKE DestroyWindow, hWnd

Done:
    ret
SubmitLogin ENDP

;---------------------------------------------------------------------
; LoginWndProc - messages for the login window
;---------------------------------------------------------------------
LoginWndProc PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
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
    cmp uMsg, WM_DESTROY
    je  OnDestroy
    INVOKE DefWindowProcA, hWnd, uMsg, wParam, lParam
    ret

OnCreate:
    INVOKE CreateLoginControls, hWnd
    xor eax, eax
    ret

OnErase:
    mov eax, 1
    ret

OnPaint:
    INVOKE PaintLogin, hWnd
    xor eax, eax
    ret

OnFieldColor:                       ; text fields use the card colours
    INVOKE GdiSetTextColor, wParam, curTheme.clrText
    INVOKE SetBkColor, wParam, curTheme.clrCard
    mov eax, hBrushField
    ret

OnDrawItem:
    INVOKE DrawPastelButton, lParam, curTheme.clrCard
    mov eax, TRUE
    ret

OnCommand:
    mov eax, wParam
    mov ebx, eax
    and eax, 0FFFFh                 ; control ID
    shr ebx, 16                     ; notification code

    cmp eax, IDOK
    jne NotOk
    INVOKE SubmitLogin, hWnd
    jmp CommandDone
NotOk:
    cmp eax, IDC_L_SWITCH
    jne NotSwitch
    mov eax, loginMode
    xor eax, 1                      ; 0 <-> 1
    INVOKE SetLoginMode, eax
    jmp CommandDone
NotSwitch:
    ; a text field gained or lost focus -> redraw its box border
    cmp eax, IDC_F_NAME
    jb  CommandDone
    cmp eax, IDC_F_NAME + FIELD_COUNT
    jae CommandDone
    sub eax, IDC_F_NAME
    cmp ebx, EN_SETFOCUS
    jne NotSetFocus
    mov focusField, eax
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp CommandDone
NotSetFocus:
    cmp ebx, EN_KILLFOCUS
    jne CommandDone
    cmp eax, focusField
    jne CommandDone
    mov focusField, -1
    INVOKE InvalidateRect, hWnd, NULL, FALSE
CommandDone:
    xor eax, eax
    ret

OnDestroy:
    INVOKE DeleteObject, hBrushField
    mov hLoginWnd, 0
    mov eax, hWnd
    cmp eax, hActiveDialog
    jne @F
    mov hActiveDialog, 0
@@: cmp loginOk, 0
    jne KeepRunning                 ; main window is open now
    INVOKE PostQuitMessage, 0
KeepRunning:
    xor eax, eax
    ret
LoginWndProc ENDP

END
