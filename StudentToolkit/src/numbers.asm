;=====================================================================
; numbers.asm  -  reading numbers typed by the user, and printing them
;
; Every number in the program is an integer. Values with one decimal
; place (marks such as 32.5) are stored in tenths: 32.5 -> 325.
;
;   ParseUInt    "42"   -> 42
;   ParseTenths  "32.5" -> 325,  "32" -> 320
;   FormatTenths 325    -> "32.5", 320 -> "32"
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

.data
szFmtInt    BYTE "%d", 0
szFmtTenths BYTE "%d.%d", 0
szFmtFixed2 BYTE "%d.%02d", 0

.code
;---------------------------------------------------------------------
; ParseUInt - reads a whole number (digits only)
; Returns: EAX = value
;          ECX = number of digits (0 = field was empty)
;          EDX = 1 if valid, 0 if it contains anything but digits
;---------------------------------------------------------------------
ParseUInt PROC USES ebx esi, pStr:DWORD
    mov esi, pStr
    xor eax, eax                    ; value
    xor ecx, ecx                    ; digit count
NextChar:
    movzx ebx, BYTE PTR [esi]
    cmp ebx, 0
    je  Valid
    cmp ebx, '0'
    jb  Invalid
    cmp ebx, '9'
    ja  Invalid
    cmp ecx, 6
    jae Invalid                     ; more than 6 digits is never needed
    sub ebx, '0'
    imul eax, eax, 10               ; value = value * 10 + digit
    add eax, ebx
    inc ecx
    inc esi
    jmp NextChar
Valid:
    mov edx, 1
    ret
Invalid:
    xor edx, edx
    ret
ParseUInt ENDP

;---------------------------------------------------------------------
; ParseTenths - reads a number with at most one decimal digit
; Returns: EAX = value x10, ECX = characters read (0 = empty),
;          EDX = 1 valid / 0 invalid
;---------------------------------------------------------------------
ParseTenths PROC USES ebx esi edi, pStr:DWORD
    mov esi, pStr
    xor eax, eax                    ; whole part
    xor ecx, ecx                    ; characters read
    xor edi, edi                    ; digits after the point (0 or 1)
    mov edx, -1                     ; -1 = no decimal point seen yet
NextChar:
    movzx ebx, BYTE PTR [esi]
    cmp ebx, 0
    je  EndOfText
    cmp ebx, '.'
    jne NotPoint
    cmp edx, -1
    jne Invalid                     ; second decimal point
    xor edx, edx
    jmp Advance
NotPoint:
    cmp ebx, '0'
    jb  Invalid
    cmp ebx, '9'
    ja  Invalid
    sub ebx, '0'
    cmp edx, -1
    jne Fraction
    cmp eax, 10000
    jae Invalid                     ; far too large
    imul eax, eax, 10
    add eax, ebx
    jmp Advance
Fraction:
    cmp edi, 1
    jae Invalid                     ; only one decimal digit allowed
    mov edx, ebx                    ; remember the tenths digit
    inc edi
Advance:
    inc ecx
    inc esi
    jmp NextChar

EndOfText:
    imul eax, eax, 10               ; whole part x10
    cmp edx, -1
    je  @F
    add eax, edx                    ; + tenths digit (0 if "32.")
@@: mov edx, 1
    ret
Invalid:
    xor edx, edx
    ret
ParseTenths ENDP

;---------------------------------------------------------------------
; FormatTenths - writes value/10 into pBuf ("32.5", or "32" if .0)
;---------------------------------------------------------------------
FormatTenths PROC USES ecx edx, value:DWORD, pBuf:DWORD
    mov eax, value
    xor edx, edx
    mov ecx, 10
    div ecx                         ; eax = whole part, edx = tenths
    cmp edx, 0
    jne WithPoint
    INVOKE wsprintf, pBuf, ADDR szFmtInt, eax
    ret
WithPoint:
    INVOKE wsprintf, pBuf, ADDR szFmtTenths, eax, edx
    ret
FormatTenths ENDP

;---------------------------------------------------------------------
; FormatUInt - writes a whole number into pBuf
;---------------------------------------------------------------------
FormatUInt PROC USES ecx edx, value:DWORD, pBuf:DWORD
    INVOKE wsprintf, pBuf, ADDR szFmtInt, value
    ret
FormatUInt ENDP

;---------------------------------------------------------------------
; ParseFixed2 - reads a number with up to two decimals, x100
;   "3.2" -> 320,  "3.25" -> 325,  "3" -> 300
; Returns: EAX = value x100, ECX = characters (0 = empty),
;          EDX = 1 valid / 0 invalid
;---------------------------------------------------------------------
ParseFixed2 PROC USES ebx esi edi, pStr:DWORD
    mov esi, pStr
    xor eax, eax                    ; value so far (whole part)
    xor ecx, ecx                    ; characters read
    xor edi, edi                    ; decimal digits read
    mov edx, -1                     ; -1 = before the point
NextChar:
    movzx ebx, BYTE PTR [esi]
    cmp ebx, 0
    je  EndOfText
    cmp ebx, '.'
    jne NotPoint
    cmp edx, -1
    jne Invalid
    xor edx, edx
    jmp Advance
NotPoint:
    cmp ebx, '0'
    jb  Invalid
    cmp ebx, '9'
    ja  Invalid
    sub ebx, '0'
    cmp edx, -1
    jne Decimal
    cmp eax, 1000
    jae Invalid
    imul eax, eax, 10
    add eax, ebx
    jmp Advance
Decimal:
    cmp edi, 2
    jae Invalid                     ; at most two decimals
    imul edx, edx, 10
    add edx, ebx
    inc edi
Advance:
    inc ecx
    inc esi
    jmp NextChar
EndOfText:
    imul eax, eax, 100              ; whole part x100
    cmp edx, -1
    je  Valid
    cmp edi, 1
    jne @F
    imul edx, edx, 10               ; "3.2" -> 20 hundredths
@@: add eax, edx
Valid:
    mov edx, 1
    ret
Invalid:
    xor edx, edx
    ret
ParseFixed2 ENDP

;---------------------------------------------------------------------
; FormatFixed2 - prints a x100 value with two decimals: 305 -> "3.05"
; (the PrintFixed2 idea from our proposal, writing into a buffer)
;---------------------------------------------------------------------
FormatFixed2 PROC USES ecx edx, value:DWORD, pBuf:DWORD
    mov eax, value
    xor edx, edx
    mov ecx, 100
    div ecx                         ; eax = whole part, edx = hundredths
    INVOKE wsprintf, pBuf, ADDR szFmtFixed2, eax, edx
    ret
FormatFixed2 ENDP

END
