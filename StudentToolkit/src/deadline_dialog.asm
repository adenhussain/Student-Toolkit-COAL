;=====================================================================
; deadline_dialog.asm  -  "Add a deadline" / "Edit deadline" popup
;
;   Title             e.g. "Quiz 3"
;   Type              [Quiz] [Assignment] [Exam] [Lab]   (chips)
;   Course (list)     | Due date  (14/11 or 14/11/2026)
;
; Same behaviour as the course popup: modal, Enter = Save,
; Esc = Cancel, red "Delete deadline" when editing.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

DeadlineDlgProc     PROTO :DWORD, :DWORD, :DWORD, :DWORD
CloseDeadlineDialog PROTO
LayoutDeadlineDialog PROTO :DWORD
PaintDeadlineDialog PROTO :DWORD
FillDeadlineFields  PROTO
SaveDeadline        PROTO
DeleteDeadline      PROTO
SelectKind          PROTO :DWORD
SetDdCourse         PROTO :DWORD
PickCourse          PROTO :DWORD
DdError             PROTO :DWORD, :DWORD

DDLG_STYLE      = WS_POPUP OR WS_CAPTION OR WS_SYSMENU OR WS_CLIPCHILDREN
IDC_DD_TITLE    = 4001
IDC_DD_COURSE   = 4002
IDC_DD_DATE     = 4003
IDC_DD_DELETE   = 4020
IDC_DD_KIND     = 4101          ; chips 4101..4104

; layout at 100% scale
DD_WIDTH        = 540
DD_PAD          = 32
DD_ROW0         = 100           ; title
DD_ROW1         = 174           ; type chips
DD_ROW2         = 248           ; course + date
DD_LABEL_H      = 20
DD_BOX_OFF      = 24
DD_BOX_H        = 40
DD_EDIT_H       = 22
DD_BTN_TOP      = DD_ROW2 + 74 + 26
DD_BTN_H        = 42
DD_HEIGHT       = DD_BTN_TOP + DD_BTN_H + 26

.data
hDeadlineDlg    DWORD 0
ddIndex         DWORD -1        ; deadline being edited, -1 = new
ddKind          DWORD DL_QUIZ   ; chosen type
ddCourse        DWORD -1        ; chosen course, -1 = General
ddFocus         DWORD -1        ; 0 = title box, 2 = date box focused
hDdBrush        DWORD 0
hDdTitle        DWORD 0
hDdCourse       DWORD 0
hDdDate         DWORD 0
hDdKind         DWORD DL_KIND_COUNT DUP(0)
hDdSave         DWORD 0
hDdCancel       DWORD 0
hDdDelete       DWORD 0
ddError         BYTE 128 DUP(0)
ddTitleBuf      BYTE DTITLE_LEN DUP(0)
ddDateBuf       BYTE 32 DUP(0)

szDdClass       BYTE "STKDeadlineDialog", 0
szDdCapAdd      BYTE "Add a deadline", 0
szDdCapEdit     BYTE "Edit deadline", 0
szDdSub         BYTE "Exams added here also guide the study planner.", 0
szDdLblTitle    BYTE "Title  (e.g. Quiz 3)", 0
szDdLblKind     BYTE "Type", 0
szDdLblCourse   BYTE "Course", 0
szDdLblDate     BYTE "Due date  (14/11, or leave empty)", 0
szDdNoCourse    BYTE "General (no course)", 0
szDdSave        BYTE "Save deadline", 0
szDdCancel      BYTE "Cancel", 0
szDdDelete      BYTE "Delete deadline", 0
szDdErrTitle    BYTE "Enter a title for this deadline.", 0
szDdErrDate     BYTE "Enter the date as day/month (14/11), or leave it empty.", 0
szDdDelTitle    BYTE "Delete deadline", 0
szLogDlSaved    BYTE "Deadline saved: %s", 0
szLogDlDel      BYTE "Deadline deleted: %s", 0
szDdDelFmt      BYTE "Delete %s?", 13, 10, "This can't be undone.", 0
ddDelMsg        BYTE 128 DUP(0)

.code
;---------------------------------------------------------------------
; RegisterDeadlineDialog
;---------------------------------------------------------------------
RegisterDeadlineDialog PROC
    LOCAL wc:WNDCLASSEX

    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.style, CS_HREDRAW OR CS_VREDRAW
    mov wc.lpfnWndProc, OFFSET DeadlineDlgProc
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
    mov wc.lpszClassName, OFFSET szDdClass
    INVOKE RegisterClassExA, ADDR wc
    ret
RegisterDeadlineDialog ENDP

;---------------------------------------------------------------------
; OpenDeadlineDialog - index = deadline to edit, -1 = new
;---------------------------------------------------------------------
OpenDeadlineDialog PROC USES ebx esi edi, index:DWORD
    LOCAL r:RECT, mainR:RECT, pCaption:DWORD

    cmp hDeadlineDlg, 0
    jne Done
    mov eax, index
    mov ddIndex, eax
    mov ddFocus, -1
    mov ddError, 0
    mov ddKind, DL_QUIZ

    mov pCaption, OFFSET szDdCapAdd
    cmp index, -1
    je  @F
    mov pCaption, OFFSET szDdCapEdit
@@: mov r.left, 0
    mov r.top, 0
    INVOKE ScaleDpi, DD_WIDTH
    mov r.right, eax
    INVOKE ScaleDpi, DD_HEIGHT
    mov r.bottom, eax
    INVOKE AdjustWindowRectEx, ADDR r, DDLG_STYLE, FALSE, 0
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
@@: INVOKE CreateWindowExA, 0, ADDR szDdClass, pCaption, DDLG_STYLE,
           ebx, eax, esi, edi, hMainWnd, NULL, hInstance, NULL
    mov hDeadlineDlg, eax
    mov hActiveDialog, eax

    INVOKE FillDeadlineFields
    INVOKE EnableWindow, hMainWnd, FALSE
    INVOKE ShowWindow, hDeadlineDlg, SW_SHOW
    INVOKE UpdateWindow, hDeadlineDlg
    INVOKE SetFocus, hDdTitle
Done:
    ret
OpenDeadlineDialog ENDP

;---------------------------------------------------------------------
; CloseDeadlineDialog
;---------------------------------------------------------------------
CloseDeadlineDialog PROC
    cmp hDeadlineDlg, 0
    je  @F
    INVOKE EnableWindow, hMainWnd, TRUE
    INVOKE SetForegroundWindow, hMainWnd
    INVOKE DestroyWindow, hDeadlineDlg
@@: ret
CloseDeadlineDialog ENDP

;---------------------------------------------------------------------
; SelectKind - highlights one of the four type chips
;---------------------------------------------------------------------
SelectKind PROC USES ebx, kind:DWORD
    mov eax, kind
    mov ddKind, eax
    xor ebx, ebx
ChipLoop:
    xor eax, eax
    cmp ebx, kind
    jne @F
    mov eax, 1
@@: INVOKE SetChipSelected, hDdKind[ebx*4], eax
    inc ebx
    cmp ebx, DL_KIND_COUNT
    jb  ChipLoop
    ret
SelectKind ENDP

;---------------------------------------------------------------------
; SetDdCourse - remembers the chosen course and shows its name
;---------------------------------------------------------------------
SetDdCourse PROC course:DWORD
    mov eax, course
    cmp eax, userData.courseCount
    jl  @F
    mov eax, -1                     ; out of range -> General
@@: mov ddCourse, eax
    cmp eax, -1
    jne @F
    INVOKE SetWindowTextA, hDdCourse, ADDR szDdNoCourse
    ret
@@: imul eax, eax, SIZEOF COURSE
    lea eax, userData.courses[eax]  ; course name (first field)
    INVOKE SetWindowTextA, hDdCourse, eax
    ret
SetDdCourse ENDP

;---------------------------------------------------------------------
; PickCourse - menu under the picker: "General" + every course.
; Menu item IDs: 1 = General, 2 = course 0, 3 = course 1 ...
;---------------------------------------------------------------------
PickCourse PROC USES ebx esi edi, hWnd:DWORD
    LOCAL btnR:RECT, hMenu:DWORD

    INVOKE CreatePopupMenu
    mov hMenu, eax
    mov edx, MF_STRING
    cmp ddCourse, -1
    jne @F
    or  edx, MF_CHECKED             ; tick the current choice
@@: INVOKE AppendMenuA, hMenu, edx, 1, ADDR szDdNoCourse
    mov esi, OFFSET userData.courses
    xor ebx, ebx
ItemLoop:
    cmp ebx, userData.courseCount
    jae ItemsDone
    mov edx, MF_STRING
    cmp ebx, ddCourse
    jne @F
    or  edx, MF_CHECKED
@@: lea edi, [ebx + 2]
    INVOKE AppendMenuA, hMenu, edx, edi, esi
    add esi, SIZEOF COURSE
    inc ebx
    jmp ItemLoop
ItemsDone:
    ; open it just below the picker and wait for a choice
    INVOKE GetWindowRect, hDdCourse, ADDR btnR
    INVOKE TrackPopupMenu, hMenu, TPM_RETURNCMD, btnR.left, btnR.bottom, 0, hWnd, NULL
    mov ebx, eax                    ; 0 = closed without choosing
    INVOKE DestroyMenu, hMenu
    cmp ebx, 0
    je  Done
    sub ebx, 2                      ; 1 -> -1 (General), 2 -> course 0 ...
    INVOKE SetDdCourse, ebx
Done:
    ret
PickCourse ENDP

;---------------------------------------------------------------------
; FillDeadlineFields - course list, then the deadline's values
;---------------------------------------------------------------------
FillDeadlineFields PROC USES ebx esi
    cmp ddIndex, -1
    jne EditExisting
    INVOKE SelectKind, DL_QUIZ
    INVOKE SetDdCourse, -1
    ret

EditExisting:
    mov eax, ddIndex
    imul eax, eax, SIZEOF DEADLINE
    lea esi, userData.deadlines[eax]
    INVOKE SetWindowTextA, hDdTitle, ADDR (DEADLINE PTR [esi]).dtitle
    INVOKE SelectKind, (DEADLINE PTR [esi]).kind
    INVOKE SetDdCourse, (DEADLINE PTR [esi]).course
    cmp (DEADLINE PTR [esi]).dueDay, NO_DATE
    je  @F                          ; no date: leave the box empty
    INVOKE FormatDateInput, (DEADLINE PTR [esi]).dueDay, ADDR ddDateBuf
    INVOKE SetWindowTextA, hDdDate, ADDR ddDateBuf
@@: ret
FillDeadlineFields ENDP

;---------------------------------------------------------------------
; DdError - red message, cursor to the field
;---------------------------------------------------------------------
DdError PROC pMsg:DWORD, hField:DWORD
    INVOKE Str_copy, pMsg, ADDR ddError
    INVOKE InvalidateRect, hDeadlineDlg, NULL, FALSE
    INVOKE MessageBeep, MB_OK
    INVOKE SetFocus, hField
    ret
DdError ENDP

;---------------------------------------------------------------------
; SaveDeadline - checks the fields, stores, sorts and saves
;---------------------------------------------------------------------
SaveDeadline PROC USES ebx esi
    LOCAL dueDay:DWORD, course:DWORD

    INVOKE GetWindowTextA, hDdTitle, ADDR ddTitleBuf, DTITLE_LEN
    cmp ddTitleBuf, 0
    jne @F
    INVOKE DdError, ADDR szDdErrTitle, hDdTitle
    ret
@@: INVOKE GetWindowTextA, hDdDate, ADDR ddDateBuf, SIZEOF ddDateBuf
    mov eax, NO_DATE
    cmp ddDateBuf, 0
    je  @F                          ; empty box: a deadline without a date
    INVOKE ParseDate, ADDR ddDateBuf
    cmp eax, -1
    jne @F
    INVOKE DdError, ADDR szDdErrDate, hDdDate
    ret
@@: mov dueDay, eax
    mov eax, ddCourse
    mov course, eax

    ; new deadlines go at the end, then the list is re-sorted
    mov eax, ddIndex
    cmp eax, -1
    jne @F
    mov eax, userData.deadlineCount
    inc userData.deadlineCount
@@: imul eax, eax, SIZEOF DEADLINE
    lea esi, userData.deadlines[eax]
    INVOKE Str_copy, ADDR ddTitleBuf, ADDR (DEADLINE PTR [esi]).dtitle
    mov eax, ddKind
    mov (DEADLINE PTR [esi]).kind, eax
    mov eax, course
    mov (DEADLINE PTR [esi]).course, eax
    mov eax, dueDay
    mov (DEADLINE PTR [esi]).dueDay, eax
    cmp ddIndex, -1
    jne @F
    mov (DEADLINE PTR [esi]).isDone, 0
@@:
    INVOKE LogEventFmt, ADDR szLogDlSaved, ADDR ddTitleBuf
    INVOKE SortDeadlines
    INVOKE SaveWithStatus
    INVOKE DeadlinesChanged
    INVOKE CloseDeadlineDialog
    ret
SaveDeadline ENDP

;---------------------------------------------------------------------
; DeleteDeadline - asks, then removes it (later items move up)
;---------------------------------------------------------------------
DeleteDeadline PROC USES ebx ecx esi edi
    mov eax, ddIndex
    imul eax, eax, SIZEOF DEADLINE
    lea ebx, userData.deadlines[eax]

    INVOKE wsprintf, ADDR ddDelMsg, ADDR szDdDelFmt, ADDR (DEADLINE PTR [ebx]).dtitle
    INVOKE MessageBoxA, hDeadlineDlg, ADDR ddDelMsg, ADDR szDdDelTitle,
           MB_YESNO OR MB_ICONWARNING OR MB_DEFBUTTON2
    cmp eax, IDYES
    jne Done
    INVOKE LogEventFmt, ADDR szLogDlDel, ebx

    mov ecx, userData.deadlineCount
    sub ecx, ddIndex
    dec ecx
    imul ecx, ecx, SIZEOF DEADLINE
    mov edi, ebx
    lea esi, [ebx + SIZEOF DEADLINE]
    cld
    rep movsb
    dec userData.deadlineCount
    mov eax, userData.deadlineCount
    imul eax, eax, SIZEOF DEADLINE
    lea edi, userData.deadlines[eax]
    mov ecx, SIZEOF DEADLINE
    xor eax, eax
    rep stosb

    INVOKE SaveWithStatus
    INVOKE DeadlinesChanged
    INVOKE CloseDeadlineDialog
Done:
    ret
DeleteDeadline ENDP

;---------------------------------------------------------------------
; LayoutDeadlineDialog - places every control
;---------------------------------------------------------------------
LayoutDeadlineDialog PROC USES ebx esi edi, hWnd:DWORD
    LOCAL rc:RECT, edgeL:DWORD, edgeR:DWORD, mid:DWORD, gap:DWORD,
          inset:DWORD, editH:DWORD, posY:DWORD, boxH:DWORD, chipW:DWORD

    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE ScaleDpi, DD_PAD
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
    INVOKE ScaleDpi, DD_EDIT_H
    mov editH, eax
    INVOKE ScaleDpi, DD_BOX_H
    mov boxH, eax

    ; title text box (full width)
    INVOKE ScaleDpi, DD_ROW0 + DD_BOX_OFF + (DD_BOX_H - DD_EDIT_H) / 2
    mov posY, eax
    mov ebx, edgeL
    add ebx, inset
    mov ecx, edgeR
    sub ecx, edgeL
    sub ecx, inset
    sub ecx, inset
    INVOKE MoveWindow, hDdTitle, ebx, posY, ecx, editH, TRUE

    ; four type chips side by side
    mov eax, edgeR
    sub eax, edgeL
    mov ecx, gap
    imul ecx, ecx, 3
    sub eax, ecx
    shr eax, 2                      ; (width - 3 gaps) / 4
    mov chipW, eax
    INVOKE ScaleDpi, DD_ROW1 + DD_BOX_OFF
    mov posY, eax
    mov ebx, edgeL
    xor esi, esi
ChipLoop:
    INVOKE MoveWindow, hDdKind[esi*4], ebx, posY, chipW, boxH, TRUE
    add ebx, chipW
    add ebx, gap
    inc esi
    cmp esi, DL_KIND_COUNT
    jb  ChipLoop

    ; course picker (left half), same size as a text box
    INVOKE ScaleDpi, DD_ROW2 + DD_BOX_OFF
    mov posY, eax
    mov ecx, mid
    sub ecx, gap
    sub ecx, edgeL
    INVOKE MoveWindow, hDdCourse, edgeL, posY, ecx, boxH, TRUE

    ; date text box (right half)
    INVOKE ScaleDpi, DD_ROW2 + DD_BOX_OFF + (DD_BOX_H - DD_EDIT_H) / 2
    mov posY, eax
    mov ebx, mid
    add ebx, gap
    add ebx, inset
    mov ecx, edgeR
    sub ecx, ebx
    sub ecx, inset
    INVOKE MoveWindow, hDdDate, ebx, posY, ecx, editH, TRUE

    ; buttons
    INVOKE ScaleDpi, DD_BTN_TOP
    mov posY, eax
    INVOKE ScaleDpi, DD_BTN_H
    mov boxH, eax
    INVOKE ScaleDpi, DD_PAD + 160
    mov ebx, rc.right
    sub ebx, eax
    INVOKE ScaleDpi, 160
    INVOKE MoveWindow, hDdSave, ebx, posY, eax, boxH, TRUE
    INVOKE ScaleDpi, 12 + 110
    sub ebx, eax
    INVOKE ScaleDpi, 110
    INVOKE MoveWindow, hDdCancel, ebx, posY, eax, boxH, TRUE
    INVOKE ScaleDpi, DD_PAD - 12
    mov ebx, eax
    INVOKE ScaleDpi, 150
    INVOKE MoveWindow, hDdDelete, ebx, posY, eax, boxH, TRUE
    ret
LayoutDeadlineDialog ENDP

;---------------------------------------------------------------------
; PaintDeadlineDialog - heading, labels, boxes for the text fields
;---------------------------------------------------------------------
PaintDeadlineDialog PROC USES ebx esi edi, hWnd:DWORD
    LOCAL ps:PAINTSTRUCT, rc:RECT, r:RECT, memDC:DWORD, hBmp:DWORD,
          oldBmp:DWORD, edgeL:DWORD, edgeR:DWORD, mid:DWORD, gap:DWORD,
          focused:DWORD

    INVOKE BeginPaint, hWnd, ADDR ps
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE CreateCompatibleDC, ps.hdc
    mov memDC, eax
    INVOKE CreateCompatibleBitmap, ps.hdc, rc.right, rc.bottom
    mov hBmp, eax
    INVOKE SelectObject, memDC, hBmp
    mov oldBmp, eax
    INVOKE FillSolid, memDC, ADDR rc, curTheme.clrCard

    INVOKE ScaleDpi, DD_PAD
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
    mov edx, OFFSET szDdCapAdd
    cmp ddIndex, -1
    je  @F
    mov edx, OFFSET szDdCapEdit
@@: INVOKE DrawTextIn, memDC, edx, ADDR r, hFontTitle, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, 58
    mov r.top, eax
    INVOKE ScaleDpi, 82
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR szDdSub, ADDR r, hFontSmall, curTheme.clrMuted,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE

    ; ---- labels ----
    INVOKE ScaleDpi, DD_ROW0
    mov r.top, eax
    INVOKE ScaleDpi, DD_ROW0 + DD_LABEL_H
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR szDdLblTitle, ADDR r, hFontSmall, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, DD_ROW1
    mov r.top, eax
    INVOKE ScaleDpi, DD_ROW1 + DD_LABEL_H
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR szDdLblKind, ADDR r, hFontSmall, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, DD_ROW2
    mov r.top, eax
    INVOKE ScaleDpi, DD_ROW2 + DD_LABEL_H
    mov r.bottom, eax
    mov eax, mid
    sub eax, gap
    mov r.right, eax
    INVOKE DrawTextIn, memDC, ADDR szDdLblCourse, ADDR r, hFontSmall, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    mov eax, mid
    add eax, gap
    mov r.left, eax
    mov eax, edgeR
    mov r.right, eax
    INVOKE DrawTextIn, memDC, ADDR szDdLblDate, ADDR r, hFontSmall, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS

    ; ---- boxes around the two text fields ----
    mov focused, 0
    cmp ddFocus, 0
    jne @F
    mov focused, 1
@@: INVOKE ScaleDpi, DD_ROW0 + DD_BOX_OFF
    mov ebx, eax
    INVOKE ScaleDpi, DD_ROW0 + DD_BOX_OFF + DD_BOX_H
    INVOKE DrawFieldBox, memDC, edgeL, ebx, edgeR, eax, focused

    mov focused, 0
    cmp ddFocus, 2
    jne @F
    mov focused, 1
@@: INVOKE ScaleDpi, DD_ROW2 + DD_BOX_OFF
    mov ebx, eax
    INVOKE ScaleDpi, DD_ROW2 + DD_BOX_OFF + DD_BOX_H
    mov edi, eax
    mov esi, mid
    add esi, gap
    INVOKE DrawFieldBox, memDC, esi, ebx, edgeR, edi, focused

    ; ---- error ----
    cmp ddError, 0
    je  NoError
    mov r.left, 0
    mov eax, rc.right
    mov r.right, eax
    INVOKE ScaleDpi, DD_BTN_TOP - 28
    mov r.top, eax
    INVOKE ScaleDpi, DD_BTN_TOP - 4
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR ddError, ADDR r, hFontSmall, CLR_DANGER_TX,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
NoError:
    INVOKE BitBlt, ps.hdc, 0, 0, rc.right, rc.bottom, memDC, 0, 0, SRCCOPY
    INVOKE SelectObject, memDC, oldBmp
    INVOKE DeleteObject, hBmp
    INVOKE DeleteDC, memDC
    INVOKE EndPaint, hWnd, ADDR ps
    ret
PaintDeadlineDialog ENDP

;---------------------------------------------------------------------
; DeadlineDlgProc - messages for the deadline popup
;---------------------------------------------------------------------
DeadlineDlgProc PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    cmp uMsg, WM_CREATE
    je  OnCreate
    cmp uMsg, WM_ERASEBKGND
    je  OnErase
    cmp uMsg, WM_PAINT
    je  OnPaint
    cmp uMsg, WM_CTLCOLOREDIT
    je  OnFieldColor
    cmp uMsg, WM_CTLCOLORLISTBOX
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
    mov hDdBrush, eax
    INVOKE CreateField, hWnd, IDC_DD_TITLE, 0, DTITLE_LEN - 1
    mov hDdTitle, eax
    ; course picker: a pastel button that opens a menu of courses
    INVOKE CreatePastelButton, hWnd, ADDR szDdNoCourse, IDC_DD_COURSE, BTN_PICKER
    mov hDdCourse, eax
    INVOKE CreateField, hWnd, IDC_DD_DATE, 0, 10
    mov hDdDate, eax
    ; type chips
    xor esi, esi
ChipCreate:
    mov ebx, IDC_DD_KIND
    add ebx, esi
    INVOKE CreatePastelButton, hWnd, kindNames[esi*4], ebx, BTN_CHIP
    mov hDdKind[esi*4], eax
    inc esi
    cmp esi, DL_KIND_COUNT
    jb  ChipCreate
    INVOKE CreatePastelButton, hWnd, ADDR szDdSave, IDOK, BTN_PRIMARY
    mov hDdSave, eax
    INVOKE CreatePastelButton, hWnd, ADDR szDdCancel, IDCANCEL, BTN_SECONDARY
    mov hDdCancel, eax
    INVOKE CreatePastelButton, hWnd, ADDR szDdDelete, IDC_DD_DELETE, BTN_DANGER_LINK
    mov hDdDelete, eax
    cmp ddIndex, -1
    jne @F
    INVOKE ShowWindow, hDdDelete, SW_HIDE
@@: INVOKE LayoutDeadlineDialog, hWnd
    xor eax, eax
    ret

OnErase:
    mov eax, 1
    ret

OnPaint:
    INVOKE PaintDeadlineDialog, hWnd
    xor eax, eax
    ret

OnFieldColor:
    INVOKE GdiSetTextColor, wParam, curTheme.clrText
    INVOKE SetBkColor, wParam, curTheme.clrCard
    mov eax, hDdBrush
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
    INVOKE SaveDeadline
    jmp CommandDone
@@: cmp eax, IDCANCEL
    jne @F
    INVOKE CloseDeadlineDialog
    jmp CommandDone
@@: cmp eax, IDC_DD_DELETE
    jne @F
    INVOKE DeleteDeadline
    jmp CommandDone
@@: cmp eax, IDC_DD_COURSE
    jne @F
    INVOKE PickCourse, hWnd
    jmp CommandDone
@@: ; a type chip?
    cmp eax, IDC_DD_KIND
    jb  NotChip
    cmp eax, IDC_DD_KIND + DL_KIND_COUNT
    jae NotChip
    sub eax, IDC_DD_KIND
    INVOKE SelectKind, eax
    jmp CommandDone
NotChip:
    ; focus changes of the two text boxes
    xor ecx, ecx                    ; field number 0 = title
    cmp eax, IDC_DD_TITLE
    je  FocusField
    mov ecx, 2                      ; 2 = date
    cmp eax, IDC_DD_DATE
    jne CommandDone
FocusField:
    cmp ebx, EN_SETFOCUS
    jne @F
    mov ddFocus, ecx
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp CommandDone
@@: cmp ebx, EN_KILLFOCUS
    jne CommandDone
    cmp ecx, ddFocus
    jne CommandDone
    mov ddFocus, -1
    INVOKE InvalidateRect, hWnd, NULL, FALSE
CommandDone:
    xor eax, eax
    ret

OnClose:
    INVOKE CloseDeadlineDialog
    xor eax, eax
    ret

OnDestroy:
    INVOKE DeleteObject, hDdBrush
    mov hDeadlineDlg, 0
    mov eax, hWnd
    cmp eax, hActiveDialog
    jne @F
    mov hActiveDialog, 0
@@: xor eax, eax
    ret
DeadlineDlgProc ENDP

END
