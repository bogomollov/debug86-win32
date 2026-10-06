print_buffer:
    push    esi
    push    ecx
    invoke  WriteConsoleA, [hStdOut], esi, ecx, chars_written, 0
    pop     ecx
    pop     esi
    ret

print_error_and_ret:
    call    print_error
    ret

print_error:
    mov     esi, err_text
    mov     ecx, err_text_len
    call    print_buffer
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
    cmp     dword [old_console_mode], 0
    je      .do_exit
    invoke  SetConsoleMode, [hStdIn], [old_console_mode]
.do_exit:
    invoke  ExitProcess, 0

skip_whitespace:
    mov     al, [esi]
    cmp     al, SPACE
    je      .adv
    cmp     al, 9
    je      .adv
    cmp     al, COMMA
    je      .adv
    ret
.adv:
    inc     esi
    jmp     skip_whitespace

is_eol:
    mov     al, [esi]
    cmp     al, CR
    je      .yes
    cmp     al, LF
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
    cmp     byte [esi+2], COLON
    jne     .parse_num

    mov     ax, cx
    add     esi, 3
    call    skip_whitespace
    mov     dx, ax
    call    parse_hex
    jc      .err
    mov     bx, ax
    mov     ax, dx
    clc
    ret

.parse_num:
    call    parse_hex
    jc      .err
    mov     bx, ax

    call    skip_whitespace
    cmp     al, COLON
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

    mov     bx, ax

    call    skip_whitespace
    cmp     al, COLON
    je      .full_end

    mov     ax, bp
    jmp     .calc

.full_end:
    inc     esi
    push    bx
    call    skip_whitespace
    call    parse_hex
    jc      .err_pop
    mov     bx, ax
    pop     ax

.calc:
    movzx   ecx, bp
    shl     ecx, 4
    movzx   edx, dx
    add     ecx, edx

    movzx   edx, ax
    shl     edx, 4
    movzx   eax, bx
    add     edx, eax

    cmp     edx, ecx
    jb      .err
    sub     edx, ecx
    inc     edx
    cmp     edx, 10000h
    jae     .err
    mov     cx, dx
    clc
    ret

.err_pop:
    pop     ax
.err:
    stc
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