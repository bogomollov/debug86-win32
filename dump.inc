section '.text' code readable executable

do_dump:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp

    cmp     word [dump_len], 0
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
    mov     al, COLON
    stosb
    mov     ax, [dump_off]
    call    put_hex_word

    mov     al, SPACE
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
    mov     edx, DUMP_LINE_BYTES
    sub     edx, ecx
    movzx   eax, word [dump_len]
    cmp     eax, edx
    jae     .dd_have_n
    mov     edx, eax
.dd_have_n:
    mov     [dd_line_bytes], dx
    mov     ebx, edx

    movzx   edx, word [dd_skip]
    xor     ecx, ecx

.dd_hex_slot:
    cmp     ecx, DUMP_LINE_BYTES
    jae     .dd_hex_done
    cmp     edx, 0
    je      .dd_hex_try_byte
    mov     al, SPACE
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
    mov     al, SPACE
    stosb
    stosb
.dd_hex_sep:
    inc     ecx
    cmp     ecx, 8
    jne     .dd_hex_sep_space
    mov     al, '-'
    stosb
    jmp     .dd_hex_slot
.dd_hex_sep_space:
    mov     al, SPACE
    stosb
    jmp     .dd_hex_slot

.dd_hex_done:
    mov     al, SPACE
    stosb
    stosb

    movzx   ecx, word [dd_line_bytes]
    sub     esi, ecx

    movzx   edx, word [dd_skip]
    movzx   ebx, word [dd_line_bytes]

.dd_ascii_loop:
    test    edx, edx
    jz      .dd_ascii_char
    mov     al, SPACE
    stosb
    dec     edx
    jmp     .dd_ascii_loop
.dd_ascii_char:
    test    ebx, ebx
    jz      .dd_ascii_done
    lodsb
    cmp     al, 20h
    jb      .dd_ascii_nonprint
    cmp     al, 7Eh
    ja      .dd_ascii_nonprint
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

    mov     ecx, edi
    sub     ecx, line_buffer
    mov     esi, line_buffer
    call    print_buffer

    add     word [dump_off], DUMP_LINE_BYTES
    movzx   ecx, word [dd_line_bytes]
    sub     word [dump_len], cx
    jz      dd_done
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