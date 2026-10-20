cmd_dump:
    mov     dword [dump_len], DUMP_DEFAULT_LEN
    mov     esi, [cmd_ptr]

    call    skip_whitespace
    call    is_eol
    jc      .do_it

    call    parse_address
    jc      print_error_and_ret
    mov     [dump_seg], ax
    mov     [dump_off], bx
    mov     bp, ax

    mov     dword [dump_len], DUMP_DEFAULT_LEN

    mov     dx, bx
    call    skip_whitespace
    call    is_eol
    jc      .do_it

    call    parse_length
    jc      print_error_and_ret
    mov     [dump_len], ecx

    call    skip_whitespace
    call    is_eol
    jnc     print_error_and_ret

.do_it:
    mov     ax, [dump_seg]
    mov     bx, [dump_off]
    call    calc_linear_addr
    mov     ecx, [dump_len]
    call    check_mem_range
    jc      print_error_and_ret
    call    do_dump
    ret

cmd_fill:
    mov     esi, [cmd_ptr]

    call    parse_address
    jc      print_error_and_ret
    mov     [fill_seg], ax
    mov     [fill_off], bx
    mov     bp, ax

    mov     dx, bx
    call    parse_length
    jc      print_error_and_ret
    mov     [fill_len], ecx

    mov     edi, fill_pat
    mov     edx, FILL_PAT_MAX
    call    parse_pattern_list
    jc      print_error_and_ret
    mov     [fill_patlen], cx

.cf_do_fill:
    mov     ax, [fill_seg]
    mov     bx, [fill_off]
    call    calc_linear_addr

    mov     ecx, [fill_len]
    call    check_mem_range
    jc      print_error_and_ret

    mov     edi, memory
    add     edi, eax

    mov     ecx, [fill_len]
    mov     esi, fill_pat
    movzx   edx, word [fill_patlen]
    xor     ebx, ebx

.cf_fill_loop:
    test    ecx, ecx
    jz      .cf_ret
    mov     al, [esi + ebx]
    mov     [edi], al
    inc     edi
    inc     ebx
    cmp     ebx, edx
    jb      .cf_no_wrap
    xor     ebx, ebx
.cf_no_wrap:
    dec     ecx
    jmp     .cf_fill_loop

.cf_ret:
    ret

cmd_edit:
    mov     esi, [cmd_ptr]

    call    parse_address
    jc      print_error_and_ret
    mov     [edit_seg], ax
    mov     [edit_off], bx

    mov     ax, [edit_seg]
    mov     bx, [edit_off]
    call    calc_linear_addr

    mov     ecx, 1
    call    check_mem_range
    jc      print_error_and_ret

    mov     ebp, memory
    add     ebp, eax

    call    skip_whitespace
    call    is_eol
    jc      .ce_interactive

    mov     edi, ebp
.ce_next_token:
    call    skip_whitespace
    call    is_eol
    jc      .ce_ret

    cmp     edi, memory + MEM_SIZE
    jae     print_error_and_ret

    cmp     al, 22h
    je      .ce_string
    cmp     al, 27h
    je      .ce_string

    call    parse_hex_byte
    jc      print_error_and_ret
    mov     [edi], al
    inc     edi
    jmp     .ce_next_token

.ce_string:
    mov     dl, al
    inc     esi
.ce_str_loop:
    mov     al, [esi]
    call    is_eol
    jc      print_error_and_ret
    cmp     al, dl
    je      .ce_str_end

    cmp     edi, memory + MEM_SIZE
    jae     print_error_and_ret

    mov     [edi], al
    inc     edi
    inc     esi
    jmp     .ce_str_loop
.ce_str_end:
    inc     esi
    jmp     .ce_next_token

.ce_interactive:
    invoke  GetConsoleMode, [hStdIn], old_console_mode
    mov     eax, [old_console_mode]
    and     eax, not 6
    invoke  SetConsoleMode, [hStdIn], eax

    mov     byte [edit_have_nibble], 0
    mov     byte [edit_cell_done], 0

    mov     al, [ebp]
    mov     [edit_orig_byte], al

    mov     dl, 2
    call    ce_show_byte
    jc      .ce_int_done

.ce_int_read:
    invoke  ReadConsoleA, [hStdIn], edit_char, 1, edit_chars_read, 0
    test    eax, eax
    jnz     .ce_read_ok
    invoke  ReadFile, [hStdIn], edit_char, 1, edit_chars_read, 0
    test    eax, eax
    jz      .ce_int_done
    cmp     dword [edit_chars_read], 0
    jz      .ce_int_done
.ce_read_ok:
    mov     al, [edit_char]

    cmp     al, 13
    je      .ce_int_done
    cmp     al, 10
    je      .ce_int_done
    cmp     al, ' '
    je      .ce_int_space
    cmp     al, '-'
    je      .ce_int_minus
    cmp     al, 8
    je      .ce_int_back
    cmp     al, 127
    je      .ce_int_back

    call    hex_to_val
    jc      .ce_int_read

    cmp     byte [edit_cell_done], 0
    jne     .ce_int_read

    mov     [line_buffer+1], al
    mov     al, [edit_char]
    mov     [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    mov     al, [line_buffer+1]

    cmp     byte [edit_have_nibble], 0
    jne     .ce_int_second
    mov     [edit_nibble], al
    mov     byte [edit_have_nibble], 1
    jmp     .ce_int_read

.ce_int_second:
    mov     dl, [edit_nibble]
    shl     dl, 4
    or      dl, al
    mov     [ebp], dl
    mov     byte [edit_have_nibble], 0
    mov     byte [edit_cell_done], 1
    jmp     .ce_int_read

.ce_int_back:
    cmp     byte [edit_cell_done], 0
    jne     .ce_back_second
    cmp     byte [edit_have_nibble], 0
    jne     .ce_back_first
    jmp     .ce_int_read

.ce_back_second:
    mov     byte [edit_cell_done], 0
    mov     byte [edit_have_nibble], 1
    mov     al, [edit_nibble]
    shl     al, 4
    mov     [ebp], al
    call    .ce_erase_char
    jmp     .ce_int_read

.ce_back_first:
    mov     byte [edit_have_nibble], 0
    mov     al, [edit_orig_byte]
    mov     [ebp], al
    call    .ce_erase_char
    jmp     .ce_int_read

.ce_erase_char:
    mov     byte [line_buffer], 8
    mov     byte [line_buffer+1], ' '
    mov     byte [line_buffer+2], 8
    mov     esi, line_buffer
    mov     ecx, 3
    call    print_buffer
    ret

.ce_commit_nibble:
    cmp     byte [edit_have_nibble], 0
    jz      .ce_commit_ret
    mov     al, [edit_nibble]
    mov     [ebp], al
    mov     byte [edit_have_nibble], 0
.ce_commit_ret:
    ret

.ce_int_space:
    call    .ce_commit_nibble
    mov     byte [edit_cell_done], 0
    inc     word [edit_off]
.ce_int_space_chk_line:
    test    word [edit_off], 0Fh
    jz      .ce_int_space_newline
    xor     dl, dl
    jmp     .ce_int_space_show
.ce_int_space_newline:
    mov     dl, 1
.ce_int_space_show:
    call    ce_show_byte
    jc      .ce_int_done
    jmp     .ce_int_read

.ce_int_minus:
    call    .ce_commit_nibble
    mov     byte [edit_cell_done], 0

    dec     word [edit_off]

.ce_int_minus_chk_line:
    mov     ax, [edit_off]
    and     ax, 0Fh
    cmp     ax, 0Fh
    jne     .ce_int_minus_same_line
    mov     dl, 1
    jmp     .ce_int_minus_show

.ce_int_minus_same_line:
    xor     dl, dl

.ce_int_minus_show:
    call    ce_show_byte
    jc      .ce_int_done
    jmp     .ce_int_read

.ce_int_done:
    call    .ce_commit_nibble
    invoke  SetConsoleMode, [hStdIn], [old_console_mode]
    mov     byte [line_buffer], 13
    mov     byte [line_buffer+1], 10
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer
.ce_ret:
    ret

ce_show_byte:
    push    edx
    
    mov     ax, [edit_seg]
    mov     bx, [edit_off]
    call    calc_linear_addr

    mov     ecx, 1
    call    check_mem_range
    jc      .csb_err

    mov     ebp, memory
    add     ebp, eax

    mov     al, [ebp]
    mov     [edit_orig_byte], al

    pop     edx
    mov     edi, line_buffer
    test    dl, dl
    jz      .csb_normal

    cmp     dl, 2
    je      .csb_addr

    mov     al, CR
    stosb
    mov     al, LF
    stosb

.csb_addr:
    mov     ax, [edit_seg]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, [edit_off]
    call    put_hex_word
    mov     al, SPACE
    stosb
    jmp     .csb_byte

.csb_normal:
    mov     al, SPACE
    stosb
    stosb

.csb_byte:
    mov     al, [ebp]
    call    put_hex_byte
    mov     al, '.'
    stosb

    mov     ecx, edi
    sub     ecx, line_buffer
    mov     esi, line_buffer
    call    print_buffer
    clc
    ret

.csb_err:
    pop     edx
    stc
    ret

cmd_move:
    push    ebx
    push    esi
    push    edi
    push    ebp

    mov     esi, [cmd_ptr]

    call    parse_address
    jc      .cm_err
    mov     [move_src_seg], ax
    mov     [move_src_off], bx
    mov     bp, ax

    mov     dx, bx
    call    parse_length
    jc      .cm_err
    mov     [move_len], ecx
    push    ecx

    call    parse_address
    jnc     .cm_dst_ok
    pop     ecx
    jmp     .cm_err

.cm_dst_ok:
    mov     [move_dst_seg], ax
    mov     [move_dst_off], bx
    pop     ecx

    call    skip_whitespace
    call    is_eol
    jnc     .cm_err

    test    ecx, ecx
    jz      .cm_done

    mov     ax, [move_src_seg]
    mov     bx, [move_src_off]
    call    calc_linear_addr
    mov     ecx, [move_len]
    call    check_mem_range
    jc      .cm_err

    mov     ax, [move_dst_seg]
    mov     bx, [move_dst_off]
    call    calc_linear_addr
    mov     ecx, [move_len]
    call    check_mem_range
    jc      .cm_err

    mov     ecx, [move_len]

    movzx   eax, word [move_src_seg]
    shl     eax, 4
    movzx   edx, word [move_src_off]
    add     edx, eax

    movzx   eax, word [move_dst_seg]
    shl     eax, 4
    movzx   edi, word [move_dst_off]
    add     edi, eax

    cmp     edi, edx
    je      .cm_done
    pushfd

    movzx   eax, word [move_src_seg]
    shl     eax, 4
    lea     esi, [memory + eax]

    movzx   eax, word [move_dst_seg]
    shl     eax, 4
    lea     edi, [memory + eax]

    mov     bx, [move_src_off]
    mov     dx, [move_dst_off]

    popfd
    jb      .cm_forward

    mov     eax, ecx
    dec     eax
    add     bx, ax
    add     dx, ax

.cm_rev_loop:
    movzx   eax, bx
    mov     al, [esi + eax]
    movzx   ebp, dx
    mov     [edi + ebp], al
    dec     bx
    dec     dx
    dec     ecx
    jnz     .cm_rev_loop
    jmp     .cm_done

.cm_forward:
.cm_fwd_loop:
    movzx   eax, bx
    mov     al, [esi + eax]
    movzx   ebp, dx
    mov     [edi + ebp], al
    inc     bx
    inc     dx
    dec     ecx
    jnz     .cm_fwd_loop

.cm_done:
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    ret

.cm_err:
    pop     ebp
    pop     edi
    add     esp, 4
    pop     ebx
    jmp     print_error_and_ret

cmd_compare:
    push    ebx
    push    esi
    push    edi
    push    ebp

    mov     esi, [cmd_ptr]

    call    parse_address
    jc      .cc_err
    mov     [comp_src_seg], ax
    mov     [comp_src_off], bx
    mov     bp, ax

    mov     dx, bx
    call    parse_length
    jc      .cc_err
    mov     [comp_len], ecx

    call    parse_address
    jc      .cc_err
    mov     [comp_dst_seg], ax
    mov     [comp_dst_off], bx

    call    skip_whitespace
    call    is_eol
    jnc     .cc_err

    mov     ecx, [comp_len]
    test    ecx, ecx
    jz      .cc_done

    mov     ax, [comp_src_seg]
    mov     bx, [comp_src_off]
    call    calc_linear_addr
    mov     ecx, [comp_len]
    call    check_mem_range
    jc      .cc_err

    mov     ax, [comp_dst_seg]
    mov     bx, [comp_dst_off]
    call    calc_linear_addr
    mov     ecx, [comp_len]
    call    check_mem_range
    jc      .cc_err

    mov     ecx, [comp_len]

    movzx   eax, word [comp_src_seg]
    shl     eax, 4
    lea     esi, [memory + eax]

    movzx   eax, word [comp_dst_seg]
    shl     eax, 4
    lea     edi, [memory + eax]

    movzx   ebx, word [comp_src_off]
    movzx   edx, word [comp_dst_off]

.cc_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     .cc_interrupted

    movzx   eax, bx
    movzx   ebp, dx
    mov     al, [esi + eax]
    cmp     al, [edi + ebp]
    je      .cc_next

    mov     [comp_val1], al
    mov     al, [edi + ebp]
    mov     [comp_val2], al

    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    mov     edi, line_buffer

    mov     ax, [comp_src_seg]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, bx
    call    put_hex_word

    mov     al, SPACE
    stosb
    stosb

    mov     al, [comp_val1]
    call    put_hex_byte

    mov     al, SPACE
    stosb
    stosb

    mov     al, [comp_val2]
    call    put_hex_byte

    mov     al, SPACE
    stosb
    stosb

    mov     ax, [comp_dst_seg]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, dx
    call    put_hex_word

    mov     al, CR
    stosb
    mov     al, LF
    stosb

    mov     ecx, edi
    sub     ecx, line_buffer
    mov     esi, line_buffer
    call    print_buffer

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx

.cc_next:
    inc     bx
    inc     dx
    dec     ecx
    jnz     .cc_loop

.cc_done:
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    ret

.cc_interrupted:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    ret

.cc_err:
    pop     ebp
    pop     edi
    add     esp, 4
    pop     ebx
    jmp     print_error_and_ret

cmd_hex:
    push    ebx
    push    esi
    push    edi

    mov     esi, [cmd_ptr]

    call    skip_whitespace
    call    parse_hex
    jc      .ch_err
    mov     bx, ax

    call    skip_whitespace
    call    parse_hex
    jc      .ch_err
    mov     dx, ax

    call    skip_whitespace
    call    is_eol
    jnc     .ch_err

    mov     edi, line_buffer

    mov     ax, bx
    add     ax, dx
    call    put_hex_word

    mov     al, SPACE
    stosb
    stosb

    mov     ax, bx
    sub     ax, dx
    call    put_hex_word

    mov     al, CR
    stosb
    mov     al, LF
    stosb

    mov     ecx, edi
    sub     ecx, line_buffer
    mov     esi, line_buffer
    call    print_buffer

    pop     edi
    pop     esi
    pop     ebx
    ret

.ch_err:
    pop     edi
    add     esp, 4
    pop     ebx
    jmp     print_error_and_ret

cmd_input:
    push    ebx
    push    esi
    push    edi

    mov     esi, [cmd_ptr]

    call    skip_whitespace
    call    parse_hex
    jc      .ci_err
    movzx   ebx, ax

    call    skip_whitespace
    call    is_eol
    jnc     .ci_err

    mov     al, [io_ports + ebx]

    mov     edi, line_buffer
    call    put_hex_byte
    mov     al, CR
    stosb
    mov     al, LF
    stosb

    mov     ecx, edi
    sub     ecx, line_buffer
    mov     esi, line_buffer
    call    print_buffer

    pop     edi
    pop     esi
    pop     ebx
    ret

.ci_err:
    pop     edi
    add     esp, 4
    pop     ebx
    jmp     print_error_and_ret

cmd_output:
    push    ebx
    push    esi

    mov     esi, [cmd_ptr]

    call    skip_whitespace
    call    parse_hex
    jc      .co_err
    movzx   ebx, ax

    call    skip_whitespace
    call    parse_hex_byte
    jc      .co_err
    mov     dl, al

    call    skip_whitespace
    call    is_eol
    jnc     .co_err

    mov     [io_ports + ebx], dl

    pop     esi
    pop     ebx
    ret

.co_err:
    add     esp, 4
    pop     ebx
    jmp     print_error_and_ret

cmd_search:
    mov     esi, [cmd_ptr]

    call    parse_address
    jc      print_error_and_ret
    mov     [search_seg], ax
    mov     [search_off], bx
    mov     bp, ax

    mov     dx, bx
    call    parse_length
    jc      print_error_and_ret
    mov     [search_len], ecx

    mov     edi, search_pat
    mov     edx, FILL_PAT_MAX
    call    parse_pattern_list
    jc      print_error_and_ret
    mov     [search_patlen], cx

.cs_do_search:
    mov     ax, [search_seg]
    mov     bx, [search_off]
    call    calc_linear_addr

    mov     ecx, [search_len]
    call    check_mem_range
    jc      print_error_and_ret

    movzx   edx, word [search_patlen]
    cmp     ecx, edx
    jb      .cs_ret

    sub     ecx, edx
    inc     ecx

    lea     edi, [memory + eax]
    xor     ebx, ebx

.cs_search_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     .cs_interrupted

    push    ecx
    push    esi
    push    edi

    lea     esi, [edi + ebx]
    mov     edi, search_pat
    movzx   ecx, word [search_patlen]
    cld
    repe    cmpsb

    pop     edi
    pop     esi
    pop     ecx
    jne     .cs_no_match

    mov     ax, [search_off]
    add     ax, bx
    movzx   eax, ax

    push    ebx
    push    ecx
    push    edi
    push    eax

    mov     edi, line_buffer
    mov     ax, [search_seg]
    call    put_hex_word
    mov     al, COLON
    stosb
    pop     eax
    call    put_hex_word
    mov     al, CR
    stosb
    mov     al, LF
    stosb

    call    print_line_buffer

    pop     edi
    pop     ecx
    pop     ebx

.cs_no_match:
    inc     ebx
    dec     ecx
    jnz     .cs_search_loop

.cs_ret:
    ret

.cs_interrupted:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer
    ret

