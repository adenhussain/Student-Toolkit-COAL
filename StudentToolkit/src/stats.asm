;=====================================================================
; stats.asm  -  study log, streaks and badges
;
; Study log: one entry per (day, course) with the minutes studied.
;   50 entries; when full, the oldest entry is dropped (rep movsb).
;
; Streak: days in a row with at least one finished Pomodoro.
;   studied yesterday  -> streak + 1
;   studied today      -> unchanged
;   otherwise          -> back to 1
;
; Badges: one bit each in userData.badges (bit operations: or, test).
;   bit 0  First step       first session
;   bit 1  3-day streak
;   bit 2  Week warrior     7-day streak
;   bit 3  10 hours club    600 minutes in total
;   bit 4  50 sessions
;   bit 5  Night owl        a session finished after 10 PM
;   bit 6  Early bird       a session finished before 8 AM
;   bit 7  Comeback         a new streak after a broken one
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

.data
szBadge0    BYTE "First step", 0
szBadge1    BYTE "3-day streak", 0
szBadge2    BYTE "Week warrior", 0
szBadge3    BYTE "10 hours club", 0
szBadge4    BYTE "50 sessions", 0
szBadge5    BYTE "Night owl", 0
szBadge6    BYTE "Early bird", 0
szBadge7    BYTE "Comeback", 0
badgeNames  DWORD OFFSET szBadge0, OFFSET szBadge1, OFFSET szBadge2, OFFSET szBadge3,
                  OFFSET szBadge4, OFFSET szBadge5, OFFSET szBadge6, OFFSET szBadge7
comebackNow DWORD 0             ; set by UpdateStreak for CheckBadges

.code
;---------------------------------------------------------------------
; LogStudy - adds minutes for a course to today's log entry
;---------------------------------------------------------------------
LogStudy PROC USES ebx ecx esi edi, course:DWORD, minutes:DWORD
    LOCAL today:DWORD

    INVOKE TodayDay
    mov today, eax
    mov eax, minutes
    add userData.totalMinutes, eax

    ; an entry for today and this course already?
    mov esi, OFFSET userData.studyLog
    mov ecx, userData.logCount
    jecxz Append
FindLoop:
    mov eax, (STUDYLOG PTR [esi]).logDay
    cmp eax, today
    jne @F
    mov eax, (STUDYLOG PTR [esi]).logCourse
    cmp eax, course
    jne @F
    mov eax, minutes
    add (STUDYLOG PTR [esi]).logMinutes, eax
    ret
@@: add esi, SIZEOF STUDYLOG
    loop FindLoop

Append:
    cmp userData.logCount, MAX_STUDYLOG
    jb  HaveRoom
    ; full: drop the oldest entry, move the rest up
    mov edi, OFFSET userData.studyLog
    lea esi, [edi + SIZEOF STUDYLOG]
    mov ecx, (MAX_STUDYLOG - 1) * SIZEOF STUDYLOG
    cld
    rep movsb
    dec userData.logCount
HaveRoom:
    mov eax, userData.logCount
    imul eax, eax, SIZEOF STUDYLOG
    lea esi, userData.studyLog[eax]
    mov eax, today
    mov (STUDYLOG PTR [esi]).logDay, eax
    mov eax, course
    mov (STUDYLOG PTR [esi]).logCourse, eax
    mov eax, minutes
    mov (STUDYLOG PTR [esi]).logMinutes, eax
    inc userData.logCount
    ret
LogStudy ENDP

;---------------------------------------------------------------------
; MinutesToday - minutes studied today for a course (-1 = all courses)
;---------------------------------------------------------------------
MinutesToday PROC USES ebx ecx esi, course:DWORD
    INVOKE TodayDay
    mov ebx, eax
    xor eax, eax
    mov esi, OFFSET userData.studyLog
    mov ecx, userData.logCount
    jecxz Done
SumLoop:
    cmp (STUDYLOG PTR [esi]).logDay, ebx
    jne Next
    cmp course, -1
    je  AddMinutes
    mov edx, (STUDYLOG PTR [esi]).logCourse
    cmp edx, course
    jne Next
AddMinutes:
    add eax, (STUDYLOG PTR [esi]).logMinutes
Next:
    add esi, SIZEOF STUDYLOG
    loop SumLoop
Done:
    ret
MinutesToday ENDP

;---------------------------------------------------------------------
; CurrentStreak - the streak still counts if the last study day was
; today or yesterday; otherwise it is broken (0).
;---------------------------------------------------------------------
CurrentStreak PROC USES ecx
    INVOKE TodayDay
    dec eax                         ; yesterday
    mov ecx, eax
    xor eax, eax
    cmp userData.lastStudyDay, ecx
    jl  @F
    mov eax, userData.streakCurrent
@@: ret
CurrentStreak ENDP

;---------------------------------------------------------------------
; UpdateStreak - called after every finished focus session
;---------------------------------------------------------------------
UpdateStreak PROC USES ecx
    mov comebackNow, 0
    inc userData.pomodoros
    INVOKE TodayDay
    cmp userData.streakCurrent, 0
    je  NewStreak
    cmp userData.lastStudyDay, eax
    je  Done                        ; already studied today
    dec eax
    cmp userData.lastStudyDay, eax
    jne Broken
    inc userData.streakCurrent      ; studied yesterday too
    inc eax
    jmp Done
Broken:
    inc eax
    cmp userData.streakCurrent, 2
    jb  NewStreak
    mov comebackNow, 1              ; a real streak was broken: comeback
NewStreak:
    mov userData.streakCurrent, 1
Done:
    mov userData.lastStudyDay, eax
    mov ecx, userData.streakCurrent
    cmp ecx, userData.streakBest
    jbe @F
    mov userData.streakBest, ecx
@@: ret
UpdateStreak ENDP

;---------------------------------------------------------------------
; CheckBadges - turns on every badge whose rule is now met
; Returns: EAX = bits of the badges that are NEW this time
;---------------------------------------------------------------------
CheckBadges PROC USES ebx ecx edx
    LOCAL sysTime:SYSTEMTIME

    xor ebx, ebx                    ; ebx = badges earned by the rules
    cmp userData.pomodoros, 1
    jb  @F
    or  ebx, 1                      ; bit 0: first step
@@: cmp userData.streakCurrent, 3
    jb  @F
    or  ebx, 2                      ; bit 1: 3-day streak
@@: cmp userData.streakCurrent, 7
    jb  @F
    or  ebx, 4                      ; bit 2: week warrior
@@: cmp userData.totalMinutes, 600
    jb  @F
    or  ebx, 8                      ; bit 3: 10 hours club
@@: cmp userData.pomodoros, 50
    jb  @F
    or  ebx, 10h                    ; bit 4: 50 sessions
@@: INVOKE GetLocalTime, ADDR sysTime
    movzx eax, sysTime.wHour
    cmp eax, 22
    jae Night
    cmp eax, 4
    jb  Night
    cmp eax, 8
    jae @F
    or  ebx, 40h                    ; bit 6: early bird (4 - 8 AM)
    jmp @F
Night:
    or  ebx, 20h                    ; bit 5: night owl (10 PM - 4 AM)
@@: cmp comebackNow, 0
    je  @F
    or  ebx, 80h                    ; bit 7: comeback
@@:
    ; new = earned AND NOT already-owned
    mov eax, userData.badges
    not eax
    and eax, ebx
    or  userData.badges, ebx
    ret
CheckBadges ENDP

END
