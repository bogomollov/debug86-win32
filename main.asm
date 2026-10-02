format PE CONSOLE

entry start

include 'fasm/include/win32a.inc'

include 'data.asm'
include 'hex.asm'
include 'dump.asm'

start:
    invoke  GetStdHandle, STD_OUTPUT_HANDLE
    mov     [hStdOut], eax

    invoke  GetStdHandle, STD_INPUT_HANDLE
    mov     [hStdIn], eax

    mov     ecx, 65536
    mov     edi, memory
    xor     eax, eax
.init_mem:
    mov     [edi], al
    inc     edi
    inc     al
    loop    .init_mem

main_loop:
    invoke  WriteConsoleA, [hStdOut], prompt, 1, chars_written, 0

    invoke  ReadConsoleA, [hStdIn], input_buffer, 255, chars_read, 0

.check_d:
    mov     al, [input_buffer]
    or      al, 20h
    mov     esi, COMTAB
.find_cmd:
    mov     bl, [esi]
    test    bl, bl
    jz      main_loop
    cmp     bl, al
    je      .exec_cmd
    add     esi, 5
    jmp     .find_cmd
.exec_cmd:
    mov     bl, [input_buffer + 1]
    cmp     bl, ' '
    je      .run_cmd
    cmp     bl, 9
    je      .run_cmd
    cmp     bl, 13
    je      .run_cmd
    cmp     bl, 10
    je      .run_cmd
    test    bl, bl
    jz      .run_cmd
    jmp     main_loop
.run_cmd:
    mov     eax, [esi+1]
    call    eax
    jmp     main_loop

cmd_quit:
    mov     ecx, [chars_read]
    cmp     ecx, 1
    jbe     exit_program

    mov     esi, input_buffer + 1
    dec     ecx
.q_skip:
    mov     al, [esi]
    cmp     al, ' '
    je      .q_next
    cmp     al, 9
    je      .q_next
    cmp     al, 13
    je      .q_next
    cmp     al, 10
    je      .q_next
    ret

.q_next:
    inc     esi
    dec     ecx
    jnz     .q_skip
    jmp     exit_program

cmd_dump:
    mov     word [dump_len], 128

    mov     esi, input_buffer
    inc     esi

.skip_ws1:
    mov     al, [esi]
    cmp     al, ' '
    je      .adv1
    cmp     al, 9
    je      .adv1
    jmp     .check_arg
.adv1:
    inc     esi
    jmp     .skip_ws1

.check_arg:
    cmp     al, 13
    je      .do_it
    cmp     al, 10
    je      .do_it
    cmp     al, 'l'
    je      .parse_len_only
    cmp     al, 'L'
    je      .parse_len_only

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
    jmp     .not_seg

.seg_ds:
    mov     ax, [reg_DS]
    jmp     .try_seg
.seg_cs:
    mov     ax, [reg_CS]
    jmp     .try_seg
.seg_es:
    mov     ax, [reg_ES]
    jmp     .try_seg
.seg_ss:
    mov     ax, [reg_SS]

.try_seg:
    mov     bl, [esi+1]
    or      bl, 20h
    cmp     bl, 's'
    jne     .not_seg
    cmp     byte [esi+2], ':'
    jne     .not_seg

    mov     [dump_seg], ax
    add     esi, 3

.skip_ws_seg:
    mov     al, [esi]
    cmp     al, ' '
    je      .adv_seg
    cmp     al, 9
    je      .adv_seg
    jmp     .parse_off_seg
.adv_seg:
    inc     esi
    jmp     .skip_ws_seg

.parse_off_seg:
    call    parse_hex
    jc      .after_addr
    mov     [dump_off], ax
    jmp     .after_addr

.not_seg:
    call    parse_hex
    jc      .do_it
    mov     bx, ax

.skip_ws2:
    mov     al, [esi]
    cmp     al, ' '
    je      .adv2
    cmp     al, 9
    je      .adv2
    jmp     .check_colon
.adv2:
    inc     esi
    jmp     .skip_ws2

.check_colon:
    cmp     al, ':'
    jne     .set_offset

    inc     esi

.skip_ws3:
    mov     al, [esi]
    cmp     al, ' '
    je      .adv3
    cmp     al, 9
    je      .adv3
    jmp     .parse_off
.adv3:
    inc     esi
    jmp     .skip_ws3

.parse_off:
    call    parse_hex
    jc      .set_offset
    mov     [dump_seg], bx
    mov     [dump_off], ax
    jmp     .after_addr

.set_offset:
    mov     ax, [reg_DS]
    mov     [dump_seg], ax
    mov     [dump_off], bx
    jmp     .after_addr

.after_addr:
.skip_ws4:
    mov     al, [esi]
    cmp     al, ' '
    je      .adv4
    cmp     al, 9
    je      .adv4
    jmp     .check_len
.adv4:
    inc     esi
    jmp     .skip_ws4

.check_len:
    cmp     al, 'l'
    je      .parse_len
    cmp     al, 'L'
    je      .parse_len

    mov     bl, al
    or      bl, 20h
    cmp     bl, '0'
    jb      .do_it
    cmp     bl, '9'
    jbe     .parse_end
    cmp     bl, 'a'
    jb      .do_it
    cmp     bl, 'f'
    ja      .do_it

.parse_end:
    call    parse_hex
    jc      .do_it
    cmp     ax, [dump_off]
    jb      .do_it
    sub     ax, [dump_off]
    inc     ax
    mov     [dump_len], ax
    jmp     .do_it

.parse_len_only:
    jmp     .parse_len

.parse_len:
    inc     esi
.skip_ws5:
    mov     al, [esi]
    cmp     al, ' '
    je      .adv5
    cmp     al, 9
    je      .adv5
    jmp     .read_len
.adv5:
    inc     esi
    jmp     .skip_ws5
.read_len:
    call    parse_hex
    jc      .do_it
    test    ax, ax
    jz      .do_it
    mov     [dump_len], ax

.do_it:
    call    do_dump
    ret

cmd_fill:
    mov     esi, input_buffer
    inc     esi

.cf_skip1:
    mov     al, [esi]
    cmp     al, ' '
    je      .cf_adv1
    cmp     al, 9
    je      .cf_adv1
    jmp     .cf_parse_addr
.cf_adv1:
    inc     esi
    jmp     .cf_skip1

.cf_parse_addr:
    call    parse_hex
    jc      .cf_ret
    mov     bx, ax

.cf_skip2:
    mov     al, [esi]
    cmp     al, ' '
    je      .cf_adv2
    cmp     al, 9
    je      .cf_adv2
    jmp     .cf_check_colon
.cf_adv2:
    inc     esi
    jmp     .cf_skip2

.cf_check_colon:
    cmp     al, ':'
    jne     .cf_no_colon

    inc     esi

.cf_skip3:
    mov     al, [esi]
    cmp     al, ' '
    je      .cf_adv3
    cmp     al, 9
    je      .cf_adv3
    jmp     .cf_parse_off
.cf_adv3:
    inc     esi
    jmp     .cf_skip3

.cf_parse_off:
    call    parse_hex
    jc      .cf_ret
    mov     [fill_seg], bx
    mov     [fill_off], ax
    jmp     .cf_after_addr

.cf_no_colon:
    mov     ax, [reg_DS]
    mov     [fill_seg], ax
    mov     [fill_off], bx

.cf_after_addr:
.cf_skip4:
    mov     al, [esi]
    cmp     al, ' '
    je      .cf_adv4
    cmp     al, 9
    je      .cf_adv4
    jmp     .cf_check_len
.cf_adv4:
    inc     esi
    jmp     .cf_skip4

.cf_check_len:
    cmp     al, 'l'
    je      .cf_have_l
    cmp     al, 'L'
    je      .cf_have_l

    call    parse_hex
    jc      .cf_ret
    cmp     ax, [fill_off]
    jb      .cf_ret
    sub     ax, [fill_off]
    inc     ax
    mov     [fill_len], ax
    jmp     .cf_skip6

.cf_have_l:
    inc     esi

.cf_skip5:
    mov     al, [esi]
    cmp     al, ' '
    je      .cf_adv5
    cmp     al, 9
    je      .cf_adv5
    jmp     .cf_parse_len
.cf_adv5:
    inc     esi
    jmp     .cf_skip5

.cf_parse_len:
    call    parse_hex
    jc      .cf_ret
    test    ax, ax
    jz      .cf_ret
    mov     [fill_len], ax

.cf_skip6:
    mov     al, [esi]
    cmp     al, ' '
    je      .cf_adv6
    cmp     al, 9
    je      .cf_adv6
    jmp     .cf_parse_pattern
.cf_adv6:
    inc     esi
    jmp     .cf_skip6

.cf_parse_pattern:
    mov     al, [esi]
    cmp     al, '"'
    je      .cf_parse_string

    mov     edi, fill_pat
    xor     ecx, ecx

.cf_pat_loop:
    mov     al, [esi]
    cmp     al, ' '
    je      .cf_pat_skip
    cmp     al, 9
    je      .cf_pat_skip
    cmp     al, 13
    je      .cf_pat_done
    cmp     al, 10
    je      .cf_pat_done
    test    al, al
    jz      .cf_pat_done

    call    parse_hex_byte
    jc      .cf_pat_done
    stosb
    inc     ecx
    cmp     ecx, 64
    jae     .cf_pat_done
    jmp     .cf_pat_loop

.cf_pat_skip:
    inc     esi
    jmp     .cf_pat_loop

.cf_pat_done:
    test    ecx, ecx
    jz      .cf_ret
    mov     [fill_patlen], cx
    jmp     .cf_do_fill

.cf_parse_string:
    inc     esi
    mov     edi, fill_pat
    xor     ecx, ecx

.cf_str_loop:
    mov     al, [esi]
    test    al, al
    jz      .cf_str_done
    cmp     al, '"'
    je      .cf_str_done
    cmp     al, 13
    je      .cf_str_done
    cmp     al, 10
    je      .cf_str_done

    stosb
    inc     ecx
    inc     esi
    cmp     ecx, 64
    jae     .cf_str_done
    jmp     .cf_str_loop

.cf_str_done:
    test    ecx, ecx
    jz      .cf_ret
    mov     [fill_patlen], cx

.cf_do_fill:
    movzx   eax, word [fill_seg]
    shl     eax, 4
    movzx   ebx, word [fill_off]
    add     eax, ebx

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
    mov     esi, input_buffer
    inc     esi

.ce_skip1:
    mov     al, [esi]
    cmp     al, ' '
    je      .ce_adv1
    cmp     al, 9
    je      .ce_adv1
    jmp     .ce_parse_addr
.ce_adv1:
    inc     esi
    jmp     .ce_skip1

.ce_parse_addr:
    call    parse_hex
    jc      .ce_ret
    mov     bx, ax

.ce_skip2:
    mov     al, [esi]
    cmp     al, ' '
    je      .ce_adv2
    cmp     al, 9
    je      .ce_adv2
    jmp     .ce_check_colon
.ce_adv2:
    inc     esi
    jmp     .ce_skip2

.ce_check_colon:
    cmp     al, ':'
    jne     .ce_no_colon

    inc     esi

.ce_skip3:
    mov     al, [esi]
    cmp     al, ' '
    je      .ce_adv3
    cmp     al, 9
    je      .ce_adv3
    jmp     .ce_parse_off
.ce_adv3:
    inc     esi
    jmp     .ce_skip3

.ce_parse_off:
    call    parse_hex
    jc      .ce_ret
    mov     [edit_seg], bx
    mov     [edit_off], ax
    jmp     .ce_after_addr

.ce_no_colon:
    mov     ax, [reg_DS]
    mov     [edit_seg], ax
    mov     [edit_off], bx

.ce_after_addr:
    movzx   eax, word [edit_seg]
    shl     eax, 4
    movzx   ebx, word [edit_off]
    add     eax, ebx
    mov     ebp, memory
    add     ebp, eax

.ce_skip_ws_after:
    mov     al, [esi]
    cmp     al, ' '
    je      .ce_adv_after
    cmp     al, 9
    je      .ce_adv_after
    jmp     .ce_check_token
.ce_adv_after:
    inc     esi
    jmp     .ce_skip_ws_after
.ce_check_token:
    cmp     al, 13
    je      .ce_interactive
    cmp     al, 10
    je      .ce_interactive
    test    al, al
    jz      .ce_interactive

    mov     edi, ebp
    jmp     .ce_next_token

.ce_next_token:
.ce_skip_ws:
    mov     al, [esi]
    cmp     al, ' '
    je      .ce_skip_inc
    cmp     al, 9
    je      .ce_skip_inc
    jmp     .ce_check_end
.ce_skip_inc:
    inc     esi
    jmp     .ce_skip_ws

.ce_check_end:
    cmp     al, 13
    je      .ce_ret
    cmp     al, 10
    je      .ce_ret
    test    al, al
    jz      .ce_ret

    cmp     al, 22h
    je      .ce_string
    cmp     al, 27h
    je      .ce_string

    call    parse_hex_byte
    jc      .ce_ret
    stosb
    jmp     .ce_next_token

.ce_string:
    mov     dl, al
    inc     esi
.ce_str_loop:
    mov     al, [esi]
    test    al, al
    jz      .ce_ret
    cmp     al, dl
    je      .ce_str_end
    cmp     al, 13
    je      .ce_ret
    cmp     al, 10
    je      .ce_ret
    stosb
    inc     esi
    jmp     .ce_str_loop
.ce_str_end:
    inc     esi
    jmp     .ce_next_token

.ce_interactive:
    invoke  GetConsoleMode, [hStdIn], old_console_mode
    mov     eax, [old_console_mode]
    and     eax, not 2
    invoke  SetConsoleMode, [hStdIn], eax

    mov     byte [edit_have_nibble], 0
    mov     byte [edit_cell_done], 0

    mov     edi, line_buffer
    mov     ax, [edit_seg]
    call    put_hex_word
    mov     al, ':'
    stosb
    mov     ax, [edit_off]
    call    put_hex_word
    mov     al, ' '
    stosb
    mov     al, [ebp]
    call    put_hex_byte
    mov     al, '.'
    stosb
    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0

.ce_int_read:
    invoke  ReadConsoleA, [hStdIn], edit_char, 1, edit_chars_read, 0
    mov     al, [edit_char]

    cmp     al, 13
    je      .ce_int_done
    cmp     al, 10
    je      .ce_int_done
    cmp     al, ' '
    je      .ce_int_space

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

.ce_int_space:
    mov     byte [edit_have_nibble], 0
    mov     byte [edit_cell_done], 0
    inc     ebp
    inc     word [edit_off]
    mov     edi, line_buffer
    mov     al, ' '
    stosb
    stosb
    mov     al, [ebp]
    call    put_hex_byte
    mov     al, '.'
    stosb
    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0
    jmp     .ce_int_read

.ce_int_done:
    invoke  SetConsoleMode, [hStdIn], [old_console_mode]
    mov     byte [line_buffer], 13
    mov     byte [line_buffer+1], 10
    invoke  WriteConsoleA, [hStdOut], line_buffer, 2, chars_written, 0
    ret

.ce_ret:
    ret

exit_program:
    invoke  ExitProcess, 0

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