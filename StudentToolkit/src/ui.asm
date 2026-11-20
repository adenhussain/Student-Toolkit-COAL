;=====================================================================
; ui.asm  -  main window layout: sidebar, screens (panels), status bar
;
; The main window is split into three areas:
;   +-----------+-----------------------------------+
;   |  sidebar  |   panel (one screen at a time)    |
;   |  7 nav    |                                   |
;   |  buttons  |                                   |
;   +-----------+-----------------------------------+
;   |  status bar                                   |
;   +-----------------------------------------------+
; Each screen is a child window ("panel"). Clicking a sidebar button
; hides the current panel and shows the chosen one.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

PaintPanel  PROTO :DWORD
PanelProc   PROTO :DWORD, :DWORD, :DWORD, :DWORD
NavBtnProc  PROTO :DWORD, :DWORD, :DWORD, :DWORD

.data
szButtonClass   BYTE "BUTTON", 0
szPanelClass    BYTE "STKPanel", 0

; ---- sidebar labels and icons (index = panel number) ----
szNav0  BYTE "Dashboard", 0
szNav1  BYTE "Courses", 0
szNav2  BYTE "Grades", 0
szNav3  BYTE "Planner", 0
szNav4  BYTE "Timer", 0
szNav5  BYTE "Deadlines", 0
szNav6  BYTE "Settings", 0
navLabels   DWORD OFFSET szNav0, OFFSET szNav1, OFFSET szNav2, OFFSET szNav3,
                  OFFSET szNav4, OFFSET szNav5, OFFSET szNav6

; Segoe MDL2 Assets icon codes
navGlyphs   DWORD 0E80Fh        ; Home
            DWORD 0E8F1h        ; Library (courses)
            DWORD 0E8EFh        ; Calculator (grades)
            DWORD 0E787h        ; Calendar (planner)
            DWORD 0E823h        ; Clock (timer)
            DWORD 0EA8Fh        ; Bell (deadlines)
            DWORD 0E713h        ; Settings gear
GLYPH_BRAND = 0E7BEh            ; Graduation cap (app logo)

; ---- one-line description under each screen title ----
szSub0  BYTE "Your overview: CGPA, next exam, today's study plan and streak", 0
szSub1  BYTE "Enter each course once: credits, marks, attendance and difficulty", 0
szSub2  BYTE "CGPA, required GPA, live grade sliders and the marks predictor", 0
szSub3  BYTE "A smart study timetable that knows your exam dates", 0
szSub4  BYTE "Pomodoro sessions, mini timer, streaks and badges", 0
szSub5  BYTE "Quizzes, assignments and exams, sorted by days left", 0
szSub6  BYTE "Themes, daily study limit, sounds, activity log and about", 0
panelSubs   DWORD OFFSET szSub0, OFFSET szSub1, OFFSET szSub2, OFFSET szSub3,
                  OFFSET szSub4, OFFSET szSub5, OFFSET szSub6

; ---- placeholder text until each screen is built ----
szSoon0 BYTE "Charts and summary cards arrive in build step 8", 0
szSoon1 BYTE "The course table arrives in build step 3", 0
szSoon2 BYTE "Grade tools arrive in build step 5", 0
szSoon3 BYTE "The smart planner arrives in build step 6", 0
szSoon4 BYTE "The Pomodoro timer arrives in build step 7", 0
szSoon5 BYTE "The deadline tracker arrives in build step 4", 0
szSoon6 BYTE "Settings and themes arrive in build step 10", 0
panelSoon   DWORD OFFSET szSoon0, OFFSET szSoon1, OFFSET szSoon2, OFFSET szSoon3,
                  OFFSET szSoon4, OFFSET szSoon5, OFFSET szSoon6

szBrandName     BYTE "Student Toolkit", 0
szBrandSub      BYTE "COAL Lab Project", 0
statusLeftBuf   BYTE 64 DUP(0)          ; "Logged in as aden"
statusRightBuf  BYTE 64 DUP(0)          ; version, or "Saved at 9:41 PM"
greetBuf        BYTE 64 DUP(0)          ; "Good evening, Aden"
szLoggedInAs    BYTE "Logged in as ", 0
szVersion       BYTE "Student Toolkit v1.0", 0
szMorning       BYTE "Good morning, ", 0
szAfternoon     BYTE "Good afternoon, ", 0
szEvening       BYTE "Good evening, ", 0

hNavBtn     DWORD PANEL_COUNT DUP(0)    ; sidebar button handles
hPanel      DWORD PANEL_COUNT DUP(0)    ; panel (screen) handles
activePanel DWORD PANEL_DASHBOARD
hoverNav    DWORD -1                    ; button under the mouse, -1 = none
oldBtnProc  DWORD 0                     ; Windows' own BUTTON handler

.code
;---------------------------------------------------------------------
; RegisterPanelClass - registers the window class used by all screens
;---------------------------------------------------------------------
RegisterPanelClass PROC
    LOCAL wc:WNDCLASSEX

    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.style, CS_HREDRAW OR CS_VREDRAW
    mov wc.lpfnWndProc, OFFSET PanelProc
    mov wc.cbClsExtra, 0
    mov wc.cbWndExtra, 0
    mov eax, hInstance
    mov wc.hInstance, eax
    mov wc.hIcon, NULL
    mov wc.hIconSm, NULL
    INVOKE LoadCursorA, NULL, IDC_ARROW
    mov wc.hCursor, eax
    mov wc.hbrBackground, NULL      ; we paint the background ourselves
    mov wc.lpszMenuName, NULL
    mov wc.lpszClassName, OFFSET szPanelClass
    INVOKE RegisterClassExA, ADDR wc
    ret
RegisterPanelClass ENDP

;---------------------------------------------------------------------
; CreateUI - creates the 7 sidebar buttons and the 7 screens.
; Called once from WM_CREATE of the main window.
;---------------------------------------------------------------------
CreateUI PROC USES ebx esi, hWnd:DWORD
    mov activePanel, PANEL_DASHBOARD    ; every login starts on the Dashboard
    mov hoverNav, -1
    xor esi, esi                    ; esi = index 0..6
CreateLoop:
    ; ---- sidebar button (owner-drawn: we draw it ourselves) ----
    mov ebx, IDC_NAV_FIRST
    add ebx, esi                    ; control ID = 1001 + index
    INVOKE CreateWindowExA, 0, ADDR szButtonClass, navLabels[esi*4],
           WS_CHILD OR WS_VISIBLE OR BS_OWNERDRAW,
           0, 0, 0, 0, hWnd, ebx, hInstance, NULL
    mov hNavBtn[esi*4], eax
    ; subclass: send the button's messages to NavBtnProc first
    INVOKE SetWindowLongA, eax, GWL_WNDPROC, OFFSET NavBtnProc
    mov oldBtnProc, eax

    ; ---- the screen (panel) for this button, hidden for now ----
    INVOKE CreateWindowExA, 0, ADDR szPanelClass, NULL,
           WS_CHILD OR WS_CLIPCHILDREN,
           0, 0, 0, 0, hWnd, NULL, hInstance, NULL
    mov hPanel[esi*4], eax
    INVOKE SetWindowLongA, eax, GWL_USERDATA, esi   ; panel remembers its index

    inc esi
    cmp esi, PANEL_COUNT
    jb  CreateLoop

    ; screens with their own buttons
    INVOKE CoursesInit, hPanel[PANEL_COURSES*4]
    INVOKE DeadlinesInit, hPanel[PANEL_DEADLINES*4]
    INVOKE GradesInit, hPanel[PANEL_GRADES*4]
    INVOKE PlannerInit, hPanel[PANEL_PLANNER*4]
    INVOKE TimerInit, hPanel[PANEL_TIMER*4]
    INVOKE DashboardInit, hPanel[PANEL_DASHBOARD*4]
    INVOKE SettingsInit, hPanel[PANEL_SETTINGS*4]

    ; show the first screen (Dashboard)
    mov eax, activePanel
    INVOKE ShowWindow, hPanel[eax*4], SW_SHOW
    ret
CreateUI ENDP

;---------------------------------------------------------------------
; LayoutUI - positions buttons and panels for the current window size.
; Called on WM_SIZE.
;---------------------------------------------------------------------
LayoutUI PROC USES ebx esi edi, hWnd:DWORD
    LOCAL rc:RECT, sideW:DWORD, statusH:DWORD, btnX:DWORD, btnW:DWORD,
          btnH:DWORD, btnStep:DWORD, panelW:DWORD, panelH:DWORD

    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE ScaleDpi, SIDEBAR_W
    mov sideW, eax
    INVOKE ScaleDpi, STATUS_H
    mov statusH, eax
    INVOKE ScaleDpi, NAV_MARGIN
    mov btnX, eax
    mov ebx, sideW
    sub ebx, eax
    sub ebx, eax
    mov btnW, ebx                   ; button width = sidebar - 2 margins
    INVOKE ScaleDpi, NAV_BTN_H
    mov btnH, eax
    INVOKE ScaleDpi, NAV_BTN_GAP
    add eax, btnH
    mov btnStep, eax                ; distance from one button to the next

    ; panel size = client area minus sidebar and status bar
    mov eax, rc.right
    sub eax, sideW
    mov panelW, eax
    mov eax, rc.bottom
    sub eax, statusH
    mov panelH, eax

    INVOKE ScaleDpi, NAV_TOP
    mov edi, eax                    ; edi = y of current button
    xor esi, esi
LayoutLoop:
    INVOKE MoveWindow, hNavBtn[esi*4], btnX, edi, btnW, btnH, TRUE
    INVOKE MoveWindow, hPanel[esi*4], sideW, 0, panelW, panelH, TRUE
    add edi, btnStep
    inc esi
    cmp esi, PANEL_COUNT
    jb  LayoutLoop

    INVOKE InvalidateRect, hWnd, NULL, FALSE
    ret
LayoutUI ENDP

;---------------------------------------------------------------------
; ShowPanel - switches to screen 'index'
;---------------------------------------------------------------------
ShowPanel PROC USES esi, index:DWORD
    mov eax, index
    cmp eax, activePanel
    je  Done                        ; already showing
    cmp eax, PANEL_COUNT
    jae Done                        ; invalid index

    mov esi, activePanel
    INVOKE ShowWindow, hPanel[esi*4], SW_HIDE
    mov esi, index
    mov activePanel, esi
    INVOKE ShowWindow, hPanel[esi*4], SW_SHOW

    ; redraw all sidebar buttons so the highlight moves
    xor esi, esi
RedrawLoop:
    INVOKE InvalidateRect, hNavBtn[esi*4], NULL, FALSE
    inc esi
    cmp esi, PANEL_COUNT
    jb  RedrawLoop
Done:
    ret
ShowPanel ENDP

;---------------------------------------------------------------------
; PaintMain - paints the parts of the main window not covered by
; child windows: the sidebar background with the logo, and the
; status bar.
;---------------------------------------------------------------------
PaintMain PROC USES ebx esi edi, hWnd:DWORD
    LOCAL ps:PAINTSTRUCT, rc:RECT, r:RECT, hdc:DWORD,
          sideW:DWORD, statusTop:DWORD, pad:DWORD

    INVOKE BeginPaint, hWnd, ADDR ps
    mov hdc, eax
    INVOKE GetClientRect, hWnd, ADDR rc
    INVOKE ScaleDpi, SIDEBAR_W
    mov sideW, eax
    INVOKE ScaleDpi, STATUS_H
    mov ebx, rc.bottom
    sub ebx, eax
    mov statusTop, ebx
    INVOKE ScaleDpi, 16
    mov pad, eax

    ; ---- sidebar background ----
    INVOKE SetRect, ADDR r, 0, 0, sideW, statusTop
    INVOKE FillSolid, hdc, ADDR r, curTheme.clrSidebar

    ; ---- logo: icon + app name + subtitle ----
    INVOKE ScaleDpi, 20
    mov esi, eax                    ; esi = left edge of logo
    INVOKE ScaleDpi, 24
    mov edi, eax                    ; edi = top of logo
    INVOKE ScaleDpi, 30
    lea ebx, [esi + eax]            ; right edge of icon box
    INVOKE ScaleDpi, 30
    add eax, edi
    INVOKE SetRect, ADDR r, esi, edi, ebx, eax
    INVOKE DrawGlyph, hdc, GLYPH_BRAND, ADDR r, hFontIconLg,
           curTheme.clrSideActText, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE

    INVOKE ScaleDpi, 36
    add esi, eax                    ; text starts right of the icon
    INVOKE ScaleDpi, 18
    lea ebx, [edi + eax]
    INVOKE SetRect, ADDR r, esi, edi, sideW, ebx
    sub r.top, 2
    INVOKE DrawTextIn, hdc, ADDR szBrandName, ADDR r, hFontBrand,
           curTheme.clrSideActText, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE ScaleDpi, 18
    lea ecx, [ebx + eax]
    INVOKE SetRect, ADDR r, esi, ebx, sideW, ecx
    INVOKE DrawTextIn, hdc, ADDR szBrandSub, ADDR r, hFontSmall,
           curTheme.clrSideText, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE

    ; ---- status bar: card colour with a thin top border ----
    INVOKE SetRect, ADDR r, 0, statusTop, rc.right, rc.bottom
    INVOKE FillSolid, hdc, ADDR r, curTheme.clrCard
    mov eax, statusTop
    inc eax
    INVOKE SetRect, ADDR r, 0, statusTop, rc.right, eax
    INVOKE FillSolid, hdc, ADDR r, curTheme.clrBorder

    mov eax, rc.right
    sub eax, pad
    INVOKE SetRect, ADDR r, pad, statusTop, eax, rc.bottom
    INVOKE DrawTextIn, hdc, ADDR statusLeftBuf, ADDR r, hFontSmall,
           curTheme.clrMuted, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    INVOKE DrawTextIn, hdc, ADDR statusRightBuf, ADDR r, hFontSmall,
           curTheme.clrMuted, DT_RIGHT OR DT_VCENTER OR DT_SINGLELINE

    INVOKE EndPaint, hWnd, ADDR ps
    ret
PaintMain ENDP

;---------------------------------------------------------------------
; DrawNavButton - draws one sidebar button (handles WM_DRAWITEM).
; Receives: pDis = address of a DRAWITEMSTRUCT
;   selected button : rounded highlight + small pill on the left
;   mouse over      : lighter rounded highlight
;   otherwise       : plain sidebar colour
;---------------------------------------------------------------------
DrawNavButton PROC USES ebx esi edi, pDis:DWORD
    LOCAL rc:RECT, r:RECT, hdc:DWORD, index:DWORD,
          textColor:DWORD, hFont:DWORD

    mov ebx, pDis
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).hDC
    mov hdc, eax
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).CtlID
    sub eax, IDC_NAV_FIRST
    mov index, eax

    ; copy the button rectangle
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).rcItem.left
    mov rc.left, eax
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).rcItem.top
    mov rc.top, eax
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).rcItem.right
    mov rc.right, eax
    mov eax, (DRAWITEMSTRUCT PTR [ebx]).rcItem.bottom
    mov rc.bottom, eax

    ; background = sidebar colour
    INVOKE FillSolid, hdc, ADDR rc, curTheme.clrSidebar

    mov eax, curTheme.clrSideText
    mov textColor, eax
    mov eax, hFontBody
    mov hFont, eax

    mov eax, index
    cmp eax, activePanel
    je  IsActive
    cmp eax, hoverNav
    je  IsHover
    jmp DrawContent

IsHover:
    INVOKE FillRound, hdc, rc.left, rc.top, rc.right, rc.bottom, 10,
           curTheme.clrSideHover, curTheme.clrSideHover
    jmp DrawContent

IsActive:
    INVOKE FillRound, hdc, rc.left, rc.top, rc.right, rc.bottom, 10,
           curTheme.clrSideActive, curTheme.clrSideActive
    ; small vertical pill on the left edge
    INVOKE ScaleDpi, 4
    mov esi, rc.left
    add esi, eax                    ; pill left
    INVOKE ScaleDpi, 3
    lea edi, [esi + eax]            ; pill right
    INVOKE ScaleDpi, 11
    mov ecx, rc.top
    add ecx, eax                    ; pill top
    mov edx, rc.bottom
    sub edx, eax                    ; pill bottom
    INVOKE FillRound, hdc, esi, ecx, edi, edx, 2,
           curTheme.clrSideActText, curTheme.clrSideActText
    mov eax, curTheme.clrSideActText
    mov textColor, eax
    mov eax, hFontBodyBold
    mov hFont, eax

DrawContent:
    ; icon
    INVOKE ScaleDpi, 16
    mov esi, rc.left
    add esi, eax
    INVOKE ScaleDpi, 24
    lea edi, [esi + eax]
    INVOKE SetRect, ADDR r, esi, rc.top, edi, rc.bottom
    mov ecx, index
    INVOKE DrawGlyph, hdc, navGlyphs[ecx*4], ADDR r, hFontIcon,
           textColor, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE

    ; label
    INVOKE ScaleDpi, 12
    add edi, eax
    INVOKE SetRect, ADDR r, edi, rc.top, rc.right, rc.bottom
    mov ecx, index
    INVOKE DrawTextIn, hdc, navLabels[ecx*4], ADDR r, hFont,
           textColor, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE
    ret
DrawNavButton ENDP

;---------------------------------------------------------------------
; NavBtnProc - extra handling for sidebar buttons (subclass):
;   hover highlight, hand cursor, no background flicker.
; Everything else goes to Windows' normal button handler.
;---------------------------------------------------------------------
NavBtnProc PROC USES ebx, hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL tme:TRACKMOUSEEVENT

    cmp uMsg, WM_MOUSEMOVE
    je  OnMouseMove
    cmp uMsg, WM_MOUSELEAVE
    je  OnMouseLeave
    cmp uMsg, WM_SETCURSOR
    je  OnSetCursor
    cmp uMsg, WM_ERASEBKGND
    je  OnErase
    jmp PassOn

OnMouseMove:
    INVOKE GetWindowLongA, hWnd, GWL_ID
    sub eax, IDC_NAV_FIRST          ; eax = this button's index
    cmp eax, hoverNav
    je  PassOn                      ; already highlighted
    mov ebx, hoverNav               ; old hover button
    mov hoverNav, eax
    cmp ebx, -1
    je  NoOldHover
    INVOKE InvalidateRect, hNavBtn[ebx*4], NULL, FALSE
NoOldHover:
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    ; ask Windows to send WM_MOUSELEAVE when the mouse leaves
    mov tme.cbSize, SIZEOF TRACKMOUSEEVENT
    mov tme.dwFlags, TME_LEAVE
    mov eax, hWnd
    mov tme.hwndTrack, eax
    mov tme.dwHoverTime, 0
    INVOKE TrackMouseEvent, ADDR tme
    jmp PassOn

OnMouseLeave:
    INVOKE GetWindowLongA, hWnd, GWL_ID
    sub eax, IDC_NAV_FIRST
    cmp eax, hoverNav
    jne PassOn
    mov hoverNav, -1
    INVOKE InvalidateRect, hWnd, NULL, FALSE
    jmp PassOn

OnSetCursor:
    INVOKE LoadCursorA, NULL, IDC_HAND
    INVOKE SetCursor, eax
    mov eax, TRUE
    ret

OnErase:
    mov eax, 1                      ; background is drawn in WM_DRAWITEM
    ret

PassOn:
    INVOKE CallWindowProcA, oldBtnProc, hWnd, uMsg, wParam, lParam
    ret
NavBtnProc ENDP

;---------------------------------------------------------------------
; PanelProc - message handler shared by all 7 screens
;---------------------------------------------------------------------
PanelProc PROC hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    cmp uMsg, WM_ERASEBKGND
    je  OnErase
    cmp uMsg, WM_PAINT
    je  OnPaint

    ; screens with their own controls get the message first
    INVOKE GetWindowLongA, hWnd, GWL_USERDATA
    cmp eax, PANEL_COURSES
    jne NotCourses
    INVOKE CoursesPanelMsg, hWnd, uMsg, wParam, lParam
    jmp CheckHandled
NotCourses:
    cmp eax, PANEL_DEADLINES
    jne NotDeadlines
    INVOKE DeadlinesPanelMsg, hWnd, uMsg, wParam, lParam
    jmp CheckHandled
NotDeadlines:
    cmp eax, PANEL_GRADES
    jne NotGrades
    INVOKE GradesPanelMsg, hWnd, uMsg, wParam, lParam
    jmp CheckHandled
NotGrades:
    cmp eax, PANEL_PLANNER
    jne NotPlanner
    INVOKE PlannerPanelMsg, hWnd, uMsg, wParam, lParam
    jmp CheckHandled
NotPlanner:
    cmp eax, PANEL_TIMER
    jne NotTimer
    INVOKE TimerPanelMsg, hWnd, uMsg, wParam, lParam
    jmp CheckHandled
NotTimer:
    cmp eax, PANEL_DASHBOARD
    jne NotDashboard
    INVOKE DashboardPanelMsg, hWnd, uMsg, wParam, lParam
    jmp CheckHandled
NotDashboard:
    cmp eax, PANEL_SETTINGS
    jne Default
    INVOKE SettingsPanelMsg, hWnd, uMsg, wParam, lParam
CheckHandled:
    cmp ecx, 0                      ; ecx = 1 -> handled, eax = result
    jne Handled
Default:
    INVOKE DefWindowProcA, hWnd, uMsg, wParam, lParam
Handled:
    ret
OnErase:
    mov eax, 1                      ; everything is painted in WM_PAINT
    ret
OnPaint:
    INVOKE PaintPanel, hWnd
    xor eax, eax
    ret
PanelProc ENDP

;---------------------------------------------------------------------
; PaintPanel - draws a screen: title, description and a card.
; Uses double buffering: everything is drawn on an off-screen bitmap
; first, then copied to the window in one step (no flicker).
;---------------------------------------------------------------------
PaintPanel PROC USES ebx esi edi, hWnd:DWORD
    LOCAL ps:PAINTSTRUCT, rc:RECT, r:RECT, memDC:DWORD, hBmp:DWORD,
          oldBmp:DWORD, index:DWORD, margin:DWORD

    INVOKE BeginPaint, hWnd, ADDR ps
    INVOKE GetClientRect, hWnd, ADDR rc
    cmp rc.right, 0
    je  Finish
    cmp rc.bottom, 0
    je  Finish

    ; ---- off-screen drawing surface ----
    INVOKE CreateCompatibleDC, ps.hdc
    mov memDC, eax
    INVOKE CreateCompatibleBitmap, ps.hdc, rc.right, rc.bottom
    mov hBmp, eax
    INVOKE SelectObject, memDC, hBmp
    mov oldBmp, eax

    INVOKE GetWindowLongA, hWnd, GWL_USERDATA
    mov index, eax
    INVOKE ScaleDpi, PAGE_MARGIN
    mov margin, eax

    ; background
    INVOKE FillSolid, memDC, ADDR rc, curTheme.clrBg

    ; title
    mov esi, rc.right
    sub esi, margin                 ; esi = right edge of content
    INVOKE ScaleDpi, 28
    mov edi, eax                    ; edi = top of title
    INVOKE ScaleDpi, 40
    lea ebx, [edi + eax]
    INVOKE SetRect, ADDR r, margin, edi, esi, ebx
    mov ecx, index
    mov edx, navLabels[ecx*4]       ; screen name as the title ...
    cmp ecx, PANEL_DASHBOARD
    jne @F
    mov edx, OFFSET greetBuf        ; ... except the Dashboard greets you
@@: INVOKE DrawTextIn, memDC, edx, ADDR r, hFontTitle,
           curTheme.clrText, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE

    ; description
    INVOKE ScaleDpi, 24
    lea edi, [ebx + eax]
    INVOKE SetRect, ADDR r, margin, ebx, esi, edi
    mov ecx, index
    INVOKE DrawTextIn, memDC, panelSubs[ecx*4], ADDR r, hFontBody,
           curTheme.clrMuted, DT_LEFT OR DT_VCENTER OR DT_SINGLELINE OR DT_END_ELLIPSIS

    ; the Courses screen draws its own table
    cmp index, PANEL_COURSES
    jne @F
    INVOKE PaintCourses, memDC, rc.right, rc.bottom
    jmp CopyToWindow
@@: cmp index, PANEL_DEADLINES
    jne @F
    INVOKE PaintDeadlines, memDC, rc.right, rc.bottom
    jmp CopyToWindow
@@: cmp index, PANEL_GRADES
    jne @F
    INVOKE PaintGrades, memDC, rc.right, rc.bottom
    jmp CopyToWindow
@@: cmp index, PANEL_PLANNER
    jne @F
    INVOKE PaintPlanner, memDC, rc.right, rc.bottom
    jmp CopyToWindow
@@: cmp index, PANEL_TIMER
    jne @F
    INVOKE PaintTimerPanel, memDC, rc.right, rc.bottom
    jmp CopyToWindow
@@: cmp index, PANEL_DASHBOARD
    jne @F
    INVOKE PaintDashboard, memDC, rc.right, rc.bottom
    jmp CopyToWindow
@@: cmp index, PANEL_SETTINGS
    jne Placeholder
    INVOKE PaintSettings, memDC, rc.right, rc.bottom
    jmp CopyToWindow

Placeholder:
    ; placeholder card
    INVOKE ScaleDpi, 28
    add edi, eax                    ; card top
    INVOKE ScaleDpi, 170
    lea ebx, [edi + eax]            ; card bottom
    INVOKE FillRound, memDC, margin, edi, esi, ebx, CARD_RADIUS,
           curTheme.clrCard, curTheme.clrBorder

    ; icon + text inside the card
    INVOKE ScaleDpi, 60
    lea ecx, [edi + eax]
    INVOKE SetRect, ADDR r, margin, edi, esi, ecx
    INVOKE ScaleDpi, 22
    add r.top, eax
    add r.bottom, eax
    mov ecx, index
    INVOKE DrawGlyph, memDC, navGlyphs[ecx*4], ADDR r, hFontIconLg,
           curTheme.clrMuted, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE
    mov eax, r.bottom
    mov r.top, eax
    INVOKE ScaleDpi, 30
    add eax, r.top
    mov r.bottom, eax
    mov ecx, index
    INVOKE DrawTextIn, memDC, panelSoon[ecx*4], ADDR r, hFontBody,
           curTheme.clrMuted, DT_CENTER OR DT_VCENTER OR DT_SINGLELINE

CopyToWindow:
    ; ---- copy the finished picture to the window ----
    INVOKE BitBlt, ps.hdc, 0, 0, rc.right, rc.bottom, memDC, 0, 0, SRCCOPY
    INVOKE SelectObject, memDC, oldBmp
    INVOKE DeleteObject, hBmp
    INVOKE DeleteDC, memDC

Finish:
    INVOKE EndPaint, hWnd, ADDR ps
    ret
PaintPanel ENDP

;---------------------------------------------------------------------
; BuildGreeting - fills greetBuf, statusLeftBuf and statusRightBuf for
; the student who just logged in, e.g. "Good evening, Aden"
;---------------------------------------------------------------------
BuildGreeting PROC USES ecx esi edi
    LOCAL sysTime:SYSTEMTIME, firstName[NAME_LEN]:BYTE

    ; part of the day from the clock
    INVOKE GetLocalTime, ADDR sysTime
    movzx eax, sysTime.wHour
    mov esi, OFFSET szMorning
    cmp eax, 12
    jb  HaveGreeting
    mov esi, OFFSET szAfternoon
    cmp eax, 17
    jb  HaveGreeting
    mov esi, OFFSET szEvening
HaveGreeting:
    INVOKE Str_copy, esi, ADDR greetBuf

    ; first word of the display name ("Aden Hussain" -> "Aden")
    mov esi, OFFSET userData.displayName
    lea edi, firstName
    mov ecx, NAME_LEN - 1
CopyName:
    mov al, [esi]
    cmp al, 0
    je  NameDone
    cmp al, ' '
    je  NameDone
    mov [edi], al
    inc esi
    inc edi
    loop CopyName
NameDone:
    mov BYTE PTR [edi], 0
    INVOKE StrAppend, ADDR greetBuf, ADDR firstName

    ; status bar texts
    INVOKE Str_copy, ADDR szLoggedInAs, ADDR statusLeftBuf
    INVOKE StrAppend, ADDR statusLeftBuf, ADDR userData.userName
    INVOKE Str_copy, ADDR szVersion, ADDR statusRightBuf
    ret
BuildGreeting ENDP

;---------------------------------------------------------------------
; SetStatusRight - changes the text on the right of the status bar
;---------------------------------------------------------------------
SetStatusRight PROC pText:DWORD
    INVOKE Str_copy, pText, ADDR statusRightBuf
    cmp hMainWnd, 0
    je  @F
    INVOKE InvalidateRect, hMainWnd, NULL, FALSE
@@: ret
SetStatusRight ENDP

END
