;=====================================================================
; theme.asm  -  colour themes
;
; All colours of the app live in one table: one THEME record per
; theme. SetTheme copies the chosen record into curTheme, and all
; drawing code reads its colours from curTheme. Switching theme is
; therefore just "copy a different row and repaint".
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

.data
; Each theme = 12 colours in the order of the THEME structure
themeTable LABEL THEME
; 0 - Lavender mist (default)
    DWORD RGBC(0F7h,0F5h,0F2h)   ; bg           #F7F5F2
    DWORD RGBC(0EAh,0E6h,0F5h)   ; sidebar      #EAE6F5
    DWORD RGBC(0E2h,0DCh,0F2h)   ; hover        #E2DCF2
    DWORD RGBC(0D9h,0D2h,0F0h)   ; active       #D9D2F0
    DWORD RGBC(05Eh,058h,080h)   ; side text    #5E5880
    DWORD RGBC(04Ah,043h,070h)   ; active text  #4A4370
    DWORD RGBC(0FFh,0FFh,0FFh)   ; card         #FFFFFF
    DWORD RGBC(0E6h,0E2h,0ECh)   ; border       #E6E2EC
    DWORD RGBC(03Ah,03Ah,04Ah)   ; text         #3A3A4A
    DWORD RGBC(07Ah,07Ah,08Ch)   ; muted        #7A7A8C
    DWORD RGBC(0A9h,0C7h,0E8h)   ; accent       #A9C7E8
    DWORD RGBC(02Fh,04Ah,066h)   ; accent text  #2F4A66
; 1 - Sage and sand
    DWORD RGBC(0F6h,0F4h,0EEh)   ; bg           #F6F4EE
    DWORD RGBC(0E3h,0EAh,0DFh)   ; sidebar      #E3EADF
    DWORD RGBC(0D9h,0E3h,0D3h)   ; hover        #D9E3D3
    DWORD RGBC(0CFh,0DCh,0C8h)   ; active       #CFDCC8
    DWORD RGBC(055h,068h,04Fh)   ; side text    #55684F
    DWORD RGBC(03Fh,056h,038h)   ; active text  #3F5638
    DWORD RGBC(0FFh,0FEh,0FBh)   ; card         #FFFEFB
    DWORD RGBC(0E4h,0E2h,0D8h)   ; border       #E4E2D8
    DWORD RGBC(03Bh,03Dh,036h)   ; text         #3B3D36
    DWORD RGBC(07Dh,07Fh,074h)   ; muted        #7D7F74
    DWORD RGBC(0B9h,0D3h,0B0h)   ; accent       #B9D3B0
    DWORD RGBC(034h,04Ah,02Eh)   ; accent text  #344A2E
; 2 - Ocean breeze
    DWORD RGBC(0F3h,0F7h,0F8h)   ; bg           #F3F7F8
    DWORD RGBC(0DDh,0EEh,0F1h)   ; sidebar      #DDEEF1
    DWORD RGBC(0D0h,0E8h,0ECh)   ; hover        #D0E8EC
    DWORD RGBC(0C4h,0E2h,0E8h)   ; active       #C4E2E8
    DWORD RGBC(03Dh,06Ah,073h)   ; side text    #3D6A73
    DWORD RGBC(01Fh,055h,060h)   ; active text  #1F5560
    DWORD RGBC(0FFh,0FFh,0FFh)   ; card         #FFFFFF
    DWORD RGBC(0DCh,0E7h,0EAh)   ; border       #DCE7EA
    DWORD RGBC(02Fh,03Bh,040h)   ; text         #2F3B40
    DWORD RGBC(073h,083h,089h)   ; muted        #738389
    DWORD RGBC(09Fh,0D3h,0DCh)   ; accent       #9FD3DC
    DWORD RGBC(01Dh,04Eh,057h)   ; accent text  #1D4E57
; 3 - Nordic frost
    DWORD RGBC(0F5h,0F6h,0F8h)   ; bg           #F5F6F8
    DWORD RGBC(0E4h,0E8h,0EFh)   ; sidebar      #E4E8EF
    DWORD RGBC(0DAh,0E0h,0EAh)   ; hover        #DAE0EA
    DWORD RGBC(0D0h,0D8h,0E5h)   ; active       #D0D8E5
    DWORD RGBC(04Ah,058h,070h)   ; side text    #4A5870
    DWORD RGBC(02Eh,03Dh,056h)   ; active text  #2E3D56
    DWORD RGBC(0FFh,0FFh,0FFh)   ; card         #FFFFFF
    DWORD RGBC(0E0h,0E4h,0EAh)   ; border       #E0E4EA
    DWORD RGBC(02Eh,033h,03Bh)   ; text         #2E333B
    DWORD RGBC(076h,07Dh,088h)   ; muted        #767D88
    DWORD RGBC(0AFh,0C2h,0DDh)   ; accent       #AFC2DD
    DWORD RGBC(028h,03Ah,055h)   ; accent text  #283A55
; 4 - Dark (muted pastels)
    DWORD RGBC(01Fh,01Eh,026h)   ; bg           #1F1E26
    DWORD RGBC(02Ah,028h,036h)   ; sidebar      #2A2836
    DWORD RGBC(033h,02Fh,044h)   ; hover        #332F44
    DWORD RGBC(03Dh,038h,052h)   ; active       #3D3852
    DWORD RGBC(0B8h,0B1h,0D8h)   ; side text    #B8B1D8
    DWORD RGBC(0E3h,0DDh,0F7h)   ; active text  #E3DDF7
    DWORD RGBC(02Ah,029h,034h)   ; card         #2A2934
    DWORD RGBC(03Ah,038h,046h)   ; border       #3A3846
    DWORD RGBC(0E6h,0E4h,0EEh)   ; text         #E6E4EE
    DWORD RGBC(09Fh,09Ch,0B0h)   ; muted        #9F9CB0
    DWORD RGBC(04Eh,06Ah,08Ch)   ; accent       #4E6A8C
    DWORD RGBC(0E6h,0F1h,0FBh)   ; accent text  #E6F1FB

curTheme    THEME <>            ; colours currently in use
themeIndex  DWORD 0             ; which row of themeTable is active
hCardBrush  DWORD 0             ; brush in the card colour (text fields)

.code
;---------------------------------------------------------------------
; SetTheme
; Copies themeTable[index] into curTheme and repaints the window.
; Receives: index = 0 .. THEME_COUNT-1 (anything else -> 0)
;---------------------------------------------------------------------
SetTheme PROC USES ecx esi edi, index:DWORD
    mov eax, index
    cmp eax, THEME_COUNT
    jb  IndexOk
    xor eax, eax                    ; invalid index -> default theme
IndexOk:
    mov themeIndex, eax

    ; esi = address of themeTable[index]
    mov ecx, SIZEOF THEME
    mul ecx                         ; eax = index * SIZEOF THEME
    mov esi, OFFSET themeTable
    add esi, eax
    mov edi, OFFSET curTheme
    mov ecx, SIZEOF THEME / 4       ; number of DWORDs in a THEME
    cld
    rep movsd                       ; copy the whole record

    ; text fields on the screens paint with this brush: renew it
    cmp hCardBrush, 0
    je  @F
    INVOKE DeleteObject, hCardBrush
@@: INVOKE CreateSolidBrush, curTheme.clrCard
    mov hCardBrush, eax

    ; repaint everything if the window already exists
    cmp hMainWnd, 0
    je  Done
    INVOKE RedrawWindow, hMainWnd, NULL, NULL,
           RDW_INVALIDATE OR RDW_ERASE OR RDW_ALLCHILDREN OR RDW_UPDATENOW
Done:
    ret
SetTheme ENDP

END
