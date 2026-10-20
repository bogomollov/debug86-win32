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

; In: edi = end of line_buffer
print_line_buffer:
    mov     ecx, edi
    sub     ecx, line_buffer
    mov     esi, line_buffer
    jmp     print_buffer

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

; ============================================================================
; decode_modrm_ea
; Decodes 8086 ModR/M effective address and displacement.
;
; In:  esi = pointer to instruction opcode byte ([esi+1] = modrm byte)
; Out: bx  = effective address offset
;      dx  = default segment word value (from reg_DS or reg_SS)
;      eax = default segment name ('DS' or 'SS')
;      ecx = displacement length (0, 1, or 2 bytes)
; Preserves: esi, edi, ebp
; ============================================================================
decode_modrm_ea:
    movzx   eax, byte [esi+1]   ; ModR/M byte
    mov     cl, al
    shr     cl, 6               ; cl = mod (0..3)
    and     al, 7               ; al = rm (0..7)

    cmp     cl, 3
    jne     .ea_is_mem

    ; mod == 3: register operand (no memory ea)
    xor     ebx, ebx
    xor     ecx, ecx
    mov     eax, 'DS'
    mov     dx, word [reg_DS]
    ret

.ea_is_mem:
    cmp     al, 0
    jne     .ea_rm1
    movzx   ebx, word [reg_BX]
    add     bx, word [reg_SI]
    mov     edx, 'DS'
    jmp     .ea_apply_disp

.ea_rm1:
    cmp     al, 1
    jne     .ea_rm2
    movzx   ebx, word [reg_BX]
    add     bx, word [reg_DI]
    mov     edx, 'DS'
    jmp     .ea_apply_disp

.ea_rm2:
    cmp     al, 2
    jne     .ea_rm3
    movzx   ebx, word [reg_BP]
    add     bx, word [reg_SI]
    mov     edx, 'SS'
    jmp     .ea_apply_disp

.ea_rm3:
    cmp     al, 3
    jne     .ea_rm4
    movzx   ebx, word [reg_BP]
    add     bx, word [reg_DI]
    mov     edx, 'SS'
    jmp     .ea_apply_disp

.ea_rm4:
    cmp     al, 4
    jne     .ea_rm5
    movzx   ebx, word [reg_SI]
    mov     edx, 'DS'
    jmp     .ea_apply_disp

.ea_rm5:
    cmp     al, 5
    jne     .ea_rm6
    movzx   ebx, word [reg_DI]
    mov     edx, 'DS'
    jmp     .ea_apply_disp

.ea_rm6:
    cmp     al, 6
    jne     .ea_rm7
    test    cl, cl
    jnz     .ea_bp_base
    ; mod == 0, rm == 6: direct 16-bit address
    movzx   ebx, word [esi+2]
    mov     edx, 'DS'
    mov     ecx, 2
    jmp     .ea_done

.ea_bp_base:
    movzx   ebx, word [reg_BP]
    mov     edx, 'SS'
    jmp     .ea_apply_disp

.ea_rm7:
    movzx   ebx, word [reg_BX]
    mov     edx, 'DS'

.ea_apply_disp:
    test    cl, cl
    jz      .ea_disp_zero
    cmp     cl, 1
    je      .ea_disp_byte
    ; mod == 2: 16-bit displacement
    add     bx, word [esi+2]
    mov     ecx, 2
    jmp     .ea_done

.ea_disp_byte:
    ; mod == 1: 8-bit sign-extended displacement
    movsx   ax, byte [esi+2]
    add     bx, ax
    mov     ecx, 1
    jmp     .ea_done

.ea_disp_zero:
    xor     ecx, ecx

.ea_done:
    mov     eax, edx
    cmp     eax, 'SS'
    je      .ea_seg_ss
    mov     dx, word [reg_DS]
    ret

.ea_seg_ss:
    mov     dx, word [reg_SS]
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

    add     esi, 3
    call    skip_whitespace
    mov     dx, cx
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

parse_address_cs:
    call    skip_whitespace
    push    esi
.check_colon_loop:
    mov     al, [esi]
    test    al, al
    jz      .no_colon_found
    cmp     al, CR
    je      .no_colon_found
    cmp     al, LF
    je      .no_colon_found
    cmp     al, ' '
    je      .no_colon_found
    cmp     al, 9
    je      .no_colon_found
    cmp     al, COMMA
    je      .no_colon_found
    cmp     al, COLON
    je      .colon_found
    inc     esi
    jmp     .check_colon_loop

.colon_found:
    pop     esi
    call    parse_address
    ret

.no_colon_found:
    pop     esi
    call    parse_hex
    jc      .pac_err
    mov     bx, ax
    mov     ax, [reg_CS]
    clc
    ret
.pac_err:
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
    clc
    ret
.l_nonzero:
    movzx   ecx, ax
    clc
    ret

print_br_error:
    mov     esi, msg_br_error
    mov     ecx, msg_br_error_len
    call    print_buffer
    ret

print_bf_error:
    mov     esi, msg_bf_error
    mov     ecx, msg_bf_error_len
    call    print_buffer
    ret

print_df_error:
    mov     esi, msg_df_error
    mov     ecx, msg_df_error_len
    call    print_buffer
    ret

print_bp_error:
    mov     esi, msg_bp_error
    mov     ecx, msg_bp_error_len
    call    print_buffer
    ret

; In: edi = buffer, edx = max_len
; Out: [chars_read] = count, CF = 0 if ok, CF = 1 if EOF
read_line_console_or_pipe:
    push    ebx
    push    esi
    push    edx
    mov     byte [edi], 0
    invoke  ReadConsoleA, [hStdIn], edi, edx, chars_read, 0
    test    eax, eax
    jnz     .rl_console_ok

    cmp     byte [ctrl_c_flag], 0
    jnz     .rl_ctrl_c

    ; Fallback for redirected input (pipe)
    pop     edx             ; max_len
    push    edx
    xor     ebx, ebx
.rl_pipe_loop:
    cmp     ebx, edx
    jae     .rl_pipe_done
    push    ebx
    push    edx
    lea     eax, [edi + ebx]
    invoke  ReadFile, [hStdIn], eax, 1, chars_read, 0
    pop     edx
    pop     ebx
    test    eax, eax
    jz      .rl_pipe_eof
    cmp     dword [chars_read], 0
    jz      .rl_pipe_eof
    mov     al, [edi + ebx]
    inc     ebx
    cmp     al, LF
    je      .rl_pipe_done
    jmp     .rl_pipe_loop

.rl_pipe_eof:
    test    ebx, ebx
    jnz     .rl_pipe_done
    pop     edx
    pop     esi
    pop     ebx
    stc
    ret

.rl_pipe_done:
    mov     [chars_read], ebx
    mov     byte [edi + ebx], 0
    pop     edx
    pop     esi
    pop     ebx
    clc
    ret

.rl_console_ok:
    pop     edx
    mov     eax, [chars_read]
    mov     byte [edi + eax], 0
    pop     esi
    pop     ebx
    clc
    ret

.rl_ctrl_c:
    pop     edx
    pop     esi
    pop     ebx
    stc
    ret


; In: esi = input stream, edi = destination buffer, edx = max length
; Out: ecx = pattern length, CF = 0 if ok, CF = 1 if syntax error or empty pattern
parse_pattern_list:
    push    ebx
    push    edx
    push    ebp
    mov     ebp, edx
    xor     ecx, ecx

.ppl_next_token:
    call    skip_whitespace
    call    is_eol
    jc      .ppl_pat_done

    cmp     ecx, ebp
    jae     .ppl_pat_done

    cmp     al, QUOTE_DOUBLE
    je      .ppl_string
    cmp     al, QUOTE_SINGLE
    je      .ppl_string

    call    parse_hex_byte
    jc      .ppl_error
    stosb
    inc     ecx
    jmp     .ppl_next_token

.ppl_string:
    mov     dl, al
    inc     esi
.ppl_str_loop:
    mov     al, [esi]
    call    is_eol
    jc      .ppl_error
    cmp     al, dl
    je      .ppl_str_end

    cmp     ecx, ebp
    jae     .ppl_pat_done

    stosb
    inc     ecx
    inc     esi
    jmp     .ppl_str_loop

.ppl_str_end:
    inc     esi
    jmp     .ppl_next_token

.ppl_pat_done:
    test    ecx, ecx
    jz      .ppl_error
    pop     ebp
    pop     edx
    pop     ebx
    clc
    ret

.ppl_error:
    pop     ebp
    pop     edx
    pop     ebx
    stc
    ret
