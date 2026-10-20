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
    mov     word [reg_SP], 0FFEEh
    mov     word [reg_BP], 0000h
    mov     word [reg_SI], 0000h
    mov     word [reg_DI], 0000h
    mov     word [reg_DX], 0000h

    ; Initialize stack return address: [SS:SP] = 0000h
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    cmp     eax, MEM_SIZE - 2
    jae     .skip_stack_ret
    mov     word [memory + eax], 0000h
.skip_stack_ret:

    ; Reset flags: NV UP EI PL NZ NA PO NC (EI=1, all other flags=0)
    mov     byte [flag_states + FLAG_OV], 0
    mov     byte [flag_states + FLAG_DN], 0
    mov     byte [flag_states + FLAG_EI], 1
    mov     byte [flag_states + FLAG_NG], 0
    mov     byte [flag_states + FLAG_ZR], 0
    mov     byte [flag_states + FLAG_AC], 0
    mov     byte [flag_states + FLAG_PE], 0
    mov     byte [flag_states + FLAG_CY], 0

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

    call    print_line_buffer
    ret

.err_write_close:
    invoke  CloseHandle, [file_handle]
.err_create:
    mov     esi, msg_file_create_err
    mov     ecx, msg_file_create_err_len
    call    print_buffer
    ret


