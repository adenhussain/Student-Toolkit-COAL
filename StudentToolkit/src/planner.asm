;=====================================================================
; planner.asm  -  the smart study planner
;
; Every course gets a priority score:
;   score = difficulty x credits x (6 - preparation) x urgency x risk
;     urgency  from days until that course's exam (Deadlines screen):
;              0-1 day 5,  2-3 days 4,  4-6 days 3,  7-13 days 2, else 1
;     risk     2 if the target grade needs more than 70% of the marks
;              still available (or is out of reach), else 1
;
; Then the timetable is built one day at a time:
;   - each day has (hours x 60 / 25) Pomodoro blocks of 25 minutes
;   - a course whose exam is today or already over gets nothing
;   - the day before an exam, that course's score doubles
;   - a course left out for 2 days in a row gets doubled again
;     (spaced revision, so nothing is forgotten)
;   - blocks are shared in proportion to the scores; leftover blocks
;     go to the highest scores first (the remainder rule from our
;     proposal); within a day the highest score is studied first
;
; Burnout check: hours per day above the daily limit -> red warning,
; and how many days the same work needs at the limit.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

UrgencyFor      PROTO :DWORD
CourseExamDay   PROTO :DWORD
CourseRisk      PROTO :DWORD
PlGeometry      PROTO :DWORD, :DWORD
PlText          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
PaintTimeline   PROTO :DWORD, :DWORD, :DWORD
PaintWhy        PROTO :DWORD, :DWORD, :DWORD
PaintLegend     PROTO :DWORD, :DWORD, :DWORD

IDC_PL_HOURS    = 1401
IDC_PL_DAYS     = 1402
IDC_PL_WHY      = 1410
RISK_PERCENT    = 70
GLYPH_TICK      = 0E73Eh

.data
; ---- results of BuildPlan ----
planGrid    BYTE MAX_PLAN_DAYS * MAX_COURSES DUP(0)   ; blocks [day][course]
dayOrder    BYTE MAX_PLAN_DAYS * MAX_COURSES DUP(0)   ; study order per day
dayCount    BYTE MAX_PLAN_DAYS DUP(0)                 ; courses studied per day
baseScore   DWORD MAX_COURSES DUP(0)    ; difficulty x credits x (6-prep) x risk
todayScore  DWORD MAX_COURSES DUP(0)    ; score for today (Why screen)
examDay     DWORD MAX_COURSES DUP(-1)   ; next exam of each course, -1 = none
riskOf      DWORD MAX_COURSES DUP(1)
totalBlocks DWORD MAX_COURSES DUP(0)    ; blocks over the whole plan
blocksPerDay DWORD 0
planToday   DWORD 0
; work areas
dayScore    DWORD MAX_COURSES DUP(0)
dayBlocks   DWORD MAX_COURSES DUP(0)
gapDays     DWORD MAX_COURSES DUP(0)    ; days since a course was studied
orderTmp    DWORD MAX_COURSES DUP(0)
doneToday   DWORD MAX_COURSES DUP(0)    ; Pomodoros finished today (Timer log)
doneTotal   DWORD 0
dayBudget   DWORD 0                     ; blocks still to share out this day
tickR       RECT <>

; ---- one pastel colour per course (background, text) ----
subjectBg   DWORD RGBC(0BFh,0D7h,0EAh)  ; sky
            DWORD RGBC(0F6h,0D5h,0C3h)  ; peach
            DWORD RGBC(0D7h,0E8h,0C5h)  ; sage
            DWORD RGBC(0E5h,0D4h,0F0h)  ; lilac
            DWORD RGBC(0F9h,0E3h,0A8h)  ; lemon
            DWORD RGBC(0C8h,0E6h,0E0h)  ; aqua
            DWORD RGBC(0F2h,0C9h,0D6h)  ; rose
            DWORD RGBC(0D9h,0D9h,0F2h)  ; periwinkle
            DWORD RGBC(0EBh,0D9h,0BCh)  ; sand
            DWORD RGBC(0CDh,0EBh,0D8h)  ; mint
subjectTx   DWORD RGBC(02Fh,04Ah,066h)
            DWORD RGBC(07Ah,03Eh,026h)
            DWORD RGBC(03Fh,056h,038h)
            DWORD RGBC(05Eh,03Fh,078h)
            DWORD RGBC(07Ah,05Ah,012h)
            DWORD RGBC(01Fh,055h,060h)
            DWORD RGBC(072h,024h,03Eh)
            DWORD RGBC(03Ch,034h,089h)
            DWORD RGBC(063h,038h,006h)
            DWORD RGBC(02Eh,06Bh,047h)

; ---- screen ----
hPlannerPanel   DWORD 0
hPlHours        DWORD 0
hPlDays         DWORD 0
hPlWhy          DWORD 0
hPlBrush        DWORD 0
showWhy         DWORD 0         ; 1 = "Why this plan?" view
plFocus         DWORD 0
plDirty         DWORD 0

pM          DWORD 0             ; geometry (real pixels)
pRight      DWORD 0
pBannerTop  DWORD 0
pGridTop    DWORD 0
pGridBot    DWORD 0
pLegendTop  DWORD 0

szLblHours      BYTE "Hours a day", 0
szLblDays       BYTE "Days", 0
szWhy           BYTE "Why this plan?", 0
szBack          BYTE "Back to timetable", 0
szFmtHealthy    BYTE "Healthy plan: %s a day, within your %s limit. Take a longer break after every 4 sessions.", 0
szFmtOverload   BYTE "Overload: %s a day is above your %s limit. The same work fits in %d days at the limit, or cut the hours.", 0
szNoCoursesPl   BYTE "Add your courses on the Courses screen to get a study plan.", 0
szFreeDay       BYTE "Free day - every exam is over", 0
szFmtExamOn     BYTE "%s exam", 0
szFmtHm         BYTE "%dh %02dm", 0
szFmtH          BYTE "%dh", 0
szFmtM          BYTE "%dm", 0
szFmtLegend     BYTE "%s  %s", 0
szFmtInt        BYTE "%d", 0
szFmtPct        BYTE "%d%%", 0
szFmtDaysLeft   BYTE "%d days", 0
szToday         BYTE "today", 0
szTomorrowPl    BYTE "tomorrow", 0
szDashPl        BYTE "-", 0
szWhyFormula    BYTE "score  =  difficulty  x  credits  x  (6 - preparation)  x  urgency  x  risk", 0
szWhyHead0      BYTE "Course", 0
szWhyHead1      BYTE "Diff.", 0
szWhyHead2      BYTE "Cr", 0
szWhyHead3      BYTE "6 - Prep", 0
szWhyHead4      BYTE "Exam", 0
szWhyHead5      BYTE "Urgency", 0
szWhyHead6      BYTE "Risk", 0
szWhyHead7      BYTE "Score", 0
szWhyHead8      BYTE "Today", 0
szWhyHead9      BYTE "Whole plan", 0
whyHeads        DWORD OFFSET szWhyHead0, OFFSET szWhyHead1, OFFSET szWhyHead2,
                      OFFSET szWhyHead3, OFFSET szWhyHead4, OFFSET szWhyHead5,
                      OFFSET szWhyHead6, OFFSET szWhyHead7, OFFSET szWhyHead8,
                      OFFSET szWhyHead9
whyColPct       DWORD 24, 7, 6, 9, 11, 9, 7, 9, 8, 10
szWhyRule1      BYTE "Urgency: exam in 0-1 day = 5,  2-3 days = 4,  4-6 days = 3,  7-13 days = 2,  later or none = 1.", 0
szWhyRule2      BYTE "Risk = 2 when the target grade needs more than 70% of the marks still available.", 0
szWhyRule3      BYTE "Day before an exam: that course counts double.  After its exam: no more time for it.", 0
szWhyRule4      BYTE "A course skipped two days in a row counts double (spaced revision). Highest score is studied first.", 0

plBuf       BYTE 160 DUP(0)
plBuf2      BYTE 32 DUP(0)
plBuf3      BYTE 32 DUP(0)

.code
;---------------------------------------------------------------------
; PlanMinutes / PlanDays - the settings, with defaults
;---------------------------------------------------------------------
PlanMinutes PROC
    mov eax, userData.planMinutes
    cmp eax, 0
    jne @F
    mov eax, DEFAULT_PLAN_MIN
@@: ret
PlanMinutes ENDP

PlanDays PROC
    mov eax, userData.planDays
    cmp eax, 0
    jne @F
    mov eax, DEFAULT_PLAN_DAYS
@@: ret
PlanDays ENDP

;---------------------------------------------------------------------
; PlanNextCourse - the course to study next today: the first one in
; today's order that still has unfinished blocks (BuildPlan first).
; Returns: EAX = course, or -1
;---------------------------------------------------------------------
PlanNextCourse PROC USES ebx ecx edx
    INVOKE BuildPlan
    movzx ecx, dayCount[0]
    xor ebx, ebx
FindLoop:
    cmp ebx, ecx
    jae None
    movzx edx, dayOrder[ebx]        ; course in today's order
    movzx eax, planGrid[edx]        ; its blocks today
    cmp eax, doneToday[edx*4]
    ja  Found                       ; not all done yet
    inc ebx
    jmp FindLoop
Found:
    mov eax, edx
    ret
None:
    mov eax, -1
    ret
PlanNextCourse ENDP

;---------------------------------------------------------------------
; UrgencyFor - urgency from the days left until an exam
; Returns: EAX = 1..5
;---------------------------------------------------------------------
UrgencyFor PROC daysLeft:DWORD
    mov eax, daysLeft
    cmp eax, 1
    jle U5
    cmp eax, 3
    jle U4
    cmp eax, 6
    jle U3
    cmp eax, 13
    jle U2
    mov eax, 1
    ret
U5: mov eax, 5
    ret
U4: mov eax, 4
    ret
U3: mov eax, 3
    ret
U2: mov eax, 2
    ret
UrgencyFor ENDP

;---------------------------------------------------------------------
; CourseExamDay - earliest unfinished exam of course cix from today on
; Returns: EAX = day number, or -1
;---------------------------------------------------------------------
CourseExamDay PROC USES ecx edx esi, cix:DWORD
    mov eax, -1
    mov esi, OFFSET userData.deadlines
    mov ecx, userData.deadlineCount
    jecxz Done
DlLoop:
    cmp (DEADLINE PTR [esi]).kind, DL_EXAM
    jne Next
    cmp (DEADLINE PTR [esi]).isDone, 0
    jne Next
    mov edx, (DEADLINE PTR [esi]).course
    cmp edx, cix
    jne Next
    mov edx, (DEADLINE PTR [esi]).dueDay
    cmp edx, NO_DATE
    je  Next                        ; no date: not an exam the plan can use
    cmp edx, planToday
    jl  Next                        ; already in the past
    cmp eax, -1
    je  Take
    cmp edx, eax
    jge Next
Take:
    mov eax, edx
Next:
    add esi, SIZEOF DEADLINE
    loop DlLoop
Done:
    ret
CourseExamDay ENDP

;---------------------------------------------------------------------
; CourseRisk - 2 if the target grade needs > 70% of the marks left
;---------------------------------------------------------------------
CourseRisk PROC USES ebx ecx edx, pCourse:DWORD
    mov ebx, pCourse
    INVOKE MarksNeeded, ebx, (COURSE PTR [ebx]).targetGrade
    cmp edx, 2
    je  Risky                       ; out of reach
    cmp edx, 0
    jne Safe                        ; secured or no marks yet
    ; need x 100 > left x 70 ?
    imul eax, eax, 100
    imul ecx, ecx, RISK_PERCENT
    cmp eax, ecx
    ja  Risky
Safe:
    mov eax, 1
    ret
Risky:
    mov eax, 2
    ret
CourseRisk ENDP

;---------------------------------------------------------------------
; BuildPlan - fills planGrid, dayOrder, totals and today's scores
;---------------------------------------------------------------------
BuildPlan PROC USES ebx ecx edx esi edi
    LOCAL days:DWORD, d:DWORD, dayNum:DWORD, sumScore:DWORD,
          used:DWORD, cix:DWORD, n:DWORD, k:DWORD, swapped:DWORD

    ; clear old results
    mov edi, OFFSET planGrid
    mov ecx, SIZEOF planGrid
    xor eax, eax
    cld
    rep stosb
    mov edi, OFFSET dayCount
    mov ecx, SIZEOF dayCount
    rep stosb
    mov edi, OFFSET totalBlocks
    mov ecx, SIZEOF totalBlocks
    rep stosb
    mov edi, OFFSET gapDays
    mov ecx, SIZEOF gapDays
    rep stosb

    INVOKE TodayDay
    mov planToday, eax
    INVOKE PlanDays
    mov days, eax
    INVOKE PlanMinutes
    xor edx, edx
    mov ecx, POMODORO_MIN
    div ecx                         ; blocks per day = minutes / 25
    cmp eax, 1
    jge @F
    mov eax, 1
@@: mov blocksPerDay, eax
    mov eax, userData.courseCount
    mov n, eax
    cmp eax, 0
    je  Done

    ; ---- base score of every course ----
    mov esi, OFFSET userData.courses
    mov cix, 0
BaseLoop:
    mov ebx, cix
    INVOKE CourseExamDay, ebx
    mov examDay[ebx*4], eax
    INVOKE CourseRisk, esi
    mov riskOf[ebx*4], eax
    mov ecx, 6
    sub ecx, (COURSE PTR [esi]).preparation
    imul eax, ecx                           ; risk x (6 - prep)
    imul eax, (COURSE PTR [esi]).difficulty
    imul eax, (COURSE PTR [esi]).credits
    mov baseScore[ebx*4], eax
    add esi, SIZEOF COURSE
    inc cix
    mov eax, cix
    cmp eax, n
    jb  BaseLoop

    ; ---- Pomodoros already finished today (re-plan from real study) ----
    mov doneTotal, 0
    xor ebx, ebx
DoneLoop:
    INVOKE MinutesToday, ebx
    xor edx, edx
    mov ecx, POMODORO_MIN
    div ecx
    mov doneToday[ebx*4], eax
    add doneTotal, eax
    inc ebx
    cmp ebx, n
    jb  DoneLoop

    ; ---- one day at a time ----
    mov d, 0
DayLoop:
    mov eax, d
    cmp eax, days
    jae Done
    add eax, planToday
    mov dayNum, eax

    ; scores for this day
    mov sumScore, 0
    xor ebx, ebx
ScoreLoop:
    xor edi, edi                    ; score 0 unless the course is still on
    mov eax, examDay[ebx*4]
    cmp eax, -1
    je  NoExam
    cmp dayNum, eax
    jge StoreScore                  ; exam today or over -> 0
    sub eax, dayNum                 ; days left
    INVOKE UrgencyFor, eax
    mov edi, eax
    imul edi, baseScore[ebx*4]
    mov eax, examDay[ebx*4]
    dec eax
    cmp eax, dayNum
    jne SpacedCheck
    shl edi, 1                      ; day before the exam: double
    jmp SpacedCheck
NoExam:
    mov edi, baseScore[ebx*4]       ; urgency 1
SpacedCheck:
    cmp gapDays[ebx*4], 2
    jb  StoreScore
    shl edi, 1                      ; skipped 2 days: double (spaced revision)
StoreScore:
    mov dayScore[ebx*4], edi
    add sumScore, edi
    cmp d, 0
    jne @F
    mov todayScore[ebx*4], edi
@@: inc ebx
    cmp ebx, n
    jb  ScoreLoop

    cmp sumScore, 0
    je  NextDay                     ; nothing left to study

    ; today only the time that is left is shared out
    mov eax, blocksPerDay
    cmp d, 0
    jne @F
    sub eax, doneTotal
    jge @F
    xor eax, eax
@@: mov dayBudget, eax

    ; blocks in proportion to the scores (rounded down)
    mov used, 0
    xor ebx, ebx
ShareLoop:
    mov eax, dayBudget
    mul dayScore[ebx*4]
    div sumScore
    mov dayBlocks[ebx*4], eax
    add used, eax
    inc ebx
    cmp ebx, n
    jb  ShareLoop

    ; order of the day: course numbers sorted by score (bubble sort)
    xor ebx, ebx
InitOrder:
    mov orderTmp[ebx*4], ebx
    inc ebx
    cmp ebx, n
    jb  InitOrder
SortPass:
    mov swapped, 0
    mov k, 1
SortStep:
    mov ebx, k
    cmp ebx, n
    jae SortCheck
    mov esi, orderTmp[ebx*4 - 4]
    mov edi, orderTmp[ebx*4]
    mov eax, dayScore[esi*4]
    cmp eax, dayScore[edi*4]
    jae NoSwap
    mov orderTmp[ebx*4 - 4], edi
    mov orderTmp[ebx*4], esi
    mov swapped, 1
NoSwap:
    inc k
    jmp SortStep
SortCheck:
    cmp swapped, 0
    jne SortPass

    ; leftover blocks: one each to the highest scores first
    mov eax, dayBudget
    sub eax, used
    mov k, 0
Leftover:
    cmp eax, 0
    je  LeftoverDone
    mov ebx, k
    mov ecx, orderTmp[ebx*4]
    cmp dayScore[ecx*4], 0
    je  WrapAround
    inc dayBlocks[ecx*4]
    dec eax
    inc k
    mov ebx, k
    cmp ebx, n
    jb  Leftover
WrapAround:
    mov k, 0
    jmp Leftover
LeftoverDone:

    ; store the day: grid, order, totals, gaps
    mov eax, d
    imul eax, eax, MAX_COURSES
    mov edi, eax                    ; edi = d * 10 (row start)
    xor ebx, ebx
StoreLoop:
    mov ecx, orderTmp[ebx*4]        ; course in study order
    mov eax, dayBlocks[ecx*4]
    cmp d, 0
    jne @F
    add eax, doneToday[ecx*4]       ; today: finished + still to do
@@: mov planGrid[edi + ecx], al
    add totalBlocks[ecx*4], eax
    cmp eax, 0
    je  Skipped
    mov gapDays[ecx*4], 0
    mov esi, d
    movzx edx, dayCount[esi]
    add edx, edi
    mov dayOrder[edx], cl           ; next place in today's order
    inc dayCount[esi]
    jmp StoreNext
Skipped:
    inc gapDays[ecx*4]
StoreNext:
    inc ebx
    cmp ebx, n
    jb  StoreLoop

NextDay:
    inc d
    jmp DayLoop
Done:
    ret
BuildPlan ENDP

;=====================================================================
;                          the screen
;=====================================================================
;---------------------------------------------------------------------
; PlannerInit - fields and the "Why this plan?" button
;---------------------------------------------------------------------
PlannerInit PROC hPanel:DWORD
    mov eax, hPanel
    mov hPlannerPanel, eax
    mov showWhy, 0
    INVOKE CreateSolidBrush, curTheme.clrCard
    mov hPlBrush, eax
    INVOKE CreateField, hPanel, IDC_PL_HOURS, 0, 4
    mov hPlHours, eax
    INVOKE CreateField, hPanel, IDC_PL_DAYS, ES_NUMBER, 2
    mov hPlDays, eax
    INVOKE CreatePastelButton, hPanel, ADDR szWhy, IDC_PL_WHY, BTN_SECONDARY
    mov hPlWhy, eax
    ; show the saved settings ("4" hours, "7" days)
    INVOKE PlanMinutes
    imul eax, eax, 10
    xor edx, edx
    mov ecx, 60
    div ecx                         ; hours x10
    INVOKE FormatTenths, eax, ADDR plBuf
    INVOKE SetWindowTextA, hPlHours, ADDR plBuf
    INVOKE PlanDays
    INVOKE FormatUInt, eax, ADDR plBuf
    INVOKE SetWindowTextA, hPlDays, ADDR plBuf
    mov plDirty, 0
    ret
PlannerInit ENDP

;---------------------------------------------------------------------
; PlGeometry - positions for the current size
;---------------------------------------------------------------------
PlGeometry PROC clientW:DWORD, clientH:DWORD
    INVOKE ScaleDpi, PAGE_MARGIN
    mov pM, eax
    mov ecx, clientW
    sub ecx, eax
    mov pRight, ecx
    INVOKE ScaleDpi, 156
    mov pBannerTop, eax
    INVOKE ScaleDpi, 210
    mov pGridTop, eax
    INVOKE ScaleDpi, 76
    mov ecx, clientH
    sub ecx, eax
    mov pGridBot, ecx
    INVOKE ScaleDpi, 64
    mov ecx, clientH
    sub ecx, eax
    mov pLegendTop, ecx
    ret
PlGeometry ENDP

;---------------------------------------------------------------------
; PlText - text in a rectangle
;---------------------------------------------------------------------
PlText PROC hdc:DWORD, pText:DWORD, x1:DWORD, y1:DWORD, x2:DWORD, y2:DWORD,
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
PlText ENDP

;---------------------------------------------------------------------
; FormatMinutes - 200 -> "3h 20m", 180 -> "3h", 50 -> "50m"
;---------------------------------------------------------------------
FormatMinutes PROC USES ecx edx, minutes:DWORD, pBuf:DWORD
    mov eax, minutes
    xor edx, edx
    mov ecx, 60
    div ecx                         ; eax = hours, edx = minutes
    cmp eax, 0
    jne HasHours
    INVOKE wsprintf, pBuf, ADDR szFmtM, edx
    ret
HasHours:
    cmp edx, 0
    jne Both
    INVOKE wsprintf, pBuf, ADDR szFmtH, eax
    ret
Both:
    INVOKE wsprintf, pBuf, ADDR szFmtHm, eax, edx
    ret
FormatMinutes ENDP

;---------------------------------------------------------------------
; PaintPlanner - toolbar boxes, burnout banner, timetable or Why view
;---------------------------------------------------------------------
PaintPlanner PROC USES ebx esi edi, hdc:DWORD, clientW:DWORD, clientH:DWORD
    LOCAL y1:DWORD, y2:DWORD, x:DWORD, limitDays:DWORD, total:DWORD,
          bannerBg:DWORD, bannerTx:DWORD

    INVOKE PlGeometry, clientW, clientH
    INVOKE BuildPlan

    ; ---- toolbar: [Hours a day  [ 4 ]]  [Days [ 7 ]] ----
    INVOKE ScaleDpi, 102
    mov y1, eax
    INVOKE ScaleDpi, 142
    mov y2, eax
    mov ebx, pM
    INVOKE ScaleDpi, 100
    lea esi, [ebx + eax]
    INVOKE PlText, hdc, ADDR szLblHours, ebx, y1, esi, y2, hFontBody, curTheme.clrMuted, DT_LEFT
    INVOKE ScaleDpi, 80
    lea edi, [esi + eax]
    xor ecx, ecx
    cmp plFocus, IDC_PL_HOURS
    jne @F
    inc ecx
@@: INVOKE DrawFieldBox, hdc, esi, y1, edi, y2, ecx
    INVOKE ScaleDpi, 28
    lea ebx, [edi + eax]
    INVOKE ScaleDpi, 50
    lea esi, [ebx + eax]
    INVOKE PlText, hdc, ADDR szLblDays, ebx, y1, esi, y2, hFontBody, curTheme.clrMuted, DT_LEFT
    INVOKE ScaleDpi, 70
    lea edi, [esi + eax]
    xor ecx, ecx
    cmp plFocus, IDC_PL_DAYS
    jne @F
    inc ecx
@@: INVOKE DrawFieldBox, hdc, esi, y1, edi, y2, ecx

    cmp userData.courseCount, 0
    jne HasCourses
    INVOKE ScaleDpi, 40
    add eax, pBannerTop
    INVOKE PlText, hdc, ADDR szNoCoursesPl, pM, pBannerTop, pRight, eax,
           hFontBody, curTheme.clrMuted, DT_LEFT
    ret

HasCourses:
    ; ---- burnout banner ----
    INVOKE PlanMinutes
    mov total, eax
    INVOKE FormatMinutes, total, ADDR plBuf2
    mov eax, userData.dailyLimit
    cmp eax, 0
    jne @F
    mov eax, DEFAULT_LIMIT
@@: mov ebx, eax                    ; daily limit in minutes
    INVOKE FormatMinutes, ebx, ADDR plBuf3
    mov eax, total
    cmp eax, ebx
    ja  Overload
    INVOKE wsprintf, ADDR plBuf, ADDR szFmtHealthy, ADDR plBuf2, ADDR plBuf3
    mov bannerBg, CLR_SAFE_BG
    mov bannerTx, CLR_SAFE_TX
    jmp DrawBanner
Overload:
    ; days needed at the limit = ceil(minutes x days / limit)
    INVOKE PlanDays
    mul total
    add eax, ebx
    dec eax
    xor edx, edx
    div ebx
    mov limitDays, eax
    INVOKE wsprintf, ADDR plBuf, ADDR szFmtOverload, ADDR plBuf2, ADDR plBuf3, limitDays
    mov bannerBg, CLR_DANGER_BG
    mov bannerTx, CLR_DANGER_TX
DrawBanner:
    INVOKE ScaleDpi, 40
    add eax, pBannerTop
    mov y2, eax
    INVOKE FillRound, hdc, pM, pBannerTop, pRight, y2, 12, bannerBg, bannerBg
    INVOKE ScaleDpi, 16
    mov ecx, pM
    add ecx, eax
    mov edx, pRight
    sub edx, eax
    INVOKE PlText, hdc, ADDR plBuf, ecx, pBannerTop, edx, y2, hFontSmall, bannerTx, DT_LEFT

    ; ---- card with the timetable or the explanation ----
    INVOKE FillRound, hdc, pM, pGridTop, pRight, pGridBot, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder
    cmp showWhy, 0
    jne @F
    INVOKE PaintTimeline, hdc, clientW, clientH
    INVOKE PaintLegend, hdc, clientW, clientH
    ret
@@: INVOKE PaintWhy, hdc, clientW, clientH
    ret
PaintPlanner ENDP

;---------------------------------------------------------------------
; PaintTimeline - one row per day: date + coloured 25-minute blocks
;---------------------------------------------------------------------
PaintTimeline PROC USES ebx esi edi, hdc:DWORD, clientW:DWORD, clientH:DWORD
    LOCAL days:DWORD, d:DWORD, rowH:DWORD, y1:DWORD, y2:DWORD, yMid:DWORD,
          barX1:DWORD, barX2:DWORD, blockW:DWORD, x:DWORD, k:DWORD,
          cix:DWORD, b:DWORD, pad:DWORD, gap:DWORD, labelBot:DWORD,
          compact:DWORD, inset:DWORD, dateFont:DWORD, doneLeft:DWORD

    INVOKE PlanDays
    mov days, eax
    INVOKE ScaleDpi, 20
    mov pad, eax
    INVOKE ScaleDpi, 3
    mov gap, eax

    ; row height: fit all days, at most 50px
    mov eax, pGridBot
    sub eax, pGridTop
    sub eax, pad
    sub eax, pad
    xor edx, edx
    div days
    mov rowH, eax
    INVOKE ScaleDpi, 50
    cmp rowH, eax
    jbe @F
    mov rowH, eax
@@:
    ; short rows (many days): one-line dates, thinner padding
    mov compact, 0
    mov eax, hFontBodyBold
    mov dateFont, eax
    INVOKE ScaleDpi, 40
    cmp rowH, eax
    jae @F
    mov compact, 1
    mov eax, hFontBody
    mov dateFont, eax
@@: mov eax, rowH                   ; block inset = 15% of the row
    imul eax, eax, 15
    xor edx, edx
    mov ecx, 100
    div ecx
    cmp eax, 2
    jge @F
    mov eax, 2
@@: mov inset, eax

    ; bar from after the date column to the right edge
    INVOKE ScaleDpi, 150
    add eax, pM
    mov barX1, eax
    mov eax, pRight
    sub eax, pad
    mov barX2, eax
    sub eax, barX1
    xor edx, edx
    div blocksPerDay
    mov blockW, eax

    mov d, 0
DayLoop:
    mov eax, d
    cmp eax, days
    jae Done
    mul rowH
    add eax, pGridTop
    add eax, pad
    mov y1, eax
    add eax, rowH
    mov y2, eax
    mov eax, y1
    add eax, y2
    shr eax, 1
    mov yMid, eax

    ; ---- date (and an exam on that day, in red) ----
    mov eax, planToday
    add eax, d
    INVOKE FormatDateShort, eax, ADDR plBuf
    mov ebx, pM
    add ebx, pad
    mov esi, barX1
    sub esi, 8
    mov edi, CLR_DANGER_TX          ; red if there is an exam that day
    mov eax, planToday
    add eax, d
    mov ecx, -1                     ; course with an exam, or -1
    xor edx, edx
ExamFind:
    cmp edx, userData.courseCount
    jae ExamFound
    cmp examDay[edx*4], eax
    jne @F
    mov ecx, edx
    jmp ExamFound
@@: inc edx
    jmp ExamFind
ExamFound:
    mov cix, ecx
    cmp ecx, -1
    jne @F
    mov edi, curTheme.clrText
@@: cmp compact, 0
    je  TwoLines
    ; compact: the date fills the row (red on an exam day)
    INVOKE PlText, hdc, ADDR plBuf, ebx, y1, esi, y2, dateFont, edi, DT_LEFT
    jmp NoExamLabel
TwoLines:
    INVOKE PlText, hdc, ADDR plBuf, ebx, y1, esi, yMid, dateFont, edi, DT_LEFT
    cmp cix, -1
    je  NoExamLabel
    mov eax, cix
    imul eax, eax, SIZEOF COURSE
    lea eax, userData.courses[eax]
    INVOKE wsprintf, ADDR plBuf, ADDR szFmtExamOn, eax
    INVOKE PlText, hdc, ADDR plBuf, ebx, yMid, esi, y2, hFontSmall, CLR_DANGER_TX, DT_LEFT
NoExamLabel:

    ; ---- the blocks of this day ----
    mov esi, d
    movzx eax, dayCount[esi]
    cmp eax, 0
    jne HasBlocks
    INVOKE PlText, hdc, ADDR szFreeDay, barX1, y1, barX2, y2, hFontSmall, curTheme.clrMuted, DT_LEFT
    jmp NextDay
HasBlocks:
    mov eax, barX1
    mov x, eax
    mov k, 0
OrderLoop:
    mov esi, d
    movzx eax, dayCount[esi]
    cmp k, eax
    jae NextDay
    imul esi, esi, MAX_COURSES
    add esi, k
    movzx ecx, dayOrder[esi]        ; course
    mov cix, ecx
    mov esi, d
    imul esi, esi, MAX_COURSES
    add esi, ecx
    movzx eax, planGrid[esi]        ; its blocks today
    mov b, eax
    mov doneLeft, 0                 ; first blocks of today = already done
    cmp d, 0
    jne @F
    mov eax, doneToday[ecx*4]
    mov doneLeft, eax
@@:
BlockLoop:
    cmp b, 0
    je  NextCourse
    ; one rounded block
    mov ebx, x
    add ebx, blockW
    sub ebx, gap
    mov eax, inset
    mov ecx, y1
    add ecx, eax
    mov edx, y2
    sub edx, eax
    mov edi, cix
    cmp doneLeft, 0
    je  NormalBlock
    ; finished today: outlined block with a tick
    INVOKE FillRound, hdc, x, ecx, ebx, edx, 6, subjectBg[edi*4], subjectTx[edi*4]
    mov eax, x
    mov tickR.left, eax
    mov tickR.right, ebx
    mov eax, y1
    mov tickR.top, eax
    mov eax, y2
    mov tickR.bottom, eax
    mov edi, cix
    INVOKE DrawGlyph, hdc, GLYPH_TICK, ADDR tickR, hFontIcon, subjectTx[edi*4],
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    dec doneLeft
    jmp NoLabel
NormalBlock:
    INVOKE FillRound, hdc, x, ecx, ebx, edx, 6, subjectBg[edi*4], subjectBg[edi*4]
    ; short course name inside the block if it fits
    INVOKE ScaleDpi, 34
    cmp blockW, eax
    jb  NoLabel
    INVOKE ScaleDpi, 18
    mov ecx, y2
    sub ecx, y1
    sub ecx, inset
    sub ecx, inset
    cmp ecx, eax
    jb  NoLabel                     ; block too thin for text
    mov eax, cix
    imul eax, eax, SIZEOF COURSE
    lea eax, userData.courses[eax]
    INVOKE ScaleDpi, 4
    mov ecx, x
    add ecx, eax
    mov edx, ebx
    sub edx, eax
    mov eax, cix
    imul eax, eax, SIZEOF COURSE
    lea eax, userData.courses[eax]
    mov edi, cix
    INVOKE PlText, hdc, eax, ecx, y1, edx, y2, hFontSmall, subjectTx[edi*4], DT_CENTER
NoLabel:
    mov eax, blockW
    add x, eax
    dec b
    jmp BlockLoop
NextCourse:
    inc k
    jmp OrderLoop

NextDay:
    inc d
    jmp DayLoop
Done:
    ret
PaintTimeline ENDP

;---------------------------------------------------------------------
; PaintLegend - colour key with each course's total time
;---------------------------------------------------------------------
PaintLegend PROC USES ebx esi edi, hdc:DWORD, clientW:DWORD, clientH:DWORD
    LOCAL x:DWORD, y1:DWORD, y2:DWORD, cix:DWORD, sq:DWORD, itemW:DWORD

    mov eax, pLegendTop
    mov y1, eax
    INVOKE ScaleDpi, 28
    add eax, y1
    mov y2, eax
    INVOKE ScaleDpi, 12
    mov sq, eax
    ; items share the width evenly (5 per line max)
    mov eax, pRight
    sub eax, pM
    mov ecx, userData.courseCount
    cmp ecx, 5
    jbe @F
    mov ecx, 5
@@: xor edx, edx
    div ecx
    mov itemW, eax
    mov eax, pM
    mov x, eax
    mov cix, 0
ItemLoop:
    mov eax, cix
    cmp eax, userData.courseCount
    jae Done
    cmp eax, 5
    jne @F
    ; second line
    mov eax, pM
    mov x, eax
    INVOKE ScaleDpi, 26
    add y1, eax
    add y2, eax
@@: ; colour square
    mov ebx, y1
    add ebx, y2
    shr ebx, 1
    mov ecx, sq
    shr ecx, 1
    sub ebx, ecx
    mov ecx, x
    add ecx, sq
    mov edx, ebx
    add edx, sq
    mov edi, cix
    INVOKE FillRound, hdc, x, ebx, ecx, edx, 3, subjectBg[edi*4], subjectTx[edi*4]
    ; "COAL  3h 20m"
    mov eax, totalBlocks[edi*4]
    imul eax, eax, POMODORO_MIN
    INVOKE FormatMinutes, eax, ADDR plBuf2
    mov eax, cix
    imul eax, eax, SIZEOF COURSE
    lea eax, userData.courses[eax]
    INVOKE wsprintf, ADDR plBuf, ADDR szFmtLegend, eax, ADDR plBuf2
    mov ebx, x
    add ebx, sq
    INVOKE ScaleDpi, 8
    add ebx, eax
    mov esi, x
    add esi, itemW
    sub esi, eax
    INVOKE PlText, hdc, ADDR plBuf, ebx, y1, esi, y2, hFontSmall, curTheme.clrText, DT_LEFT
    mov eax, itemW
    add x, eax
    inc cix
    jmp ItemLoop
Done:
    ret
PaintLegend ENDP

;---------------------------------------------------------------------
; PaintWhy - table with every factor of every course's score
;---------------------------------------------------------------------
PaintWhy PROC USES ebx esi edi, hdc:DWORD, clientW:DWORD, clientH:DWORD
    LOCAL pad:DWORD, y1:DWORD, y2:DWORD, rowH:DWORD, cix:DWORD, col:DWORD,
          colX:DWORD, colX2:DWORD, sumToday:DWORD, innerW:DWORD, cum:DWORD

    INVOKE ScaleDpi, 20
    mov pad, eax
    INVOKE ScaleDpi, 30
    mov rowH, eax
    mov eax, pRight
    sub eax, pM
    sub eax, pad
    sub eax, pad
    mov innerW, eax

    ; formula line
    mov eax, pGridTop
    add eax, pad
    mov y1, eax
    add eax, rowH
    mov y2, eax
    mov ebx, pM
    add ebx, pad
    mov esi, pRight
    sub esi, pad
    INVOKE PlText, hdc, ADDR szWhyFormula, ebx, y1, esi, y2, hFontBodyBold, curTheme.clrSideActText, DT_LEFT

    ; sum of today's scores (for the share column)
    mov sumToday, 0
    xor ecx, ecx
@@: cmp ecx, userData.courseCount
    jae @F
    mov eax, todayScore[ecx*4]
    add sumToday, eax
    inc ecx
    jmp @B
@@:
    ; ---- header and one row per course ----
    mov cix, -1                       ; -1 = header row
RowLoop:
    mov eax, rowH
    add y1, eax
    add y2, eax
    mov col, 0
    mov cum, 0
ColLoop:
    cmp col, 10
    jae RowDone
    ; column x = left + innerW x cum% / 100
    mov eax, innerW
    mul cum
    mov ecx, 100
    div ecx
    add eax, pM
    add eax, pad
    mov colX, eax
    mov ecx, col
    mov eax, whyColPct[ecx*4]
    add cum, eax
    mov eax, innerW
    mul cum
    mov ecx, 100
    div ecx
    add eax, pM
    add eax, pad
    sub eax, 6
    mov colX2, eax

    cmp cix, -1
    jne CellValue
    mov ecx, col
    INVOKE PlText, hdc, whyHeads[ecx*4], colX, y1, colX2, y2, hFontSmall, curTheme.clrMuted, DT_LEFT
    jmp NextCol

CellValue:
    mov ebx, cix
    imul esi, ebx, SIZEOF COURSE
    lea esi, userData.courses[esi]
    mov eax, col
    cmp eax, 0
    jne @F
    INVOKE PlText, hdc, esi, colX, y1, colX2, y2, hFontBodyBold, curTheme.clrText, DT_LEFT
    jmp NextCol
@@: cmp eax, 1
    jne @F
    mov eax, (COURSE PTR [esi]).difficulty
    jmp ShowNumber
@@: cmp eax, 2
    jne @F
    mov eax, (COURSE PTR [esi]).credits
    jmp ShowNumber
@@: cmp eax, 3
    jne @F
    mov eax, 6
    sub eax, (COURSE PTR [esi]).preparation
    jmp ShowNumber
@@: cmp eax, 4
    jne @F
    ; exam: "in 5 days", "tomorrow", "today", "-"
    mov eax, examDay[ebx*4]
    cmp eax, -1
    jne HasExam
    INVOKE Str_copy, ADDR szDashPl, ADDR plBuf
    jmp ShowText
HasExam:
    sub eax, planToday
    cmp eax, 0
    jne NotToday
    INVOKE Str_copy, ADDR szToday, ADDR plBuf
    jmp ShowText
NotToday:
    cmp eax, 1
    jne NotTomorrow
    INVOKE Str_copy, ADDR szTomorrowPl, ADDR plBuf
    jmp ShowText
NotTomorrow:
    INVOKE wsprintf, ADDR plBuf, ADDR szFmtDaysLeft, eax
    jmp ShowText
@@: cmp eax, 5
    jne @F
    ; urgency today
    mov eax, examDay[ebx*4]
    cmp eax, -1
    jne UrgExam
    mov eax, 1
    jmp ShowNumber
UrgExam:
    sub eax, planToday
    INVOKE UrgencyFor, eax
    jmp ShowNumber
@@: cmp eax, 6
    jne @F
    mov eax, riskOf[ebx*4]
    jmp ShowNumber
@@: cmp eax, 7
    jne @F
    mov eax, todayScore[ebx*4]
    jmp ShowBold
@@: cmp eax, 8
    jne @F
    ; share of today's time
    mov eax, todayScore[ebx*4]
    imul eax, eax, 100
    xor edx, edx
    cmp sumToday, 0
    je  ZeroShare
    div sumToday
    jmp PctReady
ZeroShare:
    xor eax, eax
PctReady:
    INVOKE wsprintf, ADDR plBuf, ADDR szFmtPct, eax
    jmp ShowText
@@: ; whole plan time
    mov eax, totalBlocks[ebx*4]
    imul eax, eax, POMODORO_MIN
    INVOKE FormatMinutes, eax, ADDR plBuf
    jmp ShowText

ShowNumber:
    INVOKE wsprintf, ADDR plBuf, ADDR szFmtInt, eax
ShowText:
    INVOKE PlText, hdc, ADDR plBuf, colX, y1, colX2, y2, hFontBody, curTheme.clrText, DT_LEFT
    jmp NextCol
ShowBold:
    INVOKE wsprintf, ADDR plBuf, ADDR szFmtInt, eax
    INVOKE PlText, hdc, ADDR plBuf, colX, y1, colX2, y2, hFontBodyBold, curTheme.clrSideActText, DT_LEFT
NextCol:
    inc col
    jmp ColLoop
RowDone:
    inc cix
    mov eax, cix
    cmp eax, userData.courseCount
    jb  RowLoop

    ; ---- the rules in words ----
    mov ebx, pM
    add ebx, pad
    mov esi, pRight
    sub esi, pad
    INVOKE ScaleDpi, 12
    add y1, eax
    add y2, eax
    mov edi, OFFSET szWhyRule1
    mov cix, 0
RuleLoop:
    INVOKE ScaleDpi, 26
    add y1, eax
    add y2, eax
    mov eax, y2
    cmp eax, pGridBot
    ja  Done                        ; no room left
    INVOKE PlText, hdc, edi, ebx, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_LEFT
    INVOKE Str_length, edi
    lea edi, [edi + eax + 1]        ; next rule string
    inc cix
    cmp cix, 4
    jb  RuleLoop
Done:
    ret
PaintWhy ENDP

;---------------------------------------------------------------------
; PlLayout (helper) - moves the two fields and the button
;---------------------------------------------------------------------
PlLayout PROC USES ebx esi edi
    LOCAL rc:RECT, inset:DWORD, editH:DWORD, posY:DWORD

    INVOKE GetClientRect, hPlannerPanel, ADDR rc
    INVOKE PlGeometry, rc.right, rc.bottom
    INVOKE ScaleDpi, 12
    mov inset, eax
    INVOKE ScaleDpi, 22
    mov editH, eax
    INVOKE ScaleDpi, 102 + 9
    mov posY, eax
    ; hours box: x = margin + 100
    INVOKE ScaleDpi, 100
    add eax, pM
    add eax, inset
    mov ebx, eax
    INVOKE ScaleDpi, 80 - 24
    INVOKE MoveWindow, hPlHours, ebx, posY, eax, editH, TRUE
    ; days box: after hours box + 28 + label 50
    INVOKE ScaleDpi, 100 + 80 + 28 + 50
    add eax, pM
    add eax, inset
    mov ebx, eax
    INVOKE ScaleDpi, 70 - 24
    INVOKE MoveWindow, hPlDays, ebx, posY, eax, editH, TRUE
    ; "Why this plan?" at the right
    INVOKE ScaleDpi, 190
    mov ebx, pRight
    sub ebx, eax
    INVOKE ScaleDpi, 102
    mov esi, eax
    INVOKE ScaleDpi, 40
    mov edi, eax
    INVOKE ScaleDpi, 190
    INVOKE MoveWindow, hPlWhy, ebx, esi, eax, edi, TRUE
    ret
PlLayout ENDP

;---------------------------------------------------------------------
; PlannerPanelMsg - messages for the Planner screen
;---------------------------------------------------------------------
PlannerPanelMsg PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    cmp uMsg, WM_SIZE
    je  OnSize
    cmp uMsg, WM_CTLCOLOREDIT
    je  OnFieldColor
    cmp uMsg, WM_DRAWITEM
    je  OnDrawItem
    cmp uMsg, WM_COMMAND
    je  OnCommand
    jmp NotHandled

OnSize:
    INVOKE PlLayout
    jmp HandledZero

OnFieldColor:
    INVOKE GdiSetTextColor, wParam, curTheme.clrText
    INVOKE SetBkColor, wParam, curTheme.clrCard
    mov eax, hCardBrush             ; follows the current theme
    jmp Handled

OnDrawItem:
    INVOKE DrawPastelButton, lParam, curTheme.clrBg
    mov eax, TRUE
    jmp Handled

OnCommand:
    mov eax, wParam
    mov ebx, eax
    and eax, 0FFFFh
    shr ebx, 16
    cmp eax, IDC_PL_WHY
    jne NotWhy
    xor showWhy, 1
    mov edx, OFFSET szWhy
    cmp showWhy, 0
    je  @F
    mov edx, OFFSET szBack
@@: INVOKE SetWindowTextA, hPlWhy, edx
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero
NotWhy:
    cmp ebx, EN_SETFOCUS
    jne @F
    mov plFocus, eax
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero
@@: cmp ebx, EN_KILLFOCUS
    jne @F
    mov plFocus, 0
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    cmp plDirty, 0
    je  HandledZero
    mov plDirty, 0
    INVOKE SaveWithStatus
    jmp HandledZero
@@: cmp ebx, EN_CHANGE
    jne HandledZero
    cmp eax, IDC_PL_HOURS
    jne NotHours
    ; hours a day: 0.5 .. 16, stored as minutes
    INVOKE GetWindowTextA, hPlHours, ADDR plBuf2, SIZEOF plBuf2
    INVOKE ParseTenths, ADDR plBuf2
    cmp edx, 0
    je  HandledZero
    cmp eax, 5
    jb  HandledZero
    cmp eax, 160
    ja  HandledZero
    imul eax, eax, 6                ; tenths of an hour -> minutes
    mov userData.planMinutes, eax
    mov plDirty, 1
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero
NotHours:
    cmp eax, IDC_PL_DAYS
    jne HandledZero
    INVOKE GetWindowTextA, hPlDays, ADDR plBuf2, SIZEOF plBuf2
    INVOKE ParseUInt, ADDR plBuf2
    cmp eax, 1
    jb  HandledZero
    cmp eax, MAX_PLAN_DAYS
    ja  HandledZero
    mov userData.planDays, eax
    mov plDirty, 1
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero

HandledZero:
    xor eax, eax
Handled:
    mov ecx, 1
    ret
NotHandled:
    xor ecx, ecx
    ret
PlannerPanelMsg ENDP

END
