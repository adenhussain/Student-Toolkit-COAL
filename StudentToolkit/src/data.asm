;=====================================================================
; data.asm  -  student accounts and the encrypted save file
;
; Every student has one file:  data\<username>.dat
; The file holds one USERDATA record, encrypted with a key made from
; the username and PIN.
;
; The PIN itself is never stored anywhere. To log in, the program
; decrypts the file with the typed PIN and checks the first 4 bytes:
;   "STK1"  -> PIN was right, data is readable
;   garbage -> PIN was wrong
;
; Encryption:
;   1. DeriveKey : hash username + PIN into a 32-bit key (FNV-1a)
;   2. CryptBuffer: a xorshift generator turns the key into a stream
;      of bytes; each file byte is XORed with the next stream byte.
;      XOR is its own inverse, so the same procedure decrypts.
; Note for the viva: this hides the data from casual reading (e.g.
; Notepad). It is not bank-grade encryption.
;=====================================================================
; Irvine32.inc already selects .686P / .MODEL flat, stdcall
option casemap:none

INCLUDE app.inc

DeriveKey   PROTO :DWORD, :DWORD
CryptBuffer PROTO :DWORD, :DWORD, :DWORD
DataChecksum PROTO :DWORD
BuildUserPath PROTO :DWORD

.data
userData    USERDATA <>                     ; the logged-in student's data
cryptBuf    BYTE SIZEOF USERDATA DUP(?)     ; work area for encrypting
userKey     DWORD 0                         ; key of the logged-in student

dataDir     BYTE 260 DUP(0)                 ; "...\bin\Debug\data\"
userPath    BYTE 300 DUP(0)                 ; "...\data\aden.dat"
szDataSub   BYTE "data", 0
szBackslash BYTE "\", 0
szDatExt    BYTE ".dat", 0

.code
;---------------------------------------------------------------------
; InitDataDir - builds the path of the "data" folder next to the
; program and creates the folder if it does not exist yet.
;---------------------------------------------------------------------
InitDataDir PROC USES edi
    INVOKE GetModuleFileNameA, NULL, ADDR dataDir, SIZEOF dataDir

    ; cut the path after the last '\'  ("C:\...\Debug\StudentToolkit.exe")
    mov edi, OFFSET dataDir
    add edi, eax                    ; edi -> end of the string
FindSlash:
    cmp edi, OFFSET dataDir
    je  CutHere
    dec edi
    cmp BYTE PTR [edi], '\'
    jne FindSlash
    inc edi                         ; keep the '\'
CutHere:
    mov BYTE PTR [edi], 0

    INVOKE StrAppend, ADDR dataDir, ADDR szDataSub
    INVOKE CreateDirectoryA, ADDR dataDir, NULL     ; fails harmlessly if it exists
    INVOKE StrAppend, ADDR dataDir, ADDR szBackslash
    ret
InitDataDir ENDP

;---------------------------------------------------------------------
; BuildUserPath - userPath = dataDir + username + ".dat"
;---------------------------------------------------------------------
BuildUserPath PROC pUser:DWORD
    INVOKE Str_copy, ADDR dataDir, ADDR userPath
    INVOKE StrAppend, ADDR userPath, pUser
    INVOKE StrAppend, ADDR userPath, ADDR szDatExt
    ret
BuildUserPath ENDP

;---------------------------------------------------------------------
; HashBytes (helper) - FNV-1a hash step over a zero-terminated string
; Receives: EAX = running hash, ESI = string.  Returns: EAX = new hash
;---------------------------------------------------------------------
HashBytes PROC USES edx esi
NextByte:
    movzx edx, BYTE PTR [esi]
    test edx, edx
    jz  Done
    xor eax, edx                    ; hash = (hash XOR byte) * prime
    imul eax, eax, 16777619
    inc esi
    jmp NextByte
Done:
    ret
HashBytes ENDP

;---------------------------------------------------------------------
; DeriveKey - turns username + PIN into a 32-bit key
; Returns: EAX = key (never 0)
;---------------------------------------------------------------------
DeriveKey PROC USES esi, pUser:DWORD, pPin:DWORD
    mov eax, 2166136261             ; FNV-1a starting value
    mov esi, pUser
    call HashBytes
    xor eax, '|'                    ; separator between the two parts
    imul eax, eax, 16777619
    mov esi, pPin
    call HashBytes
    test eax, eax
    jnz KeyOk
    inc eax                         ; xorshift needs a non-zero start
KeyOk:
    ret
DeriveKey ENDP

;---------------------------------------------------------------------
; CryptBuffer - encrypts or decrypts 'count' bytes in place
; Each byte is XORed with the next byte of a xorshift32 stream.
;---------------------------------------------------------------------
CryptBuffer PROC USES ecx edx edi, pBuf:DWORD, count:DWORD, key:DWORD
    mov edi, pBuf
    mov ecx, count
    jecxz Done
    mov eax, key
NextByte:
    mov edx, eax                    ; x ^= x << 13
    shl edx, 13
    xor eax, edx
    mov edx, eax                    ; x ^= x >> 17
    shr edx, 17
    xor eax, edx
    mov edx, eax                    ; x ^= x << 5
    shl edx, 5
    xor eax, edx
    xor [edi], al                   ; scramble one byte
    inc edi
    loop NextByte
Done:
    ret
CryptBuffer ENDP

;---------------------------------------------------------------------
; DataChecksum - FNV-1a hash of a whole USERDATA record.
; Any changed byte gives a different number, so if somebody edits the
; save file, the stored checksum no longer matches (tamper check).
; Returns: EAX
;---------------------------------------------------------------------
DataChecksum PROC USES ecx edx esi, pData:DWORD
    mov esi, pData
    mov ecx, SIZEOF USERDATA
    mov eax, 2166136261
NextByte:
    movzx edx, BYTE PTR [esi]
    xor eax, edx
    imul eax, eax, 16777619
    inc esi
    loop NextByte
    ret
DataChecksum ENDP

;---------------------------------------------------------------------
; SaveUser - encrypts userData and writes it to data\<username>.dat
; Returns: EAX = 1 if saved, 0 on error
;---------------------------------------------------------------------
SaveUser PROC USES ebx ecx esi edi
    ; stamp the record: current version + checksum of the contents
    ; (the checksum is computed while its own field is 0)
    mov userData.version, FILE_VERSION
    mov userData.checksum, 0
    INVOKE DataChecksum, ADDR userData
    mov userData.checksum, eax

    ; copy userData into cryptBuf, then encrypt the copy
    mov esi, OFFSET userData
    mov edi, OFFSET cryptBuf
    mov ecx, SIZEOF USERDATA
    cld
    rep movsb
    INVOKE CryptBuffer, ADDR cryptBuf, SIZEOF USERDATA, userKey

    INVOKE BuildUserPath, ADDR userData.userName
    mov edx, OFFSET userPath
    call CreateOutputFile           ; Irvine32: EDX = file name -> EAX = handle
    cmp eax, INVALID_HANDLE_VALUE
    je  Failed
    mov ebx, eax

    mov edx, OFFSET cryptBuf
    mov ecx, SIZEOF USERDATA
    call WriteToFile                ; Irvine32: EAX = handle -> EAX = bytes written
    mov esi, eax
    mov eax, ebx
    call CloseFile

    cmp esi, SIZEOF USERDATA
    jne Failed
    mov eax, 1
    ret
Failed:
    xor eax, eax
    ret
SaveUser ENDP

;---------------------------------------------------------------------
; LoadUser - opens a student's file and checks the PIN
; Returns: EAX = ACC_OK, ACC_NO_USER, ACC_BAD_PIN or ACC_BAD_FILE
;---------------------------------------------------------------------
LoadUser PROC USES ebx ecx esi edi, pUser:DWORD, pPin:DWORD
    LOCAL key:DWORD

    INVOKE BuildUserPath, pUser
    INVOKE GetFileAttributesA, ADDR userPath
    cmp eax, INVALID_FILE_ATTRIBUTES
    jne FileExists
    mov eax, ACC_NO_USER
    ret

FileExists:
    mov edx, OFFSET userPath
    call OpenInputFile              ; Irvine32: EDX = file name -> EAX = handle
    cmp eax, INVALID_HANDLE_VALUE
    je  BadFile
    mov ebx, eax
    mov edx, OFFSET cryptBuf
    mov ecx, SIZEOF USERDATA
    call ReadFromFile               ; Irvine32: EAX = bytes read, CF = 1 on error
    mov esi, eax
    mov eax, ebx
    call CloseFile
    cmp esi, SIZEOF USERDATA        ; file must contain exactly one record
    jne BadFile

    ; decrypt with the key from the typed PIN
    INVOKE DeriveKey, pUser, pPin
    mov key, eax
    INVOKE CryptBuffer, ADDR cryptBuf, SIZEOF USERDATA, key

    ; right PIN -> header reads "STK1"
    cmp (USERDATA PTR cryptBuf).magic, FILE_MAGIC
    jne WrongPin
    cmp (USERDATA PTR cryptBuf).version, 1
    je  Accept                      ; old file (no checksum yet): upgraded on next save
    cmp (USERDATA PTR cryptBuf).version, FILE_VERSION
    jne BadFile

    ; tamper check: recompute the checksum and compare
    mov ebx, (USERDATA PTR cryptBuf).checksum
    mov (USERDATA PTR cryptBuf).checksum, 0
    INVOKE DataChecksum, ADDR cryptBuf
    cmp eax, ebx
    jne Tampered
    mov (USERDATA PTR cryptBuf).checksum, ebx
Accept:

    ; accept: copy the decrypted record into userData
    mov esi, OFFSET cryptBuf
    mov edi, OFFSET userData
    mov ecx, SIZEOF USERDATA
    cld
    rep movsb
    mov eax, key
    mov userKey, eax
    mov eax, ACC_OK
    ret

WrongPin:
    mov eax, ACC_BAD_PIN
    ret
Tampered:
    mov eax, ACC_TAMPERED
    ret
BadFile:
    mov eax, ACC_BAD_FILE
    ret
LoadUser ENDP

;---------------------------------------------------------------------
; CreateUser - makes a new account file with default settings
; Returns: EAX = ACC_OK, ACC_EXISTS or ACC_IO_ERROR
;---------------------------------------------------------------------
CreateUser PROC pName:DWORD, pUser:DWORD, pPin:DWORD
    INVOKE BuildUserPath, pUser
    INVOKE GetFileAttributesA, ADDR userPath
    cmp eax, INVALID_FILE_ATTRIBUTES
    je  NewName
    mov eax, ACC_EXISTS
    ret

NewName:
    INVOKE ClearUser                ; start from an all-zero record
    mov userData.magic, FILE_MAGIC
    mov userData.version, FILE_VERSION
    INVOKE Str_copy, pUser, ADDR userData.userName
    INVOKE Str_copy, pName, ADDR userData.displayName
    mov userData.theme, THEME_LAVENDER
    mov userData.dailyLimit, DEFAULT_LIMIT
    mov userData.soundOn, 1

    INVOKE DeriveKey, pUser, pPin
    mov userKey, eax
    INVOKE SaveUser
    test eax, eax
    jz  WriteFailed
    mov eax, ACC_OK
    ret
WriteFailed:
    mov eax, ACC_IO_ERROR
    ret
CreateUser ENDP

;---------------------------------------------------------------------
; ChangePin - checks the current PIN, then encrypts the data again
; with a key made from the new PIN and saves it.
; The PIN is never stored: "is the old PIN right?" is answered by
; making a key from it and comparing with the key we logged in with.
; Returns: EAX = 1 changed, 0 wrong current PIN, 2 could not save
;---------------------------------------------------------------------
ChangePin PROC USES ebx, pOld:DWORD, pNew:DWORD
    INVOKE DeriveKey, ADDR userData.userName, pOld
    cmp eax, userKey
    jne WrongOld
    mov ebx, userKey                ; keep the old key in case saving fails
    INVOKE DeriveKey, ADDR userData.userName, pNew
    mov userKey, eax
    INVOKE SaveUser                 ; the whole file is encrypted again
    test eax, eax
    jz  SaveFailed
    mov eax, 1
    ret
SaveFailed:
    mov userKey, ebx                ; the file on disk still uses the old PIN
    mov eax, 2
    ret
WrongOld:
    xor eax, eax
    ret
ChangePin ENDP

;---------------------------------------------------------------------
; ClearUser - wipes the logged-in student's data from memory (logout)
;---------------------------------------------------------------------
ClearUser PROC USES ecx edi
    mov edi, OFFSET userData
    mov ecx, SIZEOF USERDATA
    xor eax, eax
    cld
    rep stosb
    mov userKey, 0
    ret
ClearUser ENDP

END
