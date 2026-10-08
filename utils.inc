print_buffer:
    push    esi
    push    ecx
    invoke  WriteConsoleA, [hStdOut], esi, ecx, chars_written, 0
    test    eax, eax
    jnz     .pb_ok
    mov     ecx, [esp]
    invoke  WriteFile, [hStdOut], esi, ecx, chars_written, 0
.pb_ok:
    pop     ecx
    pop     esi
    ret

print_string:
    push    eax
    push    ecx
    push    esi
    push    edi

    mov     edi, esi
    xor     ecx, ecx
    dec     ecx
    xor     eax, eax
    repne   scasb
    not     ecx
    dec     ecx

    push    ecx
    invoke  WriteConsoleA, [hStdOut], esi, ecx, chars_written, 0
    test    eax, eax
    jnz     .ps_ok
    mov     ecx, [esp]
    invoke  WriteFile, [hStdOut], esi, ecx, chars_written, 0
.ps_ok:
    pop     ecx

    pop     edi
    pop     esi
    pop     ecx
    pop     eax
    ret

print_error_and_ret:
    call    print_error
    ret

print_error:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    cmp     esi, input_buffer
    jb      .pe_check_cmd_ptr
    cmp     esi, input_buffer + INPUT_BUFFER_SIZE
    jb      .pe_have_ptr

.pe_check_cmd_ptr:
    mov     eax, [cmd_ptr]
    cmp     eax, input_buffer
    jb      .pe_no_ptr
    cmp     eax, input_buffer + INPUT_BUFFER_SIZE
    jae     .pe_no_ptr
    mov     esi, eax

.pe_have_ptr:
    mov     ecx, [prompt_len]
    mov     edx, input_buffer

.pe_calc_loop:
    cmp     edx, esi
    jae     .pe_calc_done
    mov     al, [edx]
    test    al, al
    jz      .pe_calc_done
    cmp     al, CR
    je      .pe_calc_done
    cmp     al, LF
    je      .pe_calc_done
    cmp     al, 9
    jne     .pe_not_tab
    add     ecx, 8
    and     ecx, not 7
    jmp     .pe_next_char
.pe_not_tab:
    inc     ecx
.pe_next_char:
    inc     edx
    jmp     .pe_calc_loop

.pe_no_ptr:
    xor     ecx, ecx

.pe_calc_done:
    cmp     ecx, LINE_BUFFER_SIZE - 16
    jbe     .pe_clamp_ok
    mov     ecx, LINE_BUFFER_SIZE - 16
.pe_clamp_ok:
    mov     edi, line_buffer
    mov     al, SPACE
    rep     stosb

    mov     esi, err_text
    mov     ecx, err_text_len
    test    ecx, ecx
    jz      .pe_copied
    cmp     byte [esi + ecx - 1], 0
    jne     .pe_copy
    dec     ecx
.pe_copy:
    rep     movsb

.pe_copied:
    mov     ecx, edi
    sub     ecx, line_buffer
    mov     esi, line_buffer
    call    print_buffer

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
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
    ja      .err
    mov     ecx, edx
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
    jnz     .l_nonzero
    mov     ecx, 10000h
    xor     cx, cx
    clc
    ret
.l_nonzero:
    movzx   ecx, ax
    mov     cx, ax
    clc
    ret