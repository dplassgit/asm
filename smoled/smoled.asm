; to build:
; nasm -fbin smoled.asm -o smoled.com
; tinyasm -f bin smoled.asm -o smoled.com


; Design thoughts:

; Need to update the screen after every character.
; So, draw all characters from the current character to newline (or EOF) mapping starting at current physical column & row.

; If inserting a newline, need to
; 1 Clear rest of the current physical line
; 2 Redraw all lines from next line to end of page


; Issues/TODO:
;  newlines (char 10) is insufficient on dos. it only linefeeds. needs CR (char 13)
;    proposal: in memory it's always 10, but when saving it's 1310
;  no load
;  leaves screen in a weird state (bold)
;  handle insert newline
;  handle delete newline
;  handle delete KEY
;  after backspace, redrawing the line leaves extra text at the end of the line
;  status line
;  only insert

org 0x0100


; get filename from 2nd arg https://en.wikipedia.org/wiki/Program_Segment_Prefix
;  xor   bx,bx
;  mov   bl,[0x80]
;  cmp   bl,0x00
;  je   exit      ; not allowed to have a zero-length
;

; load file into memory (up to 2k - screen only)

; draw status line (filename, dirty, mode)


  ; clear screen
  mov al, 0
  mov ah, 6 ; 0x06 is scroll; al=0 = clear screen
  mov bh, 0x0f  ; attribute f=bright white, for the TITLE
  xor cx, cx  ; cl,ch=window upper left corner
  mov dh, 24 ; dl,dh=window lower right corner
  mov dl, 79
  int 0x10

  ; set cursor to bottom of screen
  mov ah, 2
  xor bx, bx
  mov dl, 37
  mov dh, 24
  int 0x10

  ; output the $-terminated string
  mov ah, 9
  mov dx, TITLE
  int 0x21

  ; box cursor
  mov ch, 0
  mov cl, 7
  mov ah, 1
  int 0x10

  ; calculate offset into text; sets cl to THE character
  call xy_to_offset

  ; move to status line
  mov ah, 2
  xor bx, bx
  mov dl, 0 ; bottom left
  mov dh, 24
  int 0x10

  ; set character
  mov bh, 0
  mov bl, 4  ; bright red
  mov al, cl   ; character to print
  mov cx, 1
  mov ah, 9
  int 0x10  ; write char and attribute

  ; draw the whole text.
  call draw_all

  xor ax, ax
  push ax  ; preset the lastkey

waiting:
  ; update the cursor location on the screen
  mov dh, [y] ; row
  mov dl, [x] ; column
  xor bx, bx
  mov ah, 2
  int 0x10

  pop ax   ; last key
  mov [lastkey], al

  ; get char into al
  mov ah, 7
  int 0x21
  push ax  ; save it

  cmp al, 19 ; ctrl+s / save
  jne nots
  call save_file
  mov byte [dirty], 0
  jmp updatecursor

nots:
  cmp al, 17 ; ctrl+q / quit
  jne notq
  ; if clean, just quit
  cmp byte [dirty], 0
  je really_quit
  ; dirty, but if we hit ctrl-q 2x in a row, still end
  cmp al, [lastkey]
  jne notq

  ; fall through:
really_quit:
  ; restore cursor
  mov ch, 6
  mov cl, 7
  mov ah, 1
  int 0x10

  int 0x20   ; back to o/s
  ret

notq:
  cmp al, 1  ; ctrl+a
  jne nota
  mov byte [x], 0  ; beginning of line
  ; fall through

nota:
  cmp al, 5  ; ctrl+e
  jne note
  mov byte [x], 79 ; end of line
  ; fall through

note:
  cmp al, 14  ; ctrl-n / next line
  jne notn
  inc byte [y]
  ; fall through

notn:
  cmp al, 16  ; ctrl-p / prev line
  jne notp
  dec byte [y]
  ; fall through

notp:
  cmp al, 2  ; ctrl-b / back one char
  jne notb
  dec byte [x]
  ; fall through

notb:
  cmp al, 6  ; ctrl-f / forward one char
  jne notf
  inc byte [x]
  ; fall through

notf:
  ; TODO: process backspace (ctrl-h) delete (chr 127?), newline (ctrl-m)
  cmp al, 8  ; backspace
  jne noth
  ; if x!=0 or y!=0, do backspace
  cmp byte [x], 0
  jne .dobackspace
  cmp byte [y], 0
  je noth
  ; not at beginning. shuffle everything down
.dobackspace:
  call backspace
  call draw_all
  dec byte [x]
  jmp updatecursor


noth:
  ;cmp al, 127 ; delete : UGH THIS IS NOT DELETE
  cmp al, 4 ; ctrl-d
  jne notdel
  ; if x < 80, do delete
  cmp byte [x], 79
  je notdel
  inc word [offset]
  call backspace
  call draw_all
  jmp updatecursor


notdel:
  ; TODO: process newline (ctrl-m)

  ; detect if printable: if ascii 32 to 126
  cmp al, 32
  jl notprintable
  cmp al, 127
  jge notprintable

  mov byte [dirty], 1

  ; insert the char at al at the current offset, and redraw the line from this x location to the EOL.
  call insert_char

  ; write the character
  mov di, [offset]
  mov [di], al

  ; NOTE: this is slow on hardware, but fast on Win10
  call draw_all

  ; go to next cursor location
  inc byte [x]

  ; fall through:

notprintable:

; update cursor location
updatecursor:
  mov dl, [x] ; column
  cmp dl, 80
  jl goodcursor1
  mov byte [x], 0
  inc byte [y]
  jmp updatecursor

goodcursor1:
  cmp dl, 0xff
  jne goodcursor2
  mov byte [x], 79
  dec byte [y]
  jmp updatecursor

goodcursor2:
  mov dh, [y] ; row
  cmp dh, 0xff
  jne goodcursor3
  mov byte [y], 0
  jmp updatecursor

goodcursor3:
  cmp dh, 23
  jle goodcursor4
  mov byte [y], 23
  jmp updatecursor

goodcursor4:
  xor bx, bx
  mov ah, 2
  int 0x10   ; update the cursor location on the screen

  call xy_to_offset

  ; move to status line
  mov ah, 2
  xor bx, bx
  mov dl, 0 ; bottom left
  mov dh, 24
  int 0x10

  ; set character
  mov bh, 0
  mov bl, 4  ; bright red
  mov al, cl   ; character to print
  mov cx, 1
  mov ah, 9
  int 0x10  ; write char and attribute

  jmp waiting


; move from offset to end of text back one
backspace:
  mov di, [offset]
.loop:
  mov cl, [di]
  mov [di-1], cl
  inc di
  cmp cl, 0
  jne .loop
  ret

xy_to_offset:
  xor dx, dx  ; dl=x, dh=y
  mov si, text
.loop:
  mov cl, [si] ; char = text[i]
  ;If tx==x and ty ==y	// x, y are globals representing our physical location. ooh, we might be able to deal with scrolling here
  cmp dl, [x]
  jne .nothere
  cmp dh, [y]
  jne .nothere

  ; found it!
  mov [offset], si
  ret

.nothere:
  cmp cl, 0
  je .done  ; should be error, shrug.

	cmp cl, 10 ; newline
  je .newline
  inc dl ; next column

  jmp .next
.newline:
	mov dl, 0 ; clear column
	inc dh    ; next line
.next:
  inc si  ; next character in text
  jmp .loop

.done:
  ret


; draw the whole text starting at the top of the screen.
draw_all:
  mov si, text
  xor dx, dx ; dh=row, dl=column

.loop:
  mov al, [si]  ; get next character
  inc si
  cmp al, 0 ; eof
  je .done
  cmp al, 10 ; newline
  je .newline

  ; put al at current location
  ; move to current location
  mov ah, 2
  ; dh, dl already set
  int 0x10

  ; put char
  mov bx, 7 ; gray
  mov cx, 1
  mov ah, 9
  int 0x10

  ; go to next column in this row
  inc dl

  jmp .loop

.newline:
  ; TODO: erase to end of row

  ; set cursor to start of next row
  mov dl, 0
  inc dh
  jmp .loop

.done:
  ret


; move everything down one byte so we can insert a character at the current location
insert_char:
  call get_text_end
  ; di has end of text

.loop:
  cmp di, [offset]
  je .done
  mov cl, [di]
  mov [di+1], cl
  dec di
  jmp .loop

.done:
  ret


; calculate the end of text, returned in di
get_text_end:
  mov di, text
.loop:
  mov cl, [di]
  inc di
  cmp cl, 0
  jne .loop
  dec di
  ret

save_file:
  xor cx, cx   ; 0=write normal file
  mov dx, filename
  mov ah, 0x3c
  int 0x21   ; open file for write, handle in ax
  jc .error

  call get_text_end
  sub di, text  ; subtract start of text
  mov cx, di   ; length in cx

  ; ax has file handle, needs to be in bx
  mov bx, ax
  mov dx, text
  mov ah, 0x40
  int 0x21
  jc .error

  ; close file, handle still in bx
  mov ah, 0x3e
  int 0x21
  jc .error
  ret

.error:
  int 0x20   ; back to o/s
  ret


; DATA HERE:
; segment .data - not needed since this is built as a com file
  TITLE: db "Smoled$", 0

  ; physical cursor location on screen
  x: db 0  ; 0-79
  y: db 0  ; 0-22

  ; what line of the file is the top line shown?
  ; top: db 0 this will be for scrolling, not v1

  ; absolute location of cursor in text
  offset: dw 0

  ; last key hit
  lastkey: db 0

  dirty: db 0

  ; 24 lines x 80 rows, kind of draconian
  ; text: times 1920 db 0
  text: db  "Four score and seven years ago our fathers brought forth on this continent.", 10, "a new nation, conceived in Liberty, and dedicated to the proposition that ", 10, "all men are created equal.", 10,  0
  buffer: times 1000 db 0
    ;"Now we are engaged in a great civil war, testing whether that nation, or any ", 10, \
    ;"nation so conceived and so dedicated, can long endure. We are met on a great ", 10, \
    ;"battle-field of that war. We have come to dedicate a portion of that field, ", 10, \
    ;"as a final resting place for those who here gave their lives that that nation ", 10, \
    ;"might live. It is altogether fitting and proper that we should do this.", 10, 10, \
    ;"But, in a larger sense, we can not dedicate -- we can not consecrate -- we ", 10, \
    ;"can not hallow -- this ground. The brave men, living and dead, who struggled ", 10, \
    ;"here, have consecrated it, far above our poor power to add or detract. ", 10, \
    ;"... It is rather for us to be here dedicated to the great task ", 10, \
    ;"remaining before us -- that from these honored dead we take increased ", 10, \
    ;"devotion to that cause for which they gave the last full measure of devotion ", 10, \
    ;"-- that we here highly resolve that these dead shall not have died in vain -- ", 10, \
    ;"that this nation, under God, shall have a new birth of freedom -- and that ", 10, \
    ;"government of the people, by the people, for the people, shall not perish from ", 10, \
    ;"the earth.", 10, 0

  filename: db "SMOLED.TXT", 0 ; times 13 db 0	; 8.3

