cmd_register:
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .show_all

    mov     al, [esi]
    or      al, 20h
    cmp     al, 'f'
    jne     .parse_reg
    mov     ah, [esi+1]
    cmp     ah, ' '
    je      .is_rf
    cmp     ah, 9
    je      .is_rf
    cmp     ah, CR
    je      .is_rf
    cmp     ah, LF
    je      .is_rf
    test    ah, ah
    jz      .is_rf
    jmp     .parse_reg

.is_rf:
    inc     esi
    call    skip_whitespace
    call    is_eol
    jnc     print_error_and_ret
    jmp     cmd_rf

.parse_reg:
    call    parse_reg_name
    jc      .bad_reg
    mov     [edit_reg_ptr], eax
    call    skip_whitespace
    call    is_eol
    jnc     print_error_and_ret

    mov     edi, line_buffer
    mov     al, [edit_reg_name+0]
    stosb
    mov     al, [edit_reg_name+1]
    stosb
    mov     al, SPACE
    stosb

    mov     eax, [edit_reg_ptr]
    mov     ax, [eax]
    call    put_hex_word

    mov     al, CR
    stosb
    mov     al, LF
    stosb
    mov     al, COLON
    stosb

    call    print_line_buffer

    mov     edi, input_buffer
    mov     edx, 255
    call    read_line_console_or_pipe

    mov     esi, input_buffer
    call    skip_whitespace
    call    is_eol
    jc      .reg_done

    call    parse_hex
    jc      print_error_and_ret
    push    ax
    call    skip_whitespace
    call    is_eol
    pop     ax
    jnc     print_error_and_ret

    mov     edi, [edit_reg_ptr]
    mov     [edi], ax

.reg_done:
    ret

.bad_reg:
    call    print_br_error
    ret

.show_all:
    jmp     show_cpu_state

show_cpu_state:
    call    print_registers

    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    mov     cl, 1
    call    disasm_line
    ret


cmd_rf:
    call    show_flags

    mov     edi, input_buffer
    mov     edx, 255
    call    read_line_console_or_pipe

    mov     esi, input_buffer
    call    skip_whitespace
    call    is_eol
    jc      .rf_done

    xor     ebp, ebp

.rf_parse_loop:
    call    skip_whitespace
    call    is_eol
    jc      .rf_done

    mov     al, [esi]
    test    al, al
    jz      .rf_done
    cmp     al, CR
    je      .rf_done
    cmp     al, LF
    je      .rf_done

    or      al, 20h
    mov     ah, al
    inc     esi
    mov     al, [esi]
    or      al, 20h
    inc     esi

    mov     edi, flag_map
.rf_find:
    cmp     byte [edi + FLAG_ENTRY_NAME_OFF], 0
    je      .rf_bad_flag
    cmp     ah,  [edi + FLAG_ENTRY_NAME_OFF]
    jne     .rf_skip
    cmp     al,  [edi + FLAG_ENTRY_NAME_OFF + 1]
    jne     .rf_skip

    movzx   ebx, byte [edi + FLAG_ENTRY_INDEX_OFF]
    bt      ebp, ebx
    jc      .rf_dup_flag
    bts     ebp, ebx
    mov     al, [edi + FLAG_ENTRY_VALUE_OFF]
    mov     [flag_states + ebx], al
    jmp     .rf_parse_loop

.rf_skip:
    add     edi, FLAG_MAP_RECORD_SIZE
    jmp     .rf_find

.rf_bad_flag:
    call    print_bf_error
    ret

.rf_dup_flag:
    call    print_df_error
    ret

.rf_done:
    ret

append_flags:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi

    xor     ebx, ebx
    mov ecx, FLAG_COUNT
.af_loop:
    mov     al, [flag_states + ebx]
    test    al, al
    jz      .af_use_clr
    mov     esi, flag_set_codes
    jmp     .af_copy
.af_use_clr:
    mov     esi, flag_clr_codes
.af_copy:
    mov     eax, ebx
    shl     eax, 1
    add     esi, eax
    movsw
    mov     al, SPACE
    stosb
    inc     ebx
    loop    .af_loop

    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

show_flags:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    mov     edi, line_buffer
    call    append_flags

    mov     al, '-'
    stosb
    mov     al, SPACE
    stosb

    call    print_line_buffer

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret


parse_reg_name:
    push    esi
    mov     edi, edit_reg_name
    xor     ecx, ecx
.rd_name:
    mov     al, [esi]
    test    al, al
    jz      .rd_name_done
    cmp     al, CR
    je      .rd_name_done
    cmp     al, 10
    je      .rd_name_done
    cmp     al, ' '
    je      .rd_name_done
    cmp     al, 9
    je      .rd_name_done

    cmp     al, 'A'
    jb      .rd_store
    cmp     al, 'Z'
    ja      .rd_store
    add     al, 20h
.rd_store:
    stosb
    inc     esi
    inc     ecx
    cmp     ecx, 3
    jb      .rd_name
.rd_name_done:
    mov     byte [edi], 0
    test    ecx, ecx
    jz      .rd_err
    cmp     ecx, 2
    jne     .rd_err

    mov     ebx, reg_name_table
.rt_loop:
    cmp     byte [ebx + REG_ENTRY_NAME_OFF], 0
    je      .rd_err
    mov     cl,  [ebx + REG_ENTRY_NAME_OFF]
    cmp     cl,  [edit_reg_name]
    jne     .rt_next
    mov     cl,  [ebx + REG_ENTRY_NAME_OFF + 1]
    cmp     cl,  [edit_reg_name+1]
    jne     .rt_next
    mov     eax, [ebx + REG_ENTRY_PTR_OFF]
    pop     edx
    clc
    ret
.rt_next:
    add     ebx, REG_NAME_RECORD_SIZE
    jmp     .rt_loop

.rd_err:
    pop     esi
    stc
    ret

print_registers:
    push    esi
    push    edi
    push    ecx
    push    ebx

    mov     edi, line_buffer
    lea     esi, [reg_names]
    lea     ebx, [cpu_state]
    mov     ecx, REG_PRINT_COUNT
    xor     edx, edx

.pr_loop:
    lodsw
    stosw
    mov     al, '='
    stosb
    mov     ax, [ebx]
    call    put_hex_word
    mov     al, SPACE
    stosb
    stosb

    add     ebx, 2
    inc     edx
    cmp     edx, 8
    jne     .pr_next
    sub     edi, 2
    mov     al, CR
    stosb
    mov     al, LF
    stosb
.pr_next:
    loop    .pr_loop

    mov     al, SPACE
    stosb

    call    append_flags

    mov     al, CR
    stosb
    mov     al, LF
    stosb

    call    print_line_buffer

    pop     ecx
    pop     ebx
    pop     edi
    pop     esi
    ret


