;=====================================================================
; settings.asm  -  the Settings & About screen
;
;  +-- Appearance ------------------+  +-- About ------------------+
;  | [Lavender mist] [Sage and sand]|  |   (logo)  Student Toolkit |
;  | [Ocean breeze] [Nordic frost]  |  |   version, team, course   |
;  | [Dark]                         |  |   what it is built with   |
;  +-- Study -----------------------+  |                           |
;  | Daily limit [ 8 ] hours        |  |                           |
;  | Sounds  [On] [Off]  test sound |  |                           |
;  +-- Your data -------------------+  |                           |
;  | [Save now] [Excel] [Log]       |  ("Change PIN" link top-right)  |                           |
;  +--------------------------------+  +---------------------------+
;
; Picking a theme calls SetTheme (copies one row of the theme table)
; and the whole window repaints in the new colours at once.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

StGeometry      PROTO :DWORD, :DWORD
StLayout        PROTO
StText          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
StUpdateChips   PROTO
ApplyTheme      PROTO :DWORD

IDC_ST_THEME    = 1701          ; 1701..1705
IDC_ST_LIMIT    = 1710
IDC_ST_SNDON    = 1711
IDC_ST_SNDOFF   = 1712
IDC_ST_SNDTEST  = 1713
IDC_ST_SAVE     = 1720
IDC_ST_EXCEL    = 1721
IDC_ST_LOG      = 1722
IDC_ST_PIN      = 1723

.data
hSettingsPanel  DWORD 0
hStTheme        DWORD THEME_COUNT DUP(0)
hStLimit        DWORD 0
hStSndOn        DWORD 0
hStSndOff       DWORD 0
hStSndTest      DWORD 0
hStSave         DWORD 0
hStExcel        DWORD 0
hStLog          DWORD 0
hStPin          DWORD 0
stFocus         DWORD 0
stDirty         DWORD 0

; geometry (real pixels)
sM          DWORD 0
sLeftX2     DWORD 0
sRightX1    DWORD 0
sRightX2    DWORD 0
sTop        DWORD 0
sAppBot     DWORD 0
sStudyTop   DWORD 0
sStudyBot   DWORD 0
sDataTop    DWORD 0
sBottom     DWORD 0
sPad        DWORD 0

szTheme0    BYTE "Lavender mist", 0
szTheme1    BYTE "Sage and sand", 0
szTheme2    BYTE "Ocean breeze", 0
szTheme3    BYTE "Nordic frost", 0
szTheme4    BYTE "Dark", 0
themeNames  DWORD OFFSET szTheme0, OFFSET szTheme1, OFFSET szTheme2, OFFSET szTheme3, OFFSET szTheme4

szAppearance    BYTE "Appearance", 0
szAppearSub     BYTE "Pick a colour theme. It is saved with your account.", 0
szStudy         BYTE "Study", 0
szLimitLbl      BYTE "Daily study limit (hours)", 0
szLimitHint     BYTE "Burnout warning above this", 0
szSoundsLbl     BYTE "Sounds", 0
szSndOn         BYTE "On", 0
szSndOff        BYTE "Off", 0
szSndTest       BYTE "Test sound", 0
szDataT         BYTE "Your data", 0
szFmtDataSub    BYTE "Encrypted in data\%s.dat - only your PIN can open it.", 0
szSaveNow       BYTE "Save now", 0
szExcelBtn      BYTE "Excel report", 0
szLogBtn        BYTE "Activity log", 0
szPinBtn        BYTE "Change PIN", 0
szAboutT        BYTE "About", 0
szAboutName     BYTE "Student Toolkit", 0
szAboutVer      BYTE "Version 1.0", 0
szAbout1        BYTE "CGPA planner and smart study planner", 0
szAbout2        BYTE "written in x86 assembly language.", 0
szAboutTeamT    BYTE "Team", 0
szAboutTeam1    BYTE "Aden Hussain  (25K-0828)", 0
szAboutTeam2    BYTE "Javaria Ahmed Shaikh  (25K-0825)", 0
szAboutCourseT  BYTE "Course", 0
szAboutCourse1  BYTE "COAL Lab (EL-2003), FAST-NUCES Karachi", 0
szAboutCourse2  BYTE "Instructor: Abdullah Shaikh  |  Fall 2026", 0
szAboutBuiltT   BYTE "Built with", 0
szAboutBuilt1   BYTE "MASM (32-bit), Win32 API + GDI, Irvine32", 0
szAboutBuilt2   BYTE "Every pixel is drawn in assembly.", 0
szLogTheme      BYTE "Theme changed to %s", 0
stBuf           BYTE 128 DUP(0)

GLYPH_CAP = 0E7BEh

.code
;---------------------------------------------------------------------
; SettingsInit - creates all the controls
;---------------------------------------------------------------------
SettingsInit PROC USES ebx esi, hPanel:DWORD
    mov eax, hPanel
    mov hSettingsPanel, eax
    xor esi, esi
ThemeLoop:
    lea ebx, [esi + IDC_ST_THEME]
    INVOKE CreatePastelButton, hPanel, themeNames[esi*4], ebx, BTN_CHIP
    mov hStTheme[esi*4], eax
    inc esi
    cmp esi, THEME_COUNT
    jb  ThemeLoop
    INVOKE CreateField, hPanel, IDC_ST_LIMIT, 0, 4
    mov hStLimit, eax
    INVOKE CreatePastelButton, hPanel, ADDR szSndOn, IDC_ST_SNDON, BTN_CHIP
    mov hStSndOn, eax
    INVOKE CreatePastelButton, hPanel, ADDR szSndOff, IDC_ST_SNDOFF, BTN_CHIP
    mov hStSndOff, eax
    INVOKE CreatePastelButton, hPanel, ADDR szSndTest, IDC_ST_SNDTEST, BTN_LINK
    mov hStSndTest, eax
    INVOKE CreatePastelButton, hPanel, ADDR szSaveNow, IDC_ST_SAVE, BTN_SECONDARY
    mov hStSave, eax
    INVOKE CreatePastelButton, hPanel, ADDR szExcelBtn, IDC_ST_EXCEL, BTN_SECONDARY
    mov hStExcel, eax
    INVOKE CreatePastelButton, hPanel, ADDR szLogBtn, IDC_ST_LOG, BTN_SECONDARY
    mov hStLog, eax
    INVOKE CreatePastelButton, hPanel, ADDR szPinBtn, IDC_ST_PIN, BTN_LINK
    mov hStPin, eax

    ; show the saved daily limit in hours ("8" or "7.5")
    mov eax, userData.dailyLimit
    cmp eax, 0
    jne @F
    mov eax, DEFAULT_LIMIT
@@: imul eax, eax, 10
    xor edx, edx
    mov ecx, 60
    div ecx
    INVOKE FormatTenths, eax, ADDR stBuf
    INVOKE SetWindowTextA, hStLimit, ADDR stBuf
    mov stDirty, 0
    INVOKE StUpdateChips
    ret
SettingsInit ENDP

;---------------------------------------------------------------------
; StUpdateChips - selected theme and sound chips
;---------------------------------------------------------------------
StUpdateChips PROC USES ebx
    xor ebx, ebx
@@: xor eax, eax
    cmp ebx, themeIndex
    jne NotThis
    inc eax
NotThis:
    INVOKE SetChipSelected, hStTheme[ebx*4], eax
    inc ebx
    cmp ebx, THEME_COUNT
    jb  @B
    xor eax, eax
    cmp userData.soundOn, 0
    je  @F
    inc eax
@@: push eax
    INVOKE SetChipSelected, hStSndOn, eax
    pop eax
    xor eax, 1
    INVOKE SetChipSelected, hStSndOff, eax
    ret
StUpdateChips ENDP

;---------------------------------------------------------------------
; ApplyTheme - switch theme now, remember it, save
;---------------------------------------------------------------------
ApplyTheme PROC index:DWORD
    mov eax, index
    mov userData.theme, eax
    INVOKE SetTheme, eax            ; copies the theme row and repaints all
    INVOKE StUpdateChips
    mov eax, index
    INVOKE LogEventFmt, ADDR szLogTheme, themeNames[eax*4]
    INVOKE SaveWithStatus
    ret
ApplyTheme ENDP

;---------------------------------------------------------------------
; StGeometry - card positions
;---------------------------------------------------------------------
StGeometry PROC USES ecx edx, clientW:DWORD, clientH:DWORD
    INVOKE ScaleDpi, PAGE_MARGIN
    mov sM, eax
    INVOKE ScaleDpi, 24
    mov sPad, eax
    INVOKE ScaleDpi, 104
    mov sTop, eax
    INVOKE ScaleDpi, 20
    mov ecx, clientH
    sub ecx, eax
    mov sBottom, ecx
    ; left column 58%, right column the rest
    INVOKE ScaleDpi, 16
    mov ecx, clientW
    sub ecx, sM
    sub ecx, sM
    sub ecx, eax
    imul ecx, ecx, 58
    mov eax, ecx
    xor edx, edx
    mov ecx, 100
    div ecx
    add eax, sM
    mov sLeftX2, eax
    INVOKE ScaleDpi, 16
    add eax, sLeftX2
    mov sRightX1, eax
    mov eax, clientW
    sub eax, sM
    mov sRightX2, eax
    ; left cards: appearance / study / data
    INVOKE ScaleDpi, 104 + 196
    mov sAppBot, eax
    INVOKE ScaleDpi, 104 + 196 + 16
    mov sStudyTop, eax
    INVOKE ScaleDpi, 104 + 196 + 16 + 150
    mov sStudyBot, eax
    INVOKE ScaleDpi, 16
    add eax, sStudyBot
    mov sDataTop, eax
    ret
StGeometry ENDP

;---------------------------------------------------------------------
; StText - text in a rectangle
;---------------------------------------------------------------------
StText PROC hdc:DWORD, pText:DWORD, x1:DWORD, y1:DWORD, x2:DWORD, y2:DWORD,
            hFont:DWORD, color:DWORD, flags:DWORD
    LOCAL r:RECT
    mov eax, x1
    mov r.left, eax
    mov eax, y1
    mov r.top, eax
    mov eax, x2
    mov r.right, eax
    mov eax, y2
    mov r.bottom, eax
    mov eax, flags
    or  eax, DT_SINGLELINE OR DT_VCENTER OR DT_END_ELLIPSIS
    INVOKE DrawTextIn, hdc, pText, ADDR r, hFont, color, eax
    ret
StText ENDP

;---------------------------------------------------------------------
; StLayout - places every control
;---------------------------------------------------------------------
StLayout PROC USES ebx esi edi
    LOCAL rc:RECT, x1:DWORD, w:DWORD, h:DWORD, gap:DWORD, posY:DWORD, col:DWORD

    INVOKE GetClientRect, hSettingsPanel, ADDR rc
    INVOKE StGeometry, rc.right, rc.bottom
    mov eax, sM
    add eax, sPad
    mov x1, eax
    INVOKE ScaleDpi, 8
    mov gap, eax
    INVOKE ScaleDpi, 40
    mov h, eax

    ; theme chips: 3 per row
    mov eax, sLeftX2
    sub eax, sM
    sub eax, sPad
    sub eax, sPad
    mov ecx, gap
    shl ecx, 1
    sub eax, ecx
    xor edx, edx
    mov ecx, 3
    div ecx
    mov w, eax
    xor esi, esi
ChipLoop:
    ; row = i / 3, column = i mod 3
    mov eax, esi
    xor edx, edx
    mov ecx, 3
    div ecx
    mov col, edx
    mov ebx, eax                    ; row
    INVOKE ScaleDpi, 48
    imul ebx, eax
    INVOKE ScaleDpi, 74
    add ebx, eax
    add ebx, sTop                   ; y
    mov eax, w
    add eax, gap
    mul col
    add eax, x1                     ; x
    INVOKE MoveWindow, hStTheme[esi*4], eax, ebx, w, h, TRUE
    inc esi
    cmp esi, THEME_COUNT
    jb  ChipLoop

    ; daily limit box (right half of its row)
    INVOKE ScaleDpi, 52 + 9
    add eax, sStudyTop
    mov posY, eax
    INVOKE ScaleDpi, 180 + 12
    add eax, x1
    mov ebx, eax
    INVOKE ScaleDpi, 70 - 24
    mov ecx, eax
    INVOKE ScaleDpi, 22
    INVOKE MoveWindow, hStLimit, ebx, posY, ecx, eax, TRUE

    ; sound chips
    INVOKE ScaleDpi, 100
    add eax, sStudyTop
    mov posY, eax
    INVOKE ScaleDpi, 180
    add eax, x1
    mov ebx, eax
    INVOKE ScaleDpi, 60
    mov w, eax
    INVOKE ScaleDpi, 36
    mov h, eax
    INVOKE MoveWindow, hStSndOn, ebx, posY, w, h, TRUE
    add ebx, w
    add ebx, gap
    INVOKE MoveWindow, hStSndOff, ebx, posY, w, h, TRUE
    add ebx, w
    add ebx, gap
    INVOKE ScaleDpi, 110
    INVOKE MoveWindow, hStSndTest, ebx, posY, eax, h, TRUE

    ; data buttons
    INVOKE ScaleDpi, 76
    add eax, sDataTop
    mov posY, eax
    INVOKE ScaleDpi, 140
    mov w, eax
    INVOKE ScaleDpi, 40
    mov h, eax
    mov ebx, x1
    INVOKE MoveWindow, hStSave, ebx, posY, w, h, TRUE
    add ebx, w
    add ebx, gap
    INVOKE MoveWindow, hStExcel, ebx, posY, w, h, TRUE
    add ebx, w
    add ebx, gap
    INVOKE MoveWindow, hStLog, ebx, posY, w, h, TRUE

    ; "Change PIN" link at the top-right of the data card
    INVOKE ScaleDpi, 10
    add eax, sDataTop
    mov posY, eax
    INVOKE ScaleDpi, 130
    mov w, eax
    mov ebx, sLeftX2
    sub ebx, sPad
    sub ebx, eax
    INVOKE ScaleDpi, 16
    add ebx, eax                    ; link text has its own padding
    INVOKE ScaleDpi, 36
    INVOKE MoveWindow, hStPin, ebx, posY, w, eax, TRUE
    ret
StLayout ENDP

;---------------------------------------------------------------------
; PaintSettings - cards, labels and the About text
;---------------------------------------------------------------------
PaintSettings PROC USES ebx esi edi, hdc:DWORD, clientW:DWORD, clientH:DWORD
    LOCAL x1:DWORD, x2:DWORD, y:DWORD, lineH:DWORD, r:RECT

    INVOKE StGeometry, clientW, clientH
    mov eax, sM
    add eax, sPad
    mov x1, eax
    mov eax, sLeftX2
    sub eax, sPad
    mov x2, eax
    INVOKE ScaleDpi, 24
    mov lineH, eax

    ;---- Appearance ----
    INVOKE FillRound, hdc, sM, sTop, sLeftX2, sAppBot, CARD_RADIUS, curTheme.clrCard, curTheme.clrBorder
    INVOKE ScaleDpi, 16
    add eax, sTop
    mov y, eax
    add eax, lineH
    INVOKE StText, hdc, ADDR szAppearance, x1, y, x2, eax, hFontBodyBold, curTheme.clrText, DT_LEFT
    mov eax, lineH
    add y, eax
    mov eax, y
    add eax, lineH
    INVOKE StText, hdc, ADDR szAppearSub, x1, y, x2, eax, hFontSmall, curTheme.clrMuted, DT_LEFT

    ;---- Study ----
    INVOKE FillRound, hdc, sM, sStudyTop, sLeftX2, sStudyBot, CARD_RADIUS, curTheme.clrCard, curTheme.clrBorder
    INVOKE ScaleDpi, 16
    add eax, sStudyTop
    mov y, eax
    add eax, lineH
    INVOKE StText, hdc, ADDR szStudy, x1, y, x2, eax, hFontBodyBold, curTheme.clrText, DT_LEFT
    ; daily limit row
    INVOKE ScaleDpi, 52
    add eax, sStudyTop
    mov y, eax
    INVOKE ScaleDpi, 40
    add eax, y
    mov ebx, eax                    ; row bottom
    INVOKE ScaleDpi, 176
    add eax, x1
    mov esi, eax
    INVOKE StText, hdc, ADDR szLimitLbl, x1, y, esi, ebx, hFontBody, curTheme.clrText, DT_LEFT
    INVOKE ScaleDpi, 180
    add eax, x1
    mov esi, eax                    ; box left
    INVOKE ScaleDpi, 70
    lea edi, [esi + eax]            ; box right
    xor ecx, ecx
    cmp stFocus, IDC_ST_LIMIT
    jne @F
    inc ecx
@@: INVOKE DrawFieldBox, hdc, esi, y, edi, ebx, ecx
    INVOKE ScaleDpi, 12
    add edi, eax
    INVOKE StText, hdc, ADDR szLimitHint, edi, y, x2, ebx, hFontSmall, curTheme.clrMuted, DT_LEFT
    ; sounds row label
    INVOKE ScaleDpi, 100
    add eax, sStudyTop
    mov y, eax
    INVOKE ScaleDpi, 36
    add eax, y
    mov ebx, eax
    INVOKE ScaleDpi, 176
    add eax, x1
    INVOKE StText, hdc, ADDR szSoundsLbl, x1, y, eax, ebx, hFontBody, curTheme.clrText, DT_LEFT

    ;---- Your data ----
    INVOKE FillRound, hdc, sM, sDataTop, sLeftX2, sBottom, CARD_RADIUS, curTheme.clrCard, curTheme.clrBorder
    INVOKE ScaleDpi, 16
    add eax, sDataTop
    mov y, eax
    add eax, lineH
    INVOKE StText, hdc, ADDR szDataT, x1, y, x2, eax, hFontBodyBold, curTheme.clrText, DT_LEFT
    mov eax, lineH
    add y, eax
    INVOKE wsprintf, ADDR stBuf, ADDR szFmtDataSub, ADDR userData.userName
    mov eax, y
    add eax, lineH
    INVOKE StText, hdc, ADDR stBuf, x1, y, x2, eax, hFontSmall, curTheme.clrMuted, DT_LEFT

    ;---- About ----
    INVOKE FillRound, hdc, sRightX1, sTop, sRightX2, sBottom, CARD_RADIUS, curTheme.clrCard, curTheme.clrBorder
    mov eax, sRightX1
    add eax, sPad
    mov x1, eax
    mov eax, sRightX2
    sub eax, sPad
    mov x2, eax
    INVOKE ScaleDpi, 16
    add eax, sTop
    mov y, eax
    add eax, lineH
    INVOKE StText, hdc, ADDR szAboutT, x1, y, x2, eax, hFontBodyBold, curTheme.clrText, DT_LEFT
    ; logo + name + version
    INVOKE ScaleDpi, 34
    add y, eax
    mov eax, x1
    mov r.left, eax
    INVOKE ScaleDpi, 48
    add eax, x1
    mov r.right, eax
    mov eax, y
    mov r.top, eax
    INVOKE ScaleDpi, 52
    add eax, y
    mov r.bottom, eax
    INVOKE DrawGlyph, hdc, GLYPH_CAP, ADDR r, hFontLogo, curTheme.clrSideActText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, 60
    add eax, x1
    mov esi, eax
    INVOKE ScaleDpi, 28
    add eax, y
    INVOKE StText, hdc, ADDR szAboutName, esi, y, x2, eax, hFontBrand, curTheme.clrText, DT_LEFT
    INVOKE ScaleDpi, 28
    add eax, y
    mov ecx, eax
    add eax, lineH
    INVOKE StText, hdc, ADDR szAboutVer, esi, ecx, x2, eax, hFontSmall, curTheme.clrMuted, DT_LEFT
    INVOKE ScaleDpi, 70
    add y, eax
    ; text blocks: (heading, line, line) x 3, plus the intro
    mov eax, y
    add eax, lineH
    INVOKE StText, hdc, ADDR szAbout1, x1, y, x2, eax, hFontBody, curTheme.clrText, DT_LEFT
    mov eax, lineH
    add y, eax
    mov eax, y
    add eax, lineH
    INVOKE StText, hdc, ADDR szAbout2, x1, y, x2, eax, hFontBody, curTheme.clrText, DT_LEFT
    mov edi, OFFSET szAboutTeamT
    mov ebx, 3
BlockLoop:
    INVOKE ScaleDpi, 44
    add y, eax
    mov eax, y
    add eax, lineH
    INVOKE StText, hdc, edi, x1, y, x2, eax, hFontSmall, curTheme.clrMuted, DT_LEFT
    INVOKE Str_length, edi
    lea edi, [edi + eax + 1]        ; next string (heading -> line 1)
    mov eax, lineH
    add y, eax
    mov eax, y
    add eax, lineH
    INVOKE StText, hdc, edi, x1, y, x2, eax, hFontBody, curTheme.clrText, DT_LEFT
    INVOKE Str_length, edi
    lea edi, [edi + eax + 1]        ; line 2
    mov eax, lineH
    add y, eax
    mov eax, y
    add eax, lineH
    INVOKE StText, hdc, edi, x1, y, x2, eax, hFontBody, curTheme.clrText, DT_LEFT
    INVOKE Str_length, edi
    lea edi, [edi + eax + 1]        ; next heading
    dec ebx
    jnz BlockLoop
    ret
PaintSettings ENDP

;---------------------------------------------------------------------
; SettingsPanelMsg
;---------------------------------------------------------------------
SettingsPanelMsg PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    cmp uMsg, WM_SIZE
    je  OnSize
    cmp uMsg, WM_CTLCOLOREDIT
    je  OnFieldColor
    cmp uMsg, WM_DRAWITEM
    je  OnDrawItem
    cmp uMsg, WM_COMMAND
    je  OnCommand
    xor ecx, ecx
    ret

OnSize:
    INVOKE StLayout
    jmp HandledZero

OnFieldColor:
    INVOKE GdiSetTextColor, wParam, curTheme.clrText
    INVOKE SetBkColor, wParam, curTheme.clrCard
    mov eax, hCardBrush
    mov ecx, 1
    ret

OnDrawItem:
    INVOKE DrawPastelButton, lParam, curTheme.clrCard
    mov eax, TRUE
    mov ecx, 1
    ret

OnCommand:
    mov eax, wParam
    mov ebx, eax
    and eax, 0FFFFh
    shr ebx, 16
    ; theme chips
    cmp eax, IDC_ST_THEME
    jb  NotTheme
    cmp eax, IDC_ST_THEME + THEME_COUNT
    jae NotTheme
    sub eax, IDC_ST_THEME
    INVOKE ApplyTheme, eax
    jmp HandledZero
NotTheme:
    cmp eax, IDC_ST_SNDON
    jne @F
    mov userData.soundOn, 1
    INVOKE StUpdateChips
    INVOKE PlayChime, CHIME_DONE
    INVOKE SaveWithStatus
    jmp HandledZero
@@: cmp eax, IDC_ST_SNDOFF
    jne @F
    mov userData.soundOn, 0
    INVOKE StUpdateChips
    INVOKE SaveWithStatus
    jmp HandledZero
@@: cmp eax, IDC_ST_SNDTEST
    jne @F
    INVOKE PlayChime, CHIME_BADGE
    jmp HandledZero
@@: cmp eax, IDC_ST_SAVE
    jne @F
    INVOKE SaveWithStatus
    jmp HandledZero
@@: cmp eax, IDC_ST_EXCEL
    jne @F
    INVOKE ExportExcel
    jmp HandledZero
@@: cmp eax, IDC_ST_LOG
    jne @F
    INVOKE OpenActivityLog
    jmp HandledZero
@@: cmp eax, IDC_ST_PIN
    jne @F
    INVOKE OpenPinDialog
    jmp HandledZero
@@: cmp eax, IDC_ST_LIMIT
    jne HandledZero
    cmp ebx, EN_SETFOCUS
    jne @F
    mov stFocus, eax
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero
@@: cmp ebx, EN_KILLFOCUS
    jne @F
    mov stFocus, 0
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    cmp stDirty, 0
    je  HandledZero
    mov stDirty, 0
    INVOKE SaveWithStatus
    jmp HandledZero
@@: cmp ebx, EN_CHANGE
    jne HandledZero
    ; daily limit: 1 .. 16 hours, stored in minutes
    INVOKE GetWindowTextA, hStLimit, ADDR stBuf, SIZEOF stBuf
    INVOKE ParseTenths, ADDR stBuf
    cmp edx, 0
    je  HandledZero
    cmp eax, 10
    jb  HandledZero
    cmp eax, 160
    ja  HandledZero
    imul eax, eax, 6                ; tenths of an hour -> minutes
    mov userData.dailyLimit, eax
    mov stDirty, 1

HandledZero:
    xor eax, eax
    mov ecx, 1
    ret
SettingsPanelMsg ENDP

END
