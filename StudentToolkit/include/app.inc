;=====================================================================
; app.inc  -  shared constants, structures and declarations
;             for every module of Student Toolkit
;
; Every .asm file starts with:
;       .386
;       .model flat, stdcall
;       option casemap:none
;       INCLUDE app.inc
;=====================================================================

INCLUDE Irvine32.inc            ; Kip Irvine's library (+ SmallWin.inc)
INCLUDE win32gui.inc            ; Windows GUI declarations

;---------------------------------------------------------------------
; RGBC(r, g, b)  ->  Windows COLORREF value
; Windows stores colours as 00BBGGRRh (blue first), so the web colour
; #A9C7E8 is written RGBC(0A9h, 0C7h, 0E8h) and becomes 00E8C7A9h.
;---------------------------------------------------------------------
RGBC MACRO r:REQ, g:REQ, b:REQ
    EXITM <((((b) AND 0FFh) SHL 16) OR (((g) AND 0FFh) SHL 8) OR ((r) AND 0FFh))>
ENDM

;---------------------------------------------------------------------
; Resource IDs (must match res\app.rc)
;---------------------------------------------------------------------
IDI_APPICON     = 101
IDR_MAINMENU    = 102

IDM_SAVE        = 201
IDM_EXPORT_XLS  = 202
IDM_EXPORT_CSV  = 203
IDM_EXPORT_TT   = 204
IDM_LOGOUT      = 205
IDM_EXIT        = 206
IDM_HELP        = 207
IDM_ABOUT       = 208

;---------------------------------------------------------------------
; Screens (panels) and sidebar buttons
;---------------------------------------------------------------------
PANEL_DASHBOARD = 0
PANEL_COURSES   = 1
PANEL_GRADES    = 2
PANEL_PLANNER   = 3
PANEL_TIMER     = 4
PANEL_DEADLINES = 5
PANEL_SETTINGS  = 6
PANEL_COUNT     = 7

IDC_NAV_FIRST   = 1001          ; sidebar buttons use IDs 1001..1007

;---------------------------------------------------------------------
; Layout sizes in pixels at 100% scaling (96 DPI).
; Every value goes through ScaleDpi so the app stays sharp on
; laptops running at 125% / 150% scaling.
;---------------------------------------------------------------------
SIDEBAR_W       = 200
NAV_TOP         = 84            ; first sidebar button starts here
NAV_BTN_H       = 40
NAV_BTN_GAP     = 4
NAV_MARGIN      = 12
STATUS_H        = 30
WIN_W           = 1120
WIN_H           = 720
WIN_MIN_W       = 960
WIN_MIN_H       = 620
PAGE_MARGIN     = 36
CARD_RADIUS     = 14

;---------------------------------------------------------------------
; Theme: one colour per part of the interface.
; Each theme in the theme table is one THEME record.
;---------------------------------------------------------------------
THEME STRUCT
    clrBg           DWORD ?     ; window background
    clrSidebar      DWORD ?     ; sidebar background
    clrSideHover    DWORD ?     ; sidebar button under the mouse
    clrSideActive   DWORD ?     ; selected sidebar button
    clrSideText     DWORD ?     ; sidebar text
    clrSideActText  DWORD ?     ; selected sidebar text
    clrCard         DWORD ?     ; cards / status bar
    clrBorder       DWORD ?     ; thin borders
    clrText         DWORD ?     ; main text
    clrMuted        DWORD ?     ; secondary text
    clrAccent       DWORD ?     ; main button
    clrAccentText   DWORD ?     ; text on main button
THEME ENDS

THEME_LAVENDER  = 0
THEME_SAGE      = 1
THEME_OCEAN     = 2
THEME_NORDIC    = 3
THEME_DARK      = 4
THEME_COUNT     = 5

; Status colours are the same in every theme so their meaning never changes
CLR_SAFE_BG     = RGBC(0CDh, 0EBh, 0D8h)    ; mint    #CDEBD8
CLR_SAFE_TX     = RGBC(02Eh, 06Bh, 047h)    ;         #2E6B47
CLR_WARN_BG     = RGBC(0FBh, 0E8h, 0C0h)    ; butter  #FBE8C0
CLR_WARN_TX     = RGBC(07Ah, 05Ah, 012h)    ;         #7A5A12
CLR_DANGER_BG   = RGBC(0F6h, 0CFh, 0CFh)    ; blush   #F6CFCF
CLR_DANGER_TX   = RGBC(08Ah, 03Ah, 03Ah)    ;         #8A3A3A

;---------------------------------------------------------------------
; Save file: one USERDATA record per student, stored encrypted in
; data\<username>.dat next to the program. Fixed-size records make
; saving and loading a single WriteToFile / ReadFromFile call.
;---------------------------------------------------------------------
MAX_COURSES     = 10
MAX_SEMESTERS   = 12
MAX_DEADLINES   = 20
MAX_STUDYLOG    = 50
NAME_LEN        = 24            ; display name / course name (incl. 0)
USER_LEN        = 16            ; username (incl. 0)
USER_MIN        = 3
PIN_MIN         = 4
PIN_MAX         = 6
DTITLE_LEN      = 32

FILE_MAGIC      = 314B5453h     ; the bytes "STK1"
FILE_VERSION    = 2             ; 2 = with checksum (version 1 files still load)
DEFAULT_LIMIT   = 480           ; daily study limit in minutes (8 h)

COURSE STRUCT
    cname           BYTE NAME_LEN DUP(?)
    credits         DWORD ?     ; 1 - 4
    marksObt        DWORD ?     ; marks so far  (x10, 23.5 -> 235)
    marksTotal      DWORD ?     ; out of        (x10)
    targetGrade     DWORD ?     ; index into the grade table
    classesHeld     DWORD ?
    classesAttended DWORD ?
    difficulty      DWORD ?     ; 1 - 5
    preparation     DWORD ?     ; 1 - 5 (1 = not started)
    sliderGrade     DWORD ?     ; grade chosen on the grade slider
    cReserved       DWORD 3 DUP(?)
COURSE ENDS

SEMESTER STRUCT
    semGpa          DWORD ?     ; GPA x100 (3.45 -> 345)
    semCredits      DWORD ?
SEMESTER ENDS

DEADLINE STRUCT
    dtitle          BYTE DTITLE_LEN DUP(?)
    kind            DWORD ?     ; 0 quiz, 1 assignment, 2 exam, 3 lab
    course          DWORD ?     ; course index, -1 = none
    dueDay          DWORD ?     ; day number
    isDone          DWORD ?
DEADLINE ENDS

STUDYLOG STRUCT
    logDay          DWORD ?
    logCourse       DWORD ?
    logMinutes      DWORD ?
STUDYLOG ENDS

USERDATA STRUCT
    magic           DWORD ?     ; FILE_MAGIC when decrypted correctly
    version         DWORD ?
    userName        BYTE USER_LEN DUP(?)
    displayName     BYTE NAME_LEN DUP(?)
    ; settings
    theme           DWORD ?
    dailyLimit      DWORD ?
    soundOn         DWORD ?
    ; academic data
    courseCount     DWORD ?
    courses         COURSE MAX_COURSES DUP(<>)
    semCount        DWORD ?
    semesters       SEMESTER MAX_SEMESTERS DUP(<>)
    deadlineCount   DWORD ?
    deadlines       DEADLINE MAX_DEADLINES DUP(<>)
    ; study tracking
    logCount        DWORD ?
    studyLog        STUDYLOG MAX_STUDYLOG DUP(<>)
    streakCurrent   DWORD ?
    streakBest      DWORD ?
    lastStudyDay    DWORD ?
    totalMinutes    DWORD ?
    pomodoros       DWORD ?
    badges          DWORD ?     ; one bit per badge
    targetCgpa      DWORD ?     ; goal CGPA x100 (0 = not set)  - step 5
    planMinutes     DWORD ?     ; study minutes per day (0 = default) - step 6
    planDays        DWORD ?     ; days in the timetable (0 = default)
    checksum        DWORD ?     ; FNV-1a of the record (tamper check) - v2
    focusGuardOff   DWORD ?     ; 1 = Focus Guard switched off
    lastFocusScore  DWORD ?     ; focus score of the last session (0 = none)
    udReserved      DWORD 26 DUP(?)
USERDATA ENDS

; results of LoadUser / CreateUser
ACC_OK          = 0
ACC_NO_USER     = 1
ACC_BAD_PIN     = 2
ACC_BAD_FILE    = 3
ACC_EXISTS      = 4
ACC_IO_ERROR    = 5
ACC_TAMPERED    = 6             ; checksum does not match

; pastel button styles
BTN_PRIMARY     = 0             ; filled accent colour
BTN_LINK        = 1             ; text only
BTN_SECONDARY   = 2             ; outlined

; resource IDs added in step 2
IDR_ACCEL       = 103

;---------------------------------------------------------------------
; Shared variables (each is defined in exactly one module)
;---------------------------------------------------------------------
EXTERNDEF userData:USERDATA     ; data.asm
EXTERNDEF hLoginWnd:DWORD       ; login.asm
EXTERNDEF greetBuf:BYTE         ; ui.asm
EXTERNDEF statusLeftBuf:BYTE    ; ui.asm
EXTERNDEF statusRightBuf:BYTE   ; ui.asm
EXTERNDEF hFontLogo:DWORD       ; gfx.asm
EXTERNDEF hInstance:DWORD       ; main.asm
EXTERNDEF hMainWnd:DWORD        ; main.asm
EXTERNDEF curTheme:THEME        ; theme.asm
EXTERNDEF themeIndex:DWORD      ; theme.asm
EXTERNDEF screenDpi:DWORD       ; gfx.asm
EXTERNDEF hFontBody:DWORD       ; gfx.asm
EXTERNDEF hFontBodyBold:DWORD
EXTERNDEF hFontSmall:DWORD
EXTERNDEF hFontTitle:DWORD
EXTERNDEF hFontBrand:DWORD
EXTERNDEF hFontIcon:DWORD
EXTERNDEF hFontIconLg:DWORD

;---------------------------------------------------------------------
; Procedures shared between modules
;---------------------------------------------------------------------
; theme.asm
SetTheme        PROTO :DWORD

; gfx.asm
InitDpi         PROTO
ScaleDpi        PROTO :DWORD
CreateAppFonts  PROTO
DeleteAppFonts  PROTO
FillSolid       PROTO :DWORD, :DWORD, :DWORD
FillRound       PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DrawTextIn      PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DrawGlyph       PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD

; ui.asm
RegisterPanelClass PROTO
CreateUI        PROTO :DWORD
LayoutUI        PROTO :DWORD
ShowPanel       PROTO :DWORD
PaintMain       PROTO :DWORD
DrawNavButton   PROTO :DWORD
BuildGreeting   PROTO
SetStatusRight  PROTO :DWORD

; main.asm
StartMainWindow PROTO

; data.asm
InitDataDir     PROTO
LoadUser        PROTO :DWORD, :DWORD
CreateUser      PROTO :DWORD, :DWORD, :DWORD
SaveUser        PROTO
ChangePin       PROTO :DWORD, :DWORD
ClearUser       PROTO

; controls.asm
StrAppend           PROTO :DWORD, :DWORD
DarkenColor         PROTO :DWORD, :DWORD
CreatePastelButton  PROTO :DWORD, :DWORD, :DWORD, :DWORD
DrawPastelButton    PROTO :DWORD, :DWORD
CreateField         PROTO :DWORD, :DWORD, :DWORD, :DWORD
DrawFieldBox        PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD

; login.asm
RegisterLoginClass  PROTO
ShowLoginWindow     PROTO

;---------------------------------------------------------------------
; Added in build step 3: courses
;---------------------------------------------------------------------
GRADE_COUNT     = 12
ATTEND_MIN      = 80            ; minimum attendance % to sit the final
ATTEND_WARN     = 85            ; below this the chip turns yellow
BTN_DANGER_LINK = 3             ; red text-only button (Delete)

EXTERNDEF hActiveDialog:DWORD   ; main.asm - window that gets Tab/Enter handling
EXTERNDEF gradeGP:DWORD         ; grades_table.asm
EXTERNDEF gradeMinPct:DWORD

; main.asm
SaveWithStatus  PROTO

; grades_table.asm
GradeName       PROTO :DWORD
ParseGrade      PROTO :DWORD

; numbers.asm
ParseUInt       PROTO :DWORD
ParseTenths     PROTO :DWORD
FormatTenths    PROTO :DWORD, :DWORD
FormatUInt      PROTO :DWORD, :DWORD

; courses.asm
CoursesInit     PROTO :DWORD
PaintCourses    PROTO :DWORD, :DWORD, :DWORD
CoursesPanelMsg PROTO :DWORD, :DWORD, :DWORD, :DWORD
CoursesChanged  PROTO
AttendanceInfo  PROTO :DWORD

; course_dialog.asm
RegisterCourseDialog PROTO
OpenCourseDialog     PROTO :DWORD

;---------------------------------------------------------------------
; Added in build step 4: deadlines
;---------------------------------------------------------------------
BTN_CHIP        = 4             ; one choice of a group, can be selected
BTN_PICKER      = 5             ; shows a choice, opens a menu (with a down arrow)
DL_QUIZ         = 0             ; deadline kinds
DL_ASSIGNMENT   = 1
DL_EXAM         = 2
DL_LAB          = 3
DL_KIND_COUNT   = 4
NO_DATE         = 0FFFFFh       ; dueDay of a deadline without a date
                                ; (largest day number: sorts after dated ones)

; controls.asm
SetChipSelected PROTO :DWORD, :DWORD

; dates.asm
DateToDay       PROTO :DWORD, :DWORD, :DWORD
DayToDate       PROTO :DWORD
TodayDay        PROTO
FormatDateShort PROTO :DWORD, :DWORD
FormatDateInput PROTO :DWORD, :DWORD
ParseDate       PROTO :DWORD

; deadlines.asm
DeadlinesInit   PROTO :DWORD
PaintDeadlines  PROTO :DWORD, :DWORD, :DWORD
DeadlinesPanelMsg PROTO :DWORD, :DWORD, :DWORD, :DWORD
DeadlinesChanged PROTO
SortDeadlines   PROTO
CourseDeleted   PROTO :DWORD
EXTERNDEF kindNames:DWORD       ; deadlines.asm - "Quiz", "Assignment" ...

; deadline_dialog.asm
RegisterDeadlineDialog PROTO
OpenDeadlineDialog     PROTO :DWORD

; pin_dialog.asm (Change PIN popup) + login.asm helper
RegisterPinDialog      PROTO
OpenPinDialog          PROTO
IsValidPin             PROTO :DWORD

;---------------------------------------------------------------------
; Added in build step 5: grades
;---------------------------------------------------------------------
GRADE_D         = 10            ; index of grade D in the grade table
GRADE_APLUS     = 0             ; index of grade A+

; numbers.asm
ParseFixed2     PROTO :DWORD
FormatFixed2    PROTO :DWORD, :DWORD

; grade_calc.asm
CalcPast        PROTO
CalcSemester    PROTO
CurrentCgpa     PROTO
NewCgpa         PROTO
RequiredGpa     PROTO
GpaZone         PROTO :DWORD
MarksNeeded     PROTO :DWORD, :DWORD
SolveGrades     PROTO
EXTERNDEF solveGrade:DWORD      ; result of SolveGrades, one per course
EXTERNDEF solveGpa:DWORD

; grades.asm
GradesInit      PROTO :DWORD
PaintGrades     PROTO :DWORD, :DWORD, :DWORD
GradesPanelMsg  PROTO :DWORD, :DWORD, :DWORD, :DWORD

;---------------------------------------------------------------------
; Added in build step 6: smart planner
;---------------------------------------------------------------------
POMODORO_MIN    = 25            ; one study block
MAX_PLAN_DAYS   = 14
DEFAULT_PLAN_MIN = 240          ; 4 hours a day
DEFAULT_PLAN_DAYS = 7

; planner.asm
PlannerInit     PROTO :DWORD
PaintPlanner    PROTO :DWORD, :DWORD, :DWORD
PlannerPanelMsg PROTO :DWORD, :DWORD, :DWORD, :DWORD
BuildPlan       PROTO
EXTERNDEF planGrid:BYTE         ; blocks per day per course [day*10 + course]
EXTERNDEF subjectBg:DWORD       ; one pastel colour per course
EXTERNDEF subjectTx:DWORD

;---------------------------------------------------------------------
; Added in build step 7: Pomodoro timer, tray, streaks and badges
;---------------------------------------------------------------------
WM_TRAY         = WM_APP + 1    ; message the tray icon sends us
FOCUS_SECONDS   = 25 * 60
SHORT_SECONDS   = 5 * 60
LONG_SECONDS    = 15 * 60
TM_FOCUS        = 0             ; timer modes
TM_SHORT        = 1
TM_LONG         = 2
BADGE_COUNT     = 8
CHIME_DONE      = 0
CHIME_BREAK     = 1
CHIME_BADGE     = 2

EXTERNDEF hFontHuge:DWORD       ; gfx.asm  - the big 25:00
EXTERNDEF tmRunning:DWORD       ; pomodoro.asm
EXTERNDEF badgeNames:DWORD      ; stats.asm

; stats.asm
LogStudy        PROTO :DWORD, :DWORD
MinutesToday    PROTO :DWORD
UpdateStreak    PROTO
CheckBadges     PROTO
CurrentStreak   PROTO

; tray.asm
TrayAdd         PROTO :DWORD
TrayRemove      PROTO
TrayNotify      PROTO :DWORD, :DWORD
TrayCallback    PROTO :DWORD, :DWORD
PlayChime       PROTO :DWORD
RestoreMain     PROTO
NotifyDueDeadlines PROTO

; pomodoro.asm
TimerInit       PROTO :DWORD
PaintTimerPanel PROTO :DWORD, :DWORD, :DWORD
TimerPanelMsg   PROTO :DWORD, :DWORD, :DWORD, :DWORD
TimerStartPause PROTO
TimerStop       PROTO
FormatTimeLeft  PROTO :DWORD
TimerCourseName PROTO

; planner.asm (step 8 additions)
EXTERNDEF doneToday:DWORD       ; Pomodoros finished today, per course
PlanNextCourse  PROTO           ; course to study next today, or -1

; pomodoro.asm (step 8 addition)
SetTimerCourse  PROTO :DWORD
SetTimerMode    PROTO :DWORD

; dashboard.asm
DashboardInit   PROTO :DWORD
PaintDashboard  PROTO :DWORD, :DWORD, :DWORD
DashboardPanelMsg PROTO :DWORD, :DWORD, :DWORD, :DWORD

; gfx.asm (step 8 additions)
DashedLine      PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
OutlineRound    PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
TextWidth       PROTO :DWORD, :DWORD, :DWORD

;---------------------------------------------------------------------
; Added in build step 9: exports and activity log
;---------------------------------------------------------------------
IDM_VIEWLOG     = 209

EXTERNDEF dayOrder:BYTE         ; planner.asm
EXTERNDEF dayCount:BYTE
EXTERNDEF examDay:DWORD
EXTERNDEF totalBlocks:DWORD
PlanMinutes     PROTO
PlanDays        PROTO
FormatMinutes   PROTO :DWORD, :DWORD

; activity.asm
LogEvent        PROTO :DWORD
LogEventFmt     PROTO :DWORD, :DWORD
OpenActivityLog PROTO

; export.asm
ExportExcel     PROTO
ExportCsv       PROTO
ExportTimetable PROTO

;---------------------------------------------------------------------
; Added in build step 10: splash, settings, shared theme brush
;---------------------------------------------------------------------
EXTERNDEF hCardBrush:DWORD      ; theme.asm - brush in the card colour

; splash.asm
ShowSplash      PROTO

; settings.asm
SettingsInit    PROTO :DWORD
PaintSettings   PROTO :DWORD, :DWORD, :DWORD
SettingsPanelMsg PROTO :DWORD, :DWORD, :DWORD, :DWORD

;---------------------------------------------------------------------
; Added after v1.0: Focus Guard, finish semester, tamper detection
;---------------------------------------------------------------------
EXTERNDEF tmRemaining:DWORD     ; pomodoro.asm
EXTERNDEF fgCount:DWORD         ; focus_guard.asm - distractions so far
FocusReset      PROTO
FocusCheck      PROTO
FocusScore      PROTO

; mini_timer.asm
RegisterMiniTimer PROTO
ToggleMiniTimer PROTO
CloseMiniTimer  PROTO
RefreshMiniTimer PROTO
