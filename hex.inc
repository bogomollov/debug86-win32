parse_hex:
    push    bx
    push    cx
    xor     ax, ax
    xor     cx, cx
ph_loop:
    mov     bl, [esi]
    cmp     bl, '0'
    jb      ph_done
    cmp     bl, '9'
    jbe     ph_digit
    
    or      bl, 20h
    cmp     bl, 'a'
    jb      ph_done
    cmp     bl, 'f'
    ja      ph_done
    sub     bl, 'a' - 10
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
    jz      ph_err
    cmp     cx, 4
    jb      ph_ok

    mov     bl, [esi]
    cmp     bl, '0'
    jb      ph_ok
    cmp     bl, '9'
    jbe     ph_err
    or      bl, 20h
    cmp     bl, 'a'
    jb      ph_ok
    cmp     bl, 'f'
    jbe     ph_err

ph_ok:
    clc
    jmp     ph_out
ph_err:
    stc
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
    cmp     bl, '0'
    jb      phb_done
    cmp     bl, '9'
    jbe     phb_digit
    
    or      bl, 20h
    cmp     bl, 'a'
    jb      phb_done
    cmp     bl, 'f'
    ja      phb_done
    sub     bl, 'a' - 10
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
    jz      phb_err
    cmp     cx, 2
    jb      phb_ok

    mov     bl, [esi]
    cmp     bl, '0'
    jb      phb_ok
    cmp     bl, '9'
    jbe     phb_err
    or      bl, 20h
    cmp     bl, 'a'
    jb      phb_ok
    cmp     bl, 'f'
    jbe     phb_err

phb_ok:
    clc
    jmp     phb_out
phb_err:
    stc
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