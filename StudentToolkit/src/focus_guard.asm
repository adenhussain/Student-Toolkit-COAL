;=====================================================================
; focus_guard.asm  -  Focus Guard: notices distractions during a
;                     Pomodoro focus session
;
; Every second of a focus session (one WM_TIMER tick) we ask Windows
; which window is in front (GetForegroundWindow) and read its title
; (GetWindowTextA). The title is turned into lower case and searched
; for words such as "youtube", "instagram" or "netflix".
;   - first second on a distracting window -> a gentle notification
;     "Looks like YouTube. Back to COAL? 14 min left."
;     (at most one notification per minute)
;   - every distracted second is counted
; When the session ends:
;   focus score = (seconds - distracted seconds) x 100 / seconds
; Our own windows (main, mini timer) never count as a distraction.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

TitleHas       PROTO :DWORD, :DWORD

WARN_GAP    = 60                ; seconds between two notifications

.data
fgSeconds       DWORD 0         ; seconds of focus so far in this session
fgDistracted    DWORD 0         ; seconds spent on distracting windows
fgCount         DWORD 0         ; how many separate distractions
fgInside        DWORD 0         ; 1 while still on the distracting window
fgCooldown      DWORD 0         ; seconds until another notification is allowed

; words to look for (lower case) and how to show them
fgWord0     BYTE "youtube", 0
fgWord1     BYTE "instagram", 0
fgWord2     BYTE "facebook", 0
fgWord3     BYTE "tiktok", 0
fgWord4     BYTE "netflix", 0
fgWord5     BYTE "twitter", 0
fgWord6     BYTE "reddit", 0
fgWord7     BYTE "twitch", 0
fgWord8     BYTE "snapchat", 0
fgWord9     BYTE "pubg", 0
fgWord10    BYTE "valorant", 0
fgWord11    BYTE "minecraft", 0
fgWord12    BYTE "roblox", 0
fgWords     DWORD OFFSET fgWord0, OFFSET fgWord1, OFFSET fgWord2, OFFSET fgWord3,
                  OFFSET fgWord4, OFFSET fgWord5, OFFSET fgWord6, OFFSET fgWord7,
                  OFFSET fgWord8, OFFSET fgWord9, OFFSET fgWord10, OFFSET fgWord11,
                  OFFSET fgWord12
FG_WORD_COUNT = 13
fgName0     BYTE "YouTube", 0
fgName1     BYTE "Instagram", 0
fgName2     BYTE "Facebook", 0
fgName3     BYTE "TikTok", 0
fgName4     BYTE "Netflix", 0
fgName5     BYTE "Twitter", 0
fgName6     BYTE "Reddit", 0
fgName7     BYTE "Twitch", 0
fgName8     BYTE "Snapchat", 0
fgName9     BYTE "PUBG", 0
fgName10    BYTE "Valorant", 0
fgName11    BYTE "Minecraft", 0
fgName12    BYTE "Roblox", 0
fgNames     DWORD OFFSET fgName0, OFFSET fgName1, OFFSET fgName2, OFFSET fgName3,
                  OFFSET fgName4, OFFSET fgName5, OFFSET fgName6, OFFSET fgName7,
                  OFFSET fgName8, OFFSET fgName9, OFFSET fgName10, OFFSET fgName11,
                  OFFSET fgName12

fgTitle     BYTE 256 DUP(0)     ; title of the window in front (lower case)
fgMsg       BYTE 160 DUP(0)
szFgTitle   BYTE "Focus Guard", 0
szFgFmt     BYTE "Looks like %s. Back to %s? %d min left.", 0

.code
;---------------------------------------------------------------------
; FocusReset - a new focus session starts with a clean count
;---------------------------------------------------------------------
FocusReset PROC
    mov fgSeconds, 0
    mov fgDistracted, 0
    mov fgCount, 0
    mov fgInside, 0
    mov fgCooldown, 0
    ret
FocusReset ENDP

;---------------------------------------------------------------------
; TitleHas - does pHay contain pNeedle?  Returns: EAX = 1 / 0
;---------------------------------------------------------------------
TitleHas PROC USES ebx esi edi, pHay:DWORD, pNeedle:DWORD
    mov esi, pHay
StartLoop:
    cmp BYTE PTR [esi], 0
    je  NotFound
    ; compare the needle with the text starting at esi
    mov edi, pNeedle
    mov ebx, esi
CompareLoop:
    mov al, [edi]
    cmp al, 0
    je  Found                       ; whole needle matched
    cmp al, [ebx]
    jne NextStart
    inc edi
    inc ebx
    jmp CompareLoop
NextStart:
    inc esi
    jmp StartLoop
Found:
    mov eax, 1
    ret
NotFound:
    xor eax, eax
    ret
TitleHas ENDP

;---------------------------------------------------------------------
; FocusCheck - called once per second while a focus session runs
;---------------------------------------------------------------------
FocusCheck PROC USES ebx ecx esi edi
    LOCAL pid:DWORD

    inc fgSeconds
    cmp fgCooldown, 0
    je  @F
    dec fgCooldown
@@:
    ; which window is in front? ours never counts
    INVOKE GetForegroundWindow
    cmp eax, 0
    je  NotDistracted
    mov ebx, eax
    INVOKE GetWindowThreadProcessId, ebx, ADDR pid
    INVOKE GetCurrentProcessId
    cmp eax, pid
    je  NotDistracted

    ; read its title and turn it into lower case
    INVOKE GetWindowTextA, ebx, ADDR fgTitle, SIZEOF fgTitle
    mov esi, OFFSET fgTitle
LowerLoop:
    mov al, [esi]
    cmp al, 0
    je  LowerDone
    cmp al, 'A'
    jb  @F
    cmp al, 'Z'
    ja  @F
    add al, 20h                     ; 'A'..'Z' -> 'a'..'z'
    mov [esi], al
@@: inc esi
    jmp LowerLoop
LowerDone:

    ; look for each distracting word
    xor edi, edi
WordLoop:
    cmp edi, FG_WORD_COUNT
    jae NotDistracted
    INVOKE TitleHas, ADDR fgTitle, fgWords[edi*4]
    cmp eax, 0
    jne Distracted
    inc edi
    jmp WordLoop

Distracted:
    inc fgDistracted
    cmp fgInside, 0
    jne Done                        ; same distraction as last second
    mov fgInside, 1
    inc fgCount
    cmp fgCooldown, 0
    jne Done                        ; told them less than a minute ago
    mov fgCooldown, WARN_GAP
    ; "Looks like YouTube. Back to COAL? 14 min left."
    mov eax, tmRemaining
    xor edx, edx
    mov ecx, 60
    div ecx
    inc eax                         ; minutes left, rounded up
    mov ecx, eax
    push ecx
    INVOKE TimerCourseName
    pop ecx
    INVOKE wsprintf, ADDR fgMsg, ADDR szFgFmt, fgNames[edi*4], eax, ecx
    INVOKE TrayNotify, ADDR szFgTitle, ADDR fgMsg
    jmp Done

NotDistracted:
    mov fgInside, 0
Done:
    ret
FocusCheck ENDP

;---------------------------------------------------------------------
; FocusScore - percent of the session spent focused. Returns: EAX
;---------------------------------------------------------------------
FocusScore PROC USES ecx edx
    mov ecx, fgSeconds
    cmp ecx, 0
    jne @F
    mov eax, 100
    ret
@@: mov eax, ecx
    sub eax, fgDistracted
    imul eax, eax, 100
    xor edx, edx
    div ecx
    ret
FocusScore ENDP

END
