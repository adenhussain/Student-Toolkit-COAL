;=====================================================================
; grade_calc.asm  -  all the grade maths (integers only, values x100)
;
;   CGPA        = sum(GPA x credits) / sum(credits)
;   required    = ceil( (target x allCredits - pastPoints) / semCredits )
;   new CGPA    = (pastPoints + semesterPoints) / allCredits
;
; Example from our proposal: 30 credits at 3.00, target 3.20,
; 15 credits this semester:
;   (320 x 45 - 300 x 30) / 15 = (14400 - 9000) / 15 = 360 -> 3.60
;
; Marks predictor (course out of 100 marks, FAST grading table):
;   marks still needed = grade's minimum % - marks so far
;
; Auto-solve (greedy): start every course at D, then keep raising the
; one grade that buys the most grade points per unit of effort,
; until the semester is good enough to reach the target CGPA.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

.data
solveGrade  DWORD MAX_COURSES DUP(0)    ; grade index chosen per course
solveGpa    DWORD 0                     ; semester GPA of that choice

szZoneSecured   BYTE "Already secured", 0
szZoneComfort   BYTE "Comfortable", 0
szZoneStretch   BYTE "A stretch", 0
szZoneHard      BYTE "Hard but possible", 0
szZoneImpossible BYTE "Not possible this semester", 0

.code
;---------------------------------------------------------------------
; CalcPast - past semesters.  Returns: EAX = points, ECX = credits
; (points = GPA x100 times credits)
;---------------------------------------------------------------------
CalcPast PROC USES ebx edx esi
    xor ebx, ebx                    ; points
    xor ecx, ecx                    ; credits
    mov esi, OFFSET userData.semesters
    mov edx, userData.semCount
    cmp edx, 0
    je  Done
SemLoop:
    mov eax, (SEMESTER PTR [esi]).semGpa
    imul eax, (SEMESTER PTR [esi]).semCredits
    add ebx, eax
    add ecx, (SEMESTER PTR [esi]).semCredits
    add esi, SIZEOF SEMESTER
    dec edx
    jnz SemLoop
Done:
    mov eax, ebx
    ret
CalcPast ENDP

;---------------------------------------------------------------------
; CalcSemester - this semester with the grades on the sliders
; Returns: EAX = points, ECX = credits
;---------------------------------------------------------------------
CalcSemester PROC USES ebx edx esi edi
    xor ebx, ebx
    xor ecx, ecx
    mov esi, OFFSET userData.courses
    mov edi, userData.courseCount
    cmp edi, 0
    je  Done
CourseLoop:
    mov edx, (COURSE PTR [esi]).sliderGrade
    mov eax, gradeGP[edx*4]         ; grade points of the chosen grade
    imul eax, (COURSE PTR [esi]).credits
    add ebx, eax
    add ecx, (COURSE PTR [esi]).credits
    add esi, SIZEOF COURSE
    dec edi
    jnz CourseLoop
Done:
    mov eax, ebx
    ret
CalcSemester ENDP

;---------------------------------------------------------------------
; DivideRounded (helper) - EAX = (EAX + ECX/2) / ECX
;---------------------------------------------------------------------
DivideRounded PROC USES ebx edx
    mov ebx, ecx
    shr ebx, 1
    add eax, ebx
    xor edx, edx
    div ecx
    ret
DivideRounded ENDP

;---------------------------------------------------------------------
; CurrentCgpa - Returns: EAX = CGPA x100, or -1 if no past semesters
;---------------------------------------------------------------------
CurrentCgpa PROC USES ecx
    INVOKE CalcPast
    cmp ecx, 0
    jne @F
    mov eax, -1
    ret
@@: call DivideRounded
    ret
CurrentCgpa ENDP

;---------------------------------------------------------------------
; NewCgpa - CGPA after this semester with the slider grades
; Returns: EAX = CGPA x100, or -1 if there are no credits at all
;---------------------------------------------------------------------
NewCgpa PROC USES ebx ecx edx
    INVOKE CalcPast
    mov ebx, eax
    mov edx, ecx
    INVOKE CalcSemester
    add eax, ebx
    add ecx, edx
    cmp ecx, 0
    jne @F
    mov eax, -1
    ret
@@: call DivideRounded
    ret
NewCgpa ENDP

;---------------------------------------------------------------------
; RequiredGpa - GPA needed this semester to reach the target CGPA
; Returns: EAX = GPA x100 (rounded up; 0 = already reached)
;          EDX = 0 ok, 1 no target set, 2 no courses this semester
;---------------------------------------------------------------------
RequiredGpa PROC USES ebx ecx esi edi
    mov edx, 1
    cmp userData.targetCgpa, 0
    je  Fail
    INVOKE CalcSemester
    mov edi, ecx                    ; semester credits
    mov edx, 2
    cmp edi, 0
    je  Fail
    INVOKE CalcPast
    mov ebx, eax                    ; past points
    mov esi, ecx                    ; past credits

    ; needed points = target x (past + semester credits) - past points
    lea eax, [esi + edi]
    imul eax, userData.targetCgpa
    sub eax, ebx
    jg  @F
    xor eax, eax                    ; target already reached
    xor edx, edx
    ret
@@: ; required = ceil(needed / semester credits)
    add eax, edi
    dec eax
    xor edx, edx
    div edi
    xor edx, edx
    ret
Fail:
    xor eax, eax
    ret
RequiredGpa ENDP

;---------------------------------------------------------------------
; GpaZone - colours and words for a required GPA
; Returns: EAX = background, ECX = text colour, EDX = label
;---------------------------------------------------------------------
GpaZone PROC value:DWORD
    mov eax, value
    cmp eax, 0
    je  Secured
    cmp eax, 300
    jbe Comfort
    cmp eax, 367
    jbe Stretch
    cmp eax, 400
    jbe Hard
    mov eax, CLR_DANGER_BG
    mov ecx, CLR_DANGER_TX
    mov edx, OFFSET szZoneImpossible
    ret
Secured:
    mov eax, CLR_SAFE_BG
    mov ecx, CLR_SAFE_TX
    mov edx, OFFSET szZoneSecured
    ret
Comfort:
    mov eax, CLR_SAFE_BG
    mov ecx, CLR_SAFE_TX
    mov edx, OFFSET szZoneComfort
    ret
Stretch:
    mov eax, CLR_WARN_BG
    mov ecx, CLR_WARN_TX
    mov edx, OFFSET szZoneStretch
    ret
Hard:
    mov eax, CLR_DANGER_BG
    mov ecx, CLR_DANGER_TX
    mov edx, OFFSET szZoneHard
    ret
GpaZone ENDP

;---------------------------------------------------------------------
; MarksNeeded - marks still needed in this course for grade 'grade'
; (the course is out of 100: marks so far + the remaining marks)
; Returns: EAX = marks needed x10
;          ECX = marks still available x10
;          EDX = 0 possible, 1 already secured, 2 not reachable,
;                3 no marks entered for this course
;---------------------------------------------------------------------
MarksNeeded PROC USES ebx esi, pCourse:DWORD, grade:DWORD
    mov esi, pCourse
    mov edx, 3
    cmp (COURSE PTR [esi]).marksTotal, 0
    je  Done

    mov ecx, 1000
    sub ecx, (COURSE PTR [esi]).marksTotal  ; marks still to come (x10)
    mov ebx, grade
    mov eax, gradeMinPct[ebx*4]
    imul eax, eax, 10                       ; minimum % as x10 marks
    sub eax, (COURSE PTR [esi]).marksObt
    jg  @F
    xor eax, eax
    mov edx, 1                              ; already has enough
    ret
@@: mov edx, 2
    cmp eax, ecx
    ja  Done                                ; more than is left
    xor edx, edx
Done:
    ret
MarksNeeded ENDP

;---------------------------------------------------------------------
; SolveGrades - greedy "easiest path" to the target CGPA
; Fills solveGrade[] and solveGpa.
; Returns: EAX = 1 found, 0 not possible (or nothing to solve)
;
; Cost of raising a course one grade = difficulty + (6 - preparation)
; (hard and unprepared courses are "expensive"). Each round we raise
; the course with the best  gain x 100 / cost , where gain is the
; extra grade points x credits. Grades the marks can no longer
; reach are skipped.
;---------------------------------------------------------------------
SolveGrades PROC USES ebx ecx edx esi edi
    LOCAL needPoints:DWORD, semCredits:DWORD, points:DWORD,
          best:DWORD, bestScore:DWORD, i:DWORD

    INVOKE RequiredGpa
    cmp edx, 0
    jne NotPossible                 ; no target or no courses
    cmp eax, 400
    ja  NotPossible
    mov ebx, eax                    ; required GPA
    INVOKE CalcSemester
    mov semCredits, ecx
    imul ebx, ecx
    mov needPoints, ebx

    ; ---- start: every course at D, or higher if already secured ----
    mov esi, OFFSET userData.courses
    mov i, 0
StartLoop:
    mov eax, i
    cmp eax, userData.courseCount
    jae StartDone
    mov ebx, GRADE_APLUS            ; find the best grade already secured
FindSecured:
    cmp ebx, GRADE_D
    jae UseD
    INVOKE MarksNeeded, esi, ebx
    cmp edx, 1
    je  StartAt
    inc ebx
    jmp FindSecured
UseD:
    mov ebx, GRADE_D
StartAt:
    mov eax, i
    mov solveGrade[eax*4], ebx
    add esi, SIZEOF COURSE
    inc i
    jmp StartLoop
StartDone:

    ; ---- raise one grade at a time ----
RoundLoop:
    ; points of the current choice
    xor ebx, ebx
    mov esi, OFFSET userData.courses
    xor ecx, ecx
SumLoop:
    cmp ecx, userData.courseCount
    jae SumDone
    mov edx, solveGrade[ecx*4]
    mov eax, gradeGP[edx*4]
    imul eax, (COURSE PTR [esi]).credits
    add ebx, eax
    add esi, SIZEOF COURSE
    inc ecx
    jmp SumLoop
SumDone:
    mov points, ebx
    cmp ebx, needPoints
    jae Found

    ; best course to raise
    mov best, -1
    mov bestScore, 0
    mov esi, OFFSET userData.courses
    mov i, 0
PickLoop:
    mov eax, i
    cmp eax, userData.courseCount
    jae PickDone
    mov edx, solveGrade[eax*4]
    cmp edx, GRADE_APLUS
    je  NextCourse                  ; already the top grade
    lea edi, [edx - 1]              ; next grade up (smaller index)
    mov eax, gradeGP[edi*4]
    sub eax, gradeGP[edx*4]         ; extra grade points
    jle NextCourse                  ; A -> A+ gives nothing
    imul eax, (COURSE PTR [esi]).credits
    imul eax, eax, 100
    mov ebx, eax                    ; gain x 100
    INVOKE MarksNeeded, esi, edi
    cmp edx, 2
    je  NextCourse                  ; marks can't reach it any more
    mov ecx, 6
    sub ecx, (COURSE PTR [esi]).preparation
    add ecx, (COURSE PTR [esi]).difficulty  ; cost 2 .. 10
    mov eax, ebx
    xor edx, edx
    div ecx                         ; score = gain x 100 / cost
    cmp eax, bestScore
    jbe NextCourse
    mov bestScore, eax
    mov eax, i
    mov best, eax
NextCourse:
    add esi, SIZEOF COURSE
    inc i
    jmp PickLoop
PickDone:
    cmp best, -1
    je  NotPossible                 ; nothing left to raise
    mov eax, best
    dec solveGrade[eax*4]           ; one grade higher
    jmp RoundLoop

Found:
    mov eax, points
    mov ecx, semCredits
    call DivideRounded
    mov solveGpa, eax
    mov eax, 1
    ret
NotPossible:
    mov solveGpa, 0
    xor eax, eax
    ret
SolveGrades ENDP

END
