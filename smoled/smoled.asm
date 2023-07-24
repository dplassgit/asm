; to build:
; nasm -fbin smoled.asm -o smoled.com


; Issues/TODO:
;  when going down and the cursor is past end of line, weird things happen
;  issues deleting the last CRLF?
;  scrolling
;  overwrites status line if file has > 23 lines
;  BUG: no newline -> NO TEXT
;  status line
;  delete/replace CRLF (only deletes the CR, not the LF, shrug. mostly works)
;  cursor keys BIOS code up 0x48 down 0x50 left 0x4b right 0x4d home 0x47 end 0x4f delete ???
;  overwrite mode; insert = BIOS code 0x52

org 0x0100

TEXT_SIZE EQU 32767
CR EQU 13
LF EQU 10

section .text

  ; Clear screen
  mov al, 0
  mov ah, 6   ; 0x06 is scroll; al=0 = clear screen
  mov bh, 7   ; attribute 7=regular white
  xor cx, cx  ; cl,ch=window upper left corner
  mov dh, 24  ; dl,dh=window lower right corner
  mov dl, 79
  int 0x10

  ; write the title
  mov bh, 0
  mov bl, 15   ; attribute: bright white
  mov cx, 7    ; length
  mov dl, 37   ; dl, dh are column, row
  mov dh, 24
  mov bp, TITLE
  mov ah, 0x13
  int 0x10

  call clear_text
  ; insert CRLF because reasons
  mov byte [text], CR
  mov byte [text+1], LF
  mov byte [filename_sizes], 79
  mov byte filename_sizes[1], 0

  ; Set initial cursor location to start of text
  call set_initial_cursor_loc

  push word 0 ; preset the lastkey to zero

wait_for_key:
%ifdef DEBUG
  ;mov bl, 52
  ;mov cx, [text_end]
  ;call printcx
%endif

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
  int 0x21  ; wait for a key
  push ax  ; save it

  cmp al, 26
  jle ctrl_something
  jmp maybeprintable

ctrl_something:
  ; get key and double it (words), for the lookup
  mov bl, al
  shl bx, 1
  call handlers[bx]
  jmp updatecursor

ctrl_a:
  mov byte [x], 0  ; beginning of line
ctrl_nop:
  ret

ctrl_b:
  dec byte [x]  ; back/prev char
  ret

ctrl_d:
  ; if x < 80, do delete
  cmp byte [x], 80
  jge .done
  inc word [cursorloc]
  call backspace
.done:
  ret

ctrl_e:
  mov byte [x], 79 ; end of physical line
  ret

ctrl_f:
  inc byte [x]  ; forward/next char
  ret

ctrl_h:
  ; if x!=0 or y!=0, do backspace
  cmp byte [x], 0
  jne .dobackspace
  cmp byte [y], 0
  jne .dobackspace
  ret
  ; not at beginning. shuffle everything down
.dobackspace:
  call backspace
  dec byte [x]
  ret

ctrl_m:
  ; insert 13, 10
  call insert_char
  mov di, [cursorloc]
  mov byte [di], CR
  call insert_char
  inc word [cursorloc]
  mov di, [cursorloc]
  mov byte [di], LF
  call draw_all

  ; go to next cursor location
  inc byte [y]
  mov byte [x], 0
  ret

ctrl_n:
  inc byte [y]  ; next line
  ret

ctrl_p:
  dec byte [y]  ; prev line
  ret

ctrl_q:
  cmp byte [dirty], 0
  je .really_quit   ; if clean, just quit
  ; dirty, but if we hit ctrl-q 2x in a row, really quit
  cmp al, [lastkey]
  je .really_quit
  ret
.really_quit:
  int 0x20  ; back to o/s


maybeprintable:
  ; detect if printable: if ascii 32 to 126
  cmp al, 32
  jl notprintable
  cmp al, 127
  jge notprintable

  ; move characters down
  call insert_char

  ; store the character in al at the current cursorloc
  mov di, [cursorloc]
  mov [di], al

  ; NOTE: this is slow on hardware, but fast on DOSBox
  ; TODO: Instead, redraw the line from this x location to the EOL.
  call draw_all

  ; go to next cursor location
  inc byte [x]

  ; fall through:

notprintable:

; update cursor location: get from x, y into dl, dh, then update dl, dh and write back into x, y
updatecursor:
  mov dl, [x] ; column
  mov dh, [y] ; row
  cmp dl, 80
  jl .goodcursor1
  ; past end of row, go to next row
  mov dl, 0
  inc dh

.goodcursor1:
  cmp dl, 0xff  ; this is weird - shouldn't it be [x]?
  jne .goodcursor2
  ; column -1 - go back one row
  mov dl, 79
  dec dh

.goodcursor2:
  cmp dh, 0xff
  jne .goodcursor3
  ; row -1, go to row 0
  mov dh, 0

.goodcursor3:
  cmp dh, 23
  jle .goodcursor4
  ; > row 24, go to row 23.
  mov dh, 23

.goodcursor4:
  mov [x], dl
  mov [y], dh
  xor bx, bx
  mov ah, 2
  int 0x10   ; update the cursor location on the screen

  call xy_to_offset

%ifdef DEBUG
  ; write current character at lower right of status
  mov dl, 79; bottom right
  mov dh, 24
  mov ah, 2
  int 0x10
  mov bl, 4  ; bright red (bh=0)
  mov al, cl   ; character to print
  mov cx, 1
  mov ah, 9
  int 0x10  ; write char and attribute
%endif

  jmp wait_for_key


; move from cursorloc to end of text back one
backspace:
  mov byte [dirty], 1
  mov di, [cursorloc]
  dec word [text_end]
.loop:
  mov cl, [di]
  mov [di-1], cl
  inc di
  ; surely this can be done with a loop, and don't call me Shirley
  cmp cl, 0
  jne .loop
  call draw_all
  ret

; Sets cursorloc and cl to the value at cursorloc
xy_to_offset:
  xor dx, dx  ; dl=x, dh=y
  mov si, text
.loop:
  mov cl, [si] ; char = text[i]
  ;If tx==x and ty ==y	// x, y are globals representing our physical location. ooh, we might be able to deal with scrolling here
  cmp dh, [y]
  jne .nothere
  ; if we gethere, dh=y
  ; TODO: if next line, or same line and x > dl, move back to prevoius newline
  cmp dl, [x]
  jne .nothere

  ; found it!
  mov [cursorloc], si
.done:
  ret

.nothere:
  cmp cl, 0
  je .done  ; should be error, shrug.

	cmp cl, CR
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


set_initial_cursor_loc:
  mov di, text
  mov [cursorloc], di
  call set_text_end
  ret

; draw the whole text starting at the top of the screen.
draw_all:
  mov si, text
  xor dx, dx ; dh=row, dl=column

.loop:
  lodsb
  cmp al, 0 ; eof
  je .done
  cmp al, CR
  je .newline

  mov di, 0   ; clear newline status

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
  mov di, 1   ; indicates last was a crlf
  ; set cursor to start of next row
  mov dl, 0
  inc dh
  jmp .loop

.done:
  cmp di, 1
  jne .notlf

  ; clear the next line (in case the # of lines is smaller)
  xor al, al
  xor bh, bh
  mov bl, 7
  mov cx, 80
  xor dl, dl
  mov bp, blankline
  mov ah, 0x13
  int 0x10

.notlf:
  ret


; Move everything down one byte so we can insert a character at the current location
insert_char:
  mov byte [dirty], 1
  mov di, [text_end]
  inc word [text_end]

  ; di now points at the zero at the end of text

; surely this can be done with a loop, and don't call me Shirley
.loop:
  mov cl, [di-1]
  mov [di], cl
  dec di
  cmp di, [cursorloc]
  jne .loop

  ret

; calculate the end of text, and set it into text_end
set_text_end:
  mov di, text
.loop:
  mov cl, [di]
  inc di
  cmp cl, 0
  jne .loop
  dec di
  mov [text_end], di
  ret

move_to_status:
  xor bx, bx
  mov dl, 0 ; bottom left
  mov dh, 24
  mov ah, 2
  int 0x10
  ret

clear_text:
  xor al, al
  mov cx, TEXT_SIZE
  mov di, text
  rep stosb   ;; WOOT!
  ret

; Puts the filename in 'filename'
get_filename:
  call move_to_status

  ; get filename
  mov ah, 0x0a
  mov dx, filename_sizes ; first byte is max size
  int 0x21   ; input

  xor bx, bx
  mov bl, filename_sizes[1] ; second byte is actual size
  mov filename_sizes[bx+2], bh ; set trailing 0
  ret


load_file:
  call get_filename

  ; open & read file
  xor al, al
  mov dx, filename
  mov ah, 0x3d
  int 0x21
  jc .load_error
  mov bx, ax  ; stash file handle in bx

  call clear_text

  mov cx, TEXT_SIZE    ; maximum size
  mov dx, text    ; destination
  mov ah, 0x3f
  int 0x21        ; read from file
  jc .load_error

  ; close file, handle still in bx
  mov ah, 0x3e
  int 0x21
  jc .load_error

  mov byte [dirty], 0
  call set_initial_cursor_loc
  call draw_all
  ret

.load_error:
  ; print an error
  mov ah, 9
  mov dx, load_error_msg
  int 0x21
  int 0x20   ; back to o/s


save_file:
  cmp byte filename_sizes[1], 0 ; is size already set?
  jne .overwrite
  call get_filename ; no, get filename

.overwrite:
  xor cx, cx   ; 0=write normal file
  mov dx, filename
  mov ah, 0x3c
  int 0x21   ; open file for write, handle in ax
  jc .error

  mov di, [text_end]
  sub di, text  ; subtract start of text
  mov cx, di   ; length in cx

  ; ax has file handle, needs to be in bx
  mov bx, ax
  mov dx, text  ; source
  mov ah, 0x40  ; write to file
  int 0x21
  jc .error

  ; close file, handle still in bx
  mov ah, 0x3e
  int 0x21
  jc .error

  mov byte [dirty], 0
  ret

.error:
  ; print an error
  mov ah, 9
  mov dx, save_error_msg
  int 0x21

  int 0x20   ; back to o/s


; prints cx at column bl
%ifdef DEBUG
printcx:
  push ax
  push bx
  push dx

  ; move to second location
  mov dl, bl
  xor bx, bx
  mov dh, 24
  mov ah, 2
  int 0x10
  call printcl

  ; move to first location for high byte
  sub dl, 2
  int 0x10
  mov cl, ch
  call printcl

  pop dx
  pop bx
  pop ax
  ret


; prints cl at the current location
printcl:
  push ax
  push bx
  push cx

  ; INT 10h / AH = 0Eh - teletype output.
  ; do 1 nibble at a time
  ; high nibble:
  mov bl, cl
  mov bh, 0
  and bl, 0xf0
  shr bl, 4
  mov al, hexchars[bx]
  ; AL = character to display.
  mov ah, 0x0e
  int 0x10

  ; INT 10h / AH = 0Eh - teletype output.
  ; do 1 nibble at a time
  ; high nibble:
  mov bl, cl
  and bl, 0x0f
  mov bh, 0
  mov al, hexchars[bx]
  ; AL = character to display.
  int 0x10

  pop cx
  pop bx
  pop ax
  ret

%endif


segment .data
%ifdef DEBUG
  hexchars: db "0123456789abcdef"
%endif

  TITLE: db "Smoled", 0

  handlers: dw ctrl_nop, ctrl_a, ctrl_b, ctrl_nop, ctrl_d, ctrl_e, ctrl_f, ctrl_nop, ctrl_h, ctrl_nop, ctrl_nop, ctrl_nop, load_file, ctrl_m, ctrl_n, ctrl_nop, ctrl_p, ctrl_q, ctrl_nop, save_file, ctrl_nop, ctrl_nop, ctrl_nop, ctrl_nop, ctrl_nop, ctrl_nop, ctrl_nop

  ; physical cursor location on screen
  x: db 0  ; 0-79
  y: db 0  ; 0-22

  ; what line of the file is the top line shown?
  ; top: db 0 ; this will be for scrolling, not v1

  dirty: db 0

  ; todo: get rid of this, save 80 bytes
  blankline: times 80 db ' '

  load_error_msg: db "Load error$"
  save_error_msg: db "Save error$"

segment .bss
  ; last key hit
  lastkey: resb 1

  ; absolute location of cursor in text
  cursorloc: resb 2

  text_end: resb 2 ; location of end of text.

  filename_sizes: resb 2 ; first byte is full size, second byte (output) is actual size
  filename: resb 80

  text: resb TEXT_SIZE
