;=====================================================================
; export.asm  -  Excel report, CSV file and printable timetable
;
; Excel: the "XML Spreadsheet" format. It is plain text, so assembly
; can write it like any other file, but Excel opens it as a real
; workbook with several sheets, colours, bold headers and a live
; formula (the CGPA cell recalculates if you change a GPA in Excel).
;   Sheets: Summary | Courses | Semesters | Deadlines | Study log
;
; CSV: comma-separated values, the simplest table format.
; Timetable: a plain .txt file, one line per day of the plan.
;
; All three are built in one big buffer (xbuf) with small helpers
; (XPut, XCellStr ...), then written with Irvine32's WriteToFile.
; The standard Windows "Save As" dialog asks where to save, and
; ShellExecute opens the result in Excel / Notepad.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

XReset      PROTO
XPut        PROTO :DWORD
XPutChar    PROTO :DWORD
XPutEsc     PROTO :DWORD
XCellStr    PROTO :DWORD, :DWORD
XCellNum    PROTO :DWORD, :DWORD
XCellInt    PROTO :DWORD
XCellFix2   PROTO :DWORD
XCellTenths PROTO :DWORD
XLabelRow   PROTO :DWORD, :DWORD, :DWORD
CsvField    PROTO :DWORD
AskSavePath PROTO :DWORD, :DWORD, :DWORD
WriteBuffer PROTO
OpenSaved   PROTO

XBUF_MAX    = 65000

.data
szFmtD BYTE "%d", 0
courseHeads DWORD OFFSET szH_Course, OFFSET szH_Cr, OFFSET szH_Marks, OFFSET szH_OutOf,
                  OFFSET szH_Target, OFFSET szH_Slider, OFFSET szH_AttPct, OFFSET szH_Held,
                  OFFSET szH_Att, OFFSET szH_AttSt, OFFSET szH_Diff, OFFSET szH_Prep
semHeads DWORD OFFSET szH_Sem, OFFSET szH_Gpa, OFFSET szH_Cr
dlHeads DWORD OFFSET szH_Title, OFFSET szH_Type, OFFSET szH_Course, OFFSET szH_Due,
              OFFSET szH_Left, OFFSET szH_Status
logHeads DWORD OFFSET szH_Date, OFFSET szH_Course, OFFSET szH_Min
xbuf        BYTE 65536 DUP(?)
xlen        DWORD 0
savePath    BYTE 260 DUP(0)
ofn         OPENFILENAMEA <>
numBuf      BYTE 64 DUP(0)
lineBuf     BYTE 200 DUP(0)
smallBuf    BYTE 48 DUP(0)

szOpenVerb  BYTE "open", 0
szExcelExe  BYTE "excel.exe", 0
szQuote1    BYTE '"', 0
quotedPath  BYTE 280 DUP(0)
openInExcel DWORD 0             ; 1 for the Excel report and the CSV
szReportPre BYTE "report_", 0
szTablePre  BYTE "timetable_", 0
szExtXml    BYTE ".xml", 0
szExtCsv    BYTE ".csv", 0
szExtTxt    BYTE ".txt", 0
szDefXml    BYTE "xml", 0
szDefCsv    BYTE "csv", 0
szDefTxt    BYTE "txt", 0
szFilterXml BYTE "Excel workbook (*.xml)", 0, "*.xml", 0, 0
szFilterCsv BYTE "CSV table (*.csv)", 0, "*.csv", 0, 0
szFilterTxt BYTE "Text file (*.txt)", 0, "*.txt", 0, 0
szFailTitle BYTE "Export", 0
szFailText  BYTE "The file could not be written. Is it open in Excel?", 0
szFmtSaved  BYTE "Exported %s", 0
szLogXls    BYTE "Exported the Excel report", 0
szLogCsv    BYTE "Exported the CSV file", 0
szLogTt     BYTE "Exported the study timetable", 0

; ---------------- XML pieces ----------------
xmlHead BYTE '<?xml version="1.0"?>', 13, 10
        BYTE '<?mso-application progid="Excel.Sheet"?>', 13, 10
        BYTE '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"', 13, 10
        BYTE ' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">', 13, 10
        BYTE '<Styles>', 13, 10
        BYTE '<Style ss:ID="Default"><Font ss:FontName="Segoe UI" ss:Size="10" ss:Color="#3A3A4A"/></Style>', 13, 10
        BYTE '<Style ss:ID="t"><Font ss:FontName="Segoe UI" ss:Size="16" ss:Bold="1" ss:Color="#4A4370"/></Style>', 13, 10
        BYTE '<Style ss:ID="h"><Font ss:FontName="Segoe UI" ss:Bold="1" ss:Color="#4A4370"/><Interior ss:Color="#D9D2F0" ss:Pattern="Solid"/></Style>', 13, 10
        BYTE '<Style ss:ID="lb"><Font ss:FontName="Segoe UI" ss:Color="#7A7A8C"/></Style>', 13, 10
        BYTE '<Style ss:ID="b"><Font ss:FontName="Segoe UI" ss:Bold="1"/></Style>', 13, 10
        BYTE '<Style ss:ID="bn2"><Font ss:FontName="Segoe UI" ss:Bold="1"/><NumberFormat ss:Format="0.00"/></Style>', 13, 10
        BYTE '<Style ss:ID="n2"><NumberFormat ss:Format="0.00"/></Style>', 13, 10
        BYTE '<Style ss:ID="n2b"><Font ss:FontName="Segoe UI" ss:Bold="1" ss:Color="#4A4370"/><NumberFormat ss:Format="0.00"/></Style>', 13, 10
        BYTE '<Style ss:ID="ok"><Font ss:FontName="Segoe UI" ss:Color="#2E6B47"/><Interior ss:Color="#CDEBD8" ss:Pattern="Solid"/><NumberFormat ss:Format="0.00"/></Style>', 13, 10
        BYTE '<Style ss:ID="warn"><Font ss:FontName="Segoe UI" ss:Color="#7A5A12"/><Interior ss:Color="#FBE8C0" ss:Pattern="Solid"/><NumberFormat ss:Format="0.00"/></Style>', 13, 10
        BYTE '<Style ss:ID="bad"><Font ss:FontName="Segoe UI" ss:Color="#8A3A3A"/><Interior ss:Color="#F6CFCF" ss:Pattern="Solid"/><NumberFormat ss:Format="0.00"/></Style>', 13, 10
        BYTE '<Style ss:ID="grey"><Font ss:FontName="Segoe UI" ss:Color="#7A7A8C"/><Interior ss:Color="#F1EFEB" ss:Pattern="Solid"/></Style>', 13, 10
        BYTE '</Styles>', 13, 10, 0
xmlTail     BYTE '</Workbook>', 13, 10, 0
xSheetA     BYTE '<Worksheet ss:Name="', 0
xSheetB     BYTE '"><Table>', 13, 10, 0
xSheetEnd   BYTE '</Table></Worksheet>', 13, 10, 0
xRow        BYTE '<Row>', 0
xRowEnd     BYTE '</Row>', 13, 10, 0
xEmptyRow   BYTE '<Row/>', 13, 10, 0
xCellA      BYTE '<Cell', 0
xStyleA     BYTE ' ss:StyleID="', 0
xQuote      BYTE '"', 0
xDataStr    BYTE '><Data ss:Type="String">', 0
xDataNum    BYTE '><Data ss:Type="Number">', 0
xCellEnd    BYTE '</Data></Cell>', 0
xColW180    BYTE '<Column ss:Width="180"/>', 0
xColW110    BYTE '<Column ss:Width="110"/>', 0
xColW80     BYTE '<Column ss:Width="80"/>', 0
xAmp        BYTE '&amp;', 0
xLt         BYTE '&lt;', 0
xGt         BYTE '&gt;', 0
xQuot       BYTE '&quot;', 0
szSt_t      BYTE "t", 0
szSt_h      BYTE "h", 0
szSt_lb     BYTE "lb", 0
szSt_b      BYTE "b", 0
szSt_bn2    BYTE "bn2", 0
szSt_n2     BYTE "n2", 0
szSt_ok     BYTE "ok", 0
szSt_warn   BYTE "warn", 0
szSt_bad    BYTE "bad", 0
szSt_grey   BYTE "grey", 0
szFmtFormula BYTE '<Cell ss:StyleID="n2b" ss:Formula="=SUMPRODUCT(R2C2:R%dC2,R2C3:R%dC3)/SUM(R2C3:R%dC3)"><Data ss:Type="Number">%s</Data></Cell>', 0
szFmtSumF   BYTE '<Cell ss:StyleID="b" ss:Formula="=SUM(R2C3:R%dC3)"><Data ss:Type="Number">%d</Data></Cell>', 0

; ---------------- words used in the sheets ----------------
szShSummary BYTE "Summary", 0
szShCourses BYTE "Courses", 0
szShSems    BYTE "Semesters", 0
szShDl      BYTE "Deadlines", 0
szShLog     BYTE "Study log", 0
szRepTitle  BYTE "Student Toolkit report", 0
szLStudent  BYTE "Student", 0
szLUser     BYTE "Username", 0
szLDate     BYTE "Report date", 0
szLCgpa     BYTE "Current CGPA", 0
szLTarget   BYTE "Target CGPA", 0
szLNeeded   BYTE "Needed this semester", 0
szLSemGpa   BYTE "Semester GPA (grade sliders)", 0
szLNewCgpa  BYTE "New CGPA (grade sliders)", 0
szLStreak   BYTE "Study streak (days)", 0
szLBest     BYTE "Best streak (days)", 0
szLTotal    BYTE "Total study time", 0
szLPomos    BYTE "Pomodoros finished", 0
szLBadges   BYTE "Badges earned", 0
szFmtBadges BYTE "%d of 8", 0
szDashX     BYTE "-", 0
szAbove4X   BYTE "above 4.00 (not possible)", 0
szH_Course  BYTE "Course", 0
szH_Cr      BYTE "Credits", 0
szH_Marks   BYTE "Marks so far", 0
szH_OutOf   BYTE "Out of", 0
szH_Target  BYTE "Target grade", 0
szH_Slider  BYTE "Planned grade", 0
szH_AttPct  BYTE "Attendance %", 0
szH_Held    BYTE "Classes held", 0
szH_Att     BYTE "Attended", 0
szH_AttSt   BYTE "Attendance status", 0
szH_Diff    BYTE "Difficulty", 0
szH_Prep    BYTE "Preparation", 0
szH_Sem     BYTE "Semester", 0
szH_Gpa     BYTE "GPA", 0
szH_CgpaF   BYTE "CGPA (live Excel formula)", 0
szH_Title   BYTE "Title", 0
szH_Type    BYTE "Type", 0
szH_Due     BYTE "Due date", 0
szH_Left    BYTE "Days left", 0
szH_Status  BYTE "Status", 0
szH_Date    BYTE "Date", 0
szH_Min     BYTE "Minutes", 0
szH_TotalM  BYTE "Total minutes", 0
szFmtSemN   BYTE "Semester %d", 0
szGeneralX  BYTE "General", 0
szAttNone   BYTE "No classes yet", 0
szFmtAttOk  BYTE "Safe - can skip %d", 0
szAttEdge   BYTE "At the limit - can't skip", 0
szFmtAttBad BYTE "Below 80% - attend next %d", 0
szStDone    BYTE "Done", 0
szStLate    BYTE "Overdue", 0
szStSoon    BYTE "Due soon", 0
szStLater   BYTE "Upcoming", 0
szStNoDate  BYTE "No due date", 0
szNoDateX   BYTE "no date", 0

; ---------------- CSV / timetable words ----------------
szCsvCourses BYTE "Course,Credits,Marks so far,Out of,Target grade,Attendance %,Classes held,Attended,Difficulty,Preparation", 13, 10, 0
szCsvSems    BYTE 13, 10, "Semester,GPA,Credits", 13, 10, 0
szCsvDl      BYTE 13, 10, "Title,Type,Course,Due date,Done", 13, 10, 0
szComma      BYTE ",", 0
szNewLine    BYTE 13, 10, 0
szYes        BYTE "yes", 0
szNo         BYTE "no", 0
szTtTitle    BYTE "STUDENT TOOLKIT - STUDY TIMETABLE", 13, 10, 0
szFmtTtFor   BYTE "For %s", 0
szFmtTtInfo  BYTE "   |   %s a day in 25-minute Pomodoro sessions", 13, 10, 13, 10, 0
szTtRule     BYTE "-------------------------------------------------------------", 13, 10, 0
szFmtTtItem  BYTE "%s x%d", 0
szTtSep      BYTE ", ", 0
szTtTab      BYTE 9, 0
szTtFree     BYTE "free day", 0
szFmtTtExam  BYTE "   << %s exam", 0
szTtTotals   BYTE 13, 10, "Totals:  ", 0
szFmtTtTotal BYTE "%s %s", 0

.code
;=====================================================================
;                       buffer helpers
;=====================================================================
XReset PROC
    mov xlen, 0
    ret
XReset ENDP

;---------------------------------------------------------------------
; XPut - appends a zero-terminated string to xbuf (rep movsb)
;---------------------------------------------------------------------
XPut PROC USES ecx esi edi, pStr:DWORD
    INVOKE Str_length, pStr
    mov ecx, eax
    add eax, xlen
    cmp eax, XBUF_MAX
    ja  Done                        ; buffer full: stop adding
    mov esi, pStr
    mov edi, OFFSET xbuf
    add edi, xlen
    mov xlen, eax
    cld
    rep movsb
Done:
    ret
XPut ENDP

XPutChar PROC c1:DWORD
    mov eax, xlen
    cmp eax, XBUF_MAX
    jae @F
    mov ecx, c1
    mov xbuf[eax], cl
    inc xlen
@@: ret
XPutChar ENDP

;---------------------------------------------------------------------
; XPutEsc - appends text, turning & < > " into XML entities
;---------------------------------------------------------------------
XPutEsc PROC USES esi, pStr:DWORD
    mov esi, pStr
NextChar:
    movzx eax, BYTE PTR [esi]
    cmp eax, 0
    je  Done
    cmp eax, '&'
    jne @F
    INVOKE XPut, ADDR xAmp
    jmp Advance
@@: cmp eax, '<'
    jne @F
    INVOKE XPut, ADDR xLt
    jmp Advance
@@: cmp eax, '>'
    jne @F
    INVOKE XPut, ADDR xGt
    jmp Advance
@@: cmp eax, '"'
    jne @F
    INVOKE XPut, ADDR xQuot
    jmp Advance
@@: INVOKE XPutChar, eax
Advance:
    inc esi
    jmp NextChar
Done:
    ret
XPutEsc ENDP

;---------------------------------------------------------------------
; XCellStr / XCellNum - one spreadsheet cell (style may be NULL)
;---------------------------------------------------------------------
XCellStr PROC pText:DWORD, pStyle:DWORD
    INVOKE XPut, ADDR xCellA
    cmp pStyle, NULL
    je  @F
    INVOKE XPut, ADDR xStyleA
    INVOKE XPut, pStyle
    INVOKE XPut, ADDR xQuote
@@: INVOKE XPut, ADDR xDataStr
    INVOKE XPutEsc, pText
    INVOKE XPut, ADDR xCellEnd
    ret
XCellStr ENDP

XCellNum PROC pText:DWORD, pStyle:DWORD
    INVOKE XPut, ADDR xCellA
    cmp pStyle, NULL
    je  @F
    INVOKE XPut, ADDR xStyleA
    INVOKE XPut, pStyle
    INVOKE XPut, ADDR xQuote
@@: INVOKE XPut, ADDR xDataNum
    INVOKE XPut, pText
    INVOKE XPut, ADDR xCellEnd
    ret
XCellNum ENDP

XCellInt PROC value:DWORD
    INVOKE wsprintf, ADDR numBuf, ADDR szFmtD, value
    INVOKE XCellNum, ADDR numBuf, NULL
    ret
XCellInt ENDP

XCellFix2 PROC value:DWORD
    INVOKE FormatFixed2, value, ADDR numBuf
    INVOKE XCellNum, ADDR numBuf, ADDR szSt_n2
    ret
XCellFix2 ENDP

XCellTenths PROC value:DWORD
    INVOKE FormatTenths, value, ADDR numBuf
    INVOKE XCellNum, ADDR numBuf, NULL
    ret
XCellTenths ENDP

;---------------------------------------------------------------------
; XLabelRow - "label | value" row on the Summary sheet
;---------------------------------------------------------------------
XLabelRow PROC USES ebx esi, pLabel:DWORD, pValue:DWORD, pStyle:DWORD
    INVOKE XPut, ADDR xRow
    INVOKE XCellStr, pLabel, ADDR szSt_lb
    ; is the value a plain number ("3.14", "25")? then write a Number
    mov esi, pValue
    xor ebx, ebx                    ; 1 once a '.' is seen
    cmp BYTE PTR [esi], 0
    je  AsText
CheckChar:
    mov al, [esi]
    cmp al, 0
    je  AsNumber
    cmp al, '.'
    jne @F
    mov ebx, 1
    jmp NextChar
@@: cmp al, '0'
    jb  AsText
    cmp al, '9'
    ja  AsText
NextChar:
    inc esi
    jmp CheckChar
AsNumber:
    mov eax, pStyle
    cmp ebx, 0
    je  WriteNumber                 ; whole number: keep the given style
    cmp eax, NULL
    jne @F
    mov eax, OFFSET szSt_n2         ; decimals: always show two places
    jmp WriteNumber
@@: cmp eax, OFFSET szSt_b
    jne WriteNumber
    mov eax, OFFSET szSt_bn2
WriteNumber:
    INVOKE XCellNum, pValue, eax
    jmp RowDone
AsText:
    INVOKE XCellStr, pValue, pStyle
RowDone:
    INVOKE XPut, ADDR xRowEnd
    ret
XLabelRow ENDP

;---------------------------------------------------------------------
; XSheet / XHeaderRow helpers
;---------------------------------------------------------------------
XSheet PROC pName:DWORD
    INVOKE XPut, ADDR xSheetA
    INVOKE XPut, pName
    INVOKE XPut, ADDR xSheetB
    ret
XSheet ENDP

; header row from a list of string addresses
XHeaderRow PROC USES ebx esi, pList:DWORD, count:DWORD
    INVOKE XPut, ADDR xRow
    mov esi, pList
    xor ebx, ebx
@@: cmp ebx, count
    jae @F
    INVOKE XCellStr, DWORD PTR [esi + ebx*4], ADDR szSt_h
    inc ebx
    jmp @B
@@: INVOKE XPut, ADDR xRowEnd
    ret
XHeaderRow ENDP

;=====================================================================
;                       saving and opening
;=====================================================================
;---------------------------------------------------------------------
; AskSavePath - standard "Save As" dialog
;   savePath starts as  prefix + username + extension
; Returns: EAX = 1 if the student chose a file
;---------------------------------------------------------------------
AskSavePath PROC USES edi, namePrefix:DWORD, nameExt:DWORD, filterText:DWORD
    INVOKE Str_copy, namePrefix, ADDR savePath
    INVOKE StrAppend, ADDR savePath, ADDR userData.userName
    INVOKE StrAppend, ADDR savePath, nameExt

    mov edi, OFFSET ofn
    mov ecx, SIZEOF OPENFILENAMEA
    xor eax, eax
    cld
    rep stosb
    mov ofn.ofnSize, SIZEOF OPENFILENAMEA
    mov eax, hMainWnd
    mov ofn.ofnOwner, eax
    mov eax, filterText
    mov ofn.ofnFilter, eax
    mov ofn.ofnFile, OFFSET savePath
    mov ofn.ofnMaxFile, SIZEOF savePath
    mov ofn.ofnFlags, OFN_OVERWRITEPROMPT OR OFN_PATHMUSTEXIST OR OFN_NOCHANGEDIR
    mov eax, nameExt
    inc eax                         ; default extension without the dot
    mov ofn.ofnDefExt, eax
    INVOKE GetSaveFileNameA, ADDR ofn
    ret
AskSavePath ENDP

;---------------------------------------------------------------------
; WriteBuffer - xbuf -> savePath (Irvine32 file routines)
; Returns: EAX = 1 ok, 0 failed
;---------------------------------------------------------------------
WriteBuffer PROC USES ebx ecx edx esi
    mov edx, OFFSET savePath
    call CreateOutputFile
    cmp eax, INVALID_HANDLE_VALUE
    je  Failed
    mov ebx, eax
    mov edx, OFFSET xbuf
    mov ecx, xlen
    call WriteToFile
    mov esi, eax
    mov eax, ebx
    call CloseFile
    cmp esi, xlen
    jne Failed
    mov eax, 1
    ret
Failed:
    INVOKE MessageBoxA, hMainWnd, ADDR szFailText, ADDR szFailTitle, MB_OK OR MB_ICONWARNING
    xor eax, eax
    ret
WriteBuffer ENDP

;---------------------------------------------------------------------
; OpenSaved - opens the new file (Excel / Notepad) and says so
;---------------------------------------------------------------------
OpenSaved PROC USES esi
    ; reports open in Excel itself (Windows may send .xml files to a
    ; browser); if Excel is not installed, use the normal program
    cmp openInExcel, 0
    je  DefaultOpen
    INVOKE Str_copy, ADDR szQuote1, ADDR quotedPath
    INVOKE StrAppend, ADDR quotedPath, ADDR savePath
    INVOKE StrAppend, ADDR quotedPath, ADDR szQuote1
    INVOKE ShellExecuteA, hMainWnd, ADDR szOpenVerb, ADDR szExcelExe, ADDR quotedPath, NULL, SW_SHOWNORMAL
    cmp eax, 32                     ; above 32 = started
    ja  Opened
DefaultOpen:
    INVOKE ShellExecuteA, hMainWnd, ADDR szOpenVerb, ADDR savePath, NULL, NULL, SW_SHOWNORMAL
Opened:
    ; status bar: "Exported report_aden.xml" (file name only)
    mov esi, OFFSET savePath
    INVOKE Str_length, esi
    add esi, eax
@@: cmp esi, OFFSET savePath
    je  @F
    cmp BYTE PTR [esi - 1], '\'
    je  @F
    dec esi
    jmp @B
@@: INVOKE wsprintf, ADDR lineBuf, ADDR szFmtSaved, esi
    INVOKE SetStatusRight, ADDR lineBuf
    ret
OpenSaved ENDP

;=====================================================================
;                       the Excel report
;=====================================================================
ExportExcel PROC USES ebx esi edi
    LOCAL value:DWORD, status:DWORD, rows:DWORD, today:DWORD, i:DWORD,
          sysTime:SYSTEMTIME

    INVOKE AskSavePath, ADDR szReportPre, ADDR szExtXml, ADDR szFilterXml
    cmp eax, 0
    je  Done
    INVOKE TodayDay
    mov today, eax
    INVOKE XReset
    INVOKE XPut, ADDR xmlHead

    ;================ Summary ================
    INVOKE XSheet, ADDR szShSummary
    INVOKE XPut, ADDR xColW180
    INVOKE XPut, ADDR xColW180
    INVOKE XPut, ADDR xRow
    INVOKE XCellStr, ADDR szRepTitle, ADDR szSt_t
    INVOKE XPut, ADDR xRowEnd
    INVOKE XPut, ADDR xEmptyRow
    INVOKE XLabelRow, ADDR szLStudent, ADDR userData.displayName, ADDR szSt_b
    INVOKE XLabelRow, ADDR szLUser, ADDR userData.userName, NULL
    INVOKE FormatDateShort, today, ADDR smallBuf
    INVOKE XLabelRow, ADDR szLDate, ADDR smallBuf, NULL
    INVOKE XPut, ADDR xEmptyRow
    ; CGPA
    INVOKE CurrentCgpa
    mov esi, OFFSET szDashX
    cmp eax, -1
    je  @F
    INVOKE FormatFixed2, eax, ADDR smallBuf
    mov esi, OFFSET smallBuf
@@: INVOKE XLabelRow, ADDR szLCgpa, esi, ADDR szSt_b
    ; target
    mov esi, OFFSET szDashX
    cmp userData.targetCgpa, 0
    je  @F
    INVOKE FormatFixed2, userData.targetCgpa, ADDR smallBuf
    mov esi, OFFSET smallBuf
@@: INVOKE XLabelRow, ADDR szLTarget, esi, NULL
    ; needed, coloured like the app
    INVOKE RequiredGpa
    mov value, eax
    mov status, edx
    mov esi, OFFSET szDashX
    mov edi, NULL
    cmp status, 0
    jne NeededRow
    mov edi, OFFSET szSt_ok
    cmp value, 300
    jbe @F
    mov edi, OFFSET szSt_warn
    cmp value, 367
    jbe @F
    mov edi, OFFSET szSt_bad
@@: mov esi, OFFSET szAbove4X
    cmp value, 400
    ja  NeededRow
    INVOKE FormatFixed2, value, ADDR smallBuf
    mov esi, OFFSET smallBuf
NeededRow:
    INVOKE XLabelRow, ADDR szLNeeded, esi, edi
    ; semester GPA and new CGPA from the sliders
    INVOKE CalcSemester
    mov esi, OFFSET szDashX
    cmp ecx, 0
    je  @F
    mov ebx, ecx
    shr ebx, 1
    add eax, ebx
    xor edx, edx
    div ecx
    INVOKE FormatFixed2, eax, ADDR smallBuf
    mov esi, OFFSET smallBuf
@@: INVOKE XLabelRow, ADDR szLSemGpa, esi, NULL
    INVOKE NewCgpa
    mov esi, OFFSET szDashX
    cmp eax, -1
    je  @F
    INVOKE FormatFixed2, eax, ADDR smallBuf
    mov esi, OFFSET smallBuf
@@: INVOKE XLabelRow, ADDR szLNewCgpa, esi, NULL
    INVOKE XPut, ADDR xEmptyRow
    ; study numbers
    INVOKE CurrentStreak
    INVOKE wsprintf, ADDR smallBuf, ADDR szFmtD, eax
    INVOKE XLabelRow, ADDR szLStreak, ADDR smallBuf, NULL
    INVOKE wsprintf, ADDR smallBuf, ADDR szFmtD, userData.streakBest
    INVOKE XLabelRow, ADDR szLBest, ADDR smallBuf, NULL
    INVOKE FormatMinutes, userData.totalMinutes, ADDR smallBuf
    INVOKE XLabelRow, ADDR szLTotal, ADDR smallBuf, NULL
    INVOKE wsprintf, ADDR smallBuf, ADDR szFmtD, userData.pomodoros
    INVOKE XLabelRow, ADDR szLPomos, ADDR smallBuf, NULL
    ; badges: count the bits
    xor ecx, ecx
    mov eax, userData.badges
    mov ebx, BADGE_COUNT
@@: shr eax, 1
    adc ecx, 0
    dec ebx
    jnz @B
    INVOKE wsprintf, ADDR smallBuf, ADDR szFmtBadges, ecx
    INVOKE XLabelRow, ADDR szLBadges, ADDR smallBuf, NULL
    INVOKE XPut, ADDR xSheetEnd

    ;================ Courses ================
    INVOKE XSheet, ADDR szShCourses
    INVOKE XPut, ADDR xColW180
    mov ecx, 11
@@: push ecx
    INVOKE XPut, ADDR xColW110
    pop ecx
    loop @B
    INVOKE XHeaderRow, ADDR courseHeads, 12
    mov esi, OFFSET userData.courses
    mov i, 0
CourseLoop:
    mov eax, i
    cmp eax, userData.courseCount
    jae CoursesDone
    INVOKE XPut, ADDR xRow
    INVOKE XCellStr, esi, ADDR szSt_b
    INVOKE XCellInt, (COURSE PTR [esi]).credits
    cmp (COURSE PTR [esi]).marksTotal, 0
    jne @F
    INVOKE XCellStr, ADDR szDashX, NULL
    INVOKE XCellStr, ADDR szDashX, NULL
    jmp MarksDone
@@: INVOKE XCellTenths, (COURSE PTR [esi]).marksObt
    INVOKE XCellTenths, (COURSE PTR [esi]).marksTotal
MarksDone:
    INVOKE GradeName, (COURSE PTR [esi]).targetGrade
    INVOKE XCellStr, eax, NULL
    INVOKE GradeName, (COURSE PTR [esi]).sliderGrade
    INVOKE XCellStr, eax, NULL
    ; attendance
    INVOKE AttendanceInfo, esi
    mov value, edx
    mov status, ecx
    cmp ecx, 0
    jne @F
    INVOKE XCellStr, ADDR szDashX, NULL
    jmp AttCounts
@@: INVOKE XCellInt, eax
AttCounts:
    INVOKE XCellInt, (COURSE PTR [esi]).classesHeld
    INVOKE XCellInt, (COURSE PTR [esi]).classesAttended
    cmp status, 0
    jne @F
    INVOKE XCellStr, ADDR szAttNone, ADDR szSt_grey
    jmp AttDone
@@: cmp status, 1
    jne @F
    INVOKE wsprintf, ADDR lineBuf, ADDR szFmtAttOk, value
    INVOKE XCellStr, ADDR lineBuf, ADDR szSt_ok
    jmp AttDone
@@: cmp status, 2
    jne @F
    INVOKE XCellStr, ADDR szAttEdge, ADDR szSt_warn
    jmp AttDone
@@: INVOKE wsprintf, ADDR lineBuf, ADDR szFmtAttBad, value
    INVOKE XCellStr, ADDR lineBuf, ADDR szSt_bad
AttDone:
    INVOKE XCellInt, (COURSE PTR [esi]).difficulty
    INVOKE XCellInt, (COURSE PTR [esi]).preparation
    INVOKE XPut, ADDR xRowEnd
    add esi, SIZEOF COURSE
    inc i
    jmp CourseLoop
CoursesDone:
    INVOKE XPut, ADDR xSheetEnd

    ;================ Semesters ================
    INVOKE XSheet, ADDR szShSems
    INVOKE XPut, ADDR xColW180
    INVOKE XPut, ADDR xColW80
    INVOKE XPut, ADDR xColW80
    INVOKE XHeaderRow, ADDR semHeads, 3
    mov esi, OFFSET userData.semesters
    mov i, 0
SemLoop:
    mov eax, i
    cmp eax, userData.semCount
    jae SemsDone
    INVOKE XPut, ADDR xRow
    mov eax, i
    inc eax
    INVOKE wsprintf, ADDR lineBuf, ADDR szFmtSemN, eax
    INVOKE XCellStr, ADDR lineBuf, NULL
    INVOKE XCellFix2, (SEMESTER PTR [esi]).semGpa
    INVOKE XCellInt, (SEMESTER PTR [esi]).semCredits
    INVOKE XPut, ADDR xRowEnd
    add esi, SIZEOF SEMESTER
    inc i
    jmp SemLoop
SemsDone:
    cmp userData.semCount, 0
    je  NoFormula
    ; live formula: =SUMPRODUCT(GPA, credits) / SUM(credits)
    INVOKE XPut, ADDR xEmptyRow
    INVOKE XPut, ADDR xRow
    INVOKE XCellStr, ADDR szH_CgpaF, ADDR szSt_b
    INVOKE CurrentCgpa
    INVOKE FormatFixed2, eax, ADDR smallBuf
    mov eax, userData.semCount
    inc eax                         ; last data row (row 1 is the header)
    INVOKE wsprintf, ADDR lineBuf, ADDR szFmtFormula, eax, eax, eax, ADDR smallBuf
    INVOKE XPut, ADDR lineBuf
    INVOKE XPut, ADDR xRowEnd
NoFormula:
    INVOKE XPut, ADDR xSheetEnd

    ;================ Deadlines ================
    INVOKE XSheet, ADDR szShDl
    INVOKE XPut, ADDR xColW180
    mov ecx, 5
@@: push ecx
    INVOKE XPut, ADDR xColW110
    pop ecx
    loop @B
    INVOKE XHeaderRow, ADDR dlHeads, 6
    mov esi, OFFSET userData.deadlines
    mov i, 0
DlLoop:
    mov eax, i
    cmp eax, userData.deadlineCount
    jae DlDone
    INVOKE XPut, ADDR xRow
    INVOKE XCellStr, ADDR (DEADLINE PTR [esi]).dtitle, ADDR szSt_b
    mov eax, (DEADLINE PTR [esi]).kind
    INVOKE XCellStr, kindNames[eax*4], NULL
    mov ecx, OFFSET szGeneralX
    mov eax, (DEADLINE PTR [esi]).course
    cmp eax, -1
    je  @F
    cmp eax, userData.courseCount
    jae @F
    imul eax, eax, SIZEOF COURSE
    lea ecx, userData.courses[eax]
@@: INVOKE XCellStr, ecx, NULL
    cmp (DEADLINE PTR [esi]).dueDay, NO_DATE
    jne HasDueDate
    ; no date: "no date", empty days-left, status "No due date" / "Done"
    INVOKE XCellStr, ADDR szNoDateX, NULL
    INVOKE XCellStr, ADDR szDashX, NULL
    cmp (DEADLINE PTR [esi]).isDone, 0
    jne @F
    INVOKE XCellStr, ADDR szStNoDate, ADDR szSt_grey
    jmp DlRowEnd
@@: INVOKE XCellStr, ADDR szStDone, ADDR szSt_grey
    jmp DlRowEnd
HasDueDate:
    INVOKE FormatDateShort, (DEADLINE PTR [esi]).dueDay, ADDR smallBuf
    INVOKE XCellStr, ADDR smallBuf, NULL
    mov eax, (DEADLINE PTR [esi]).dueDay
    sub eax, today
    mov value, eax
    INVOKE XCellInt, eax
    ; status
    cmp (DEADLINE PTR [esi]).isDone, 0
    je  @F
    INVOKE XCellStr, ADDR szStDone, ADDR szSt_grey
    jmp DlRowEnd
@@: cmp value, 0
    jge @F
    INVOKE XCellStr, ADDR szStLate, ADDR szSt_bad
    jmp DlRowEnd
@@: cmp value, 1
    jg  @F
    INVOKE XCellStr, ADDR szStSoon, ADDR szSt_bad
    jmp DlRowEnd
@@: cmp value, 3
    jg  @F
    INVOKE XCellStr, ADDR szStSoon, ADDR szSt_warn
    jmp DlRowEnd
@@: INVOKE XCellStr, ADDR szStLater, ADDR szSt_ok
DlRowEnd:
    INVOKE XPut, ADDR xRowEnd
    add esi, SIZEOF DEADLINE
    inc i
    jmp DlLoop
DlDone:
    INVOKE XPut, ADDR xSheetEnd

    ;================ Study log ================
    INVOKE XSheet, ADDR szShLog
    INVOKE XPut, ADDR xColW110
    INVOKE XPut, ADDR xColW180
    INVOKE XPut, ADDR xColW80
    INVOKE XHeaderRow, ADDR logHeads, 3
    mov esi, OFFSET userData.studyLog
    mov i, 0
LogLoop:
    mov eax, i
    cmp eax, userData.logCount
    jae LogDone
    INVOKE XPut, ADDR xRow
    INVOKE FormatDateShort, (STUDYLOG PTR [esi]).logDay, ADDR smallBuf
    INVOKE XCellStr, ADDR smallBuf, NULL
    mov ecx, OFFSET szGeneralX
    mov eax, (STUDYLOG PTR [esi]).logCourse
    cmp eax, userData.courseCount
    jae @F
    imul eax, eax, SIZEOF COURSE
    lea ecx, userData.courses[eax]
@@: INVOKE XCellStr, ecx, NULL
    INVOKE XCellInt, (STUDYLOG PTR [esi]).logMinutes
    INVOKE XPut, ADDR xRowEnd
    add esi, SIZEOF STUDYLOG
    inc i
    jmp LogLoop
LogDone:
    cmp userData.logCount, 0
    je  NoSum
    INVOKE XPut, ADDR xRow
    INVOKE XCellStr, ADDR szH_TotalM, ADDR szSt_b
    INVOKE XCellStr, ADDR szDashX, NULL
    mov eax, userData.logCount
    inc eax
    INVOKE wsprintf, ADDR lineBuf, ADDR szFmtSumF, eax, userData.totalMinutes
    INVOKE XPut, ADDR lineBuf
    INVOKE XPut, ADDR xRowEnd
NoSum:
    INVOKE XPut, ADDR xSheetEnd
    INVOKE XPut, ADDR xmlTail

    INVOKE WriteBuffer
    cmp eax, 0
    je  Done
    mov openInExcel, 1
    INVOKE OpenSaved
    INVOKE LogEvent, ADDR szLogXls
Done:
    ret
ExportExcel ENDP

;=====================================================================
;                       CSV
;=====================================================================
;---------------------------------------------------------------------
; CsvField - "text" with any " doubled (CSV rule), no comma after
;---------------------------------------------------------------------
CsvField PROC USES ebx esi, pStr:DWORD
    INVOKE XPutChar, '"'
    mov esi, pStr
@@: movzx ebx, BYTE PTR [esi]       ; (XPutChar changes EAX, so use EBX)
    cmp ebx, 0
    je  @F
    INVOKE XPutChar, ebx
    cmp ebx, '"'
    jne Skip
    INVOKE XPutChar, ebx            ; "" inside a field means one "
Skip:
    inc esi
    jmp @B
@@: INVOKE XPutChar, '"'
    ret
CsvField ENDP

CsvNumber PROC value:DWORD
    INVOKE XPut, ADDR szComma
    INVOKE wsprintf, ADDR numBuf, ADDR szFmtD, value
    INVOKE XPut, ADDR numBuf
    ret
CsvNumber ENDP

ExportCsv PROC USES ebx esi
    LOCAL i:DWORD

    INVOKE AskSavePath, ADDR szReportPre, ADDR szExtCsv, ADDR szFilterCsv
    cmp eax, 0
    je  Done
    INVOKE XReset

    ; ---- courses ----
    INVOKE XPut, ADDR szCsvCourses
    mov esi, OFFSET userData.courses
    mov i, 0
CourseLoop:
    mov eax, i
    cmp eax, userData.courseCount
    jae CoursesDone
    INVOKE CsvField, esi
    INVOKE CsvNumber, (COURSE PTR [esi]).credits
    INVOKE XPut, ADDR szComma
    cmp (COURSE PTR [esi]).marksTotal, 0
    je  NoMarks                     ; no marks yet: leave both cells empty
    INVOKE FormatTenths, (COURSE PTR [esi]).marksObt, ADDR numBuf
    INVOKE XPut, ADDR numBuf
    INVOKE XPut, ADDR szComma
    INVOKE FormatTenths, (COURSE PTR [esi]).marksTotal, ADDR numBuf
    INVOKE XPut, ADDR numBuf
    jmp MarksWritten
NoMarks:
    INVOKE XPut, ADDR szComma
MarksWritten:
    INVOKE XPut, ADDR szComma
    INVOKE GradeName, (COURSE PTR [esi]).targetGrade
    INVOKE XPut, eax
    INVOKE AttendanceInfo, esi
    INVOKE CsvNumber, eax
    INVOKE CsvNumber, (COURSE PTR [esi]).classesHeld
    INVOKE CsvNumber, (COURSE PTR [esi]).classesAttended
    INVOKE CsvNumber, (COURSE PTR [esi]).difficulty
    INVOKE CsvNumber, (COURSE PTR [esi]).preparation
    INVOKE XPut, ADDR szNewLine
    add esi, SIZEOF COURSE
    inc i
    jmp CourseLoop
CoursesDone:

    ; ---- semesters ----
    INVOKE XPut, ADDR szCsvSems
    mov esi, OFFSET userData.semesters
    mov i, 0
SemLoop:
    mov eax, i
    cmp eax, userData.semCount
    jae SemsDone
    inc eax
    INVOKE wsprintf, ADDR numBuf, ADDR szFmtD, eax
    INVOKE XPut, ADDR numBuf
    INVOKE XPut, ADDR szComma
    INVOKE FormatFixed2, (SEMESTER PTR [esi]).semGpa, ADDR numBuf
    INVOKE XPut, ADDR numBuf
    INVOKE CsvNumber, (SEMESTER PTR [esi]).semCredits
    INVOKE XPut, ADDR szNewLine
    add esi, SIZEOF SEMESTER
    inc i
    jmp SemLoop
SemsDone:

    ; ---- deadlines ----
    INVOKE XPut, ADDR szCsvDl
    mov esi, OFFSET userData.deadlines
    mov i, 0
DlLoop:
    mov eax, i
    cmp eax, userData.deadlineCount
    jae DlDone
    INVOKE CsvField, ADDR (DEADLINE PTR [esi]).dtitle
    INVOKE XPut, ADDR szComma
    mov eax, (DEADLINE PTR [esi]).kind
    INVOKE XPut, kindNames[eax*4]
    INVOKE XPut, ADDR szComma
    mov ecx, OFFSET szGeneralX
    mov eax, (DEADLINE PTR [esi]).course
    cmp eax, -1
    je  @F
    cmp eax, userData.courseCount
    jae @F
    imul eax, eax, SIZEOF COURSE
    lea ecx, userData.courses[eax]
@@: INVOKE CsvField, ecx
    INVOKE XPut, ADDR szComma
    cmp (DEADLINE PTR [esi]).dueDay, NO_DATE
    je  @F                          ; no date: empty CSV cell
    INVOKE FormatDateInput, (DEADLINE PTR [esi]).dueDay, ADDR numBuf
    INVOKE XPut, ADDR numBuf
@@: INVOKE XPut, ADDR szComma
    mov edx, OFFSET szNo
    cmp (DEADLINE PTR [esi]).isDone, 0
    je  @F
    mov edx, OFFSET szYes
@@: INVOKE XPut, edx
    INVOKE XPut, ADDR szNewLine
    add esi, SIZEOF DEADLINE
    inc i
    jmp DlLoop
DlDone:

    INVOKE WriteBuffer
    cmp eax, 0
    je  Done
    mov openInExcel, 1
    INVOKE OpenSaved
    INVOKE LogEvent, ADDR szLogCsv
Done:
    ret
ExportCsv ENDP

;=====================================================================
;                       timetable (.txt)
;=====================================================================
ExportTimetable PROC USES ebx esi edi
    LOCAL days:DWORD, d:DWORD, k:DWORD, cix:DWORD, first:DWORD, today:DWORD

    INVOKE AskSavePath, ADDR szTablePre, ADDR szExtTxt, ADDR szFilterTxt
    cmp eax, 0
    je  Done
    INVOKE BuildPlan
    INVOKE TodayDay
    mov today, eax
    INVOKE PlanDays
    mov days, eax
    INVOKE XReset

    ; heading
    INVOKE XPut, ADDR szTtTitle
    INVOKE wsprintf, ADDR lineBuf, ADDR szFmtTtFor, ADDR userData.displayName
    INVOKE XPut, ADDR lineBuf
    INVOKE PlanMinutes
    INVOKE FormatMinutes, eax, ADDR smallBuf
    INVOKE wsprintf, ADDR lineBuf, ADDR szFmtTtInfo, ADDR smallBuf
    INVOKE XPut, ADDR lineBuf
    INVOKE XPut, ADDR szTtRule

    ; one line per day:  "Sat 7 Nov <tab> COAL x6, DLD x3   << COAL exam"
    mov d, 0
DayLoop:
    mov eax, d
    cmp eax, days
    jae DaysDone
    add eax, today
    INVOKE FormatDateShort, eax, ADDR smallBuf
    INVOKE XPut, ADDR smallBuf
    INVOKE XPut, ADDR szTtTab
    mov esi, d
    movzx ecx, dayCount[esi]
    cmp ecx, 0
    jne @F
    INVOKE XPut, ADDR szTtFree
    jmp ExamNote
@@: mov k, 0
    mov first, 1
ItemLoop:
    mov esi, d
    movzx eax, dayCount[esi]
    cmp k, eax
    jae ExamNote
    imul esi, esi, MAX_COURSES
    add esi, k
    movzx ebx, dayOrder[esi]        ; course
    mov esi, d
    imul esi, esi, MAX_COURSES
    add esi, ebx
    movzx edi, planGrid[esi]        ; blocks
    cmp first, 0
    jne @F
    INVOKE XPut, ADDR szTtSep
@@: mov first, 0
    imul eax, ebx, SIZEOF COURSE
    lea eax, userData.courses[eax]
    INVOKE wsprintf, ADDR lineBuf, ADDR szFmtTtItem, eax, edi
    INVOKE XPut, ADDR lineBuf
    inc k
    jmp ItemLoop
ExamNote:
    ; an exam on this day?
    mov eax, d
    add eax, today
    xor ebx, ebx
ExamFind:
    cmp ebx, userData.courseCount
    jae NoExam
    cmp examDay[ebx*4], eax
    je  HasExam
    inc ebx
    jmp ExamFind
HasExam:
    imul eax, ebx, SIZEOF COURSE
    lea eax, userData.courses[eax]
    INVOKE wsprintf, ADDR lineBuf, ADDR szFmtTtExam, eax
    INVOKE XPut, ADDR lineBuf
NoExam:
    INVOKE XPut, ADDR szNewLine
    inc d
    jmp DayLoop
DaysDone:

    ; totals
    INVOKE XPut, ADDR szTtRule
    INVOKE XPut, ADDR szTtTotals
    mov first, 1
    xor ebx, ebx
TotalLoop:
    cmp ebx, userData.courseCount
    jae TotalsDone
    mov eax, totalBlocks[ebx*4]
    cmp eax, 0
    je  NextTotal
    imul eax, eax, POMODORO_MIN
    INVOKE FormatMinutes, eax, ADDR smallBuf
    cmp first, 0
    jne @F
    INVOKE XPut, ADDR szTtSep
@@: mov first, 0
    imul eax, ebx, SIZEOF COURSE
    lea eax, userData.courses[eax]
    INVOKE wsprintf, ADDR lineBuf, ADDR szFmtTtTotal, eax, ADDR smallBuf
    INVOKE XPut, ADDR lineBuf
NextTotal:
    inc ebx
    jmp TotalLoop
TotalsDone:
    INVOKE XPut, ADDR szNewLine

    INVOKE WriteBuffer
    cmp eax, 0
    je  Done
    mov openInExcel, 0              ; the timetable opens in Notepad
    INVOKE OpenSaved
    INVOKE LogEvent, ADDR szLogTt
Done:
    ret
ExportTimetable ENDP

END
