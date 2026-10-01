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