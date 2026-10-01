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

exit_program:
    invoke  ExitProcess, 0

section '.idata' import data readable writeable
    library kernel32, 'KERNEL32.DLL'

    import kernel32,\
           ExitProcess,   'ExitProcess',\
           GetStdHandle,  'GetStdHandle',\
           WriteConsoleA, 'WriteConsoleA',\
           ReadConsoleA,  'ReadConsoleA'