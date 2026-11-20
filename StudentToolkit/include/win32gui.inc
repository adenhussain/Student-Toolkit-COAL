;=====================================================================
; win32gui.inc  -  Windows GUI structures, constants and prototypes
;
; Irvine32.inc (via SmallWin.inc) already declares the console and
; file functions (CreateFileA, ReadFile, WriteFile, MessageBoxA,
; ExitProcess, GetLocalTime ...). This file adds everything needed
; for a real window: user32 (windows, messages, controls),
; gdi32 (drawing) and comctl32 (common controls).
;=====================================================================

;---------------------------------------------------------------------
; Structures
;---------------------------------------------------------------------
POINT STRUCT
    x       DWORD ?
    y       DWORD ?
POINT ENDS

RECT STRUCT
    left    DWORD ?
    top     DWORD ?
    right   DWORD ?
    bottom  DWORD ?
RECT ENDS

MSG STRUCT                      ; one message from the message queue
    hwnd    DWORD ?
    message DWORD ?
    wParam  DWORD ?
    lParam  DWORD ?
    time    DWORD ?
    pt      POINT <>
MSG ENDS

WNDCLASSEX STRUCT               ; describes a "kind" of window
    cbSize          DWORD ?
    style           DWORD ?
    lpfnWndProc     DWORD ?     ; address of the message handler
    cbClsExtra      DWORD ?
    cbWndExtra      DWORD ?
    hInstance       DWORD ?
    hIcon           DWORD ?
    hCursor         DWORD ?
    hbrBackground   DWORD ?
    lpszMenuName    DWORD ?
    lpszClassName   DWORD ?
    hIconSm         DWORD ?
WNDCLASSEX ENDS

PAINTSTRUCT STRUCT
    hdc         DWORD ?
    fErase      DWORD ?
    rcPaint     RECT <>
    fRestore    DWORD ?
    fIncUpdate  DWORD ?
    rgbReserved BYTE 32 DUP(?)
PAINTSTRUCT ENDS

DRAWITEMSTRUCT STRUCT           ; sent with WM_DRAWITEM for owner-drawn buttons
    CtlType     DWORD ?
    CtlID       DWORD ?
    itemID      DWORD ?
    itemAction  DWORD ?
    itemState   DWORD ?
    hwndItem    DWORD ?
    hDC         DWORD ?
    rcItem      RECT <>
    itemData    DWORD ?
DRAWITEMSTRUCT ENDS

MINMAXINFO STRUCT
    ptReserved      POINT <>
    ptMaxSize       POINT <>
    ptMaxPosition   POINT <>
    ptMinTrackSize  POINT <>
    ptMaxTrackSize  POINT <>
MINMAXINFO ENDS

TRACKMOUSEEVENT STRUCT
    cbSize      DWORD ?
    dwFlags     DWORD ?
    hwndTrack   DWORD ?
    dwHoverTime DWORD ?
TRACKMOUSEEVENT ENDS

INITCOMMONCONTROLSEX STRUCT
    dwSize  DWORD ?
    dwICC   DWORD ?
INITCOMMONCONTROLSEX ENDS

;---------------------------------------------------------------------
; Window styles and show commands
;---------------------------------------------------------------------
WS_OVERLAPPEDWINDOW = 00CF0000h
WS_CHILD            = 40000000h
WS_VISIBLE          = 10000000h
WS_CLIPCHILDREN     = 02000000h
WS_CLIPSIBLINGS     = 04000000h
CS_VREDRAW          = 0001h
CS_HREDRAW          = 0002h
CW_USEDEFAULT       = 80000000h
BS_OWNERDRAW        = 0000000Bh

SW_HIDE             = 0
SW_SHOWNORMAL       = 1
SW_SHOW             = 5

GWL_WNDPROC         = -4
GWL_ID              = -12
GWL_USERDATA        = -21

;---------------------------------------------------------------------
; Window messages
;---------------------------------------------------------------------
WM_CREATE           = 0001h
WM_DESTROY          = 0002h
WM_SIZE             = 0005h
WM_PAINT            = 000Fh
WM_CLOSE            = 0010h
WM_ERASEBKGND       = 0014h
WM_SETCURSOR        = 0020h
WM_GETMINMAXINFO    = 0024h
WM_DRAWITEM         = 002Bh
WM_COMMAND          = 0111h
WM_MOUSEMOVE        = 0200h
WM_MOUSELEAVE       = 02A3h

TME_LEAVE           = 00000002h
ODS_SELECTED        = 0001h

;---------------------------------------------------------------------
; Resources, cursors, system metrics
;---------------------------------------------------------------------
IDC_ARROW           = 32512
IDC_HAND            = 32649
IMAGE_ICON          = 1
SM_CXSCREEN         = 0
SM_CYSCREEN         = 1
SM_CXSMICON         = 49
SM_CYSMICON         = 50

;---------------------------------------------------------------------
; GDI (drawing) constants
;---------------------------------------------------------------------
TRANSPARENT         = 1
PS_SOLID            = 0
SRCCOPY             = 00CC0020h
LOGPIXELSY          = 90

FW_NORMAL           = 400
FW_SEMIBOLD         = 600
DEFAULT_CHARSET     = 1
OUT_DEFAULT_PRECIS  = 0
CLIP_DEFAULT_PRECIS = 0
CLEARTYPE_QUALITY   = 5
DEFAULT_PITCH       = 0

DT_LEFT             = 0000h
DT_CENTER           = 0001h
DT_RIGHT            = 0002h
DT_VCENTER          = 0004h
DT_WORDBREAK        = 0010h
DT_SINGLELINE       = 0020h
DT_NOPREFIX         = 0800h
DT_END_ELLIPSIS     = 8000h

RDW_INVALIDATE      = 0001h
RDW_ERASE           = 0004h
RDW_ALLCHILDREN     = 0080h
RDW_UPDATENOW       = 0100h

ICC_WIN95_CLASSES   = 000000FFh
ICC_BAR_CLASSES     = 00000004h

;---------------------------------------------------------------------
; user32.dll - windows, messages, controls
;---------------------------------------------------------------------
GetModuleHandleA    PROTO :DWORD
MulDiv              PROTO :DWORD, :DWORD, :DWORD
RegisterClassExA    PROTO :DWORD
CreateWindowExA     PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD,
                          :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DefWindowProcA      PROTO :DWORD, :DWORD, :DWORD, :DWORD
CallWindowProcA     PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DestroyWindow       PROTO :DWORD
ShowWindow          PROTO :DWORD, :DWORD
UpdateWindow        PROTO :DWORD
MoveWindow          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
GetMessageA         PROTO :DWORD, :DWORD, :DWORD, :DWORD
TranslateMessage    PROTO :DWORD
DispatchMessageA    PROTO :DWORD
PostQuitMessage     PROTO :DWORD
GetClientRect       PROTO :DWORD, :DWORD
InvalidateRect      PROTO :DWORD, :DWORD, :DWORD
RedrawWindow        PROTO :DWORD, :DWORD, :DWORD, :DWORD
BeginPaint          PROTO :DWORD, :DWORD
EndPaint            PROTO :DWORD, :DWORD
GetDC               PROTO :DWORD
ReleaseDC           PROTO :DWORD, :DWORD
FillRect            PROTO :DWORD, :DWORD, :DWORD
SetRect             PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DrawTextA           PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DrawTextW           PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
LoadIconA           PROTO :DWORD, :DWORD
LoadCursorA         PROTO :DWORD, :DWORD
LoadImageA          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
SetCursor           PROTO :DWORD
GetSystemMetrics    PROTO :DWORD
SetWindowLongA      PROTO :DWORD, :DWORD, :DWORD
GetWindowLongA      PROTO :DWORD, :DWORD
TrackMouseEvent     PROTO :DWORD

;---------------------------------------------------------------------
; gdi32.dll - drawing
;---------------------------------------------------------------------
CreateSolidBrush        PROTO :DWORD
CreatePen               PROTO :DWORD, :DWORD, :DWORD
SelectObject            PROTO :DWORD, :DWORD
DeleteObject            PROTO :DWORD
RoundRect               PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
SetBkMode               PROTO :DWORD, :DWORD
GetDeviceCaps           PROTO :DWORD, :DWORD
CreateCompatibleDC      PROTO :DWORD
CreateCompatibleBitmap  PROTO :DWORD, :DWORD, :DWORD
DeleteDC                PROTO :DWORD
BitBlt                  PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD,
                              :DWORD, :DWORD, :DWORD, :DWORD
CreateFontA             PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD,
                              :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD

; gdi32's SetTextColor has the same name as Irvine32's console
; SetTextColor procedure. To use both, the GDI version is called
; through its import pointer under the name GdiSetTextColor.
PROTO_2ARGS     TYPEDEF PROTO :DWORD, :DWORD
PTR_PROTO_2ARGS TYPEDEF PTR PROTO_2ARGS
EXTERNDEF _imp__SetTextColor@8:PTR_PROTO_2ARGS
GdiSetTextColor TEXTEQU <_imp__SetTextColor@8>

;---------------------------------------------------------------------
; comctl32.dll - common controls (tables, sliders, progress bars)
;---------------------------------------------------------------------
InitCommonControlsEx    PROTO :DWORD

;---------------------------------------------------------------------
; Added in build step 2: login window, text fields, files, shortcuts
;---------------------------------------------------------------------
WS_CAPTION          = 00C00000h
WS_SYSMENU          = 00080000h
WS_MINIMIZEBOX      = 00020000h
WS_TABSTOP          = 00010000h

ES_LOWERCASE        = 0010h     ; edit box turns typing into lowercase
ES_PASSWORD         = 0020h     ; edit box shows dots instead of text
ES_AUTOHSCROLL      = 0080h
ES_NUMBER           = 2000h     ; edit box accepts digits only

WM_SETFONT          = 0030h
WM_CTLCOLOREDIT     = 0133h
EM_LIMITTEXT        = 00C5h
EM_SETSEL           = 00B1h     ; select text in an edit box
EN_SETFOCUS         = 0100h     ; edit box got keyboard focus
EN_KILLFOCUS        = 0200h     ; edit box lost keyboard focus

ODS_FOCUS           = 0010h
SWP_NOMOVE          = 0002h
SWP_NOZORDER        = 0004h
INVALID_FILE_ATTRIBUTES = -1

GetModuleFileNameA  PROTO :DWORD, :DWORD, :DWORD
CreateDirectoryA    PROTO :DWORD, :DWORD
GetFileAttributesA  PROTO :DWORD
SendMessageA        PROTO :DWORD, :DWORD, :DWORD, :DWORD
GetWindowTextA      PROTO :DWORD, :DWORD, :DWORD
SetWindowTextA      PROTO :DWORD, :DWORD
SetFocus            PROTO :DWORD
SetWindowPos        PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
AdjustWindowRectEx  PROTO :DWORD, :DWORD, :DWORD, :DWORD
IsDialogMessageA    PROTO :DWORD, :DWORD
LoadAcceleratorsA   PROTO :DWORD, :DWORD
TranslateAcceleratorA PROTO :DWORD, :DWORD, :DWORD
MessageBeep         PROTO :DWORD
SetBkColor          PROTO :DWORD, :DWORD

;---------------------------------------------------------------------
; Added in build step 3: course table and course dialog
;---------------------------------------------------------------------
ES_UPPERCASE        = 0008h
WS_POPUP            = 80000000h
WM_LBUTTONDOWN      = 0201h
WM_MOUSEWHEEL       = 020Ah
HTCLIENT            = 1

GetWindowRect       PROTO :DWORD, :DWORD
EnableWindow        PROTO :DWORD, :DWORD
SetForegroundWindow PROTO :DWORD

;---------------------------------------------------------------------
; Added in build step 4: drop-down list (course picker), mouse wheel
;---------------------------------------------------------------------
CBS_DROPDOWNLIST    = 0003h
WS_VSCROLL          = 00200000h
CB_ADDSTRING        = 0143h
CB_GETCURSEL        = 0147h
CB_RESETCONTENT     = 014Bh
CB_SETCURSEL        = 014Eh
CB_SETITEMHEIGHT    = 0153h
WM_CTLCOLORLISTBOX  = 0134h
MF_STRING           = 0000h
MF_CHECKED          = 0008h
TPM_RETURNCMD       = 0100h

CreatePopupMenu     PROTO
AppendMenuA         PROTO :DWORD, :DWORD, :DWORD, :DWORD
TrackPopupMenu      PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DestroyMenu         PROTO :DWORD

;---------------------------------------------------------------------
; Added in build step 5: dragging sliders, animation timer
;---------------------------------------------------------------------
WM_LBUTTONUP        = 0202h
WM_TIMER            = 0113h
EN_CHANGE           = 0300h

SetCapture          PROTO :DWORD
ReleaseCapture      PROTO
SetTimer            PROTO :DWORD, :DWORD, :DWORD, :DWORD
KillTimer           PROTO :DWORD, :DWORD

;---------------------------------------------------------------------
; Added in build step 7: tray icon, notifications, mini timer, sounds
;---------------------------------------------------------------------
NOTIFYICONDATAA STRUCT
    nidSize         DWORD ?
    nidWnd          DWORD ?
    nidID           DWORD ?
    nidFlags        DWORD ?
    nidCallback     DWORD ?
    nidIcon         DWORD ?
    nidTip          BYTE 128 DUP(?)
    nidState        DWORD ?
    nidStateMask    DWORD ?
    nidInfo         BYTE 256 DUP(?)
    nidTimeout      DWORD ?
    nidInfoTitle    BYTE 64 DUP(?)
    nidInfoFlags    DWORD ?
    nidGuid         BYTE 16 DUP(?)
    nidBalloonIcon  DWORD ?
NOTIFYICONDATAA ENDS

NIM_ADD             = 0
NIM_MODIFY          = 1
NIM_DELETE          = 2
NIF_MESSAGE         = 1
NIF_ICON            = 2
NIF_TIP             = 4
NIF_INFO            = 10h
NIIF_INFO           = 1

WM_APP              = 8000h
WM_LBUTTONDBLCLK    = 0203h
WM_RBUTTONUP        = 0205h
WM_NCHITTEST        = 0084h
WM_NCLBUTTONDBLCLK  = 00A3h
HTCAPTION           = 2
WS_EX_TOPMOST       = 00000008h
WS_EX_TOOLWINDOW    = 00000080h
SW_RESTORE          = 9
TPM_RIGHTBUTTON     = 0002h
MF_SEPARATOR        = 0800h
FW_LIGHT            = 300

Shell_NotifyIconA   PROTO :DWORD, :DWORD
Beep                PROTO :DWORD, :DWORD
GetCursorPos        PROTO :DWORD
IsIconic            PROTO :DWORD
CreateRoundRectRgn  PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
SetWindowRgn        PROTO :DWORD, :DWORD, :DWORD
ScreenToClient      PROTO :DWORD, :DWORD

;---------------------------------------------------------------------
; Added in build step 8: charts (dashed lines, outlines, text width)
;---------------------------------------------------------------------
SIZEL STRUCT
    sx      DWORD ?
    sy      DWORD ?
SIZEL ENDS

PS_DASH             = 1
NULL_BRUSH          = 5

MoveToEx            PROTO :DWORD, :DWORD, :DWORD, :DWORD
LineTo              PROTO :DWORD, :DWORD, :DWORD
GetStockObject      PROTO :DWORD
GetTextExtentPoint32A PROTO :DWORD, :DWORD, :DWORD, :DWORD

;---------------------------------------------------------------------
; Added in build step 9: Save dialog, opening files in other programs
;---------------------------------------------------------------------
OPENFILENAMEA STRUCT
    ofnSize             DWORD ?
    ofnOwner            DWORD ?
    ofnInstance         DWORD ?
    ofnFilter           DWORD ?
    ofnCustomFilter     DWORD ?
    ofnMaxCustFilter    DWORD ?
    ofnFilterIndex      DWORD ?
    ofnFile             DWORD ?
    ofnMaxFile          DWORD ?
    ofnFileTitle        DWORD ?
    ofnMaxFileTitle     DWORD ?
    ofnInitialDir       DWORD ?
    ofnTitle            DWORD ?
    ofnFlags            DWORD ?
    ofnFileOffset       WORD ?
    ofnFileExtension    WORD ?
    ofnDefExt           DWORD ?
    ofnCustData         DWORD ?
    ofnHook             DWORD ?
    ofnTemplateName     DWORD ?
    ofnReserved         DWORD ?
    ofnReserved2        DWORD ?
    ofnFlagsEx          DWORD ?
OPENFILENAMEA ENDS

OFN_OVERWRITEPROMPT = 0002h
OFN_NOCHANGEDIR     = 0008h
OFN_PATHMUSTEXIST   = 0800h

GetSaveFileNameA    PROTO :DWORD
ShellExecuteA       PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD

;---------------------------------------------------------------------
; Added for Focus Guard: which window is in front, and whose is it
;---------------------------------------------------------------------
GetForegroundWindow     PROTO
GetWindowThreadProcessId PROTO :DWORD, :DWORD
GetCurrentProcessId     PROTO
