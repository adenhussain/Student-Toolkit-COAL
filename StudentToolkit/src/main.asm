;=====================================================================
; Student Toolkit  -  COAL Lab Project, FAST-NUCES Karachi, Fall 2026
;   Aden Hussain          25K-0828
;   Javaria Ahmed Shaikh  25K-0825
;
; main.asm  -  program entry point, main window and message loop
;
; How a Windows GUI program works:
;   1. Register a window class (which procedure handles its messages)
;   2. Create the window and show it
;   3. Message loop: wait for an event (click, key, repaint ...)
;      and send it to the window's procedure (MainWndProc)
;   4. MainWndProc reacts to each message with a cmp / je chain
;
; Program flow:
;   start -> login window -> (logged in) -> main window
;   main window: File > Log out -> saves -> back to the login window
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

MainWndProc PROTO :DWORD, :DWORD, :DWORD, :DWORD

.data
hInstance       DWORD 0
hMainWnd        DWORD 0
hAccel          DWORD 0             ; keyboard shortcuts (Ctrl+S)
hActiveDialog   DWORD 0             ; login / course popup that is open
logoutPending   DWORD 0             ; 1 while logging out

szMainClass     BYTE "STKMainWindow", 0
szAppTitle      BYTE "Student Toolkit", 0
szAboutTitle    BYTE "About Student Toolkit", 0
szAboutText     BYTE "Student Toolkit  v1.0", 13, 10, 13, 10
                BYTE "CGPA planner and smart study planner", 13, 10
                BYTE "written in x86 assembly (MASM) with the Win32 API.", 13, 10, 13, 10
                BYTE "COAL Lab Project, FAST-NUCES Karachi, Fall 2026", 13, 10
                BYTE "Aden Hussain  (25K-0828)", 13, 10
                BYTE "Javaria Ahmed Shaikh  (25K-0825)", 0
szSaveFailTitle BYTE "Save failed", 0
szSaveFailText  BYTE "Your data could not be saved. Check that the data folder", 13, 10
                BYTE "next to StudentToolkit.exe is not read-only.", 0
szFmtSaved      BYTE "Saved at %d:%02d %s", 0
szAM            BYTE "AM", 0
szPM            BYTE "PM", 0
szLogOut        BYTE "Logged out", 0
szLogClosed     BYTE "Closed Student Toolkit", 0
szHelpTitle     BYTE "Student Toolkit - Help", 0
szHelpText      BYTE "Dashboard - everything at a glance. Start session starts the next planned Pomodoro.", 13, 10, 13, 10
                BYTE "Courses - add each course once: credits, marks, attendance, difficulty, preparation. Click a row to edit.", 13, 10, 13, 10
                BYTE "Grades - past semesters, target CGPA, the GPA you need. Drag the sliders, or press Auto-solve.", 13, 10, 13, 10
                BYTE "Planner - hours a day and days ahead. 'Why this plan?' explains every score.", 13, 10, 13, 10
                BYTE "Timer - 25-minute focus sessions with breaks. Mini timer stays on top of other windows.", 13, 10, 13, 10
                BYTE "Deadlines - quizzes, assignments, exams and labs. Click the circle when one is done.", 13, 10, 13, 10
                BYTE "Settings - colour themes, daily limit, sounds, your data and About.", 13, 10, 13, 10
                BYTE "Shortcuts:  Ctrl+S save   F1 help", 0
savedBuf        BYTE 64 DUP(0)

.code
;---------------------------------------------------------------------
; main - program entry point
;---------------------------------------------------------------------
main PROC
    LOCAL wc:WNDCLASSEX, msg:MSG, icc:INITCOMMONCONTROLSEX

    INVOKE GetModuleHandleA, NULL
    mov hInstance, eax

    ; enable modern Windows controls (tables, sliders, progress bars)
    mov icc.dwSize, SIZEOF INITCOMMONCONTROLSEX
    mov icc.dwICC, ICC_WIN95_CLASSES OR ICC_BAR_CLASSES
    INVOKE InitCommonControlsEx, ADDR icc

    INVOKE InitDpi
    INVOKE SetTheme, THEME_LAVENDER
    INVOKE CreateAppFonts
    INVOKE InitDataDir
    INVOKE RegisterPanelClass
    INVOKE RegisterLoginClass
    INVOKE RegisterCourseDialog
    INVOKE RegisterDeadlineDialog
    INVOKE RegisterPinDialog
    INVOKE RegisterMiniTimer
    INVOKE LoadAcceleratorsA, hInstance, IDR_ACCEL
    mov hAccel, eax

    ; ---- 1. register the main window class ----
    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.style, CS_HREDRAW OR CS_VREDRAW
    mov wc.lpfnWndProc, OFFSET MainWndProc
    mov wc.cbClsExtra, 0
    mov wc.cbWndExtra, 0
    mov eax, hInstance
    mov wc.hInstance, eax
    INVOKE LoadIconA, hInstance, IDI_APPICON
    mov wc.hIcon, eax
    INVOKE GetSystemMetrics, SM_CYSMICON
    push eax
    INVOKE GetSystemMetrics, SM_CXSMICON
    pop ecx
    INVOKE LoadImageA, hInstance, IDI_APPICON, IMAGE_ICON, eax, ecx, 0
    mov wc.hIconSm, eax
    INVOKE LoadCursorA, NULL, IDC_ARROW
    mov wc.hCursor, eax
    mov wc.hbrBackground, NULL          ; we paint the background ourselves
    mov wc.lpszMenuName, IDR_MAINMENU   ; menu bar from app.rc
    mov wc.lpszClassName, OFFSET szMainClass
    INVOKE RegisterClassExA, ADDR wc

    ; ---- 2. splash screen, then the login window ----
    INVOKE ShowSplash

    ; ---- 3. message loop ----
MessageLoop:
    INVOKE GetMessageA, ADDR msg, NULL, 0, 0
    cmp eax, 0
    je  ExitProgram                     ; WM_QUIT received
    cmp eax, -1
    je  ExitProgram                     ; error

    ; login / course popup: Tab moves between fields, Enter = OK,
    ; Esc = Cancel
    cmp hActiveDialog, 0
    je  TryShortcut
    INVOKE IsDialogMessageA, hActiveDialog, ADDR msg
    test eax, eax
    jnz MessageLoop
    jmp Dispatch                        ; no shortcuts while a popup is open
TryShortcut:
    ; main window: keyboard shortcuts such as Ctrl+S
    cmp hMainWnd, 0
    je  Dispatch
    INVOKE TranslateAcceleratorA, hMainWnd, hAccel, ADDR msg
    test eax, eax
    jnz MessageLoop
Dispatch:
    INVOKE TranslateMessage, ADDR msg
    INVOKE DispatchMessageA, ADDR msg
    jmp MessageLoop

ExitProgram:
    INVOKE DeleteAppFonts
    INVOKE ExitProcess, msg.wParam
    ret                                 ; never reached (ExitProcess ends the program)
main ENDP

;---------------------------------------------------------------------
; StartMainWindow - opens the main window after a successful login
;---------------------------------------------------------------------
StartMainWindow PROC USES ebx esi edi
    INVOKE SetTheme, userData.theme     ; the student's own theme
    INVOKE BuildGreeting

    INVOKE ScaleDpi, WIN_W
    mov esi, eax                        ; width
    INVOKE ScaleDpi, WIN_H
    mov edi, eax                        ; height

    ; centre on the screen
    INVOKE GetSystemMetrics, SM_CXSCREEN
    sub eax, esi
    sar eax, 1                          ; (screen width - window width) / 2
    jns XOk
    xor eax, eax
XOk:
    mov ebx, eax
    INVOKE GetSystemMetrics, SM_CYSCREEN
    sub eax, edi
    sar eax, 1
    jns YOk
    xor eax, eax
YOk:
    INVOKE CreateWindowExA, 0, ADDR szMainClass, ADDR szAppTitle,
           WS_OVERLAPPEDWINDOW OR WS_CLIPCHILDREN,
           ebx, eax, esi, edi, NULL, NULL, hInstance, NULL
    mov hMainWnd, eax
    INVOKE ShowWindow, hMainWnd, SW_SHOWNORMAL
    INVOKE UpdateWindow, hMainWnd
    INVOKE NotifyDueDeadlines           ; "Quiz 3 is due tomorrow."
    ret
StartMainWindow ENDP

;---------------------------------------------------------------------
; SaveWithStatus - saves and shows "Saved at 9:41 PM" in the status bar
;---------------------------------------------------------------------
SaveWithStatus PROC USES ebx ecx edx
    LOCAL sysTime:SYSTEMTIME

    INVOKE SaveUser
    test eax, eax
    jnz Saved
    INVOKE MessageBoxA, hMainWnd, ADDR szSaveFailText, ADDR szSaveFailTitle,
           MB_OK OR MB_ICONWARNING
    ret

Saved:
    INVOKE GetLocalTime, ADDR sysTime
    movzx eax, sysTime.wHour                 ; 0..23 -> 12-hour clock
    mov ebx, OFFSET szAM
    cmp eax, 12
    jb  @F
    mov ebx, OFFSET szPM
    sub eax, 12
@@: cmp eax, 0
    jne @F
    mov eax, 12                         ; 0 o'clock is shown as 12
@@: movzx ecx, sysTime.wMinute
    INVOKE wsprintf, ADDR savedBuf, ADDR szFmtSaved, eax, ecx, ebx
    INVOKE SetStatusRight, ADDR savedBuf
    ret
SaveWithStatus ENDP

;---------------------------------------------------------------------
; MainWndProc - handles every message sent to the main window
;---------------------------------------------------------------------
MainWndProc PROC USES ebx esi edi, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD

    cmp uMsg, WM_CREATE         ; window was just created
    je  OnCreate
    cmp uMsg, WM_SIZE           ; window was resized
    je  OnSize
    cmp uMsg, WM_GETMINMAXINFO  ; Windows asks for the minimum size
    je  OnMinMax
    cmp uMsg, WM_ERASEBKGND     ; skip default erase (prevents flicker)
    je  OnErase
    cmp uMsg, WM_PAINT          ; window needs to be redrawn
    je  OnPaint
    cmp uMsg, WM_DRAWITEM       ; a sidebar button needs to be drawn
    je  OnDrawItem
    cmp uMsg, WM_COMMAND        ; button click or menu choice
    je  OnCommand
    cmp uMsg, WM_CLOSE          ; X button / File > Exit
    je  OnClose
    cmp uMsg, WM_TRAY           ; click on the tray icon
    je  OnTray
    cmp uMsg, WM_DESTROY        ; window is closing
    je  OnDestroy

    ; any other message: let Windows do the default thing
    INVOKE DefWindowProcA, hWnd, uMsg, wParam, lParam
    ret

OnCreate:
    INVOKE CreateUI, hWnd
    INVOKE TrayAdd, hWnd                ; icon next to the clock
    xor eax, eax
    ret

OnTray:
    INVOKE TrayCallback, hWnd, lParam
    xor eax, eax
    ret

OnSize:
    INVOKE LayoutUI, hWnd
    xor eax, eax
    ret

OnMinMax:
    mov ebx, lParam
    INVOKE ScaleDpi, WIN_MIN_W
    mov (MINMAXINFO PTR [ebx]).ptMinTrackSize.x, eax
    INVOKE ScaleDpi, WIN_MIN_H
    mov (MINMAXINFO PTR [ebx]).ptMinTrackSize.y, eax
    xor eax, eax
    ret

OnErase:
    mov eax, 1
    ret

OnPaint:
    INVOKE PaintMain, hWnd
    xor eax, eax
    ret

OnDrawItem:
    INVOKE DrawNavButton, lParam
    mov eax, TRUE
    ret

OnCommand:
    mov eax, wParam
    and eax, 0FFFFh                     ; low word = control / menu ID

    ; sidebar buttons: IDs 1001 .. 1007
    cmp eax, IDC_NAV_FIRST
    jb  NotNav
    cmp eax, IDC_NAV_FIRST + PANEL_COUNT
    jae NotNav
    sub eax, IDC_NAV_FIRST              ; eax = screen index 0..6
    INVOKE ShowPanel, eax
    jmp CommandDone
NotNav:
    cmp eax, IDM_SAVE
    je  MenuSave
    cmp eax, IDM_LOGOUT
    je  MenuLogout
    cmp eax, IDM_EXIT
    je  MenuExit
    cmp eax, IDM_ABOUT
    je  MenuAbout
    cmp eax, IDM_EXPORT_XLS
    je  MenuExcel
    cmp eax, IDM_EXPORT_CSV
    je  MenuCsv
    cmp eax, IDM_EXPORT_TT
    je  MenuTimetable
    cmp eax, IDM_VIEWLOG
    je  MenuLog
    cmp eax, IDM_HELP
    je  MenuHelp
    jmp CommandDone
MenuHelp:
    INVOKE MessageBoxA, hWnd, ADDR szHelpText, ADDR szHelpTitle, MB_OK OR MB_ICONINFORMATION
    jmp CommandDone
MenuExcel:
    INVOKE ExportExcel
    jmp CommandDone
MenuCsv:
    INVOKE ExportCsv
    jmp CommandDone
MenuTimetable:
    INVOKE ExportTimetable
    jmp CommandDone
MenuLog:
    INVOKE OpenActivityLog
    jmp CommandDone
MenuSave:
    INVOKE SaveWithStatus
    jmp CommandDone
MenuLogout:
    INVOKE LogEvent, ADDR szLogOut
    INVOKE SaveUser
    mov logoutPending, 1
    INVOKE DestroyWindow, hWnd          ; WM_DESTROY opens the login window
    jmp CommandDone
MenuExit:
    INVOKE SendMessageA, hWnd, WM_CLOSE, 0, 0
    jmp CommandDone
MenuAbout:
    INVOKE MessageBoxA, hWnd, ADDR szAboutText, ADDR szAboutTitle,
           MB_OK OR MB_ICONINFORMATION
CommandDone:
    xor eax, eax
    ret

OnClose:
    INVOKE LogEvent, ADDR szLogClosed
    INVOKE SaveUser                     ; never lose data when closing
    INVOKE DestroyWindow, hWnd
    xor eax, eax
    ret

OnDestroy:
    INVOKE TimerStop                    ; stop the Pomodoro, close the mini timer
    INVOKE TrayRemove
    mov hMainWnd, 0
    cmp logoutPending, 0
    je  QuitProgram
    mov logoutPending, 0
    INVOKE ClearUser                    ; forget the student's data
    INVOKE ShowLoginWindow
    xor eax, eax
    ret
QuitProgram:
    INVOKE PostQuitMessage, 0
    xor eax, eax
    ret
MainWndProc ENDP

END main
