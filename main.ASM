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

    mov     al, [input_buffer]
    or      al, 20h

    cmp     al, 'q'
    je      exit_program
    cmp     al, 'd'
    je      cmd_dump
    jmp     main_loop

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
    mov     [dump_off], bx

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
    jmp     main_loop

exit_program:
    invoke  ExitProcess, 0

section '.idata' import data readable writeable
    library kernel32, 'KERNEL32.DLL'

    import kernel32,\
           ExitProcess,   'ExitProcess',\
           GetStdHandle,  'GetStdHandle',\
           WriteConsoleA, 'WriteConsoleA',\
           ReadConsoleA,  'ReadConsoleA'