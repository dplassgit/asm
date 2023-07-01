; to build:
; nasm -fbin smoled.asm -o smoled.com


; Design thoughts:

; Whenever a char is typed, the rest of the text needs to be moved down and the new char inserted at the location.

; Need to update the screen after every character.
; We know which physical row we're on and which physical column we're at.
; We (should) know what offset into the text we're at (which needs to update on every cursor movement).
; So, draw all characters from the current character to newline (or EOF) mapping starting at current physical column & row.

; If inserting a newline, need to
; 1 Clear rest of the current physical line
; 2 Redraw all lines from next line to end of page

; should write a subroutine to do the above, which would
; be usable for initial drawing



org 0x0100


; what shall it do?
; full screen

; get filename from 2nd arg https://en.wikipedia.org/wiki/Program_Segment_Prefix
;  xor   bx,bx
;  mov   bl,[0x80]
;  cmp   bl,0x00
;  je   exit      ; not allowed to have a zero-length
;
;  ; find the space
;  Mov cl, 0
;Loop:
;  Cmp [cl+0x81], ' '  ;; wil this even work?
;  Je space
;  Inc cl
;  Cmp cl, bl
;  Jne loop
;
;Space:
;  ; copy next at most 11 chars to "filename" but what about spaces?

; load file into memory (up to 2k - screen only)

; draw lines of the file

; draw status line (filename, dirty, mode)


  ; clear screen
  mov al, 0
  mov ah, 6 ; 0x06 is scroll; al=0 = clear screen
  ;mov bh, 0x0f  ; attribute f=bright white, for the TITLE
  mov bh, 0x07
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
  mov al, ' ' ; thi sisn't working,... only sets the first character as bright white...
  mov bl, 0x0f ; set attribute to bright white
  mov ah, 9
  mov cx, 1
  int 0x10

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

  pop ax
  mov byte [lastkey], al

  ; get char into al
  mov ah, 7
  int 0x21
  push ax

  ;cmp al, 19 ; ctrl+s / save
  ;jne nots

nots:
  cmp al, 17 ; ctrl+q / quit
  jne notq
  ; if clean, just quit
  cmp byte [dirty], 0
  je end
  ; dirty, but if we hit ctrl-q 2x in a row, still end
  cmp al, [lastkey]
  jne notq

  ; fall through:

  ; really quit

end:
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

  ; detect if  printable: if ascii 32 to 126
  cmp al, 32
  jl notprintable
  cmp al, 127
  jge notprintable

  mov byte [dirty], 1

  ; insert the char at al at the current offset, and redraw the line from this x location to the EOL.
  ;call insert_char

  ; TEMPORARY: write the char in al at the current location
  mov di, [offset]
  mov byte [di], al

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
  ;mov dh, [y] ; row
  ;mov dl, [x] ; column
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
  inc si
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
  ; set cursor to start of next row
  mov dl, 0
  inc dh
  jmp .loop

.done: ret


; draw starting from offset at x, y to the EOL
;draw_line:
;  ret
;
;

; move everything down one byte so we can insert a character at the current location
insert_char:
  mov si, [offset]
  ; have to start at the end of the string, which we do not know.
  ; THIS IS BROKEN
  xor bx, bx

.loop:
  mov dl, [si+bx]
  cmp dl, 0
  mov [si+bx+1], dl
  je .done
  dec bx
  jmp .loop

.done
  ; TODO: detect overflow
  inc word [textlength]
  ret



; DATA HERE:
; segment .data - not needed since this is built as a com file
  TITLE: db "Smoled$", 0

  ; physical cursor location on screen
  x: db 0  ; 0-79
  y: db 0  ; 0-22

  ; what line of the file is the top line shown?
  ; top: db 0 this will be for scrolling, not v1

  ; location of cursor in text
  offset: dw 0

  ; last key hit
  lastkey: db 0

  dirty: db 0

  textlength: dw 40	 ; length of the text
  ; 24 lines x 80 rows, kind of draconian
  ; text: times 1920 db 0
  text: db  "Four score and seven years ago our fathers brought forth on this continent.", 10, "a new nation, conceived in Liberty, and dedicated to the proposition that ", 10, "all men are created equal.", 10,  0
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


  filename: times 13 db 0	; 8.3

