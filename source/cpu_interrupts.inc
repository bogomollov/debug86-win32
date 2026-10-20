check_char_available:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    cmp     byte [kbd_peek_valid], 1
    je      .cca_avail

    invoke  GetConsoleMode, [hStdIn], kbd_temp_mode
    test    eax, eax
    jz      .cca_not_console

.cca_console_loop:
    mov     dword [events_read], 0
    invoke  PeekConsoleInputA, [hStdIn], input_record, 1, events_read
    test    eax, eax
    jz      .cca_none
    cmp     dword [events_read], 0
    jz      .cca_none

    cmp     word [input_record], 1
    jne     .cca_discard

    cmp     dword [input_record + 4], 0
    je      .cca_discard

    cmp     byte [input_record + 14], 0
    jne     .cca_got_key

    movzx   eax, word [input_record + 10]
    cmp     eax, 10h    ; VK_SHIFT
    je      .cca_discard
    cmp     eax, 11h    ; VK_CONTROL
    je      .cca_discard
    cmp     eax, 12h    ; VK_MENU
    je      .cca_discard
    cmp     eax, 14h    ; VK_CAPITAL
    je      .cca_discard
    cmp     eax, 90h    ; VK_NUMLOCK
    je      .cca_discard
    cmp     eax, 91h    ; VK_SCROLL
    je      .cca_discard

    cmp     word [input_record + 12], 0
    je      .cca_discard
    jmp     .cca_got_key

.cca_discard:
    invoke  ReadConsoleInputA, [hStdIn], input_record, 1, events_read
    jmp     .cca_console_loop

.cca_got_key:
    invoke  ReadConsoleInputA, [hStdIn], input_record, 1, events_read
    mov     al, [input_record + 14]
    mov     [kbd_peek_char], al
    mov     al, [input_record + 12]
    mov     [kbd_peek_scan], al
    mov     byte [kbd_peek_valid], 1
    jmp     .cca_avail

.cca_not_console:
    mov     dword [temp_pipe_avail], 0
    invoke  PeekNamedPipe, [hStdIn], 0, 0, 0, temp_pipe_avail, 0
    test    eax, eax
    jz      .cca_try_file
    cmp     dword [temp_pipe_avail], 0
    jz      .cca_none
    invoke  ReadFile, [hStdIn], kbd_peek_char, 1, events_read, 0
    test    eax, eax
    jz      .cca_none
    cmp     dword [events_read], 1
    jne     .cca_none
    call    .cca_setup_scan
    mov     byte [kbd_peek_valid], 1
    jmp     .cca_avail

.cca_try_file:
    invoke  ReadFile, [hStdIn], kbd_peek_char, 1, events_read, 0
    test    eax, eax
    jz      .cca_eof
    cmp     dword [events_read], 1
    jne     .cca_eof
    call    .cca_setup_scan
    mov     byte [kbd_peek_valid], 1
    jmp     .cca_avail

.cca_eof:
    mov     byte [stdin_eof], 1
    jmp     .cca_none

.cca_setup_scan:
    mov     byte [kbd_peek_scan], 0
    mov     dl, [kbd_peek_char]
    cmp     dl, 13
    jne     .css_not_cr
    mov     byte [kbd_peek_scan], 1Ch
    ret
.css_not_cr:
    cmp     dl, 8
    jne     .css_not_bs
    mov     byte [kbd_peek_scan], 0Eh
    ret
.css_not_bs:
    cmp     dl, 9
    jne     .css_not_tab
    mov     byte [kbd_peek_scan], 0Fh
    ret
.css_not_tab:
    cmp     dl, 27
    jne     .css_not_esc
    mov     byte [kbd_peek_scan], 01h
    ret
.css_not_esc:
    ret

.cca_avail:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     al, 1
    ret

.cca_none:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    xor     al, al
    ret

get_keystroke:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

.gk_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     .gk_ctrl_c
    cmp     byte [stdin_eof], 0
    jne     .gk_eof
    call    check_char_available
    test    al, al
    jnz     .gk_have_char
    cmp     byte [stdin_eof], 0
    jne     .gk_eof
    invoke  Sleep, 10
    jmp     .gk_loop

.gk_have_char:
    mov     byte [kbd_peek_valid], 0
    mov     al, [kbd_peek_char]
    mov     ah, [kbd_peek_scan]
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

.gk_eof:
    mov     al, 1Ah
    xor     ah, ah
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

.gk_ctrl_c:
    xor     ax, ax
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

handle_int21:
    push    ebx
    push    esi
    push    edi
    push    ebp

    mov     ah, byte [reg_AX+1]
    cmp     ah, 00h
    je      .prog_end
    cmp     ah, 01h
    je      .ah01
    cmp     ah, 02h
    je      .ah02
    cmp     ah, 06h
    je      .ah06
    cmp     ah, 07h
    je      .ah07_08
    cmp     ah, 08h
    je      .ah07_08
    cmp     ah, INT21_AH_PRINT_STRING
    je      .ah09
    cmp     ah, INT21_AH_BUFFERED_INPUT
    je      .ah0a
    cmp     ah, 0Bh
    je      .ah0b
    cmp     ah, 25h
    je      .ah25
    cmp     ah, 30h
    je      .ah30
    cmp     ah, 35h
    je      .ah35
    cmp     ah, INT21_AH_EXIT
    je      .prog_end
    jmp     .done

.ah01:
    call    get_keystroke
    mov     byte [reg_AX], al
    cmp     al, CR
    jne     .ah01_not_cr
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer
    jmp     .done
.ah01_not_cr:
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    jmp     .done

.ah02:
    mov     al, byte [reg_DX]
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    mov     al, byte [reg_DX]
    mov     byte [reg_AX], al
    jmp     .done

.ah06:
    cmp     byte [reg_DX], 0FFh
    jne     .ah06_out
    call    check_char_available
    test    al, al
    jz      .ah06_no_char
    mov     byte [kbd_peek_valid], 0
    mov     al, [kbd_peek_char]
    mov     byte [reg_AX], al
    mov     byte [flag_states + FLAG_ZR], 0
    jmp     .done
.ah06_no_char:
    mov     byte [reg_AX], 0
    mov     byte [flag_states + FLAG_ZR], 1
    jmp     .done
.ah06_out:
    mov     al, byte [reg_DX]
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    mov     al, byte [reg_DX]
    mov     byte [reg_AX], al
    jmp     .done

.ah07_08:
    call    get_keystroke
    mov     byte [reg_AX], al
    jmp     .done

.ah09:
    mov     ax, [reg_DS]
    mov     bx, [reg_DX]
    call    calc_linear_addr
    
    mov     ecx, MEM_SIZE
    sub     ecx, eax
    jbe     .done
    
    mov     esi, memory
    add     esi, eax
    mov     edi, esi
    push    ecx
    mov     al, '$'
    repne   scasb
    pop     ecx
    jne     .done
    
    mov     edx, edi
    sub     edx, esi
    dec     edx
    jz      .done
    
    mov     ecx, edx
    call    print_buffer
    jmp     .done

.ah0a:
    mov     ax, [reg_DS]
    mov     bx, [reg_DX]
    call    calc_linear_addr

    cmp     eax, MEM_SIZE - 2
    jae     .done

    mov     edi, memory
    add     edi, eax

    movzx   ecx, byte [edi]
    test    ecx, ecx
    jnz     .ah0a_have_max
    mov     ecx, 255
    mov     byte [edi], cl
.ah0a_have_max:

    mov     edx, MEM_SIZE - 3
    sub     edx, eax
    jbe     .done
    cmp     ecx, edx
    jbe     .ah0a_len_ok
    mov     ecx, edx
.ah0a_len_ok:

    mov     dword [int21_old_console_mode], 0
    invoke  GetConsoleMode, [hStdIn], int21_old_console_mode
    test    eax, eax
    jz      .ah0a_no_setmode
    mov     eax, [int21_old_console_mode]
    or      eax, ENABLE_PROCESSED_INPUT or ENABLE_LINE_INPUT or ENABLE_ECHO_INPUT
    invoke  SetConsoleMode, [hStdIn], eax
.ah0a_no_setmode:

    mov     dword [int21_chars_read], 0
    invoke  ReadConsoleA, [hStdIn], int21_input_buf, 255, int21_chars_read, 0
    test    eax, eax
    jnz     .ah0a_read_ok
    ; Pipe fallback for INT 21h AH=0Ah
    xor     ecx, ecx
.ah0a_pipe_loop:
    cmp     ecx, 254
    jae     .ah0a_pipe_done
    push    ecx
    lea     eax, [int21_input_buf + ecx]
    invoke  ReadFile, [hStdIn], eax, 1, int21_chars_read, 0
    pop     ecx
    test    eax, eax
    jz      .ah0a_pipe_done
    cmp     dword [int21_chars_read], 0
    jz      .ah0a_pipe_done
    mov     al, [int21_input_buf + ecx]
    inc     ecx
    cmp     al, LF
    je      .ah0a_pipe_done
    jmp     .ah0a_pipe_loop
.ah0a_pipe_done:
    mov     [int21_chars_read], ecx
.ah0a_read_ok:

    cmp     dword [int21_old_console_mode], 0
    jz      .ah0a_no_restoremode
    invoke  SetConsoleMode, [hStdIn], [int21_old_console_mode]
.ah0a_no_restoremode:

    cmp     byte [ctrl_c_flag], 0
    jne     .done

    mov     ebx, [int21_chars_read]
    xor     edx, edx
    mov     esi, int21_input_buf
.ah0a_count:
    test    ebx, ebx
    jz      .ah0a_count_done
    mov     al, [esi]
    cmp     al, 13
    je      .ah0a_count_done
    cmp     al, 10
    je      .ah0a_count_done
    inc     esi
    inc     edx
    dec     ebx
    jmp     .ah0a_count
.ah0a_count_done:

    cmp     edx, ecx
    jbe     .ah0a_clamp_ok
    mov     edx, ecx
.ah0a_clamp_ok:

    mov     byte [edi + 1], dl
    push    edi
    push    esi
    push    ecx
    cld
    lea     esi, [int21_input_buf]
    lea     edi, [edi + 2]
    mov     ecx, edx
    rep     movsb
    mov     byte [edi], 13
    pop     ecx
    pop     esi
    pop     edi
    jmp     .done

.ah0b:
    call    check_char_available
    test    al, al
    jz      .ah0b_none
    mov     byte [reg_AX], 0FFh
    jmp     .done
.ah0b_none:
    mov     byte [reg_AX], 00h
    jmp     .done

.ah25:
    movzx   eax, byte [reg_AX]
    shl     eax, 2
    mov     dx, [reg_DX]
    mov     word [memory + eax], dx
    mov     dx, [reg_DS]
    mov     word [memory + eax + 2], dx
    jmp     .done

.ah30:
    mov     word [reg_AX], 0002h
    mov     word [reg_BX], 0000h
    mov     word [reg_CX], 0000h
    jmp     .done

.ah35:
    movzx   eax, byte [reg_AX]
    shl     eax, 2
    mov     bx, word [memory + eax]
    mov     [reg_BX], bx
    mov     bx, word [memory + eax + 2]
    mov     [reg_ES], bx
    jmp     .done

.done:
    add     word [reg_IP], 2
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    mov     eax, STEP_OK
    ret

.prog_end:
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    mov     eax, STEP_PROGRAM_END
    ret


handle_int10:
    push    ebx
    push    esi
    push    edi
    push    ebp

    mov     ah, byte [reg_AX+1]
    cmp     ah, 0Eh
    je      .ah0e
    cmp     ah, 02h
    je      .ah02
    jmp     .done

.ah0e:
    mov     al, byte [reg_AX]
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    jmp     .done

.ah02:
    movzx   eax, byte [reg_DX+1]
    shl     eax, 16
    mov     al, byte [reg_DX]
    invoke  SetConsoleCursorPosition, [hStdOut], eax

.done:
    add     word [reg_IP], 2
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    mov     eax, STEP_OK
    ret


handle_int16:
    push    ebx
    push    esi
    push    edi
    push    ebp

    mov     ah, byte [reg_AX+1]
    cmp     ah, 00h
    je      .ah00
    cmp     ah, 01h
    je      .ah01
    jmp     .done

.ah00:
    call    get_keystroke
    mov     word [reg_AX], ax
    jmp     .done

.ah01:
    call    check_char_available
    test    al, al
    jz      .ah01_none
    mov     byte [flag_states + FLAG_ZR], 0
    mov     al, [kbd_peek_char]
    mov     ah, [kbd_peek_scan]
    mov     word [reg_AX], ax
    jmp     .done
.ah01_none:
    mov     byte [flag_states + FLAG_ZR], 1

.done:
    add     word [reg_IP], 2
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    mov     eax, STEP_OK
    ret


