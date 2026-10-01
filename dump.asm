section '.text' code readable executable

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