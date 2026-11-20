;=====================================================================
; grades.asm  -  the Grades screen
;
;  +--------------+ +--------------+ +----------------------+
;  | Current CGPA | | Target CGPA  | | Needed this semester |
;  |    3.05      | |   [ 3.20 ]   | |   3.60  (coloured)   |
;  +--------------+ +--------------+ +----------------------+
;  +--------------------------------------+ +-----------------+
;  | This semester   [Reset] [Auto-solve] | | Past semesters  |
;  | COAL      ----O-------------  [B+]   | | Semester 1 3.20 |
;  | need 31 of 50 left                   | | ...             |
;  | ...                                  | | [GPA][Cr] [Add] |
;  | Semester GPA 3.21    New CGPA 3.12   | |                 |
;  +--------------------------------------+ +-----------------+
;
; The grade sliders are drawn by us: 12 positions, F on the left,
; A+ on the right. Dragging one updates every number immediately.
; Auto-solve runs the greedy solver and slides each grade into place
; with a short animation (a Windows timer).
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

GrGeometry      PROTO :DWORD, :DWORD
GrLayout        PROTO
SliderHit       PROTO :DWORD, :DWORD
SemesterHit     PROTO :DWORD, :DWORD
SetSlider       PROTO :DWORD, :DWORD
ThumbX          PROTO :DWORD
GrCard          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
GrText          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
AddSemester     PROTO
RemoveSemester  PROTO :DWORD
FinishSemester  PROTO
RunAutoSolve    PROTO
ResetSliders    PROTO
GradeChipColors PROTO :DWORD
GrGlyphAt       PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD

IDC_GR_TARGET   = 1301
IDC_GR_SEMGPA   = 1302
IDC_GR_SEMCR    = 1303
IDC_GR_SOLVE    = 1310
IDC_GR_RESET    = 1311
IDC_GR_ADDSEM   = 1312
IDC_GR_FINISH   = 1313
TIMER_SOLVE     = 1
SLIDER_STEPS    = 11            ; positions 0..11 -> 12 grades

.data
hGradesPanel    DWORD 0
hGrTarget       DWORD 0
hGrSemGpa       DWORD 0
hGrSemCr        DWORD 0
hGrSolve        DWORD 0
hGrReset        DWORD 0
hGrAddSem       DWORD 0
hGrFinish       DWORD 0
hGrBrush        DWORD 0
dragRow         DWORD -1        ; slider being dragged, -1 = none
hotSpot         DWORD 0         ; 1 when the mouse is over a slider or x
targetDirty     DWORD 0
grFocus         DWORD 0         ; which text box has focus (control ID)

; geometry in real pixels (set by GrGeometry)
gM          DWORD 0             ; page margin
gGap        DWORD 0
gCardW      DWORD 0
gCardsTop   DWORD 0
gCardsBot   DWORD 0
gLowTop     DWORD 0
gLowBot     DWORD 0
gLeftX2     DWORD 0             ; right edge of the sliders card
gRightX1    DWORD 0             ; left edge of the semesters card
gRightX2    DWORD 0
gRowsTop    DWORD 0
gRowH       DWORD 0
gTrackX1    DWORD 0
gTrackX2    DWORD 0
gSemTop     DWORD 0             ; first semester row
gSemRowH    DWORD 0
gAddTop     DWORD 0             ; top of the "add semester" boxes
gBoxH       DWORD 0

szCurrentCgpa   BYTE "Current CGPA", 0
szTargetCgpa    BYTE "Target CGPA", 0
szNeeded        BYTE "Needed this semester", 0
szFmtPastInfo   BYTE "Semesters: %d   |   Credits: %d", 0
szNoPast        BYTE "Add past semesters on the right", 0
szTargetHint    BYTE "e.g. 3.20", 0
szSetTarget     BYTE "Type a target CGPA", 0
szAddCoursesFirst BYTE "Add this semester's courses", 0
szAbove4        BYTE "> 4.00", 0
szDash          BYTE "-", 0
szThisSem       BYTE "This semester", 0
szDragHint      BYTE "Drag a grade, or let Auto-solve pick the easiest path", 0
szNoCourses     BYTE "Add your courses on the Courses screen first.", 0
szFmtFooter     BYTE "Semester GPA  %s          New CGPA  %s", 0
szPastSems      BYTE "Past semesters", 0
szFinishSem     BYTE "Finish semester", 0
szFinTitle      BYTE "Finish this semester", 0
szFinFmt        BYTE "Finish this semester?", 13, 10, 13, 10
                BYTE "Your grades on the sliders give a semester GPA of %s over %d credits. "
                BYTE "It will be saved as Semester %d.", 13, 10, 13, 10
                BYTE "Then this semester's %d courses and their deadlines are cleared, ready for the new semester. "
                BYTE "Set every slider to your real final grade first.", 13, 10, 13, 10
                BYTE "This can't be undone.", 0
szFinNoCourses  BYTE "There are no courses this semester to finish.", 0
szFinFull       BYTE "You already have 12 past semesters.", 0
szFinDoneFmt    BYTE "Semester %d saved with GPA %s. Your CGPA is now %s.", 13, 10, 13, 10
                BYTE "Add the new semester's courses on the Courses screen.", 0
szLogFinish     BYTE "Finished a semester: GPA %s", 0
finMsg          BYTE 512 DUP(0)
finBuf          BYTE 16 DUP(0)
finBuf2         BYTE 16 DUP(0)
szFmtSemName    BYTE "Semester %d", 0
szFmtCredits    BYTE "%d cr", 0
szLblGpa        BYTE "GPA", 0
szLblCr         BYTE "Credits", 0
szNoSems        BYTE "None yet. First semester? Leave this empty.", 0
szSolve         BYTE "Auto-solve", 0
szReset         BYTE "Reset", 0
szAddSem        BYTE "Add", 0
szFmtNeed       BYTE "Final: need %s of %s left", 0
szSecured       BYTE "Already secured with current marks", 0
szOutOfReach    BYTE "Out of reach with the marks left", 0
szNoMarksYet    BYTE "Add marks in Courses to see what you need", 0
szFmtChip       BYTE "%s   %s", 0
szFmtSolved     BYTE "Easiest path found: semester GPA %s", 0
szSolveNoTarget BYTE "Set a target CGPA first.", 0
szSolveNoCourse BYTE "Add your courses first.", 0
szSolveTooHigh  BYTE "Even straight A's can't reach this target this semester.", 0
szSolveBlocked  BYTE "Not reachable with the marks still available.", 0
szErrSemGpa     BYTE "GPA must be 0.00 - 4.00", 0
szErrSemCr      BYTE "Credits must be 1 - 30", 0
szErrSemFull    BYTE "Up to 12 semesters", 0
szRemoveTitle   BYTE "Remove semester", 0
szFmtRemove     BYTE "Remove Semester %d (GPA %s, %d credits)?", 0
szEmptyStr      BYTE 0
szLogSemAdd     BYTE "Past semester added: GPA %s", 0
szLogSemDel     BYTE "Past semester removed", 0

solverMsg   BYTE 96 DUP(0)
semError    BYTE 64 DUP(0)
grBuf       BYTE 128 DUP(0)
grBuf2      BYTE 32 DUP(0)
grBuf3      BYTE 32 DUP(0)

GLYPH_REMOVE = 0E711h           ; small x

.code
;---------------------------------------------------------------------
; GradesInit - creates the text boxes and buttons of the screen
;---------------------------------------------------------------------
GradesInit PROC hPanel:DWORD
    mov eax, hPanel
    mov hGradesPanel, eax
    mov dragRow, -1
    mov solverMsg, 0
    mov semError, 0
    INVOKE CreateSolidBrush, curTheme.clrCard
    mov hGrBrush, eax

    INVOKE CreateField, hPanel, IDC_GR_TARGET, 0, 4
    mov hGrTarget, eax
    INVOKE CreateField, hPanel, IDC_GR_SEMGPA, 0, 4
    mov hGrSemGpa, eax
    INVOKE CreateField, hPanel, IDC_GR_SEMCR, ES_NUMBER, 2
    mov hGrSemCr, eax
    INVOKE CreatePastelButton, hPanel, ADDR szSolve, IDC_GR_SOLVE, BTN_PRIMARY
    mov hGrSolve, eax
    INVOKE CreatePastelButton, hPanel, ADDR szReset, IDC_GR_RESET, BTN_SECONDARY
    mov hGrReset, eax
    INVOKE CreatePastelButton, hPanel, ADDR szAddSem, IDC_GR_ADDSEM, BTN_SECONDARY
    mov hGrAddSem, eax
    INVOKE CreatePastelButton, hPanel, ADDR szFinishSem, IDC_GR_FINISH, BTN_LINK
    mov hGrFinish, eax

    ; show the saved target
    cmp userData.targetCgpa, 0
    je  @F
    INVOKE FormatFixed2, userData.targetCgpa, ADDR grBuf
    INVOKE SetWindowTextA, hGrTarget, ADDR grBuf
@@: mov targetDirty, 0
    ret
GradesInit ENDP

;---------------------------------------------------------------------
; GrGeometry - every position on the screen for its current size
;---------------------------------------------------------------------
GrGeometry PROC USES ebx ecx edx, clientW:DWORD, clientH:DWORD
    INVOKE ScaleDpi, PAGE_MARGIN
    mov gM, eax
    INVOKE ScaleDpi, 16
    mov gGap, eax
    ; three cards in a row
    mov eax, clientW
    sub eax, gM
    sub eax, gM
    sub eax, gGap
    sub eax, gGap
    xor edx, edx
    mov ecx, 3
    div ecx
    mov gCardW, eax
    INVOKE ScaleDpi, 104
    mov gCardsTop, eax
    INVOKE ScaleDpi, 104 + 112
    mov gCardsBot, eax
    ; lower area: sliders card (62%) and semesters card
    INVOKE ScaleDpi, 234
    mov gLowTop, eax
    INVOKE ScaleDpi, 20
    mov ecx, clientH
    sub ecx, eax
    mov gLowBot, ecx
    mov eax, clientW
    sub eax, gM
    sub eax, gM
    sub eax, gGap
    imul eax, eax, 62
    xor edx, edx
    mov ecx, 100
    div ecx
    add eax, gM
    mov gLeftX2, eax
    add eax, gGap
    mov gRightX1, eax
    mov eax, clientW
    sub eax, gM
    mov gRightX2, eax

    ; slider rows
    INVOKE ScaleDpi, 66
    add eax, gLowTop
    mov gRowsTop, eax
    INVOKE ScaleDpi, 54
    mov gRowH, eax
    mov ecx, userData.courseCount
    cmp ecx, 0
    je  @F
    INVOKE ScaleDpi, 52             ; footer
    mov ebx, gLowBot
    sub ebx, eax
    sub ebx, gRowsTop               ; room for rows
    mov eax, ebx
    xor edx, edx
    div ecx
    cmp eax, gRowH
    jae @F
    mov gRowH, eax                  ; many courses: shorter rows
@@: INVOKE ScaleDpi, 206
    add eax, gM
    mov gTrackX1, eax
    INVOKE ScaleDpi, 120
    mov ecx, gLeftX2
    sub ecx, eax
    mov gTrackX2, ecx

    ; semesters card
    INVOKE ScaleDpi, 60
    add eax, gLowTop
    mov gSemTop, eax
    INVOKE ScaleDpi, 32
    mov gSemRowH, eax
    INVOKE ScaleDpi, 40
    mov gBoxH, eax
    INVOKE ScaleDpi, 20 + 40
    mov ecx, gLowBot
    sub ecx, eax
    mov gAddTop, ecx
    ret
GrGeometry ENDP

;---------------------------------------------------------------------
; GrLayout - moves the text boxes and buttons into place
;---------------------------------------------------------------------
GrLayout PROC USES ebx esi edi
    LOCAL rc:RECT, inset:DWORD, editH:DWORD, x:DWORD, w:DWORD, posY:DWORD

    INVOKE GetClientRect, hGradesPanel, ADDR rc
    INVOKE GrGeometry, rc.right, rc.bottom
    INVOKE ScaleDpi, 12
    mov inset, eax
    INVOKE ScaleDpi, 22
    mov editH, eax

    ; target box inside the middle card
    INVOKE ScaleDpi, 20
    add eax, gM
    add eax, gCardW
    add eax, gGap                   ; card 2 left + 20 = box left
    add eax, inset
    mov x, eax
    INVOKE ScaleDpi, 110 - 24
    mov w, eax
    INVOKE ScaleDpi, 46 + 9
    add eax, gCardsTop
    mov posY, eax
    INVOKE MoveWindow, hGrTarget, x, posY, w, editH, TRUE

    ; buttons in the sliders card header
    INVOKE ScaleDpi, 14
    add eax, gLowTop
    mov posY, eax
    INVOKE ScaleDpi, 20 + 130
    mov ebx, gLeftX2
    sub ebx, eax
    INVOKE ScaleDpi, 36
    mov edi, eax
    INVOKE ScaleDpi, 130
    INVOKE MoveWindow, hGrSolve, ebx, posY, eax, edi, TRUE
    INVOKE ScaleDpi, 8 + 90
    sub ebx, eax
    INVOKE ScaleDpi, 90
    INVOKE MoveWindow, hGrReset, ebx, posY, eax, edi, TRUE

    ; "add semester" row: [GPA] [Credits] [Add]
    INVOKE ScaleDpi, 20
    add eax, gRightX1
    mov ebx, eax                    ; GPA box left
    mov eax, gBoxH
    sub eax, editH
    shr eax, 1
    add eax, gAddTop
    mov posY, eax
    lea ecx, [ebx]
    add ecx, inset
    INVOKE ScaleDpi, 80 - 24
    INVOKE MoveWindow, hGrSemGpa, ecx, posY, eax, editH, TRUE
    INVOKE ScaleDpi, 80 + 8
    add ebx, eax                    ; credits box left
    mov ecx, ebx
    add ecx, inset
    INVOKE ScaleDpi, 70 - 24
    INVOKE MoveWindow, hGrSemCr, ecx, posY, eax, editH, TRUE
    INVOKE ScaleDpi, 70 + 8
    add ebx, eax                    ; Add button left
    INVOKE ScaleDpi, 20
    mov ecx, gRightX2
    sub ecx, eax
    sub ecx, ebx                    ; button width
    INVOKE MoveWindow, hGrAddSem, ebx, gAddTop, ecx, gBoxH, TRUE

    ; "Finish semester" in the top-right corner of the semesters card
    INVOKE ScaleDpi, 12 + 150
    mov ebx, gRightX2
    sub ebx, eax
    INVOKE ScaleDpi, 10
    add eax, gLowTop
    mov esi, eax
    INVOKE ScaleDpi, 34
    mov edi, eax
    INVOKE ScaleDpi, 150
    INVOKE MoveWindow, hGrFinish, ebx, esi, eax, edi, TRUE
    ret
GrLayout ENDP

;---------------------------------------------------------------------
; GrCard - white rounded card (or a coloured one)
;---------------------------------------------------------------------
GrCard PROC hdc:DWORD, x1:DWORD, y1:DWORD, x2:DWORD, y2:DWORD, fillColor:DWORD
    mov eax, curTheme.clrBorder
    mov ecx, fillColor
    cmp ecx, curTheme.clrCard
    je  @F
    mov eax, ecx                    ; coloured card: no grey border
@@: INVOKE FillRound, hdc, x1, y1, x2, y2, CARD_RADIUS, fillColor, eax
    ret
GrCard ENDP

;---------------------------------------------------------------------
; GrText - text in the rectangle x1,y1 - x2,y2
;---------------------------------------------------------------------
GrText PROC hdc:DWORD, pText:DWORD, x1:DWORD, y1:DWORD, x2:DWORD, y2:DWORD,
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
GrText ENDP

;---------------------------------------------------------------------
; ThumbX - x of a slider thumb for grade index 'grade'
; position p = 11 - grade  (F on the left, A+ on the right)
;---------------------------------------------------------------------
ThumbX PROC USES ecx edx, grade:DWORD
    mov eax, SLIDER_STEPS
    sub eax, grade
    mov ecx, gTrackX2
    sub ecx, gTrackX1
    mul ecx
    mov ecx, SLIDER_STEPS
    div ecx
    add eax, gTrackX1
    ret
ThumbX ENDP

;---------------------------------------------------------------------
; GradeChipColors - colour of a grade label: B or better green,
; C or better yellow, lower red.  Returns EAX = bg, ECX = text
;---------------------------------------------------------------------
GradeChipColors PROC grade:DWORD
    mov eax, grade
    mov eax, gradeGP[eax*4]
    cmp eax, 300
    jae Good
    cmp eax, 200
    jae Middle
    mov eax, CLR_DANGER_BG
    mov ecx, CLR_DANGER_TX
    ret
Good:
    mov eax, CLR_SAFE_BG
    mov ecx, CLR_SAFE_TX
    ret
Middle:
    mov eax, CLR_WARN_BG
    mov ecx, CLR_WARN_TX
    ret
GradeChipColors ENDP

;---------------------------------------------------------------------
; PaintGrades - the whole screen below the title
;---------------------------------------------------------------------
PaintGrades PROC USES ebx esi edi, hdc:DWORD, clientW:DWORD, clientH:DWORD
    LOCAL x1:DWORD, x2:DWORD, y1:DWORD, y2:DWORD, pad:DWORD, value:DWORD,
          status:DWORD, zoneBg:DWORD, zoneTx:DWORD, zoneLabel:DWORD,
          row:DWORD, yMid:DWORD, grade:DWORD, chipBg:DWORD, chipTx:DWORD,
          thumb:DWORD, radius:DWORD, pastCr:DWORD, needVal:DWORD,
          remVal:DWORD, predText:DWORD, predColor:DWORD

    INVOKE GrGeometry, clientW, clientH
    INVOKE ScaleDpi, 20
    mov pad, eax

    ;================ card 1: current CGPA ================
    mov eax, gM
    mov x1, eax
    add eax, gCardW
    mov x2, eax
    INVOKE GrCard, hdc, x1, gCardsTop, x2, gCardsBot, curTheme.clrCard
    mov ebx, x1
    add ebx, pad
    mov esi, x2
    sub esi, pad
    INVOKE ScaleDpi, 14
    add eax, gCardsTop
    mov y1, eax
    INVOKE ScaleDpi, 22
    add eax, y1
    mov y2, eax
    INVOKE GrText, hdc, ADDR szCurrentCgpa, ebx, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_LEFT
    INVOKE CalcPast
    mov pastCr, ecx
    INVOKE CurrentCgpa
    mov value, eax
    mov eax, y2
    mov y1, eax
    INVOKE ScaleDpi, 44
    add eax, y1
    mov y2, eax
    cmp value, -1
    je  NoPast
    INVOKE FormatFixed2, value, ADDR grBuf
    INVOKE GrText, hdc, ADDR grBuf, ebx, y1, esi, y2, hFontTitle, curTheme.clrText, DT_LEFT
    INVOKE wsprintf, ADDR grBuf, ADDR szFmtPastInfo, userData.semCount, pastCr
    jmp PastInfo
NoPast:
    INVOKE GrText, hdc, ADDR szDash, ebx, y1, esi, y2, hFontTitle, curTheme.clrMuted, DT_LEFT
    INVOKE Str_copy, ADDR szNoPast, ADDR grBuf
PastInfo:
    mov eax, y2
    mov y1, eax
    INVOKE ScaleDpi, 22
    add eax, y1
    mov y2, eax
    INVOKE GrText, hdc, ADDR grBuf, ebx, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_LEFT

    ;================ card 2: target CGPA ================
    mov eax, x2
    add eax, gGap
    mov x1, eax
    add eax, gCardW
    mov x2, eax
    INVOKE GrCard, hdc, x1, gCardsTop, x2, gCardsBot, curTheme.clrCard
    mov ebx, x1
    add ebx, pad
    mov esi, x2
    sub esi, pad
    INVOKE ScaleDpi, 14
    add eax, gCardsTop
    mov y1, eax
    INVOKE ScaleDpi, 22
    add eax, y1
    mov y2, eax
    INVOKE GrText, hdc, ADDR szTargetCgpa, ebx, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_LEFT
    ; box around the target text box
    INVOKE ScaleDpi, 46
    add eax, gCardsTop
    mov y1, eax
    add eax, gBoxH
    mov y2, eax
    INVOKE ScaleDpi, 110
    add eax, ebx
    mov edi, eax                    ; box right
    xor ecx, ecx
    cmp grFocus, IDC_GR_TARGET
    jne @F
    inc ecx
@@: INVOKE DrawFieldBox, hdc, ebx, y1, edi, y2, ecx
    INVOKE ScaleDpi, 12
    add edi, eax
    INVOKE GrText, hdc, ADDR szTargetHint, edi, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_LEFT

    ;================ card 3: needed this semester ================
    mov eax, x2
    add eax, gGap
    mov x1, eax
    add eax, gCardW
    mov x2, eax
    INVOKE RequiredGpa
    mov value, eax
    mov status, edx
    ; colours: grey card while there is nothing to compute
    mov eax, curTheme.clrCard
    mov zoneBg, eax
    mov eax, curTheme.clrText
    mov zoneTx, eax
    cmp status, 0
    jne @F
    INVOKE GpaZone, value
    mov zoneBg, eax
    mov zoneTx, ecx
    mov zoneLabel, edx
@@: INVOKE GrCard, hdc, x1, gCardsTop, x2, gCardsBot, zoneBg
    mov ebx, x1
    add ebx, pad
    mov esi, x2
    sub esi, pad
    INVOKE ScaleDpi, 14
    add eax, gCardsTop
    mov y1, eax
    INVOKE ScaleDpi, 22
    add eax, y1
    mov y2, eax
    INVOKE GrText, hdc, ADDR szNeeded, ebx, y1, esi, y2, hFontSmall, zoneTx, DT_LEFT
    mov eax, y2
    mov y1, eax
    INVOKE ScaleDpi, 44
    add eax, y1
    mov y2, eax
    cmp status, 1
    jne @F
    INVOKE GrText, hdc, ADDR szDash, ebx, y1, esi, y2, hFontTitle, curTheme.clrMuted, DT_LEFT
    mov edi, OFFSET szSetTarget
    jmp NeededInfo
@@: cmp status, 2
    jne @F
    INVOKE GrText, hdc, ADDR szDash, ebx, y1, esi, y2, hFontTitle, curTheme.clrMuted, DT_LEFT
    mov edi, OFFSET szAddCoursesFirst
    jmp NeededInfo
@@: cmp value, 400
    jbe @F
    INVOKE Str_copy, ADDR szAbove4, ADDR grBuf
    jmp ShowNeeded
@@: INVOKE FormatFixed2, value, ADDR grBuf
ShowNeeded:
    INVOKE GrText, hdc, ADDR grBuf, ebx, y1, esi, y2, hFontTitle, zoneTx, DT_LEFT
    mov edi, zoneLabel
NeededInfo:
    mov eax, y2
    mov y1, eax
    INVOKE ScaleDpi, 22
    add eax, y1
    mov y2, eax
    INVOKE GrText, hdc, edi, ebx, y1, esi, y2, hFontSmall, zoneTx, DT_LEFT

    ;================ sliders card ================
    INVOKE GrCard, hdc, gM, gLowTop, gLeftX2, gLowBot, curTheme.clrCard
    mov ebx, gM
    add ebx, pad
    INVOKE ScaleDpi, 14
    add eax, gLowTop
    mov y1, eax
    INVOKE ScaleDpi, 26
    add eax, y1
    mov y2, eax
    INVOKE ScaleDpi, 250
    mov esi, gLeftX2
    sub esi, eax
    INVOKE GrText, hdc, ADDR szThisSem, ebx, y1, esi, y2, hFontBodyBold, curTheme.clrText, DT_LEFT
    mov eax, y2
    mov y1, eax
    INVOKE ScaleDpi, 20
    add eax, y1
    mov y2, eax
    mov edi, OFFSET szDragHint
    cmp solverMsg, 0
    je  @F
    mov edi, OFFSET solverMsg
@@: INVOKE ScaleDpi, 20 + 130 + 8 + 90 + 8   ; stop before the buttons
    mov esi, gLeftX2
    sub esi, eax
    INVOKE GrText, hdc, edi, ebx, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_LEFT

    cmp userData.courseCount, 0
    jne HasCourses
    INVOKE ScaleDpi, 20
    mov esi, gLeftX2
    sub esi, eax
    mov eax, gRowsTop
    mov y1, eax
    INVOKE ScaleDpi, 40
    add eax, y1
    mov y2, eax
    INVOKE GrText, hdc, ADDR szNoCourses, ebx, y1, esi, y2, hFontBody, curTheme.clrMuted, DT_LEFT
    jmp SemestersCard

HasCourses:
    INVOKE ScaleDpi, 9
    mov radius, eax
    mov row, 0
    mov esi, OFFSET userData.courses
RowLoop:
    mov eax, row
    cmp eax, userData.courseCount
    jae RowsDone
    mul gRowH
    add eax, gRowsTop
    mov y1, eax
    add eax, gRowH
    mov y2, eax
    mov eax, y1
    add eax, y2
    shr eax, 1
    mov yMid, eax
    mov eax, (COURSE PTR [esi]).sliderGrade
    mov grade, eax

    ; ---- name (top half) and marks predictor (bottom half) ----
    mov ebx, gM
    add ebx, pad
    INVOKE ScaleDpi, 16
    mov edi, gTrackX1
    sub edi, eax                    ; right edge of the name column
    INVOKE ScaleDpi, 2
    mov ecx, yMid
    add ecx, eax
    INVOKE GrText, hdc, esi, ebx, y1, edi, ecx, hFontBodyBold, curTheme.clrText, DT_LEFT

    ; marks predictor for the grade on the slider
    INVOKE MarksNeeded, esi, grade  ; eax = need, ecx = left, edx = status
    mov needVal, eax
    mov remVal, ecx
    mov predText, OFFSET szNoMarksYet
    mov eax, curTheme.clrMuted
    mov predColor, eax
    cmp edx, 3
    je  PredDone
    mov predText, OFFSET szSecured
    mov predColor, CLR_SAFE_TX
    cmp edx, 1
    je  PredDone
    mov predText, OFFSET szOutOfReach
    mov predColor, CLR_DANGER_TX
    cmp edx, 2
    je  PredDone
    ; "Final: need 31.5 of 50 left"
    INVOKE FormatTenths, needVal, ADDR grBuf2
    INVOKE FormatTenths, remVal, ADDR grBuf3
    INVOKE wsprintf, ADDR grBuf, ADDR szFmtNeed, ADDR grBuf2, ADDR grBuf3
    mov predText, OFFSET grBuf
    mov eax, curTheme.clrMuted
    mov predColor, eax
PredDone:
    INVOKE ScaleDpi, 2
    mov edx, yMid
    sub edx, eax
    INVOKE GrText, hdc, predText, ebx, edx, edi, y2, hFontSmall, predColor, DT_LEFT

    ; ---- slider: track, filled part, thumb ----
    INVOKE ScaleDpi, 3
    mov ecx, yMid
    sub ecx, eax
    mov edx, yMid
    add edx, eax
    INVOKE FillRound, hdc, gTrackX1, ecx, gTrackX2, edx, 3,
           curTheme.clrBorder, curTheme.clrBorder
    INVOKE ThumbX, grade
    mov thumb, eax
    INVOKE ScaleDpi, 3
    mov ecx, yMid
    sub ecx, eax
    mov edx, yMid
    add edx, eax
    INVOKE FillRound, hdc, gTrackX1, ecx, thumb, edx, 3,
           curTheme.clrAccent, curTheme.clrAccent
    mov ebx, thumb
    sub ebx, radius
    mov edi, thumb
    add edi, radius
    mov ecx, yMid
    sub ecx, radius
    mov edx, yMid
    add edx, radius
    INVOKE FillRound, hdc, ebx, ecx, edi, edx, 9,
           curTheme.clrCard, curTheme.clrAccentText

    ; ---- grade chip: "B+   3.33" ----
    INVOKE GradeName, grade
    mov ebx, eax
    mov ecx, grade
    INVOKE FormatFixed2, gradeGP[ecx*4], ADDR grBuf2
    INVOKE wsprintf, ADDR grBuf, ADDR szFmtChip, ebx, ADDR grBuf2
    INVOKE GradeChipColors, grade
    mov chipBg, eax
    mov chipTx, ecx
    INVOKE ScaleDpi, 100
    mov ebx, gLeftX2
    sub ebx, eax
    INVOKE ScaleDpi, 16
    mov edi, gLeftX2
    sub edi, eax
    INVOKE ScaleDpi, 13
    mov ecx, yMid
    sub ecx, eax
    mov edx, yMid
    add edx, eax
    mov y1, ecx
    mov y2, edx
    INVOKE FillRound, hdc, ebx, y1, edi, y2, 13, chipBg, chipBg
    INVOKE GrText, hdc, ADDR grBuf, ebx, y1, edi, y2, hFontSmall, chipTx, DT_CENTER

    add esi, SIZEOF COURSE
    inc row
    jmp RowLoop
RowsDone:

    ; ---- footer: semester GPA and new CGPA ----
    INVOKE CalcSemester
    mov ebx, eax
    mov edi, ecx
    mov eax, ebx
    mov ecx, edi
    call SemesterGpaRounded
    INVOKE FormatFixed2, eax, ADDR grBuf2
    INVOKE NewCgpa
    INVOKE FormatFixed2, eax, ADDR grBuf3
    INVOKE wsprintf, ADDR grBuf, ADDR szFmtFooter, ADDR grBuf2, ADDR grBuf3
    INVOKE ScaleDpi, 46
    mov ecx, gLowBot
    sub ecx, eax
    mov y1, ecx
    INVOKE ScaleDpi, 8
    mov ecx, gLowBot
    sub ecx, eax
    mov y2, ecx
    mov ebx, gM
    add ebx, pad
    mov esi, gLeftX2
    sub esi, pad
    INVOKE GrText, hdc, ADDR grBuf, ebx, y1, esi, y2, hFontBodyBold, curTheme.clrSideActText, DT_LEFT

SemestersCard:
    ;================ past semesters card ================
    INVOKE GrCard, hdc, gRightX1, gLowTop, gRightX2, gLowBot, curTheme.clrCard
    mov ebx, gRightX1
    add ebx, pad
    mov esi, gRightX2
    sub esi, pad
    INVOKE ScaleDpi, 14
    add eax, gLowTop
    mov y1, eax
    INVOKE ScaleDpi, 26
    add eax, y1
    mov y2, eax
    INVOKE GrText, hdc, ADDR szPastSems, ebx, y1, esi, y2, hFontBodyBold, curTheme.clrText, DT_LEFT

    cmp userData.semCount, 0
    jne HasSems
    mov eax, gSemTop
    mov y1, eax
    add eax, gSemRowH
    mov y2, eax
    INVOKE GrText, hdc, ADDR szNoSems, ebx, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_LEFT
    jmp AddRow
HasSems:
    mov row, 0
SemLoop:
    mov eax, row
    cmp eax, userData.semCount
    jae AddRow
    mul gSemRowH
    add eax, gSemTop
    mov y1, eax
    add eax, gSemRowH
    mov y2, eax
    ; stop before the add row
    INVOKE ScaleDpi, 26
    mov ecx, gAddTop
    sub ecx, eax
    cmp y2, ecx
    ja  AddRow
    ; "Semester 2"
    mov eax, row
    inc eax
    INVOKE wsprintf, ADDR grBuf, ADDR szFmtSemName, eax
    INVOKE GrText, hdc, ADDR grBuf, ebx, y1, esi, y2, hFontBody, curTheme.clrText, DT_LEFT
    ; GPA and credits
    mov eax, row
    imul eax, eax, SIZEOF SEMESTER
    lea edi, userData.semesters[eax]
    INVOKE FormatFixed2, (SEMESTER PTR [edi]).semGpa, ADDR grBuf
    mov eax, esi
    sub eax, ebx
    imul eax, eax, 48
    xor edx, edx
    mov ecx, 100
    div ecx
    add eax, ebx
    mov x1, eax
    INVOKE GrText, hdc, ADDR grBuf, x1, y1, esi, y2, hFontBodyBold, curTheme.clrText, DT_LEFT
    INVOKE wsprintf, ADDR grBuf, ADDR szFmtCredits, (SEMESTER PTR [edi]).semCredits
    mov eax, esi
    sub eax, ebx
    imul eax, eax, 70
    xor edx, edx
    mov ecx, 100
    div ecx
    add eax, ebx
    mov x1, eax
    INVOKE GrText, hdc, ADDR grBuf, x1, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_LEFT
    ; remove "x" at the right end of the row
    INVOKE ScaleDpi, 24
    mov ecx, esi
    sub ecx, eax
    mov x1, ecx
    INVOKE GrGlyphAt, hdc, x1, y1, esi, y2
    inc row
    jmp SemLoop

AddRow:
    ; labels and boxes of the "add semester" row
    INVOKE ScaleDpi, 22
    mov ecx, gAddTop
    sub ecx, eax
    mov y1, ecx
    mov eax, gAddTop
    mov y2, eax
    INVOKE ScaleDpi, 80
    lea edi, [ebx + eax]
    INVOKE GrText, hdc, ADDR szLblGpa, ebx, y1, edi, y2, hFontSmall, curTheme.clrText, DT_LEFT
    INVOKE ScaleDpi, 8
    add edi, eax
    INVOKE ScaleDpi, 70
    lea ecx, [edi + eax]
    mov x2, ecx
    INVOKE GrText, hdc, ADDR szLblCr, edi, y1, x2, y2, hFontSmall, curTheme.clrText, DT_LEFT
    ; error text (right of the labels)
    cmp semError, 0
    je  @F
    INVOKE ScaleDpi, 8
    mov ecx, x2
    add ecx, eax
    INVOKE GrText, hdc, ADDR semError, ecx, y1, esi, y2, hFontSmall, CLR_DANGER_TX, DT_LEFT
@@: mov eax, gAddTop
    mov y1, eax
    add eax, gBoxH
    mov y2, eax
    INVOKE ScaleDpi, 80
    lea edi, [ebx + eax]
    xor ecx, ecx
    cmp grFocus, IDC_GR_SEMGPA
    jne @F
    inc ecx
@@: INVOKE DrawFieldBox, hdc, ebx, y1, edi, y2, ecx
    INVOKE ScaleDpi, 8
    add edi, eax
    INVOKE ScaleDpi, 70
    lea ebx, [edi + eax]
    xor ecx, ecx
    cmp grFocus, IDC_GR_SEMCR
    jne @F
    inc ecx
@@: INVOKE DrawFieldBox, hdc, edi, y1, ebx, y2, ecx
    ret
PaintGrades ENDP

;---------------------------------------------------------------------
; GrGlyphAt (helper) - the small "x" remove icon in a rectangle
;---------------------------------------------------------------------
GrGlyphAt PROC hdc:DWORD, x1:DWORD, y1:DWORD, x2:DWORD, y2:DWORD
    LOCAL r:RECT
    mov eax, x1
    mov r.left, eax
    mov eax, y1
    mov r.top, eax
    mov eax, x2
    mov r.right, eax
    mov eax, y2
    mov r.bottom, eax
    INVOKE DrawGlyph, hdc, GLYPH_REMOVE, ADDR r, hFontIcon, curTheme.clrMuted,
           DT_RIGHT OR DT_VCENTER OR DT_SINGLELINE
    ret
GrGlyphAt ENDP

;---------------------------------------------------------------------
; SemesterGpaRounded (helper) - EAX = points / credits (ECX), 0 if none
;---------------------------------------------------------------------
SemesterGpaRounded PROC USES ebx edx
    cmp ecx, 0
    jne @F
    xor eax, eax
    ret
@@: mov ebx, ecx
    shr ebx, 1
    add eax, ebx
    xor edx, edx
    div ecx
    ret
SemesterGpaRounded ENDP

;---------------------------------------------------------------------
; SliderHit - slider row at (x, y), or -1
;---------------------------------------------------------------------
SliderHit PROC USES ecx edx, x:DWORD, y:DWORD
    LOCAL rc:RECT
    INVOKE GetClientRect, hGradesPanel, ADDR rc
    INVOKE GrGeometry, rc.right, rc.bottom
    INVOKE ScaleDpi, 14
    mov ecx, gTrackX1
    sub ecx, eax
    cmp x, ecx
    jl  Miss
    mov ecx, gTrackX2
    add ecx, eax
    cmp x, ecx
    jg  Miss
    mov eax, y
    sub eax, gRowsTop
    jl  Miss
    xor edx, edx
    div gRowH
    cmp eax, userData.courseCount
    jae Miss
    ret
Miss:
    mov eax, -1
    ret
SliderHit ENDP

;---------------------------------------------------------------------
; SemesterHit - semester row whose "x" is at (x, y), or -1
;---------------------------------------------------------------------
SemesterHit PROC USES ecx edx, x:DWORD, y:DWORD
    LOCAL rc:RECT
    INVOKE GetClientRect, hGradesPanel, ADDR rc
    INVOKE GrGeometry, rc.right, rc.bottom
    INVOKE ScaleDpi, 20 + 28
    mov ecx, gRightX2
    sub ecx, eax
    cmp x, ecx
    jl  Miss
    mov eax, y
    sub eax, gSemTop
    jl  Miss
    xor edx, edx
    div gSemRowH
    cmp eax, userData.semCount
    jae Miss
    ret
Miss:
    mov eax, -1
    ret
SemesterHit ENDP

;---------------------------------------------------------------------
; SetSlider - moves slider 'row' to the grade under x
;---------------------------------------------------------------------
SetSlider PROC USES ebx ecx edx esi, row:DWORD, x:DWORD
    ; position p = round((x - x1) * 11 / (x2 - x1)), clamped to 0..11
    mov eax, x
    sub eax, gTrackX1
    jge @F
    xor eax, eax
@@: imul eax, eax, SLIDER_STEPS
    mov ecx, gTrackX2
    sub ecx, gTrackX1
    mov ebx, ecx
    shr ebx, 1
    add eax, ebx                    ; + half a step for rounding
    xor edx, edx
    div ecx
    cmp eax, SLIDER_STEPS
    jbe @F
    mov eax, SLIDER_STEPS
@@: mov ebx, SLIDER_STEPS
    sub ebx, eax                    ; grade index = 11 - p
    mov eax, row
    imul eax, eax, SIZEOF COURSE
    lea esi, userData.courses[eax]
    cmp (COURSE PTR [esi]).sliderGrade, ebx
    je  Done
    mov (COURSE PTR [esi]).sliderGrade, ebx
    mov solverMsg, 0
    INVOKE InvalidateRect, hGradesPanel, NULL, FALSE
Done:
    ret
SetSlider ENDP

;---------------------------------------------------------------------
; AddSemester - reads the GPA and credits boxes and adds a semester
;---------------------------------------------------------------------
AddSemester PROC USES ebx esi
    LOCAL gpa:DWORD

    mov semError, 0
    cmp userData.semCount, MAX_SEMESTERS
    jb  @F
    INVOKE Str_copy, ADDR szErrSemFull, ADDR semError
    jmp Fail
@@: INVOKE GetWindowTextA, hGrSemGpa, ADDR grBuf2, SIZEOF grBuf2
    INVOKE ParseFixed2, ADDR grBuf2
    cmp edx, 0
    je  BadGpa
    cmp ecx, 0
    je  BadGpa
    cmp eax, 400
    ja  BadGpa
    mov gpa, eax
    INVOKE GetWindowTextA, hGrSemCr, ADDR grBuf2, SIZEOF grBuf2
    INVOKE ParseUInt, ADDR grBuf2
    cmp eax, 1
    jb  BadCr
    cmp eax, 30
    ja  BadCr
    mov ebx, eax

    mov eax, userData.semCount
    imul eax, eax, SIZEOF SEMESTER
    lea esi, userData.semesters[eax]
    mov eax, gpa
    mov (SEMESTER PTR [esi]).semGpa, eax
    mov (SEMESTER PTR [esi]).semCredits, ebx
    inc userData.semCount
    INVOKE FormatFixed2, gpa, ADDR grBuf3
    INVOKE LogEventFmt, ADDR szLogSemAdd, ADDR grBuf3
    INVOKE SetWindowTextA, hGrSemGpa, ADDR szEmptyStr
    INVOKE SetWindowTextA, hGrSemCr, ADDR szEmptyStr
    INVOKE SaveWithStatus
    INVOKE InvalidateRect, hGradesPanel, NULL, FALSE
    INVOKE SetFocus, hGrSemGpa
    ret
BadGpa:
    INVOKE Str_copy, ADDR szErrSemGpa, ADDR semError
    INVOKE SetFocus, hGrSemGpa
    jmp Fail
BadCr:
    INVOKE Str_copy, ADDR szErrSemCr, ADDR semError
    INVOKE SetFocus, hGrSemCr
Fail:
    INVOKE MessageBeep, MB_OK
    INVOKE InvalidateRect, hGradesPanel, NULL, FALSE
    ret
AddSemester ENDP

;---------------------------------------------------------------------
; RemoveSemester - asks, then removes semester 'index'
;---------------------------------------------------------------------
RemoveSemester PROC USES ebx ecx esi edi, index:DWORD
    mov eax, index
    imul eax, eax, SIZEOF SEMESTER
    lea ebx, userData.semesters[eax]
    INVOKE FormatFixed2, (SEMESTER PTR [ebx]).semGpa, ADDR grBuf2
    mov eax, index
    inc eax
    INVOKE wsprintf, ADDR grBuf, ADDR szFmtRemove, eax, ADDR grBuf2,
           (SEMESTER PTR [ebx]).semCredits
    INVOKE MessageBoxA, hMainWnd, ADDR grBuf, ADDR szRemoveTitle,
           MB_YESNO OR MB_ICONQUESTION OR MB_DEFBUTTON2
    cmp eax, IDYES
    jne Done
    ; move the later semesters up one place
    mov ecx, userData.semCount
    sub ecx, index
    dec ecx
    imul ecx, ecx, SIZEOF SEMESTER
    mov edi, ebx
    lea esi, [ebx + SIZEOF SEMESTER]
    cld
    rep movsb
    dec userData.semCount
    mov eax, userData.semCount
    imul eax, eax, SIZEOF SEMESTER
    lea edi, userData.semesters[eax]
    mov (SEMESTER PTR [edi]).semGpa, 0
    mov (SEMESTER PTR [edi]).semCredits, 0
    INVOKE LogEvent, ADDR szLogSemDel
    INVOKE SaveWithStatus
    INVOKE InvalidateRect, hGradesPanel, NULL, FALSE
Done:
    ret
RemoveSemester ENDP

;---------------------------------------------------------------------
; FinishSemester - turns this semester into a past semester:
;   1. semester GPA from the sliders -> new past-semester entry
;   2. deadlines that belong to a course are removed (the list is
;      packed: kept items move up over removed ones)
;   3. the courses are cleared; the study log keeps its minutes
;      (for streaks) but no longer points at a course
;---------------------------------------------------------------------
FinishSemester PROC USES ebx ecx esi edi
    LOCAL gpa:DWORD, credits:DWORD, kept:DWORD

    cmp userData.courseCount, 0
    jne @F
    INVOKE MessageBoxA, hMainWnd, ADDR szFinNoCourses, ADDR szFinTitle, MB_OK OR MB_ICONINFORMATION
    ret
@@: cmp userData.semCount, MAX_SEMESTERS
    jb  @F
    INVOKE MessageBoxA, hMainWnd, ADDR szFinFull, ADDR szFinTitle, MB_OK OR MB_ICONINFORMATION
    ret
@@:
    ; semester GPA = points / credits, rounded
    INVOKE CalcSemester
    mov credits, ecx
    call SemesterGpaRounded
    mov gpa, eax
    INVOKE FormatFixed2, gpa, ADDR finBuf
    mov eax, userData.semCount
    inc eax
    INVOKE wsprintf, ADDR finMsg, ADDR szFinFmt, ADDR finBuf, credits, eax, userData.courseCount
    INVOKE MessageBoxA, hMainWnd, ADDR finMsg, ADDR szFinTitle,
           MB_YESNO OR MB_ICONQUESTION OR MB_DEFBUTTON2
    cmp eax, IDYES
    je  @F
    ret
@@:
    ; 1. add the past semester
    mov eax, userData.semCount
    imul eax, eax, SIZEOF SEMESTER
    lea esi, userData.semesters[eax]
    mov eax, gpa
    mov (SEMESTER PTR [esi]).semGpa, eax
    mov eax, credits
    mov (SEMESTER PTR [esi]).semCredits, eax
    inc userData.semCount

    ; 2. keep only deadlines without a course ("General")
    mov kept, 0
    mov esi, OFFSET userData.deadlines   ; reading position
    mov edi, OFFSET userData.deadlines   ; writing position
    xor ebx, ebx
PackLoop:
    cmp ebx, userData.deadlineCount
    jae PackDone
    cmp (DEADLINE PTR [esi]).course, -1
    jne SkipIt
    cmp esi, edi
    je  @F
    push esi
    mov ecx, SIZEOF DEADLINE
    cld
    rep movsb                       ; move it up
    pop esi
    sub edi, SIZEOF DEADLINE
@@: add edi, SIZEOF DEADLINE
    inc kept
SkipIt:
    add esi, SIZEOF DEADLINE
    inc ebx
    jmp PackLoop
PackDone:
    ; clear the slots after the kept ones
    mov eax, MAX_DEADLINES
    sub eax, kept
    imul ecx, eax, SIZEOF DEADLINE
    xor eax, eax
    rep stosb
    mov eax, kept
    mov userData.deadlineCount, eax

    ; 3. clear the courses, unlink the study log
    mov edi, OFFSET userData.courses
    mov ecx, SIZEOF userData.courses
    xor eax, eax
    rep stosb
    mov userData.courseCount, 0
    mov esi, OFFSET userData.studyLog
    mov ecx, userData.logCount
    jecxz @F
UnlinkLoop:
    mov (STUDYLOG PTR [esi]).logCourse, -1
    add esi, SIZEOF STUDYLOG
    loop UnlinkLoop
@@:
    mov solverMsg, 0
    INVOKE LogEventFmt, ADDR szLogFinish, ADDR finBuf
    INVOKE SaveWithStatus
    INVOKE CoursesChanged
    INVOKE DeadlinesChanged
    INVOKE InvalidateRect, hGradesPanel, NULL, FALSE
    ; "Semester 4 saved with GPA 3.42. Your CGPA is now 3.10."
    INVOKE CurrentCgpa
    INVOKE FormatFixed2, eax, ADDR finBuf2
    INVOKE wsprintf, ADDR finMsg, ADDR szFinDoneFmt, userData.semCount, ADDR finBuf, ADDR finBuf2
    INVOKE MessageBoxA, hMainWnd, ADDR finMsg, ADDR szFinTitle, MB_OK OR MB_ICONINFORMATION
    ret
FinishSemester ENDP

;---------------------------------------------------------------------
; RunAutoSolve - solve, then animate the sliders to the answer
;---------------------------------------------------------------------
RunAutoSolve PROC
    INVOKE KillTimer, hGradesPanel, TIMER_SOLVE
    INVOKE SolveGrades
    cmp eax, 0
    je  Failed
    INVOKE FormatFixed2, solveGpa, ADDR grBuf2
    INVOKE wsprintf, ADDR solverMsg, ADDR szFmtSolved, ADDR grBuf2
    INVOKE SetTimer, hGradesPanel, TIMER_SOLVE, 70, NULL
    jmp Redraw
Failed:
    INVOKE RequiredGpa
    mov ecx, OFFSET szSolveNoTarget
    cmp edx, 1
    je  @F
    mov ecx, OFFSET szSolveNoCourse
    cmp edx, 2
    je  @F
    mov ecx, OFFSET szSolveTooHigh
    cmp eax, 400
    ja  @F
    mov ecx, OFFSET szSolveBlocked
@@: INVOKE Str_copy, ecx, ADDR solverMsg
    INVOKE MessageBeep, MB_OK
Redraw:
    INVOKE InvalidateRect, hGradesPanel, NULL, FALSE
    ret
RunAutoSolve ENDP

;---------------------------------------------------------------------
; AnimateStep (helper) - one timer tick: every slider moves one grade
; towards the solver's answer. Returns: EAX = 1 if anything moved
;---------------------------------------------------------------------
AnimateStep PROC USES ebx ecx esi
    xor eax, eax                    ; moved flag
    mov esi, OFFSET userData.courses
    xor ecx, ecx
StepLoop:
    cmp ecx, userData.courseCount
    jae Done
    mov ebx, solveGrade[ecx*4]
    cmp (COURSE PTR [esi]).sliderGrade, ebx
    je  Next
    ja  MoveUp
    inc (COURSE PTR [esi]).sliderGrade
    mov eax, 1
    jmp Next
MoveUp:
    dec (COURSE PTR [esi]).sliderGrade  ; smaller index = better grade
    mov eax, 1
Next:
    add esi, SIZEOF COURSE
    inc ecx
    jmp StepLoop
Done:
    ret
AnimateStep ENDP

;---------------------------------------------------------------------
; ResetSliders - every slider back to the course's target grade
;---------------------------------------------------------------------
ResetSliders PROC USES ecx esi
    INVOKE KillTimer, hGradesPanel, TIMER_SOLVE
    mov esi, OFFSET userData.courses
    mov ecx, userData.courseCount
    jecxz Done
ResetLoop:
    mov eax, (COURSE PTR [esi]).targetGrade
    mov (COURSE PTR [esi]).sliderGrade, eax
    add esi, SIZEOF COURSE
    loop ResetLoop
Done:
    mov solverMsg, 0
    INVOKE SaveWithStatus
    INVOKE InvalidateRect, hGradesPanel, NULL, FALSE
    ret
ResetSliders ENDP

;---------------------------------------------------------------------
; GradesPanelMsg - messages for the Grades screen
; Returns: EAX = result, ECX = 1 if handled
;---------------------------------------------------------------------
GradesPanelMsg PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL mx:DWORD, my:DWORD

    ; mouse position for mouse messages
    mov eax, lParam
    movsx ecx, ax
    mov mx, ecx
    sar eax, 16
    mov my, eax

    cmp uMsg, WM_SIZE
    je  OnSize
    cmp uMsg, WM_CTLCOLOREDIT
    je  OnFieldColor
    cmp uMsg, WM_DRAWITEM
    je  OnDrawItem
    cmp uMsg, WM_COMMAND
    je  OnCommand
    cmp uMsg, WM_LBUTTONDOWN
    je  OnDown
    cmp uMsg, WM_MOUSEMOVE
    je  OnMove
    cmp uMsg, WM_LBUTTONUP
    je  OnUp
    cmp uMsg, WM_TIMER
    je  OnTimer
    cmp uMsg, WM_SETCURSOR
    je  OnSetCursor
    jmp NotHandled

OnSize:
    INVOKE GrLayout
    jmp HandledZero

OnFieldColor:
    INVOKE GdiSetTextColor, wParam, curTheme.clrText
    INVOKE SetBkColor, wParam, curTheme.clrCard
    mov eax, hCardBrush             ; follows the current theme
    jmp Handled

OnDrawItem:
    INVOKE DrawPastelButton, lParam, curTheme.clrCard
    mov eax, TRUE
    jmp Handled

OnCommand:
    mov eax, wParam
    mov ebx, eax
    and eax, 0FFFFh                 ; control ID
    shr ebx, 16                     ; notification
    cmp eax, IDC_GR_SOLVE
    jne @F
    INVOKE RunAutoSolve
    jmp HandledZero
@@: cmp eax, IDC_GR_RESET
    jne @F
    INVOKE ResetSliders
    jmp HandledZero
@@: cmp eax, IDC_GR_FINISH
    jne @F
    INVOKE FinishSemester
    jmp HandledZero
@@: cmp eax, IDC_GR_ADDSEM
    jne @F
    INVOKE AddSemester
    jmp HandledZero
@@: ; text boxes: focus border, and the target updates live
    cmp ebx, EN_SETFOCUS
    jne @F
    mov grFocus, eax
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero
@@: cmp ebx, EN_KILLFOCUS
    jne @F
    mov grFocus, 0
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    cmp eax, IDC_GR_TARGET
    jne HandledZero
    cmp targetDirty, 0
    je  HandledZero
    mov targetDirty, 0
    INVOKE SaveWithStatus
    jmp HandledZero
@@: cmp ebx, EN_CHANGE
    jne HandledZero
    cmp eax, IDC_GR_TARGET
    jne HandledZero
    INVOKE GetWindowTextA, hGrTarget, ADDR grBuf2, SIZEOF grBuf2
    INVOKE ParseFixed2, ADDR grBuf2
    cmp edx, 0
    je  HandledZero                 ; half-typed: keep the old target
    cmp eax, 400
    ja  HandledZero
    cmp eax, userData.targetCgpa
    je  HandledZero
    mov userData.targetCgpa, eax    ; empty box -> 0 = no target
    mov targetDirty, 1
    mov solverMsg, 0
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero

OnDown:
    INVOKE SemesterHit, mx, my
    cmp eax, -1
    je  @F
    INVOKE RemoveSemester, eax
    jmp HandledZero
@@: INVOKE SliderHit, mx, my
    cmp eax, -1
    je  HandledZero
    mov dragRow, eax
    INVOKE KillTimer, hWnd, TIMER_SOLVE
    INVOKE SetCapture, hWnd         ; keep getting the mouse while dragging
    INVOKE SetSlider, dragRow, mx
    jmp HandledZero

OnMove:
    cmp dragRow, -1
    je  CheckHot
    INVOKE SetSlider, dragRow, mx
    jmp HandledZero
CheckHot:
    mov hotSpot, 0
    INVOKE SliderHit, mx, my
    cmp eax, -1
    jne IsHot
    INVOKE SemesterHit, mx, my
    cmp eax, -1
    je  HandledZero
IsHot:
    mov hotSpot, 1
    jmp HandledZero

OnUp:
    cmp dragRow, -1
    je  HandledZero
    mov dragRow, -1
    INVOKE ReleaseCapture
    INVOKE SaveWithStatus
    jmp HandledZero

OnTimer:
    INVOKE AnimateStep
    cmp eax, 0
    jne @F
    INVOKE KillTimer, hWnd, TIMER_SOLVE    ; every slider has arrived
    INVOKE SaveWithStatus
@@: INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero

OnSetCursor:
    cmp hotSpot, 0
    jne @F
    cmp dragRow, -1
    je  NotHandled
@@: INVOKE LoadCursorA, NULL, IDC_HAND
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
GradesPanelMsg ENDP

END
