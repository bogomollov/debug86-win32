format PE CONSOLE

entry start

include 'fasm/include/win32a.inc'

include 'data.asm'
include 'hex.asm'

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

do_dump:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp

    mov     ebp, 8

.line_loop:
    mov     edi, line_buffer

    mov     ax, [dump_seg]
    call    put_hex_word
    mov     al, ':'
    stosb
    mov     ax, [dump_off]
    call    put_hex_word

    mov     al, ' '
    stosb
    stosb

    movzx   eax, word [dump_seg]
    shl     eax, 4
    movzx   ebx, word [dump_off]
    add     eax, ebx
    mov     esi, memory
    add     esi, eax

    xor     edx, edx
.hex_loop:
    lodsb
    call    put_hex_byte
    inc     edx
    cmp     edx, 16
    je      .hex_done
    cmp     edx, 8
    je      .dash
    mov     al, ' '
    stosb
    jmp     .hex_loop
.dash:
    mov     al, '-'
    stosb
    jmp     .hex_loop
.hex_done:
    mov     al, ' '
    stosb
    stosb
    stosb

    sub     esi, 16
    mov     ecx, 16
.ascii_loop:
    lodsb
    cmp     al, 20h
    jb      .nonprint
    cmp     al, 7Eh
    ja      .nonprint
    jmp     .print
.nonprint:
    mov     al, '.'
.print:
    stosb
    loop    .ascii_loop

    mov     al, 13
    stosb
    mov     al, 10
    stosb

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0

    add     word [dump_off], 16

    dec     ebp
    jnz     .line_loop

    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

section '.idata' import data readable writeable
    library kernel32, 'KERNEL32.DLL'

    import kernel32,\
           ExitProcess,   'ExitProcess',\
           GetStdHandle,  'GetStdHandle',\
           WriteConsoleA, 'WriteConsoleA',\
           ReadConsoleA,  'ReadConsoleA'