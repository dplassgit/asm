; Whenever a char is typed, the rest of the text needs to be moved down and the new char inserted at the location.

; Need to update the screen after every character. 
; We know which physical row we're on and which physical column we're at. 
; We (should) know what offset into the text we're at. (which needs to update on every cursor movement)
; So, draw all characters from current char to newline (or EOF) mapping starting at current physical column & row.

; If inserting a newline, need to
; 1 Clear rest of current physical line
; 2 Redraw all lines from next line to end of page

; should write a subroutine to do the above, which would
; be usable for initial drawing



org 0x0100

main:

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
  xor ax, ax
  mov ah, 0x06 ; 0x06 is scroll; al=0 = clear screen
  mov bh, 0x07  ; attribute 0111=gray
  xor cx, cx  ; cl,ch=window upper left corner
  mov dh, 23; dl,dh=window lower right corner
  mov dl, 79
  int 0x10

  ; set cursor to bottom of screen
  mov ah, 2
  xor bx, bx
  mov dl, 20
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

  ; move cursor to top of screen
  mov ah, 2
  xor bx, bx
  xor dx, dx
  int 0x10

  xor ax, ax
  push ax

save:
  ; TODO: update status line
  mov byte [dirty], 0

waiting:
  pop ax
  mov byte [lastkey], al

  ; get char
  mov ah, 7
  int 0x21
  push ax
  ; al has char

  ;cmp al, 19 ; ctrl+s / save
  ;je save

  cmp al, 17 ; ctrl+q / quit
  jne notq
  ; if clean, just quit
  cmp byte [dirty], 0
  je end
  ; dirty, but if we hit ctrl-q 2x in a row, still end
  cmp al, [lastkey]
  je end
  ; fall through

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

  ; TEMPORARY: write visible chars to the screen at the current location
  ; only write it if it's a "visible" character
  cmp al, 32 
  jl updatecursor
  cmp al, 127
  jge updatecursor

  ; write the char in al at the current location
  ; TODO: insert the char at al at the current offset, and redraw the line from this x location to the EOL.
  mov bh, 0
  mov ah, 0x0a
  mov cx, 1
  int 0x10

  mov byte [dirty], 1

  ; go to next cursor location
  ; TODO: write into memory.
  inc byte [x]

  ; fall through:

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
  ; TODO: update offset into text

  mov ah, 2
  xor bx, bx
  int 0x10   ; update the cursor location on the screen

  jmp waiting


end:
  ; restore cursor
  mov ch, 6
  mov cl, 7
  mov ah, 1
  int 0x10

  int 0x20   ; back to o/s

section .data:
  TITLE: db "Smoled$", 0

  ; physical cursor location on screen
  x: db 0  ; 0-79
  y: db 0  ; 0-22

  ; what line of the file is the top line shown?
  ; top: db 0 this will be for scrolling, not v1

  ; *relative* location of cursor in text
  offset: dw 0

  ; last key hit
  lastkey: db 0

  dirty: db 0

  textlength: dw 0	 ; length of the text
  ; 23 lines x 80 rows, kind of draconian
;  text: times 1841 db 0

  filename: times 13 db 0	; 8.3



; draw the whole text starting at the top of the screen.
;Drawtext:
;  ; move to top of screen
;  mov ah, 2
;  xor bx, bx
;  xor dx, dx
;  int 0x10
;
;  Mov si, 0 ; relative offset into 'text'
;  Mov bl, 0 ; row
;  Mov bh, 0 ; column
;drawloop:
;  Mov cl, [si+text]  ; char - will this work?
;  Cmp cl, 0 ; eof
;  Je drawloopdone
;  Cmp cl, 13 ; newline
;  Je drawnewline
;
;  ; TODO: put cl at current location
;  ; go to next location (is this free?)
; 
;  Jmp drawloop
;
;Drawnewline:
;  ; set cursor to next line  
;  Inc bl
;  ; TODO: move to beginning of line 'bl'
;  Jmp drawloop 
;
;Drawloopdone:
;  Ret
;
;; draw starting from offset at x, y to the EOL
;Drawline:
;  ret
;
;
;; move everything down one byte so we can insert a character at the current location
;Insertchar:
;  ; TODO: detect overflow
;  Inc word [textlength]
;
;  ; for dx = offset+1; i < textlength; ++i
;  ;   text[i] = text[i-1]
;  Mov dx, [offset]
;.Loop:
;  Inc dx
;  Cmp dx, [textlength]
;  Je .done
;  Mov cl, [dx]
;  Mov [dx+1], cl  ; will this work?
;  Jmp .loop
;.done
;  Ret
;
