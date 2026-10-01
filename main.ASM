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
    jmp     .do_it

.set_offset:
    mov     [dump_off], bx

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