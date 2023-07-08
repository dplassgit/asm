org 0x0100

; to build:
; nasm -fbin input.asm -o input.com

  mov dx, bufinsize
  mov ah, 0x0a
  int 0x21

  xor cx, cx
  mov cl, [bufoutsize]
  mov si, buffer
  add si, cx
  mov byte [si], 36 ; '$'

printit:
  mov ah, 2
  mov dl, 13
  int 0x21

  ; print 13, 10
  mov ah, 2
  mov dl, 10
  int 0x21

  mov ah, 0x09
  mov dx, buffer
  int 0x21

  int 0x20


bufinsize: db 13
bufoutsize: db 0
buffer: times 13 db 0
