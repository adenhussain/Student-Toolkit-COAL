;=====================================================================
; course_dialog.asm  -  "Add a course" / "Edit course" popup
;
; Fields (two per row except the name):
;   Course name
;   Credit hours (1-4)        | Target grade (A+ ... F)
;   Marks so far (e.g. 32.5)  | Out of (e.g. 50)
;   Classes held              | Classes attended
;   Difficulty (1-5)          | Preparation (1-5)
;
; While it is open the main window is disabled (a "modal" popup).
; Enter = Save, Esc = Cancel. Editing shows a red "Delete course".
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

CourseDlgProc       PROTO :DWORD, :DWORD, :DWORD, :DWORD
CloseCourseDialog   PROTO
DlgFieldGeom        PROTO :DWORD, :DWORD
LayoutCourseDialog  PROTO :DWORD
PaintCourseDialog   PROTO :DWORD
FillCourseFields    PROTO
SaveCourse          PROTO
DeleteCourse        PROTO
DlgError            PROTO :DWORD, :DWORD

CDLG_STYLE      = WS_POPUP OR WS_CAPTION OR WS_SYSMENU OR WS_CLIPCHILDREN
IDC_CF_FIRST    = 3001          ; fields 3001..3009
IDC_CD_DELETE   = 3020
CF_COUNT        = 9
CF_BUF_LEN      = 32

CF_NAME     = 0
CF_CREDITS  = 1
CF_TARGET   = 2
CF_MARKS    = 3
CF_TOTAL    = 4
CF_HELD     = 5
CF_ATTENDED = 6
CF_DIFF     = 7
CF_PREP     = 8

; layout at 100% scale
D_WIDTH     = 520
D_PAD       = 32
D_FIELD_TOP = 100
D_STEP      = 74
D_ROWS      = 5
D_LABEL_H   = 20
D_BOX_OFF   = 24
D_BOX_H     = 40
D_EDIT_H    = 22
D_BTN_TOP   = D_FIELD_TOP + D_ROWS * D_STEP + 26
D_BTN_H     = 42
D_HEIGHT    = D_BTN_TOP + D_BTN_H + 26

.data
hCourseDlg  DWORD 0
editIndex   DWORD -1            ; course being edited, -1 = new course
dlgFocus    DWORD -1            ; field with keyboard focus
hDlgBrush   DWORD 0
hCF         DWORD CF_COUNT DUP(0)
hBtnSave    DWORD 0
hBtnCancel  DWORD 0
hBtnDelete  DWORD 0
dlgError    BYTE 128 DUP(0)

cfRow       DWORD 0, 1, 1, 2, 2, 3, 3, 4, 4
cfCol       DWORD 0, 1, 2, 1, 2, 1, 2, 1, 2     ; 0 full, 1 left, 2 right
cfStyle     DWORD 0, ES_NUMBER, ES_UPPERCASE, 0, 0, ES_NUMBER, ES_NUMBER, ES_NUMBER, ES_NUMBER
cfMax       DWORD NAME_LEN - 1, 1, 2, 5, 5, 3, 3, 1, 1
cfBufs      BYTE CF_COUNT * CF_BUF_LEN DUP(0)   ; text typed in each field

szL0    BYTE "Course name", 0
szL1    BYTE "Credit hours  (1-4)", 0
szL2    BYTE "Target grade  (e.g. B+)", 0
szL3    BYTE "Marks so far  (e.g. 32.5)", 0
szL4    BYTE "Out of  (e.g. 50)", 0
szL5    BYTE "Classes held", 0
szL6    BYTE "Classes attended", 0
szL7    BYTE "Difficulty  (1 easy - 5 hard)", 0
szL8    BYTE "Preparation  (1 none - 5 ready)", 0
cfLabels DWORD OFFSET szL0, OFFSET szL1, OFFSET szL2, OFFSET szL3, OFFSET szL4,
               OFFSET szL5, OFFSET szL6, OFFSET szL7, OFFSET szL8

szDlgClass      BYTE "STKCourseDialog", 0
szCapAdd        BYTE "Add a course", 0
szCapEdit       BYTE "Edit course", 0
szDlgSub        BYTE "Marks and attendance can stay empty until you have them.", 0
szBtnSave       BYTE "Save course", 0
szBtnCancel     BYTE "Cancel", 0
szBtnDelete     BYTE "Delete course", 0
szDefCredits    BYTE "3", 0
szDefTarget     BYTE "B+", 0
szDefLevel      BYTE "3", 0
szEmptyStr      BYTE 0

szErrCName      BYTE "Enter the course name.", 0
szErrCredits    BYTE "Credit hours must be 1 to 4.", 0
szErrTarget     BYTE "Target grade must be one of A+ A A- B+ B B- C+ C C- D+ D F.", 0
szErrMarksNum   BYTE "Marks must be a number such as 32 or 32.5", 0
szErrMarksNoTot BYTE "Enter what the marks are out of.", 0
szErrMarksTot   BYTE "'Out of' must be between 1 and 100.", 0
szErrMarksMore  BYTE "Marks so far can't be more than the total.", 0
szErrHeld       BYTE "Classes must be whole numbers (0 - 300).", 0
szErrAttended   BYTE "Attended can't be more than classes held.", 0
szErrLevel      BYTE "Difficulty and preparation must be 1 to 5.", 0
szDelTitle      BYTE "Delete course", 0
szLogCourseSaved BYTE "Course saved: %s", 0
szLogCourseDel  BYTE "Course deleted: %s", 0
szDelFmt        BYTE "Delete %s?", 13, 10, "Its marks and attendance will be removed. This can't be undone.", 0
delMsg          BYTE 160 DUP(0)

; results of DlgFieldGeom
dgLeft      DWORD 0
dgRight     DWORD 0
dgTop       DWORD 0

GLYPH_COURSES = 0E8F1h

.code
;---------------------------------------------------------------------
; RegisterCourseDialog
;---------------------------------------------------------------------
RegisterCourseDialog PROC
    LOCAL wc:WNDCLASSEX

    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.style, CS_HREDRAW OR CS_VREDRAW
    mov wc.lpfnWndProc, OFFSET CourseDlgProc
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
    mov wc.lpszClassName, OFFSET szDlgClass
    INVOKE RegisterClassExA, ADDR wc
    ret
RegisterCourseDialog ENDP

;---------------------------------------------------------------------
; OpenCourseDialog - index = course to edit, or -1 for a new course
;---------------------------------------------------------------------
OpenCourseDialog PROC USES ebx esi edi, index:DWORD
    LOCAL r:RECT, mainR:RECT, pCaption:DWORD

    cmp hCourseDlg, 0
    jne Done                        ; already open
    mov eax, index
    mov editIndex, eax
    mov dlgFocus, -1
    mov dlgError, 0

    mov pCaption, OFFSET szCapAdd
    cmp index, -1
    je  @F
    mov pCaption, OFFSET szCapEdit
@@:
    ; window size from the client size
    mov r.left, 0
    mov r.top, 0
    INVOKE ScaleDpi, D_WIDTH
    mov r.right, eax
    INVOKE ScaleDpi, D_HEIGHT
    mov r.bottom, eax
    INVOKE AdjustWindowRectEx, ADDR r, CDLG_STYLE, FALSE, 0
    mov esi, r.right
    sub esi, r.left                 ; width
    mov edi, r.bottom
    sub edi, r.top                  ; height

    ; centre over the main window
    INVOKE GetWindowRect, hMainWnd, ADDR mainR
    mov ebx, mainR.left
    add ebx, mainR.right
    sub ebx, esi
    sar ebx, 1                      ; x
    mov eax, mainR.top
    add eax, mainR.bottom
    sub eax, edi
    sar eax, 1                      ; y
    jns @F
    xor eax, eax
@@:
    INVOKE CreateWindowExA, 0, ADDR szDlgClass, pCaption, CDLG_STYLE,
           ebx, eax, esi, edi, hMainWnd, NULL, hInstance, NULL
    mov hCourseDlg, eax
    mov hActiveDialog, eax          ; Tab / Enter / Esc work in it

    INVOKE FillCourseFields
    INVOKE EnableWindow, hMainWnd, FALSE    ; modal: main window waits
    INVOKE ShowWindow, hCourseDlg, SW_SHOW
    INVOKE UpdateWindow, hCourseDlg
    INVOKE SetFocus, hCF[CF_NAME*4]
Done:
    ret
OpenCourseDialog ENDP

;---------------------------------------------------------------------
; CloseCourseDialog - re-enables the main window, then closes
;---------------------------------------------------------------------
CloseCourseDialog PROC
    cmp hCourseDlg, 0
    je  @F
    INVOKE EnableWindow, hMainWnd, TRUE
    INVOKE SetForegroundWindow, hMainWnd
    INVOKE DestroyWindow, hCourseDlg
@@: ret
CloseCourseDialog ENDP

;---------------------------------------------------------------------
; FillCourseFields - puts the course's values (or defaults) in the fields
;---------------------------------------------------------------------
FillCourseFields PROC USES ebx esi
    LOCAL buf[16]:BYTE

    cmp editIndex, -1
    jne EditExisting

    ; ---- new course: sensible defaults ----
    INVOKE SetWindowTextA, hCF[CF_CREDITS*4], ADDR szDefCredits
    INVOKE SetWindowTextA, hCF[CF_TARGET*4], ADDR szDefTarget
    INVOKE SetWindowTextA, hCF[CF_DIFF*4], ADDR szDefLevel
    INVOKE SetWindowTextA, hCF[CF_PREP*4], ADDR szDefLevel
    ret

EditExisting:
    mov eax, editIndex
    imul eax, eax, SIZEOF COURSE
    lea esi, userData.courses[eax]  ; esi -> the course

    INVOKE SetWindowTextA, hCF[CF_NAME*4], ADDR (COURSE PTR [esi]).cname
    INVOKE FormatUInt, (COURSE PTR [esi]).credits, ADDR buf
    INVOKE SetWindowTextA, hCF[CF_CREDITS*4], ADDR buf
    INVOKE GradeName, (COURSE PTR [esi]).targetGrade
    INVOKE SetWindowTextA, hCF[CF_TARGET*4], eax

    cmp (COURSE PTR [esi]).marksTotal, 0
    je  NoMarks
    INVOKE FormatTenths, (COURSE PTR [esi]).marksObt, ADDR buf
    INVOKE SetWindowTextA, hCF[CF_MARKS*4], ADDR buf
    INVOKE FormatTenths, (COURSE PTR [esi]).marksTotal, ADDR buf
    INVOKE SetWindowTextA, hCF[CF_TOTAL*4], ADDR buf
NoMarks:
    cmp (COURSE PTR [esi]).classesHeld, 0
    je  NoClasses
    INVOKE FormatUInt, (COURSE PTR [esi]).classesHeld, ADDR buf
    INVOKE SetWindowTextA, hCF[CF_HELD*4], ADDR buf
    INVOKE FormatUInt, (COURSE PTR [esi]).classesAttended, ADDR buf
    INVOKE SetWindowTextA, hCF[CF_ATTENDED*4], ADDR buf
NoClasses:
    INVOKE FormatUInt, (COURSE PTR [esi]).difficulty, ADDR buf
    INVOKE SetWindowTextA, hCF[CF_DIFF*4], ADDR buf
    INVOKE FormatUInt, (COURSE PTR [esi]).preparation, ADDR buf
    INVOKE SetWindowTextA, hCF[CF_PREP*4], ADDR buf
    ret
FillCourseFields ENDP

;---------------------------------------------------------------------
; DlgError - shows a red message and puts the cursor in the bad field
;---------------------------------------------------------------------
DlgError PROC pMsg:DWORD, field:DWORD
    INVOKE Str_copy, pMsg, ADDR dlgError
    INVOKE InvalidateRect, hCourseDlg, NULL, FALSE
    INVOKE MessageBeep, MB_OK
    mov eax, field
    INVOKE SetFocus, hCF[eax*4]
    ret
DlgError ENDP

;---------------------------------------------------------------------
; SaveCourse - checks every field, then stores the course and saves
;---------------------------------------------------------------------
SaveCourse PROC USES ebx esi edi
    LOCAL credits:DWORD, target:DWORD, marks:DWORD, total:DWORD,
          held:DWORD, attended:DWORD, diff:DWORD, prep:DWORD,
          marksLen:DWORD

    ; read every field into its buffer
    xor esi, esi
    mov edi, OFFSET cfBufs
ReadLoop:
    INVOKE GetWindowTextA, hCF[esi*4], edi, CF_BUF_LEN
    add edi, CF_BUF_LEN
    inc esi
    cmp esi, CF_COUNT
    jb  ReadLoop

    ; ---- course name ----
    cmp cfBufs[CF_NAME * CF_BUF_LEN], 0
    jne @F
    INVOKE DlgError, ADDR szErrCName, CF_NAME
    ret
@@:
    ; ---- credit hours 1..4 ----
    INVOKE ParseUInt, ADDR cfBufs[CF_CREDITS * CF_BUF_LEN]
    cmp edx, 0
    je  BadCredits
    cmp eax, 1
    jb  BadCredits
    cmp eax, 4
    ja  BadCredits
    mov credits, eax

    ; ---- target grade ----
    INVOKE ParseGrade, ADDR cfBufs[CF_TARGET * CF_BUF_LEN]
    cmp eax, -1
    je  BadTarget
    mov target, eax

    ; ---- marks: both empty, or obtained <= total ----
    INVOKE ParseTenths, ADDR cfBufs[CF_MARKS * CF_BUF_LEN]
    cmp edx, 0
    je  BadMarksNum
    mov marks, eax
    mov marksLen, ecx
    INVOKE ParseTenths, ADDR cfBufs[CF_TOTAL * CF_BUF_LEN]
    cmp edx, 0
    je  BadTotalNum
    mov total, eax
    cmp ecx, 0
    jne HaveTotal
    cmp marksLen, 0
    jne NoTotal                     ; marks typed but no total
    mov marks, 0                    ; both empty: no marks yet
    jmp MarksOk
HaveTotal:
    cmp eax, 10                     ; total between 1.0 and 100.0
    jb  BadTotal
    cmp eax, 1000
    ja  BadTotal
    mov eax, marks
    cmp eax, total
    ja  MarksTooBig
MarksOk:

    ; ---- attendance ----
    INVOKE ParseUInt, ADDR cfBufs[CF_HELD * CF_BUF_LEN]
    cmp edx, 0
    je  BadHeld
    cmp eax, 300
    ja  BadHeld
    mov held, eax
    INVOKE ParseUInt, ADDR cfBufs[CF_ATTENDED * CF_BUF_LEN]
    cmp edx, 0
    je  BadAttendedNum
    mov attended, eax
    cmp eax, held
    ja  BadAttended

    ; ---- difficulty / preparation 1..5 ----
    INVOKE ParseUInt, ADDR cfBufs[CF_DIFF * CF_BUF_LEN]
    cmp eax, 1
    jb  BadDiff
    cmp eax, 5
    ja  BadDiff
    mov diff, eax
    INVOKE ParseUInt, ADDR cfBufs[CF_PREP * CF_BUF_LEN]
    cmp eax, 1
    jb  BadPrep
    cmp eax, 5
    ja  BadPrep
    mov prep, eax

    ; ---- everything is valid: store it ----
    mov eax, editIndex
    cmp eax, -1
    jne @F
    mov eax, userData.courseCount   ; new course goes at the end
    inc userData.courseCount
@@: imul eax, eax, SIZEOF COURSE
    lea esi, userData.courses[eax]

    INVOKE Str_copy, ADDR cfBufs[CF_NAME * CF_BUF_LEN], ADDR (COURSE PTR [esi]).cname
    mov eax, credits
    mov (COURSE PTR [esi]).credits, eax
    mov eax, target
    mov (COURSE PTR [esi]).targetGrade, eax
    mov eax, marks
    mov (COURSE PTR [esi]).marksObt, eax
    mov eax, total
    mov (COURSE PTR [esi]).marksTotal, eax
    mov eax, held
    mov (COURSE PTR [esi]).classesHeld, eax
    mov eax, attended
    mov (COURSE PTR [esi]).classesAttended, eax
    mov eax, diff
    mov (COURSE PTR [esi]).difficulty, eax
    mov eax, prep
    mov (COURSE PTR [esi]).preparation, eax
    cmp editIndex, -1
    jne @F
    mov eax, target                 ; the grade slider starts at the target
    mov (COURSE PTR [esi]).sliderGrade, eax
@@:
    INVOKE LogEventFmt, ADDR szLogCourseSaved, esi
    INVOKE SaveWithStatus
    INVOKE CoursesChanged
    INVOKE CloseCourseDialog
    ret

BadCredits:
    INVOKE DlgError, ADDR szErrCredits, CF_CREDITS
    ret
BadTarget:
    INVOKE DlgError, ADDR szErrTarget, CF_TARGET
    ret
BadMarksNum:
    INVOKE DlgError, ADDR szErrMarksNum, CF_MARKS
    ret
BadTotalNum:
    INVOKE DlgError, ADDR szErrMarksNum, CF_TOTAL
    ret
NoTotal:
    INVOKE DlgError, ADDR szErrMarksNoTot, CF_TOTAL
    ret
BadTotal:
    INVOKE DlgError, ADDR szErrMarksTot, CF_TOTAL
    ret
MarksTooBig:
    INVOKE DlgError, ADDR szErrMarksMore, CF_MARKS
    ret
BadHeld:
    INVOKE DlgError, ADDR szErrHeld, CF_HELD
    ret
BadAttendedNum:
    INVOKE DlgError, ADDR szErrHeld, CF_ATTENDED
    ret
BadAttended:
    INVOKE DlgError, ADDR szErrAttended, CF_ATTENDED
    ret
BadDiff:
    INVOKE DlgError, ADDR szErrLevel, CF_DIFF
    ret
BadPrep:
    INVOKE DlgError, ADDR szErrLevel, CF_PREP
    ret
SaveCourse ENDP

;---------------------------------------------------------------------
; DeleteCourse - asks first, then removes the course from the array
; by moving every later course one place up (rep movsb).
;---------------------------------------------------------------------
DeleteCourse PROC USES ebx ecx esi edi
    mov eax, editIndex
    imul eax, eax, SIZEOF COURSE
    lea ebx, userData.courses[eax]  ; ebx -> course to delete

    INVOKE wsprintf, ADDR delMsg, ADDR szDelFmt, ADDR (COURSE PTR [ebx]).cname
    INVOKE MessageBoxA, hCourseDlg, ADDR delMsg, ADDR szDelTitle,
           MB_YESNO OR MB_ICONWARNING OR MB_DEFBUTTON2
    cmp eax, IDYES
    jne Done
    INVOKE LogEventFmt, ADDR szLogCourseDel, ebx

    ; bytes to move = (courseCount - index - 1) * SIZEOF COURSE
    mov ecx, userData.courseCount
    sub ecx, editIndex
    dec ecx
    imul ecx, ecx, SIZEOF COURSE
    mov edi, ebx                    ; destination: the deleted course
    lea esi, [ebx + SIZEOF COURSE]  ; source: the course after it
    cld
    rep movsb

    ; clear the now-unused last slot
    dec userData.courseCount
    mov eax, userData.courseCount
    imul eax, eax, SIZEOF COURSE
    lea edi, userData.courses[eax]
    mov ecx, SIZEOF COURSE
    xor eax, eax
    rep stosb

    ; deadlines of this course become "General", later ones shift up
    INVOKE CourseDeleted, editIndex
    INVOKE SaveWithStatus
    INVOKE CoursesChanged
    INVOKE CloseCourseDialog
Done:
    ret
DeleteCourse ENDP

;---------------------------------------------------------------------
; DlgFieldGeom - box position of field i (sets dgLeft, dgRight, dgTop)
;---------------------------------------------------------------------
DlgFieldGeom PROC USES ebx ecx edx esi edi, i:DWORD, clientW:DWORD
    mov ebx, i
    mov eax, cfRow[ebx*4]
    imul eax, eax, D_STEP
    add eax, D_FIELD_TOP
    mov dgTop, eax                  ; field top at 100%

    INVOKE ScaleDpi, D_PAD
    mov esi, eax                    ; left edge
    mov edi, clientW
    sub edi, eax                    ; right edge
    mov dgLeft, esi
    mov dgRight, edi
    mov ebx, cfCol[ebx*4]
    cmp ebx, 0
    je  Done
    lea eax, [esi + edi]
    shr eax, 1                      ; middle
    mov ecx, eax
    INVOKE ScaleDpi, 8
    cmp ebx, 1
    jne RightHalf
    sub ecx, eax
    mov dgRight, ecx
    jmp Done
RightHalf:
    add ecx, eax
    mov dgLeft, ecx
Done:
    ret
DlgFieldGeom ENDP

;---------------------------------------------------------------------
; LayoutCourseDialog - places fields and buttons
;---------------------------------------------------------------------
LayoutCourseDialog PROC USES ebx esi edi, hWnd:DWORD
    LOCAL rc:RECT, inset:DWORD, editH:DWORD, posY:DWORD, btnH:DWORD

    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE ScaleDpi, 12
    mov inset, eax
    INVOKE ScaleDpi, D_EDIT_H
    mov editH, eax

    xor esi, esi
FieldLoop:
    INVOKE DlgFieldGeom, esi, rc.right
    mov eax, dgTop
    add eax, D_BOX_OFF + (D_BOX_H - D_EDIT_H) / 2
    INVOKE ScaleDpi, eax
    mov posY, eax
    mov ebx, dgLeft
    add ebx, inset
    mov ecx, dgRight
    sub ecx, dgLeft
    sub ecx, inset
    sub ecx, inset
    INVOKE MoveWindow, hCF[esi*4], ebx, posY, ecx, editH, TRUE
    inc esi
    cmp esi, CF_COUNT
    jb  FieldLoop

    ; buttons: [Delete course]            [Cancel] [Save course]
    INVOKE ScaleDpi, D_BTN_TOP
    mov posY, eax
    INVOKE ScaleDpi, D_BTN_H
    mov btnH, eax
    INVOKE ScaleDpi, D_PAD + 150
    mov ebx, rc.right
    sub ebx, eax                    ; Save x
    INVOKE ScaleDpi, 150
    INVOKE MoveWindow, hBtnSave, ebx, posY, eax, btnH, TRUE
    INVOKE ScaleDpi, 12 + 110
    sub ebx, eax                    ; Cancel x
    INVOKE ScaleDpi, 110
    INVOKE MoveWindow, hBtnCancel, ebx, posY, eax, btnH, TRUE
    INVOKE ScaleDpi, D_PAD - 12     ; link text has its own padding
    mov ebx, eax
    INVOKE ScaleDpi, 140
    INVOKE MoveWindow, hBtnDelete, ebx, posY, eax, btnH, TRUE
    ret
LayoutCourseDialog ENDP

;---------------------------------------------------------------------
; PaintCourseDialog - heading, field labels and boxes, error text
;---------------------------------------------------------------------
PaintCourseDialog PROC USES ebx esi edi, hWnd:DWORD
    LOCAL ps:PAINTSTRUCT, rc:RECT, r:RECT, memDC:DWORD, hBmp:DWORD,
          oldBmp:DWORD, focused:DWORD, pad:DWORD

    INVOKE BeginPaint, hWnd, ADDR ps
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE CreateCompatibleDC, ps.hdc
    mov memDC, eax
    INVOKE CreateCompatibleBitmap, ps.hdc, rc.right, rc.bottom
    mov hBmp, eax
    INVOKE SelectObject, memDC, hBmp
    mov oldBmp, eax

    INVOKE FillSolid, memDC, ADDR rc, curTheme.clrCard
    INVOKE ScaleDpi, D_PAD
    mov pad, eax

    ; heading
    mov eax, pad
    mov r.left, eax
    mov eax, rc.right
    sub eax, pad
    mov r.right, eax
    INVOKE ScaleDpi, 22
    mov r.top, eax
    INVOKE ScaleDpi, 58
    mov r.bottom, eax
    mov edx, OFFSET szCapAdd
    cmp editIndex, -1
    je  @F
    mov edx, OFFSET szCapEdit
@@: INVOKE DrawTextIn, memDC, edx, ADDR r, hFontTitle, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, 58
    mov r.top, eax
    INVOKE ScaleDpi, 82
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR szDlgSub, ADDR r, hFontSmall, curTheme.clrMuted,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE

    ; fields
    xor esi, esi
FieldLoop:
    INVOKE DlgFieldGeom, esi, rc.right
    mov eax, dgLeft
    mov r.left, eax
    mov eax, dgRight
    mov r.right, eax
    INVOKE ScaleDpi, dgTop
    mov r.top, eax
    mov eax, dgTop
    add eax, D_LABEL_H
    INVOKE ScaleDpi, eax
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, cfLabels[esi*4], ADDR r, hFontSmall, curTheme.clrText,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS

    mov focused, 0
    cmp esi, dlgFocus
    jne @F
    mov focused, 1
@@: mov ebx, dgTop
    add ebx, D_BOX_OFF
    INVOKE ScaleDpi, ebx
    mov edi, eax                    ; box top
    add ebx, D_BOX_H
    INVOKE ScaleDpi, ebx            ; box bottom
    INVOKE DrawFieldBox, memDC, dgLeft, edi, dgRight, eax, focused
    inc esi
    cmp esi, CF_COUNT
    jb  FieldLoop

    ; error message above the buttons
    cmp dlgError, 0
    je  NoError
    mov r.left, 0
    mov eax, rc.right
    mov r.right, eax
    INVOKE ScaleDpi, D_BTN_TOP - 28
    mov r.top, eax
    INVOKE ScaleDpi, D_BTN_TOP - 4
    mov r.bottom, eax
    INVOKE DrawTextIn, memDC, ADDR dlgError, ADDR r, hFontSmall, CLR_DANGER_TX,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
NoError:

    INVOKE BitBlt, ps.hdc, 0, 0, rc.right, rc.bottom, memDC, 0, 0, SRCCOPY
    INVOKE SelectObject, memDC, oldBmp
    INVOKE DeleteObject, hBmp
    INVOKE DeleteDC, memDC
    INVOKE EndPaint, hWnd, ADDR ps
    ret
PaintCourseDialog ENDP

;---------------------------------------------------------------------
; CourseDlgProc - messages for the course popup
;---------------------------------------------------------------------
CourseDlgProc PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
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
    mov hDlgBrush, eax
    xor esi, esi
CreateLoop:
    mov ebx, IDC_CF_FIRST
    add ebx, esi
    INVOKE CreateField, hWnd, ebx, cfStyle[esi*4], cfMax[esi*4]
    mov hCF[esi*4], eax
    inc esi
    cmp esi, CF_COUNT
    jb  CreateLoop
    INVOKE CreatePastelButton, hWnd, ADDR szBtnSave, IDOK, BTN_PRIMARY
    mov hBtnSave, eax
    INVOKE CreatePastelButton, hWnd, ADDR szBtnCancel, IDCANCEL, BTN_SECONDARY
    mov hBtnCancel, eax
    INVOKE CreatePastelButton, hWnd, ADDR szBtnDelete, IDC_CD_DELETE, BTN_DANGER_LINK
    mov hBtnDelete, eax
    cmp editIndex, -1
    jne @F
    INVOKE ShowWindow, hBtnDelete, SW_HIDE  ; nothing to delete yet
@@: INVOKE LayoutCourseDialog, hWnd
    xor eax, eax
    ret

OnErase:
    mov eax, 1
    ret

OnPaint:
    INVOKE PaintCourseDialog, hWnd
    xor eax, eax
    ret

OnFieldColor:
    INVOKE GdiSetTextColor, wParam, curTheme.clrText
    INVOKE SetBkColor, wParam, curTheme.clrCard
    mov eax, hDlgBrush
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
    jne NotSave
    INVOKE SaveCourse
    jmp CommandDone
NotSave:
    cmp eax, IDCANCEL
    jne NotCancel
    INVOKE CloseCourseDialog
    jmp CommandDone
NotCancel:
    cmp eax, IDC_CD_DELETE
    jne NotDelete
    INVOKE DeleteCourse
    jmp CommandDone
NotDelete:
    ; focus moved between fields -> redraw the box borders
    cmp eax, IDC_CF_FIRST
    jb  CommandDone
    cmp eax, IDC_CF_FIRST + CF_COUNT
    jae CommandDone
    sub eax, IDC_CF_FIRST
    cmp ebx, EN_SETFOCUS
    jne NotSetFocus
    mov dlgFocus, eax
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp CommandDone
NotSetFocus:
    cmp ebx, EN_KILLFOCUS
    jne CommandDone
    cmp eax, dlgFocus
    jne CommandDone
    mov dlgFocus, -1
    INVOKE InvalidateRect, hWnd, NULL, FALSE
CommandDone:
    xor eax, eax
    ret

OnClose:
    INVOKE CloseCourseDialog
    xor eax, eax
    ret

OnDestroy:
    INVOKE DeleteObject, hDlgBrush
    mov hCourseDlg, 0
    mov eax, hWnd
    cmp eax, hActiveDialog
    jne @F
    mov hActiveDialog, 0
@@: xor eax, eax
    ret
CourseDlgProc ENDP

END
