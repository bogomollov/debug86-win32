section '.text' code readable executable

put_hex_word:
    push    ax
    mov     al, ah
    call    put_hex_byte
    pop     ax
    call    put_hex_byte
    ret

put_hex_byte:
    push    ax
    mov     ah, al
    shr     al, 4
    call    put_hex_nibble
    mov     al, ah
    and     al, 0Fh
    call    put_hex_nibble
    pop     ax
    ret

put_hex_nibble:
    and     al, 0Fh
    cmp     al, 10
    jb      .digit
    add     al, 'A' - 10
    stosb
    ret
.digit:
    add     al, '0'
    stosb
    ret