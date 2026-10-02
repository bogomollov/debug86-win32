section '.text' code readable executable

do_dump:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp

    movzx   ebp, word [dump_len]
    test    ebp, ebp
    jz      dd_done

dd_line_loop:
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

    mov     ecx, ebp
    cmp     ecx, 16
    jbe     dd_have_count
    mov     ecx, 16
dd_have_count:
    mov     ebx, ecx
    xor     edx, edx

dd_hex_loop:
    lodsb
    call    put_hex_byte
    inc     edx
    cmp     edx, ebx
    je      dd_hex_pad
    cmp     edx, 8
    je      dd_dash
    mov     al, ' '
    stosb
    jmp     dd_hex_loop
dd_dash:
    mov     al, '-'
    stosb
    jmp     dd_hex_loop

dd_hex_pad:
    cmp     edx, 16
    je      dd_hex_done
.pad_loop:
    cmp     edi, line_buffer + 58
    jae     dd_hex_done
    cmp     edi, line_buffer + 34
    jne     .pad_space
    cmp     edx, 8
    jbe     .pad_space
    mov     al, '-'
    stosb
.pad_space:
    mov     al, ' '
    stosb
    jmp     .pad_loop

dd_hex_done:
    mov     al, ' '
    stosb
    stosb
    stosb

    sub     esi, ebx
    mov     ecx, ebx
dd_ascii_loop:
    lodsb
    cmp     al, 20h
    jb      dd_nonprint
    cmp     al, 7Fh
    jae     dd_nonprint
    jmp     dd_print
dd_nonprint:
    mov     al, '.'
dd_print:
    stosb
    loop    dd_ascii_loop

    mov     al, 13
    stosb
    mov     al, 10
    stosb

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0

    add     word [dump_off], bx
    sub     ebp, ebx
    jz      dd_done
    jmp     dd_line_loop

dd_done:
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret