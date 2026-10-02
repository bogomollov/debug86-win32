section '.text' code readable executable

parse_hex:
    push    bx
    push    cx

    xor     ax, ax
    xor     cx, cx
ph_loop:
    mov     bl, [esi]
    cmp     bl, 'a'
    jb      ph_upper
    cmp     bl, 'z'
    ja      ph_upper
    sub     bl, 20h
ph_upper:
    cmp     bl, '0'
    jb      ph_done
    cmp     bl, '9'
    jbe     ph_digit
    cmp     bl, 'A'
    jb      ph_done
    cmp     bl, 'F'
    ja      ph_done
    sub     bl, 'A' - 10
    jmp     ph_have
ph_digit:
    sub     bl, '0'
ph_have:
    shl     ax, 4
    or      al, bl
    inc     esi
    inc     cx
    cmp     cx, 4
    jb      ph_loop
ph_done:
    test    cx, cx
    jnz     ph_ok
    stc
    jmp     ph_out
ph_ok:
    clc
ph_out:
    pop     cx
    pop     bx
    ret

parse_hex_byte:
    push    bx
    push    cx
    xor     ax, ax
    xor     cx, cx
phb_loop:
    mov     bl, [esi]
    cmp     bl, 'a'
    jb      phb_upper
    cmp     bl, 'z'
    ja      phb_upper
    sub     bl, 20h
phb_upper:
    cmp     bl, '0'
    jb      phb_done
    cmp     bl, '9'
    jbe     phb_digit
    cmp     bl, 'A'
    jb      phb_done
    cmp     bl, 'F'
    ja      phb_done
    sub     bl, 'A' - 10
    jmp     phb_have
phb_digit:
    sub     bl, '0'
phb_have:
    shl     al, 4
    or      al, bl
    inc     esi
    inc     cx
    cmp     cx, 2
    jb      phb_loop
phb_done:
    test    cx, cx
    jnz     phb_ok
    stc
    jmp     phb_out
phb_ok:
    clc
phb_out:
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