format PE CONSOLE

entry start

include 'fasm/include/win32a.inc'

include 'data.inc'
include 'hex.inc'
include 'dump.inc'
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
    inc     al
    loop    .init_mem

main_loop:
    invoke  WriteConsoleA, [hStdOut], prompt, 1, chars_written, 0
    invoke  ReadConsoleA,  [hStdIn], input_buffer, 255, chars_read, 0

    mov     esi, input_buffer
    call    skip_whitespace

    call    is_eol
    jc      main_loop

    mov     [cmd_ptr], esi
    mov     al, [esi]
    or      al, 20h

    mov     esi, COMTAB
.find_cmd:
    mov     bl, [esi]
    test    bl, bl
    jz      .cmd_not_found
    cmp     bl, al
    je      .run_cmd
    add     esi, 5
    jmp     .find_cmd
.run_cmd:
    mov     eax, [esi+1]
    inc     dword [cmd_ptr]
    call    eax
    jmp     main_loop

.cmd_not_found:
    call    print_error
    jmp     main_loop

cmd_help:
    invoke  WriteConsoleA, [hStdOut], help_text, help_text_len, chars_written, 0
    ret

cmd_quit:
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      exit_program
    ret

cmd_dump:
    mov     word [dump_len], 128
    mov     esi, [cmd_ptr]

    call    skip_whitespace
    call    is_eol
    jc      .do_it

    call    parse_address
    jc      print_error_and_ret
    mov     [dump_seg], ax
    mov     [dump_off], bx
    mov     bp, ax

    mov     word [dump_len], 16

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

    cmp     ecx, 64
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

    cmp     ecx, 64
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
    stosb
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
    stosb
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

    stosb
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

    mov     al, 13
    stosb
    mov     al, 10
    stosb
    mov     ax, [edit_seg]
    call    put_hex_word
    mov     al, ':'
    stosb
    mov     ax, [edit_off]
    call    put_hex_word
    mov     al, ' '
    stosb
    jmp     .csb_byte

.csb_normal:
    mov     al, ' '
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
    mov     al, ':'
    stosb
    mov     ax, [asm_off]
    call    put_hex_word
    mov     al, ' '
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
    mov     word [unasm_len], 32

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
    mov     al, ':'
    stosb
    mov     ax, [unasm_off]
    call    put_hex_word
    mov     al, ' '
    stosb
    stosb

    mov     ax, [unasm_seg]
    mov     bx, [unasm_off]
    call    calc_linear_addr
    mov     ebp, memory
    add     ebp, eax

    mov     al, [ebp]
    call    find_opcode
    jc      .not_found

    movzx   ebx, dl
    inc     ebx
    cmp     ecx, ebx
    jae     .have_bytes

.not_found:
    mov     al, [ebp]
    call    put_hex_byte
    
    push    ecx
    mov     ecx, 8
    mov     al, ' '
    rep stosb
    pop     ecx
    
    mov     al, 'D'
    stosb
    mov     al, 'B'
    stosb
    mov     al, ' '
    stosb
    stosb
    stosb
    stosb
    
    mov     al, [ebp]
    call    put_hex_byte
    
    mov     ebx, 1
    jmp     .line_done

.have_bytes:
    push    esi
    push    edx
    push    ebx
    
    mov     esi, ebp
.hex_loop:
    lodsb
    call    put_hex_byte
    mov     al, ' '
    stosb
    dec     ebx
    jnz     .hex_loop
    pop     ebx
    
    mov     eax, 3
    sub     eax, ebx
    imul    eax, 3
    add     eax, 2
    push    ecx
    mov     ecx, eax
    mov     al, ' '
    rep stosb
    pop     ecx
    
    pop     edx
    pop     esi
    
.str_loop:
    lodsb
    test    al, al
    jz      .str_done
    cmp     al, 'a'
    jb      .store_char
    cmp     al, 'z'
    ja      .store_char
    sub     al, 20h
.store_char:
    stosb
    jmp     .str_loop
.str_done:

    test    dl, dl
    jz      .line_done
    
    cmp     dh, 1
    je      .use_comma
    mov     al, ' '
    jmp     .put_sep
.use_comma:
    mov     al, ','
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
    mov     al, 13
    stosb
    mov     al, 10
    stosb
    
    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0
    
    add     [unasm_off], bx
    sub     [unasm_len], bx
    jmp     .unasm_loop

.done:
    ret

find_opcode:
    push    edi
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
    
    mov     ebx, asm_2word_table
    call    search_table
    jc      .err

.found:
    mov     [asm_bytes], al
    mov     word [asm_len], 1
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
    cmp     cx, 10
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
    
    cmp     al, 90h
    je      .exec_nop
    cmp     al, 0C3h
    je      .exec_ret
    cmp     al, 0CDh
    je      .exec_int
    
    cmp     al, 0B8h
    je      .exec_mov_ax
    cmp     al, 0BBh
    je      .exec_mov_bx
    cmp     al, 0B9h
    je      .exec_mov_cx
    cmp     al, 0BAh
    je      .exec_mov_dx
    
    cmp     al, 0B0h
    je      .exec_mov_al
    cmp     al, 0B1h
    je      .exec_mov_cl
    cmp     al, 0B2h
    je      .exec_mov_dl
    cmp     al, 0B3h
    je      .exec_mov_bl
    cmp     al, 0B4h
    je      .exec_mov_ah
    cmp     al, 0B5h
    je      .exec_mov_ch
    cmp     al, 0B6h
    je      .exec_mov_dh
    cmp     al, 0B7h
    je      .exec_mov_bh
    
    cmp     al, 05h
    je      .exec_add_ax
    cmp     al, 2Dh
    je      .exec_sub_ax

    jmp     .unknown_insn

.exec_nop:
    add     word [reg_IP], 1
    jmp     .run_loop

.exec_ret:
    jmp     .program_end

.exec_int:
    mov     al, [ebp+1]
    cmp     al, 20h
    je      .program_end
    cmp     al, 21h
    je      .program_end
    add     word [reg_IP], 2
    jmp     .run_loop

.exec_mov_ax:
    mov     ax, [ebp+1]
    mov     [reg_AX], ax
    add     word [reg_IP], 3
    jmp     .run_loop
.exec_mov_bx:
    mov     ax, [ebp+1]
    mov     [reg_BX], ax
    add     word [reg_IP], 3
    jmp     .run_loop
.exec_mov_cx:
    mov     ax, [ebp+1]
    mov     [reg_CX], ax
    add     word [reg_IP], 3
    jmp     .run_loop
.exec_mov_dx:
    mov     ax, [ebp+1]
    mov     [reg_DX], ax
    add     word [reg_IP], 3
    jmp     .run_loop

.exec_mov_al:
    mov     al, [ebp+1]
    mov     byte [reg_AX], al
    add     word [reg_IP], 2
    jmp     .run_loop
.exec_mov_cl:
    mov     al, [ebp+1]
    mov     byte [reg_CX], al
    add     word [reg_IP], 2
    jmp     .run_loop
.exec_mov_dl:
    mov     al, [ebp+1]
    mov     byte [reg_DX], al
    add     word [reg_IP], 2
    jmp     .run_loop
.exec_mov_bl:
    mov     al, [ebp+1]
    mov     byte [reg_BX], al
    add     word [reg_IP], 2
    jmp     .run_loop

.exec_mov_ah:
    mov     al, [ebp+1]
    mov     byte [reg_AX+1], al
    add     word [reg_IP], 2
    jmp     .run_loop
.exec_mov_ch:
    mov     al, [ebp+1]
    mov     byte [reg_CX+1], al
    add     word [reg_IP], 2
    jmp     .run_loop
.exec_mov_dh:
    mov     al, [ebp+1]
    mov     byte [reg_DX+1], al
    add     word [reg_IP], 2
    jmp     .run_loop
.exec_mov_bh:
    mov     al, [ebp+1]
    mov     byte [reg_BX+1], al
    add     word [reg_IP], 2
    jmp     .run_loop

.exec_add_ax:
    mov     ax, [ebp+1]
    add     [reg_AX], ax
    add     word [reg_IP], 3
    jmp     .run_loop

.exec_sub_ax:
    mov     ax, [ebp+1]
    sub     [reg_AX], ax
    add     word [reg_IP], 3
    jmp     .run_loop

.hit_breakpoint:
    invoke  WriteConsoleA, [hStdOut], msg_breakpoint, msg_breakpoint_len, chars_written, 0
    jmp     print_registers

.program_end:
    invoke  WriteConsoleA, [hStdOut], msg_prog_end, msg_prog_end_len, chars_written, 0
    jmp     print_registers

.unknown_insn:
    invoke  WriteConsoleA, [hStdOut], msg_unknown_insn, msg_unknown_insn_len, chars_written, 0
    jmp     print_registers

.out_of_bounds:
    call    print_error
    ret

print_registers:
    mov     edi, line_buffer
    
    mov     ax, 'AX'
    stosw
    mov     al, '='
    stosb
    mov     ax, [reg_AX]
    call    put_hex_word
    
    mov     ax, '  '
    stosw
    mov     ax, 'BX'
    stosw
    mov     al, '='
    stosb
    mov     ax, [reg_BX]
    call    put_hex_word

    mov     ax, '  '
    stosw
    mov     ax, 'CX'
    stosw
    mov     al, '='
    stosb
    mov     ax, [reg_CX]
    call    put_hex_word

    mov     ax, '  '
    stosw
    mov     ax, 'DX'
    stosw
    mov     al, '='
    stosb
    mov     ax, [reg_DX]
    call    put_hex_word

    mov     al, 13
    stosb
    mov     al, 10
    stosb

    mov     ax, 'DS'
    stosw
    mov     al, '='
    stosb
    mov     ax, [reg_DS]
    call    put_hex_word

    mov     ax, '  '
    stosw
    mov     ax, 'ES'
    stosw
    mov     al, '='
    stosb
    mov     ax, [reg_ES]
    call    put_hex_word

    mov     ax, '  '
    stosw
    mov     ax, 'SS'
    stosw
    mov     al, '='
    stosb
    mov     ax, [reg_SS]
    call    put_hex_word

    mov     ax, '  '
    stosw
    mov     ax, 'CS'
    stosw
    mov     al, '='
    stosb
    mov     ax, [reg_CS]
    call    put_hex_word

    mov     ax, '  '
    stosw
    mov     ax, 'IP'
    stosw
    mov     al, '='
    stosb
    mov     ax, [reg_IP]
    call    put_hex_word

    mov     al, 13
    stosb
    mov     al, 10
    stosb
    
    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0
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