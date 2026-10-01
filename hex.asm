section '.text' code readable executable

parse_hex:
    push    bx
    push    cx

    xor     ax, ax
    xor     cx, cx
.loop:
    mov     bl, [esi]
    cmp     bl, 'a'
    jb      .upper
    cmp     bl, 'z'
    ja      .upper
    sub     bl, 20h
.upper:
    cmp     bl, '0'
    jb      .done
    cmp     bl, '9'
    jbe     .digit
    cmp     bl, 'A'
    jb      .done
    cmp     bl, 'F'
    ja      .done
    sub     bl, 'A' - 10
    jmp     .have
.digit:
    sub     bl, '0'
.have:
    shl     ax, 4
    or      al, bl
    inc     esi
    inc     cx
    cmp     cx, 4
    jb      .loop
.done:
    test    cx, cx
    jnz     .ok
    stc
    jmp     .out
.ok:
    clc
.out:
    pop     cx
    pop     bx
    ret

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