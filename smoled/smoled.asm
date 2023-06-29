  org 0x0100

main:

; what shall it do?
; full screen

; There must be a standard for these:
; ctrl+s = save (19)
; ctrl+q = quit (17)
; ctrl+e=end of line
; ctrl+a=start of line
; INS: toggle insert mode?

; get args
; get filename from 2nd arg https://en.wikipedia.org/wiki/Program_Segment_Prefix
; load file into memory (up to 32k - that's 1/2 a segment (?)))
; draw N-1 lines of the file (what happens if > 80 chars? punt)
; draw status line (filename, dirty, mode)

; get character
; if cursor key, if y is at bottom and moving down, increase line and redraw
; if left and x = 0, beep
; if y is at top and moving up, decrease line and redraw (modulo -1)
; else if INS, toggle mode, update status line
; else if ctrl+s, save. clear dirty. update status line. 
; else if ctrl+q, if dirty, beep and increment quit counter. if counter == 2, quit
;                 if not dirty, quit.
; if printable: if insert, move all characters down, write character in memory, write char on screen
; HOW TO DEAL WITH NEWLINE?
; else if replace, write character in memory, write char on screen
; clear quit bit, if clean, set dirty and update status line

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
  mov dh, 23
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

  ; move cursor
  mov ah, 2
  xor bx, bx
  xor dx, dx
  int 0x10

save:
  mov byte [dirty], 0

resetquit:
  mov byte [quit], 0
waiting:
  ; get char
  mov ah, 7
  int 0x21
  ; al has char

  ;cmp al, 19 ; ctrl+s
  ;je save
  ;mov byte [dirty], 1
  ; TODO: update status line

  cmp al, 17 ; ctrl+q
  jne notq
  inc byte [quit]
  cmp byte [quit], 2
  je end
  jmp waiting

notq:
  cmp al, 1  ; ctrl+a
  jne nota
  mov byte [x], 0  ; beginning of line

  jmp updatecursor

nota:
  cmp al, 5  ; ctrl+e
  jne note
  mov byte [x], 79 ; beginning of line
  jmp updatecursor

note:
  cmp al, 14  ; ctrl-n
  jne notn
  inc byte [y]
  jmp updatecursor

notn:
  cmp al, 16  ; ctrl-p
  jne notp
  dec byte [y]
  jmp updatecursor
 
notp:
  cmp al, 2  ; ctrl-b
  jne notb
  dec byte [x]
  jmp updatecursor

notb:
  cmp al, 6  ; ctrl-f
  jne notf
  inc byte [x]
  jmp updatecursor

notf:
  ; put the character at the cursor position (?)
  ; only write it if it's "visible"
  cmp al, 32 
  jl waiting
  cmp al, 127
  jge waiting

  ; write the char in al at the current location
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
  jne goodcursor1
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
  mov ah, 2
  xor bx, bx
  int 0x10
  jmp waiting


end:
  ; restore cursor
  mov ch, 6
 	mov cl, 7
  mov ah, 1
  int 0x10

  int 0x20   ; back to o/s
  ret

section .data:
  TITLE: db "Smoled$", 0

  ; physical cursor location on screen
  x: db 0  ; 0-79
  y: db 0  ; 0-22

  ; what line of the file is the top line shown?
  top: db 0

  lines: db 0 ; how many lines are in the text
  offsets: times 24 dw 0 ; array of where each line of the text starts

  ; absolute location of cursor in file. how to deal with newlines?
  cursor: dw 0

  ; # of times in a row quit was hit
  quit: db 0

  dirty: db 0

  ; 23 lines x 80 rows
  text: times 1841 db 0
