parse_hex:
    push    bx
    push    cx
    xor     bx, bx
    xor     cx, cx
.loop:
    mov     al, [esi]
    call    hex_to_val
    jc      .done
    shl     bx, 4
    or      bl, al
    inc     esi
    inc     cx
    jmp     .loop
.done:
    test    cx, cx
    jz      .err
    mov     ax, bx
    clc
    jmp     .out
.err:
    stc
.out:
    pop     cx
    pop     bx
    ret

parse_hex_byte:
    push    bx
    push    cx
    xor     bx, bx
    xor     cx, cx
.loop:
    mov     al, [esi]
    call    hex_to_val
    jc      .done
    shl     bl, 4
    or      bl, al
    inc     esi
    inc     cx
    cmp     cx, 2
    jb      .loop
.done:
    test    cx, cx
    jz      .err
    cmp     cx, 2
    jb      .ok
    mov     al, [esi]
    call    hex_to_val
    jnc     .err
.ok:
    mov     al, bl
    clc
    jmp     .out
.err:
    stc
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
    jb      phn_digit
    add     al, 'A' - 10
    stosb
    ret
phn_digit:
    add     al, '0'
    stosb
    ret

hex_to_val:
    cmp     al, '0'
    jb      .invalid
    cmp     al, '9'
    jbe     .digit
    mov     ah, al
    or      ah, 20h
    cmp     ah, 'a'
    jb      .invalid
    cmp     ah, 'f'
    ja      .invalid
    sub     ah, 'a' - 10
    mov     al, ah
    clc
    ret
.digit:
    sub     al, '0'
    clc
    ret
.invalid:
    stc
    ret