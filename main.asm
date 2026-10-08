format PE CONSOLE

entry start

include 'fasm/include/win32a.inc'

include 'data.inc'
include 'hex.inc'
include 'dump.inc'
include 'lexer.inc'
include 'utils.inc'

ctrl_handler:
    mov     eax, [esp+4]
    cmp     eax, 0
    je      .handled
    cmp     eax, 1
    je      .handled
    xor     eax, eax
    ret     4

.handled:
    mov     byte [ctrl_c_flag], 1
    mov     eax, 1
    ret     4

start:
    invoke  GetStdHandle, STD_OUTPUT_HANDLE
    mov     [hStdOut], eax

    invoke  GetStdHandle, STD_INPUT_HANDLE
    mov     [hStdIn], eax

    invoke  SetConsoleOutputCP, 866

    invoke  SetConsoleCtrlHandler, ctrl_handler, 1

    mov     ecx, MEM_SIZE
    mov     edi, memory
    xor     eax, eax
.init_mem:
    mov     [edi], al
    inc     edi
    loop    .init_mem

    call    init_psp
    call    parse_startup_cmdline

main_loop:
    mov     byte [ctrl_c_flag], 0
    mov     dword [prompt_len], 1
    invoke  WriteConsoleA, [hStdOut], prompt, 1, chars_written, 0
    test    eax, eax
    jnz     .prompt_ok
    invoke  WriteFile, [hStdOut], prompt, 1, chars_written, 0
.prompt_ok:

    mov     byte [input_buffer], 0
    invoke  ReadConsoleA, [hStdIn], input_buffer, INPUT_BUFFER_MAX, chars_read, 0
    test    eax, eax
    jnz     .check_read_count

    ; Fallback for redirected input (pipes, automated scripts)
    xor     ecx, ecx
.pipe_read_loop:
    cmp     ecx, INPUT_BUFFER_MAX - 1
    jae     .pipe_line_done
    push    ecx
    lea     eax, [input_buffer + ecx]
    invoke  ReadFile, [hStdIn], eax, 1, chars_read, 0
    pop     ecx
    test    eax, eax
    jz      .pipe_eof_check
    cmp     dword [chars_read], 0
    jz      .pipe_eof_check
    mov     al, [input_buffer + ecx]
    inc     ecx
    cmp     al, LF
    je      .pipe_line_done
    jmp     .pipe_read_loop
.pipe_eof_check:
    test    ecx, ecx
    jz      exit_program
.pipe_line_done:
    mov     [chars_read], ecx
    mov     byte [input_buffer + ecx], 0

.check_read_count:
    cmp     dword [chars_read], 0
    jz      .read_failed

    mov     byte [ctrl_c_flag], 0
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
    mov     esi, [cmd_ptr]
    call    print_error
    jmp     main_loop

.read_failed:
    cmp     byte [ctrl_c_flag], 0
    jnz     .prompt_crlf
    jmp     main_loop

.prompt_crlf:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    invoke  WriteConsoleA, [hStdOut], line_buffer, 2, chars_written, 0
    jmp     main_loop

cmd_help:
    mov     esi, help_text
    mov     ecx, help_text_len
    call    print_buffer
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
    jc      .bad_reg
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
    test    eax, eax
    jnz     .reg_prompt_ok
    invoke  WriteFile, [hStdOut], line_buffer, edx, chars_written, 0
.reg_prompt_ok:

    mov     edi, input_buffer
    mov     edx, 255
    call    read_line_console_or_pipe

    mov     esi, input_buffer
    call    skip_whitespace
    call    is_eol
    jc      .reg_done

    call    parse_hex
    jc      .reg_done

    mov     edi, [edit_reg_ptr]
    mov     [edi], ax

.reg_done:
    ret

.bad_reg:
    call    print_br_error
    ret

.show_all:
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

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0
    test    eax, eax
    jnz     .sf_ok
    invoke  WriteFile, [hStdOut], line_buffer, edx, chars_written, 0
.sf_ok:

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

init_psp:
    push    eax
    push    ebx
    push    ecx
    push    edi

    mov     ax, [reg_CS]
    xor     bx, bx
    call    calc_linear_addr
    cmp     eax, MEM_SIZE - 256
    jae     .psp_done

    mov     edi, memory
    add     edi, eax

    ; Offset 00h: INT 20h opcode (CD 20)
    mov     byte [edi + 00h], 0CDh
    mov     byte [edi + 01h], 20h

    ; Offset 02h: Top of memory segment (A000h)
    mov     word [edi + 02h], 0A000h

    ; Offset 05h: Far call to DOS dispatcher (CD 21 CB)
    mov     byte [edi + 05h], 0CDh
    mov     byte [edi + 06h], 21h
    mov     byte [edi + 07h], 0CBh

    ; Clear FCBs at 5Ch and 6Ch
    lea     ebx, [edi + 5Ch]
    mov     ecx, 32
.clear_fcb:
    mov     byte [ebx], 0
    inc     ebx
    loop    .clear_fcb

    ; Set default empty command tail at 80h
    mov     byte [edi + 80h], 0
    mov     byte [edi + 81h], 0Dh

    ; Set stack return word at [SS:SP] to 0000h for near RET termination
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    cmp     eax, MEM_SIZE - 2
    jae     .psp_done
    mov     word [memory + eax], 0000h

.psp_done:
    pop     ecx
    pop     edi
    pop     ebx
    pop     eax
    ret

set_psp_command_tail:
    push    eax
    push    ebx
    push    ecx
    push    esi
    push    edi

    mov     ax, [reg_CS]
    xor     bx, bx
    call    calc_linear_addr
    cmp     eax, MEM_SIZE - 256
    jae     .spt_done

    mov     edi, memory
    add     edi, eax
    add     edi, 81h

    xor     ecx, ecx
.tail_loop:
    mov     al, [esi]
    test    al, al
    jz      .tail_end
    cmp     al, CR
    je      .tail_end
    cmp     al, LF
    je      .tail_end
    cmp     ecx, 126
    jae     .tail_end
    mov     [edi], al
    inc     edi
    inc     esi
    inc     ecx
    jmp     .tail_loop

.tail_end:
    mov     byte [edi], 0Dh

    mov     ax, [reg_CS]
    xor     bx, bx
    call    calc_linear_addr
    mov     edi, memory
    add     edi, eax
    mov     byte [edi + 80h], cl

.spt_done:
    pop     edi
    pop     esi
    pop     ecx
    pop     ebx
    pop     eax
    ret

parse_filename_and_args:
    call    skip_whitespace
    call    is_eol
    jc      .no_file

    mov     edi, current_filename
    xor     ecx, ecx

    mov     al, [esi]
    cmp     al, '"'
    je      .quoted_filename

.unquoted_filename:
    mov     al, [esi]
    test    al, al
    jz      .fn_done
    cmp     al, CR
    je      .fn_done
    cmp     al, LF
    je      .fn_done
    cmp     al, ' '
    je      .fn_done
    cmp     al, 9
    je      .fn_done
    cmp     al, ','
    je      .fn_done
    cmp     ecx, 255
    jae     .fn_skip_char
    stosb
    inc     ecx
.fn_skip_char:
    inc     esi
    jmp     .unquoted_filename

.quoted_filename:
    inc     esi
.quoted_loop:
    mov     al, [esi]
    test    al, al
    jz      .fn_done
    cmp     al, CR
    je      .fn_done
    cmp     al, LF
    je      .fn_done
    cmp     al, '"'
    je      .quoted_close
    cmp     ecx, 255
    jae     .q_skip_char
    stosb
    inc     ecx
.q_skip_char:
    inc     esi
    jmp     .quoted_loop
.quoted_close:
    inc     esi

.fn_done:
    mov     byte [edi], 0
    test    ecx, ecx
    jz      .no_file

    call    set_psp_command_tail
    clc
    ret

.no_file:
    mov     byte [current_filename], 0
    stc
    ret

parse_startup_cmdline:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    invoke  GetCommandLineA
    test    eax, eax
    jz      .psc_done

    mov     esi, eax
    call    skip_whitespace
    cmp     byte [esi], 0
    je      .psc_done

    cmp     byte [esi], '"'
    je      .skip_quoted_exe

.skip_unquoted_exe:
    mov     al, [esi]
    test    al, al
    jz      .psc_done
    cmp     al, ' '
    je      .exe_skipped
    cmp     al, 9
    je      .exe_skipped
    inc     esi
    jmp     .skip_unquoted_exe

.skip_quoted_exe:
    inc     esi
.skip_quoted_exe_loop:
    mov     al, [esi]
    test    al, al
    jz      .psc_done
    cmp     al, '"'
    je      .quote_closed
    inc     esi
    jmp     .skip_quoted_exe_loop
.quote_closed:
    inc     esi

.exe_skipped:
    call    skip_whitespace
    cmp     byte [esi], 0
    je      .psc_done
    cmp     byte [esi], CR
    je      .psc_done
    cmp     byte [esi], LF
    je      .psc_done

    call    parse_filename_and_args
    jc      .psc_done

    mov     ax, [reg_CS]
    mov     bx, 0100h
    call    do_load_file
    jnc     .psc_done

    mov     word [reg_BX], 0
    mov     word [reg_CX], 0

.psc_done:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

parse_address_cs:
    push    esi
    call    skip_whitespace
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

do_load_file:
    mov     [load_seg], ax
    mov     [load_off], bx

    cmp     byte [current_filename], 0
    je      .err_not_found

    mov     ax, [load_seg]
    mov     bx, [load_off]
    call    calc_linear_addr
    mov     edi, eax

    invoke  CreateFileA, current_filename, GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0
    cmp     eax, INVALID_HANDLE_VALUE
    je      .err_not_found
    mov     [file_handle], eax

    invoke  GetFileSize, [file_handle], 0
    cmp     eax, 0FFFFFFFFh
    je      .err_read_fail
    mov     [file_size], eax

    mov     edx, edi
    add     edx, [file_size]
    cmp     edx, MEM_SIZE
    ja      .err_no_mem

    cmp     word [load_off], 0100h
    jne     .skip_com_check
    cmp     dword [file_size], 0FF00h
    ja      .err_no_mem
.skip_com_check:

    lea     edx, [memory + edi]
    invoke  ReadFile, [file_handle], edx, [file_size], file_bytes_rw, 0
    test    eax, eax
    jz      .err_read_fail

    invoke  CloseHandle, [file_handle]

    mov     eax, [file_size]
    mov     [reg_CX], ax
    shr     eax, 16
    mov     [reg_BX], ax

    mov     ax, [load_seg]
    cmp     ax, [reg_CS]
    jne     .load_ok
    cmp     word [load_off], 0100h
    jne     .load_ok
    mov     word [reg_IP], 0100h
    mov     word [reg_AX], 0000h

.load_ok:
    clc
    ret

.err_no_mem:
    invoke  CloseHandle, [file_handle]
    mov     esi, msg_no_memory
    mov     ecx, msg_no_memory_len
    call    print_buffer
    stc
    ret

.err_read_fail:
    invoke  CloseHandle, [file_handle]
.err_not_found:
    mov     esi, msg_file_not_found
    mov     ecx, msg_file_not_found_len
    call    print_buffer
    stc
    ret

cmd_name:
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .empty_name

    call    parse_filename_and_args
    ret

.empty_name:
    mov     byte [current_filename], 0
    mov     ax, [reg_CS]
    xor     bx, bx
    call    calc_linear_addr
    cmp     eax, MEM_SIZE - 256
    jae     .ret
    mov     edi, memory
    add     edi, eax
    mov     byte [edi + 80h], 0
    mov     byte [edi + 81h], 0Dh
.ret:
    ret

cmd_load:
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .default_addr

    call    parse_address_cs
    jc      print_error_and_ret
    mov     dx, ax
    call    skip_whitespace
    call    is_eol
    jnc     print_error_and_ret
    mov     ax, dx
    jmp     .do_it

.default_addr:
    mov     ax, [reg_CS]
    mov     bx, 0100h

.do_it:
    call    do_load_file
    ret

cmd_write:
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .default_addr

    call    parse_address_cs
    jc      print_error_and_ret
    mov     dx, ax
    call    skip_whitespace
    call    is_eol
    jnc     print_error_and_ret
    mov     ax, dx
    jmp     .do_it

.default_addr:
    mov     ax, [reg_CS]
    mov     bx, 0100h

.do_it:
    mov     [load_seg], ax
    mov     [load_off], bx

    cmp     byte [current_filename], 0
    je      .err_create

    movzx   eax, word [reg_BX]
    shl     eax, 16
    mov     ax, word [reg_CX]
    mov     [file_size], eax

    mov     ax, [load_seg]
    mov     bx, [load_off]
    call    calc_linear_addr
    mov     edi, eax

    mov     edx, edi
    add     edx, [file_size]
    cmp     edx, MEM_SIZE
    ja      .err_create

    invoke  CreateFileA, current_filename, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0
    cmp     eax, INVALID_HANDLE_VALUE
    je      .err_create
    mov     [file_handle], eax

    cmp     dword [file_size], 0
    je      .skip_write
    lea     edx, [memory + edi]
    invoke  WriteFile, [file_handle], edx, [file_size], file_bytes_rw, 0
    test    eax, eax
    jz      .err_write_close

.skip_write:
    invoke  CloseHandle, [file_handle]

    mov     edi, line_buffer
    mov     esi, msg_writing
.cpy_writing:
    lodsb
    test    al, al
    jz      .cpy_w_done
    stosb
    jmp     .cpy_writing
.cpy_w_done:

    cmp     word [reg_BX], 0
    je      .put_cx_only
    mov     ax, [reg_BX]
    call    put_hex_word
.put_cx_only:
    mov     ax, [reg_CX]
    call    put_hex_word

    mov     esi, msg_bytes
.cpy_bytes:
    lodsb
    test    al, al
    jz      .cpy_b_done
    stosb
    jmp     .cpy_bytes
.cpy_b_done:

    mov     edx, edi
    sub     edx, line_buffer
    push    edx
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0
    test    eax, eax
    jnz     .cw_out_ok
    mov     edx, [esp]
    invoke  WriteFile, [hStdOut], line_buffer, edx, chars_written, 0
.cw_out_ok:
    pop     edx
    ret

.err_write_close:
    invoke  CloseHandle, [file_handle]
.err_create:
    mov     esi, msg_file_create_err
    mov     ecx, msg_file_create_err_len
    call    print_buffer
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

    mov     word [dump_len], DUMP_DEFAULT_LEN

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
    mov     [move_len], cx
    push    ecx

    call    parse_address
    jnc     .cm_dst_ok
    pop     ecx
    jmp     .cm_err

.cm_dst_ok:
    mov     [move_dst_seg], ax
    mov     [move_dst_off], bx
    pop     ecx

    test    ecx, ecx
    jz      .cm_done

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

    movzx   eax, word [move_src_seg]
    shl     eax, 4
    lea     esi, [memory + eax]

    movzx   eax, word [move_dst_seg]
    shl     eax, 4
    lea     edi, [memory + eax]

    mov     bx, [move_src_off]
    mov     dx, [move_dst_off]

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
    invoke  WriteConsoleA, [hStdOut], line_buffer, 2, chars_written, 0
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
    xor     ecx, ecx

.cs_next_token:
    call    skip_whitespace
    call    is_eol
    jc      .cs_pat_done

    cmp     ecx, FILL_PAT_MAX
    jae     .cs_pat_done

    cmp     al, 22h
    je      .cs_string
    cmp     al, 27h
    je      .cs_string

    call    parse_hex_byte
    jc      print_error_and_ret
    stosb
    inc     ecx
    jmp     .cs_next_token

.cs_string:
    mov     dl, al
    inc     esi
.cs_str_loop:
    mov     al, [esi]
    call    is_eol
    jc      .cs_pat_done
    cmp     al, dl
    je      .cs_str_end

    cmp     ecx, FILL_PAT_MAX
    jae     .cs_pat_done

    stosb
    inc     ecx
    inc     esi
    jmp     .cs_str_loop
.cs_str_end:
    inc     esi
    jmp     .cs_next_token

.cs_pat_done:
    test    ecx, ecx
    jz      print_error_and_ret
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

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0

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
    invoke  WriteConsoleA, [hStdOut], line_buffer, 2, chars_written, 0
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
    test    eax, eax
    jnz     .prompt_ok
    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteFile, [hStdOut], line_buffer, edx, chars_written, 0
.prompt_ok:
    mov     [prompt_len], edx

    mov     edi, input_buffer
    mov     edx, 255
    call    read_line_console_or_pipe
    jc      .done
    
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
    mov     dword [prompt_len], 1
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

    mov     ax, [unasm_seg]
    mov     bx, [unasm_off]
    xor     cl, cl
    call    disasm_line
    add     [unasm_off], bx

    mov     ax, [unasm_len]
    sub     ax, bx
    jbe     .done
    mov     [unasm_len], ax
    jmp     .unasm_loop

.done:
    ret

disasm_line:
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp
    sub     esp, 16

    movzx   edx, ax
    mov     [esp+0], edx
    movzx   edx, bx
    mov     [esp+4], edx
    movzx   edx, cl
    mov     [esp+8], edx
    mov     dword [esp+12], 1
    mov     dword [dis_is_unary], 0

    mov     edi, line_buffer
    mov     ax, [esp+0]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, [esp+4]
    call    put_hex_word
    mov     al, SPACE
    stosb
    stosb

    mov     ax, [esp+0]
    mov     bx, [esp+4]
    call    calc_linear_addr
    cmp     eax, MEM_SIZE
    jae     .out_of_mem

    mov     ebp, memory
    add     ebp, eax

    mov     al, [ebp]

    cmp     al, 70h
    jb      .not_dis_jcc
    cmp     al, 7Fh
    jbe     .dis_jcc
.not_dis_jcc:

    cmp     al, 0EBh
    je      .dis_jmp_short
    cmp     al, 0E9h
    je      .dis_jmp_near
    cmp     al, 0E8h
    je      .dis_call_near
    cmp     al, 0E0h
    je      .dis_loopnz
    cmp     al, 0E1h
    je      .dis_loopz
    cmp     al, 0E2h
    je      .dis_loop
    cmp     al, 0E3h
    je      .dis_jcxz

    cmp     al, 40h
    jb      .not_dis_inc
    cmp     al, 47h
    jbe     .dis_inc_r16
.not_dis_inc:

    cmp     al, 50h
    jb      .not_dis_push
    cmp     al, 57h
    jbe     .dis_push_r16
.not_dis_push:

    cmp     al, 58h
    jb      .not_dis_pop
    cmp     al, 5Fh
    jbe     .dis_pop_r16
.not_dis_pop:

    cmp     al, 91h
    jb      .not_dis_xchg_ax
    cmp     al, 97h
    jbe     .dis_xchg_ax_r16
.not_dis_xchg_ax:

    cmp     al, 9Ah
    je      .dis_call_far
    cmp     al, 0EAh
    je      .dis_jmp_far
    cmp     al, 0E6h
    je      .dis_out_imm
    cmp     al, 0E7h
    je      .dis_out_imm
    cmp     al, 0D4h
    je      .dis_aam_aad
    cmp     al, 0D5h
    je      .dis_aam_aad

    call    find_opcode
    jc      .try_dis_modrm


    movzx   ebx, dl
    inc     ebx
    mov     [esp+12], ebx

    mov     eax, ebp
    sub     eax, memory
    add     eax, ebx
    cmp     eax, MEM_SIZE
    jbe     .have_bytes

.not_found:
    mov     dword [esp+12], 1
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
    jmp     .line_done

.out_of_mem:
    mov     al, '?'
    stosb
    mov     al, '?'
    stosb
    mov     dword [esp+12], 1
    jmp     .write_line

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
    cmp     dword [esp+8], 0
    jz      .write_line

    ; Memory Operand Preview
    mov     esi, ebp
    xor     edx, edx            ; override segment name (2 chars), 0 = none
    mov     al, [esi]
    cmp     al, 26h
    jne     .res_chk_cs
    mov     edx, 'ES'
    inc     esi
    jmp     .res_got_prefix
.res_chk_cs:
    cmp     al, 2Eh
    jne     .res_chk_ss
    mov     edx, 'CS'
    inc     esi
    jmp     .res_got_prefix
.res_chk_ss:
    cmp     al, 36h
    jne     .res_chk_ds
    mov     edx, 'SS'
    inc     esi
    jmp     .res_got_prefix
.res_chk_ds:
    cmp     al, 3Eh
    jne     .res_chk_ext
    mov     edx, 'DS'
    inc     esi
    jmp     .res_got_prefix
.res_chk_ext:
    cmp     dword [seg_override], 0
    jz      .res_got_prefix
    cmp     dword [seg_override], reg_ES
    jne     .res_ext_cs
    mov     edx, 'ES'
    jmp     .res_got_prefix
.res_ext_cs:
    cmp     dword [seg_override], reg_CS
    jne     .res_ext_ss
    mov     edx, 'CS'
    jmp     .res_got_prefix
.res_ext_ss:
    cmp     dword [seg_override], reg_SS
    jne     .res_ext_ds
    mov     edx, 'SS'
    jmp     .res_got_prefix
.res_ext_ds:
    cmp     dword [seg_override], reg_DS
    jne     .res_got_prefix
    mov     edx, 'DS'
.res_got_prefix:

    mov     al, [esi]

    ; Direct MOV A0..A3
    cmp     al, 0A0h
    jb      .res_not_direct
    cmp     al, 0A3h
    ja      .res_not_direct
    movzx   ebx, word [esi+1]
    mov     cl, al
    and     cl, 1               ; is_word
    test    edx, edx
    jnz     .res_direct_seg
    mov     edx, 'DS'
.res_direct_seg:
    jmp     .res_have_ea

.res_not_direct:
    ; ALU 00..03, 08..0B, 10..13, 18..1B, 20..23, 28..2B, 30..33, 38..3B
    cmp     al, 3Bh
    ja      .res_chk_mov
    mov     ah, al
    and     ah, 07h
    cmp     ah, 3
    ja      .res_no_mem
    mov     cl, al
    and     cl, 1               ; is_word
    jmp     .res_is_modrm

.res_chk_mov:
    cmp     al, 88h
    jb      .res_chk_imm_alu
    cmp     al, 8Bh
    ja      .res_chk_mov_imm
    mov     cl, al
    and     cl, 1               ; is_word
    jmp     .res_is_modrm

.res_chk_mov_imm:
    cmp     al, 0C6h
    je      .res_c6
    cmp     al, 0C7h
    je      .res_c7
    jmp     .res_chk_lea_sreg
.res_c6:
    mov     cl, 0
    jmp     .res_is_modrm
.res_c7:
    mov     cl, 1
    jmp     .res_is_modrm

.res_chk_lea_sreg:
    cmp     al, 8Ch
    jb      .res_chk_test_xchg
    cmp     al, 8Fh
    jbe     .res_modrm_word
    cmp     al, 0C4h
    je      .res_modrm_word
    cmp     al, 0C5h
    je      .res_modrm_word
    jmp     .res_chk_test_xchg
.res_modrm_word:
    mov     cl, 1
    jmp     .res_is_modrm

.res_chk_test_xchg:
    cmp     al, 84h
    jb      .res_chk_f6_f7
    cmp     al, 87h
    ja      .res_chk_f6_f7
    mov     cl, al
    and     cl, 1
    jmp     .res_is_modrm

.res_chk_f6_f7:
    cmp     al, 0F6h
    je      .res_f6
    cmp     al, 0F7h
    je      .res_f7
    jmp     .res_chk_fe_ff
.res_f6:
    mov     cl, 0
    jmp     .res_is_modrm
.res_f7:
    mov     cl, 1
    jmp     .res_is_modrm

.res_chk_fe_ff:
    cmp     al, 0FEh
    je      .res_fe
    cmp     al, 0FFh
    je      .res_ff
    jmp     .res_no_mem
.res_fe:
    mov     cl, 0
    jmp     .res_is_modrm
.res_ff:
    mov     cl, 1
    jmp     .res_is_modrm

.res_chk_imm_alu:
    cmp     al, 80h
    jb      .res_no_mem
    cmp     al, 83h
    ja      .res_no_mem
    mov     cl, 0
    cmp     al, 81h
    je      .res_imm_w
    cmp     al, 83h
    je      .res_imm_w
    jmp     .res_is_modrm
.res_imm_w:
    mov     cl, 1

.res_is_modrm:
    mov     ah, [esi+1]         ; modrm byte
    cmp     ah, 0C0h
    jae     .res_no_mem         ; mod == 3 -> not memory!

    push    ecx                 ; [esp]: is_word
    push    edx                 ; [esp+4]: override seg name

    mov     ch, ah
    shr     ch, 6               ; ch = mod
    and     ah, 7               ; ah = rm

    cmp     ah, 0
    jne     .res_rm1
    movzx   ebx, word [reg_BX]
    add     bx, word [reg_SI]
    mov     edx, 'DS'
    jmp     .res_apply_disp
.res_rm1:
    cmp     ah, 1
    jne     .res_rm2
    movzx   ebx, word [reg_BX]
    add     bx, word [reg_DI]
    mov     edx, 'DS'
    jmp     .res_apply_disp
.res_rm2:
    cmp     ah, 2
    jne     .res_rm3
    movzx   ebx, word [reg_BP]
    add     bx, word [reg_SI]
    mov     edx, 'SS'
    jmp     .res_apply_disp
.res_rm3:
    cmp     ah, 3
    jne     .res_rm4
    movzx   ebx, word [reg_BP]
    add     bx, word [reg_DI]
    mov     edx, 'SS'
    jmp     .res_apply_disp
.res_rm4:
    cmp     ah, 4
    jne     .res_rm5
    movzx   ebx, word [reg_SI]
    mov     edx, 'DS'
    jmp     .res_apply_disp
.res_rm5:
    cmp     ah, 5
    jne     .res_rm6
    movzx   ebx, word [reg_DI]
    mov     edx, 'DS'
    jmp     .res_apply_disp
.res_rm6:
    cmp     ah, 6
    jne     .res_rm7
    test    ch, ch
    jnz     .res_bp_base
    ; mod == 0, rm == 6: direct address
    movzx   ebx, word [esi+2]
    mov     edx, 'DS'
    jmp     .res_disp_done
.res_bp_base:
    movzx   ebx, word [reg_BP]
    mov     edx, 'SS'
    jmp     .res_apply_disp
.res_rm7:
    movzx   ebx, word [reg_BX]
    mov     edx, 'DS'

.res_apply_disp:
    cmp     ch, 1
    jne     .res_chk_disp2
    movsx   ax, byte [esi+2]
    add     bx, ax
    jmp     .res_disp_done
.res_chk_disp2:
    cmp     ch, 2
    jne     .res_disp_done
    add     bx, word [esi+2]

.res_disp_done:
    pop     eax                 ; override seg name
    test    eax, eax
    jz      .res_default_seg_kept
    mov     edx, eax
.res_default_seg_kept:
    pop     ecx                 ; cl = is_word

.res_have_ea:
    push    ecx                 ; [esp+8]: is_word
    push    edx                 ; [esp+4]: segment name ('DS', 'SS', etc.)
    push    ebx                 ; [esp+0]: offset

    cmp     edx, 'SS'
    je      .res_val_ss
    cmp     edx, 'ES'
    je      .res_val_es
    cmp     edx, 'CS'
    je      .res_val_cs
    mov     ax, word [reg_DS]
    jmp     .res_calc_linear
.res_val_ss:
    mov     ax, word [reg_SS]
    jmp     .res_calc_linear
.res_val_es:
    mov     ax, word [reg_ES]
    jmp     .res_calc_linear
.res_val_cs:
    mov     ax, word [reg_CS]

.res_calc_linear:
    call    calc_linear_addr
    cmp     eax, MEM_SIZE
    jae     .res_skip_preview
    cmp     byte [esp+8], 1     ; is_word?
    jne     .res_read_val
    cmp     eax, MEM_SIZE - 1
    jae     .res_skip_preview

.res_read_val:
    cmp     byte [esp+8], 1
    jne     .res_byte_val
    movzx   esi, word [memory + eax]
    jmp     .res_align_col
.res_byte_val:
    movzx   esi, byte [memory + eax]

.res_align_col:
    mov     eax, edi
    sub     eax, line_buffer
    cmp     eax, 55
    jae     .res_pad_one
    mov     ecx, 55
    sub     ecx, eax
    mov     al, SPACE
    rep     stosb
    jmp     .res_output_str
.res_pad_one:
    mov     al, SPACE
    stosb

.res_output_str:
    pop     ebx                 ; offset
    pop     edx                 ; segment name
    pop     ecx                 ; is_word

    mov     ax, dx
    stosw
    mov     al, COLON
    stosb
    mov     ax, bx
    call    put_hex_word
    mov     al, '='
    stosb
    test    cl, cl
    jnz     .res_val_w
    mov     eax, esi
    call    put_hex_byte
    jmp     .write_line
.res_val_w:
    mov     ax, si
    call    put_hex_word
    jmp     .write_line

.res_skip_preview:
    pop     ebx
    pop     edx
    pop     ecx
    jmp     .write_line

.res_no_mem:

.write_line:
    mov     al, CR
    stosb
    mov     al, LF
    stosb

    mov     edx, edi
    sub     edx, line_buffer
    push    edx
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0
    test    eax, eax
    jnz     .dis_out_ok
    mov     edx, [esp]
    invoke  WriteFile, [hStdOut], line_buffer, edx, chars_written, 0
.dis_out_ok:
    pop     edx

    mov     ebx, [esp+12]
    add     esp, 16
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    ret

.try_dis_modrm:
    mov     al, [ebp]

    ; Check for segment override prefix byte at [ebp]
    cmp     al, 26h
    je      .dis_pref_es
    cmp     al, 2Eh
    je      .dis_pref_cs
    cmp     al, 36h
    je      .dis_pref_ss
    cmp     al, 3Eh
    je      .dis_pref_ds
    jmp     .dis_check_direct

.dis_pref_es:
    mov     ax, 'ES'
    jmp     .dis_emit_prefix
.dis_pref_cs:
    mov     ax, 'CS'
    jmp     .dis_emit_prefix
.dis_pref_ss:
    mov     ax, 'SS'
    jmp     .dis_emit_prefix
.dis_pref_ds:
    mov     ax, 'DS'
.dis_emit_prefix:
    mov     dword [esp+12], 1
    push    eax
    mov     al, [ebp]
    call    put_hex_byte
    mov     ecx, 12
    mov     al, SPACE
    rep     stosb
    pop     eax
    mov     [edi], ax
    add     edi, 2
    mov     al, COLON
    stosb
    jmp     .line_done

.dis_check_direct:
    ; Check for direct memory moves: A0h..A3h
    cmp     al, 0A0h
    jb      .dis_not_direct
    cmp     al, 0A3h
    ja      .dis_not_direct

    ; Length = 3
    mov     eax, ebp
    sub     eax, memory
    add     eax, 3
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     dword [esp+12], 3

    mov     al, [ebp]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte
    mov     al, [ebp+2]
    call    put_hex_byte

    mov     ecx, 8
    mov     al, SPACE
    rep     stosb

    mov     al, 'M'
    stosb
    mov     al, 'O'
    stosb
    mov     al, 'V'
    stosb
    mov     ecx, 5
    mov     al, SPACE
    rep     stosb

    mov     al, [ebp]
    cmp     al, 0A0h
    je      .dis_dm_al_from_mem
    cmp     al, 0A1h
    je      .dis_dm_ax_from_mem
    cmp     al, 0A2h
    je      .dis_dm_mem_from_al
    ; A3h: MOV [disp], AX
    mov     al, '['
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    mov     al, ']'
    stosb
    mov     al, COMMA
    stosb
    mov     ax, 'AX'
    stosw
    jmp     .line_done

.dis_dm_mem_from_al:
    mov     al, '['
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    mov     al, ']'
    stosb
    mov     al, COMMA
    stosb
    mov     ax, 'AL'
    stosw
    jmp     .line_done

.dis_dm_al_from_mem:
    mov     ax, 'AL'
    stosw
    mov     al, COMMA
    stosb
    mov     al, '['
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    mov     al, ']'
    stosb
    jmp     .line_done

.dis_dm_ax_from_mem:
    mov     ax, 'AX'
    stosw
    mov     al, COMMA
    stosb
    mov     al, '['
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    mov     al, ']'
    stosb
    jmp     .line_done

.dis_not_direct:
    mov     dword [dis_is_unary], 0
    ; Check ModR/M opcodes
    cmp     al, 3Bh
    ja      .dis_chk_mov
    mov     ah, al
    and     ah, 07h
    cmp     ah, 3
    ja      .not_found
    ; ALU 00..03, 08..0B, 10..13, 18..1B, 20..23, 28..2B, 30..33, 38..3B
    movzx   edx, al
    and     edx, 1
    mov     [dis_is_word], edx
    movzx   edx, al
    shr     edx, 1
    and     edx, 1
    mov     [dis_dir], edx
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    movzx   edx, al
    shr     edx, 3
    and     edx, 7
    shl     edx, 2
    lea     edx, [alu_op_names + edx]
    mov     [dis_mnem_ptr], edx
    jmp     .dis_have_modrm_params

.dis_chk_mov:
    cmp     al, 88h
    jb      .dis_chk_imm_alu
    cmp     al, 8Bh
    ja      .dis_chk_mov_imm
    ; MOV 88..8B
    movzx   edx, al
    and     edx, 1
    mov     [dis_is_word], edx
    movzx   edx, al
    shr     edx, 1
    and     edx, 1
    mov     [dis_dir], edx
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_mov
    jmp     .dis_have_modrm_params

.dis_chk_mov_imm:
    cmp     al, 0C6h
    je      .dis_mov_c6
    cmp     al, 0C7h
    je      .dis_mov_c7
    jmp     .dis_chk_sreg
.dis_mov_c6:
    mov     dword [dis_is_word], 0
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 1
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_mov
    jmp     .dis_have_modrm_params
.dis_mov_c7:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 2
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_mov
    jmp     .dis_have_modrm_params

.dis_chk_sreg:
    cmp     al, 8Ch
    je      .dis_mov_to_rm_sreg
    cmp     al, 8Eh
    je      .dis_mov_to_sreg_rm
    cmp     al, 8Fh
    je      .dis_pop_rm16
    jmp     .dis_chk_lea
.dis_pop_rm16:
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    jnz     .not_found
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_is_unary], 1
    mov     dword [dis_mnem_ptr], str_mnem_pop
    jmp     .dis_have_modrm_params
.dis_mov_to_rm_sreg:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 1
    mov     dword [dis_mnem_ptr], str_mnem_mov
    jmp     .dis_have_modrm_params
.dis_mov_to_sreg_rm:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 1
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 1
    mov     dword [dis_mnem_ptr], str_mnem_mov
    jmp     .dis_have_modrm_params

.dis_chk_lea:
    cmp     al, 8Dh
    jne     .dis_chk_test_xchg
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 1
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_lea
    jmp     .dis_have_modrm_params

.dis_chk_test_xchg:
    cmp     al, 84h
    je      .dis_op_test_b
    cmp     al, 85h
    je      .dis_op_test_w
    cmp     al, 86h
    je      .dis_op_xchg_b
    cmp     al, 87h
    je      .dis_op_xchg_w
    cmp     al, 0C4h
    je      .dis_op_les
    cmp     al, 0C5h
    je      .dis_op_lds
    cmp     al, 0F6h
    je      .dis_op_f6
    cmp     al, 0F7h
    je      .dis_op_f7
    cmp     al, 0FEh
    je      .dis_op_fe
    cmp     al, 0FFh
    je      .dis_op_ff
    jmp     .not_found
.dis_op_test_b:
    mov     dword [dis_is_word], 0
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_test
    jmp     .dis_have_modrm_params
.dis_op_test_w:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_test
    jmp     .dis_have_modrm_params
.dis_op_xchg_b:
    mov     dword [dis_is_word], 0
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_xchg
    jmp     .dis_have_modrm_params
.dis_op_xchg_w:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_xchg
    jmp     .dis_have_modrm_params
.dis_op_les:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 1
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_les
    jmp     .dis_have_modrm_params
.dis_op_lds:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 1
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_lds
    jmp     .dis_have_modrm_params

.dis_op_f6:
    mov     dword [dis_is_word], 0
    jmp     .dis_f6_f7_common
.dis_op_f7:
    mov     dword [dis_is_word], 1
.dis_f6_f7_common:
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    mov     eax, [f6_f7_mnems + edx*4]
    test    eax, eax
    jz      .not_found
    mov     [dis_mnem_ptr], eax
    mov     dword [dis_dir], 0
    mov     dword [dis_is_sreg], 0
    test    edx, edx
    jnz     .dis_f67_unary
    mov     eax, [dis_is_word]
    inc     eax
    mov     [dis_imm_len], eax
    mov     dword [dis_is_unary], 0
    jmp     .dis_have_modrm_params
.dis_f67_unary:
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_unary], 2
    jmp     .dis_have_modrm_params

.dis_op_fe:
    mov     dword [dis_is_word], 0
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    cmp     edx, 1
    ja      .not_found
    mov     eax, [fe_ff_mnems + edx*4]
    mov     [dis_mnem_ptr], eax
    mov     dword [dis_dir], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_unary], 2
    jmp     .dis_have_modrm_params

.dis_op_ff:
    mov     dword [dis_is_word], 1
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    cmp     edx, 6
    ja      .not_found
    mov     eax, [fe_ff_mnems + edx*4]
    test    eax, eax
    jz      .not_found
    mov     [dis_mnem_ptr], eax
    mov     dword [dis_dir], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_imm_len], 0
    cmp     edx, 6
    je      .dis_ff_push
    mov     dword [dis_is_unary], 2
    jmp     .dis_have_modrm_params
.dis_ff_push:
    mov     dword [dis_is_unary], 1
    jmp     .dis_have_modrm_params

.dis_chk_imm_alu:
    cmp     al, 80h
    jb      .not_found
    cmp     al, 83h
    ja      .dis_chk_test_xchg
    mov     dword [dis_dir], 0
    mov     dword [dis_is_sreg], 0
    cmp     al, 80h
    je      .dis_alu_imm_80
    cmp     al, 81h
    je      .dis_alu_imm_81
    cmp     al, 82h
    je      .dis_alu_imm_80
    ; 83h: is_word = 1, imm_len = 1
    mov     dword [dis_is_word], 1
    mov     dword [dis_imm_len], 1
    jmp     .dis_imm_alu_mnem
.dis_alu_imm_80:
    mov     dword [dis_is_word], 0
    mov     dword [dis_imm_len], 1
    jmp     .dis_imm_alu_mnem
.dis_alu_imm_81:
    mov     dword [dis_is_word], 1
    mov     dword [dis_imm_len], 2
.dis_imm_alu_mnem:
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    shl     edx, 2
    lea     edx, [alu_op_names + edx]
    mov     [dis_mnem_ptr], edx

.dis_have_modrm_params:
    movzx   eax, byte [ebp+1]   ; modrm byte
    mov     ecx, eax
    shr     ecx, 6              ; mod
    and     eax, 7              ; rm
    xor     edx, edx
    test    ecx, ecx
    jnz     .dis_mod1_chk
    cmp     eax, 6
    jne     .dis_got_disp_len
    mov     edx, 2
    jmp     .dis_got_disp_len
.dis_mod1_chk:
    cmp     ecx, 1
    jne     .dis_mod2_chk
    mov     edx, 1
    jmp     .dis_got_disp_len
.dis_mod2_chk:
    cmp     ecx, 2
    jne     .dis_got_disp_len
    mov     edx, 2
.dis_got_disp_len:
    mov     [dis_disp_len], edx

    mov     eax, 2
    add     eax, edx
    add     eax, [dis_imm_len]
    mov     [esp+12], eax       ; insn_len

    mov     edx, ebp
    sub     edx, memory
    add     edx, eax
    cmp     edx, MEM_SIZE
    ja      .not_found

    ; Output hex bytes:
    mov     esi, ebp
    mov     ecx, [esp+12]
.dis_hex_loop:
    lodsb
    call    put_hex_byte
    loop    .dis_hex_loop

    mov     eax, 14
    mov     ecx, [esp+12]
    sub     eax, ecx
    sub     eax, ecx
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb

    ; Output mnemonic:
    mov     esi, [dis_mnem_ptr]
    xor     ecx, ecx
.dis_mnem_loop:
    lodsb
    test    al, al
    jz      .dis_mnem_pad
    cmp     al, SPACE
    je      .dis_mnem_pad
    stosb
    inc     ecx
    cmp     ecx, 4
    jb      .dis_mnem_loop
.dis_mnem_pad:
    mov     eax, 8
    sub     eax, ecx
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb

    ; Output operands:
    cmp     dword [dis_is_unary], 0
    jz      .dis_not_unary
    call    .dm_write_rm
    jmp     .line_done

.dis_not_unary:
    cmp     dword [dis_imm_len], 0
    jnz     .dis_ops_rm_imm

    cmp     dword [dis_dir], 1
    je      .dis_ops_reg_rm

    ; dir == 0: r/m, reg
    call    .dm_write_rm
    mov     al, COMMA
    stosb
    call    .dm_write_reg
    jmp     .line_done

.dis_ops_reg_rm:
    call    .dm_write_reg
    mov     al, COMMA
    stosb
    call    .dm_write_rm
    jmp     .line_done

.dis_ops_rm_imm:
    call    .dm_write_rm
    mov     al, COMMA
    stosb
    mov     edx, 2
    add     edx, [dis_disp_len]
    cmp     dword [dis_imm_len], 1
    je      .dis_ops_imm8
    mov     ax, word [ebp + edx]
    call    put_hex_word
    jmp     .line_done
.dis_ops_imm8:
    mov     al, byte [ebp + edx]
    call    put_hex_byte
    jmp     .line_done

.dm_write_reg:
    movzx   eax, byte [ebp+1]
    shr     eax, 3
    and     eax, 7
    cmp     dword [dis_is_sreg], 1
    jne     .dm_not_sreg
    and     eax, 3
    lea     edx, [sreg_names + eax*2]
    mov     ax, [edx]
    stosw
    ret
.dm_not_sreg:
    cmp     dword [dis_is_word], 1
    jne     .dm_reg8
    lea     edx, [op_reg16_names + eax*2]
    mov     ax, [edx]
    stosw
    ret
.dm_reg8:
    lea     edx, [op_reg8_names + eax*2]
    mov     ax, [edx]
    stosw
    ret

.dm_write_rm:
    movzx   eax, byte [ebp+1]
    mov     ecx, eax
    shr     ecx, 6              ; mod
    and     eax, 7              ; rm
    cmp     ecx, 3
    jne     .dm_rm_mem
    cmp     dword [dis_is_word], 1
    jne     .dm_rm_r8
    lea     edx, [op_reg16_names + eax*2]
    mov     ax, [edx]
    stosw
    ret
.dm_rm_r8:
    lea     edx, [op_reg8_names + eax*2]
    mov     ax, [edx]
    stosw
    ret

.dm_rm_mem:
    cmp     dword [dis_imm_len], 0
    jnz     .dm_print_size_prefix
    cmp     dword [dis_is_unary], 2
    je      .dm_print_size_prefix
    jmp     .dm_no_size_spec

.dm_print_size_prefix:
    cmp     dword [dis_is_word], 1
    jne     .dm_spec_b
    mov     eax, 'WORD'
    stosd
    mov     al, SPACE
    stosb
    mov     ax, 'PT'
    stosw
    mov     al, 'R'
    stosb
    mov     al, SPACE
    stosb
    jmp     .dm_no_size_spec
.dm_spec_b:
    mov     eax, 'BYTE'
    stosd
    mov     al, SPACE
    stosb
    mov     ax, 'PT'
    stosw
    mov     al, 'R'
    stosb
    mov     al, SPACE
    stosb

.dm_no_size_spec:
    movzx   eax, byte [ebp+1]
    mov     ecx, eax
    shr     ecx, 6              ; mod
    and     eax, 7              ; rm
    mov     byte [edi], '['
    inc     edi
    test    ecx, ecx
    jnz     .dm_mem_has_base
    cmp     eax, 6
    jne     .dm_mem_has_base
    ; mod == 0, rm == 6: direct address
    mov     ax, word [ebp+2]
    call    put_hex_word
    mov     byte [edi], ']'
    inc     edi
    ret

.dm_mem_has_base:
    lea     esi, [modrm_base_names + eax*8]
.dm_copy_base_chars:
    lodsb
    test    al, al
    jz      .dm_base_copied
    stosb
    jmp     .dm_copy_base_chars
.dm_base_copied:
    cmp     ecx, 1
    jne     .dm_disp_word_chk
    mov     al, byte [ebp+2]
    cmp     al, 0
    jge     .dm_disp_byte_pos
    mov     byte [edi], '-'
    inc     edi
    neg     al
    call    put_hex_byte
    jmp     .dm_close_rm_bracket
.dm_disp_byte_pos:
    mov     byte [edi], '+'
    inc     edi
    call    put_hex_byte
    jmp     .dm_close_rm_bracket
.dm_disp_word_chk:
    cmp     ecx, 2
    jne     .dm_close_rm_bracket
    mov     byte [edi], '+'
    inc     edi
    mov     ax, word [ebp+2]
    call    put_hex_word
.dm_close_rm_bracket:
    mov     byte [edi], ']'
    inc     edi
    ret

.dis_jcc:
    mov     dword [esp+12], 2
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

    movzx   eax, byte [ebp]
    sub     eax, 70h
    shl     eax, 2
    lea     esi, [jcc_names + eax]
    mov     al, [esi]
    stosb
    mov     al, [esi+1]
    stosb
    mov     al, [esi+2]
    cmp     al, ' '
    je      .jcc_skip_sp
    stosb
    mov     ecx, 5
    jmp     .jcc_pad
.jcc_skip_sp:
    mov     ecx, 6
.jcc_pad:
    mov     al, SPACE
    rep     stosb

    movsx   eax, byte [ebp+1]
    add     ax, [esp+4]
    add     ax, 2
    call    put_hex_word
    jmp     .line_done

.dis_jmp_short:
    mov     dword [esp+12], 2
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
    mov     al, 'M'
    stosb
    mov     al, 'P'
    stosb

    mov     ecx, 5
    mov     al, SPACE
    rep     stosb

    movsx   eax, byte [ebp+1]
    add     ax, [esp+4]
    add     ax, 2
    call    put_hex_word
    jmp     .line_done

.dis_loopnz:
    mov     dword [esp+12], 2
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

    mov     al, 'L'
    stosb
    mov     al, 'O'
    stosb
    mov     al, 'O'
    stosb
    mov     al, 'P'
    stosb
    mov     al, 'N'
    stosb
    mov     al, 'Z'
    stosb

    mov     ecx, 2
    mov     al, SPACE
    rep     stosb

    movsx   eax, byte [ebp+1]
    add     ax, [esp+4]
    add     ax, 2
    call    put_hex_word
    jmp     .line_done

.dis_loopz:
    mov     dword [esp+12], 2
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

    mov     al, 'L'
    stosb
    mov     al, 'O'
    stosb
    mov     al, 'O'
    stosb
    mov     al, 'P'
    stosb
    mov     al, 'Z'
    stosb

    mov     ecx, 3
    mov     al, SPACE
    rep     stosb

    movsx   eax, byte [ebp+1]
    add     ax, [esp+4]
    add     ax, 2
    call    put_hex_word
    jmp     .line_done

.dis_loop:
    mov     dword [esp+12], 2
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

    mov     al, 'L'
    stosb
    mov     al, 'O'
    stosb
    mov     al, 'O'
    stosb
    mov     al, 'P'
    stosb

    mov     ecx, 4
    mov     al, SPACE
    rep     stosb

    movsx   eax, byte [ebp+1]
    add     ax, [esp+4]
    add     ax, 2
    call    put_hex_word
    jmp     .line_done

.dis_jcxz:
    mov     dword [esp+12], 2
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
    mov     al, 'C'
    stosb
    mov     al, 'X'
    stosb
    mov     al, 'Z'
    stosb

    mov     ecx, 4
    mov     al, SPACE
    rep     stosb

    movsx   eax, byte [ebp+1]
    add     ax, [esp+4]
    add     ax, 2
    call    put_hex_word
    jmp     .line_done

.dis_jmp_near:
    mov     dword [esp+12], 3
    mov     eax, ebp
    sub     eax, memory
    add     eax, 3
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     al, [ebp]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte
    mov     al, [ebp+2]
    call    put_hex_byte

    mov     ecx, 8
    mov     al, SPACE
    rep     stosb

    mov     al, 'J'
    stosb
    mov     al, 'M'
    stosb
    mov     al, 'P'
    stosb

    mov     ecx, 5
    mov     al, SPACE
    rep     stosb

    mov     ax, word [ebp+1]
    add     ax, [esp+4]
    add     ax, 3
    call    put_hex_word
    jmp     .line_done

.dis_call_near:
    mov     dword [esp+12], 3
    mov     eax, ebp
    sub     eax, memory
    add     eax, 3
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     al, [ebp]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte
    mov     al, [ebp+2]
    call    put_hex_byte

    mov     ecx, 8
    mov     al, SPACE
    rep     stosb

    mov     al, 'C'
    stosb
    mov     al, 'A'
    stosb
    mov     al, 'L'
    stosb
    mov     al, 'L'
    stosb

    mov     ecx, 4
    mov     al, SPACE
    rep     stosb

    mov     ax, word [ebp+1]
    add     ax, [esp+4]
    add     ax, 3
    call    put_hex_word
    jmp     .line_done

.dis_inc_r16:
    mov     dword [esp+12], 1
    mov     al, [ebp]
    call    put_hex_byte

    mov     ecx, 12
    mov     al, SPACE
    rep     stosb

    mov     al, 'I'
    stosb
    mov     al, 'N'
    stosb
    mov     al, 'C'
    stosb

    mov     ecx, 5
    mov     al, SPACE
    rep     stosb

    movzx   eax, byte [ebp]
    sub     eax, 40h
    shl     eax, 1
    lea     esi, [op_reg16_names + eax]
    lodsw
    stosw
    jmp     .line_done

.dis_push_r16:
    mov     dword [esp+12], 1
    mov     al, [ebp]
    call    put_hex_byte

    mov     ecx, 12
    mov     al, SPACE
    rep     stosb

    mov     al, 'P'
    stosb
    mov     al, 'U'
    stosb
    mov     al, 'S'
    stosb
    mov     al, 'H'
    stosb

    mov     ecx, 4
    mov     al, SPACE
    rep     stosb

    movzx   eax, byte [ebp]
    sub     eax, 50h
    shl     eax, 1
    lea     esi, [op_reg16_names + eax]
    lodsw
    stosw
    jmp     .line_done

.dis_pop_r16:
    mov     dword [esp+12], 1
    mov     al, [ebp]
    call    put_hex_byte

    mov     ecx, 12
    mov     al, SPACE
    rep     stosb

    mov     al, 'P'
    stosb
    mov     al, 'O'
    stosb
    mov     al, 'P'
    stosb

    mov     ecx, 5
    mov     al, SPACE
    rep     stosb

    movzx   eax, byte [ebp]
    sub     eax, 58h
    shl     eax, 1
    lea     esi, [op_reg16_names + eax]
    lodsw
    stosw
    jmp     .line_done

.dis_xchg_ax_r16:
    mov     dword [esp+12], 1
    mov     al, [ebp]
    call    put_hex_byte

    mov     ecx, 12
    mov     al, SPACE
    rep     stosb

    mov     al, 'X'
    stosb
    mov     al, 'C'
    stosb
    mov     al, 'H'
    stosb
    mov     al, 'G'
    stosb

    mov     ecx, 4
    mov     al, SPACE
    rep     stosb

    mov     ax, 'AX'
    stosw
    mov     al, COMMA
    stosb

    movzx   eax, byte [ebp]
    sub     eax, 90h
    shl     eax, 1
    lea     esi, [op_reg16_names + eax]
    lodsw
    stosw
    jmp     .line_done

.dis_call_far:
    mov     dword [esp+12], 5
    mov     eax, ebp
    sub     eax, memory
    add     eax, 5
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     esi, ebp
    mov     ecx, 5
.dis_cf_hex:
    lodsb
    call    put_hex_byte
    loop    .dis_cf_hex

    mov     ecx, 4
    mov     al, SPACE
    rep     stosb

    mov     eax, 'CALL'
    stosd
    mov     ecx, 4
    mov     al, SPACE
    rep     stosb

    mov     ax, word [ebp+3]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    jmp     .line_done

.dis_jmp_far:
    mov     dword [esp+12], 5
    mov     eax, ebp
    sub     eax, memory
    add     eax, 5
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     esi, ebp
    mov     ecx, 5
.dis_jf_hex:
    lodsb
    call    put_hex_byte
    loop    .dis_jf_hex

    mov     ecx, 4
    mov     al, SPACE
    rep     stosb

    mov     al, 'J'
    stosb
    mov     al, 'M'
    stosb
    mov     al, 'P'
    stosb
    mov     ecx, 5
    mov     al, SPACE
    rep     stosb

    mov     ax, word [ebp+3]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    jmp     .line_done

.dis_out_imm:
    mov     dword [esp+12], 2
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

    mov     al, 'O'
    stosb
    mov     al, 'U'
    stosb
    mov     al, 'T'
    stosb
    mov     ecx, 5
    mov     al, SPACE
    rep     stosb

    mov     al, [ebp+1]
    call    put_hex_byte
    mov     al, COMMA
    stosb
    cmp     byte [ebp], 0E7h
    je      .dis_out_ax
    mov     ax, 'AL'
    stosw
    jmp     .line_done
.dis_out_ax:
    mov     ax, 'AX'
    stosw
    jmp     .line_done

.dis_aam_aad:
    mov     dword [esp+12], 2
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

    cmp     byte [ebp], 0D4h
    jne     .dis_is_aad
    mov     al, 'A'
    stosb
    mov     al, 'A'
    stosb
    mov     al, 'M'
    stosb
    jmp     .dis_aam_ops
.dis_is_aad:
    mov     al, 'A'
    stosb
    mov     al, 'A'
    stosb
    mov     al, 'D'
    stosb
.dis_aam_ops:
    cmp     byte [ebp+1], 0Ah
    je      .line_done
    mov     ecx, 5
    mov     al, SPACE
    rep     stosb
    mov     al, [ebp+1]
    call    put_hex_byte
    jmp     .line_done

op_reg16_names:
    dw 'AX', 'CX', 'DX', 'BX', 'SP', 'BP', 'SI', 'DI'

jcc_names:
    db 'JO ', 0, 'JNO', 0, 'JB ', 0, 'JAE', 0
    db 'JZ ', 0, 'JNZ', 0, 'JBE', 0, 'JA ', 0
    db 'JS ', 0, 'JNS', 0, 'JP ', 0, 'JNP', 0
    db 'JL ', 0, 'JGE', 0, 'JLE', 0, 'JG ', 0


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
    cmp     byte [ebx+1], 2
    ja      .next2
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

mem_mnem_table:
    db 'mov', 0, 1, 0
    db 'add', 0, 0, 0
    db 'or',  0, 0, 1
    db 'adc', 0, 0, 2
    db 'sbb', 0, 0, 3
    db 'and', 0, 0, 4
    db 'sub', 0, 0, 5
    db 'xor', 0, 0, 6
    db 'cmp', 0, 0, 7
    db 'test',0, 2, 0
    db 'mul', 0, 3, 4
    db 'not', 0, 3, 2
    db 'neg', 0, 3, 3
    db 'imul', 0, 3, 5
    db 'div', 0, 3, 6
    db 'idiv', 0, 3, 7
    db 'inc', 0, 4, 0
    db 'dec', 0, 4, 1
    db 'push',0, 4, 6
    db 'pop', 0, 5, 0
    db 0

check_has_bracket:
.scan:
    mov     al, [esi]
    test    al, al
    jz      .no
    cmp     al, CR
    je      .no
    cmp     al, LF
    je      .no
    cmp     al, '['
    je      .yes
    inc     esi
    jmp     .scan
.yes:
    stc
    ret
.no:
    clc
    ret

parse_asm_reg:
    push    ebx
    push    ecx
    push    edx

    mov     ebx, esi
.skip_ws:
    mov     al, [ebx]
    cmp     al, ' '
    je      .inc_ws
    cmp     al, 9
    je      .inc_ws
    jmp     .check_chars
.inc_ws:
    inc     ebx
    jmp     .skip_ws

.check_chars:
    mov     al, [ebx]
    test    al, al
    jz      .fail
    cmp     al, CR
    je      .fail
    cmp     al, LF
    je      .fail
    mov     ah, [ebx+1]
    test    ah, ah
    jz      .fail
    cmp     ah, CR
    je      .fail
    cmp     ah, LF
    je      .fail

    cmp     al, 'A'
    jb      .c1_ok
    cmp     al, 'Z'
    ja      .c1_ok
    add     al, 20h
.c1_ok:
    cmp     ah, 'A'
    jb      .c2_ok
    cmp     ah, 'Z'
    ja      .c2_ok
    add     ah, 20h
.c2_ok:

    mov     dl, [ebx+2]
    cmp     dl, ' '
    je      .delim_ok
    cmp     dl, 9
    je      .delim_ok
    cmp     dl, ','
    je      .delim_ok
    cmp     dl, ']'
    je      .delim_ok
    cmp     dl, '+'
    je      .delim_ok
    cmp     dl, '-'
    je      .delim_ok
    cmp     dl, CR
    je      .delim_ok
    cmp     dl, LF
    je      .delim_ok
    test    dl, dl
    jz      .delim_ok
    jmp     .fail

.delim_ok:
    cmp     al, 'a'
    jne     .not_ax
    cmp     ah, 'x'
    jne     .not_ax
    mov     al, 0
    mov     ah, 2
    jmp     .matched
.not_ax:
    cmp     al, 'c'
    jne     .not_cx
    cmp     ah, 'x'
    jne     .not_cx
    mov     al, 1
    mov     ah, 2
    jmp     .matched
.not_cx:
    cmp     al, 'd'
    jne     .not_dx
    cmp     ah, 'x'
    jne     .not_dx
    mov     al, 2
    mov     ah, 2
    jmp     .matched
.not_dx:
    cmp     al, 'b'
    jne     .not_bx
    cmp     ah, 'x'
    jne     .not_bx
    mov     al, 3
    mov     ah, 2
    jmp     .matched
.not_bx:
    cmp     al, 's'
    jne     .not_sp
    cmp     ah, 'p'
    jne     .not_sp
    mov     al, 4
    mov     ah, 2
    jmp     .matched
.not_sp:
    cmp     al, 'b'
    jne     .not_bp
    cmp     ah, 'p'
    jne     .not_bp
    mov     al, 5
    mov     ah, 2
    jmp     .matched
.not_bp:
    cmp     al, 's'
    jne     .not_si
    cmp     ah, 'i'
    jne     .not_si
    mov     al, 6
    mov     ah, 2
    jmp     .matched
.not_si:
    cmp     al, 'd'
    jne     .not_di
    cmp     ah, 'i'
    jne     .not_di
    mov     al, 7
    mov     ah, 2
    jmp     .matched
.not_di:

    cmp     al, 'a'
    jne     .not_al
    cmp     ah, 'l'
    jne     .not_al
    mov     al, 0
    mov     ah, 1
    jmp     .matched
.not_al:
    cmp     al, 'c'
    jne     .not_cl
    cmp     ah, 'l'
    jne     .not_cl
    mov     al, 1
    mov     ah, 1
    jmp     .matched
.not_cl:
    cmp     al, 'd'
    jne     .not_dl
    cmp     ah, 'l'
    jne     .not_dl
    mov     al, 2
    mov     ah, 1
    jmp     .matched
.not_dl:
    cmp     al, 'b'
    jne     .not_bl
    cmp     ah, 'l'
    jne     .not_bl
    mov     al, 3
    mov     ah, 1
    jmp     .matched
.not_bl:
    cmp     al, 'a'
    jne     .not_ah
    cmp     ah, 'h'
    jne     .not_ah
    mov     al, 4
    mov     ah, 1
    jmp     .matched
.not_ah:
    cmp     al, 'c'
    jne     .not_ch
    cmp     ah, 'h'
    jne     .not_ch
    mov     al, 5
    mov     ah, 1
    jmp     .matched
.not_ch:
    cmp     al, 'd'
    jne     .not_dh
    cmp     ah, 'h'
    jne     .not_dh
    mov     al, 6
    mov     ah, 1
    jmp     .matched
.not_dh:
    cmp     al, 'b'
    jne     .not_bh
    cmp     ah, 'h'
    jne     .not_bh
    mov     al, 7
    mov     ah, 1
    jmp     .matched
.not_bh:

.fail:
    pop     edx
    pop     ecx
    pop     ebx
    stc
    ret

.matched:
    add     ebx, 2
    mov     esi, ebx
    pop     edx
    pop     ecx
    pop     ebx
    clc
    ret

parse_size_prefix:
    push    ebx
    push    ecx
    push    edx

    mov     ebx, esi
.psp_skip_ws:
    mov     al, [ebx]
    cmp     al, ' '
    je      .psp_inc_ws
    cmp     al, 9
    je      .psp_inc_ws
    jmp     .psp_check
.psp_inc_ws:
    inc     ebx
    jmp     .psp_skip_ws

.psp_check:
    mov     al, [ebx]
    or      al, 20h
    cmp     al, 'w'
    jne     .psp_check_byte
    mov     al, [ebx+1]
    or      al, 20h
    cmp     al, 'o'
    jne     .psp_check_byte
    mov     al, [ebx+2]
    or      al, 20h
    cmp     al, 'r'
    jne     .psp_check_byte
    mov     al, [ebx+3]
    or      al, 20h
    cmp     al, 'd'
    jne     .psp_check_byte
    mov     al, [ebx+4]
    cmp     al, ' '
    je      .psp_word_match
    cmp     al, 9
    je      .psp_word_match
    cmp     al, '['
    je      .psp_word_match
    jmp     .psp_fail

.psp_word_match:
    add     ebx, 4
    mov     edx, 2
    jmp     .psp_check_ptr

.psp_check_byte:
    mov     al, [ebx]
    or      al, 20h
    cmp     al, 'b'
    jne     .psp_fail
    mov     al, [ebx+1]
    or      al, 20h
    cmp     al, 'y'
    jne     .psp_fail
    mov     al, [ebx+2]
    or      al, 20h
    cmp     al, 't'
    jne     .psp_fail
    mov     al, [ebx+3]
    or      al, 20h
    cmp     al, 'e'
    jne     .psp_fail
    mov     al, [ebx+4]
    cmp     al, ' '
    je      .psp_byte_match
    cmp     al, 9
    je      .psp_byte_match
    cmp     al, '['
    je      .psp_byte_match
    jmp     .psp_fail

.psp_byte_match:
    add     ebx, 4
    mov     edx, 1

.psp_check_ptr:
.psp_ptr_ws:
    mov     al, [ebx]
    cmp     al, ' '
    je      .psp_ptr_inc
    cmp     al, 9
    je      .psp_ptr_inc
    jmp     .psp_check_ptr_word
.psp_ptr_inc:
    inc     ebx
    jmp     .psp_ptr_ws

.psp_check_ptr_word:
    mov     al, [ebx]
    or      al, 20h
    cmp     al, 'p'
    jne     .psp_done
    mov     al, [ebx+1]
    or      al, 20h
    cmp     al, 't'
    jne     .psp_done
    mov     al, [ebx+2]
    or      al, 20h
    cmp     al, 'r'
    jne     .psp_done
    mov     al, [ebx+3]
    cmp     al, ' '
    je      .psp_skip_ptr_str
    cmp     al, 9
    je      .psp_skip_ptr_str
    cmp     al, '['
    je      .psp_skip_ptr_str
    jmp     .psp_done
.psp_skip_ptr_str:
    add     ebx, 3
.psp_after_ptr_ws:
    mov     al, [ebx]
    cmp     al, ' '
    je      .psp_after_ptr_inc
    cmp     al, 9
    je      .psp_after_ptr_inc
    jmp     .psp_done
.psp_after_ptr_inc:
    inc     ebx
    jmp     .psp_after_ptr_ws

.psp_done:
    mov     esi, ebx
    mov     eax, edx
    pop     edx
    pop     ecx
    pop     ebx
    clc
    ret

.psp_fail:
    pop     edx
    pop     ecx
    pop     ebx
    xor     eax, eax
    stc
    ret

parse_mem_instruction:
    push    ebp
    mov     ebp, esp
    sub     esp, 128

    mov     dword [ebp-4], 0      ; var_type
    mov     dword [ebp-8], 0      ; var_reg
    mov     dword [ebp-12], 2     ; var_size (default word = 2)
    mov     dword [ebp-16], 0     ; var_has_bx
    mov     dword [ebp-20], 0     ; var_has_bp
    mov     dword [ebp-24], 0     ; var_has_si
    mov     dword [ebp-28], 0     ; var_has_di
    mov     dword [ebp-32], 0     ; var_has_disp
    mov     dword [ebp-36], 1     ; var_sign = 1
    mov     dword [ebp-40], 0     ; var_disp = 0
    mov     dword [ebp-44], 0     ; var_mod = 0
    mov     dword [ebp-48], 0     ; var_rm = 0
    mov     dword [ebp-52], 0     ; var_disp_len = 0
    mov     dword [ebp-56], 0     ; var_imm = 0
    mov     dword [ebp-60], 0     ; var_opcode
    mov     dword [ebp-64], 0     ; var_modrm
    mov     dword [ebp-68], 2     ; var_imm_len = 2
    mov     dword [ebp-72], 0     ; var_dir (0=mem dest, 1=reg dest)
    mov     dword [ebp-76], 0     ; var_is_reg_op (0=imm, 1=reg)
    mov     dword [ebp-80], 0     ; var_explicit_size (0=none, 1=byte, 2=word)
    mov     dword [ebp-84], 0     ; var_alu_op (0..7)

    call    skip_whitespace
    lea     edi, [ebp-128]
.read_mnem:
    call    is_eol
    jc      .mem_err
    mov     al, [esi]
    cmp     al, ' '
    je      .mnem_done
    cmp     al, 9
    je      .mnem_done
    cmp     al, '['
    je      .mnem_done
    cmp     al, 'A'
    jb      .mnem_store
    cmp     al, 'Z'
    ja      .mnem_store
    add     al, 20h
.mnem_store:
    stosb
    inc     esi
    lea     eax, [ebp-128+15]
    cmp     edi, eax
    jae     .mem_err
    jmp     .read_mnem
.mnem_done:
    mov     byte [edi], 0

    mov     ebx, mem_mnem_table
.search_mnem:
    cmp     byte [ebx], 0
    je      .mem_err
    lea     edi, [ebp-128]
    mov     edx, ebx
.cmp_mnem:
    mov     al, [edi]
    mov     ah, [edx]
    cmp     al, ah
    jne     .next_mnem
    test    al, al
    jz      .found_mnem
    inc     edi
    inc     edx
    jmp     .cmp_mnem
.next_mnem:
    cmp     byte [ebx], 0
    je      .skip_null
    inc     ebx
    jmp     .next_mnem
.skip_null:
    add     ebx, 3
    jmp     .search_mnem

.found_mnem:
    mov     edx, ebx
.find_mnem_null:
    cmp     byte [edx], 0
    je      .got_mnem_null
    inc     edx
    jmp     .find_mnem_null
.got_mnem_null:
    movzx   eax, byte [edx+1]
    mov     dword [ebp-4], eax   ; var_type
    movzx   eax, byte [edx+2]
    mov     dword [ebp-8], eax   ; var_reg
    mov     dword [ebp-84], eax  ; var_alu_op

    call    skip_whitespace

    ; Check if Operand 1 is a register (e.g. MOV DX, [0200])
    call    parse_asm_reg
    jnc     .op1_is_reg

    ; Operand 1 is MEMORY (e.g. MOV [0200], AX or MOV WORD PTR [BX+8], 0017)
    mov     dword [ebp-72], 0    ; var_dir = 0 (mem is destination)

    call    parse_size_prefix
    jc      .op1_no_size_prefix
    mov     [ebp-12], eax        ; var_size = 1 or 2
    mov     [ebp-80], eax        ; var_explicit_size = 1 or 2
.op1_no_size_prefix:

    call    skip_whitespace
    cmp     byte [esi], '['
    jne     .mem_err

    call    .parse_bracket_content
    jc      .mem_err

    cmp     dword [ebp-4], 3
    jb      .not_unary_mem
    cmp     dword [ebp-4], 5
    je      .unary_mem_pop
    cmp     dword [ebp-4], 4
    jne     .unary_req_size
    cmp     dword [ebp-8], 6     ; PUSH r/m16?
    je      .unary_mem_push
.unary_req_size:
    cmp     dword [ebp-80], 0
    jz      .mem_err
    call    skip_whitespace
    call    is_eol
    jnc     .mem_err
    cmp     dword [ebp-4], 3
    jne     .unary_mem_dec
    mov     dword [ebp-60], 0F6h
    cmp     dword [ebp-12], 2
    jne     .unary_mem_done
    mov     dword [ebp-60], 0F7h
    jmp     .unary_mem_done
.unary_mem_dec:
    mov     dword [ebp-60], 0FEh
    cmp     dword [ebp-12], 2
    jne     .unary_mem_done
    mov     dword [ebp-60], 0FFh
    jmp     .unary_mem_done
.unary_mem_push:
    call    skip_whitespace
    call    is_eol
    jnc     .mem_err
    cmp     dword [ebp-12], 1
    je      .mem_err             ; PUSH BYTE PTR is illegal
    mov     dword [ebp-60], 0FFh
    mov     dword [ebp-12], 2
    jmp     .unary_mem_done
.unary_mem_pop:
    call    skip_whitespace
    call    is_eol
    jnc     .mem_err
    cmp     dword [ebp-12], 1
    je      .mem_err             ; POP BYTE PTR is illegal
    mov     dword [ebp-60], 8Fh
    mov     dword [ebp-8], 0
    mov     dword [ebp-12], 2
.unary_mem_done:
    mov     dword [ebp-68], 0
    jmp     .encode_instruction
.not_unary_mem:

    call    skip_whitespace

    ; Check if Operand 2 is a register
    call    parse_asm_reg
    jc      .op2_is_immediate

    ; Operand 2 IS A REGISTER!
    mov     dword [ebp-76], 1    ; var_is_reg_op = 1
    movzx   edx, al
    mov     dword [ebp-8], edx   ; var_reg = source reg
    movzx   edx, ah              ; edx = reg size (1 or 2)

    cmp     dword [ebp-80], 0
    jz      .op2_deduce_size
    cmp     [ebp-80], edx
    jne     .mem_err
.op2_deduce_size:
    mov     [ebp-12], edx        ; var_size = reg size

    call    skip_whitespace
    call    is_eol
    jnc     .mem_err

    jmp     .encode_instruction

.op2_is_immediate:
    mov     dword [ebp-76], 0    ; var_is_reg_op = 0
    call    parse_hex
    jc      .mem_err
    movzx   eax, ax
    mov     dword [ebp-56], eax  ; var_imm = eax

    call    skip_whitespace
    call    is_eol
    jnc     .mem_err

    jmp     .encode_instruction

.op1_is_reg:
    mov     dword [ebp-72], 1    ; var_dir = 1 (reg is destination)
    movzx   edx, al
    mov     dword [ebp-8], edx   ; var_reg = destination reg
    movzx   edx, ah
    mov     dword [ebp-12], edx  ; var_size = reg size (1 or 2)
    mov     dword [ebp-76], 1    ; var_is_reg_op = 1

    call    skip_whitespace

    call    parse_size_prefix
    jc      .op2_no_size_prefix
    cmp     eax, [ebp-12]
    jne     .mem_err
.op2_no_size_prefix:

    call    skip_whitespace
    cmp     byte [esi], '['
    jne     .mem_err

    call    .parse_bracket_content
    jc      .mem_err

    call    skip_whitespace
    call    is_eol
    jnc     .mem_err

.encode_instruction:
    mov     eax, [ebp-44]        ; var_mod
    shl     al, 6
    mov     edx, [ebp-8]         ; var_reg
    shl     dl, 3
    or      al, dl
    mov     edx, [ebp-48]        ; var_rm
    or      al, dl
    mov     dword [ebp-64], eax  ; var_modrm

    cmp     dword [ebp-4], 3
    jae     .emit_bytes

    cmp     dword [ebp-76], 1
    je      .enc_reg_op

    ; --- IMMEDIATE OPERAND ---
    cmp     dword [ebp-4], 1     ; MOV?
    je      .enc_mov_imm
    cmp     dword [ebp-4], 2     ; TEST?
    je      .enc_test_imm

    ; ALU with immediate
    cmp     dword [ebp-12], 1    ; byte?
    jne     .alu_word_imm
    mov     dword [ebp-60], 80h  ; opcode 80h
    mov     dword [ebp-68], 1    ; imm_len = 1
    jmp     .emit_bytes

.alu_word_imm:
    mov     al, byte [ebp-56]
    movsx   eax, al
    cmp     eax, dword [ebp-56]
    jne     .alu_imm16
    mov     dword [ebp-60], 83h  ; opcode 83h
    mov     dword [ebp-68], 1    ; imm_len = 1
    jmp     .emit_bytes

.alu_imm16:
    mov     dword [ebp-60], 81h  ; opcode 81h
    mov     dword [ebp-68], 2    ; imm_len = 2
    jmp     .emit_bytes

.enc_mov_imm:
    cmp     dword [ebp-12], 1    ; byte?
    jne     .mov_word_imm
    mov     dword [ebp-60], 0C6h ; opcode C6h
    mov     dword [ebp-68], 1
    jmp     .emit_bytes
.mov_word_imm:
    mov     dword [ebp-60], 0C7h ; opcode C7h
    mov     dword [ebp-68], 2
    jmp     .emit_bytes

.enc_test_imm:
    cmp     dword [ebp-12], 1    ; byte?
    jne     .test_word_imm
    mov     dword [ebp-60], 0F6h ; opcode F6h
    mov     dword [ebp-68], 1
    jmp     .emit_bytes
.test_word_imm:
    mov     dword [ebp-60], 0F7h ; opcode F7h
    mov     dword [ebp-68], 2
    jmp     .emit_bytes

    ; --- REGISTER OPERAND ---
.enc_reg_op:
    mov     dword [ebp-68], 0    ; imm_len = 0

    cmp     dword [ebp-4], 1     ; MOV?
    je      .enc_mov_reg
    cmp     dword [ebp-4], 2     ; TEST?
    je      .enc_test_reg

    ; ALU with register
    mov     eax, [ebp-84]        ; var_alu_op
    shl     eax, 3
    cmp     dword [ebp-72], 1
    jne     .alu_reg_mem_dst
    add     eax, 2
.alu_reg_mem_dst:
    cmp     dword [ebp-12], 2
    jne     .alu_reg_set_op
    inc     eax
.alu_reg_set_op:
    mov     dword [ebp-60], eax
    jmp     .emit_bytes

.enc_mov_reg:
    cmp     dword [ebp-72], 1
    je      .mov_reg_dst
    cmp     dword [ebp-12], 1
    je      .mov_rm8_r8
    mov     dword [ebp-60], 89h
    jmp     .emit_bytes
.mov_rm8_r8:
    mov     dword [ebp-60], 88h
    jmp     .emit_bytes

.mov_reg_dst:
    cmp     dword [ebp-12], 1
    je      .mov_r8_rm8
    mov     dword [ebp-60], 8Bh
    jmp     .emit_bytes
.mov_r8_rm8:
    mov     dword [ebp-60], 8Ah
    jmp     .emit_bytes

.enc_test_reg:
    cmp     dword [ebp-12], 1
    je      .test_rm8_r8
    mov     dword [ebp-60], 85h
    jmp     .emit_bytes
.test_rm8_r8:
    mov     dword [ebp-60], 84h
    jmp     .emit_bytes

.emit_bytes:
    mov     edi, asm_bytes
    mov     al, byte [ebp-60]    ; opcode
    stosb
    mov     al, byte [ebp-64]    ; modrm
    stosb

    mov     ecx, [ebp-52]        ; disp_len
    test    ecx, ecx
    jz      .emit_imm_check
    mov     al, byte [ebp-40]
    stosb
    cmp     ecx, 2
    jne     .emit_imm_check
    mov     al, byte [ebp-40+1]
    stosb

.emit_imm_check:
    cmp     dword [ebp-68], 0
    jz      .emit_done
    mov     al, byte [ebp-56]
    stosb
    cmp     dword [ebp-68], 2
    jne     .emit_done
    mov     al, byte [ebp-56+1]
    stosb

.emit_done:
    mov     eax, edi
    sub     eax, asm_bytes
    mov     word [asm_len], ax
    clc
    leave
    ret

.mem_err:
    leave
    stc
    ret

.parse_bracket_content:
    cmp     byte [esi], '['
    jne     .bracket_err
    inc     esi

.bracket_loop:
    call    skip_whitespace
    call    is_eol
    jc      .bracket_err
    mov     al, [esi]
    cmp     al, ']'
    je      .bracket_done

    cmp     al, '+'
    jne     .not_plus
    mov     dword [ebp-36], 1    ; var_sign = 1
    inc     esi
    jmp     .bracket_loop

.not_plus:
    cmp     al, '-'
    jne     .not_minus
    mov     dword [ebp-36], -1   ; var_sign = -1
    inc     esi
    jmp     .bracket_loop

.not_minus:
    mov     al, [esi]
    mov     ah, [esi+1]
    or      al, 20h
    or      ah, 20h
    mov     dl, [esi+2]
    cmp     dl, ' '
    je      .try_reg
    cmp     dl, 9
    je      .try_reg
    cmp     dl, '+'
    je      .try_reg
    cmp     dl, '-'
    je      .try_reg
    cmp     dl, ']'
    je      .try_reg
    jmp     .parse_disp_num

.try_reg:
    cmp     al, 'b'
    jne     .check_reg_bp
    cmp     ah, 'x'
    jne     .check_reg_bp
    cmp     dword [ebp-16], 0
    jne     .bracket_err
    mov     dword [ebp-16], 1    ; var_has_bx = 1
    add     esi, 2
    jmp     .bracket_loop

.check_reg_bp:
    cmp     al, 'b'
    jne     .check_reg_si
    cmp     ah, 'p'
    jne     .check_reg_si
    cmp     dword [ebp-20], 0
    jne     .bracket_err
    mov     dword [ebp-20], 1    ; var_has_bp = 1
    add     esi, 2
    jmp     .bracket_loop

.check_reg_si:
    cmp     al, 's'
    jne     .check_reg_di
    cmp     ah, 'i'
    jne     .check_reg_di
    cmp     dword [ebp-24], 0
    jne     .bracket_err
    mov     dword [ebp-24], 1    ; var_has_si = 1
    add     esi, 2
    jmp     .bracket_loop

.check_reg_di:
    cmp     al, 'd'
    jne     .parse_disp_num
    cmp     ah, 'i'
    jne     .parse_disp_num
    cmp     dword [ebp-28], 0
    jne     .bracket_err
    mov     dword [ebp-28], 1    ; var_has_di = 1
    add     esi, 2
    jmp     .bracket_loop

.parse_disp_num:
    call    parse_hex
    jc      .bracket_err
    movsx   eax, ax
    cmp     dword [ebp-36], -1
    jne     .disp_pos
    neg     eax
.disp_pos:
    add     dword [ebp-40], eax  ; var_disp += eax
    mov     dword [ebp-32], 1    ; var_has_disp = 1
    mov     dword [ebp-36], 1    ; reset var_sign = 1
    jmp     .bracket_loop

.bracket_done:
    inc     esi

    mov     eax, [ebp-16]
    add     eax, [ebp-20]
    cmp     eax, 2
    jae     .bracket_err

    mov     eax, [ebp-24]
    add     eax, [ebp-28]
    cmp     eax, 2
    jae     .bracket_err

    cmp     dword [ebp-16], 1
    jne     .check_bx_di
    cmp     dword [ebp-24], 1
    jne     .check_bx_di
    mov     dword [ebp-48], 0    ; RM = 0
    jmp     .got_rm

.check_bx_di:
    cmp     dword [ebp-16], 1
    jne     .check_bp_si
    cmp     dword [ebp-28], 1
    jne     .check_bp_si
    mov     dword [ebp-48], 1    ; RM = 1
    jmp     .got_rm

.check_bp_si:
    cmp     dword [ebp-20], 1
    jne     .check_bp_di
    cmp     dword [ebp-24], 1
    jne     .check_bp_di
    mov     dword [ebp-48], 2    ; RM = 2
    jmp     .got_rm

.check_bp_di:
    cmp     dword [ebp-20], 1
    jne     .check_si_only
    cmp     dword [ebp-28], 1
    jne     .check_si_only
    mov     dword [ebp-48], 3    ; RM = 3
    jmp     .got_rm

.check_si_only:
    cmp     dword [ebp-24], 1
    jne     .check_di_only
    mov     dword [ebp-48], 4    ; RM = 4
    jmp     .got_rm

.check_di_only:
    cmp     dword [ebp-28], 1
    jne     .check_bp_only
    mov     dword [ebp-48], 5    ; RM = 5
    jmp     .got_rm

.check_bp_only:
    cmp     dword [ebp-20], 1
    jne     .check_bx_only
    mov     dword [ebp-48], 6    ; RM = 6
    jmp     .got_rm

.check_bx_only:
    cmp     dword [ebp-16], 1
    jne     .direct_addr
    mov     dword [ebp-48], 7    ; RM = 7
    jmp     .got_rm

.direct_addr:
    mov     dword [ebp-48], 6    ; RM = 6
    mov     dword [ebp-44], 0    ; Mod = 00b
    mov     dword [ebp-52], 2    ; disp_len = 2
    jmp     .rm_done

.got_rm:
    cmp     dword [ebp-32], 0    ; has_disp?
    jne     .has_some_disp
    cmp     dword [ebp-48], 6    ; BP only?
    jne     .no_disp_zero
    mov     dword [ebp-44], 1    ; Mod = 01b
    mov     dword [ebp-52], 1    ; disp_len = 1
    mov     dword [ebp-40], 0
    jmp     .rm_done

.no_disp_zero:
    mov     dword [ebp-44], 0    ; Mod = 00b
    mov     dword [ebp-52], 0    ; disp_len = 0
    jmp     .rm_done

.has_some_disp:
    cmp     dword [ebp-40], 0
    jne     .check_disp_size
    cmp     dword [ebp-48], 6    ; BP only?
    je      .disp8_case
    mov     dword [ebp-44], 0    ; Mod = 00b
    mov     dword [ebp-52], 0    ; disp_len = 0
    jmp     .rm_done

.check_disp_size:
    mov     al, byte [ebp-40]
    movsx   eax, al
    cmp     eax, dword [ebp-40]
    jne     .disp16_case

.disp8_case:
    mov     dword [ebp-44], 1    ; Mod = 01b
    mov     dword [ebp-52], 1    ; disp_len = 1
    jmp     .rm_done

.disp16_case:
    mov     dword [ebp-44], 2    ; Mod = 10b
    mov     dword [ebp-52], 2    ; disp_len = 2

.rm_done:
    clc
    ret

.bracket_err:
    stc
    ret

parse_instruction:
    call    skip_whitespace
    call    is_eol
    jc      .err

    ; Check for 'db' or 'dw' directive
    mov     al, [esi]
    or      al, 20h
    cmp     al, 'd'
    jne     .not_directive
    mov     ah, [esi+1]
    or      ah, 20h
    cmp     ah, 'b'
    je      .check_db_delim
    cmp     ah, 'w'
    je      .check_dw_delim
    jmp     .not_directive

.check_db_delim:
    mov     al, [esi+2]
    cmp     al, ' '
    je      .parse_db
    cmp     al, 9
    je      .parse_db
    cmp     al, ','
    je      .parse_db
    jmp     .not_directive

.check_dw_delim:
    mov     al, [esi+2]
    cmp     al, ' '
    je      .parse_dw
    cmp     al, 9
    je      .parse_dw
    cmp     al, ','
    je      .parse_dw
    jmp     .not_directive

.parse_db:
    add     esi, 2
    xor     ecx, ecx
    mov     edi, asm_bytes
.db_loop:
    call    skip_whitespace
    call    is_eol
    jc      .db_done
    mov     al, [esi]
    cmp     al, ''''
    je      .db_string
    cmp     al, '"'
    je      .db_string
    call    parse_hex_byte
    jc      .err
    movzx   ecx, cx
    cmp     ecx, ASM_BYTES_SIZE
    jae     .err
    mov     [edi], al
    inc     edi
    inc     ecx
    jmp     .db_loop
.db_string:
    mov     dl, al
    inc     esi
.db_str_loop:
    call    is_eol
    jc      .err
    mov     al, [esi]
    cmp     al, dl
    jne     .db_str_char
    inc     esi
    cmp     byte [esi], dl
    jne     .db_loop
.db_str_char:
    cmp     ecx, ASM_BYTES_SIZE
    jae     .err
    mov     [edi], al
    inc     edi
    inc     ecx
    inc     esi
    jmp     .db_str_loop
.db_done:
    test    ecx, ecx
    jz      .err
    mov     [asm_len], cx
    clc
    ret

.parse_dw:
    add     esi, 2
    xor     ecx, ecx
    mov     edi, asm_bytes
.dw_loop:
    call    skip_whitespace
    call    is_eol
    jc      .dw_done
    call    parse_hex
    jc      .err
    movzx   ecx, cx
    cmp     ecx, ASM_BYTES_SIZE - 2
    ja      .err
    mov     [edi], al
    mov     [edi+1], ah
    add     edi, 2
    add     ecx, 2
    jmp     .dw_loop
.dw_done:
    test    ecx, ecx
    jz      .err
    mov     [asm_len], cx
    clc
    ret

.not_directive:
    push    esi
    call    check_has_bracket
    pop     esi
    jc      parse_mem_instruction

    mov     edi, asm_token
    call    get_token
    
    cmp     byte [asm_token], 0
    je      .err
    
    mov     ebx, asm_1word_table
    call    search_table
    jnc     .found

    mov     ebx, asm_rel8_table
    call    search_table
    jnc     .found_rel8

    ; Check if first token is 'call'
    cmp     dword [asm_token], 'call'
    jne     .not_call_insn
    cmp     byte [asm_token+4], 0
    jne     .not_call_insn

    call    skip_whitespace
    call    is_eol
    jc      .err

    ; Check reg16: call ax, call bx, etc.
    push    esi
    call    parse_asm_reg
    jc      .call_target
    cmp     ah, 2
    jne     .call_target_restore
    push    eax
    call    skip_whitespace
    call    is_eol
    pop     eax
    jnc     .call_target_restore
    add     esp, 4
    mov     byte [asm_bytes], 0FFh
    add     al, 0D0h
    mov     byte [asm_bytes+1], al
    mov     word [asm_len], 2
    clc
    ret

.call_target_restore:
    pop     esi
    jmp     .call_parse_addr

.call_target:
    pop     esi

.call_parse_addr:
    call    parse_hex
    jc      .err
    mov     bx, ax
    call    skip_whitespace
    cmp     byte [esi], ':'
    jne     .call_near

    ; Far call: 9A off seg (5 bytes)
    inc     esi
    call    skip_whitespace
    call    parse_hex
    jc      .err
    push    ax
    call    skip_whitespace
    call    is_eol
    pop     ax
    jnc     .err
    mov     byte [asm_bytes], 9Ah
    mov     [asm_bytes+1], al
    mov     [asm_bytes+2], ah
    mov     [asm_bytes+3], bl
    mov     [asm_bytes+4], bh
    mov     word [asm_len], 5
    clc
    ret

.call_near:
    call    is_eol
    jnc     .err
    mov     ax, bx
    sub     ax, [asm_off]
    sub     ax, 3
    mov     byte [asm_bytes], 0E8h
    mov     [asm_bytes+1], al
    mov     [asm_bytes+2], ah
    mov     word [asm_len], 3
    clc
    ret

.not_call_insn:
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
    jmp     parse_alu_reg_imm

.found_3word:
    pop     edi
    pop     esi
    mov     [asm_bytes], al
    test    ah, ah
    jz      .found_3word_1byte
    mov     [asm_bytes+1], ah
    mov     word [asm_len], 2
    clc
    ret
.found_3word_1byte:
    mov     word [asm_len], 1
    clc
    ret

.found_rel8:
    mov     [asm_bytes], al
    call    skip_whitespace
    call    is_eol
    jc      .err

    cmp     byte [asm_bytes], 0EBh
    jne     .rel8_check_addr

    ; For JMP, check if operand is reg16
    push    esi
    call    parse_asm_reg
    jc      .jmp_not_reg
    cmp     ah, 2
    jne     .jmp_not_reg_restore
    push    eax
    call    skip_whitespace
    call    is_eol
    pop     eax
    jnc     .jmp_not_reg_restore
    add     esp, 4
    mov     byte [asm_bytes], 0FFh
    add     al, 0E0h
    mov     byte [asm_bytes+1], al
    mov     word [asm_len], 2
    clc
    ret

.jmp_not_reg_restore:
    pop     esi
    jmp     .rel8_check_addr

.jmp_not_reg:
    pop     esi

.rel8_check_addr:
    call    parse_hex
    jc      .err
    mov     bx, ax

    call    skip_whitespace
    cmp     byte [esi], ':'
    jne     .rel8_no_colon

    ; Colon is ONLY valid for JMP (0EBh)
    cmp     byte [asm_bytes], 0EBh
    jne     .err

    ; Far jump: EA off seg (5 bytes)
    inc     esi
    call    skip_whitespace
    call    parse_hex
    jc      .err
    push    ax
    call    skip_whitespace
    call    is_eol
    pop     ax
    jnc     .err
    mov     byte [asm_bytes], 0EAh
    mov     [asm_bytes+1], al
    mov     [asm_bytes+2], ah
    mov     [asm_bytes+3], bl
    mov     [asm_bytes+4], bh
    mov     word [asm_len], 5
    clc
    ret

.rel8_no_colon:
    call    is_eol
    jnc     .err

    mov     ax, bx
    sub     ax, [asm_off]
    sub     ax, 2
    movsx   dx, al
    cmp     dx, ax
    jne     .rel8_disp_overflow

    mov     [asm_bytes+1], al
    mov     word [asm_len], 2
    clc
    ret

.rel8_disp_overflow:
    cmp     byte [asm_bytes], 0EBh
    jne     .err

    ; Near jump: E9 disp16 (3 bytes)
    mov     ax, bx
    sub     ax, [asm_off]
    sub     ax, 3
    mov     byte [asm_bytes], 0E9h
    mov     [asm_bytes+1], al
    mov     [asm_bytes+2], ah
    mov     word [asm_len], 3
    clc
    ret

.found:
    mov     [asm_bytes], al
    mov     word [asm_len], INSN_LEN_1
    mov     [asm_arg_size], ah
    
    test    ah, ah
    jnz     .has_args
    call    skip_whitespace
    call    is_eol
    jnc     .check_ret_imm
    clc
    ret

.check_ret_imm:
    cmp     byte [asm_bytes], 0C3h
    je      .do_ret_imm
    cmp     byte [asm_bytes], 0CBh
    je      .do_retf_imm
    jmp     .err

.do_ret_imm:
    mov     byte [asm_bytes], 0C2h
    mov     byte [asm_arg_size], 2
    jmp     .has_immediate

.do_retf_imm:
    mov     byte [asm_bytes], 0CAh
    mov     byte [asm_arg_size], 2
    jmp     .has_immediate

.has_args:
    cmp     ah, 2
    jbe     .has_immediate

    call    skip_whitespace
    call    is_eol
    jnc     .err

    mov     [asm_bytes+1], ah
    mov     word [asm_len], INSN_LEN_2
    clc
    ret

.has_immediate:
    call    skip_whitespace
    cmp     byte [esi], ','
    jne     .no_imm_comma
    inc     esi
    call    skip_whitespace
.no_imm_comma:
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

parse_alu_reg_imm:
    mov     edi, asm_token
.pari_find_space:
    mov     al, [edi]
    test    al, al
    jz      .pari_err
    cmp     al, ' '
    je      .pari_found_space
    inc     edi
    jmp     .pari_find_space

.pari_found_space:
    mov     byte [edi], 0
    inc     edi

    mov     ebx, mem_mnem_table
.pari_search_mnem:
    cmp     byte [ebx], 0
    je      .pari_err
    mov     edx, ebx
    mov     ecx, asm_token
.pari_cmp_mnem:
    mov     al, [ecx]
    mov     ah, [edx]
    cmp     al, ah
    jne     .pari_next_mnem
    test    al, al
    jz      .pari_found_mnem
    inc     ecx
    inc     edx
    jmp     .pari_cmp_mnem

.pari_next_mnem:
    cmp     byte [ebx], 0
    je      .pari_skip_null
    inc     ebx
    jmp     .pari_next_mnem
.pari_skip_null:
    add     ebx, 3
    jmp     .pari_search_mnem

.pari_found_mnem:
    mov     cl, [edx+1]
    cmp     cl, 0
    je      .pari_type_ok
    cmp     cl, 2
    jne     .pari_err
.pari_type_ok:
    mov     ch, [edx+2]

    push    esi
    push    ecx
    mov     esi, edi
    call    parse_asm_reg
    pop     ecx
    pop     esi
    jc      .pari_err

    push    eax
    push    ecx

    call    skip_whitespace
    cmp     byte [esi], ','
    jne     .pari_no_comma
    inc     esi
    call    skip_whitespace
.pari_no_comma:
    call    parse_hex
    pop     ecx
    pop     edx
    jc      .pari_err

    push    ax
    push    edx
    push    ecx
    call    skip_whitespace
    call    is_eol
    pop     ecx
    pop     edx
    pop     bx
    jnc     .pari_err

    movzx   eax, ch
    shl     al, 3
    or      al, 0C0h
    or      al, dl
    mov     byte [asm_bytes+1], al

    cmp     cl, 2
    je      .pari_test

    cmp     dh, 1
    jne     .pari_alu_word

    test    bh, bh
    jnz     .pari_err
    mov     byte [asm_bytes], 80h
    mov     byte [asm_bytes+2], bl
    mov     word [asm_len], 3
    clc
    ret

.pari_alu_word:
    movsx   ax, bl
    cmp     ax, bx
    jne     .pari_alu_imm16

    mov     byte [asm_bytes], 83h
    mov     byte [asm_bytes+2], bl
    mov     word [asm_len], 3
    clc
    ret

.pari_alu_imm16:
    mov     byte [asm_bytes], 81h
    mov     byte [asm_bytes+2], bl
    mov     byte [asm_bytes+3], bh
    mov     word [asm_len], 4
    clc
    ret

.pari_test:
    cmp     dh, 1
    jne     .pari_test_word
    test    bh, bh
    jnz     .pari_err
    mov     byte [asm_bytes], 0F6h
    mov     byte [asm_bytes+2], bl
    mov     word [asm_len], 3
    clc
    ret

.pari_test_word:
    mov     byte [asm_bytes], 0F7h
    mov     byte [asm_bytes+2], bl
    mov     byte [asm_bytes+3], bh
    mov     word [asm_len], 4
    clc
    ret

.pari_err:
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
    jae     .too_many_bp

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
    mov     byte [ctrl_c_flag], 0
    call    step
    cmp     eax, STEP_OK
    je      .run_loop
    cmp     eax, STEP_PROGRAM_END
    je      .program_end
    cmp     eax, STEP_UNKNOWN
    je      .unknown_insn
    jmp     .out_of_bounds

.run_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     .interrupted

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
    cmp     byte [ctrl_c_flag], 0
    jne     .interrupted

    call    step
    cmp     eax, STEP_OK
    je      .run_loop
    cmp     eax, STEP_PROGRAM_END
    je      .program_end
    cmp     eax, STEP_UNKNOWN
    je      .unknown_insn
    jmp     .out_of_bounds

.interrupted:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    invoke  WriteConsoleA, [hStdOut], line_buffer, 2, chars_written, 0
    jmp     cmd_register.show_all

.hit_breakpoint:
    jmp     cmd_register.show_all

.program_end:
    mov     esi, msg_prog_end
    mov     ecx, msg_prog_end_len
    call    print_buffer
    ret

.unknown_insn:
    jmp     cmd_register.show_all

.too_many_bp:
    call    print_bp_error
    ret

.out_of_bounds:
    call    print_error
    ret

cmd_trace:
    mov     word [trace_count], 1
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .start_trace

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
    jc      .start_trace

.parse_count:
    call    parse_hex
    jc      print_error_and_ret
    test    ax, ax
    jz      print_error_and_ret
    mov     [trace_count], ax

    call    skip_whitespace
    call    is_eol
    jnc     print_error_and_ret

.start_trace:
    mov     byte [ctrl_c_flag], 0

.trace_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     .trace_interrupted

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
    mov     esi, msg_prog_end
    mov     ecx, msg_prog_end_len
    call    print_buffer
    ret

.step_unknown:
    jmp     cmd_register.show_all

.trace_interrupted:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    invoke  WriteConsoleA, [hStdOut], line_buffer, 2, chars_written, 0
    jmp     cmd_register.show_all

.step_ok:
    call    cmd_register.show_all
    dec     word [trace_count]
    jnz     .trace_loop
    ret

cmd_proceed:
    mov     word [proceed_count], 1
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .start_proceed

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
    jc      .start_proceed

.parse_count:
    call    parse_hex
    jc      print_error_and_ret
    test    ax, ax
    jz      print_error_and_ret
    mov     [proceed_count], ax

    call    skip_whitespace
    call    is_eol
    jnc     print_error_and_ret

.start_proceed:
    mov     byte [ctrl_c_flag], 0

.proceed_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     .proceed_interrupted

    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    call    calc_linear_addr

    mov     ecx, 1
    call    check_mem_range
    jc      .proceed_out_of_bounds

    lea     esi, [memory + eax]
    mov     edi, esi
    xor     dl, dl

.prefix_loop:
    mov     eax, edi
    sub     eax, memory
    cmp     eax, MEM_SIZE
    jae     .not_step_over

    mov     al, [edi]
    cmp     al, 26h
    je      .is_override
    cmp     al, 2Eh
    je      .is_override
    cmp     al, 36h
    je      .is_override
    cmp     al, 3Eh
    je      .is_override
    cmp     al, 0F0h
    je      .is_override

    cmp     al, 0F2h
    je      .is_rep
    cmp     al, 0F3h
    je      .is_rep
    jmp     .inspect_opcode

.is_override:
    inc     edi
    jmp     .prefix_loop

.is_rep:
    mov     dl, 1
    inc     edi
    jmp     .prefix_loop

.inspect_opcode:
    test    dl, dl
    jz      .not_rep_string

    cmp     al, 0A4h
    jb      .not_step_over
    cmp     al, 0A7h
    jbe     .is_rep_string
    cmp     al, 0AAh
    jb      .not_step_over
    cmp     al, 0AFh
    jbe     .is_rep_string
    jmp     .not_step_over

.is_rep_string:
    lea     ecx, [edi + 1]
    sub     ecx, esi
    jmp     .do_step_over

.not_rep_string:
    cmp     al, 0E8h
    jne     .not_call_near
    lea     ecx, [edi + 3]
    sub     ecx, esi
    jmp     .do_step_over
.not_call_near:

    cmp     al, 9Ah
    jne     .not_call_far
    lea     ecx, [edi + 5]
    sub     ecx, esi
    jmp     .do_step_over
.not_call_far:

    cmp     al, 0FFh
    jne     .not_call_indirect
    mov     eax, edi
    sub     eax, memory
    inc     eax
    cmp     eax, MEM_SIZE
    jae     .not_step_over

    mov     al, [edi + 1]
    mov     ah, al
    shr     ah, 3
    and     ah, 7
    cmp     ah, 2
    je      .is_ff_call
    cmp     ah, 3
    jne     .not_step_over

.is_ff_call:
    mov     dh, al
    shr     dh, 6
    and     dh, 3
    and     al, 7
    cmp     dh, 3
    je      .ff_len_2
    cmp     dh, 1
    je      .ff_len_3
    cmp     dh, 2
    je      .ff_len_4
    cmp     al, 6
    je      .ff_len_4
.ff_len_2:
    lea     ecx, [edi + 2]
    sub     ecx, esi
    jmp     .do_step_over
.ff_len_3:
    lea     ecx, [edi + 3]
    sub     ecx, esi
    jmp     .do_step_over
.ff_len_4:
    lea     ecx, [edi + 4]
    sub     ecx, esi
    jmp     .do_step_over
.not_call_indirect:

    cmp     al, 0CDh
    jne     .not_int_imm
    lea     ecx, [edi + 2]
    sub     ecx, esi
    jmp     .do_step_over
.not_int_imm:

    cmp     al, 0CCh
    jne     .not_int3
    lea     ecx, [edi + 1]
    sub     ecx, esi
    jmp     .do_step_over
.not_int3:

    cmp     al, 0CEh
    jne     .not_into
    lea     ecx, [edi + 1]
    sub     ecx, esi
    jmp     .do_step_over
.not_into:

    cmp     al, 0E0h
    je      .is_loop_insn
    cmp     al, 0E1h
    je      .is_loop_insn
    cmp     al, 0E2h
    je      .is_loop_insn
    cmp     al, 0E3h
    je      .is_loop_insn

    jmp     .not_step_over

.is_loop_insn:
    lea     ecx, [edi + 2]
    sub     ecx, esi
    jmp     .do_step_over

.not_step_over:
    call    step
    cmp     eax, STEP_OK
    je      .proceed_step_ok
    cmp     eax, STEP_PROGRAM_END
    je      .proceed_prog_end
    cmp     eax, STEP_UNKNOWN
    je      .proceed_unknown
    jmp     .proceed_out_of_bounds

.proceed_step_ok:
    call    cmd_register.show_all
    dec     word [proceed_count]
    jnz     .proceed_loop
    ret

.do_step_over:
    mov     ax, [reg_CS]
    mov     [proceed_target_seg], ax
    mov     ax, [reg_IP]
    add     ax, cx
    mov     [proceed_target_off], ax

    call    step
    cmp     eax, STEP_OK
    je      .proceed_step_loop
    cmp     eax, STEP_PROGRAM_END
    je      .proceed_prog_end
    cmp     eax, STEP_UNKNOWN
    je      .proceed_unknown
    jmp     .proceed_out_of_bounds

.proceed_step_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     .proceed_interrupted

    mov     ax, [reg_CS]
    cmp     ax, [proceed_target_seg]
    jne     .proceed_continue_run
    mov     bx, [reg_IP]
    cmp     bx, [proceed_target_off]
    je      .proceed_hit_target

.proceed_continue_run:
    call    step
    cmp     eax, STEP_OK
    je      .proceed_step_loop
    cmp     eax, STEP_PROGRAM_END
    je      .proceed_prog_end
    cmp     eax, STEP_UNKNOWN
    je      .proceed_unknown
    jmp     .proceed_out_of_bounds

.proceed_hit_target:
    call    cmd_register.show_all
    dec     word [proceed_count]
    jnz     .proceed_loop
    ret

.proceed_interrupted:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    invoke  WriteConsoleA, [hStdOut], line_buffer, 2, chars_written, 0
    jmp     cmd_register.show_all

.proceed_prog_end:
    mov     esi, msg_prog_end
    mov     ecx, msg_prog_end_len
    call    print_buffer
    ret

.proceed_unknown:
    jmp     cmd_register.show_all

.proceed_out_of_bounds:
    call    print_error
    ret

update_flags_from_eflags:
    push    eax
    mov     eax, edx
    shr     eax, 11
    and     al, 1
    mov     [flag_states + FLAG_OV], al

    mov     eax, edx
    shr     eax, 7
    and     al, 1
    mov     [flag_states + FLAG_NG], al

    mov     eax, edx
    shr     eax, 6
    and     al, 1
    mov     [flag_states + FLAG_ZR], al

    mov     eax, edx
    shr     eax, 4
    and     al, 1
    mov     [flag_states + FLAG_AC], al

    mov     eax, edx
    shr     eax, 2
    and     al, 1
    mov     [flag_states + FLAG_PE], al

    mov     eax, edx
    and     al, 1
    mov     [flag_states + FLAG_CY], al

    pop     eax
    ret

pack_flags:
    push    ecx
    mov     ax, 0002h
    movzx   ecx, byte [flag_states + FLAG_CY]
    and     ecx, 1
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_PE]
    and     ecx, 1
    shl     ecx, 2
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_AC]
    and     ecx, 1
    shl     ecx, 4
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_ZR]
    and     ecx, 1
    shl     ecx, 6
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_NG]
    and     ecx, 1
    shl     ecx, 7
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_EI]
    and     ecx, 1
    shl     ecx, 9
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_DN]
    and     ecx, 1
    shl     ecx, 10
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_OV]
    and     ecx, 1
    shl     ecx, 11
    or      ax, cx
    pop     ecx
    ret

unpack_flags:
    push    eax
    push    ecx
    mov     cx, ax
    mov     al, cl
    and     al, 1
    mov     [flag_states + FLAG_CY], al
    mov     al, cl
    shr     al, 2
    and     al, 1
    mov     [flag_states + FLAG_PE], al
    mov     al, cl
    shr     al, 4
    and     al, 1
    mov     [flag_states + FLAG_AC], al
    mov     al, cl
    shr     al, 6
    and     al, 1
    mov     [flag_states + FLAG_ZR], al
    mov     al, cl
    shr     al, 7
    and     al, 1
    mov     [flag_states + FLAG_NG], al
    mov     ax, cx
    shr     ax, 9
    and     al, 1
    mov     [flag_states + FLAG_EI], al
    mov     ax, cx
    shr     ax, 10
    and     al, 1
    mov     [flag_states + FLAG_DN], al
    mov     ax, cx
    shr     ax, 11
    and     al, 1
    mov     [flag_states + FLAG_OV], al
    pop     ecx
    pop     eax
    ret

decode_modrm:
    push    ebp
    mov     ebp, esp
    sub     esp, 16

    movzx   eax, bl
    mov     [ebp-4], eax
    mov     eax, [ebp]
    mov     [ebp-16], eax

    mov     eax, [ebp-16]
    movzx   eax, byte [eax+1]

    mov     edx, eax
    shr     edx, 3
    and     edx, 7
    mov     [ebp-8], edx

    cmp     dword [ebp-4], 0
    jz      .reg_byte
    mov     esi, [reg16_ptrs + edx*4]
    jmp     .check_mod
.reg_byte:
    mov     esi, [reg8_ptrs + edx*4]

.check_mod:
    mov     ecx, eax
    shr     ecx, 6
    and     ecx, 3
    cmp     ecx, 3
    jne     .is_mem

    and     eax, 7
    cmp     dword [ebp-4], 0
    jz      .rm_reg_byte
    mov     edi, [reg16_ptrs + eax*4]
    jmp     .rm_reg_done
.rm_reg_byte:
    mov     edi, [reg8_ptrs + eax*4]
.rm_reg_done:
    mov     ecx, 2
    mov     edx, [ebp-8]
    leave
    clc
    ret

.is_mem:
    and     eax, 7
    mov     dword [ebp-12], 0

    cmp     eax, 0
    jne     .not_rm0
    movzx   ebx, word [reg_BX]
    add     bx, word [reg_SI]
    mov     dx, word [reg_DS]
    jmp     .got_base
.not_rm0:
    cmp     eax, 1
    jne     .not_rm1
    movzx   ebx, word [reg_BX]
    add     bx, word [reg_DI]
    mov     dx, word [reg_DS]
    jmp     .got_base
.not_rm1:
    cmp     eax, 2
    jne     .not_rm2
    movzx   ebx, word [reg_BP]
    add     bx, word [reg_SI]
    mov     dx, word [reg_SS]
    jmp     .got_base
.not_rm2:
    cmp     eax, 3
    jne     .not_rm3
    movzx   ebx, word [reg_BP]
    add     bx, word [reg_DI]
    mov     dx, word [reg_SS]
    jmp     .got_base
.not_rm3:
    cmp     eax, 4
    jne     .not_rm4
    movzx   ebx, word [reg_SI]
    mov     dx, word [reg_DS]
    jmp     .got_base
.not_rm4:
    cmp     eax, 5
    jne     .not_rm5
    movzx   ebx, word [reg_DI]
    mov     dx, word [reg_DS]
    jmp     .got_base
.not_rm5:
    cmp     eax, 6
    jne     .not_rm6
    test    ecx, ecx
    jnz     .bp_base
    mov     eax, [ebp-16]
    mov     bx, word [eax+2]
    mov     dx, word [reg_DS]
    mov     dword [ebp-12], 2
    jmp     .disp_done
.bp_base:
    movzx   ebx, word [reg_BP]
    mov     dx, word [reg_SS]
    jmp     .got_base
.not_rm6:
    movzx   ebx, word [reg_BX]
    mov     dx, word [reg_DS]

.got_base:
    test    ecx, ecx
    jz      .disp_zero
    cmp     ecx, 1
    je      .disp_byte
    mov     eax, [ebp-16]
    add     bx, word [eax+2]
    mov     dword [ebp-12], 2
    jmp     .disp_done
.disp_byte:
    mov     eax, [ebp-16]
    movsx   ax, byte [eax+2]
    add     bx, ax
    mov     dword [ebp-12], 1
    jmp     .disp_done
.disp_zero:
    mov     dword [ebp-12], 0

.disp_done:
    mov     [modrm_offset], bx
    cmp     dword [seg_override], 0
    jz      .no_seg_override
    mov     eax, [seg_override]
    mov     dx, [eax]
.no_seg_override:
    mov     ax, dx
    call    calc_linear_addr

    mov     edx, [ebp-4]
    inc     edx
    lea     edi, [eax + edx]
    cmp     edi, MEM_SIZE
    ja      .modrm_err

    lea     edi, [memory + eax]
    mov     ecx, [ebp-12]
    add     ecx, 2
    mov     edx, [ebp-8]
    mov     ebx, [ebp-4]
    leave
    clc
    ret

.modrm_err:
    leave
    stc
    ret

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

exec_one_string_op:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    cmp     al, 0A4h
    je      .op_movsb
    cmp     al, 0A5h
    je      .op_movsw
    cmp     al, 0A6h
    je      .op_cmpsb
    cmp     al, 0A7h
    je      .op_cmpsw
    cmp     al, 0AAh
    je      .op_stosb
    cmp     al, 0ABh
    je      .op_stosw
    cmp     al, 0ACh
    je      .op_lodsb
    cmp     al, 0ADh
    je      .op_lodsw
    cmp     al, 0AEh
    je      .op_scasb
    cmp     al, 0AFh
    je      .op_scasw
    jmp     .fail

.op_movsb:
    mov     ax, [reg_DS]
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    movzx   edx, byte [memory + eax]

    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    mov     byte [memory + eax], dl

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .movsb_dec
    inc     word [reg_SI]
    inc     word [reg_DI]
    jmp     .ok
.movsb_dec:
    dec     word [reg_SI]
    dec     word [reg_DI]
    jmp     .ok

.op_movsw:
    mov     ax, [reg_DS]
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    movzx   edx, word [memory + eax]

    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    mov     word [memory + eax], dx

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .movsw_dec
    add     word [reg_SI], 2
    add     word [reg_DI], 2
    jmp     .ok
.movsw_dec:
    sub     word [reg_SI], 2
    sub     word [reg_DI], 2
    jmp     .ok

.op_cmpsb:
    mov     ax, [reg_DS]
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    movzx   edx, byte [memory + eax]

    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    mov     cl, byte [memory + eax]

    cmp     dl, cl
    pushfd
    pop     edx
    call    update_flags_from_eflags

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .cmpsb_dec
    inc     word [reg_SI]
    inc     word [reg_DI]
    jmp     .ok
.cmpsb_dec:
    dec     word [reg_SI]
    dec     word [reg_DI]
    jmp     .ok

.op_cmpsw:
    mov     ax, [reg_DS]
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    movzx   esi, word [memory + eax]

    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    mov     cx, word [memory + eax]

    cmp     si, cx
    pushfd
    pop     edx
    call    update_flags_from_eflags

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .cmpsw_dec
    add     word [reg_SI], 2
    add     word [reg_DI], 2
    jmp     .ok
.cmpsw_dec:
    sub     word [reg_SI], 2
    sub     word [reg_DI], 2
    jmp     .ok

.op_stosb:
    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    mov     dl, byte [reg_AX]
    mov     byte [memory + eax], dl

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .stosb_dec
    inc     word [reg_DI]
    jmp     .ok
.stosb_dec:
    dec     word [reg_DI]
    jmp     .ok

.op_stosw:
    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    mov     dx, word [reg_AX]
    mov     word [memory + eax], dx

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .stosw_dec
    add     word [reg_DI], 2
    jmp     .ok
.stosw_dec:
    sub     word [reg_DI], 2
    jmp     .ok

.op_lodsb:
    mov     ax, [reg_DS]
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    mov     dl, byte [memory + eax]
    mov     byte [reg_AX], dl

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .lodsb_dec
    inc     word [reg_SI]
    jmp     .ok
.lodsb_dec:
    dec     word [reg_SI]
    jmp     .ok

.op_lodsw:
    mov     ax, [reg_DS]
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    mov     dx, word [memory + eax]
    mov     word [reg_AX], dx

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .lodsw_dec
    add     word [reg_SI], 2
    jmp     .ok
.lodsw_dec:
    sub     word [reg_SI], 2
    jmp     .ok

.op_scasb:
    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    mov     dl, byte [reg_AX]
    cmp     dl, byte [memory + eax]
    pushfd
    pop     edx
    call    update_flags_from_eflags

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .scasb_dec
    inc     word [reg_DI]
    jmp     .ok
.scasb_dec:
    dec     word [reg_DI]
    jmp     .ok

.op_scasw:
    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    mov     dx, word [reg_AX]
    cmp     dx, word [memory + eax]
    pushfd
    pop     edx
    call    update_flags_from_eflags

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .scasw_dec
    add     word [reg_DI], 2
    jmp     .ok
.scasw_dec:
    sub     word [reg_DI], 2
    jmp     .ok

.ok:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    clc
    ret

.fail:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    stc
    ret

step:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp

    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    mov     [step_initial_ip], bx
    mov     dword [seg_override], 0
    mov     dword [prefix_len], 0
    call    calc_linear_addr

    mov     ecx, 1
    call    check_mem_range
    jc      .out_of_bounds

    mov     ebp, memory
    add     ebp, eax

.prefix_loop:
    mov     eax, ebp
    sub     eax, memory
    cmp     eax, MEM_SIZE
    jae     .out_of_bounds

    mov     al, [ebp]
    cmp     al, 26h
    je      .pref_es
    cmp     al, 2Eh
    je      .pref_cs
    cmp     al, 36h
    je      .pref_ss
    cmp     al, 3Eh
    je      .pref_ds
    cmp     al, 0F0h
    je      .pref_lock
    jmp     .prefix_done

.pref_es:
    mov     dword [seg_override], reg_ES
    inc     ebp
    inc     dword [prefix_len]
    jmp     .prefix_loop

.pref_cs:
    mov     dword [seg_override], reg_CS
    inc     ebp
    inc     dword [prefix_len]
    jmp     .prefix_loop

.pref_ss:
    mov     dword [seg_override], reg_SS
    inc     ebp
    inc     dword [prefix_len]
    jmp     .prefix_loop

.pref_ds:
    mov     dword [seg_override], reg_DS
    inc     ebp
    inc     dword [prefix_len]
    jmp     .prefix_loop

.pref_lock:
    inc     ebp
    inc     dword [prefix_len]
    jmp     .prefix_loop

.prefix_done:
    mov     ax, word [prefix_len]
    add     [reg_IP], ax

    movzx   eax, byte [ebp]

    cmp     al, OP_NOP
    jne     .not_nop
    add     word [reg_IP], 1
    jmp     .step_ok
.not_nop:

    cmp     al, 0C3h
    jne     .not_ret
    cmp     word [reg_SP], 0FFEEh
    jae     .step_prog_end
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     cx, word [memory + eax]
    test    cx, cx
    jz      .step_prog_end
    mov     [reg_IP], cx
    add     word [reg_SP], 2
    jmp     .step_ok
.not_ret:

    cmp     al, 0C2h
    jne     .not_ret_imm16
    cmp     word [reg_SP], 0FFEEh
    jae     .step_prog_end
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     cx, word [memory + eax]
    test    cx, cx
    jz      .step_prog_end
    mov     [reg_IP], cx
    add     word [reg_SP], 2
    mov     dx, word [ebp+1]
    add     [reg_SP], dx
    jmp     .step_ok
.not_ret_imm16:

    cmp     al, 0CBh
    jne     .not_retf
    cmp     word [reg_SP], 0FFEEh
    jae     .step_prog_end
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 4
    call    check_mem_range
    jc      .out_of_bounds
    mov     cx, word [memory + eax]
    mov     dx, word [memory + eax + 2]
    test    cx, cx
    jz      .step_prog_end
    mov     [reg_IP], cx
    mov     [reg_CS], dx
    add     word [reg_SP], 4
    jmp     .step_ok
.not_retf:

    cmp     al, 0CAh
    jne     .not_retf_imm16
    cmp     word [reg_SP], 0FFEEh
    jae     .step_prog_end
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 4
    call    check_mem_range
    jc      .out_of_bounds
    mov     cx, word [memory + eax]
    mov     dx, word [memory + eax + 2]
    test    cx, cx
    jz      .step_prog_end
    mov     [reg_IP], cx
    mov     [reg_CS], dx
    add     word [reg_SP], 4
    mov     si, word [ebp+1]
    add     [reg_SP], si
    jmp     .step_ok
.not_retf_imm16:

    cmp     al, 0E8h
    jne     .not_call_near
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, [reg_IP]
    add     dx, 3
    mov     word [memory + eax], dx
    mov     cx, word [ebp+1]
    add     [reg_IP], cx
    add     word [reg_IP], 3
    jmp     .step_ok
.not_call_near:

    cmp     al, 9Ah
    jne     .not_call_far
    sub     word [reg_SP], 4
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 4
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, [reg_IP]
    add     dx, 5
    mov     word [memory + eax], dx
    mov     dx, [reg_CS]
    mov     word [memory + eax + 2], dx
    mov     cx, word [ebp+1]
    mov     dx, word [ebp+3]
    mov     [reg_IP], cx
    mov     [reg_CS], dx
    jmp     .step_ok
.not_call_far:

    cmp     al, 0EAh
    jne     .not_jmp_far
    mov     cx, word [ebp+1]
    mov     dx, word [ebp+3]
    mov     [reg_IP], cx
    mov     [reg_CS], dx
    jmp     .step_ok
.not_jmp_far:

    cmp     al, 0E9h
    jne     .not_jmp_near
    mov     cx, word [ebp+1]
    add     word [reg_IP], 3
    add     [reg_IP], cx
    jmp     .step_ok
.not_jmp_near:

    cmp     al, 0EBh
    jne     .not_jmp_short
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    add     [reg_IP], cx
    jmp     .step_ok
.not_jmp_short:

    cmp     al, 0E0h
    jne     .not_loopnz
    dec     word [reg_CX]
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    cmp     word [reg_CX], 0
    je      .step_ok
    cmp     byte [flag_states + FLAG_ZR], 0
    jne     .step_ok
    add     [reg_IP], cx
    jmp     .step_ok
.not_loopnz:

    cmp     al, 0E1h
    jne     .not_loopz
    dec     word [reg_CX]
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    cmp     word [reg_CX], 0
    je      .step_ok
    cmp     byte [flag_states + FLAG_ZR], 1
    jne     .step_ok
    add     [reg_IP], cx
    jmp     .step_ok
.not_loopz:

    cmp     al, 0E2h
    jne     .not_loop
    dec     word [reg_CX]
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    cmp     word [reg_CX], 0
    je      .step_ok
    add     [reg_IP], cx
    jmp     .step_ok
.not_loop:

    cmp     al, 0E3h
    jne     .not_jcxz
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    cmp     word [reg_CX], 0
    jne     .step_ok
    add     [reg_IP], cx
    jmp     .step_ok
.not_jcxz:

    cmp     al, OP_INT
    jne     .not_int
    mov     al, [ebp+1]
    cmp     al, INT_VECTOR_20
    je      .step_prog_end
    cmp     al, INT_VECTOR_21
    je      .int21
    cmp     al, INT_VECTOR_10
    je      .int10
    cmp     al, INT_VECTOR_16
    je      .int16
    add     word [reg_IP], 2
    jmp     .step_ok

.int21:
    mov     ah, byte [reg_AX+1]
    cmp     ah, 00h
    je      .step_prog_end
    cmp     ah, 01h
    je      .int21_ah01
    cmp     ah, 02h
    je      .int21_ah02
    cmp     ah, 06h
    je      .int21_ah06
    cmp     ah, 07h
    je      .int21_ah07_08
    cmp     ah, 08h
    je      .int21_ah07_08
    cmp     ah, INT21_AH_PRINT_STRING
    je      .int21_ah09
    cmp     ah, INT21_AH_BUFFERED_INPUT
    je      .int21_ah0a
    cmp     ah, 0Bh
    je      .int21_ah0b
    cmp     ah, 25h
    je      .int21_ah25
    cmp     ah, 30h
    je      .int21_ah30
    cmp     ah, 35h
    je      .int21_ah35
    cmp     ah, INT21_AH_EXIT
    je      .step_prog_end
    add     word [reg_IP], 2
    jmp     .step_ok

.int21_ah01:
    call    get_keystroke
    mov     byte [reg_AX], al
    cmp     al, CR
    jne     .int21_01_not_cr
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer
    jmp     .int21_01_done
.int21_01_not_cr:
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
.int21_01_done:
    add     word [reg_IP], 2
    jmp     .step_ok

.int21_ah02:
    mov     al, byte [reg_DX]
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    mov     al, byte [reg_DX]
    mov     byte [reg_AX], al
    add     word [reg_IP], 2
    jmp     .step_ok

.int21_ah06:
    cmp     byte [reg_DX], 0FFh
    jne     .int21_06_out
    call    check_char_available
    test    al, al
    jz      .int21_06_no_char
    mov     byte [kbd_peek_valid], 0
    mov     al, [kbd_peek_char]
    mov     byte [reg_AX], al
    mov     byte [flag_states + FLAG_ZR], 0
    jmp     .int21_06_done
.int21_06_no_char:
    mov     byte [reg_AX], 0
    mov     byte [flag_states + FLAG_ZR], 1
    jmp     .int21_06_done
.int21_06_out:
    mov     al, byte [reg_DX]
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    mov     al, byte [reg_DX]
    mov     byte [reg_AX], al
.int21_06_done:
    add     word [reg_IP], 2
    jmp     .step_ok

.int21_ah07_08:
    call    get_keystroke
    mov     byte [reg_AX], al
    add     word [reg_IP], 2
    jmp     .step_ok

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
    
    mov     ecx, edx
    call    print_buffer

.int21_09_skip:
    add     word [reg_IP], 2
    jmp     .step_ok

.int21_ah0a:
    mov     ax, [reg_DS]
    mov     bx, [reg_DX]
    call    calc_linear_addr

    cmp     eax, MEM_SIZE - 2
    jae     .int21_0a_skip

    mov     edi, memory
    add     edi, eax

    movzx   ecx, byte [edi]
    test    ecx, ecx
    jnz     .int21_0a_have_max
    mov     ecx, 255
    mov     byte [edi], cl
.int21_0a_have_max:

    mov     edx, MEM_SIZE - 3
    sub     edx, eax
    jbe     .int21_0a_skip
    cmp     ecx, edx
    jbe     .int21_0a_len_ok
    mov     ecx, edx
.int21_0a_len_ok:

    mov     dword [int21_old_console_mode], 0
    invoke  GetConsoleMode, [hStdIn], int21_old_console_mode
    test    eax, eax
    jz      .int21_0a_no_setmode
    mov     eax, [int21_old_console_mode]
    or      eax, ENABLE_PROCESSED_INPUT or ENABLE_LINE_INPUT or ENABLE_ECHO_INPUT
    invoke  SetConsoleMode, [hStdIn], eax
.int21_0a_no_setmode:

    mov     dword [int21_chars_read], 0
    invoke  ReadConsoleA, [hStdIn], int21_input_buf, 255, int21_chars_read, 0
    test    eax, eax
    jnz     .int21_0a_read_ok
    ; Pipe fallback for INT 21h AH=0Ah
    xor     ecx, ecx
.int21_0a_pipe_loop:
    cmp     ecx, 254
    jae     .int21_0a_pipe_done
    push    ecx
    lea     eax, [int21_input_buf + ecx]
    invoke  ReadFile, [hStdIn], eax, 1, int21_chars_read, 0
    pop     ecx
    test    eax, eax
    jz      .int21_0a_pipe_done
    cmp     dword [int21_chars_read], 0
    jz      .int21_0a_pipe_done
    mov     al, [int21_input_buf + ecx]
    inc     ecx
    cmp     al, LF
    je      .int21_0a_pipe_done
    jmp     .int21_0a_pipe_loop
.int21_0a_pipe_done:
    mov     [int21_chars_read], ecx
.int21_0a_read_ok:

    cmp     dword [int21_old_console_mode], 0
    jz      .int21_0a_no_restoremode
    invoke  SetConsoleMode, [hStdIn], [int21_old_console_mode]
.int21_0a_no_restoremode:

    cmp     byte [ctrl_c_flag], 0
    jne     .int21_0a_skip

    mov     ebx, [int21_chars_read]
    xor     edx, edx
    mov     esi, int21_input_buf
.int21_0a_count:
    test    ebx, ebx
    jz      .int21_0a_count_done
    mov     al, [esi]
    cmp     al, 13
    je      .int21_0a_count_done
    cmp     al, 10
    je      .int21_0a_count_done
    inc     esi
    inc     edx
    dec     ebx
    jmp     .int21_0a_count
.int21_0a_count_done:

    cmp     edx, ecx
    jbe     .int21_0a_clamp_ok
    mov     edx, ecx
.int21_0a_clamp_ok:

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

.int21_0a_skip:
    add     word [reg_IP], 2
    jmp     .step_ok

.int21_ah0b:
    call    check_char_available
    test    al, al
    jz      .int21_0b_none
    mov     byte [reg_AX], 0FFh
    jmp     .int21_0b_done
.int21_0b_none:
    mov     byte [reg_AX], 00h
.int21_0b_done:
    add     word [reg_IP], 2
    jmp     .step_ok

.int21_ah25:
    movzx   eax, byte [reg_AX]
    shl     eax, 2
    mov     dx, [reg_DX]
    mov     word [memory + eax], dx
    mov     dx, [reg_DS]
    mov     word [memory + eax + 2], dx
    add     word [reg_IP], 2
    jmp     .step_ok

.int21_ah30:
    mov     word [reg_AX], 0002h
    mov     word [reg_BX], 0000h
    mov     word [reg_CX], 0000h
    add     word [reg_IP], 2
    jmp     .step_ok

.int21_ah35:
    movzx   eax, byte [reg_AX]
    shl     eax, 2
    mov     bx, word [memory + eax]
    mov     [reg_BX], bx
    mov     bx, word [memory + eax + 2]
    mov     [reg_ES], bx
    add     word [reg_IP], 2
    jmp     .step_ok

.int10:
    mov     ah, byte [reg_AX+1]
    cmp     ah, 0Eh
    je      .int10_ah0e
    cmp     ah, 02h
    je      .int10_ah02
    add     word [reg_IP], 2
    jmp     .step_ok

.int10_ah0e:
    mov     al, byte [reg_AX]
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    add     word [reg_IP], 2
    jmp     .step_ok

.int10_ah02:
    movzx   eax, byte [reg_DX+1]
    shl     eax, 16
    mov     al, byte [reg_DX]
    invoke  SetConsoleCursorPosition, [hStdOut], eax
    add     word [reg_IP], 2
    jmp     .step_ok

.int16:
    mov     ah, byte [reg_AX+1]
    cmp     ah, 00h
    je      .int16_ah00
    cmp     ah, 01h
    je      .int16_ah01
    add     word [reg_IP], 2
    jmp     .step_ok

.int16_ah00:
    call    get_keystroke
    mov     word [reg_AX], ax
    add     word [reg_IP], 2
    jmp     .step_ok

.int16_ah01:
    call    check_char_available
    test    al, al
    jz      .int16_01_none
    mov     byte [flag_states + FLAG_ZR], 0
    mov     al, [kbd_peek_char]
    mov     ah, [kbd_peek_scan]
    mov     word [reg_AX], ax
    jmp     .int16_01_done
.int16_01_none:
    mov     byte [flag_states + FLAG_ZR], 1
.int16_01_done:
    add     word [reg_IP], 2
    jmp     .step_ok
.not_int:

    cmp     al, 50h
    jb      .not_push_r16
    cmp     al, 57h
    ja      .not_push_r16
    sub     al, 50h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    mov     si, [edi]
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     word [memory + eax], si
    add     word [reg_IP], 1
    jmp     .step_ok
.not_push_r16:

    cmp     al, 58h
    jb      .not_pop_r16
    cmp     al, 5Fh
    ja      .not_pop_r16
    sub     al, 58h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     cx, word [memory + eax]
    mov     [edi], cx
    add     word [reg_SP], 2
    add     word [reg_IP], 1
    jmp     .step_ok
.not_pop_r16:

    ; --- PUSH segment register (06h, 0Eh, 16h, 1Eh) ---
    cmp     al, 06h
    je      .push_es
    cmp     al, 0Eh
    je      .push_cs
    cmp     al, 16h
    je      .push_ss
    cmp     al, 1Eh
    je      .push_ds
    jmp     .not_push_seg
.push_es:
    mov     dx, [reg_ES]
    jmp     .do_push_seg
.push_cs:
    mov     dx, [reg_CS]
    jmp     .do_push_seg
.push_ss:
    mov     dx, [reg_SS]
    jmp     .do_push_seg
.push_ds:
    mov     dx, [reg_DS]
.do_push_seg:
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     word [memory + eax], dx
    add     word [reg_IP], 1
    jmp     .step_ok
.not_push_seg:

    ; --- POP segment register (07h, 17h, 1Fh) ---
    cmp     al, 07h
    je      .pop_es
    cmp     al, 17h
    je      .pop_ss
    cmp     al, 1Fh
    je      .pop_ds
    jmp     .not_pop_seg
.pop_es:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, word [memory + eax]
    mov     [reg_ES], dx
    add     word [reg_SP], 2
    add     word [reg_IP], 1
    jmp     .step_ok
.pop_ss:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, word [memory + eax]
    mov     [reg_SS], dx
    add     word [reg_SP], 2
    add     word [reg_IP], 1
    jmp     .step_ok
.pop_ds:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, word [memory + eax]
    mov     [reg_DS], dx
    add     word [reg_SP], 2
    add     word [reg_IP], 1
    jmp     .step_ok
.not_pop_seg:

    ; --- NOP (90h) and XCHG AX, r16 (91h-97h) ---
    cmp     al, 90h
    jb      .not_xchg_ax_r16
    cmp     al, 97h
    ja      .not_xchg_ax_r16
    sub     al, 90h
    jz      .is_nop
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    mov     ax, [reg_AX]
    xchg    ax, [edi]
    mov     [reg_AX], ax
.is_nop:
    add     word [reg_IP], 1
    jmp     .step_ok
.not_xchg_ax_r16:

    ; --- CBW (98h) and CWD (99h) ---
    cmp     al, 98h
    jne     .not_cbw
    mov     al, byte [reg_AX]
    cbw
    mov     [reg_AX], ax
    add     word [reg_IP], 1
    jmp     .step_ok
.not_cbw:

    cmp     al, 99h
    jne     .not_cwd
    mov     ax, word [reg_AX]
    cwd
    mov     [reg_DX], dx
    add     word [reg_IP], 1
    jmp     .step_ok
.not_cwd:

    ; --- WAIT (9Bh) ---
    cmp     al, 9Bh
    jne     .not_wait
    add     word [reg_IP], 1
    jmp     .step_ok
.not_wait:

    ; --- PUSHF (9Ch), POPF (9Dh), SAHF (9Eh), LAHF (9Fh) ---
    cmp     al, 9Ch
    jne     .not_pushf
    call    pack_flags
    sub     word [reg_SP], 2
    mov     dx, ax
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     word [memory + eax], dx
    add     word [reg_IP], 1
    jmp     .step_ok
.not_pushf:

    cmp     al, 9Dh
    jne     .not_popf
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     ax, word [memory + eax]
    add     word [reg_SP], 2
    call    unpack_flags
    add     word [reg_IP], 1
    jmp     .step_ok
.not_popf:

    cmp     al, 9Eh
    jne     .not_sahf
    mov     al, byte [reg_AX+1]
    mov     cl, al
    and     al, 1
    mov     [flag_states + FLAG_CY], al
    mov     al, cl
    shr     al, 2
    and     al, 1
    mov     [flag_states + FLAG_PE], al
    mov     al, cl
    shr     al, 4
    and     al, 1
    mov     [flag_states + FLAG_AC], al
    mov     al, cl
    shr     al, 6
    and     al, 1
    mov     [flag_states + FLAG_ZR], al
    mov     al, cl
    shr     al, 7
    and     al, 1
    mov     [flag_states + FLAG_NG], al
    add     word [reg_IP], 1
    jmp     .step_ok
.not_sahf:

    cmp     al, 9Fh
    jne     .not_lahf
    call    pack_flags
    mov     byte [reg_AX+1], al
    add     word [reg_IP], 1
    jmp     .step_ok
.not_lahf:

    ; --- XLAT (D7h) ---
    cmp     al, 0D7h
    jne     .not_xlat
    movzx   ebx, byte [reg_AX]
    add     bx, word [reg_BX]
    mov     dx, word [reg_DS]
    cmp     dword [seg_override], 0
    jz      .xlat_no_override
    mov     eax, [seg_override]
    mov     dx, [eax]
.xlat_no_override:
    mov     ax, dx
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .out_of_bounds
    mov     al, byte [memory + eax]
    mov     byte [reg_AX], al
    add     word [reg_IP], 1
    jmp     .step_ok
.not_xlat:

    ; --- DAA (27h), DAS (2Fh), AAA (37h), AAS (3Fh) ---
    cmp     al, 27h
    jne     .not_daa
    call    pack_flags
    mov     ah, al
    sahf
    mov     al, byte [reg_AX]
    daa
    mov     byte [reg_AX], al
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 1
    jmp     .step_ok
.not_daa:

    cmp     al, 2Fh
    jne     .not_das
    call    pack_flags
    mov     ah, al
    sahf
    mov     al, byte [reg_AX]
    das
    mov     byte [reg_AX], al
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 1
    jmp     .step_ok
.not_das:

    cmp     al, 37h
    jne     .not_aaa
    call    pack_flags
    mov     ah, al
    sahf
    mov     al, byte [reg_AX]
    mov     ah, byte [reg_AX+1]
    aaa
    mov     word [reg_AX], ax
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 1
    jmp     .step_ok
.not_aaa:

    cmp     al, 3Fh
    jne     .not_aas
    call    pack_flags
    mov     ah, al
    sahf
    mov     al, byte [reg_AX]
    mov     ah, byte [reg_AX+1]
    aas
    mov     word [reg_AX], ax
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 1
    jmp     .step_ok
.not_aas:

    ; --- AAM (D4h) and AAD (D5h) ---
    cmp     al, 0D4h
    jne     .not_aam
    movzx   ecx, byte [ebp+1]
    test    ecx, ecx
    jz      .unknown_insn
    movzx   eax, byte [reg_AX]
    xor     edx, edx
    div     ecx
    mov     byte [reg_AX+1], al   ; AH = AL / imm8
    mov     byte [reg_AX], dl     ; AL = AL % imm8
    test    dl, dl
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 2
    jmp     .step_ok
.not_aam:

    cmp     al, 0D5h
    jne     .not_aad
    movzx   ecx, byte [ebp+1]
    movzx   eax, byte [reg_AX+1] ; AH
    imul    eax, ecx
    movzx   edx, byte [reg_AX]   ; AL
    add     eax, edx
    and     eax, 0FFh
    mov     byte [reg_AX], al
    mov     byte [reg_AX+1], 0
    test    al, al
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 2
    jmp     .step_ok
.not_aad:

    ; --- SALC (D6h) ---
    cmp     al, 0D6h
    jne     .not_salc
    cmp     byte [flag_states + FLAG_CY], 0
    jz      .salc_nc
    mov     byte [reg_AX], 0FFh
    jmp     .salc_done
.salc_nc:
    mov     byte [reg_AX], 0
.salc_done:
    add     word [reg_IP], 1
    jmp     .step_ok
.not_salc:

    ; --- IN / OUT (E4h..E7h, ECh..EFh) ---
    cmp     al, 0E4h
    jne     .not_in_al_imm
    mov     byte [reg_AX], 0FFh
    add     word [reg_IP], 2
    jmp     .step_ok
.not_in_al_imm:

    cmp     al, 0E5h
    jne     .not_in_ax_imm
    mov     word [reg_AX], 0FFFFh
    add     word [reg_IP], 2
    jmp     .step_ok
.not_in_ax_imm:

    cmp     al, 0E6h
    je      .is_out_imm
    cmp     al, 0E7h
    je      .is_out_imm
    jmp     .not_out_imm
.is_out_imm:
    add     word [reg_IP], 2
    jmp     .step_ok
.not_out_imm:

    cmp     al, 0ECh
    jne     .not_in_al_dx
    mov     byte [reg_AX], 0FFh
    add     word [reg_IP], 1
    jmp     .step_ok
.not_in_al_dx:

    cmp     al, 0EDh
    jne     .not_in_ax_dx
    mov     word [reg_AX], 0FFFFh
    add     word [reg_IP], 1
    jmp     .step_ok
.not_in_ax_dx:

    cmp     al, 0EEh
    je      .is_out_dx
    cmp     al, 0EFh
    je      .is_out_dx
    jmp     .not_out_dx
.is_out_dx:
    add     word [reg_IP], 1
    jmp     .step_ok
.not_out_dx:

    ; --- CLC, STC, CMC, CLD, STD, CLI, STI, HLT ---
    cmp     al, 0F8h
    jne     .not_clc
    mov     byte [flag_states + FLAG_CY], 0
    add     word [reg_IP], 1
    jmp     .step_ok
.not_clc:

    cmp     al, 0F9h
    jne     .not_stc
    mov     byte [flag_states + FLAG_CY], 1
    add     word [reg_IP], 1
    jmp     .step_ok
.not_stc:

    cmp     al, 0F5h
    jne     .not_cmc
    xor     byte [flag_states + FLAG_CY], 1
    add     word [reg_IP], 1
    jmp     .step_ok
.not_cmc:

    cmp     al, 0FCh
    jne     .not_cld
    mov     byte [flag_states + FLAG_DN], 0
    add     word [reg_IP], 1
    jmp     .step_ok
.not_cld:

    cmp     al, 0FDh
    jne     .not_std
    mov     byte [flag_states + FLAG_DN], 1
    add     word [reg_IP], 1
    jmp     .step_ok
.not_std:

    cmp     al, 0FAh
    jne     .not_cli
    mov     byte [flag_states + FLAG_EI], 0
    add     word [reg_IP], 1
    jmp     .step_ok
.not_cli:

    cmp     al, 0FBh
    jne     .not_sti
    mov     byte [flag_states + FLAG_EI], 1
    add     word [reg_IP], 1
    jmp     .step_ok
.not_sti:

    cmp     al, 0F4h
    jne     .not_hlt
    add     word [reg_IP], 1
    jmp     .step_ok
.not_hlt:

    ; --- IRET (CFh), INT 3 (CCh), INTO (CEh) ---
    cmp     al, 0CFh
    jne     .not_iret
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 6
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, word [memory + eax]
    mov     [reg_IP], dx
    mov     dx, word [memory + eax + 2]
    mov     [reg_CS], dx
    mov     ax, word [memory + eax + 4]
    add     word [reg_SP], 6
    call    unpack_flags
    jmp     .step_ok
.not_iret:

    cmp     al, 0CCh
    jne     .not_int3
    add     word [reg_IP], 1
    jmp     .step_ok
.not_int3:

    cmp     al, 0CEh
    jne     .not_into
    add     word [reg_IP], 1
    jmp     .step_ok
.not_into:

    ; --- REP / REPNE string ops (F3h / F2h) ---
    cmp     al, 0F3h
    je      .is_rep_prefix
    cmp     al, 0F2h
    je      .is_rep_prefix
    jmp     .not_rep_string

.is_rep_prefix:
    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     dl, byte [ebp+1]
    cmp     dl, 0A4h
    jb      .unknown_insn
    cmp     dl, 0A7h
    jbe     .rep_prefix_valid
    cmp     dl, 0AAh
    jb      .unknown_insn
    cmp     dl, 0AFh
    ja      .unknown_insn

.rep_prefix_valid:
    mov     dh, byte [ebp]      ; dh = prefix (F3h or F2h), dl = opcode
.rep_loop:
    cmp     word [reg_CX], 0
    je      .rep_done

    mov     al, dl
    call    exec_one_string_op
    jc      .out_of_bounds

    dec     word [reg_CX]

    cmp     dl, 0A6h
    je      .rep_check_zf
    cmp     dl, 0A7h
    je      .rep_check_zf
    cmp     dl, 0AEh
    je      .rep_check_zf
    cmp     dl, 0AFh
    je      .rep_check_zf
    jmp     .rep_loop

.rep_check_zf:
    cmp     dh, 0F3h
    je      .rep_check_repe
    ; REPNE (F2): terminate if ZF == 1
    cmp     byte [flag_states + FLAG_ZR], 0
    jne     .rep_done
    jmp     .rep_loop

.rep_check_repe:
    ; REPE (F3): terminate if ZF == 0
    cmp     byte [flag_states + FLAG_ZR], 0
    je      .rep_done
    jmp     .rep_loop

.rep_done:
    add     word [reg_IP], 2
    jmp     .step_ok
.not_rep_string:

    ; --- Non-prefixed string ops (A4h..A7h, AAh..AFh) ---
    cmp     al, 0A4h
    jb      .not_string_op
    cmp     al, 0A7h
    jbe     .is_single_string_op
    cmp     al, 0AAh
    jb      .not_string_op
    cmp     al, 0AFh
    ja      .not_string_op

.is_single_string_op:
    call    exec_one_string_op
    jc      .out_of_bounds
    add     word [reg_IP], 1
    jmp     .step_ok
.not_string_op:

    cmp     al, 40h
    jb      .not_inc_r16
    cmp     al, 47h
    ja      .not_inc_r16
    sub     al, 40h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    inc     word [edi]
    pushfd
    pop     edx
    mov     cl, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], cl
    add     word [reg_IP], 1
    jmp     .step_ok
.not_inc_r16:

    cmp     al, 48h
    jb      .not_dec_r16
    cmp     al, 4Fh
    ja      .not_dec_r16
    sub     al, 48h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    dec     word [edi]
    pushfd
    pop     edx
    mov     cl, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], cl
    add     word [reg_IP], 1
    jmp     .step_ok
.not_dec_r16:

    cmp     al, 70h
    jb      .not_jcc
    cmp     al, 7Fh
    ja      .not_jcc

    mov     dl, al
    and     dl, 1

    shr     al, 1
    and     al, 7

    cmp     al, 0
    jne     .jcc_1
    mov     dh, [flag_states + FLAG_OV]
    jmp     .jcc_eval_done

.jcc_1:
    cmp     al, 1
    jne     .jcc_2
    mov     dh, [flag_states + FLAG_CY]
    jmp     .jcc_eval_done

.jcc_2:
    cmp     al, 2
    jne     .jcc_3
    mov     dh, [flag_states + FLAG_ZR]
    jmp     .jcc_eval_done

.jcc_3:
    cmp     al, 3
    jne     .jcc_4
    mov     dh, [flag_states + FLAG_CY]
    or      dh, [flag_states + FLAG_ZR]
    jmp     .jcc_eval_done

.jcc_4:
    cmp     al, 4
    jne     .jcc_5
    mov     dh, [flag_states + FLAG_NG]
    jmp     .jcc_eval_done

.jcc_5:
    cmp     al, 5
    jne     .jcc_6
    mov     dh, [flag_states + FLAG_PE]
    jmp     .jcc_eval_done

.jcc_6:
    cmp     al, 6
    jne     .jcc_7
    mov     dh, [flag_states + FLAG_NG]
    cmp     dh, [flag_states + FLAG_OV]
    setne   dh
    jmp     .jcc_eval_done

.jcc_7:
    mov     dh, [flag_states + FLAG_NG]
    cmp     dh, [flag_states + FLAG_OV]
    setne   dh
    or      dh, [flag_states + FLAG_ZR]

.jcc_eval_done:
    xor     dh, dl
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    test    dh, dh
    jz      .step_ok
    add     [reg_IP], cx
    jmp     .step_ok
.not_jcc:

    cmp     al, 0B0h
    jb      .not_mov_r8_imm
    cmp     al, 0B7h
    ja      .not_mov_r8_imm
    sub     al, 0B0h
    movzx   eax, al
    mov     edi, [reg8_ptrs + eax*4]
    mov     dl, [ebp+1]
    mov     [edi], dl
    add     word [reg_IP], 2
    jmp     .step_ok
.not_mov_r8_imm:

    cmp     al, 0B8h
    jb      .not_mov_r16_imm
    cmp     al, 0BFh
    ja      .not_mov_r16_imm
    sub     al, 0B8h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    mov     dx, word [ebp+1]
    mov     [edi], dx
    add     word [reg_IP], 3
    jmp     .step_ok
.not_mov_r16_imm:

    cmp     al, 88h
    jne     .not_mov_rm8_r8
    xor     bl, bl
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [esi]
    mov     [edi], al
    add     [reg_IP], cx
    jmp     .step_ok
.not_mov_rm8_r8:

    cmp     al, 89h
    jne     .not_mov_rm16_r16
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     ax, [esi]
    mov     [edi], ax
    add     [reg_IP], cx
    jmp     .step_ok
.not_mov_rm16_r16:

    cmp     al, 8Ah
    jne     .not_mov_r8_rm8
    xor     bl, bl
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [edi]
    mov     [esi], al
    add     [reg_IP], cx
    jmp     .step_ok
.not_mov_r8_rm8:

    cmp     al, 8Bh
    jne     .not_mov_r16_rm16
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     ax, [edi]
    mov     [esi], ax
    add     [reg_IP], cx
    jmp     .step_ok
.not_mov_r16_rm16:

    cmp     al, 0C6h
    jne     .not_mov_rm8_imm8
    xor     bl, bl
    call    decode_modrm
    jc      .out_of_bounds
    test    edx, edx
    jnz     .unknown_insn
    mov     al, [ebp + ecx]
    mov     [edi], al
    inc     ecx
    add     [reg_IP], cx
    jmp     .step_ok
.not_mov_rm8_imm8:

    cmp     al, 0C7h
    jne     .not_mov_rm16_imm16
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    test    edx, edx
    jnz     .unknown_insn
    mov     ax, word [ebp + ecx]
    mov     [edi], ax
    add     ecx, 2
    add     [reg_IP], cx
    jmp     .step_ok
.not_mov_rm16_imm16:

    cmp     al, 0A0h
    jb      .not_mov_accum_mem
    cmp     al, 0A3h
    ja      .not_mov_accum_mem

    mov     bx, word [ebp+1]
    mov     ax, [reg_DS]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    lea     edi, [memory + eax]

    movzx   eax, byte [ebp]
    cmp     al, 0A0h
    je      .exec_a0
    cmp     al, 0A1h
    je      .exec_a1
    cmp     al, 0A2h
    je      .exec_a2
    mov     ax, word [reg_AX]
    mov     word [edi], ax
    add     word [reg_IP], 3
    jmp     .step_ok

.exec_a0:
    mov     al, byte [edi]
    mov     byte [reg_AX], al
    add     word [reg_IP], 3
    jmp     .step_ok

.exec_a1:
    mov     ax, word [edi]
    mov     word [reg_AX], ax
    add     word [reg_IP], 3
    jmp     .step_ok

.exec_a2:
    mov     al, byte [reg_AX]
    mov     byte [edi], al
    add     word [reg_IP], 3
    jmp     .step_ok

.not_mov_accum_mem:

    ; --- MOV r/m16, Sreg (8Ch) ---
    cmp     al, 8Ch
    jne     .not_mov_rm16_sreg
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     edx, [ebp+1]
    shr     edx, 3
    and     edx, 3
    mov     esi, [sreg_ptrs + edx*4]
    mov     ax, word [esi]
    mov     word [edi], ax
    add     [reg_IP], cx
    jmp     .step_ok
.not_mov_rm16_sreg:

    ; --- MOV Sreg, r/m16 (8Eh) ---
    cmp     al, 8Eh
    jne     .not_mov_sreg_rm16
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     ax, word [edi]
    mov     edx, [ebp+1]
    shr     edx, 3
    and     edx, 3
    mov     esi, [sreg_ptrs + edx*4]
    mov     [esi], ax
    add     [reg_IP], cx
    jmp     .step_ok
.not_mov_sreg_rm16:

    ; --- POP r/m16 (8Fh) ---
    cmp     al, 8Fh
    jne     .not_pop_rm16
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    test    edx, edx
    jnz     .unknown_insn
    push    ecx
    push    edi
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    pop     edi
    pop     ecx
    jc      .out_of_bounds
    mov     dx, word [memory + eax]
    add     word [reg_SP], 2
    mov     word [edi], dx
    add     [reg_IP], cx
    jmp     .step_ok
.not_pop_rm16:

    ; --- XCHG r/m8, r8 (86h) ---
    cmp     al, 86h
    jne     .not_xchg_rm8_r8
    xor     bl, bl
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [esi]
    xchg    al, [edi]
    mov     [esi], al
    add     [reg_IP], cx
    jmp     .step_ok
.not_xchg_rm8_r8:

    ; --- XCHG r/m16, r16 (87h) ---
    cmp     al, 87h
    jne     .not_xchg_rm16_r16
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     ax, [esi]
    xchg    ax, [edi]
    mov     [esi], ax
    add     [reg_IP], cx
    jmp     .step_ok
.not_xchg_rm16_r16:

    ; --- LEA reg16, mem (8Dh) ---
    cmp     al, 8Dh
    jne     .not_lea
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [ebp+1]
    shr     al, 6
    cmp     al, 3
    je      .unknown_insn
    mov     ax, [modrm_offset]
    mov     [esi], ax
    add     [reg_IP], cx
    jmp     .step_ok
.not_lea:

    ; --- LES (C4h) and LDS (C5h) ---
    cmp     al, 0C4h
    je      .is_les
    cmp     al, 0C5h
    je      .is_lds
    jmp     .not_les_lds
.is_les:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [ebp+1]
    shr     al, 6
    cmp     al, 3
    je      .unknown_insn
    push    ecx
    mov     eax, edi
    sub     eax, memory
    mov     ecx, 4
    call    check_mem_range
    pop     ecx
    jc      .out_of_bounds
    mov     ax, word [edi]
    mov     dx, word [edi+2]
    mov     [esi], ax
    mov     [reg_ES], dx
    add     [reg_IP], cx
    jmp     .step_ok
.is_lds:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [ebp+1]
    shr     al, 6
    cmp     al, 3
    je      .unknown_insn
    push    ecx
    mov     eax, edi
    sub     eax, memory
    mov     ecx, 4
    call    check_mem_range
    pop     ecx
    jc      .out_of_bounds
    mov     ax, word [edi]
    mov     dx, word [edi+2]
    mov     [esi], ax
    mov     [reg_DS], dx
    add     [reg_IP], cx
    jmp     .step_ok
.not_les_lds:

    cmp     al, 0D0h
    jb      .not_shift
    cmp     al, 0D3h
    ja      .not_shift

    mov     bl, byte [ebp]
    and     bl, 1
    call    decode_modrm
    jc      .out_of_bounds

    push    ecx

    test    byte [ebp], 2
    jnz     .shift_cl
    mov     cl, 1
    jmp     .shift_count_ok
.shift_cl:
    mov     cl, byte [reg_CX]
    and     cl, 1Fh
.shift_count_ok:

    test    bl, bl
    jz      .shift_byte

    cmp     edx, 0
    je      .sh16_rol
    cmp     edx, 1
    je      .sh16_ror
    cmp     edx, 2
    je      .sh16_rcl
    cmp     edx, 3
    je      .sh16_rcr
    cmp     edx, 4
    je      .sh16_shl
    cmp     edx, 5
    je      .sh16_shr
    cmp     edx, 7
    je      .sh16_sar
    pop     ecx
    jmp     .unknown_insn

.sh16_rol:
    rol     word [edi], cl
    jmp     .shift_flags
.sh16_ror:
    ror     word [edi], cl
    jmp     .shift_flags
.sh16_rcl:
    bt      word [flag_states + FLAG_CY], 0
    rcl     word [edi], cl
    jmp     .shift_flags
.sh16_rcr:
    bt      word [flag_states + FLAG_CY], 0
    rcr     word [edi], cl
    jmp     .shift_flags
.sh16_shl:
    shl     word [edi], cl
    jmp     .shift_flags
.sh16_shr:
    shr     word [edi], cl
    jmp     .shift_flags
.sh16_sar:
    sar     word [edi], cl
    jmp     .shift_flags

.shift_byte:
    cmp     edx, 0
    je      .sh8_rol
    cmp     edx, 1
    je      .sh8_ror
    cmp     edx, 2
    je      .sh8_rcl
    cmp     edx, 3
    je      .sh8_rcr
    cmp     edx, 4
    je      .sh8_shl
    cmp     edx, 5
    je      .sh8_shr
    cmp     edx, 7
    je      .sh8_sar
    pop     ecx
    jmp     .unknown_insn

.sh8_rol:
    rol     byte [edi], cl
    jmp     .shift_flags
.sh8_ror:
    ror     byte [edi], cl
    jmp     .shift_flags
.sh8_rcl:
    bt      word [flag_states + FLAG_CY], 0
    rcl     byte [edi], cl
    jmp     .shift_flags
.sh8_rcr:
    bt      word [flag_states + FLAG_CY], 0
    rcr     byte [edi], cl
    jmp     .shift_flags
.sh8_shl:
    shl     byte [edi], cl
    jmp     .shift_flags
.sh8_shr:
    shr     byte [edi], cl
    jmp     .shift_flags
.sh8_sar:
    sar     byte [edi], cl
    jmp     .shift_flags

.shift_flags:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    pop     ecx
    add     [reg_IP], cx
    jmp     .step_ok
.not_shift:

    cmp     al, 80h
    je      .is_alu_imm
    cmp     al, 81h
    je      .is_alu_imm
    cmp     al, 82h
    je      .is_alu_imm
    cmp     al, 83h
    je      .is_alu_imm
    jmp     .not_alu_imm

.is_alu_imm:
    cmp     byte [ebp], 81h
    je      .alu_imm_w
    cmp     byte [ebp], 83h
    je      .alu_imm_w
    xor     bl, bl
    jmp     .alu_imm_modrm
.alu_imm_w:
    mov     bl, 1
.alu_imm_modrm:
    call    decode_modrm
    jc      .out_of_bounds

    test    bl, bl
    jz      .alu_imm_read_b

    cmp     byte [ebp], 83h
    je      .alu_imm_sign_ext
    mov     ax, word [ebp + ecx]
    add     ecx, 2
    jmp     .alu_imm_exec_w
.alu_imm_sign_ext:
    movsx   ax, byte [ebp + ecx]
    inc     ecx

.alu_imm_exec_w:
    push    ecx
    cmp     edx, 0
    je      .alu_w_add
    cmp     edx, 1
    je      .alu_w_or
    cmp     edx, 2
    je      .alu_w_adc
    cmp     edx, 3
    je      .alu_w_sbb
    cmp     edx, 4
    je      .alu_w_and
    cmp     edx, 5
    je      .alu_w_sub
    cmp     edx, 6
    je      .alu_w_xor
    cmp     edx, 7
    je      .alu_w_cmp
    pop     ecx
    jmp     .unknown_insn

.alu_w_add:
    add     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_or:
    or      word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_adc:
    bt      word [flag_states + FLAG_CY], 0
    adc     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_sbb:
    bt      word [flag_states + FLAG_CY], 0
    sbb     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_and:
    and     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_sub:
    sub     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_xor:
    xor     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_cmp:
    cmp     word [edi], ax
    jmp     .alu_imm_w_done

.alu_imm_w_done:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    pop     ecx
    add     [reg_IP], cx
    jmp     .step_ok

.alu_imm_read_b:
    mov     al, byte [ebp + ecx]
    inc     ecx
    push    ecx
    cmp     edx, 0
    je      .alu_b_add
    cmp     edx, 1
    je      .alu_b_or
    cmp     edx, 2
    je      .alu_b_adc
    cmp     edx, 3
    je      .alu_b_sbb
    cmp     edx, 4
    je      .alu_b_and
    cmp     edx, 5
    je      .alu_b_sub
    cmp     edx, 6
    je      .alu_b_xor
    cmp     edx, 7
    je      .alu_b_cmp
    pop     ecx
    jmp     .unknown_insn

.alu_b_add:
    add     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_or:
    or      byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_adc:
    bt      word [flag_states + FLAG_CY], 0
    adc     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_sbb:
    bt      word [flag_states + FLAG_CY], 0
    sbb     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_and:
    and     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_sub:
    sub     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_xor:
    xor     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_cmp:
    cmp     byte [edi], al
    jmp     .alu_imm_b_done

.alu_imm_b_done:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    pop     ecx
    add     [reg_IP], cx
    jmp     .step_ok
.not_alu_imm:

    cmp     al, 3Bh
    jbe     .is_reg_alu
    cmp     al, 84h
    je      .is_test_reg
    cmp     al, 85h
    je      .is_test_reg
    jmp     .not_reg_alu

.is_test_reg:
    and     al, 1
    mov     bl, al
    call    decode_modrm
    jc      .out_of_bounds
    test    bl, bl
    jz      .test_b
    mov     ax, word [esi]
    test    word [edi], ax
    jmp     .test_flags
.test_b:
    mov     al, byte [esi]
    test    byte [edi], al
.test_flags:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok

.is_reg_alu:
    mov     al, byte [ebp]
    and     al, 7
    cmp     al, 3
    ja      .not_reg_alu

    mov     bl, byte [ebp]
    and     bl, 1
    call    decode_modrm
    jc      .out_of_bounds

    mov     dl, byte [ebp]
    shr     dl, 3
    test    byte [ebp], 2
    jz      .dir_rm_dst
    xchg    esi, edi

.dir_rm_dst:
    push    ecx
    movzx   edx, dl
    test    bl, bl
    jz      .reg_alu_byte

    mov     ax, word [esi]
    cmp     edx, 0
    je      .alu_w_add
    cmp     edx, 1
    je      .alu_w_or
    cmp     edx, 2
    je      .alu_w_adc
    cmp     edx, 3
    je      .alu_w_sbb
    cmp     edx, 4
    je      .alu_w_and
    cmp     edx, 5
    je      .alu_w_sub
    cmp     edx, 6
    je      .alu_w_xor
    cmp     edx, 7
    je      .alu_w_cmp
    pop     ecx
    jmp     .unknown_insn

.reg_alu_byte:
    mov     al, byte [esi]
    cmp     edx, 0
    je      .alu_b_add
    cmp     edx, 1
    je      .alu_b_or
    cmp     edx, 2
    je      .alu_b_adc
    cmp     edx, 3
    je      .alu_b_sbb
    cmp     edx, 4
    je      .alu_b_and
    cmp     edx, 5
    je      .alu_b_sub
    cmp     edx, 6
    je      .alu_b_xor
    cmp     edx, 7
    je      .alu_b_cmp
    pop     ecx
    jmp     .unknown_insn
.not_reg_alu:

    cmp     al, 05h
    je      .ax_imm_add
    cmp     al, 0Dh
    je      .ax_imm_or
    cmp     al, 15h
    je      .ax_imm_adc
    cmp     al, 1Dh
    je      .ax_imm_sbb
    cmp     al, 25h
    je      .ax_imm_and
    cmp     al, 2Dh
    je      .ax_imm_sub
    cmp     al, 35h
    je      .ax_imm_xor
    cmp     al, 3Dh
    je      .ax_imm_cmp
    cmp     al, 0A9h
    je      .ax_imm_test

    cmp     al, 04h
    je      .al_imm_add
    cmp     al, 0Ch
    je      .al_imm_or
    cmp     al, 14h
    je      .al_imm_adc
    cmp     al, 1Ch
    je      .al_imm_sbb
    cmp     al, 24h
    je      .al_imm_and
    cmp     al, 2Ch
    je      .al_imm_sub
    cmp     al, 34h
    je      .al_imm_xor
    cmp     al, 3Ch
    je      .al_imm_cmp
    cmp     al, 0A8h
    je      .al_imm_test
    jmp     .not_ax_imm

.ax_imm_add:
    mov     ax, word [ebp+1]
    add     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_or:
    mov     ax, word [ebp+1]
    or      word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_adc:
    bt      word [flag_states + FLAG_CY], 0
    mov     ax, word [ebp+1]
    adc     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_sbb:
    bt      word [flag_states + FLAG_CY], 0
    mov     ax, word [ebp+1]
    sbb     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_and:
    mov     ax, word [ebp+1]
    and     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_sub:
    mov     ax, word [ebp+1]
    sub     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_xor:
    mov     ax, word [ebp+1]
    xor     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_cmp:
    mov     ax, word [ebp+1]
    cmp     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_test:
    mov     ax, word [ebp+1]
    test    word [reg_AX], ax
    jmp     .ax_imm_flags

.ax_imm_flags:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 3
    jmp     .step_ok

.al_imm_add:
    mov     al, byte [ebp+1]
    add     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_or:
    mov     al, byte [ebp+1]
    or      byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_adc:
    bt      word [flag_states + FLAG_CY], 0
    mov     al, byte [ebp+1]
    adc     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_sbb:
    bt      word [flag_states + FLAG_CY], 0
    mov     al, byte [ebp+1]
    sbb     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_and:
    mov     al, byte [ebp+1]
    and     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_sub:
    mov     al, byte [ebp+1]
    sub     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_xor:
    mov     al, byte [ebp+1]
    xor     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_cmp:
    mov     al, byte [ebp+1]
    cmp     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_test:
    mov     al, byte [ebp+1]
    test    byte [reg_AX], al
    jmp     .al_imm_flags

.al_imm_flags:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 2
    jmp     .step_ok
.not_ax_imm:

    cmp     al, 0F6h
    je      .is_f6_f7
    cmp     al, 0F7h
    je      .is_f6_f7
    jmp     .not_f6_f7

.is_f6_f7:
    mov     ah, al
    and     al, 1
    mov     bl, al
    call    decode_modrm
    jc      .out_of_bounds

    cmp     edx, 0
    je      .f67_test
    cmp     edx, 2
    je      .f67_not
    cmp     edx, 3
    je      .f67_neg
    cmp     edx, 4
    je      .f67_mul
    cmp     edx, 5
    je      .f67_imul
    cmp     edx, 6
    je      .f67_div
    cmp     edx, 7
    je      .f67_idiv
    jmp     .unknown_insn

.f67_test:
    test    bl, bl
    jz      .f6_test_b
    mov     ax, word [ebp + ecx]
    add     ecx, 2
    test    word [edi], ax
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok
.f6_test_b:
    mov     al, byte [ebp + ecx]
    inc     ecx
    test    byte [edi], al
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok

.f67_not:
    test    bl, bl
    jz      .f6_not_b
    not     word [edi]
    add     [reg_IP], cx
    jmp     .step_ok
.f6_not_b:
    not     byte [edi]
    add     [reg_IP], cx
    jmp     .step_ok

.f67_neg:
    test    bl, bl
    jz      .f6_neg_b
    neg     word [edi]
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok
.f6_neg_b:
    neg     byte [edi]
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok

.f67_mul:
    test    bl, bl
    jz      .f6_mul_b
    mov     ax, word [reg_AX]
    mul     word [edi]
    mov     word [reg_AX], ax
    mov     word [reg_DX], dx
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok
.f6_mul_b:
    mov     al, byte [reg_AX]
    mul     byte [edi]
    mov     word [reg_AX], ax
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok

.f67_imul:
    test    bl, bl
    jz      .f6_imul_b
    mov     ax, word [reg_AX]
    imul    word [edi]
    mov     word [reg_AX], ax
    mov     word [reg_DX], dx
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok
.f6_imul_b:
    mov     al, byte [reg_AX]
    imul    byte [edi]
    mov     word [reg_AX], ax
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok

.f67_div:
    test    bl, bl
    jz      .f6_div_b
    movzx   ebx, word [edi]
    test    ebx, ebx
    jz      .unknown_insn
    movzx   eax, word [reg_AX]
    movzx   edx, word [reg_DX]
    shl     edx, 16
    or      eax, edx
    xor     edx, edx
    div     ebx
    cmp     eax, 0FFFFh
    ja      .unknown_insn
    mov     word [reg_AX], ax
    mov     word [reg_DX], dx
    add     [reg_IP], cx
    jmp     .step_ok
.f6_div_b:
    movzx   ebx, byte [edi]
    test    ebx, ebx
    jz      .unknown_insn
    movzx   eax, word [reg_AX]
    xor     edx, edx
    div     ebx
    cmp     eax, 0FFh
    ja      .unknown_insn
    mov     byte [reg_AX], al
    mov     byte [reg_AX+1], dl
    add     [reg_IP], cx
    jmp     .step_ok

.f67_idiv:
    test    bl, bl
    jz      .f6_idiv_b
    movsx   ebx, word [edi]
    test    ebx, ebx
    jz      .unknown_insn
    movzx   eax, word [reg_AX]
    movzx   edx, word [reg_DX]
    shl     edx, 16
    or      eax, edx
    cdq
    idiv    ebx
    cmp     eax, -32768
    jl      .unknown_insn
    cmp     eax, 32767
    jg      .unknown_insn
    mov     word [reg_AX], ax
    mov     word [reg_DX], dx
    add     [reg_IP], cx
    jmp     .step_ok
.f6_idiv_b:
    movsx   ebx, byte [edi]
    test    ebx, ebx
    jz      .unknown_insn
    movsx   eax, word [reg_AX]
    cdq
    idiv    ebx
    cmp     eax, -128
    jl      .unknown_insn
    cmp     eax, 127
    jg      .unknown_insn
    mov     byte [reg_AX], al
    mov     byte [reg_AX+1], dl
    add     [reg_IP], cx
    jmp     .step_ok

.not_f6_f7:

    cmp     al, 0FEh
    je      .is_fe_ff
    cmp     al, 0FFh
    je      .is_fe_ff
    jmp     .not_fe_ff

.is_fe_ff:
    mov     ah, al
    and     al, 1
    mov     bl, al
    call    decode_modrm
    jc      .out_of_bounds
    test    edx, edx
    jz      .fe_ff_inc
    cmp     edx, 1
    je      .fe_ff_dec
    cmp     edx, 2
    je      .ff_call_near
    cmp     edx, 3
    je      .ff_call_far
    cmp     edx, 4
    je      .ff_jmp_near
    cmp     edx, 5
    je      .ff_jmp_far
    cmp     edx, 6
    je      .ff_push
    jmp     .unknown_insn

.fe_ff_dec:
    test    byte [ebp], 1
    jz      .fe_dec_b
    dec     word [edi]
    pushfd
    pop     edx
    mov     cl, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], cl
    add     [reg_IP], cx
    jmp     .step_ok
.fe_dec_b:
    dec     byte [edi]
    pushfd
    pop     edx
    mov     cl, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], cl
    add     [reg_IP], cx
    jmp     .step_ok

.fe_ff_inc:
    test    byte [ebp], 1
    jz      .fe_inc_b
    inc     word [edi]
    pushfd
    pop     edx
    mov     cl, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], cl
    add     [reg_IP], cx
    jmp     .step_ok
.fe_inc_b:
    inc     byte [edi]
    pushfd
    pop     edx
    mov     cl, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], cl
    add     [reg_IP], cx
    jmp     .step_ok

.ff_call_near:
    test    byte [ebp], 1
    jz      .unknown_insn
    mov     si, word [edi]
    mov     dx, [reg_IP]
    add     dx, cx
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    push    ecx
    mov     ecx, 2
    call    check_mem_range
    pop     ecx
    jc      .out_of_bounds
    mov     word [memory + eax], dx
    mov     [reg_IP], si
    jmp     .step_ok

.ff_call_far:
    test    byte [ebp], 1
    jz      .unknown_insn
    cmp     byte [ebp+1], 0C0h
    jae     .unknown_insn
    mov     si, word [edi]
    mov     dx, [reg_IP]
    add     dx, cx
    sub     word [reg_SP], 4
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    push    ecx
    mov     ecx, 4
    call    check_mem_range
    pop     ecx
    jc      .out_of_bounds
    mov     word [memory + eax], dx
    mov     dx, [reg_CS]
    mov     word [memory + eax+2], dx
    mov     dx, word [edi+2]
    mov     [reg_IP], si
    mov     [reg_CS], dx
    jmp     .step_ok

.ff_jmp_near:
    test    byte [ebp], 1
    jz      .unknown_insn
    mov     si, word [edi]
    mov     [reg_IP], si
    jmp     .step_ok

.ff_jmp_far:
    test    byte [ebp], 1
    jz      .unknown_insn
    cmp     byte [ebp+1], 0C0h
    jae     .unknown_insn
    mov     si, word [edi]
    mov     dx, word [edi+2]
    mov     [reg_IP], si
    mov     [reg_CS], dx
    jmp     .step_ok

.ff_push:
    test    byte [ebp], 1
    jz      .unknown_insn
    mov     si, word [edi]
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    push    ecx
    mov     ecx, 2
    call    check_mem_range
    pop     ecx
    jc      .out_of_bounds
    mov     word [memory + eax], si
    add     [reg_IP], cx
    jmp     .step_ok
.not_fe_ff:

.unknown_insn:
    mov     dword [seg_override], 0
    mov     ax, [step_initial_ip]
    mov     [reg_IP], ax
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     eax, STEP_UNKNOWN
    ret

.out_of_bounds:
    mov     dword [seg_override], 0
    mov     ax, [step_initial_ip]
    mov     [reg_IP], ax
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     eax, STEP_ERROR
    ret

.step_prog_end:
    mov     dword [seg_override], 0
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     eax, STEP_PROGRAM_END
    ret

.step_ok:
    mov     dword [seg_override], 0
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     eax, STEP_OK
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

    mov     edx, edi
    sub     edx, line_buffer
    push    edx
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0
    test    eax, eax
    jnz     .pr_ret
    mov     edx, [esp]
    invoke  WriteFile, [hStdOut], line_buffer, edx, chars_written, 0
.pr_ret:
    pop     edx

    pop     ecx
    pop     ebx
    pop     edi
    pop     esi
    ret

section '.data' data readable writeable
    ctrl_c_flag     db 0

section '.idata' import data readable writeable
    library kernel32, 'KERNEL32.DLL'

    import kernel32,\
           ExitProcess,           'ExitProcess',\
           GetStdHandle,          'GetStdHandle',\
           WriteConsoleA,         'WriteConsoleA',\
           ReadConsoleA,          'ReadConsoleA',\
           SetConsoleOutputCP,    'SetConsoleOutputCP',\
           GetConsoleMode,        'GetConsoleMode',\
           SetConsoleMode,        'SetConsoleMode',\
           SetConsoleCtrlHandler, 'SetConsoleCtrlHandler',\
           GetCommandLineA,       'GetCommandLineA',\
           CreateFileA,           'CreateFileA',\
           ReadFile,              'ReadFile',\
           WriteFile,             'WriteFile',\
           CloseHandle,           'CloseHandle',\
           GetFileSize,           'GetFileSize',\
           SetConsoleCursorPosition, 'SetConsoleCursorPosition',\
           PeekConsoleInputA,     'PeekConsoleInputA',\
           ReadConsoleInputA,     'ReadConsoleInputA',\
           PeekNamedPipe,         'PeekNamedPipe',\
           Sleep,                 'Sleep'
