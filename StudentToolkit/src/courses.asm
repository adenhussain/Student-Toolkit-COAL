;=====================================================================
; courses.asm  -  the Courses screen
;
; Every course is entered once here; all other tools read it.
; The screen shows:
;   - a summary line: number of courses, credit hours, warnings
;   - "+ Add course" button
;   - a table, one row per course:
;       Course | Cr | Marks | Target | Difficulty | Preparation |
;       Attendance % | Status chip
;     Difficulty / Preparation are drawn as 5 dots.
;     The status chip applies FAST's attendance rule (ATTEND_MIN %):
;       mint   "Can skip 3"     - safe, 3 more absences allowed
;       butter "Can't skip"     - exactly at the limit
;       blush  "Attend next 4"  - below the limit, 4 classes in a
;                                 row needed to get back above it
; Clicking a row opens the course in the edit dialog.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

CourseGeometry  PROTO :DWORD
ColumnX         PROTO :DWORD
HitRow          PROTO :DWORD, :DWORD
DrawCell        PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DrawDots        PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DrawStatusChip  PROTO :DWORD, :DWORD, :DWORD, :DWORD

IDC_ADD_COURSE  = 1101
COL_COUNT       = 8
TBL_TOP         = 160           ; layout at 100% scale
TBL_HEAD_H      = 36
TBL_ROW_H       = 40
TOOLBAR_Y       = 102
ADD_BTN_W       = 170
ADD_BTN_H       = 40

.data
hCoursesPanel   DWORD 0
hBtnAddCourse   DWORD 0
hoverRow        DWORD -1        ; row under the mouse, -1 = none

; table geometry in real pixels (set by CourseGeometry)
tLeft       DWORD 0
tRight      DWORD 0
tTop        DWORD 0
tRowsTop    DWORD 0
tRowH       DWORD 0

; column widths in percent of the table (they add up to 100)
colPct      DWORD 27, 6, 13, 8, 12, 12, 10, 12

szHead0     BYTE "Course", 0
szHead1     BYTE "Cr", 0
szHead2     BYTE "Marks", 0
szHead3     BYTE "Target", 0
szHead4     BYTE "Difficulty", 0
szHead5     BYTE "Preparation", 0
szHead6     BYTE "Attend.", 0
szHead7     BYTE "Status", 0
colHeads    DWORD OFFSET szHead0, OFFSET szHead1, OFFSET szHead2, OFFSET szHead3,
                  OFFSET szHead4, OFFSET szHead5, OFFSET szHead6, OFFSET szHead7

szAddCourse     BYTE "+   Add course", 0
szFmtSummary    BYTE "%d of %d courses     |     %d credit hours     |     Attendance alerts: %d", 0
szEmptyTitle    BYTE "No courses yet", 0
szEmptyText     BYTE "Add each course once. Grades, Planner and Timer all use this list.", 0
szFmtSkip       BYTE "Can skip %d", 0
szCantSkip      BYTE "Can't skip", 0
szFmtNeed       BYTE "Attend next %d", 0
szNoClasses     BYTE "No classes yet", 0
szFmtPct        BYTE "%d%%", 0
szDash          BYTE "-", 0
szSlash         BYTE " / ", 0
szFullTitle     BYTE "Course list full", 0
szFullText      BYTE "You can add up to 10 courses.", 13, 10
                BYTE "Delete a course to make room for a new one.", 0

cellBuf     BYTE 64 DUP(0)
cellBuf2    BYTE 32 DUP(0)

GLYPH_COURSES = 0E8F1h

.code
;---------------------------------------------------------------------
; CoursesInit - creates the "+ Add course" button on the panel
;---------------------------------------------------------------------
CoursesInit PROC hPanel:DWORD
    mov eax, hPanel
    mov hCoursesPanel, eax
    mov hoverRow, -1
    INVOKE CreatePastelButton, hPanel, ADDR szAddCourse, IDC_ADD_COURSE, BTN_PRIMARY
    mov hBtnAddCourse, eax
    ret
CoursesInit ENDP

;---------------------------------------------------------------------
; CoursesChanged - redraws the screen after a course was saved
;---------------------------------------------------------------------
CoursesChanged PROC
    mov hoverRow, -1
    INVOKE InvalidateRect, hCoursesPanel, NULL, FALSE
    ret
CoursesChanged ENDP

;---------------------------------------------------------------------
; CourseGeometry - table position for a panel of width clientW
;---------------------------------------------------------------------
CourseGeometry PROC clientW:DWORD
    INVOKE ScaleDpi, PAGE_MARGIN
    mov tLeft, eax
    mov ecx, clientW
    sub ecx, eax
    mov tRight, ecx
    INVOKE ScaleDpi, TBL_TOP
    mov tTop, eax
    INVOKE ScaleDpi, TBL_HEAD_H
    add eax, tTop
    mov tRowsTop, eax
    INVOKE ScaleDpi, TBL_ROW_H
    mov tRowH, eax
    ret
CourseGeometry ENDP

;---------------------------------------------------------------------
; ColumnX - left edge of column 'col' (col = COL_COUNT gives the end)
; x = inner left + inner width * (sum of widths before col) / 100
; Returns: EAX
;---------------------------------------------------------------------
ColumnX PROC USES ebx ecx edx esi, col:DWORD
    ; ebx = sum of colPct[0 .. col-1]
    xor ebx, ebx
    xor esi, esi
SumLoop:
    cmp esi, col
    jae SumDone
    add ebx, colPct[esi*4]
    inc esi
    jmp SumLoop
SumDone:
    INVOKE ScaleDpi, 16
    mov ecx, eax                    ; inner padding
    mov eax, tRight
    sub eax, tLeft
    sub eax, ecx
    sub eax, ecx                    ; inner width
    mul ebx
    mov ebx, 100
    div ebx
    add eax, tLeft
    add eax, ecx
    ret
ColumnX ENDP

;---------------------------------------------------------------------
; AttendanceInfo - applies the attendance rule to one course
; Returns: EAX = attendance percent
;          ECX = 0 no classes yet, 1 safe, 2 at the limit, 3 below
;          EDX = classes that can be skipped (1) or must be attended (3)
;---------------------------------------------------------------------
AttendanceInfo PROC USES ebx esi edi, pCourse:DWORD
    mov esi, pCourse
    mov ebx, (COURSE PTR [esi]).classesHeld
    cmp ebx, 0
    jne HasClasses
    xor eax, eax
    xor ecx, ecx
    xor edx, edx
    ret

HasClasses:
    ; percent = attended * 100 / held
    mov eax, (COURSE PTR [esi]).classesAttended
    imul eax, eax, 100
    xor edx, edx
    div ebx
    mov edi, eax                    ; edi = percent

    ; above the limit?  attended*100 >= MIN*held
    mov eax, (COURSE PTR [esi]).classesAttended
    imul eax, eax, 100
    mov ecx, ebx
    imul ecx, ecx, ATTEND_MIN
    cmp eax, ecx
    jb  Below

    ; skips allowed = attended*100/MIN - held
    xor edx, edx
    mov ecx, ATTEND_MIN
    div ecx
    sub eax, ebx
    mov edx, eax
    mov ecx, 1                      ; safe
    cmp edx, 0
    jne Done
    mov ecx, 2                      ; exactly at the limit
    jmp Done

Below:
    ; classes needed in a row = ceil((MIN*held - 100*attended) / (100-MIN))
    mov eax, ebx
    imul eax, eax, ATTEND_MIN
    mov ecx, (COURSE PTR [esi]).classesAttended
    imul ecx, ecx, 100
    sub eax, ecx
    add eax, 100 - ATTEND_MIN - 1   ; round up
    xor edx, edx
    mov ecx, 100 - ATTEND_MIN
    div ecx
    mov edx, eax
    mov ecx, 3                      ; below the limit
Done:
    mov eax, edi
    ret
AttendanceInfo ENDP

;---------------------------------------------------------------------
; DrawCell - text inside column 'col' of a row
;---------------------------------------------------------------------
DrawCell PROC hdc:DWORD, col:DWORD, y1:DWORD, y2:DWORD, pText:DWORD,
              hFont:DWORD, color:DWORD
    LOCAL r:RECT

    INVOKE ColumnX, col
    mov r.left, eax
    mov ecx, col
    inc ecx
    INVOKE ColumnX, ecx
    sub eax, 8                      ; small gap before the next column
    mov r.right, eax
    mov eax, y1
    mov r.top, eax
    mov eax, y2
    mov r.bottom, eax
    INVOKE DrawTextIn, hdc, pText, ADDR r, hFont, color,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS
    ret
DrawCell ENDP

;---------------------------------------------------------------------
; DrawDots - 5 small circles, the first 'count' filled (1-5 scale)
;---------------------------------------------------------------------
DrawDots PROC USES ebx esi edi, hdc:DWORD, col:DWORD, y1:DWORD, y2:DWORD, count:DWORD
    LOCAL dotSize:DWORD, stepX:DWORD, dotTop:DWORD, color:DWORD

    INVOKE ScaleDpi, 9
    mov dotSize, eax
    INVOKE ScaleDpi, 14
    mov stepX, eax
    mov eax, y1                     ; vertical centre - dotSize/2
    add eax, y2
    shr eax, 1
    mov ecx, dotSize
    shr ecx, 1
    sub eax, ecx
    mov dotTop, eax

    INVOKE ColumnX, col
    mov esi, eax                    ; x of the first dot
    xor ebx, ebx
DotLoop:
    mov eax, curTheme.clrBorder     ; empty dot
    cmp ebx, count
    jae @F
    mov eax, curTheme.clrSideActText ; filled dot
@@: mov color, eax
    mov edi, dotTop
    add edi, dotSize
    mov ecx, esi
    add ecx, dotSize
    INVOKE FillRound, hdc, esi, dotTop, ecx, edi, 5, color, color
    add esi, stepX
    inc ebx
    cmp ebx, 5
    jb  DotLoop
    ret
DrawDots ENDP

;---------------------------------------------------------------------
; DrawStatusChip - coloured attendance chip in the last column
;---------------------------------------------------------------------
DrawStatusChip PROC USES ebx esi edi, hdc:DWORD, y1:DWORD, y2:DWORD, pCourse:DWORD
    LOCAL r:RECT, bgColor:DWORD, txColor:DWORD

    INVOKE AttendanceInfo, pCourse
    cmp ecx, 0
    je  NoClasses
    cmp ecx, 1
    je  Safe
    cmp ecx, 2
    je  Edge
    ; below the limit
    INVOKE wsprintf, ADDR cellBuf, ADDR szFmtNeed, edx
    mov bgColor, CLR_DANGER_BG
    mov txColor, CLR_DANGER_TX
    jmp DrawIt
Safe:
    INVOKE wsprintf, ADDR cellBuf, ADDR szFmtSkip, edx
    mov bgColor, CLR_SAFE_BG
    mov txColor, CLR_SAFE_TX
    jmp DrawIt
Edge:
    INVOKE Str_copy, ADDR szCantSkip, ADDR cellBuf
    mov bgColor, CLR_WARN_BG
    mov txColor, CLR_WARN_TX
    jmp DrawIt
NoClasses:
    INVOKE Str_copy, ADDR szNoClasses, ADDR cellBuf
    mov eax, curTheme.clrBg
    mov bgColor, eax
    mov eax, curTheme.clrMuted
    mov txColor, eax

DrawIt:
    ; chip: column width minus a gap, 26px high, vertically centred
    INVOKE ColumnX, COL_COUNT - 1
    mov r.left, eax
    INVOKE ColumnX, COL_COUNT
    mov r.right, eax
    INVOKE ScaleDpi, 26
    mov ebx, eax
    mov eax, y1
    add eax, y2
    sub eax, ebx
    shr eax, 1
    mov r.top, eax
    add eax, ebx
    mov r.bottom, eax
    INVOKE FillRound, hdc, r.left, r.top, r.right, r.bottom, 13, bgColor, bgColor
    INVOKE DrawTextIn, hdc, ADDR cellBuf, ADDR r, hFontSmall, txColor,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS
    ret
DrawStatusChip ENDP

;---------------------------------------------------------------------
; PaintCourses - draws the whole Courses screen below its title
;---------------------------------------------------------------------
PaintCourses PROC USES ebx esi edi, hdc:DWORD, clientW:DWORD, clientH:DWORD
    LOCAL r:RECT, row:DWORD, y1:DWORD, y2:DWORD, credits:DWORD,
          alerts:DWORD, pCourse:DWORD, pad:DWORD

    INVOKE CourseGeometry, clientW
    INVOKE ScaleDpi, 16
    mov pad, eax

    ; ---- summary line: count credits and attendance alerts ----
    mov credits, 0
    mov alerts, 0
    mov esi, OFFSET userData.courses
    xor ebx, ebx
SumLoop:
    cmp ebx, userData.courseCount
    jae SumDone
    mov eax, (COURSE PTR [esi]).credits
    add credits, eax
    INVOKE AttendanceInfo, esi
    cmp ecx, 2                      ; at or below the limit
    jb  @F
    inc alerts
@@: add esi, SIZEOF COURSE
    inc ebx
    jmp SumLoop
SumDone:
    INVOKE wsprintf, ADDR cellBuf, ADDR szFmtSummary, userData.courseCount,
           MAX_COURSES, credits, alerts
    mov eax, tLeft
    mov r.left, eax
    INVOKE ScaleDpi, ADD_BTN_W + 16
    mov ecx, tRight
    sub ecx, eax
    mov r.right, ecx
    INVOKE ScaleDpi, TOOLBAR_Y
    mov r.top, eax
    INVOKE ScaleDpi, TOOLBAR_Y + ADD_BTN_H
    mov r.bottom, eax
    INVOKE DrawTextIn, hdc, ADDR cellBuf, ADDR r, hFontBody, curTheme.clrMuted,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS

    cmp userData.courseCount, 0
    jne HasCourses

    ; ---- empty state ----
    INVOKE ScaleDpi, 180
    add eax, tTop
    mov ebx, eax
    INVOKE FillRound, hdc, tLeft, tTop, tRight, ebx, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder
    mov eax, tLeft
    mov r.left, eax
    mov eax, tRight
    mov r.right, eax
    INVOKE ScaleDpi, 30
    add eax, tTop
    mov r.top, eax
    INVOKE ScaleDpi, 40
    add eax, r.top
    mov r.bottom, eax
    INVOKE DrawGlyph, hdc, GLYPH_COURSES, ADDR r, hFontIconLg,
           curTheme.clrMuted, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    mov eax, r.bottom
    add eax, 6
    mov r.top, eax
    INVOKE ScaleDpi, 30
    add eax, r.top
    mov r.bottom, eax
    INVOKE DrawTextIn, hdc, ADDR szEmptyTitle, ADDR r, hFontBodyBold,
           curTheme.clrText, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    mov eax, r.bottom
    mov r.top, eax
    INVOKE ScaleDpi, 26
    add eax, r.top
    mov r.bottom, eax
    INVOKE DrawTextIn, hdc, ADDR szEmptyText, ADDR r, hFontBody,
           curTheme.clrMuted, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    ret

HasCourses:
    ; ---- table card ----
    mov eax, userData.courseCount
    mul tRowH
    add eax, tRowsTop
    add eax, 8
    mov ebx, eax
    INVOKE FillRound, hdc, tLeft, tTop, tRight, ebx, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder

    ; ---- header row ----
    xor esi, esi
HeadLoop:
    INVOKE DrawCell, hdc, esi, tTop, tRowsTop, colHeads[esi*4],
           hFontSmall, curTheme.clrMuted
    inc esi
    cmp esi, COL_COUNT
    jb  HeadLoop
    mov eax, tLeft
    add eax, pad
    mov r.left, eax
    mov eax, tRight
    sub eax, pad
    mov r.right, eax
    mov eax, tRowsTop
    dec eax
    mov r.top, eax
    inc eax
    mov r.bottom, eax
    INVOKE FillSolid, hdc, ADDR r, curTheme.clrBorder

    ; ---- one row per course ----
    mov row, 0
    mov esi, OFFSET userData.courses
RowLoop:
    mov eax, row
    cmp eax, userData.courseCount
    jae RowsDone
    mov pCourse, esi
    mul tRowH
    add eax, tRowsTop
    mov y1, eax
    add eax, tRowH
    mov y2, eax

    ; hover highlight
    mov eax, row
    cmp eax, hoverRow
    jne NoHover
    INVOKE ScaleDpi, 6
    mov ecx, tLeft
    add ecx, eax
    mov edx, tRight
    sub edx, eax
    mov edi, y1
    add edi, 2
    mov ebx, y2
    sub ebx, 2
    INVOKE FillRound, hdc, ecx, edi, edx, ebx, 8, curTheme.clrBg, curTheme.clrBg
NoHover:

    ; thin line between rows
    cmp row, 0
    je  NoLine
    mov eax, y1
    mov r.top, eax
    inc eax
    mov r.bottom, eax
    INVOKE FillSolid, hdc, ADDR r, curTheme.clrBorder
NoLine:

    ; course name
    INVOKE DrawCell, hdc, 0, y1, y2, ADDR (COURSE PTR [esi]).cname,
           hFontBodyBold, curTheme.clrText
    ; credit hours
    INVOKE FormatUInt, (COURSE PTR [esi]).credits, ADDR cellBuf
    INVOKE DrawCell, hdc, 1, y1, y2, ADDR cellBuf, hFontBody, curTheme.clrText
    ; marks "32.5 / 50"
    cmp (COURSE PTR [esi]).marksTotal, 0
    jne HasMarks
    INVOKE DrawCell, hdc, 2, y1, y2, ADDR szDash, hFontBody, curTheme.clrMuted
    jmp MarksDone
HasMarks:
    INVOKE FormatTenths, (COURSE PTR [esi]).marksObt, ADDR cellBuf
    INVOKE StrAppend, ADDR cellBuf, ADDR szSlash
    INVOKE FormatTenths, (COURSE PTR [esi]).marksTotal, ADDR cellBuf2
    INVOKE StrAppend, ADDR cellBuf, ADDR cellBuf2
    INVOKE DrawCell, hdc, 2, y1, y2, ADDR cellBuf, hFontBody, curTheme.clrText
MarksDone:
    ; target grade
    INVOKE GradeName, (COURSE PTR [esi]).targetGrade
    INVOKE DrawCell, hdc, 3, y1, y2, eax, hFontBody, curTheme.clrText
    ; difficulty and preparation dots
    INVOKE DrawDots, hdc, 4, y1, y2, (COURSE PTR [esi]).difficulty
    INVOKE DrawDots, hdc, 5, y1, y2, (COURSE PTR [esi]).preparation
    ; attendance percent
    INVOKE AttendanceInfo, esi
    cmp ecx, 0
    jne HasAttendance
    INVOKE DrawCell, hdc, 6, y1, y2, ADDR szDash, hFontBody, curTheme.clrMuted
    jmp AttendDone
HasAttendance:
    INVOKE wsprintf, ADDR cellBuf, ADDR szFmtPct, eax
    INVOKE DrawCell, hdc, 6, y1, y2, ADDR cellBuf, hFontBody, curTheme.clrText
AttendDone:
    ; status chip
    INVOKE DrawStatusChip, hdc, y1, y2, esi

    add esi, SIZEOF COURSE
    inc row
    jmp RowLoop
RowsDone:
    ret
PaintCourses ENDP

;---------------------------------------------------------------------
; HitRow - which course row is at (x, y)?  Returns: EAX = row or -1
;---------------------------------------------------------------------
HitRow PROC USES ecx edx, x:DWORD, y:DWORD
    LOCAL rc:RECT

    INVOKE GetClientRect, hCoursesPanel, ADDR rc
    INVOKE CourseGeometry, rc.right
    mov eax, x
    cmp eax, tLeft
    jl  Miss
    cmp eax, tRight
    jge Miss
    mov eax, y
    sub eax, tRowsTop
    jl  Miss
    xor edx, edx
    div tRowH                       ; row = (y - rowsTop) / rowHeight
    cmp eax, userData.courseCount
    jae Miss
    ret
Miss:
    mov eax, -1
    ret
HitRow ENDP

;---------------------------------------------------------------------
; CoursesPanelMsg - messages for the Courses screen
; Returns: EAX = result, ECX = 1 if handled (0 -> default handling)
;---------------------------------------------------------------------
CoursesPanelMsg PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL rc:RECT, tme:TRACKMOUSEEVENT

    cmp uMsg, WM_SIZE
    je  OnSize
    cmp uMsg, WM_DRAWITEM
    je  OnDrawItem
    cmp uMsg, WM_COMMAND
    je  OnCommand
    cmp uMsg, WM_MOUSEMOVE
    je  OnMouseMove
    cmp uMsg, WM_MOUSELEAVE
    je  OnMouseLeave
    cmp uMsg, WM_LBUTTONDOWN
    je  OnClick
    cmp uMsg, WM_SETCURSOR
    je  OnSetCursor
    jmp NotHandled

OnSize:
    ; "+ Add course" sits at the right end of the toolbar row
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE ScaleDpi, PAGE_MARGIN + ADD_BTN_W
    mov ebx, rc.right
    sub ebx, eax
    INVOKE ScaleDpi, TOOLBAR_Y
    mov esi, eax
    INVOKE ScaleDpi, ADD_BTN_W
    mov edi, eax
    INVOKE ScaleDpi, ADD_BTN_H
    INVOKE MoveWindow, hBtnAddCourse, ebx, esi, edi, eax, TRUE
    jmp HandledZero

OnDrawItem:
    INVOKE DrawPastelButton, lParam, curTheme.clrBg
    mov eax, TRUE
    jmp Handled

OnCommand:
    mov eax, wParam
    and eax, 0FFFFh
    cmp eax, IDC_ADD_COURSE
    jne HandledZero
    cmp userData.courseCount, MAX_COURSES
    jb  CanAdd
    INVOKE MessageBoxA, hMainWnd, ADDR szFullText, ADDR szFullTitle,
           MB_OK OR MB_ICONINFORMATION
    jmp HandledZero
CanAdd:
    INVOKE OpenCourseDialog, -1     ; -1 = new course
    jmp HandledZero

OnMouseMove:
    mov eax, lParam
    movsx ecx, ax                   ; x = low word (signed)
    sar eax, 16                     ; y = high word
    INVOKE HitRow, ecx, eax
    cmp eax, hoverRow
    je  HandledZero
    mov hoverRow, eax
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    mov tme.cbSize, SIZEOF TRACKMOUSEEVENT
    mov tme.dwFlags, TME_LEAVE
    mov eax, hWnd
    mov tme.hwndTrack, eax
    mov tme.dwHoverTime, 0
    INVOKE TrackMouseEvent, ADDR tme
    jmp HandledZero

OnMouseLeave:
    cmp hoverRow, -1
    je  HandledZero
    mov hoverRow, -1
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero

OnClick:
    mov eax, lParam
    movsx ecx, ax
    sar eax, 16
    INVOKE HitRow, ecx, eax
    cmp eax, -1
    je  HandledZero
    INVOKE OpenCourseDialog, eax    ; edit this course
    jmp HandledZero

OnSetCursor:
    cmp hoverRow, -1
    je  NotHandled
    INVOKE LoadCursorA, NULL, IDC_HAND
    INVOKE SetCursor, eax
    mov eax, TRUE
    jmp Handled

HandledZero:
    xor eax, eax
Handled:
    mov ecx, 1
    ret
NotHandled:
    xor ecx, ecx
    ret
CoursesPanelMsg ENDP

END
