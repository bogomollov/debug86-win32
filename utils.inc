print_error_and_ret:
    call    print_error
    ret

print_error:
    invoke  WriteConsoleA, [hStdOut], err_text, err_text_len, chars_written, 0
    ret

check_mem_range:
    push    edx
    mov     edx, eax
    add     edx, ecx
    jc      .bad
    cmp     edx, MEM_SIZE
    ja      .bad
    pop     edx
    clc
    ret
.bad:
    pop     edx
    stc
    ret

exit_program:
    invoke  ExitProcess, 0

skip_whitespace:
    mov     al, [esi]
    cmp     al, ' '
    je      .adv
    cmp     al, 9
    je      .adv
    ret
.adv:
    inc     esi
    jmp     skip_whitespace

is_eol:
    mov     al, [esi]
    cmp     al, 13
    je      .yes
    cmp     al, 10
    je      .yes
    test    al, al
    jz      .yes
    clc
    ret
.yes:
    stc
    ret

calc_linear_addr:
    movzx   eax, ax
    shl     eax, 4
    movzx   ebx, bx
    add     eax, ebx
    ret

parse_address:
    call    skip_whitespace
    
    mov     bl, [esi]
    or      bl, 20h
    cmp     bl, 'd'
    je      .seg_ds
    cmp     bl, 'c'
    je      .seg_cs
    cmp     bl, 'e'
    je      .seg_es
    cmp     bl, 's'
    je      .seg_ss
    jmp     .parse_num

.seg_ds: mov cx, [reg_DS]
         jmp .check_s
.seg_cs: mov cx, [reg_CS]
         jmp .check_s
.seg_es: mov cx, [reg_ES]
         jmp .check_s
.seg_ss: mov cx, [reg_SS]

.check_s:
    mov     bl, [esi+1]
    or      bl, 20h
    cmp     bl, 's'
    jne     .parse_num
    cmp     byte [esi+2], ':'
    jne     .parse_num
    
    mov     ax, cx
    add     esi, 3
    call    skip_whitespace
    call    parse_hex
    jc      .err
    mov     bx, ax
    clc
    ret

.parse_num:
    call    parse_hex
    jc      .err
    mov     bx, ax

    call    skip_whitespace
    cmp     al, ':'
    jne     .no_colon

    inc     esi
    call    skip_whitespace
    call    parse_hex
    jc      .err
    
    push    ax
    mov     ax, bx
    pop     bx
    clc
    ret

.no_colon:
    mov     ax, [reg_DS]
    clc
    ret
.err:
    stc
    ret

parse_length:
    call    skip_whitespace
    call    is_eol
    jc      .err
    
    mov     bl, al
    or      bl, 20h
    cmp     bl, 'l'
    je      .have_l

    call    parse_hex
    jc      .err
    cmp     ax, dx
    jb      .err
    sub     ax, dx
    inc     ax
    mov     cx, ax
    clc
    ret

.have_l:
    inc     esi
    call    skip_whitespace
    call    parse_hex
    jc      .err
    test    ax, ax
    jz      .err
    mov     cx, ax
    clc
    ret
.err:
    stc
    ret