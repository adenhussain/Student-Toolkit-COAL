;=====================================================================
; dates.asm  -  calendar dates as simple day numbers
;
; A date is stored as ONE number: days since 1 January 2000.
;   1 Jan 2000 -> 0,   2 Jan 2000 -> 1,   7 Nov 2026 -> 9807
; Then "days left" is just  dueDay - today  (one subtraction).
;
; Converting uses a days-per-month table and a leap-year test:
;   leap year = year divisible by 4   (correct for 2000 - 2099)
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

IsLeapYear  PROTO :DWORD
DaysInMonth PROTO :DWORD, :DWORD

BASE_YEAR   = 2000

.data
monthDays   DWORD 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
monthNames  BYTE "Jan",0, "Feb",0, "Mar",0, "Apr",0, "May",0, "Jun",0
            BYTE "Jul",0, "Aug",0, "Sep",0, "Oct",0, "Nov",0, "Dec",0
dayNames    BYTE "Sun",0, "Mon",0, "Tue",0, "Wed",0, "Thu",0, "Fri",0, "Sat",0
szFmtShort  BYTE "%s %d %s", 0          ; "Fri 14 Nov"
szFmtInput  BYTE "%d/%d/%d", 0          ; "14/11/2026"

.code
;---------------------------------------------------------------------
; IsLeapYear - Returns: EAX = 1 if leap year, else 0
;---------------------------------------------------------------------
IsLeapYear PROC year:DWORD
    mov eax, year
    and eax, 3                      ; year mod 4 (lowest two bits)
    jnz NotLeap
    mov eax, 1
    ret
NotLeap:
    xor eax, eax
    ret
IsLeapYear ENDP

;---------------------------------------------------------------------
; DaysInMonth - month 1..12.  Returns: EAX
;---------------------------------------------------------------------
DaysInMonth PROC USES ecx, year:DWORD, month:DWORD
    mov ecx, month
    mov eax, monthDays[ecx*4 - 4]
    cmp ecx, 2
    jne Done
    INVOKE IsLeapYear, year
    add eax, 28                     ; February: 28 + leap (0 or 1)
Done:
    ret
DaysInMonth ENDP

;---------------------------------------------------------------------
; DateToDay - (year, month, day) -> day number
;---------------------------------------------------------------------
DateToDay PROC USES ebx ecx edx, year:DWORD, month:DWORD, day:DWORD
    xor ebx, ebx                    ; total days

    ; whole years before 'year'
    mov ecx, BASE_YEAR
YearLoop:
    cmp ecx, year
    jae YearsDone
    INVOKE IsLeapYear, ecx
    add eax, 365
    add ebx, eax
    inc ecx
    jmp YearLoop
YearsDone:

    ; whole months before 'month'
    mov ecx, 1
MonthLoop:
    cmp ecx, month
    jae MonthsDone
    INVOKE DaysInMonth, year, ecx
    add ebx, eax
    inc ecx
    jmp MonthLoop
MonthsDone:

    mov eax, day
    dec eax
    add eax, ebx
    ret
DateToDay ENDP

;---------------------------------------------------------------------
; DayToDate - day number -> EAX = year, ECX = month, EDX = day
;---------------------------------------------------------------------
DayToDate PROC USES ebx esi, dayNum:DWORD
    mov ebx, dayNum                 ; days still to place
    mov esi, BASE_YEAR
YearLoop:
    INVOKE IsLeapYear, esi
    add eax, 365                    ; length of this year
    cmp ebx, eax
    jb  FoundYear
    sub ebx, eax
    inc esi
    jmp YearLoop
FoundYear:
    mov ecx, 1
MonthLoop:
    INVOKE DaysInMonth, esi, ecx
    cmp ebx, eax
    jb  FoundMonth
    sub ebx, eax
    inc ecx
    jmp MonthLoop
FoundMonth:
    mov eax, esi
    lea edx, [ebx + 1]
    ret
DayToDate ENDP

;---------------------------------------------------------------------
; TodayDay - today's date from the Windows clock.  Returns: EAX
;---------------------------------------------------------------------
TodayDay PROC USES ecx edx
    LOCAL sysTime:SYSTEMTIME

    INVOKE GetLocalTime, ADDR sysTime
    movzx eax, sysTime.wYear
    movzx ecx, sysTime.wMonth
    movzx edx, sysTime.wDay
    INVOKE DateToDay, eax, ecx, edx
    ret
TodayDay ENDP

;---------------------------------------------------------------------
; FormatDateShort - "Fri 14 Nov" into pBuf
; 1 Jan 2000 was a Saturday, so weekday = (day + 6) mod 7  (0 = Sun)
;---------------------------------------------------------------------
FormatDateShort PROC USES ebx ecx edx esi edi, dayNum:DWORD, pBuf:DWORD
    mov eax, dayNum
    add eax, 6
    xor edx, edx
    mov ecx, 7
    div ecx
    lea esi, dayNames[edx*4]        ; weekday name

    INVOKE DayToDate, dayNum        ; eax = year, ecx = month, edx = day
    lea edi, monthNames[ecx*4 - 4]  ; month name
    INVOKE wsprintf, pBuf, ADDR szFmtShort, esi, edx, edi
    ret
FormatDateShort ENDP

;---------------------------------------------------------------------
; FormatDateInput - "14/11/2026" into pBuf (used to fill text fields)
;---------------------------------------------------------------------
FormatDateInput PROC USES ecx edx, dayNum:DWORD, pBuf:DWORD
    INVOKE DayToDate, dayNum
    INVOKE wsprintf, pBuf, ADDR szFmtInput, edx, ecx, eax
    ret
FormatDateInput ENDP

;---------------------------------------------------------------------
; ParseDate - reads "14/11", "14/11/2026", "14-11" or "14.11.2026"
; Without a year: this year, or next year if that date is more than
; 60 days in the past (a January deadline typed in December).
; Returns: EAX = day number, or -1 if it is not a valid date
;---------------------------------------------------------------------
ParseDate PROC USES ebx ecx edx esi edi, pStr:DWORD
    LOCAL parts[3]:DWORD, count:DWORD, digits:DWORD, sysTime:SYSTEMTIME

    mov parts[0], 0
    mov parts[4], 0
    mov parts[8], 0
    mov count, 0                    ; index of the part being read
    mov digits, 0
    mov esi, pStr
NextChar:
    movzx eax, BYTE PTR [esi]
    cmp eax, 0
    je  EndOfText
    cmp eax, '/'
    je  Separator
    cmp eax, '-'
    je  Separator
    cmp eax, '.'
    je  Separator
    cmp eax, '0'
    jb  Invalid
    cmp eax, '9'
    ja  Invalid
    sub eax, '0'
    mov ebx, count
    mov ecx, parts[ebx*4]
    imul ecx, ecx, 10               ; part = part * 10 + digit
    add ecx, eax
    mov parts[ebx*4], ecx
    inc digits
    cmp digits, 4
    ja  Invalid
    jmp Advance
Separator:
    cmp digits, 0
    je  Invalid                     ; "/" with no number before it
    inc count
    cmp count, 2
    ja  Invalid                     ; more than 3 parts
    mov digits, 0
Advance:
    inc esi
    jmp NextChar

EndOfText:
    cmp digits, 0
    je  Invalid
    cmp count, 1
    jb  Invalid                     ; need at least day and month

    ; month 1..12, day 1..days in that month
    mov ecx, parts[4]
    cmp ecx, 1
    jb  Invalid
    cmp ecx, 12
    ja  Invalid

    cmp count, 2
    je  HaveYear
    ; no year typed: this year (or next, see above)
    INVOKE GetLocalTime, ADDR sysTime
    movzx edi, sysTime.wYear
    jmp CheckDay
HaveYear:
    mov edi, parts[8]
    cmp edi, 100
    jae @F
    add edi, 2000                   ; "26" -> 2026
@@: cmp edi, BASE_YEAR
    jb  Invalid
    cmp edi, 2099
    ja  Invalid

CheckDay:
    INVOKE DaysInMonth, edi, parts[4]
    mov ecx, parts[0]
    cmp ecx, 1
    jb  Invalid
    cmp ecx, eax
    ja  Invalid

    INVOKE DateToDay, edi, parts[4], parts[0]
    cmp count, 2
    je  Done                        ; year was typed: use it as is
    mov ebx, eax
    INVOKE TodayDay
    sub eax, 60
    cmp ebx, eax
    jge KeepYear
    inc edi                         ; long past -> next year
    INVOKE DaysInMonth, edi, parts[4]
    cmp parts[0], eax
    ja  Invalid                     ; 29 Feb in a non-leap year
    INVOKE DateToDay, edi, parts[4], parts[0]
    ret
KeepYear:
    mov eax, ebx
Done:
    ret
Invalid:
    mov eax, -1
    ret
ParseDate ENDP

END
