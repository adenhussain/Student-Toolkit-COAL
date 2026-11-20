;=====================================================================
; deadlines.asm  -  the Deadlines screen
;
; One row per quiz / assignment / exam / lab:
;   [o] [Quiz] Quiz 3                 Fri 14 Nov    [ In 2 days ]
;              COAL
;   - the circle on the left marks it done (click it)
;   - the coloured chip on the right shows the days left:
;       red    overdue, today, tomorrow
;       yellow 2 - 3 days
;       green  4 days or more
;       grey   done
; The list is kept sorted (bubble sort): unfinished items first,
; earliest due date first. Clicking a row opens it for editing.
; The mouse wheel scrolls when there are more rows than fit.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

DlGeometry      PROTO :DWORD, :DWORD
DlColumnX       PROTO :DWORD
DlHitTest       PROTO :DWORD, :DWORD
DlVisibleRows   PROTO
DeadlineKey     PROTO :DWORD
DrawChip        PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
ToggleDone      PROTO :DWORD

IDC_ADD_DEADLINE = 1201
DCOL_COUNT      = 5
DL_TOP          = 160           ; layout at 100% scale
DL_ROW_H        = 56
TOOLBAR_Y       = 102
ADD_BTN_W       = 180
ADD_BTN_H       = 40
GLYPH_BELL      = 0EA8Fh
GLYPH_CHECK     = 0E73Eh

.data
hDeadlinesPanel DWORD 0
hBtnAddDeadline DWORD 0
hoverDl         DWORD -1        ; row under the mouse (index in the list)
scrollTop       DWORD 0         ; first row shown

dLeft       DWORD 0             ; list geometry in real pixels
dRight      DWORD 0
dTop        DWORD 0
dRowH       DWORD 0
dBottom     DWORD 0             ; lowest y the list may use

; column widths in percent: done, kind, title, due date, days left
dColPct     DWORD 5, 15, 42, 16, 22

szKind0     BYTE "Quiz", 0
szKind1     BYTE "Assignment", 0
szKind2     BYTE "Exam", 0
szKind3     BYTE "Lab", 0
kindNames   DWORD OFFSET szKind0, OFFSET szKind1, OFFSET szKind2, OFFSET szKind3
; pastel colour per kind: lilac, sky, peach, sage
kindBg      DWORD RGBC(0E5h,0D4h,0F0h)     ; quiz        lilac
            DWORD RGBC(0BFh,0D7h,0EAh)     ; assignment  sky
            DWORD RGBC(0F6h,0D5h,0C3h)     ; exam        peach
            DWORD RGBC(0D7h,0E8h,0C5h)     ; lab         sage
kindTx      DWORD RGBC(05Eh,03Fh,078h)
            DWORD RGBC(02Fh,04Ah,066h)
            DWORD RGBC(07Ah,03Eh,026h)
            DWORD RGBC(03Fh,056h,038h)

szAddDeadline   BYTE "+   Add deadline", 0
szFmtDlSummary  BYTE "Upcoming: %d     |     Due within 3 days: %d     |     Done: %d", 0
szDlEmptyTitle  BYTE "No deadlines yet", 0
szDlEmptyText   BYTE "Add quizzes, assignments, labs and exams to see what is due next.", 0
szOverdue       BYTE "Overdue", 0
szDueToday      BYTE "Due today", 0
szTomorrow      BYTE "Tomorrow", 0
szFmtInDays     BYTE "In %d days", 0
szDoneChip      BYTE "Done", 0
szNoDate        BYTE "No date", 0
szNoDueDate     BYTE "No due date", 0
szGeneral       BYTE "General", 0
szFmtShowing    BYTE "Showing %d - %d of %d.  Scroll with the mouse wheel for more.", 0
szDlFullTitle   BYTE "Deadline list full", 0
szLogDone       BYTE "Deadline ticked done: %s", 0
szLogUndone     BYTE "Deadline marked not done: %s", 0
szDlFullText    BYTE "You can keep up to 20 deadlines.", 13, 10
                BYTE "Delete finished ones to make room.", 0

dlBuf       BYTE 96 DUP(0)

.code
;---------------------------------------------------------------------
; DeadlinesInit - "+ Add deadline" button on the Deadlines panel
;---------------------------------------------------------------------
DeadlinesInit PROC hPanel:DWORD
    mov eax, hPanel
    mov hDeadlinesPanel, eax
    mov hoverDl, -1
    mov scrollTop, 0
    INVOKE CreatePastelButton, hPanel, ADDR szAddDeadline, IDC_ADD_DEADLINE, BTN_PRIMARY
    mov hBtnAddDeadline, eax
    ret
DeadlinesInit ENDP

;---------------------------------------------------------------------
; DeadlinesChanged - redraw after a change
;---------------------------------------------------------------------
DeadlinesChanged PROC
    mov hoverDl, -1
    INVOKE DlVisibleRows
    mov ecx, userData.deadlineCount
    sub ecx, eax                    ; largest useful scrollTop
    jns @F
    xor ecx, ecx
@@: cmp scrollTop, ecx
    jbe @F
    mov scrollTop, ecx
@@: INVOKE InvalidateRect, hDeadlinesPanel, NULL, FALSE
    ret
DeadlinesChanged ENDP

;---------------------------------------------------------------------
; DeadlineKey - sort key: unfinished first, then earliest due date
; Returns: EAX = isDone * 2^20 + dueDay
;---------------------------------------------------------------------
DeadlineKey PROC USES esi, pDl:DWORD
    mov esi, pDl
    mov eax, (DEADLINE PTR [esi]).isDone
    shl eax, 20
    add eax, (DEADLINE PTR [esi]).dueDay
    ret
DeadlineKey ENDP

;---------------------------------------------------------------------
; SortDeadlines - bubble sort of userData.deadlines by DeadlineKey
; Each pass moves the largest remaining key to the end. A pass with
; no swaps means the list is sorted, so we stop early.
;---------------------------------------------------------------------
SortDeadlines PROC USES eax ebx ecx edx esi edi
    LOCAL lastIndex:DWORD, swapped:DWORD

    mov eax, userData.deadlineCount
    cmp eax, 2
    jb  Done
    dec eax
    mov lastIndex, eax              ; compare pairs 0..lastIndex-1
PassLoop:
    mov swapped, 0
    mov esi, OFFSET userData.deadlines
    xor ebx, ebx
PairLoop:
    cmp ebx, lastIndex
    jae PassDone
    lea edi, [esi + SIZEOF DEADLINE]    ; next item
    INVOKE DeadlineKey, esi
    mov edx, eax
    INVOKE DeadlineKey, edi
    cmp edx, eax
    jbe NoSwap
    ; swap the two records, one DWORD at a time
    push esi
    push edi
    mov ecx, SIZEOF DEADLINE / 4
SwapLoop:
    mov eax, [esi]
    mov edx, [edi]
    mov [esi], edx
    mov [edi], eax
    add esi, 4
    add edi, 4
    loop SwapLoop
    pop edi
    pop esi
    mov swapped, 1
NoSwap:
    add esi, SIZEOF DEADLINE
    inc ebx
    jmp PairLoop
PassDone:
    cmp swapped, 0
    je  Done
    dec lastIndex
    jnz PassLoop
Done:
    ret
SortDeadlines ENDP

;---------------------------------------------------------------------
; CourseDeleted - course 'index' was removed: deadlines of that course
; become "General", deadlines of later courses move up one number.
;---------------------------------------------------------------------
CourseDeleted PROC USES ecx esi, index:DWORD
    mov esi, OFFSET userData.deadlines
    mov ecx, userData.deadlineCount
    jecxz Done
FixLoop:
    mov eax, (DEADLINE PTR [esi]).course
    cmp eax, index
    jne NotThis
    mov (DEADLINE PTR [esi]).course, -1
    jmp Next
NotThis:
    cmp eax, index
    jle Next                        ; earlier course or -1: unchanged
    dec (DEADLINE PTR [esi]).course
Next:
    add esi, SIZEOF DEADLINE
    loop FixLoop
Done:
    ret
CourseDeleted ENDP

;---------------------------------------------------------------------
; ToggleDone - ticks / unticks a deadline, re-sorts and saves
;---------------------------------------------------------------------
ToggleDone PROC USES esi, index:DWORD
    mov eax, index
    imul eax, eax, SIZEOF DEADLINE
    lea esi, userData.deadlines[eax]
    xor (DEADLINE PTR [esi]).isDone, 1
    mov edx, OFFSET szLogDone
    cmp (DEADLINE PTR [esi]).isDone, 0
    jne @F
    mov edx, OFFSET szLogUndone
@@: INVOKE LogEventFmt, edx, esi    ; title is the first field
    INVOKE SortDeadlines
    INVOKE SaveWithStatus
    INVOKE DeadlinesChanged
    ret
ToggleDone ENDP

;---------------------------------------------------------------------
; DlGeometry - list position for a panel of the given size
;---------------------------------------------------------------------
DlGeometry PROC clientW:DWORD, clientH:DWORD
    INVOKE ScaleDpi, PAGE_MARGIN
    mov dLeft, eax
    mov ecx, clientW
    sub ecx, eax
    mov dRight, ecx
    INVOKE ScaleDpi, DL_TOP
    mov dTop, eax
    INVOKE ScaleDpi, DL_ROW_H
    mov dRowH, eax
    INVOKE ScaleDpi, 44             ; room for the "Showing ..." line
    mov ecx, clientH
    sub ecx, eax
    mov dBottom, ecx
    ret
DlGeometry ENDP

;---------------------------------------------------------------------
; DlVisibleRows - how many rows fit.  Returns: EAX (at least 1)
;---------------------------------------------------------------------
DlVisibleRows PROC USES ecx edx
    LOCAL rc:RECT

    INVOKE GetClientRect, hDeadlinesPanel, ADDR rc
    INVOKE DlGeometry, rc.right, rc.bottom
    mov eax, dBottom
    sub eax, dTop
    jg  @F
    mov eax, 1
    ret
@@: xor edx, edx
    div dRowH
    cmp eax, 1
    jge @F
    mov eax, 1
@@: ret
DlVisibleRows ENDP

;---------------------------------------------------------------------
; DlColumnX - left edge of column col (col = DCOL_COUNT gives the end)
;---------------------------------------------------------------------
DlColumnX PROC USES ebx ecx edx esi, col:DWORD
    xor ebx, ebx
    xor esi, esi
SumLoop:
    cmp esi, col
    jae SumDone
    add ebx, dColPct[esi*4]
    inc esi
    jmp SumLoop
SumDone:
    INVOKE ScaleDpi, 16
    mov ecx, eax
    mov eax, dRight
    sub eax, dLeft
    sub eax, ecx
    sub eax, ecx
    mul ebx
    mov ebx, 100
    div ebx
    add eax, dLeft
    add eax, ecx
    ret
DlColumnX ENDP

;---------------------------------------------------------------------
; DrawChip - rounded coloured label, vertically centred in y1..y2
;---------------------------------------------------------------------
DrawChip PROC USES ebx, hdc:DWORD, x1:DWORD, x2:DWORD, y1:DWORD, y2:DWORD,
              pText:DWORD, bgColor:DWORD, txColor:DWORD
    LOCAL r:RECT

    mov eax, x1
    mov r.left, eax
    mov eax, x2
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
    INVOKE DrawTextIn, hdc, pText, ADDR r, hFontSmall, txColor,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS
    ret
DrawChip ENDP

;---------------------------------------------------------------------
; PaintDeadlines - summary line, list rows, "Showing ..." line
;---------------------------------------------------------------------
PaintDeadlines PROC USES ebx esi edi, hdc:DWORD, clientW:DWORD, clientH:DWORD
    LOCAL r:RECT, today:DWORD, upcoming:DWORD, soon:DWORD, doneCount:DWORD,
          visible:DWORD, shown:DWORD, k:DWORD, y1:DWORD, y2:DWORD,
          yMid:DWORD, x1:DWORD, x2:DWORD, chipBg:DWORD, chipTx:DWORD,
          titleColor:DWORD, pDl:DWORD

    INVOKE DlGeometry, clientW, clientH
    INVOKE TodayDay
    mov today, eax

    ; ---- summary: upcoming, due within 3 days, done ----
    mov upcoming, 0
    mov soon, 0
    mov doneCount, 0
    mov esi, OFFSET userData.deadlines
    mov ecx, userData.deadlineCount
    jecxz CountDone
CountLoop:
    cmp (DEADLINE PTR [esi]).isDone, 0
    je  NotDone
    inc doneCount
    jmp CountNext
NotDone:
    inc upcoming
    mov eax, (DEADLINE PTR [esi]).dueDay
    sub eax, today
    cmp eax, 3
    jg  CountNext                   ; signed: overdue items count as soon
    inc soon
CountNext:
    add esi, SIZEOF DEADLINE
    loop CountLoop
CountDone:
    INVOKE wsprintf, ADDR dlBuf, ADDR szFmtDlSummary, upcoming, soon, doneCount
    mov eax, dLeft
    mov r.left, eax
    INVOKE ScaleDpi, ADD_BTN_W + 16
    mov ecx, dRight
    sub ecx, eax
    mov r.right, ecx
    INVOKE ScaleDpi, TOOLBAR_Y
    mov r.top, eax
    INVOKE ScaleDpi, TOOLBAR_Y + ADD_BTN_H
    mov r.bottom, eax
    INVOKE DrawTextIn, hdc, ADDR dlBuf, ADDR r, hFontBody, curTheme.clrMuted,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS

    cmp userData.deadlineCount, 0
    jne HasItems

    ; ---- empty state ----
    INVOKE ScaleDpi, 180
    add eax, dTop
    mov ebx, eax
    INVOKE FillRound, hdc, dLeft, dTop, dRight, ebx, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder
    mov eax, dLeft
    mov r.left, eax
    mov eax, dRight
    mov r.right, eax
    INVOKE ScaleDpi, 30
    add eax, dTop
    mov r.top, eax
    INVOKE ScaleDpi, 40
    add eax, r.top
    mov r.bottom, eax
    INVOKE DrawGlyph, hdc, GLYPH_BELL, ADDR r, hFontIconLg,
           curTheme.clrMuted, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    mov eax, r.bottom
    add eax, 6
    mov r.top, eax
    INVOKE ScaleDpi, 30
    add eax, r.top
    mov r.bottom, eax
    INVOKE DrawTextIn, hdc, ADDR szDlEmptyTitle, ADDR r, hFontBodyBold,
           curTheme.clrText, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    mov eax, r.bottom
    mov r.top, eax
    INVOKE ScaleDpi, 26
    add eax, r.top
    mov r.bottom, eax
    INVOKE DrawTextIn, hdc, ADDR szDlEmptyText, ADDR r, hFontBody,
           curTheme.clrMuted, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    ret

HasItems:
    ; ---- how many rows to draw ----
    INVOKE DlVisibleRows
    mov visible, eax
    mov ecx, userData.deadlineCount
    sub ecx, scrollTop
    cmp ecx, eax
    jbe @F
    mov ecx, eax
@@: mov shown, ecx

    ; card behind the rows
    mov eax, shown
    mul dRowH
    add eax, dTop
    add eax, 8
    mov ebx, eax
    INVOKE FillRound, hdc, dLeft, dTop, dRight, ebx, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder

    mov k, 0
RowLoop:
    mov eax, k
    cmp eax, shown
    jae RowsDone
    ; y range of this row
    mul dRowH
    add eax, dTop
    add eax, 4
    mov y1, eax
    add eax, dRowH
    mov y2, eax
    mov eax, y1
    add eax, y2
    shr eax, 1
    mov yMid, eax
    ; esi -> deadline number scrollTop + k
    mov eax, scrollTop
    add eax, k
    mov edi, eax                    ; edi = index in the list
    imul eax, eax, SIZEOF DEADLINE
    lea esi, userData.deadlines[eax]
    mov pDl, esi

    ; hover highlight
    cmp edi, hoverDl
    jne NoHover
    INVOKE ScaleDpi, 6
    mov ecx, dLeft
    add ecx, eax
    mov edx, dRight
    sub edx, eax
    mov eax, y1
    add eax, 2
    mov ebx, y2
    sub ebx, 2
    INVOKE FillRound, hdc, ecx, eax, edx, ebx, 8, curTheme.clrBg, curTheme.clrBg
NoHover:
    ; line between rows
    cmp k, 0
    je  NoLine
    INVOKE ScaleDpi, 16
    mov ecx, dLeft
    add ecx, eax
    mov r.left, ecx
    mov ecx, dRight
    sub ecx, eax
    mov r.right, ecx
    mov eax, y1
    mov r.top, eax
    inc eax
    mov r.bottom, eax
    INVOKE FillSolid, hdc, ADDR r, curTheme.clrBorder
NoLine:

    ; ---- done circle ----
    INVOKE DlColumnX, 0
    mov x1, eax
    INVOKE ScaleDpi, 22
    mov ebx, eax                    ; circle size
    mov ecx, x1
    add ecx, ebx
    mov x2, ecx
    mov eax, yMid
    shr ebx, 1
    sub eax, ebx
    mov r.top, eax
    add eax, ebx
    add eax, ebx
    mov r.bottom, eax
    mov eax, x1
    mov r.left, eax
    mov eax, x2
    mov r.right, eax
    cmp (DEADLINE PTR [esi]).isDone, 0
    jne IsDone
    INVOKE FillRound, hdc, r.left, r.top, r.right, r.bottom, 11,
           curTheme.clrCard, curTheme.clrMuted
    jmp CircleDone
IsDone:
    INVOKE FillRound, hdc, r.left, r.top, r.right, r.bottom, 11,
           CLR_SAFE_BG, CLR_SAFE_BG
    INVOKE DrawGlyph, hdc, GLYPH_CHECK, ADDR r, hFontIcon, CLR_SAFE_TX,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
CircleDone:

    ; ---- kind chip ----
    INVOKE DlColumnX, 1
    mov x1, eax
    INVOKE DlColumnX, 2
    sub eax, 16
    mov x2, eax
    mov esi, pDl
    mov ebx, (DEADLINE PTR [esi]).kind
    INVOKE DrawChip, hdc, x1, x2, y1, y2, kindNames[ebx*4], kindBg[ebx*4], kindTx[ebx*4]

    ; ---- title (top half) and course (bottom half) ----
    mov esi, pDl
    mov eax, curTheme.clrText
    cmp (DEADLINE PTR [esi]).isDone, 0
    je  @F
    mov eax, curTheme.clrMuted      ; finished items fade out
@@: mov titleColor, eax
    INVOKE DlColumnX, 2
    mov r.left, eax
    INVOKE DlColumnX, 3
    sub eax, 8
    mov r.right, eax
    INVOKE ScaleDpi, 6
    mov ecx, y1
    add ecx, eax
    mov r.top, ecx
    mov eax, yMid
    inc eax
    mov r.bottom, eax
    INVOKE DrawTextIn, hdc, ADDR (DEADLINE PTR [esi]).dtitle, ADDR r, hFontBodyBold,
           titleColor, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS
    mov eax, yMid
    mov r.top, eax
    INVOKE ScaleDpi, 6
    mov ecx, y2
    sub ecx, eax
    mov r.bottom, ecx
    mov edx, OFFSET szGeneral
    mov eax, (DEADLINE PTR [esi]).course
    cmp eax, -1
    je  @F
    cmp eax, userData.courseCount
    jae @F
    imul eax, eax, SIZEOF COURSE
    lea edx, userData.courses[eax]  ; cname is the first field
@@: INVOKE DrawTextIn, hdc, edx, ADDR r, hFontSmall, curTheme.clrMuted,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS

    ; ---- due date ----
    cmp (DEADLINE PTR [esi]).dueDay, NO_DATE
    jne @F
    INVOKE Str_copy, ADDR szNoDate, ADDR dlBuf
    jmp HaveDate
@@: INVOKE FormatDateShort, (DEADLINE PTR [esi]).dueDay, ADDR dlBuf
HaveDate:
    INVOKE DlColumnX, 3
    mov r.left, eax
    INVOKE DlColumnX, 4
    sub eax, 8
    mov r.right, eax
    mov eax, y1
    mov r.top, eax
    mov eax, y2
    mov r.bottom, eax
    INVOKE DrawTextIn, hdc, ADDR dlBuf, ADDR r, hFontBody, titleColor,
           DT_LEFT OR DT_VCENTER OR DT_SINGLELINE

    ; ---- days-left chip ----
    cmp (DEADLINE PTR [esi]).isDone, 0
    je  NotFinished
    INVOKE Str_copy, ADDR szDoneChip, ADDR dlBuf
    mov eax, curTheme.clrBg
    mov chipBg, eax
    mov eax, curTheme.clrMuted
    mov chipTx, eax
    jmp ChipReady
NotFinished:
    cmp (DEADLINE PTR [esi]).dueDay, NO_DATE
    jne @F
    INVOKE Str_copy, ADDR szNoDueDate, ADDR dlBuf
    mov eax, curTheme.clrBg
    mov chipBg, eax
    mov eax, curTheme.clrMuted
    mov chipTx, eax
    jmp ChipReady
@@: mov eax, (DEADLINE PTR [esi]).dueDay
    sub eax, today                  ; days left (negative = overdue)
    mov chipBg, CLR_DANGER_BG
    mov chipTx, CLR_DANGER_TX
    cmp eax, 0
    jl  ChipOverdue
    je  ChipToday
    cmp eax, 1
    je  ChipTomorrow
    INVOKE wsprintf, ADDR dlBuf, ADDR szFmtInDays, eax
    mov chipBg, CLR_WARN_BG
    mov chipTx, CLR_WARN_TX
    mov eax, (DEADLINE PTR [esi]).dueDay
    sub eax, today
    cmp eax, 3
    jle ChipReady
    mov chipBg, CLR_SAFE_BG
    mov chipTx, CLR_SAFE_TX
    jmp ChipReady
ChipOverdue:
    INVOKE Str_copy, ADDR szOverdue, ADDR dlBuf
    jmp ChipReady
ChipToday:
    INVOKE Str_copy, ADDR szDueToday, ADDR dlBuf
    jmp ChipReady
ChipTomorrow:
    INVOKE Str_copy, ADDR szTomorrow, ADDR dlBuf
ChipReady:
    INVOKE DlColumnX, 4
    mov x1, eax
    INVOKE DlColumnX, DCOL_COUNT
    mov x2, eax
    INVOKE DrawChip, hdc, x1, x2, y1, y2, ADDR dlBuf, chipBg, chipTx

    inc k
    jmp RowLoop
RowsDone:

    ; ---- "Showing 1 - 9 of 14" when not everything fits ----
    mov eax, userData.deadlineCount
    cmp eax, shown
    jbe NoScrollHint
    mov eax, scrollTop
    inc eax
    mov ecx, scrollTop
    add ecx, shown
    INVOKE wsprintf, ADDR dlBuf, ADDR szFmtShowing, eax, ecx, userData.deadlineCount
    mov eax, dLeft
    mov r.left, eax
    mov eax, dRight
    mov r.right, eax
    mov eax, shown
    mul dRowH
    add eax, dTop
    add eax, 14
    mov r.top, eax
    INVOKE ScaleDpi, 26
    add eax, r.top
    mov r.bottom, eax
    INVOKE DrawTextIn, hdc, ADDR dlBuf, ADDR r, hFontSmall, curTheme.clrMuted,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
NoScrollHint:
    ret
PaintDeadlines ENDP

;---------------------------------------------------------------------
; DlHitTest - which deadline is at (x, y)?
; Returns: EAX = index in the list or -1,  ECX = 1 if on the circle
;---------------------------------------------------------------------
DlHitTest PROC USES ebx edx, x:DWORD, y:DWORD
    LOCAL rc:RECT

    INVOKE GetClientRect, hDeadlinesPanel, ADDR rc
    INVOKE DlGeometry, rc.right, rc.bottom
    mov eax, x
    cmp eax, dLeft
    jl  Miss
    cmp eax, dRight
    jge Miss
    mov eax, y
    sub eax, dTop
    sub eax, 4
    jl  Miss
    xor edx, edx
    div dRowH                       ; row on screen
    mov ebx, eax
    INVOKE DlVisibleRows
    cmp ebx, eax
    jae Miss
    add ebx, scrollTop              ; row in the list
    cmp ebx, userData.deadlineCount
    jae Miss
    ; on the done circle?  (left of the kind column)
    INVOKE DlColumnX, 1
    xor ecx, ecx
    cmp x, eax
    jge @F
    mov ecx, 1
@@: mov eax, ebx
    ret
Miss:
    mov eax, -1
    xor ecx, ecx
    ret
DlHitTest ENDP

;---------------------------------------------------------------------
; DeadlinesPanelMsg - messages for the Deadlines screen
; Returns: EAX = result, ECX = 1 if handled
;---------------------------------------------------------------------
DeadlinesPanelMsg PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
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
    cmp uMsg, WM_MOUSEWHEEL
    je  OnWheel
    cmp uMsg, WM_SETCURSOR
    je  OnSetCursor
    jmp NotHandled

OnSize:
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE ScaleDpi, PAGE_MARGIN + ADD_BTN_W
    mov ebx, rc.right
    sub ebx, eax
    INVOKE ScaleDpi, TOOLBAR_Y
    mov esi, eax
    INVOKE ScaleDpi, ADD_BTN_W
    mov edi, eax
    INVOKE ScaleDpi, ADD_BTN_H
    INVOKE MoveWindow, hBtnAddDeadline, ebx, esi, edi, eax, TRUE
    INVOKE DeadlinesChanged         ; keep scrolling in range
    jmp HandledZero

OnDrawItem:
    INVOKE DrawPastelButton, lParam, curTheme.clrBg
    mov eax, TRUE
    jmp Handled

OnCommand:
    mov eax, wParam
    and eax, 0FFFFh
    cmp eax, IDC_ADD_DEADLINE
    jne HandledZero
    cmp userData.deadlineCount, MAX_DEADLINES
    jb  CanAdd
    INVOKE MessageBoxA, hMainWnd, ADDR szDlFullText, ADDR szDlFullTitle,
           MB_OK OR MB_ICONINFORMATION
    jmp HandledZero
CanAdd:
    INVOKE OpenDeadlineDialog, -1
    jmp HandledZero

OnMouseMove:
    mov eax, lParam
    movsx ecx, ax
    sar eax, 16
    INVOKE DlHitTest, ecx, eax
    cmp eax, hoverDl
    je  HandledZero
    mov hoverDl, eax
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    mov tme.cbSize, SIZEOF TRACKMOUSEEVENT
    mov tme.dwFlags, TME_LEAVE
    mov eax, hWnd
    mov tme.hwndTrack, eax
    mov tme.dwHoverTime, 0
    INVOKE TrackMouseEvent, ADDR tme
    jmp HandledZero

OnMouseLeave:
    cmp hoverDl, -1
    je  HandledZero
    mov hoverDl, -1
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero

OnClick:
    mov eax, lParam
    movsx ecx, ax
    sar eax, 16
    INVOKE DlHitTest, ecx, eax
    cmp eax, -1
    je  HandledZero
    cmp ecx, 1
    jne OpenIt
    INVOKE ToggleDone, eax          ; clicked the circle
    jmp HandledZero
OpenIt:
    INVOKE OpenDeadlineDialog, eax
    jmp HandledZero

OnWheel:
    ; high word of wParam = wheel movement (+ up, - down)
    INVOKE DlVisibleRows
    mov ecx, userData.deadlineCount
    sub ecx, eax                    ; largest scrollTop
    jg  @F
    xor ecx, ecx
@@: mov eax, wParam
    sar eax, 16
    cmp eax, 0
    jl  WheelDown
    cmp scrollTop, 0
    je  HandledZero
    dec scrollTop
    jmp WheelRedraw
WheelDown:
    cmp scrollTop, ecx
    jae HandledZero
    inc scrollTop
WheelRedraw:
    mov hoverDl, -1
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero

OnSetCursor:
    cmp hoverDl, -1
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
DeadlinesPanelMsg ENDP

END
