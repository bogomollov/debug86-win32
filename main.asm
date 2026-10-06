format PE CONSOLE

entry start

include 'fasm/include/win32a.inc'

include 'data.inc'
include 'hex.inc'
include 'dump.inc'
include 'lexer.inc'
include 'utils.inc'

start:
    invoke  GetStdHandle, STD_OUTPUT_HANDLE
    mov     [hStdOut], eax

    invoke  GetStdHandle, STD_INPUT_HANDLE
    mov     [hStdIn], eax

    invoke SetConsoleOutputCP, 866

    mov     ecx, MEM_SIZE
    mov     edi, memory
    xor     eax, eax
.init_mem:
    mov     [edi], al
    inc     edi
    loop    .init_mem

main_loop:
    invoke  WriteConsoleA, [hStdOut], prompt, 1, chars_written, 0
    invoke  ReadConsoleA, [hStdIn], input_buffer, INPUT_BUFFER_MAX, chars_read, 0

    mov     esi, input_buffer
    call    skip_whitespace

    call    is_eol
    jc      main_loop

    mov     [cmd_ptr], esi
    mov     al, [esi]
    or      al, 20h

    mov     esi, COMTAB
.find_cmd:
    mov     bl, [esi + CMD_ENTRY_CHAR_OFF]
    test    bl, bl
    jz      .cmd_not_found
    cmp     bl, al
    je      .run_cmd
    add     esi, COMTAB_RECORD_SIZE
    jmp     .find_cmd
.run_cmd:
    mov     eax, [esi + CMD_ENTRY_HANDLER_OFF]
    inc     dword [cmd_ptr]
    call    eax
    jmp     main_loop

.cmd_not_found:
    call    print_error
    jmp     main_loop

cmd_help:
    invoke  WriteConsoleA, [hStdOut], help_text, help_text_len, chars_written, 0
    ret

cmd_register:
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .show_all

    mov     al, [esi]
    or      al, 20h
    cmp     al, 'f'
    je      cmd_rf

    call    parse_reg_name
    jc      print_error_and_ret
    mov     [edit_reg_ptr], eax

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

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0

    invoke  ReadConsoleA, [hStdIn], input_buffer, 255, chars_read, 0

    mov     esi, input_buffer
    call    skip_whitespace
    call    is_eol
    jc      .reg_done

    call    parse_hex
    jc      .reg_done

    mov     edi, [edit_reg_ptr]
    mov     [edi], ax

.reg_done:
    mov     byte [line_buffer], 13
    mov     byte [line_buffer+1], 10
    invoke  WriteConsoleA, [hStdOut], line_buffer, 2, chars_written, 0
    ret

.show_all:
    call    print_registers

    mov     edi, line_buffer

    mov     ax, [reg_CS]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, [reg_IP]
    call    put_hex_word
    mov     al, SPACE
    stosb

    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    call    calc_linear_addr
    mov     ebp, memory
    add     ebp, eax

    mov     al, [ebp]
    cmp     al, 00h
    je      .cr_add_bxsi

    call    put_hex_byte
    mov     al, SPACE
    stosb
    mov     al, 'D'
    stosb
    mov     al, 'B'
    stosb
    mov     al, SPACE
    stosb
    mov     al, [ebp]
    call    put_hex_byte
    jmp     .cr_done

.cr_add_bxsi:
    mov     al, [ebp]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte
    mov     al, SPACE
    stosb

    mov     esi, str_add_bxsi_al
.cr_str:
    lodsb
    test    al, al
    jz      .cr_mem_chk
    stosb
    jmp     .cr_str

.cr_mem_chk:
    mov     al, [ebp+1]
    test    al, 0C0h
    jnz     .cr_done
    and     al, 07h
    jnz     .cr_done

    movzx   ecx, word [reg_BX]
    movzx   ebx, word [reg_SI]
    add     ecx, ebx
    push    ecx

    movzx   eax, word [reg_DS]
    shl     eax, 4
    add     eax, ecx
    mov     esi, memory
    add     esi, eax
    mov     bl, [esi]

    pop     ecx

    mov     al, SPACE
    stosb
    mov     al, 'D'
    stosb
    mov     al, 'S'
    stosb
    mov     al, COLON
    stosb
    mov     ax, cx
    call    put_hex_word
    mov     al, '='
    stosb
    mov     al, bl
    call    put_hex_byte

.cr_done:
    mov     al, CR
    stosb
    mov     al, LF
    stosb

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0
    ret

cmd_rf:
    call    show_flags

    invoke  ReadConsoleA, [hStdIn], input_buffer, 255, chars_read, 0

    mov     esi, input_buffer
    call    skip_whitespace
    call    is_eol
    jc      .rf_done

.rf_parse_loop:
    mov     al, [esi]
    or      al, 20h
    mov     ah, al
    inc     esi
    mov     al, [esi]
    or      al, 20h
    inc     esi

    mov     edi, flag_map
.rf_find:
    cmp     byte [edi + FLAG_ENTRY_NAME_OFF], 0
    je      .rf_next
    cmp     ah,  [edi + FLAG_ENTRY_NAME_OFF]
    jne     .rf_skip
    cmp     al,  [edi + FLAG_ENTRY_NAME_OFF + 1]
    jne     .rf_skip
    movzx   ebx, byte [edi + FLAG_ENTRY_INDEX_OFF]
    mov     al,       [edi + FLAG_ENTRY_VALUE_OFF]
    mov     [flag_states + ebx], al
    jmp     .rf_next
.rf_skip:
    add     edi, FLAG_MAP_RECORD_SIZE
    jmp     .rf_find

.rf_next:
    call    skip_whitespace
    call    is_eol
    jc      .rf_done
    jmp     .rf_parse_loop

.rf_done:
    mov     byte [line_buffer], 13
    mov     byte [line_buffer+1], 10
    invoke  WriteConsoleA, [hStdOut], line_buffer, 2, chars_written, 0
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

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0

    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

cmd_quit:
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      exit_program
    ret

cmd_dump:
    mov     word [dump_len], DUMP_DEFAULT_LEN
    mov     esi, [cmd_ptr]

    call    skip_whitespace
    call    is_eol
    jc      .do_it

    call    parse_address
    jc      print_error_and_ret
    mov     [dump_seg], ax
    mov     [dump_off], bx
    mov     bp, ax

    mov     word [dump_len], DUMP_LINE_BYTES

    mov     dx, bx
    call    skip_whitespace
    call    is_eol
    jc      .do_it

    call    parse_length
    jc      print_error_and_ret
    mov     [dump_len], cx

.do_it:
    mov     ax, [dump_seg]
    mov     bx, [dump_off]
    call    calc_linear_addr
    movzx   ecx, word [dump_len]
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
    mov     [fill_len], cx

    mov     edi, fill_pat
    xor     ecx, ecx

.cf_next_token:
    call    skip_whitespace
    call    is_eol
    jc      .cf_pat_done

    cmp     ecx, FILL_PAT_MAX
    jae     .cf_pat_done

    cmp     al, 22h
    je      .cf_string
    cmp     al, 27h
    je      .cf_string

    call    parse_hex_byte
    jc      print_error_and_ret
    stosb
    inc     ecx
    jmp     .cf_next_token

.cf_string:
    mov     dl, al
    inc     esi
.cf_str_loop:
    mov     al, [esi]
    call    is_eol
    jc      .cf_pat_done
    cmp     al, dl
    je      .cf_str_end

    cmp     ecx, FILL_PAT_MAX
    jae     .cf_pat_done

    stosb
    inc     ecx
    inc     esi
    jmp     .cf_str_loop
.cf_str_end:
    inc     esi
    jmp     .cf_next_token

.cf_pat_done:
    test    ecx, ecx
    jz      print_error_and_ret
    mov     [fill_patlen], cx

.cf_do_fill:
    mov     ax, [fill_seg]
    mov     bx, [fill_off]
    call    calc_linear_addr

    movzx   ecx, word [fill_len]
    call    check_mem_range
    jc      print_error_and_ret

    mov     edi, memory
    add     edi, eax

    movzx   ecx, word [fill_len]
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
    jc      .ce_ret
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

    mov     dl, 1
    call    ce_show_byte
    jc      .ce_int_done

.ce_int_read:
    invoke  ReadConsoleA, [hStdIn], edit_char, 1, edit_chars_read, 0
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
    invoke  WriteConsoleA, [hStdOut], line_buffer, 1, chars_written, 0
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
    invoke  WriteConsoleA, [hStdOut], line_buffer, 3, chars_written, 0
    ret

.ce_int_space:
    mov     byte [edit_have_nibble], 0
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
    mov     byte [edit_have_nibble], 0
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
    invoke  SetConsoleMode, [hStdIn], [old_console_mode]
    mov     byte [line_buffer], 13
    mov     byte [line_buffer+1], 10
    invoke  WriteConsoleA, [hStdOut], line_buffer, 2, chars_written, 0
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

    mov     al, CR
    stosb
    mov     al, LF
    stosb
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

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0
    clc
    ret

.csb_err:
    pop     edx
    stc
    ret

cmd_move:
    mov     esi, [cmd_ptr]

    call    parse_address
    jc      print_error_and_ret
    mov     [move_src_seg], ax
    mov     [move_src_off], bx
    mov     bp, ax

    mov     dx, bx
    call    parse_length
    jc      print_error_and_ret
    mov     [move_len], cx

    call    parse_address
    jc      print_error_and_ret
    mov     [move_dst_seg], ax
    mov     [move_dst_off], bx

    mov     ax, [move_src_seg]
    mov     bx, [move_src_off]
    call    calc_linear_addr
    movzx   ecx, word [move_len]
    call    check_mem_range
    jc      print_error_and_ret
    mov     edx, memory
    add     edx, eax

    mov     ax, [move_dst_seg]
    mov     bx, [move_dst_off]
    call    calc_linear_addr
    movzx   ecx, word [move_len]
    call    check_mem_range
    jc      print_error_and_ret
    mov     edi, memory
    add     edi, eax
    
    mov     esi, edx
    test    ecx, ecx
    jz      .cm_ret

    cmp     esi, edi
    je      .cm_ret
    ja      .cm_forward

    mov     eax, esi
    add     eax, ecx
    cmp     eax, edi
    jbe     .cm_forward

    add     esi, ecx
    dec     esi
    add     edi, ecx
    dec     edi
    std
    rep movsb
    cld
    ret

.cm_forward:
    cld
    rep movsb
.cm_ret:
    ret

cmd_assemble:
    mov     esi, [cmd_ptr]

    call    skip_whitespace
    call    is_eol
    jc      .use_default
    
    call    parse_address
    jc      print_error_and_ret
    mov     [asm_seg], ax
    mov     [asm_off], bx
    jmp     .loop

.use_default:
    mov     ax, [reg_CS]
    mov     [asm_seg], ax
    mov     ax, [asm_off]
    test    ax, ax
    jnz     .loop
    mov     word [asm_off], 0100h

.loop:
    mov     edi, line_buffer
    mov     ax, [asm_seg]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, [asm_off]
    call    put_hex_word
    mov     al, SPACE
    stosb
    stosb
    
    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0

    invoke  ReadConsoleA, [hStdIn], input_buffer, 255, chars_read, 0
    
    mov     esi, input_buffer
    call    skip_whitespace
    call    is_eol
    jc      .done

    call    parse_instruction
    jc      .error
    
    mov     ax, [asm_seg]
    mov     bx, [asm_off]
    call    calc_linear_addr
    movzx   ecx, word [asm_len]
    call    check_mem_range
    jc      .error
    
    mov     edi, memory
    add     edi, eax
    mov     esi, asm_bytes
    rep     movsb
    
    mov     ax, [asm_len]
    add     [asm_off], ax
    jmp     .loop

.error:
    call    print_error
    jmp     .loop

.done:
    ret

cmd_unassemble:
    mov     esi, [cmd_ptr]
    mov     word [unasm_len], UNASM_DEFAULT_LEN

    call    skip_whitespace
    call    is_eol
    jc      .do_it

    call    parse_address
    jc      print_error_and_ret
    mov     [unasm_seg], ax
    mov     [unasm_off], bx
    mov     bp, ax

    mov     dx, bx
    call    skip_whitespace
    call    is_eol
    jc      .do_it

    call    parse_length
    jc      print_error_and_ret
    mov     [unasm_len], cx

.do_it:
    mov     ax, [unasm_seg]
    mov     bx, [unasm_off]
    call    calc_linear_addr
    movzx   ecx, word [unasm_len]
    call    check_mem_range
    jc      print_error_and_ret

.unasm_loop:
    movzx   ecx, word [unasm_len]
    test    ecx, ecx
    jz      .done

    mov     edi, line_buffer
    mov     ax, [unasm_seg]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, [unasm_off]
    call    put_hex_word
    mov     al, SPACE
    stosb
    stosb

    mov     ax, [unasm_seg]
    mov     bx, [unasm_off]
    call    calc_linear_addr
    mov     ebp, memory
    add     ebp, eax

    mov     al, [ebp]
    cmp     al, OP_JNZ_REL8
    je      .rel_jump
    call    find_opcode
    jc      .not_found

    movzx   ebx, dl
    inc     ebx

    mov     eax, ebp
    sub     eax, memory
    add     eax, ebx
    cmp     eax, MEM_SIZE
    jbe     .have_bytes

.not_found:
    mov     al, [ebp]
    call    put_hex_byte

    mov     ecx, 12
    mov     al, SPACE
    rep     stosb

    mov     al, 'D'
    stosb
    mov     al, 'B'
    stosb

    mov     ecx, 6
    mov     al, SPACE
    rep     stosb

    mov     al, [ebp]
    call    put_hex_byte

    mov     ebx, 1
    jmp     .line_done

.have_bytes:
    push    esi
    push    edx
    push    ebx
    push    ecx

    mov     esi, ebp
    mov     ecx, ebx
.hex_loop:
    lodsb
    call    put_hex_byte
    dec     ecx
    jnz     .hex_loop

    mov     eax, 14
    sub     eax, ebx
    sub     eax, ebx
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb

    pop     ecx
    pop     ebx
    pop     edx
    pop     esi

.str_loop:
    xor     ecx, ecx
.str_mnem:
    lodsb
    test    al, al
    jz      .str_pad_only
    cmp     al, SPACE
    je      .str_have_ops
    cmp     al, 'a'
    jb      .str_store_m
    cmp     al, 'z'
    ja      .str_store_m
    sub     al, 20h
.str_store_m:
    stosb
    inc     ecx
    jmp     .str_mnem

.str_have_ops:
    mov     eax, 8
    sub     eax, ecx
    jle     .str_ops
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb
.str_ops:
    lodsb
    test    al, al
    jz      .str_done
    cmp     al, 'a'
    jb      .str_store_op
    cmp     al, 'z'
    ja      .str_store_op
    sub     al, 20h
.str_store_op:
    stosb
    jmp     .str_ops

.str_pad_only:
    mov     eax, 8
    sub     eax, ecx
    jle     .str_done
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb
.str_done:
    test    dl, dl
    jz      .line_done

    cmp     dh, 2
    je      .line_done

    cmp     dh, 1
    je      .use_comma
    mov     al, SPACE
    jmp     .put_sep
.use_comma:
    mov     al, COMMA
.put_sep:
    stosb

    cmp     dl, 1
    je      .arg_byte

    mov     al, [ebp+2]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte
    jmp     .line_done

.arg_byte:
    mov     al, [ebp+1]
    call    put_hex_byte

.line_done:
    mov     al, CR
    stosb
    mov     al, LF
    stosb

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0

    add     [unasm_off], bx

    mov     ax, [unasm_len]
    sub     ax, bx
    jbe     .done
    mov     [unasm_len], ax
    jmp     .unasm_loop

.done:
    ret

.rel_jump:
    mov     eax, ebp
    sub     eax, memory
    add     eax, 2
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     al, [ebp]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte

    mov     ecx, 10
    mov     al, SPACE
    rep     stosb

    mov     al, 'J'
    stosb
    mov     al, 'N'
    stosb
    mov     al, 'Z'
    stosb

    mov     ecx, 5
    mov     al, SPACE
    rep     stosb

    movsx   eax, byte [ebp+1]
    add     ax, [unasm_off]
    add     ax, 2
    call    put_hex_word

    mov     bx, 2
    jmp     .line_done

find_opcode:
    push    edi
    
    mov     edi, asm_2byte_table
.loop3:
    cmp     byte [edi], 0
    je      .end3
    mov     ebx, edi
.skip3:
    cmp     byte [ebx], 0
    je      .found_null3
    inc     ebx
    jmp     .skip3
.found_null3:
    inc     ebx
    cmp     al, [ebx]
    jne     .next3
    mov     ah, [ebp+1]
    cmp     ah, [ebx+1]
    jne     .next3
    mov     esi, edi
    mov     dl, 1
    mov     dh, 2
    pop     edi
    clc
    ret
.next3:
    add     ebx, 2
    mov     edi, ebx
    jmp     .loop3
.end3:

    mov     edi, asm_1word_table
.loop1:
    cmp     byte [edi], 0
    je      .end1
    mov     ebx, edi
.skip1:
    cmp     byte [ebx], 0
    je      .found_null1
    inc     ebx
    jmp     .skip1
.found_null1:
    inc     ebx
    cmp     al, [ebx]
    jne     .next1
    mov     esi, edi
    mov     dl, [ebx+1]
    mov     dh, 0
    pop     edi
    clc
    ret
.next1:
    add     ebx, 2
    mov     edi, ebx
    jmp     .loop1
.end1:

    mov     edi, asm_2word_table
.loop2:
    cmp     byte [edi], 0
    je      .end2
    mov     ebx, edi
.skip2:
    cmp     byte [ebx], 0
    je      .found_null2
    inc     ebx
    jmp     .skip2
.found_null2:
    inc     ebx
    cmp     al, [ebx]
    jne     .next2
    mov     esi, edi
    mov     dl, [ebx+1]
    mov     dh, 1
    pop     edi
    clc
    ret
.next2:
    add     ebx, 2
    mov     edi, ebx
    jmp     .loop2
.end2:
    pop     edi
    stc
    ret

parse_instruction:
    mov     edi, asm_token
    call    get_token
    
    cmp     byte [asm_token], 0
    je      .err
    
    mov     ebx, asm_1word_table
    call    search_table
    jnc     .found
    
    mov     edi, asm_token
.find_end:
    cmp     byte [edi], 0
    je      .append_space
    inc     edi
    jmp     .find_end
.append_space:
    mov     byte [edi], ' '
    inc     edi
    
    call    get_token
    cmp     byte [asm_token], 0
    je      .err
    
    push    esi
    
    mov     edi, asm_token
.find_end2:
    cmp     byte [edi], 0
    je      .append_space2
    inc     edi
    jmp     .find_end2
.append_space2:
    mov     byte [edi], ' '
    push    edi
    inc     edi
    
    call    get_token
    
    mov     ebx, asm_3word_table
    call    search_table
    jnc     .found_3word
    
    pop     edi
    mov     byte [edi], 0
    pop     esi
    
    mov     ebx, asm_2word_table
    call    search_table
    jnc     .found
    jmp     .err

.found_3word:
    pop     edi
    pop     esi
    mov     [asm_bytes], al
    mov     [asm_bytes+1], ah
    mov     word [asm_len], 2
    clc
    ret

.found:
    mov     [asm_bytes], al
    mov     word [asm_len], INSN_LEN_1
    mov     [asm_arg_size], ah
    
    test    ah, ah
    jz      .ok
    
    call    skip_whitespace
    call    parse_hex
    jc      .err
    
    mov     dl, [asm_arg_size]
    cmp     dl, 1
    je      .arg_byte
    
    mov     [asm_bytes+1], al
    mov     [asm_bytes+2], ah
    mov     word [asm_len], 3
    clc
    ret
    
.arg_byte:
    mov     [asm_bytes+1], al
    mov     word [asm_len], 2
.ok:
    clc
    ret
    
.err:
    stc
    ret

get_token:
    call    skip_whitespace
.loop:
    call    is_eol
    jc      .done
    mov     al, [esi]
    cmp     al, ' '
    je      .done
    cmp     al, 9
    je      .done
    cmp     al, ','
    je      .done
    
    cmp     al, 'A'
    jb      .store
    cmp     al, 'Z'
    ja      .store
    add     al, 20h
.store:
    stosb
    inc     esi
    jmp     .loop
.done:
    mov     byte [edi], 0
    ret

search_table:
.loop:
    mov     al, [ebx]
    test    al, al
    jz      .not_found
    
    mov     edi, asm_token
    mov     edx, ebx
.cmp:
    mov     cl, [edi]
    mov     ch, [edx]
    cmp     cl, ch
    jne     .next
    test    cl, cl
    jz      .match
    inc     edi
    inc     edx
    jmp     .cmp
    
.next:
    mov     al, [ebx]
    test    al, al
    jz      .skip_done
    inc     ebx
    jmp     .next
.skip_done:
    add     ebx, 3
    jmp     .loop
    
.match:
    inc     edx
    mov     al, [edx]
    mov     ah, [edx+1]
    clc
    ret
    
.not_found:
    stc
    ret

cmd_go:
    mov     word [num_breakpoints], 0
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .start_run

    mov     al, [esi]
    cmp     al, '='
    jne     .parse_bp_loop

    inc     esi
    call    parse_address
    jc      print_error_and_ret
    mov     [reg_CS], ax
    mov     [reg_IP], bx

.parse_bp_loop:
    call    skip_whitespace
    call    is_eol
    jc      .start_run
    
    mov     cx, [num_breakpoints]
    cmp     cx, MAX_BREAKPOINTS
    jae     print_error_and_ret

    push    cx
    call    parse_address
    pop     cx
    jc      print_error_and_ret
    
    movzx   ecx, cx
    mov     [breakpoints_seg + ecx*2], ax
    mov     [breakpoints_off + ecx*2], bx
    inc     cx
    mov     [num_breakpoints], cx
    jmp     .parse_bp_loop

.start_run:
.run_loop:
    mov     cx, [num_breakpoints]
    test    cx, cx
    jz      .no_bp
    
    movzx   ecx, cx
    xor     edx, edx
.bp_check:
    cmp     edx, ecx
    jae     .no_bp
    mov     ax, [breakpoints_seg + edx*2]
    cmp     ax, [reg_CS]
    jne     .next_bp
    mov     bx, [breakpoints_off + edx*2]
    cmp     bx, [reg_IP]
    jne     .next_bp
    
    jmp     .hit_breakpoint
    
.next_bp:
    inc     edx
    jmp     .bp_check

.no_bp:
    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    call    calc_linear_addr
    
    mov     ecx, 3
    call    check_mem_range
    jc      .out_of_bounds
    
    mov     ebp, memory
    add     ebp, eax
    
    mov     al, [ebp]
    
    cmp     al, OP_NOP
    je      .exec_nop
    cmp     al, 0C3h
    je      .exec_ret
    cmp     al, OP_INT
    je      .exec_int
    
    cmp     al, OP_MOV_AX
    je      .exec_mov_ax
    cmp     al, OP_MOV_BX
    je      .exec_mov_bx
    cmp     al, OP_MOV_CX
    je      .exec_mov_cx
    cmp     al, OP_MOV_DX
    je      .exec_mov_dx
    
    cmp     al, OP_MOV_AL
    je      .exec_mov_al
    cmp     al, OP_MOV_CL
    je      .exec_mov_cl
    cmp     al, OP_MOV_DL
    je      .exec_mov_dl
    cmp     al, OP_MOV_BL
    je      .exec_mov_bl
    cmp     al, OP_MOV_AH
    je      .exec_mov_ah
    cmp     al, OP_MOV_CH
    je      .exec_mov_ch
    cmp     al, OP_MOV_DH
    je      .exec_mov_dh
    cmp     al, OP_MOV_BH
    je      .exec_mov_bh
    
    cmp     al, OP_MOV_BX_AX
    je      .exec_mov_bx_ax

    cmp     al, OP_ADD_AX
    je      .exec_add_ax
    cmp     al, OP_SUB_AX
    je      .exec_sub_ax

    jmp     .unknown_insn

.exec_nop:
    add     word [reg_IP], INSN_LEN_1
    jmp     .run_loop

.exec_ret:
    jmp     .program_end

.exec_int:
    mov     al, [ebp+1]
    cmp     al, INT_VECTOR_20
    je      .program_end
    cmp     al, INT_VECTOR_21
    je      .int21
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop

.int21:
    mov     ah, byte [reg_AX+1]
    cmp     ah, 09h
    je      .int21_ah09
    cmp     ah, 4Ch
    je      .program_end
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop

.int21_ah09:
    mov     ax, [reg_DS]
    mov     bx, [reg_DX]
    call    calc_linear_addr
    
    mov     ecx, MEM_SIZE
    sub     ecx, eax
    jbe     .int21_09_skip
    
    mov     esi, memory
    add     esi, eax
    mov     edi, esi
    push    ecx
    mov     al, '$'
    repne   scasb
    pop     ecx
    jne     .int21_09_skip
    
    mov     edx, edi
    sub     edx, esi
    dec     edx
    jz      .int21_09_skip
    
    invoke  WriteConsoleA, [hStdOut], esi, edx, chars_written, 0

.int21_09_skip:
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop

.exec_mov_ax:
    mov     ax, [ebp+1]
    mov     [reg_AX], ax
    add     word [reg_IP], INSN_LEN_3
    jmp     .run_loop
.exec_mov_bx:
    mov     ax, [ebp+1]
    mov     [reg_BX], ax
    add     word [reg_IP], INSN_LEN_3
    jmp     .run_loop
.exec_mov_cx:
    mov     ax, [ebp+1]
    mov     [reg_CX], ax
    add     word [reg_IP], INSN_LEN_3
    jmp     .run_loop
.exec_mov_dx:
    mov     ax, [ebp+1]
    mov     [reg_DX], ax
    add     word [reg_IP], INSN_LEN_3
    jmp     .run_loop

.exec_mov_al:
    mov     al, [ebp+1]
    mov     byte [reg_AX], al
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop
.exec_mov_cl:
    mov     al, [ebp+1]
    mov     byte [reg_CX], al
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop
.exec_mov_dl:
    mov     al, [ebp+1]
    mov     byte [reg_DX], al
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop
.exec_mov_bl:
    mov     al, [ebp+1]
    mov     byte [reg_BX], al
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop

.exec_mov_ah:
    mov     al, [ebp+1]
    mov     byte [reg_AX+1], al
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop
.exec_mov_ch:
    mov     al, [ebp+1]
    mov     byte [reg_CX+1], al
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop
.exec_mov_dh:
    mov     al, [ebp+1]
    mov     byte [reg_DX+1], al
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop
.exec_mov_bh:
    mov     al, [ebp+1]
    mov     byte [reg_BX+1], al
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop
    
.exec_mov_bx_ax:
    mov     al, [ebp+1]
    cmp     al, OP_MOV_BX_AX_MODRM
    jne     .unknown_insn
    mov     ax, [reg_AX]
    mov     [reg_BX], ax
    add     word [reg_IP], INSN_LEN_2
    jmp     .run_loop

.exec_add_ax:
    mov     ax, [ebp+1]
    add     [reg_AX], ax
    add     word [reg_IP], INSN_LEN_3
    jmp     .run_loop

.exec_sub_ax:
    mov     ax, [ebp+1]
    sub     [reg_AX], ax
    add     word [reg_IP], INSN_LEN_3
    jmp     .run_loop

.hit_breakpoint:
    invoke  WriteConsoleA, [hStdOut], msg_breakpoint, msg_breakpoint_len, chars_written, 0
    jmp     print_registers

.program_end:
    invoke  WriteConsoleA, [hStdOut], msg_prog_end, msg_prog_end_len, chars_written, 0
    ret

.unknown_insn:
    invoke  WriteConsoleA, [hStdOut], msg_unknown_insn, msg_unknown_insn_len, chars_written, 0
    jmp     print_registers

.out_of_bounds:
    call    print_error
    ret

cmd_trace:
    mov     word [trace_count], 1
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .trace_loop

    mov     al, [esi]
    cmp     al, '='
    jne     .parse_count

    inc     esi
    call    parse_address
    jc      print_error_and_ret
    mov     [reg_CS], ax
    mov     [reg_IP], bx

    call    skip_whitespace
    call    is_eol
    jc      .trace_loop

.parse_count:
    call    parse_hex
    jc      print_error_and_ret
    test    ax, ax
    jz      print_error_and_ret
    mov     [trace_count], ax

    call    skip_whitespace
    call    is_eol
    jnc     print_error_and_ret

.trace_loop:
    call    step
    cmp     eax, STEP_OK
    je      .step_ok
    cmp     eax, STEP_PROGRAM_END
    je      .step_prog_end
    cmp     eax, STEP_UNKNOWN
    je      .step_unknown

.step_out_of_bounds:
    call    print_error
    ret

.step_prog_end:
    invoke  WriteConsoleA, [hStdOut], msg_prog_end, msg_prog_end_len, chars_written, 0
    ret

.step_unknown:
    invoke  WriteConsoleA, [hStdOut], msg_unknown_insn, msg_unknown_insn_len, chars_written, 0
    jmp     print_registers

.step_ok:
    call    cmd_register.show_all
    dec     word [trace_count]
    jnz     .trace_loop
    ret

step:
    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    call    calc_linear_addr

    mov     ecx, 3
    call    check_mem_range
    jc      .out_of_bounds

    mov     ebp, memory
    add     ebp, eax

    mov     al, [ebp]

    cmp     al, OP_NOP
    je      .exec_nop
    cmp     al, 0C3h
    je      .exec_ret
    cmp     al, OP_INT
    je      .exec_int

    cmp     al, OP_MOV_AX
    je      .exec_mov_ax
    cmp     al, OP_MOV_BX
    je      .exec_mov_bx
    cmp     al, OP_MOV_CX
    je      .exec_mov_cx
    cmp     al, OP_MOV_DX
    je      .exec_mov_dx

    cmp     al, OP_MOV_AL
    je      .exec_mov_al
    cmp     al, OP_MOV_CL
    je      .exec_mov_cl
    cmp     al, OP_MOV_DL
    je      .exec_mov_dl
    cmp     al, OP_MOV_BL
    je      .exec_mov_bl
    cmp     al, OP_MOV_AH
    je      .exec_mov_ah
    cmp     al, OP_MOV_CH
    je      .exec_mov_ch
    cmp     al, OP_MOV_DH
    je      .exec_mov_dh
    cmp     al, OP_MOV_BH
    je      .exec_mov_bh

    cmp     al, OP_MOV_BX_AX
    je      .exec_mov_bx_ax

    cmp     al, OP_ADD_AX
    je      .exec_add_ax
    cmp     al, OP_SUB_AX
    je      .exec_sub_ax

    mov     eax, STEP_UNKNOWN
    ret

.exec_nop:
    add     word [reg_IP], INSN_LEN_1
    mov     eax, STEP_OK
    ret

.exec_ret:
    mov     eax, STEP_PROGRAM_END
    ret

.exec_int:
    mov     al, [ebp+1]
    cmp     al, INT_VECTOR_20
    je      .exec_ret
    cmp     al, INT_VECTOR_21
    je      .int21
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret

.int21:
    mov     ah, byte [reg_AX+1]
    cmp     ah, 09h
    je      .int21_ah09
    cmp     ah, 4Ch
    je      .exec_ret
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret

.int21_ah09:
    mov     ax, [reg_DS]
    mov     bx, [reg_DX]
    call    calc_linear_addr

    mov     ecx, MEM_SIZE
    sub     ecx, eax
    jbe     .int21_09_skip

    mov     esi, memory
    add     esi, eax
    mov     edi, esi
    push    ecx
    mov     al, '$'
    repne   scasb
    pop     ecx
    jne     .int21_09_skip

    mov     edx, edi
    sub     edx, esi
    dec     edx
    jz      .int21_09_skip

    invoke  WriteConsoleA, [hStdOut], esi, edx, chars_written, 0

.int21_09_skip:
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret

.exec_mov_ax:
    mov     ax, [ebp+1]
    mov     [reg_AX], ax
    add     word [reg_IP], INSN_LEN_3
    mov     eax, STEP_OK
    ret
.exec_mov_bx:
    mov     ax, [ebp+1]
    mov     [reg_BX], ax
    add     word [reg_IP], INSN_LEN_3
    mov     eax, STEP_OK
    ret
.exec_mov_cx:
    mov     ax, [ebp+1]
    mov     [reg_CX], ax
    add     word [reg_IP], INSN_LEN_3
    mov     eax, STEP_OK
    ret
.exec_mov_dx:
    mov     ax, [ebp+1]
    mov     [reg_DX], ax
    add     word [reg_IP], INSN_LEN_3
    mov     eax, STEP_OK
    ret

.exec_mov_al:
    mov     al, [ebp+1]
    mov     byte [reg_AX], al
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret
.exec_mov_cl:
    mov     al, [ebp+1]
    mov     byte [reg_CX], al
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret
.exec_mov_dl:
    mov     al, [ebp+1]
    mov     byte [reg_DX], al
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret
.exec_mov_bl:
    mov     al, [ebp+1]
    mov     byte [reg_BX], al
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret

.exec_mov_ah:
    mov     al, [ebp+1]
    mov     byte [reg_AX+1], al
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret
.exec_mov_ch:
    mov     al, [ebp+1]
    mov     byte [reg_CX+1], al
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret
.exec_mov_dh:
    mov     al, [ebp+1]
    mov     byte [reg_DX+1], al
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret
.exec_mov_bh:
    mov     al, [ebp+1]
    mov     byte [reg_BX+1], al
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret

.exec_mov_bx_ax:
    mov     al, [ebp+1]
    cmp     al, OP_MOV_BX_AX_MODRM
    jne     .unknown_insn
    mov     ax, [reg_AX]
    mov     [reg_BX], ax
    add     word [reg_IP], INSN_LEN_2
    mov     eax, STEP_OK
    ret

.exec_add_ax:
    mov     ax, [ebp+1]
    add     [reg_AX], ax
    add     word [reg_IP], INSN_LEN_3
    mov     eax, STEP_OK
    ret

.exec_sub_ax:
    mov     ax, [ebp+1]
    sub     [reg_AX], ax
    add     word [reg_IP], INSN_LEN_3
    mov     eax, STEP_OK
    ret

.unknown_insn:
    mov     eax, STEP_UNKNOWN
    ret

.out_of_bounds:
    mov     eax, STEP_ERROR
    ret

parse_reg_name:
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
    clc
    ret
.rt_next:
    add     ebx, REG_NAME_RECORD_SIZE
    jmp     .rt_loop

.rd_err:
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

    add     ebx, 2
    inc     edx
    cmp     edx, 8
    jne     .pr_next
    dec     edi
    mov     al, CR
    stosb
    mov     al, LF
    stosb
.pr_next:
    loop    .pr_loop

    call    append_flags

    mov     al, CR
    stosb
    mov     al, LF
    stosb

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0

    pop     ecx
    pop     ebx
    pop     edi
    pop     esi
    ret

section '.idata' import data readable writeable
    library kernel32, 'KERNEL32.DLL'

    import kernel32,\
           ExitProcess,        'ExitProcess',\
           GetStdHandle,       'GetStdHandle',\
           WriteConsoleA,      'WriteConsoleA',\
           ReadConsoleA,       'ReadConsoleA',\
           SetConsoleOutputCP, 'SetConsoleOutputCP',\
           GetConsoleMode,     'GetConsoleMode',\
           SetConsoleMode,     'SetConsoleMode'