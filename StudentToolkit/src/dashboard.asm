;=====================================================================
; dashboard.asm  -  the home screen: everything at a glance
;
;  [ CGPA ] [ Needed this semester ] [ Next exam ] [ Streak ]
;  +---------------------------+ +---------------------------+
;  |  GPA trend (bar chart)    | |  Today's plan (split bar) |
;  +---------------------------+ +---------------------------+
;  [ Upcoming: chips ......................  (Start session) ]
;
; Every number comes from the other screens: Grades (CGPA, needed
; GPA, semesters), Deadlines (next exam, upcoming), Courses
; (attendance alerts), Planner (today's blocks) and Timer (streak).
;
; Charts are drawn with rectangles and lines. Bar height is scaled
; with integer maths:  height = GPA x plotHeight / 400.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

DsGeometry      PROTO :DWORD, :DWORD
DsText          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DsCard          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
PaintSummaryCards PROTO :DWORD
PaintGpaChart   PROTO :DWORD
PaintTodayChart PROTO :DWORD
PaintUpcoming   PROTO :DWORD
DsChip          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
NextExam        PROTO
FormatMinutesDs PROTO :DWORD, :DWORD

IDC_DS_START    = 1601
CLR_LILAC_BG    = RGBC(0E5h, 0D4h, 0F0h)
CLR_LILAC_TX    = RGBC(05Eh, 03Fh, 078h)

.data
hDashPanel  DWORD 0
hDsStart    DWORD 0

; geometry (real pixels)
dM          DWORD 0
dGap        DWORD 0
dCardW      DWORD 0
dCardsTop   DWORD 0
dCardsBot   DWORD 0
dChartsTop  DWORD 0
dChartsBot  DWORD 0
dMid        DWORD 0
dRightEdge  DWORD 0
dUpTop      DWORD 0
dUpBot      DWORD 0
chipX       DWORD 0             ; next free x on the Upcoming row
chipMaxX    DWORD 0

szDsCgpa        BYTE "Current CGPA", 0
szDsNeeded      BYTE "Needed this semester", 0
szDsExam        BYTE "Next exam", 0
szDsStreak      BYTE "Study streak", 0
szDsDash        BYTE "-", 0
szFmtTarget     BYTE "Target %s", 0
szNoTargetDs    BYTE "No target set yet", 0
szSetTargetDs   BYTE "Set a target on Grades", 0
szAddCoursesDs  BYTE "Add this semester's courses", 0
szAbove4Ds      BYTE "> 4.00", 0
szNoExams       BYTE "No exams added", 0
szFmtExamIn     BYTE "in %d days  |  %s", 0
szFmtExamTmrw   BYTE "tomorrow  |  %s", 0
szFmtExamToday  BYTE "today  |  %s", 0
szFmtDays       BYTE "%d days", 0
szOneDay        BYTE "1 day", 0
szFmtStreakSub  BYTE "Best %d  |  today %s", 0

szGpaTrend      BYTE "GPA trend", 0
szNoTrend       BYTE "Add past semesters on the Grades screen to see your trend.", 0
szFmtSem        BYTE "S%d", 0
szNext          BYTE "Next", 0
szFmtNeedBar    BYTE "need %s", 0
szFmtTargetLine BYTE "- - -  target %s", 0
szFmtGrid       BYTE "%d.0", 0

szTodayPlan     BYTE "Today's plan", 0
szFmtDoneOf     BYTE "%d of %d sessions done", 0
szNoPlan        BYTE "Nothing planned today. Add courses, or check your exam dates.", 0
szFmtBlocks     BYTE "%d x 25 min", 0
szFmtDoneN      BYTE "%d done", 0

szUpcoming      BYTE "Upcoming", 0
szNothingDue    BYTE "Nothing due soon. Enjoy the calm.", 0
szFmtChipDays   BYTE "%s  -  in %d days", 0
szFmtChipTmrw   BYTE "%s  -  tomorrow", 0
szFmtChipToday  BYTE "%s  -  today", 0
szFmtChipLate   BYTE "%s  -  overdue", 0
szFmtChipAtt    BYTE "%s: attend next %d", 0
szStartSession  BYTE "Start session", 0

szDsHM      BYTE "%dh %02dm", 0
szDsM       BYTE "%dm", 0
dsBuf       BYTE 128 DUP(0)
dsBuf2      BYTE 48 DUP(0)

.code
;---------------------------------------------------------------------
; DashboardInit - the "Start session" button
;---------------------------------------------------------------------
DashboardInit PROC hPanel:DWORD
    mov eax, hPanel
    mov hDashPanel, eax
    INVOKE CreatePastelButton, hPanel, ADDR szStartSession, IDC_DS_START, BTN_PRIMARY
    mov hDsStart, eax
    ret
DashboardInit ENDP

;---------------------------------------------------------------------
; DsGeometry - card and chart positions for the panel size
;---------------------------------------------------------------------
DsGeometry PROC USES ecx edx, clientW:DWORD, clientH:DWORD
    INVOKE ScaleDpi, PAGE_MARGIN
    mov dM, eax
    mov ecx, clientW
    sub ecx, eax
    mov dRightEdge, ecx
    INVOKE ScaleDpi, 16
    mov dGap, eax
    ; 4 cards: (width - 2 margins - 3 gaps) / 4
    mov eax, dRightEdge
    sub eax, dM
    mov ecx, dGap
    imul ecx, ecx, 3
    sub eax, ecx
    shr eax, 2
    mov dCardW, eax
    INVOKE ScaleDpi, 104
    mov dCardsTop, eax
    INVOKE ScaleDpi, 206
    mov dCardsBot, eax
    INVOKE ScaleDpi, 222
    mov dChartsTop, eax
    ; Upcoming row at the bottom
    INVOKE ScaleDpi, 20
    mov ecx, clientH
    sub ecx, eax
    mov dUpBot, ecx
    INVOKE ScaleDpi, 70
    mov ecx, dUpBot
    sub ecx, eax
    mov dUpTop, ecx
    sub ecx, dGap
    mov dChartsBot, ecx
    ; middle between the two charts
    mov eax, dM
    add eax, dRightEdge
    shr eax, 1
    mov dMid, eax
    ret
DsGeometry ENDP

;---------------------------------------------------------------------
; DsText - text in a rectangle
;---------------------------------------------------------------------
DsText PROC hdc:DWORD, pText:DWORD, x1:DWORD, y1:DWORD, x2:DWORD, y2:DWORD,
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
DsText ENDP

;---------------------------------------------------------------------
; DsCard - one summary card: label, big value, small line
;---------------------------------------------------------------------
DsCard PROC USES ebx esi edi, hdc:DWORD, x1:DWORD, x2:DWORD, fillColor:DWORD,
            labelColor:DWORD, pLabel:DWORD, pValue:DWORD, valueColor:DWORD,
            pSub:DWORD, subColor:DWORD
    LOCAL y1:DWORD, y2:DWORD
    mov eax, curTheme.clrBorder
    mov ecx, fillColor
    cmp ecx, curTheme.clrCard
    je  @F
    mov eax, ecx
@@: INVOKE FillRound, hdc, x1, dCardsTop, x2, dCardsBot, CARD_RADIUS, fillColor, eax
    INVOKE ScaleDpi, 18
    mov ebx, x1
    add ebx, eax
    mov esi, x2
    sub esi, eax
    INVOKE ScaleDpi, 12
    add eax, dCardsTop
    mov y1, eax
    INVOKE ScaleDpi, 22
    add eax, y1
    mov y2, eax
    INVOKE DsText, hdc, pLabel, ebx, y1, esi, y2, hFontSmall, labelColor, DT_LEFT
    mov eax, y2
    mov y1, eax
    INVOKE ScaleDpi, 42
    add eax, y1
    mov y2, eax
    INVOKE DsText, hdc, pValue, ebx, y1, esi, y2, hFontTitle, valueColor, DT_LEFT
    mov eax, y2
    mov y1, eax
    INVOKE ScaleDpi, 22
    add eax, y1
    mov y2, eax
    INVOKE DsText, hdc, pSub, ebx, y1, esi, y2, hFontSmall, subColor, DT_LEFT
    ret
DsCard ENDP

;---------------------------------------------------------------------
; NextExam - earliest unfinished exam from today on
; Returns: EAX = address of the DEADLINE, or 0
;---------------------------------------------------------------------
NextExam PROC USES ebx ecx esi
    INVOKE TodayDay
    mov ebx, eax
    mov esi, OFFSET userData.deadlines
    mov ecx, userData.deadlineCount
    jecxz None
FindLoop:
    cmp (DEADLINE PTR [esi]).kind, DL_EXAM
    jne Next
    cmp (DEADLINE PTR [esi]).isDone, 0
    jne Next
    cmp (DEADLINE PTR [esi]).dueDay, NO_DATE
    je  Next                        ; an exam without a date can't be "next"
    cmp (DEADLINE PTR [esi]).dueDay, ebx
    jl  Next
    mov eax, esi                    ; list is sorted: first match is soonest
    ret
Next:
    add esi, SIZEOF DEADLINE
    loop FindLoop
None:
    xor eax, eax
    ret
NextExam ENDP

;---------------------------------------------------------------------
; PaintSummaryCards - the four cards at the top
;---------------------------------------------------------------------
PaintSummaryCards PROC USES ebx esi edi, hdc:DWORD
    LOCAL x1:DWORD, x2:DWORD, value:DWORD, status:DWORD, valueBuf[16]:BYTE,
          subBuf[64]:BYTE, zoneBg:DWORD, zoneTx:DWORD, pSub:DWORD, pVal:DWORD

    ;---------- 1. current CGPA ----------
    mov eax, dM
    mov x1, eax
    add eax, dCardW
    mov x2, eax
    INVOKE CurrentCgpa
    lea edi, valueBuf
    cmp eax, -1
    jne @F
    INVOKE Str_copy, ADDR szDsDash, edi
    jmp CgpaSub
@@: INVOKE FormatFixed2, eax, edi
CgpaSub:
    lea esi, subBuf
    cmp userData.targetCgpa, 0
    jne @F
    INVOKE Str_copy, ADDR szNoTargetDs, esi
    jmp CgpaDraw
@@: INVOKE FormatFixed2, userData.targetCgpa, ADDR dsBuf2
    INVOKE wsprintf, esi, ADDR szFmtTarget, ADDR dsBuf2
CgpaDraw:
    lea edi, valueBuf
    lea esi, subBuf
    INVOKE DsCard, hdc, x1, x2, curTheme.clrCard, curTheme.clrMuted, ADDR szDsCgpa,
           edi, curTheme.clrText, esi, curTheme.clrMuted

    ;---------- 2. needed this semester ----------
    mov eax, x2
    add eax, dGap
    mov x1, eax
    add eax, dCardW
    mov x2, eax
    INVOKE RequiredGpa
    mov value, eax
    mov status, edx
    mov eax, curTheme.clrCard
    mov zoneBg, eax
    mov eax, curTheme.clrMuted
    mov zoneTx, eax
    mov pVal, OFFSET szDsDash
    mov pSub, OFFSET szSetTargetDs
    cmp status, 1
    je  NeededDraw
    mov pSub, OFFSET szAddCoursesDs
    cmp status, 2
    je  NeededDraw
    INVOKE GpaZone, value
    mov zoneBg, eax
    mov zoneTx, ecx
    mov pSub, edx
    lea edi, valueBuf
    mov pVal, edi
    cmp value, 400
    jbe @F
    INVOKE Str_copy, ADDR szAbove4Ds, edi
    jmp NeededDraw
@@: INVOKE FormatFixed2, value, edi
NeededDraw:
    INVOKE DsCard, hdc, x1, x2, zoneBg, zoneTx, ADDR szDsNeeded,
           pVal, zoneTx, pSub, zoneTx

    ;---------- 3. next exam ----------
    mov eax, x2
    add eax, dGap
    mov x1, eax
    add eax, dCardW
    mov x2, eax
    INVOKE NextExam
    cmp eax, 0
    jne HasExam
    INVOKE DsCard, hdc, x1, x2, CLR_LILAC_BG, CLR_LILAC_TX, ADDR szDsExam,
           ADDR szDsDash, CLR_LILAC_TX, ADDR szNoExams, CLR_LILAC_TX
    jmp StreakCard
HasExam:
    mov esi, eax
    ; value: the course name, or the exam title if it has no course
    lea edi, (DEADLINE PTR [esi]).dtitle
    mov eax, (DEADLINE PTR [esi]).course
    cmp eax, -1
    je  @F
    cmp eax, userData.courseCount
    jae @F
    imul eax, eax, SIZEOF COURSE
    lea edi, userData.courses[eax]
@@: mov pVal, edi
    ; "in 3 days  |  Thu 12 Nov"
    INVOKE FormatDateShort, (DEADLINE PTR [esi]).dueDay, ADDR dsBuf2
    INVOKE TodayDay
    mov ecx, (DEADLINE PTR [esi]).dueDay
    sub ecx, eax
    lea ebx, subBuf
    cmp ecx, 0
    jne @F
    INVOKE wsprintf, ebx, ADDR szFmtExamToday, ADDR dsBuf2
    jmp ExamDraw
@@: cmp ecx, 1
    jne @F
    INVOKE wsprintf, ebx, ADDR szFmtExamTmrw, ADDR dsBuf2
    jmp ExamDraw
@@: INVOKE wsprintf, ebx, ADDR szFmtExamIn, ecx, ADDR dsBuf2
ExamDraw:
    lea ebx, subBuf
    INVOKE DsCard, hdc, x1, x2, CLR_LILAC_BG, CLR_LILAC_TX, ADDR szDsExam,
           pVal, CLR_LILAC_TX, ebx, CLR_LILAC_TX

StreakCard:
    ;---------- 4. streak ----------
    mov eax, x2
    add eax, dGap
    mov x1, eax
    add eax, dCardW
    mov x2, eax
    INVOKE CurrentStreak
    lea edi, valueBuf
    cmp eax, 1
    jne @F
    INVOKE Str_copy, ADDR szOneDay, edi
    jmp StreakSub
@@: INVOKE wsprintf, edi, ADDR szFmtDays, eax
StreakSub:
    INVOKE MinutesToday, -1
    INVOKE FormatMinutesDs, eax, ADDR dsBuf2
    lea esi, subBuf
    INVOKE wsprintf, esi, ADDR szFmtStreakSub, userData.streakBest, ADDR dsBuf2
    lea edi, valueBuf
    lea esi, subBuf
    INVOKE DsCard, hdc, x1, x2, CLR_SAFE_BG, CLR_SAFE_TX, ADDR szDsStreak,
           edi, CLR_SAFE_TX, esi, CLR_SAFE_TX
    ret
PaintSummaryCards ENDP

;---------------------------------------------------------------------
; FormatMinutesDs - 75 -> "1h 15m", 0 -> "0m"
;---------------------------------------------------------------------
FormatMinutesDs PROC USES ecx edx, minutes:DWORD, pBuf:DWORD
    mov eax, minutes
    xor edx, edx
    mov ecx, 60
    div ecx
    cmp eax, 0
    jne @F
    INVOKE wsprintf, pBuf, ADDR szDsM, edx
    ret
@@: INVOKE wsprintf, pBuf, ADDR szDsHM, eax, edx
    ret
FormatMinutesDs ENDP

;---------------------------------------------------------------------
; PaintGpaChart - one bar per past semester, a dashed "Next" bar for
; the GPA needed this semester, and a dashed target line
;---------------------------------------------------------------------
PaintGpaChart PROC USES ebx esi edi, hdc:DWORD
    LOCAL x1:DWORD, x2:DWORD, plotX1:DWORD, plotX2:DWORD, plotTop:DWORD,
          plotBot:DWORD, plotH:DWORD, n:DWORD, slot:DWORD, barW:DWORD,
          i:DWORD, barX:DWORD, barTop:DWORD, need:DWORD, hasNext:DWORD,
          gpa:DWORD, y:DWORD, barColor:DWORD

    mov eax, dM
    mov x1, eax
    mov eax, dMid
    sub eax, 8
    mov x2, eax
    INVOKE FillRound, hdc, x1, dChartsTop, x2, dChartsBot, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder
    ; title
    INVOKE ScaleDpi, 20
    mov ebx, x1
    add ebx, eax
    INVOKE ScaleDpi, 14
    add eax, dChartsTop
    mov ecx, eax
    INVOKE ScaleDpi, 24
    add eax, ecx
    INVOKE DsText, hdc, ADDR szGpaTrend, ebx, ecx, x2, eax, hFontSmall, curTheme.clrMuted, DT_LEFT

    ; plot area
    INVOKE ScaleDpi, 54
    add eax, x1
    mov plotX1, eax
    INVOKE ScaleDpi, 20
    mov ecx, x2
    sub ecx, eax
    mov plotX2, ecx
    INVOKE ScaleDpi, 58
    add eax, dChartsTop
    mov plotTop, eax
    INVOKE ScaleDpi, 34
    mov ecx, dChartsBot
    sub ecx, eax
    mov plotBot, ecx
    sub ecx, plotTop
    mov plotH, ecx

    ; how many bars: past semesters + "Next" (if a GPA is needed)
    mov hasNext, 0
    INVOKE RequiredGpa
    mov need, eax
    cmp edx, 0
    jne @F
    cmp eax, 0
    je  @F
    cmp eax, 400
    ja  @F
    mov hasNext, 1
@@: mov eax, userData.semCount
    add eax, hasNext
    mov n, eax
    cmp eax, 0
    jne HasBars
    INVOKE ScaleDpi, 20
    mov edx, x1
    add edx, eax
    mov ebx, x2
    sub ebx, eax
    mov eax, plotTop
    add eax, plotBot
    shr eax, 1
    mov ecx, eax
    sub ecx, 14
    add eax, 14
    INVOKE DsText, hdc, ADDR szNoTrend, edx, ecx, ebx, eax, hFontSmall, curTheme.clrMuted, DT_CENTER
    ret

HasBars:
    ; ---- grid lines at 1.0, 2.0, 3.0, 4.0 ----
    mov i, 1
GridLoop:
    mov eax, i
    imul eax, plotH
    shr eax, 2                      ; plotH x i / 4
    mov ecx, plotBot
    sub ecx, eax
    mov y, ecx
    lea edx, [ecx + 1]
    INVOKE FillRound, hdc, plotX1, y, plotX2, edx, 0, curTheme.clrBg, curTheme.clrBg
    INVOKE wsprintf, ADDR dsBuf2, ADDR szFmtGrid, i
    mov eax, y
    sub eax, 10
    mov ecx, y
    add ecx, 10
    mov edx, plotX1
    sub edx, 8
    INVOKE DsText, hdc, ADDR dsBuf2, x1, eax, edx, ecx, hFontSmall, curTheme.clrMuted, DT_RIGHT
    inc i
    cmp i, 4
    jbe GridLoop
    ; base line
    mov eax, plotBot
    inc eax
    INVOKE FillRound, hdc, plotX1, plotBot, plotX2, eax, 0, curTheme.clrBorder, curTheme.clrBorder

    ; ---- dashed target line (behind the bars), label in the title row ----
    cmp userData.targetCgpa, 0
    je  NoTarget
    mov eax, userData.targetCgpa
    cmp eax, 400
    ja  NoTarget
    mul plotH
    mov ecx, 400
    div ecx
    mov ecx, plotBot
    sub ecx, eax
    mov y, ecx
    INVOKE DashedLine, hdc, plotX1, y, plotX2, y, curTheme.clrSideActText
    INVOKE FormatFixed2, userData.targetCgpa, ADDR dsBuf2
    INVOKE wsprintf, ADDR dsBuf, ADDR szFmtTargetLine, ADDR dsBuf2
    INVOKE ScaleDpi, 14
    add eax, dChartsTop
    mov ecx, eax
    INVOKE ScaleDpi, 24
    add eax, ecx
    INVOKE DsText, hdc, ADDR dsBuf, plotX1, ecx, plotX2, eax, hFontSmall, curTheme.clrSideActText, DT_RIGHT
NoTarget:

    ; ---- bars ----
    mov eax, plotX2
    sub eax, plotX1
    xor edx, edx
    div n
    mov slot, eax
    imul eax, eax, 55
    xor edx, edx
    mov ecx, 100
    div ecx
    mov barW, eax
    INVOKE ScaleDpi, 64
    cmp barW, eax
    jbe @F
    mov barW, eax                   ; not too wide when there are few
@@:
    mov i, 0
BarLoop:
    mov eax, i
    cmp eax, n
    jae BarsDone
    ; x of this bar
    mul slot
    add eax, plotX1
    mov ecx, slot
    sub ecx, barW
    shr ecx, 1
    add eax, ecx
    mov barX, eax
    ; GPA of this bar: a past semester, or the needed GPA ("Next")
    mov eax, i
    cmp eax, userData.semCount
    jae IsNext
    imul eax, eax, SIZEOF SEMESTER
    lea eax, userData.semesters[eax]
    mov eax, (SEMESTER PTR [eax]).semGpa
    mov gpa, eax
    jmp HaveGpa
IsNext:
    mov eax, need
    mov gpa, eax
HaveGpa:
    ; height = gpa x plotH / 400
    mov eax, gpa
    mul plotH
    mov ecx, 400
    div ecx
    mov ecx, plotBot
    sub ecx, eax
    mov barTop, ecx
    mov ebx, barX
    add ebx, barW                   ; bar right
    mov eax, i
    cmp eax, userData.semCount
    jae DrawNext
    ; colour by GPA: 3.00+ green, 2.00+ yellow, lower red
    mov barColor, CLR_SAFE_BG
    cmp gpa, 300
    jae @F
    mov barColor, CLR_WARN_BG
    cmp gpa, 200
    jae @F
    mov barColor, CLR_DANGER_BG
@@: INVOKE FillRound, hdc, barX, barTop, ebx, plotBot, 6, barColor, barColor
    INVOKE FormatFixed2, gpa, ADDR dsBuf2
    mov eax, i
    inc eax
    INVOKE wsprintf, ADDR dsBuf, ADDR szFmtSem, eax
    jmp BarLabels
DrawNext:
    INVOKE FillRound, hdc, barX, barTop, ebx, plotBot, 6, CLR_LILAC_BG, CLR_LILAC_BG
    INVOKE OutlineRound, hdc, barX, barTop, ebx, plotBot, 6, curTheme.clrSideActText
    INVOKE FormatFixed2, gpa, ADDR dsBuf
    INVOKE wsprintf, ADDR dsBuf2, ADDR szFmtNeedBar, ADDR dsBuf
    INVOKE Str_copy, ADDR szNext, ADDR dsBuf
BarLabels:
    ; value above the bar, name below
    INVOKE ScaleDpi, 12
    mov esi, barX
    sub esi, eax
    mov edi, ebx
    add edi, eax
    mov eax, barTop
    sub eax, 22
    mov ecx, barTop
    sub ecx, 2
    INVOKE DsText, hdc, ADDR dsBuf2, esi, eax, edi, ecx, hFontSmall, curTheme.clrText, DT_CENTER
    mov eax, plotBot
    add eax, 4
    mov ecx, plotBot
    add ecx, 28
    INVOKE DsText, hdc, ADDR dsBuf, esi, eax, edi, ecx, hFontSmall, curTheme.clrMuted, DT_CENTER
    inc i
    jmp BarLoop
BarsDone:
    ret
PaintGpaChart ENDP

;---------------------------------------------------------------------
; PaintTodayChart - today's blocks as one split bar + a legend
;---------------------------------------------------------------------
PaintTodayChart PROC USES ebx esi edi, hdc:DWORD
    LOCAL x1:DWORD, x2:DWORD, total:DWORD, doneSum:DWORD, barX1:DWORD,
          barW:DWORD, barY1:DWORD, barY2:DWORD, x:DWORD, ci:DWORD,
          blocks:DWORD, segW:DWORD, done:DWORD, rowY:DWORD, rowH:DWORD,
          sq:DWORD, darker:DWORD

    mov eax, dMid
    add eax, 8
    mov x1, eax
    mov eax, dRightEdge
    mov x2, eax
    INVOKE FillRound, hdc, x1, dChartsTop, x2, dChartsBot, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder
    INVOKE BuildPlan

    ; totals for today (day 0)
    mov total, 0
    mov doneSum, 0
    xor ecx, ecx
SumLoop:
    cmp ecx, userData.courseCount
    jae SumDone
    movzx eax, planGrid[ecx]
    add total, eax
    mov edx, doneToday[ecx*4]
    cmp edx, eax
    jbe @F
    mov edx, eax                    ; never more "done" than planned
@@: add doneSum, edx
    inc ecx
    jmp SumLoop
SumDone:

    ; title + "2 of 9 sessions done"
    INVOKE ScaleDpi, 20
    mov ebx, x1
    add ebx, eax
    mov esi, x2
    sub esi, eax
    INVOKE ScaleDpi, 14
    add eax, dChartsTop
    mov ecx, eax
    INVOKE ScaleDpi, 24
    add eax, ecx
    mov edi, eax
    push ecx
    INVOKE DsText, hdc, ADDR szTodayPlan, ebx, ecx, esi, edi, hFontSmall, curTheme.clrMuted, DT_LEFT
    pop ecx
    cmp total, 0
    je  NoPlan
    push ecx
    INVOKE wsprintf, ADDR dsBuf, ADDR szFmtDoneOf, doneSum, total
    pop ecx
    INVOKE DsText, hdc, ADDR dsBuf, ebx, ecx, esi, edi, hFontSmall, curTheme.clrSideActText, DT_RIGHT

    ; ---- split bar ----
    mov barX1, ebx
    mov eax, esi
    sub eax, ebx
    mov barW, eax
    INVOKE ScaleDpi, 52
    add eax, dChartsTop
    mov barY1, eax
    INVOKE ScaleDpi, 26
    add eax, barY1
    mov barY2, eax
    mov eax, barX1
    mov x, eax
    mov ci, 0
SegLoop:
    mov ecx, ci
    cmp ecx, userData.courseCount
    jae SegDone
    movzx eax, planGrid[ecx]
    mov blocks, eax
    cmp eax, 0
    je  NextSeg
    ; width = blocks x barW / total  (last segment fills to the end)
    mul barW
    div total
    mov segW, eax
    mov edi, x
    add edi, segW
    INVOKE FillRound, hdc, x, barY1, edi, barY2, 6, subjectBg[ecx*4], subjectBg[ecx*4]
    ; done part a little darker
    mov ecx, ci
    mov eax, doneToday[ecx*4]
    cmp eax, blocks
    jbe @F
    mov eax, blocks
@@: cmp eax, 0
    je  NoDone
    mul segW
    div blocks
    mov edx, x
    add edx, eax
    mov ecx, ci
    push edx
    INVOKE DarkenColor, subjectBg[ecx*4], 34
    mov darker, eax
    pop edx
    INVOKE FillRound, hdc, x, barY1, edx, barY2, 6, darker, darker
NoDone:
    mov eax, segW
    add x, eax
NextSeg:
    inc ci
    jmp SegLoop
SegDone:

    ; ---- legend: one row per course with blocks today ----
    INVOKE ScaleDpi, 98
    add eax, dChartsTop
    mov rowY, eax
    INVOKE ScaleDpi, 30
    mov rowH, eax
    INVOKE ScaleDpi, 12
    mov sq, eax
    mov ci, 0
LegendLoop:
    mov ecx, ci
    cmp ecx, userData.courseCount
    jae Done
    movzx eax, planGrid[ecx]
    cmp eax, 0
    je  NextLegend
    mov blocks, eax
    mov eax, rowY
    add eax, rowH
    cmp eax, dChartsBot
    ja  Done                        ; no more room
    ; colour square
    mov eax, rowY
    add eax, rowY
    add eax, rowH
    sub eax, sq
    shr eax, 1                      ; square top
    mov edx, eax
    add edx, sq
    mov edi, ebx
    add edi, sq
    INVOKE FillRound, hdc, ebx, eax, edi, edx, 3, subjectBg[ecx*4], subjectTx[ecx*4]
    ; name
    INVOKE ScaleDpi, 10
    add edi, eax
    mov ecx, ci
    imul eax, ecx, SIZEOF COURSE
    lea eax, userData.courses[eax]
    mov edx, rowY
    add edx, rowH
    INVOKE DsText, hdc, eax, edi, rowY, esi, edx, hFontBody, curTheme.clrText, DT_LEFT
    ; "4 x 25 min" and "2 done" on the right
    INVOKE wsprintf, ADDR dsBuf, ADDR szFmtBlocks, blocks
    mov ecx, ci
    mov eax, doneToday[ecx*4]
    cmp eax, 0
    je  NoDoneText
    INVOKE wsprintf, ADDR dsBuf2, ADDR szFmtDoneN, eax
    INVOKE ScaleDpi, 90
    mov ecx, esi
    sub ecx, eax
    mov edx, rowY
    add edx, rowH
    INVOKE DsText, hdc, ADDR dsBuf, edi, rowY, ecx, edx, hFontSmall, curTheme.clrMuted, DT_RIGHT
    mov edx, rowY
    add edx, rowH
    INVOKE DsText, hdc, ADDR dsBuf2, edi, rowY, esi, edx, hFontSmall, CLR_SAFE_TX, DT_RIGHT
    jmp RowDone
NoDoneText:
    mov edx, rowY
    add edx, rowH
    INVOKE DsText, hdc, ADDR dsBuf, edi, rowY, esi, edx, hFontSmall, curTheme.clrMuted, DT_RIGHT
RowDone:
    mov eax, rowH
    add rowY, eax
NextLegend:
    inc ci
    jmp LegendLoop

NoPlan:
    mov eax, dChartsTop
    add eax, dChartsBot
    shr eax, 1
    mov ecx, eax
    sub ecx, 14
    add eax, 14
    INVOKE DsText, hdc, ADDR szNoPlan, ebx, ecx, esi, eax, hFontSmall, curTheme.clrMuted, DT_CENTER
Done:
    ret
PaintTodayChart ENDP

;---------------------------------------------------------------------
; DsChip - one chip on the Upcoming row (skipped if it doesn't fit)
; Returns: EAX = 1 drawn, 0 no room
;---------------------------------------------------------------------
DsChip PROC USES ebx esi, hdc:DWORD, pText:DWORD, bgColor:DWORD, txColor:DWORD, yMid:DWORD
    LOCAL w:DWORD, h:DWORD
    INVOKE TextWidth, hdc, pText, hFontSmall
    mov w, eax
    INVOKE ScaleDpi, 28
    add w, eax
    mov eax, chipX
    add eax, w
    cmp eax, chipMaxX
    jbe @F
    xor eax, eax
    ret
@@: INVOKE ScaleDpi, 30
    mov h, eax
    mov ebx, yMid
    shr eax, 1
    sub ebx, eax                    ; chip top
    mov esi, ebx
    add esi, h                      ; chip bottom
    mov ecx, chipX
    add ecx, w
    INVOKE FillRound, hdc, chipX, ebx, ecx, esi, 15, bgColor, bgColor
    mov ecx, chipX
    add ecx, w
    INVOKE DsText, hdc, pText, chipX, ebx, ecx, esi, hFontSmall, txColor, DT_CENTER
    INVOKE ScaleDpi, 8
    add eax, w
    add chipX, eax
    mov eax, 1
    ret
DsChip ENDP

;---------------------------------------------------------------------
; PaintUpcoming - next deadlines and attendance alerts as chips
;---------------------------------------------------------------------
PaintUpcoming PROC USES ebx esi edi, hdc:DWORD
    LOCAL yMid:DWORD, today:DWORD, shown:DWORD, chipBg:DWORD, chipTx:DWORD,
          maxDl:DWORD

    INVOKE FillRound, hdc, dM, dUpTop, dRightEdge, dUpBot, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder
    mov eax, dUpTop
    add eax, dUpBot
    shr eax, 1
    mov yMid, eax
    INVOKE ScaleDpi, 20
    mov ebx, dM
    add ebx, eax
    INVOKE ScaleDpi, 100
    lea esi, [ebx + eax]
    mov eax, yMid
    sub eax, 12
    mov ecx, yMid
    add ecx, 12
    INVOKE DsText, hdc, ADDR szUpcoming, ebx, eax, esi, ecx, hFontSmall, curTheme.clrMuted, DT_LEFT
    mov chipX, esi
    INVOKE ScaleDpi, 20 + 180 + 12
    mov ecx, dRightEdge
    sub ecx, eax
    mov chipMaxX, ecx               ; leave room for "Start session"

    INVOKE TodayDay
    mov today, eax
    mov shown, 0

    ; attendance alerts are important: if there are any, show at most
    ; 2 deadline chips so they still fit
    mov maxDl, 4
    mov esi, OFFSET userData.courses
    xor edi, edi
CountAlerts:
    cmp edi, userData.courseCount
    jae CountDone
    INVOKE AttendanceInfo, esi
    cmp ecx, 3
    jne @F
    mov maxDl, 2
@@: add esi, SIZEOF COURSE
    inc edi
    jmp CountAlerts
CountDone:

    ; ---- unfinished deadlines, soonest first (the list is sorted) ----
    mov esi, OFFSET userData.deadlines
    xor edi, edi
DlLoop:
    cmp edi, userData.deadlineCount
    jae Alerts
    mov eax, shown
    cmp eax, maxDl
    jae Alerts
    cmp (DEADLINE PTR [esi]).isDone, 0
    jne NextDl
    cmp (DEADLINE PTR [esi]).dueDay, NO_DATE
    je  NextDl                      ; nothing "upcoming" without a date
    mov eax, (DEADLINE PTR [esi]).dueDay
    sub eax, today
    mov chipBg, CLR_DANGER_BG
    mov chipTx, CLR_DANGER_TX
    cmp eax, 0
    jl  ChipLate
    je  ChipToday
    cmp eax, 1
    je  ChipTmrw
    INVOKE wsprintf, ADDR dsBuf, ADDR szFmtChipDays, ADDR (DEADLINE PTR [esi]).dtitle, eax
    mov eax, (DEADLINE PTR [esi]).dueDay
    sub eax, today
    mov chipBg, CLR_WARN_BG
    mov chipTx, CLR_WARN_TX
    cmp eax, 3
    jle DrawDl
    mov chipBg, CLR_SAFE_BG
    mov chipTx, CLR_SAFE_TX
    jmp DrawDl
ChipLate:
    INVOKE wsprintf, ADDR dsBuf, ADDR szFmtChipLate, ADDR (DEADLINE PTR [esi]).dtitle
    jmp DrawDl
ChipToday:
    INVOKE wsprintf, ADDR dsBuf, ADDR szFmtChipToday, ADDR (DEADLINE PTR [esi]).dtitle
    jmp DrawDl
ChipTmrw:
    INVOKE wsprintf, ADDR dsBuf, ADDR szFmtChipTmrw, ADDR (DEADLINE PTR [esi]).dtitle
DrawDl:
    INVOKE DsChip, hdc, ADDR dsBuf, chipBg, chipTx, yMid
    cmp eax, 0
    je  Finished                    ; row is full
    inc shown
NextDl:
    add esi, SIZEOF DEADLINE
    inc edi
    jmp DlLoop

Alerts:
    ; ---- courses below the attendance limit ----
    mov esi, OFFSET userData.courses
    xor edi, edi
AttLoop:
    cmp edi, userData.courseCount
    jae Finished
    INVOKE AttendanceInfo, esi
    cmp ecx, 3
    jne NextAtt
    INVOKE wsprintf, ADDR dsBuf, ADDR szFmtChipAtt, esi, edx
    INVOKE DsChip, hdc, ADDR dsBuf, CLR_DANGER_BG, CLR_DANGER_TX, yMid
    cmp eax, 0
    je  Finished
    inc shown
NextAtt:
    add esi, SIZEOF COURSE
    inc edi
    jmp AttLoop

Finished:
    cmp shown, 0
    jne Done
    mov eax, yMid
    sub eax, 12
    mov ecx, yMid
    add ecx, 12
    INVOKE DsText, hdc, ADDR szNothingDue, chipX, eax, chipMaxX, ecx, hFontSmall, curTheme.clrMuted, DT_LEFT
Done:
    ret
PaintUpcoming ENDP

;---------------------------------------------------------------------
; PaintDashboard - everything below the greeting
;---------------------------------------------------------------------
PaintDashboard PROC hdc:DWORD, clientW:DWORD, clientH:DWORD
    INVOKE DsGeometry, clientW, clientH
    INVOKE PaintSummaryCards, hdc
    INVOKE PaintGpaChart, hdc
    INVOKE PaintTodayChart, hdc
    INVOKE PaintUpcoming, hdc
    ret
PaintDashboard ENDP

;---------------------------------------------------------------------
; DashboardPanelMsg - button placement and "Start session"
;---------------------------------------------------------------------
DashboardPanelMsg PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL rc:RECT

    cmp uMsg, WM_SIZE
    je  OnSize
    cmp uMsg, WM_DRAWITEM
    je  OnDrawItem
    cmp uMsg, WM_COMMAND
    je  OnCommand
    xor ecx, ecx
    ret

OnSize:
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE DsGeometry, rc.right, rc.bottom
    INVOKE ScaleDpi, 20 + 180
    mov ebx, dRightEdge
    sub ebx, eax                    ; x
    INVOKE ScaleDpi, 42
    mov edi, eax                    ; height
    mov esi, dUpTop
    add esi, dUpBot
    sub esi, edi
    shr esi, 1                      ; y: centred in the Upcoming card
    INVOKE ScaleDpi, 180
    INVOKE MoveWindow, hDsStart, ebx, esi, eax, edi, TRUE
    jmp HandledZero

OnDrawItem:
    INVOKE DrawPastelButton, lParam, curTheme.clrCard
    mov eax, TRUE
    mov ecx, 1
    ret

OnCommand:
    mov eax, wParam
    and eax, 0FFFFh
    cmp eax, IDC_DS_START
    jne HandledZero
    ; study the course the plan says is next, on the Timer screen
    INVOKE PlanNextCourse
    cmp eax, -1
    jne @F
    xor eax, eax
@@: INVOKE SetTimerCourse, eax
    INVOKE ShowPanel, PANEL_TIMER
    cmp tmRunning, 0
    jne HandledZero
    INVOKE SetTimerMode, TM_FOCUS   ; a study session, not a break
    INVOKE TimerStartPause

HandledZero:
    xor eax, eax
    mov ecx, 1
    ret
DashboardPanelMsg ENDP

END
