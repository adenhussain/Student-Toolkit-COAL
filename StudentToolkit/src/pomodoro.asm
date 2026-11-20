;=====================================================================
; pomodoro.asm  -  the Pomodoro timer and the Timer screen
;
; Cycle: Focus 25 min -> short break 5 -> focus -> ... after 4 focus
; sessions a long 15-minute break.
; A Windows timer (SetTimer) sends WM_TIMER every 1000 ms; each tick
; takes one second off (12 seconds in "Demo speed", so a whole
; session takes about 2 minutes for the viva).
; When a focus session finishes:
;   - 25 minutes go into the study log for the chosen course
;   - the streak and badges are updated
;   - a chime plays and Windows shows a notification
; Stopping halfway logs nothing (a Pomodoro only counts when finished).
;
; Screen: left card = timer, right = streak card and badge wall.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

FinishSession   PROTO
TimerTick       PROTO
TimerReset      PROTO
PickTimerCourse PROTO :DWORD
TmLayout        PROTO
TmGeometry      PROTO :DWORD, :DWORD
TmText          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
UpdateTimerButtons PROTO
FormatTimeHM    PROTO :DWORD, :DWORD

IDC_TM_COURSE   = 1501
IDC_TM_MODE     = 1502          ; 1502..1504 mode chips
IDC_TM_START    = 1510
IDC_TM_RESET    = 1511
IDC_TM_MINI     = 1512
IDC_TM_DEMO     = 1513
IDC_TM_GUARD    = 1514
TIMER_POMODORO  = 2
DEMO_STEP       = 12            ; seconds per tick in demo speed

.data
tmMode      DWORD TM_FOCUS
tmTotal     DWORD FOCUS_SECONDS
tmRemaining DWORD FOCUS_SECONDS
tmRunning   DWORD 0
tmStarted   DWORD 0             ; 1 once started (Pause -> "Resume")
tmCourse    DWORD 0
tmCycle     DWORD 0             ; focus sessions done in this cycle (0-3)
tmDemo      DWORD 0
lastBadge   DWORD -1            ; badge unlocked most recently (for the card)

hTimerPanel DWORD 0
hTmCourse   DWORD 0
hTmMode     DWORD 3 DUP(0)
hTmStart    DWORD 0
hTmReset    DWORD 0
hTmMini     DWORD 0
hTmDemo     DWORD 0
hTmGuard    DWORD 0

; geometry (real pixels)
tM          DWORD 0
tLeftX2     DWORD 0
tRightX1    DWORD 0
tRightX2    DWORD 0
tTop        DWORD 0
tBottom     DWORD 0
tStreakBot  DWORD 0

szMode0     BYTE "Focus  25", 0
szMode1     BYTE "Short break  5", 0
szMode2     BYTE "Long break  15", 0
modeNames   DWORD OFFSET szMode0, OFFSET szMode1, OFFSET szMode2
modeSeconds DWORD FOCUS_SECONDS, SHORT_SECONDS, LONG_SECONDS
szStart     BYTE "Start", 0
szPause     BYTE "Pause", 0
szResume    BYTE "Resume", 0
szReset     BYTE "Reset", 0
szMini      BYTE "Mini timer", 0
szDemo      BYTE "Demo speed", 0
szStudying  BYTE "Studying", 0
szNoCourse  BYTE "No course", 0
szFmtTime   BYTE "%02d:%02d", 0
szFmtCycle  BYTE "Focus session %d of 4  |  long break after the 4th", 0
szOnBreak   BYTE "Break time: stand up, drink water, rest your eyes", 0
szNeedCourse BYTE "Add a course on the Courses screen first.", 0
szNeedCourseT BYTE "Timer", 0

szStreakT   BYTE "Study streak", 0
szFmtStreak BYTE "%d-day streak", 0
szNoStreak  BYTE "No streak yet", 0
szFmtBest   BYTE "Best streak: %d", 0
szFmtToday  BYTE "Sessions today: %d  |  %s", 0
szFmtTotal  BYTE "All time: %s  |  sessions: %d", 0
szBadgesT   BYTE "Badges", 0
szFmtBadges BYTE "%d of 8 earned", 0

szDoneTitle BYTE "Session done", 0
szFmtDoneS  BYTE "%s: 25 minutes logged. Time for a 5-minute break.", 0
szFmtDoneL  BYTE "%s: 25 minutes logged. 4 in a row - take a 15-minute break!", 0
szFmtDoneFS BYTE "%s: 25 minutes logged, focus score %d%%. Time for a 5-minute break.", 0
szFmtDoneFL BYTE "%s: 25 minutes logged, focus score %d%%. Take a 15-minute break!", 0
szGuard     BYTE "Focus Guard", 0
szFmtGuardOn BYTE "Focus Guard is watching  |  distractions: %d", 0
szFmtLastScore BYTE "Last session focus score: %d%%", 0
szLogGuardOn BYTE "Focus Guard switched on", 0
szLogGuardOff BYTE "Focus Guard switched off", 0
szBreakTitle BYTE "Break over", 0
szBreakText BYTE "Ready for the next focus session?", 0
szBadgeTitle BYTE "Badge unlocked", 0
szLogPomo   BYTE "Pomodoro finished: %s (25 min)", 0
szLogBadge  BYTE "Badge unlocked: %s", 0

szHM1       BYTE "%dh %02dm", 0
szHM2       BYTE "%dm", 0
tmBuf       BYTE 160 DUP(0)
tmBuf2      BYTE 32 DUP(0)

GLYPH_STAR  = 0E735h            ; filled star
GLYPH_LOCK  = 0E72Eh

.code
;---------------------------------------------------------------------
; TimerInit - the controls of the Timer screen
;---------------------------------------------------------------------
TimerInit PROC USES ebx esi, hPanel:DWORD
    mov eax, hPanel
    mov hTimerPanel, eax
    mov tmRunning, 0
    mov tmStarted, 0
    mov tmCycle, 0
    mov lastBadge, -1
    mov tmCourse, 0
    mov tmDemo, 0                   ; demo speed is off at every login

    INVOKE CreatePastelButton, hPanel, ADDR szNoCourse, IDC_TM_COURSE, BTN_PICKER
    mov hTmCourse, eax
    xor esi, esi
ModeLoop:
    lea ebx, [esi + IDC_TM_MODE]
    INVOKE CreatePastelButton, hPanel, modeNames[esi*4], ebx, BTN_CHIP
    mov hTmMode[esi*4], eax
    inc esi
    cmp esi, 3
    jb  ModeLoop
    INVOKE CreatePastelButton, hPanel, ADDR szStart, IDC_TM_START, BTN_PRIMARY
    mov hTmStart, eax
    INVOKE CreatePastelButton, hPanel, ADDR szReset, IDC_TM_RESET, BTN_SECONDARY
    mov hTmReset, eax
    INVOKE CreatePastelButton, hPanel, ADDR szMini, IDC_TM_MINI, BTN_SECONDARY
    mov hTmMini, eax
    INVOKE CreatePastelButton, hPanel, ADDR szDemo, IDC_TM_DEMO, BTN_CHIP
    mov hTmDemo, eax
    INVOKE SetChipSelected, hTmDemo, tmDemo
    INVOKE CreatePastelButton, hPanel, ADDR szGuard, IDC_TM_GUARD, BTN_CHIP
    mov hTmGuard, eax
    mov eax, userData.focusGuardOff
    xor eax, 1                      ; selected = on
    INVOKE SetChipSelected, hTmGuard, eax

    INVOKE SetTimerMode, TM_FOCUS
    INVOKE TimerCourseName
    INVOKE SetWindowTextA, hTmCourse, eax
    ret
TimerInit ENDP

;---------------------------------------------------------------------
; TimerCourseName - name of the chosen course.  Returns: EAX = text
;---------------------------------------------------------------------
TimerCourseName PROC
    mov eax, tmCourse
    cmp eax, userData.courseCount
    jae NoCourse
    imul eax, eax, SIZEOF COURSE
    lea eax, userData.courses[eax]
    ret
NoCourse:
    mov eax, OFFSET szNoCourse
    ret
TimerCourseName ENDP

;---------------------------------------------------------------------
; SetTimerCourse - chooses the course (from the Dashboard button)
;---------------------------------------------------------------------
SetTimerCourse PROC course:DWORD
    mov eax, course
    cmp eax, userData.courseCount
    jae @F
    mov tmCourse, eax
    INVOKE TimerCourseName
    INVOKE SetWindowTextA, hTmCourse, eax
    INVOKE RefreshMiniTimer
@@: ret
SetTimerCourse ENDP

;---------------------------------------------------------------------
; FormatTimeLeft - "24:59" into pBuf
;---------------------------------------------------------------------
FormatTimeLeft PROC USES ecx edx, pBuf:DWORD
    mov eax, tmRemaining
    xor edx, edx
    mov ecx, 60
    div ecx                         ; eax = minutes, edx = seconds
    INVOKE wsprintf, pBuf, ADDR szFmtTime, eax, edx
    ret
FormatTimeLeft ENDP

;---------------------------------------------------------------------
; UpdateTimerButtons - Start / Pause / Resume text, chips, repaint
;---------------------------------------------------------------------
UpdateTimerButtons PROC USES ebx
    mov edx, OFFSET szStart
    cmp tmRunning, 0
    je  @F
    mov edx, OFFSET szPause
    jmp SetText
@@: cmp tmStarted, 0
    je  SetText
    mov edx, OFFSET szResume
SetText:
    INVOKE SetWindowTextA, hTmStart, edx
    xor ebx, ebx
ChipLoop:
    xor eax, eax
    cmp ebx, tmMode
    jne @F
    inc eax
@@: INVOKE SetChipSelected, hTmMode[ebx*4], eax
    inc ebx
    cmp ebx, 3
    jb  ChipLoop
    INVOKE InvalidateRect, hTimerPanel, NULL, FALSE
    INVOKE RefreshMiniTimer
    ret
UpdateTimerButtons ENDP

;---------------------------------------------------------------------
; SetTimerMode - switches to Focus / Short / Long and stops the clock
;---------------------------------------------------------------------
SetTimerMode PROC mode:DWORD
    INVOKE FocusReset
    INVOKE KillTimer, hTimerPanel, TIMER_POMODORO
    mov tmRunning, 0
    mov tmStarted, 0
    mov eax, mode
    mov tmMode, eax
    mov eax, modeSeconds[eax*4]
    mov tmTotal, eax
    mov tmRemaining, eax
    INVOKE UpdateTimerButtons
    ret
SetTimerMode ENDP

;---------------------------------------------------------------------
; TimerStartPause - the Start / Pause / Resume button
;---------------------------------------------------------------------
TimerStartPause PROC
    cmp tmRunning, 0
    je  StartIt
    INVOKE KillTimer, hTimerPanel, TIMER_POMODORO
    mov tmRunning, 0
    jmp Done
StartIt:
    cmp tmMode, TM_FOCUS
    jne @F
    cmp userData.courseCount, 0
    jne @F
    INVOKE MessageBoxA, hMainWnd, ADDR szNeedCourse, ADDR szNeedCourseT,
           MB_OK OR MB_ICONINFORMATION
    ret
@@: mov tmRunning, 1
    mov tmStarted, 1
    INVOKE SetTimer, hTimerPanel, TIMER_POMODORO, 1000, NULL
Done:
    INVOKE UpdateTimerButtons
    ret
TimerStartPause ENDP

;---------------------------------------------------------------------
; TimerReset - back to the full time of the current mode
;---------------------------------------------------------------------
TimerReset PROC
    INVOKE SetTimerMode, tmMode
    ret
TimerReset ENDP

;---------------------------------------------------------------------
; TimerStop - used when logging out
;---------------------------------------------------------------------
TimerStop PROC
    cmp hTimerPanel, 0
    je  @F
    INVOKE KillTimer, hTimerPanel, TIMER_POMODORO
@@: mov tmRunning, 0
    mov tmStarted, 0
    mov hTimerPanel, 0
    INVOKE CloseMiniTimer
    ret
TimerStop ENDP

;---------------------------------------------------------------------
; TimerTick - one WM_TIMER: take time off, finish at zero
;---------------------------------------------------------------------
TimerTick PROC
    cmp tmMode, TM_FOCUS
    jne @F
    cmp userData.focusGuardOff, 0
    jne @F
    INVOKE FocusCheck               ; Focus Guard: one check per second
@@: mov eax, 1
    cmp tmDemo, 0
    je  @F
    mov eax, DEMO_STEP
@@: sub tmRemaining, eax
    jg  StillRunning
    mov tmRemaining, 0
    INVOKE FinishSession
    ret
StillRunning:
    INVOKE InvalidateRect, hTimerPanel, NULL, FALSE
    INVOKE RefreshMiniTimer
    ret
TimerTick ENDP

;---------------------------------------------------------------------
; FinishSession - focus done: log it, streak, badges, chime, toast;
;                 break done: chime and toast. Then the next mode.
;---------------------------------------------------------------------
FinishSession PROC USES ebx esi edi
    LOCAL newBadges:DWORD, nextMode:DWORD

    INVOKE KillTimer, hTimerPanel, TIMER_POMODORO
    mov tmRunning, 0
    cmp tmMode, TM_FOCUS
    jne BreakDone

    ; ---- a focus session is complete ----
    INVOKE LogStudy, tmCourse, POMODORO_MIN
    INVOKE TimerCourseName
    INVOKE LogEventFmt, ADDR szLogPomo, eax
    INVOKE UpdateStreak
    INVOKE CheckBadges
    mov newBadges, eax
    INVOKE SaveWithStatus

    inc tmCycle
    mov nextMode, TM_SHORT
    mov esi, OFFSET szFmtDoneS
    mov edi, OFFSET szFmtDoneFS
    cmp tmCycle, 4
    jb  @F
    mov tmCycle, 0
    mov nextMode, TM_LONG
    mov esi, OFFSET szFmtDoneL
    mov edi, OFFSET szFmtDoneFL
@@: INVOKE PlayChime, CHIME_DONE
    cmp userData.focusGuardOff, 0
    jne NoScore
    ; with Focus Guard: the message includes the focus score
    INVOKE FocusScore
    mov userData.lastFocusScore, eax
    mov ebx, eax
    INVOKE TimerCourseName
    INVOKE wsprintf, ADDR tmBuf, edi, eax, ebx
    INVOKE SaveUser
    jmp Announce
NoScore:
    INVOKE TimerCourseName
    INVOKE wsprintf, ADDR tmBuf, esi, eax
Announce:
    INVOKE TrayNotify, ADDR szDoneTitle, ADDR tmBuf

    ; a new badge? announce the first new one
    cmp newBadges, 0
    je  NextMode
    xor ebx, ebx
FindBit:
    bt  newBadges, ebx              ; test bit number ebx
    jc  FoundBit
    inc ebx
    cmp ebx, BADGE_COUNT
    jb  FindBit
    jmp NextMode
FoundBit:
    mov lastBadge, ebx
    INVOKE LogEventFmt, ADDR szLogBadge, badgeNames[ebx*4]
    INVOKE PlayChime, CHIME_BADGE
    INVOKE TrayNotify, ADDR szBadgeTitle, badgeNames[ebx*4]
    jmp NextMode

BreakDone:
    mov nextMode, TM_FOCUS
    INVOKE PlayChime, CHIME_BREAK
    INVOKE TrayNotify, ADDR szBreakTitle, ADDR szBreakText

NextMode:
    INVOKE SetTimerMode, nextMode
    ret
FinishSession ENDP

;---------------------------------------------------------------------
; PickTimerCourse - menu of courses under the picker
;---------------------------------------------------------------------
PickTimerCourse PROC USES ebx esi edi, hWnd:DWORD
    LOCAL btnR:RECT, hMenu:DWORD

    cmp userData.courseCount, 0
    je  Done
    INVOKE CreatePopupMenu
    mov hMenu, eax
    mov esi, OFFSET userData.courses
    xor ebx, ebx
ItemLoop:
    cmp ebx, userData.courseCount
    jae ItemsDone
    mov edx, MF_STRING
    cmp ebx, tmCourse
    jne @F
    or  edx, MF_CHECKED
@@: lea edi, [ebx + 1]              ; menu IDs start at 1
    INVOKE AppendMenuA, hMenu, edx, edi, esi
    add esi, SIZEOF COURSE
    inc ebx
    jmp ItemLoop
ItemsDone:
    INVOKE GetWindowRect, hTmCourse, ADDR btnR
    INVOKE TrackPopupMenu, hMenu, TPM_RETURNCMD, btnR.left, btnR.bottom, 0, hWnd, NULL
    mov ebx, eax
    INVOKE DestroyMenu, hMenu
    cmp ebx, 0
    je  Done
    dec ebx
    mov tmCourse, ebx
    INVOKE TimerCourseName
    INVOKE SetWindowTextA, hTmCourse, eax
    INVOKE RefreshMiniTimer
Done:
    ret
PickTimerCourse ENDP

;---------------------------------------------------------------------
; TmGeometry - left card (timer) and right column (streak, badges)
;---------------------------------------------------------------------
TmGeometry PROC USES ecx edx, clientW:DWORD, clientH:DWORD
    INVOKE ScaleDpi, PAGE_MARGIN
    mov tM, eax
    INVOKE ScaleDpi, 104
    mov tTop, eax
    INVOKE ScaleDpi, 20
    mov ecx, clientH
    sub ecx, eax
    mov tBottom, ecx
    ; left card = 58% of the width
    INVOKE ScaleDpi, 16
    mov ecx, clientW
    sub ecx, tM
    sub ecx, tM
    sub ecx, eax
    imul ecx, ecx, 58
    mov eax, ecx
    xor edx, edx
    mov ecx, 100
    div ecx
    add eax, tM
    mov tLeftX2, eax
    INVOKE ScaleDpi, 16
    add eax, tLeftX2
    mov tRightX1, eax
    mov eax, clientW
    sub eax, tM
    mov tRightX2, eax
    INVOKE ScaleDpi, 104 + 176
    mov tStreakBot, eax
    ret
TmGeometry ENDP

;---------------------------------------------------------------------
; TmText - text in a rectangle
;---------------------------------------------------------------------
TmText PROC hdc:DWORD, pText:DWORD, x1:DWORD, y1:DWORD, x2:DWORD, y2:DWORD,
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
TmText ENDP

;---------------------------------------------------------------------
; TmLayout - positions of the buttons on the timer card
;---------------------------------------------------------------------
TmLayout PROC USES ebx esi edi
    LOCAL rc:RECT, pad:DWORD, cx1:DWORD, cardW:DWORD, w:DWORD, h:DWORD,
          gap:DWORD, posY:DWORD

    INVOKE GetClientRect, hTimerPanel, ADDR rc
    INVOKE TmGeometry, rc.right, rc.bottom
    INVOKE ScaleDpi, 24
    mov pad, eax
    add eax, tM
    mov cx1, eax                    ; inner left of the timer card
    mov eax, tLeftX2
    sub eax, tM
    mov cardW, eax
    INVOKE ScaleDpi, 8
    mov gap, eax
    INVOKE ScaleDpi, 40
    mov h, eax

    ; course picker
    INVOKE ScaleDpi, 48
    add eax, tTop
    mov posY, eax
    INVOKE ScaleDpi, 280
    INVOKE MoveWindow, hTmCourse, cx1, posY, eax, h, TRUE

    ; three mode chips across the card
    INVOKE ScaleDpi, 104
    add eax, tTop
    mov posY, eax
    mov eax, cardW
    sub eax, pad
    sub eax, pad
    mov ecx, gap
    shl ecx, 1
    sub eax, ecx
    xor edx, edx
    mov ecx, 3
    div ecx
    mov w, eax
    mov ebx, cx1
    xor esi, esi
ChipLoop:
    INVOKE MoveWindow, hTmMode[esi*4], ebx, posY, w, h, TRUE
    add ebx, w
    add ebx, gap
    inc esi
    cmp esi, 3
    jb  ChipLoop

    ; [Start] [Reset] centred
    INVOKE ScaleDpi, 354
    add eax, tTop
    mov posY, eax
    INVOKE ScaleDpi, 44
    mov h, eax
    INVOKE ScaleDpi, 180 + 8 + 110
    mov ebx, cardW
    sub ebx, eax
    shr ebx, 1
    add ebx, tM                     ; left of the pair
    INVOKE ScaleDpi, 180
    INVOKE MoveWindow, hTmStart, ebx, posY, eax, h, TRUE
    INVOKE ScaleDpi, 180 + 8
    add ebx, eax
    INVOKE ScaleDpi, 110
    INVOKE MoveWindow, hTmReset, ebx, posY, eax, h, TRUE

    ; [Mini timer] [Demo speed] [Focus Guard] centred below
    INVOKE ScaleDpi, 410
    add eax, tTop
    mov posY, eax
    INVOKE ScaleDpi, 38
    mov h, eax
    INVOKE ScaleDpi, 128 + 8 + 128 + 8 + 128
    mov ebx, cardW
    sub ebx, eax
    shr ebx, 1
    add ebx, tM
    INVOKE ScaleDpi, 128
    mov w, eax
    INVOKE MoveWindow, hTmMini, ebx, posY, w, h, TRUE
    add ebx, w
    add ebx, gap
    INVOKE MoveWindow, hTmDemo, ebx, posY, w, h, TRUE
    add ebx, w
    add ebx, gap
    INVOKE MoveWindow, hTmGuard, ebx, posY, w, h, TRUE
    ret
TmLayout ENDP

;---------------------------------------------------------------------
; PaintTimerPanel - timer card, streak card, badge wall
;---------------------------------------------------------------------
PaintTimerPanel PROC USES ebx esi edi, hdc:DWORD, clientW:DWORD, clientH:DWORD
    LOCAL pad:DWORD, cx1:DWORD, cx2:DWORD, y1:DWORD, y2:DWORD,
          barW:DWORD, fillW:DWORD, streak:DWORD, sessions:DWORD,
          earned:DWORD, i:DWORD, col:DWORD, itemX:DWORD, itemY:DWORD,
          itemW:DWORD, itemH:DWORD, circle:DWORD, r:RECT

    INVOKE TmGeometry, clientW, clientH

    ; keep the course picker in step with the course list
    ; (courses may have been added or deleted since login)
    mov eax, tmCourse
    cmp eax, userData.courseCount
    jb  @F
    mov tmCourse, 0
@@: INVOKE GetWindowTextA, hTmCourse, ADDR tmBuf2, SIZEOF tmBuf2
    INVOKE TimerCourseName
    mov ebx, eax
    INVOKE Str_compare, ebx, ADDR tmBuf2
    je  @F
    INVOKE SetWindowTextA, hTmCourse, ebx
@@:
    INVOKE ScaleDpi, 24
    mov pad, eax
    mov eax, tM
    add eax, pad
    mov cx1, eax
    mov eax, tLeftX2
    sub eax, pad
    mov cx2, eax

    ;================ timer card ================
    INVOKE FillRound, hdc, tM, tTop, tLeftX2, tBottom, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder
    INVOKE ScaleDpi, 22
    add eax, tTop
    mov y1, eax
    INVOKE ScaleDpi, 44
    add eax, tTop
    mov y2, eax
    INVOKE TmText, hdc, ADDR szStudying, cx1, y1, cx2, y2, hFontSmall, curTheme.clrMuted, DT_LEFT

    ; big time
    INVOKE FormatTimeLeft, ADDR tmBuf
    INVOKE ScaleDpi, 156
    add eax, tTop
    mov y1, eax
    INVOKE ScaleDpi, 276
    add eax, tTop
    mov y2, eax
    mov ebx, curTheme.clrText
    cmp tmMode, TM_FOCUS
    je  @F
    mov ebx, CLR_SAFE_TX            ; breaks shown in green
@@: INVOKE TmText, hdc, ADDR tmBuf, cx1, y1, cx2, y2, hFontHuge, ebx, DT_CENTER

    ; progress bar
    INVOKE ScaleDpi, 286
    add eax, tTop
    mov y1, eax
    INVOKE ScaleDpi, 10
    add eax, y1
    mov y2, eax
    INVOKE ScaleDpi, 24
    mov esi, cx1
    add esi, eax                    ; bar left
    mov edi, cx2
    sub edi, eax                    ; bar right
    INVOKE FillRound, hdc, esi, y1, edi, y2, 5, curTheme.clrBg, curTheme.clrBorder
    mov eax, edi
    sub eax, esi
    mov barW, eax
    mov eax, tmTotal
    sub eax, tmRemaining            ; elapsed
    mul barW
    div tmTotal
    mov fillW, eax
    cmp eax, 10
    jb  NoFill
    lea ecx, [esi + eax]
    mov edx, curTheme.clrAccent
    cmp tmMode, TM_FOCUS
    je  @F
    mov edx, CLR_SAFE_BG
@@: INVOKE FillRound, hdc, esi, y1, ecx, y2, 5, edx, edx
NoFill:

    ; cycle / break text
    INVOKE ScaleDpi, 306
    add eax, tTop
    mov y1, eax
    INVOKE ScaleDpi, 332
    add eax, tTop
    mov y2, eax
    cmp tmMode, TM_FOCUS
    jne OnBreak
    mov eax, tmCycle
    inc eax
    INVOKE wsprintf, ADDR tmBuf, ADDR szFmtCycle, eax
    INVOKE TmText, hdc, ADDR tmBuf, cx1, y1, cx2, y2, hFontSmall, curTheme.clrMuted, DT_CENTER
    jmp CardDone
OnBreak:
    INVOKE TmText, hdc, ADDR szOnBreak, cx1, y1, cx2, y2, hFontSmall, CLR_SAFE_TX, DT_CENTER
CardDone:
    ; Focus Guard line: live count while running, else the last score
    cmp userData.focusGuardOff, 0
    jne GuardDone
    INVOKE ScaleDpi, 24
    add y1, eax
    add y2, eax
    cmp tmRunning, 0
    je  ShowLast
    cmp tmMode, TM_FOCUS
    jne GuardDone
    INVOKE wsprintf, ADDR tmBuf, ADDR szFmtGuardOn, fgCount
    mov edx, curTheme.clrSideActText
    cmp fgCount, 0
    je  @F
    mov edx, CLR_DANGER_TX
@@: INVOKE TmText, hdc, ADDR tmBuf, cx1, y1, cx2, y2, hFontSmall, edx, DT_CENTER
    jmp GuardDone
ShowLast:
    cmp userData.lastFocusScore, 0
    je  GuardDone
    INVOKE wsprintf, ADDR tmBuf, ADDR szFmtLastScore, userData.lastFocusScore
    INVOKE TmText, hdc, ADDR tmBuf, cx1, y1, cx2, y2, hFontSmall, curTheme.clrMuted, DT_CENTER
GuardDone:

    ;================ streak card ================
    INVOKE FillRound, hdc, tRightX1, tTop, tRightX2, tStreakBot, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder
    mov ebx, tRightX1
    add ebx, pad
    mov esi, tRightX2
    sub esi, pad
    INVOKE ScaleDpi, 18
    add eax, tTop
    mov y1, eax
    INVOKE ScaleDpi, 40
    add eax, tTop
    mov y2, eax
    INVOKE TmText, hdc, ADDR szStreakT, ebx, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_LEFT
    ; big "4-day streak" with a star
    INVOKE CurrentStreak
    mov streak, eax
    INVOKE ScaleDpi, 42
    add eax, tTop
    mov y1, eax
    INVOKE ScaleDpi, 84
    add eax, tTop
    mov y2, eax
    INVOKE ScaleDpi, 34
    lea edi, [ebx + eax]
    mov edx, curTheme.clrBorder
    cmp streak, 0
    je  @F
    mov edx, CLR_WARN_TX
@@: mov r.left, ebx
    mov r.right, edi
    mov eax, y1
    mov r.top, eax
    mov eax, y2
    mov r.bottom, eax
    INVOKE DrawGlyph, hdc, GLYPH_STAR, ADDR r, hFontIconLg, edx, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    cmp streak, 0
    je  NoStreak
    INVOKE wsprintf, ADDR tmBuf, ADDR szFmtStreak, streak
    INVOKE TmText, hdc, ADDR tmBuf, edi, y1, esi, y2, hFontTitle, curTheme.clrText, DT_LEFT
    jmp StreakLines
NoStreak:
    INVOKE TmText, hdc, ADDR szNoStreak, edi, y1, esi, y2, hFontTitle, curTheme.clrMuted, DT_LEFT
StreakLines:
    ; best / today / total
    INVOKE wsprintf, ADDR tmBuf, ADDR szFmtBest, userData.streakBest
    INVOKE ScaleDpi, 92
    add eax, tTop
    mov y1, eax
    INVOKE ScaleDpi, 114
    add eax, tTop
    mov y2, eax
    INVOKE TmText, hdc, ADDR tmBuf, ebx, y1, esi, y2, hFontSmall, curTheme.clrText, DT_LEFT
    INVOKE MinutesToday, -1
    mov edi, eax
    xor edx, edx
    mov ecx, POMODORO_MIN
    div ecx
    mov sessions, eax
    INVOKE FormatTimeHM, edi, ADDR tmBuf2
    INVOKE wsprintf, ADDR tmBuf, ADDR szFmtToday, sessions, ADDR tmBuf2
    INVOKE ScaleDpi, 116
    add eax, tTop
    mov y1, eax
    INVOKE ScaleDpi, 138
    add eax, tTop
    mov y2, eax
    INVOKE TmText, hdc, ADDR tmBuf, ebx, y1, esi, y2, hFontSmall, curTheme.clrText, DT_LEFT
    INVOKE FormatTimeHM, userData.totalMinutes, ADDR tmBuf2
    INVOKE wsprintf, ADDR tmBuf, ADDR szFmtTotal, ADDR tmBuf2, userData.pomodoros
    INVOKE ScaleDpi, 140
    add eax, tTop
    mov y1, eax
    INVOKE ScaleDpi, 162
    add eax, tTop
    mov y2, eax
    INVOKE TmText, hdc, ADDR tmBuf, ebx, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_LEFT

    ;================ badge wall ================
    INVOKE ScaleDpi, 16
    add eax, tStreakBot
    mov y1, eax
    INVOKE FillRound, hdc, tRightX1, y1, tRightX2, tBottom, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder
    ; count earned badges (popcount of the bitmask, one bit at a time)
    mov earned, 0
    mov eax, userData.badges
    mov ecx, BADGE_COUNT
CountBits:
    shr eax, 1
    adc earned, 0                   ; carry = the bit shifted out
    loop CountBits
    INVOKE ScaleDpi, 16
    add y1, eax
    INVOKE ScaleDpi, 24
    add eax, y1
    mov y2, eax
    INVOKE TmText, hdc, ADDR szBadgesT, ebx, y1, esi, y2, hFontBodyBold, curTheme.clrText, DT_LEFT
    INVOKE wsprintf, ADDR tmBuf, ADDR szFmtBadges, earned
    INVOKE TmText, hdc, ADDR tmBuf, ebx, y1, esi, y2, hFontSmall, curTheme.clrMuted, DT_RIGHT

    ; 2 columns x 4 rows
    INVOKE ScaleDpi, 8
    add eax, y2
    mov itemY, eax
    mov eax, tBottom
    sub eax, itemY
    sub eax, pad
    shr eax, 2
    mov itemH, eax
    mov eax, esi
    sub eax, ebx
    shr eax, 1
    mov itemW, eax
    INVOKE ScaleDpi, 30
    mov circle, eax
    mov i, 0
BadgeLoop:
    mov eax, i
    cmp eax, BADGE_COUNT
    jae BadgesDone
    ; position: column = i AND 1, row = i / 2
    mov ecx, eax
    and ecx, 1
    mov col, ecx
    mov eax, itemW
    mul col
    add eax, ebx
    mov itemX, eax
    mov eax, i
    shr eax, 1
    mul itemH
    add eax, itemY
    mov y1, eax
    add eax, itemH
    mov y2, eax
    ; circle centred vertically
    mov eax, y1
    add eax, y2
    sub eax, circle
    shr eax, 1
    mov r.top, eax
    add eax, circle
    mov r.bottom, eax
    mov eax, itemX
    mov r.left, eax
    add eax, circle
    mov r.right, eax
    mov ecx, i
    bt  userData.badges, ecx        ; is badge i earned?
    jnc Locked
    INVOKE FillRound, hdc, r.left, r.top, r.right, r.bottom, 15,
           curTheme.clrSideActive, curTheme.clrSideActive
    INVOKE DrawGlyph, hdc, GLYPH_STAR, ADDR r, hFontIcon, curTheme.clrSideActText,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    mov edi, curTheme.clrText
    jmp BadgeName
Locked:
    INVOKE FillRound, hdc, r.left, r.top, r.right, r.bottom, 15,
           curTheme.clrBg, curTheme.clrBg
    INVOKE DrawGlyph, hdc, GLYPH_LOCK, ADDR r, hFontIcon, curTheme.clrMuted,
           DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    mov edi, curTheme.clrMuted
BadgeName:
    INVOKE ScaleDpi, 10
    add eax, r.right
    mov ecx, itemX
    add ecx, itemW
    mov edx, i
    INVOKE TmText, hdc, badgeNames[edx*4], eax, y1, ecx, y2, hFontSmall, edi, DT_LEFT
    inc i
    jmp BadgeLoop
BadgesDone:
    ret
PaintTimerPanel ENDP

;---------------------------------------------------------------------
; FormatTimeHM - 75 -> "1h 15m",  50 -> "50m"
;---------------------------------------------------------------------
FormatTimeHM PROC USES ecx edx, minutes:DWORD, pBuf:DWORD
    mov eax, minutes
    xor edx, edx
    mov ecx, 60
    div ecx
    cmp eax, 0
    jne @F
    INVOKE wsprintf, pBuf, ADDR szHM2, edx
    ret
@@: INVOKE wsprintf, pBuf, ADDR szHM1, eax, edx
    ret
FormatTimeHM ENDP

;---------------------------------------------------------------------
; TimerPanelMsg - messages for the Timer screen
;---------------------------------------------------------------------
TimerPanelMsg PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    cmp uMsg, WM_SIZE
    je  OnSize
    cmp uMsg, WM_DRAWITEM
    je  OnDrawItem
    cmp uMsg, WM_COMMAND
    je  OnCommand
    cmp uMsg, WM_TIMER
    je  OnTimer
    jmp NotHandled

OnSize:
    INVOKE TmLayout
    jmp HandledZero

OnDrawItem:
    INVOKE DrawPastelButton, lParam, curTheme.clrCard
    mov eax, TRUE
    jmp Handled

OnTimer:
    cmp wParam, TIMER_POMODORO
    jne HandledZero
    INVOKE TimerTick
    jmp HandledZero

OnCommand:
    mov eax, wParam
    and eax, 0FFFFh
    cmp eax, IDC_TM_START
    jne @F
    INVOKE TimerStartPause
    jmp HandledZero
@@: cmp eax, IDC_TM_RESET
    jne @F
    INVOKE TimerReset
    jmp HandledZero
@@: cmp eax, IDC_TM_MINI
    jne @F
    INVOKE ToggleMiniTimer
    jmp HandledZero
@@: cmp eax, IDC_TM_DEMO
    jne @F
    xor tmDemo, 1
    INVOKE SetChipSelected, hTmDemo, tmDemo
    jmp HandledZero
@@: cmp eax, IDC_TM_GUARD
    jne @F
    xor userData.focusGuardOff, 1
    mov eax, userData.focusGuardOff
    xor eax, 1
    INVOKE SetChipSelected, hTmGuard, eax
    mov edx, OFFSET szLogGuardOn
    cmp userData.focusGuardOff, 0
    je  LogGuard
    mov edx, OFFSET szLogGuardOff
LogGuard:
    INVOKE LogEvent, edx
    INVOKE SaveWithStatus
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp HandledZero
@@: cmp eax, IDC_TM_COURSE
    jne @F
    INVOKE PickTimerCourse, hWnd
    jmp HandledZero
@@: cmp eax, IDC_TM_MODE
    jb  HandledZero
    cmp eax, IDC_TM_MODE + 3
    jae HandledZero
    sub eax, IDC_TM_MODE
    INVOKE SetTimerMode, eax
    jmp HandledZero

HandledZero:
    xor eax, eax
Handled:
    mov ecx, 1
    ret
NotHandled:
    xor ecx, ecx
    ret
TimerPanelMsg ENDP

END
