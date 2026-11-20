;=====================================================================
; grades_table.asm  -  FAST-NUCES grading table
;
;   Percentage   Grade   Grade points
;   90 +         A+      4.00
;   86 - 89      A       4.00
;   82 - 85      A-      3.67
;   78 - 81      B+      3.33
;   74 - 77      B       3.00
;   70 - 73      B-      2.67
;   66 - 69      C+      2.33
;   62 - 65      C       2.00
;   58 - 61      C-      1.67
;   54 - 57      D+      1.33
;   50 - 53      D       1.00
;   below 50     F       0.00
;
; Three parallel arrays: index i describes the same grade in each.
; Grade points are stored x100 (3.67 -> 367), like everywhere else.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

GRADE_NAME_LEN = 3              ; "A+",0  - every name uses 3 bytes

.data
gradeNames  BYTE "A+",0, "A",0,0, "A-",0, "B+",0, "B",0,0, "B-",0
            BYTE "C+",0, "C",0,0, "C-",0, "D+",0, "D",0,0, "F",0,0
gradeMinPct DWORD 90, 86, 82, 78, 74, 70, 66, 62, 58, 54, 50, 0
gradeGP     DWORD 400, 400, 367, 333, 300, 267, 233, 200, 167, 133, 100, 0

.code
;---------------------------------------------------------------------
; GradeName - address of the name of grade 'index' ("B+")
; Returns: EAX
;---------------------------------------------------------------------
GradeName PROC index:DWORD
    mov eax, index
    cmp eax, GRADE_COUNT
    jb  @F
    mov eax, GRADE_COUNT - 1        ; out of range -> "F"
@@: imul eax, eax, GRADE_NAME_LEN
    add eax, OFFSET gradeNames
    ret
GradeName ENDP

;---------------------------------------------------------------------
; ParseGrade - finds a grade by name ("b+" or "B+")
; Returns: EAX = index 0..11, or -1 if it is not a grade
;---------------------------------------------------------------------
ParseGrade PROC USES ebx ecx esi, pStr:DWORD
    LOCAL upper[4]:BYTE

    ; copy at most 2 characters in upper case
    mov esi, pStr
    xor ecx, ecx
CopyLoop:
    mov al, [esi + ecx]
    cmp al, 0
    je  CopyDone
    cmp ecx, 2
    jae NotFound                    ; longer than 2 characters
    cmp al, 'a'
    jb  @F
    cmp al, 'z'
    ja  @F
    sub al, 20h                     ; to upper case
@@: mov upper[ecx], al
    inc ecx
    jmp CopyLoop
CopyDone:
    mov upper[ecx], 0
    cmp ecx, 0
    je  NotFound

    ; compare with every name in the table
    xor ebx, ebx
SearchLoop:
    INVOKE GradeName, ebx
    INVOKE Str_compare, ADDR upper, eax
    je  Found
    inc ebx
    cmp ebx, GRADE_COUNT
    jb  SearchLoop
NotFound:
    mov eax, -1
    ret
Found:
    mov eax, ebx
    ret
ParseGrade ENDP

END
