org 0x0100

loop:
  ; check if there is something in kb buffer
  mov ah, 1
  int 0x16
  je loop

  ; get key from buffer
  mov ah, 0
  int 0x16

  cmp al, 3  ; ctrl+c
  je end
  mov dx, ax   ; save in dx
  push dx
  ; AH = BIOS scan code.
  ; AL = ASCII character.

  mov ah, 9
  mov dx, ascii_msg
  int 0x21

  ; print ascii char (already in al)
  pop dx
  push dx
  mov al, dl
  mov ah, 2
  int 0x21

  call printnum   ; prints num in dl

  mov ah, 9
  mov dx, bios_msg
  int 0x21

  ;mov ah, 2
  ;pop dx
  ;push dx
  ;mov dl, dh  ; print bios scan code
  ;int 0x21

  pop dx
  mov al, dh
  call printnum

  jmp loop

end:
  int 0x20
  ret

printnum:
  ; print al in hex
  push ax
  shr al, 4 ; top nbble
  call printnibble
  pop ax
  push ax
  and ax, 0x0f
  call printnibble
  pop ax

  ret

printnibble:
  ; print the nibble in the lower 4 bits of al
  mov si, ax
  and si, 0x0f
  mov dl, [hex+si]
  mov ah, 2
  int 0x21
  ret

  

ascii_msg: db 13, 10, "ascii:", 13, 10, "$"
bios_msg: db 13, 10, "bios:", 13, 10, "$"
hex: db "0123456789ABCDEF"
