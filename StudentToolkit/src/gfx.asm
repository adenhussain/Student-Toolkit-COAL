;=====================================================================
; gfx.asm  -  drawing helpers shared by every screen
;
;   InitDpi / ScaleDpi   keep sizes correct at 125% / 150% scaling
;   CreateAppFonts       Segoe UI text fonts + Segoe MDL2 icon font
;   FillSolid            fill a rectangle with one colour
;   FillRound            rounded rectangle (cards, buttons)
;   DrawTextIn           draw a string inside a rectangle
;   DrawGlyph            draw one icon from the Segoe MDL2 icon font
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

.data
screenDpi       DWORD 96        ; 96 = 100% scaling

hFontBody       DWORD 0
hFontBodyBold   DWORD 0
hFontSmall      DWORD 0
hFontTitle      DWORD 0
hFontBrand      DWORD 0
hFontIcon       DWORD 0
hFontIconLg     DWORD 0
hFontLogo       DWORD 0
hFontHuge       DWORD 0

szFontUI        BYTE "Segoe UI", 0
szFontIcons     BYTE "Segoe MDL2 Assets", 0      ; built-in Windows icon font

.code
;---------------------------------------------------------------------
; InitDpi - reads the screen's DPI (96 at 100%, 120 at 125%, ...)
;---------------------------------------------------------------------
InitDpi PROC USES ebx
    INVOKE GetDC, NULL
    mov ebx, eax
    INVOKE GetDeviceCaps, ebx, LOGPIXELSY
    mov screenDpi, eax
    INVOKE ReleaseDC, NULL, ebx
    ret
InitDpi ENDP

;---------------------------------------------------------------------
; ScaleDpi - converts a 100%-scale pixel size to the real screen
; Returns: EAX = value * screenDpi / 96  (ECX, EDX preserved)
;---------------------------------------------------------------------
ScaleDpi PROC USES ecx edx, value:DWORD
    INVOKE MulDiv, value, screenDpi, 96
    ret
ScaleDpi ENDP

;---------------------------------------------------------------------
; MakeFont - creates a font of 'pixels' height (at 100% scale)
; Returns: EAX = font handle
;---------------------------------------------------------------------
MakeFont PROC pixels:DWORD, weight:DWORD, faceName:DWORD
    INVOKE ScaleDpi, pixels
    neg eax                         ; negative height = character height
    INVOKE CreateFontA, eax, 0, 0, 0, weight, 0, 0, 0,
           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
           CLEARTYPE_QUALITY, DEFAULT_PITCH, faceName
    ret
MakeFont ENDP

;---------------------------------------------------------------------
; CreateAppFonts / DeleteAppFonts
;---------------------------------------------------------------------
CreateAppFonts PROC
    INVOKE MakeFont, 15, FW_NORMAL,   ADDR szFontUI
    mov hFontBody, eax
    INVOKE MakeFont, 15, FW_SEMIBOLD, ADDR szFontUI
    mov hFontBodyBold, eax
    INVOKE MakeFont, 13, FW_NORMAL,   ADDR szFontUI
    mov hFontSmall, eax
    INVOKE MakeFont, 28, FW_SEMIBOLD, ADDR szFontUI
    mov hFontTitle, eax
    INVOKE MakeFont, 17, FW_SEMIBOLD, ADDR szFontUI
    mov hFontBrand, eax
    INVOKE MakeFont, 16, FW_NORMAL,   ADDR szFontIcons
    mov hFontIcon, eax
    INVOKE MakeFont, 22, FW_NORMAL,   ADDR szFontIcons
    mov hFontIconLg, eax
    INVOKE MakeFont, 40, FW_NORMAL,   ADDR szFontIcons
    mov hFontLogo, eax
    INVOKE MakeFont, 84, FW_LIGHT,    ADDR szFontUI
    mov hFontHuge, eax
    ret
CreateAppFonts ENDP

DeleteAppFonts PROC
    INVOKE DeleteObject, hFontBody
    INVOKE DeleteObject, hFontBodyBold
    INVOKE DeleteObject, hFontSmall
    INVOKE DeleteObject, hFontTitle
    INVOKE DeleteObject, hFontBrand
    INVOKE DeleteObject, hFontIcon
    INVOKE DeleteObject, hFontIconLg
    INVOKE DeleteObject, hFontLogo
    INVOKE DeleteObject, hFontHuge
    ret
DeleteAppFonts ENDP

;---------------------------------------------------------------------
; FillSolid - fills the rectangle at pRect with one colour
;---------------------------------------------------------------------
FillSolid PROC USES ebx, hdc:DWORD, pRect:DWORD, color:DWORD
    INVOKE CreateSolidBrush, color
    mov ebx, eax
    INVOKE FillRect, hdc, pRect, ebx
    INVOKE DeleteObject, ebx
    ret
FillSolid ENDP

;---------------------------------------------------------------------
; FillRound - rounded rectangle with a fill colour and a 1px border.
; radius is given at 100% scale; coordinates are real pixels.
;---------------------------------------------------------------------
FillRound PROC USES ebx esi edi, hdc:DWORD, x1:DWORD, y1:DWORD, x2:DWORD,
               y2:DWORD, radius:DWORD, fillColor:DWORD, borderColor:DWORD
    LOCAL oldBrush:DWORD, oldPen:DWORD

    INVOKE CreateSolidBrush, fillColor
    mov ebx, eax
    INVOKE CreatePen, PS_SOLID, 1, borderColor
    mov esi, eax
    INVOKE SelectObject, hdc, ebx
    mov oldBrush, eax
    INVOKE SelectObject, hdc, esi
    mov oldPen, eax

    INVOKE ScaleDpi, radius
    shl eax, 1                      ; RoundRect wants the corner diameter
    mov edi, eax
    INVOKE RoundRect, hdc, x1, y1, x2, y2, edi, edi

    INVOKE SelectObject, hdc, oldBrush
    INVOKE SelectObject, hdc, oldPen
    INVOKE DeleteObject, ebx
    INVOKE DeleteObject, esi
    ret
FillRound ENDP

;---------------------------------------------------------------------
; DrawTextIn - draws a zero-terminated string inside a rectangle
; flags: DT_LEFT / DT_CENTER / DT_RIGHT, DT_VCENTER, DT_SINGLELINE ...
;---------------------------------------------------------------------
DrawTextIn PROC USES ebx, hdc:DWORD, pText:DWORD, pRect:DWORD,
                hFont:DWORD, color:DWORD, flags:DWORD
    INVOKE SelectObject, hdc, hFont
    mov ebx, eax                    ; remember the old font
    INVOKE SetBkMode, hdc, TRANSPARENT
    INVOKE GdiSetTextColor, hdc, color
    mov eax, flags
    or  eax, DT_NOPREFIX            ; draw '&' as a normal character
    INVOKE DrawTextA, hdc, pText, -1, pRect, eax
    INVOKE SelectObject, hdc, ebx
    ret
DrawTextIn ENDP

;---------------------------------------------------------------------
; DrawGlyph - draws one icon character from the Segoe MDL2 font.
; glyph is the icon's Unicode code, e.g. 0E80Fh = home
;---------------------------------------------------------------------
DrawGlyph PROC USES ebx, hdc:DWORD, glyph:DWORD, pRect:DWORD,
               hFont:DWORD, color:DWORD, flags:DWORD
    LOCAL wideChar[2]:WORD

    mov eax, glyph
    mov wideChar[0], ax
    mov wideChar[2], 0
    INVOKE SelectObject, hdc, hFont
    mov ebx, eax
    INVOKE SetBkMode, hdc, TRANSPARENT
    INVOKE GdiSetTextColor, hdc, color
    INVOKE DrawTextW, hdc, ADDR wideChar, 1, pRect, flags
    INVOKE SelectObject, hdc, ebx
    ret
DrawGlyph ENDP

;---------------------------------------------------------------------
; DashedLine - dashed line from (x1,y1) to (x2,y2)   (chart target line)
;---------------------------------------------------------------------
DashedLine PROC USES ebx esi, hdc:DWORD, x1:DWORD, y1:DWORD, x2:DWORD, y2:DWORD, color:DWORD
    INVOKE CreatePen, PS_DASH, 1, color
    mov ebx, eax
    INVOKE SelectObject, hdc, ebx
    mov esi, eax
    INVOKE SetBkMode, hdc, TRANSPARENT  ; gaps show the background
    INVOKE MoveToEx, hdc, x1, y1, NULL
    INVOKE LineTo, hdc, x2, y2
    INVOKE SelectObject, hdc, esi
    INVOKE DeleteObject, ebx
    ret
DashedLine ENDP

;---------------------------------------------------------------------
; OutlineRound - rounded rectangle with a dashed border, no fill
; (the "Next semester" bar of the GPA chart)
;---------------------------------------------------------------------
OutlineRound PROC USES ebx esi edi, hdc:DWORD, x1:DWORD, y1:DWORD, x2:DWORD,
                  y2:DWORD, radius:DWORD, color:DWORD
    LOCAL oldBrush:DWORD
    INVOKE CreatePen, PS_DASH, 1, color
    mov ebx, eax
    INVOKE SelectObject, hdc, ebx
    mov esi, eax
    INVOKE GetStockObject, NULL_BRUSH   ; inside stays see-through
    INVOKE SelectObject, hdc, eax
    mov oldBrush, eax
    INVOKE SetBkMode, hdc, TRANSPARENT
    INVOKE ScaleDpi, radius
    shl eax, 1
    mov edi, eax
    INVOKE RoundRect, hdc, x1, y1, x2, y2, edi, edi
    INVOKE SelectObject, hdc, oldBrush
    INVOKE SelectObject, hdc, esi
    INVOKE DeleteObject, ebx
    ret
OutlineRound ENDP

;---------------------------------------------------------------------
; TextWidth - width in pixels of a string in a font
;---------------------------------------------------------------------
TextWidth PROC USES ebx, hdc:DWORD, pText:DWORD, hFont:DWORD
    LOCAL sz:SIZEL
    INVOKE SelectObject, hdc, hFont
    mov ebx, eax
    INVOKE Str_length, pText
    mov ecx, eax                    ; (ADDR sz below uses EAX)
    INVOKE GetTextExtentPoint32A, hdc, pText, ecx, ADDR sz
    INVOKE SelectObject, hdc, ebx
    mov eax, sz.sx
    ret
TextWidth ENDP

END
