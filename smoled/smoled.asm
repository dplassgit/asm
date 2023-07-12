; to build:
; nasm -fbin smoled.asm -o smoled.com
; tinyasm -f bin smoled.asm -o smoled.com


; Issues/TODO:
;  load file
;  save to correct filename
;  delete/replace CRLF (only deletes the CR, not the LF, shrug. mostly works)
;  handle delete KEY (vs ctrl+d)
;  overwrite mode; insert = BIOS code 0x52
;  when going down and the cursor is past end of line, weird things happen
;  cursor keys BIOS code up 0x48 down 0x50 left 0x4b right 0x4d home 0x47 end 0x4f
;  status line

org 0x0100

section .text

; get filename from 2nd arg https://en.wikipedia.org/wiki/Program_Segment_Prefix
;  xor   bx,bx
;  mov   bl,[0x80]
;  cmp   bl,0x00
;  je   exit      ; not allowed to have a zero-length
;

  ; TODO: load file into memory (up to 2k)

  ; clear screen
  mov al, 0
  mov ah, 6 ; 0x06 is scroll; al=0 = clear screen
  mov bh, 7  ; attribute 7=regular white
  xor cx, cx  ; cl,ch=window upper left corner
  mov dh, 24 ; dl,dh=window lower right corner
  mov dl, 79
  int 0x10

  ; output the title
  mov bh, 0
  mov bl, 15   ; attribute: bright white
  mov cx, 7    ; length
  mov dl, 37   ; dl, dh are column, riw
  mov dh, 24
  mov bp, TITLE
  mov ah, 0x13
  int 0x10

  ; box cursor
  mov ch, 0
  mov cl, 7
  mov ah, 1
  int 0x10

  ; calculate cursor location in text; sets cl to THE character
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
  ; not falling through because the two calls munge things.
  jmp updatecursor


noth:
  cmp al, 4 ; ctrl+d
  jne notdel
  ; process ctrl+d (NOT DELETE)
  ; if x < 80, do delete
  cmp byte [x], 79
  je notdel
  inc word [cursorloc]
  call backspace
  call draw_all
  ; not falling through because the two calls munge things.
  jmp updatecursor

notdel:
  cmp al, 13 ;  ctrl+m / enter
  jne notenter

  ; process enter (ctrl-m)
  mov byte [dirty], 1

  ; insert 13, 10
  call insert_char
  mov di, [cursorloc]
  mov byte [di], 13

  call insert_char
  inc word [cursorloc]
  mov di, [cursorloc]
  mov byte [di], 10

  call draw_all

  ; go to next cursor location
  inc byte [y]
  mov byte [x], 0
  jmp updatecursor

notenter:
  ; detect if printable: if ascii 32 to 126
  cmp al, 32
  jl notprintable
  cmp al, 127
  jge notprintable

  mov byte [dirty], 1

  ; insert the char at al at the current cursorloc
  ; TODO: and redraw the line from this x location to the EOL.
  call insert_char

  ; write the character
  mov di, [cursorloc]
  mov [di], al

  ; NOTE: this is slow on hardware, but fast on DOSBox
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
  ; dl, dh already set
  int 0x10   ; update the cursor location on the screen

  call xy_to_offset

  ; move to status line
  mov ah, 2
  xor bx, bx
  mov dl, 0 ; bottom left
  mov dh, 24
  int 0x10

  ; set character
  mov bl, 4  ; bright red (bh=0)
  mov al, cl   ; character to print
  mov cx, 1
  mov ah, 9
  int 0x10  ; write char and attribute

  jmp waiting


; move from cursorloc to end of text back one
backspace:
  mov di, [cursorloc]
.loop:
  mov cl, [di]
  mov [di-1], cl
  inc di
  cmp cl, 0
  jne .loop
  ret

; Sets cursorloc and cl to the value at cursorloc
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
  mov [cursorloc], si
  ret

.nothere:
  cmp cl, 0
  je .done  ; should be error, shrug.

	cmp cl, 13 ; CR
  je .newline
  inc dl ; next column

  cmp dl, 80 ; got to last column without a newline, reset 
  je .newline

  jmp .next
.newline:
  inc si  ; skip LF
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
  cmp al, 13 ; CR
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
  cmp dl, 80
  je .resetcol
  jmp .loop

.newline:
  ; erase to end of row
  cmp dl, 80
  je .resetcol
  ; put space at current location
  mov al, ' '
  mov ah, 2
  ; dh, dl already set
  int 0x10

  ; put char
  mov bx, 7 ; gray
  mov cx, 1
  mov ah, 9
  int 0x10
  inc dl  ; next column
  jmp .newline

.resetcol:
  inc si  ; skip LF
  ; set cursor to start of next row
  mov dl, 0
  inc dh
  jmp .loop

.done:
  ; clear the next line (in case the # of lines is smaller)
  mov al, 0
  mov bh, 0
  mov bl, 7
  mov cx, 80
  mov dl, 0
  mov bp, blankline
  mov ah, 0x13
  int 0x10

  ret


; move everything down one byte so we can insert a character at the current location
insert_char:
  call get_text_end
  ; di points at the zero at the end of text

; surely this can be done with a loop, and don't call me Shirley
.loop:
  mov cl, [di-1]
  mov [di], cl
  dec di
  cmp di, [cursorloc]
  jne .loop

  ret


; calculate the end of text, returned in di
; TODO: cache this and only change it when a character is inserted or deleted
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


segment .data
  TITLE: db "Smoled", 0

  ; physical cursor location on screen
  x: db 0  ; 0-79
  y: db 0  ; 0-22

  ; what line of the file is the top line shown?
  ; top: db 0 this will be for scrolling, not v1

  dirty: db 0

  ; last key hit
  lastkey: db 0

  ; absolute location of cursor in text
  cursorloc: dw 0

  filename: db "SMOLED.TXT", 0 ; times 13 db 0	; 8.3
  blankline: times 80 db ' '

  ; 24 lines x 80 rows, kind of draconian
  ; text: times 1920 db 0
  text: db  "Four score and seven years ago our fathers brought forth on this continent.", 13, 10, "a new nation, conceived in Liberty,", 13, 10, "and dedicated to the proposition that", 13, 10, "all men are created equal.", 13, 10, 0
  buffer: times 1000 db 0
    ;"Now we are engaged in a great civil war, testing whether that nation, or any ", 13, \
    ;"nation so conceived and so dedicated, can long endure. We are met on a great ", 13, \
    ;"battle-field of that war. We have come to dedicate a portion of that field, ", 13, \
    ;"as a final resting place for those who here gave their lives that that nation ", 13, \
    ;"might live. It is altogether fitting and proper that we should do this.", 13, 13, \
    ;"But, in a larger sense, we can not dedicate -- we can not consecrate -- we ", 13, \
    ;"can not hallow -- this ground. The brave men, living and dead, who struggled ", 13, \
    ;"here, have consecrated it, far above our poor power to add or detract. ", 13, \
    ;"... It is rather for us to be here dedicated to the great task ", 13, \
    ;"remaining before us -- that from these honored dead we take increased ", 13, \
    ;"devotion to that cause for which they gave the last full measure of devotion ", 13, \
    ;"-- that we here highly resolve that these dead shall not have died in vain -- ", 13, \
    ;"that this nation, under God, shall have a new birth of freedom -- and that ", 13, \
    ;"government of the people, by the people, for the people, shall not perish from ", 13, \
    ;"the earth.", 13, 0
