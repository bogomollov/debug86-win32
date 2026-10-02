section '.text' code readable executable

DUMP_ASCII_OFFSET = 34
DUMP_LINE_LENGTH  = 58

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

    mov     ax, [dump_off]
    movzx   ecx, ax
    and     ecx, 0Fh
    mov     [dd_skip], cx

    and     ax, 0FFF0h
    mov     [dump_off], ax

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
    movzx   ecx, word [dd_skip]
    add     eax, ecx
    mov     esi, memory
    add     esi, eax

    movzx   ecx, word [dd_skip]
    mov     edx, 16
    sub     edx, ecx
    cmp     ebp, edx
    jae     .dd_have_n
    mov     edx, ebp
.dd_have_n:
    mov     [dd_line_bytes], dx
    mov     ebx, edx

    movzx   edx, word [dd_skip]
    xor     ecx, ecx

.dd_hex_slot:
    cmp     ecx, 16
    jae     .dd_hex_done
    cmp     edx, 0
    je      .dd_hex_try_byte
    mov     al, ' '
    stosb
    stosb
    dec     edx
    jmp     .dd_hex_sep
.dd_hex_try_byte:
    cmp     ebx, 0
    je      .dd_hex_blank
    lodsb
    call    put_hex_byte
    dec     ebx
    jmp     .dd_hex_sep
.dd_hex_blank:
    mov     al, ' '
    stosb
    stosb
.dd_hex_sep:
    inc     ecx
    cmp     ecx, 16
    jae     .dd_hex_done
    cmp     ecx, 8
    jne     .dd_hex_sep_space
    mov     al, '-'
    stosb
    jmp     .dd_hex_slot
.dd_hex_sep_space:
    mov     al, ' '
    stosb
    jmp     .dd_hex_slot

.dd_hex_done:
    mov     al, ' '
    stosb
    stosb
    stosb

    movzx   ecx, word [dd_line_bytes]
    sub     esi, ecx

    movzx   edx, word [dd_skip]
    movzx   ebx, word [dd_line_bytes]

.dd_ascii_loop:
    test    edx, edx
    jz      .dd_ascii_char
    mov     al, ' '
    stosb
    dec     edx
    jmp     .dd_ascii_loop
.dd_ascii_char:
    test    ebx, ebx
    jz      .dd_ascii_done
    lodsb
    cmp     al, 20h
    jb      .dd_ascii_nonprint
    cmp     al, 7Fh
    jae     .dd_ascii_nonprint
    jmp     .dd_ascii_store
.dd_ascii_nonprint:
    mov     al, '.'
.dd_ascii_store:
    stosb
    dec     ebx
    jmp     .dd_ascii_loop
.dd_ascii_done:
    mov     al, 13
    stosb
    mov     al, 10
    stosb

    mov     edx, edi
    sub     edx, line_buffer
    invoke  WriteConsoleA, [hStdOut], line_buffer, edx, chars_written, 0

    movzx   ecx, word [dd_line_bytes]
    sub     ebp, ecx
    jz      dd_done
    add     word [dump_off], 16
    mov     word [dd_skip], 0
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