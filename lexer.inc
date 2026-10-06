TOK_EOF         equ 0
TOK_NUMBER      equ 1
TOK_IDENT       equ 2
TOK_STRING      equ 3
TOK_PUNCT       equ 4

TOK_TEXT_MAX    equ 64

lex_next:
    call    lex_skip_ws

    call    lex_is_eol
    jc      .eof

    mov     al, [esi]

    cmp     al, QUOTE_DOUBLE
    je      .string
    cmp     al, QUOTE_SINGLE
    je      .string

    call    hex_to_val
    jnc     .number

    mov     al, [esi]
    mov     ah, al
    or      ah, 20h
    cmp     ah, 'a'
    jb      .punct
    cmp     ah, 'z'
    ja      .punct
    jmp     .ident

.ident:
    mov     edi, tok_text
    xor     ecx, ecx
.ident_loop:
    mov     al, [esi]
    mov     ah, al
    or      ah, 20h
    cmp     ah, 'a'
    jb      .ident_try_digit
    cmp     ah, 'z'
    ja      .ident_try_digit

    cmp     al, 'A'
    jb      .ident_store
    cmp     al, 'Z'
    ja      .ident_store
    add     al, 20h
    jmp     .ident_store
.ident_try_digit:
    cmp     al, '0'
    jb      .ident_done
    cmp     al, '9'
    ja      .ident_done
.ident_store:
    cmp     ecx, TOK_TEXT_MAX-1
    jae     .ident_skip
    stosb
    inc     ecx
.ident_skip:
    inc     esi
    jmp     .ident_loop
.ident_done:
    mov     byte [edi], 0
    mov     al, TOK_IDENT
    ret

.number:
    xor     ebx, ebx
    xor     ecx, ecx
.number_loop:
    cmp     ecx, 4
    jae     .number_done
    mov     al, [esi]
    call    hex_to_val
    jc      .number_done
    shl     bx, 4
    or      bl, al
    inc     esi
    inc     ecx
    jmp     .number_loop
.number_done:
    test    cx, cx
    jz      .punct
    mov     [tok_num], bx
    mov     byte [tok_text], 0
    mov     al, TOK_NUMBER
    ret

.string:
    mov     [tok_punct], al
    inc     esi
    mov     edi, tok_text
    xor     ecx, ecx
.string_loop:
    mov     al, [esi]
    test    al, al
    jz      .string_done
    cmp     al, CR
    je      .string_done
    cmp     al, LF
    je      .string_done
    cmp     al, [tok_punct]
    je      .string_close
    cmp     ecx, TOK_TEXT_MAX-1
    jae     .string_skip
    stosb
    inc     ecx
.string_skip:
    inc     esi
    jmp     .string_loop
.string_close:
    inc     esi
.string_done:
    mov     byte [edi], 0
    mov     al, TOK_STRING
    ret

.punct:
    mov     al, [esi]
    mov     [tok_punct], al
    inc     esi
    mov     byte [tok_text], 0
    mov     al, TOK_PUNCT
    ret

.eof:
    mov     byte [tok_text], 0
    mov     al, TOK_EOF
    ret

lex_skip_ws:
    mov     al, [esi]
    cmp     al, SPACE
    je      .adv
    cmp     al, 9
    je      .adv
    cmp     al, COMMA
    je      .adv
    ret
.adv:
    inc     esi
    jmp     lex_skip_ws

lex_is_eol:
    mov     al, [esi]
    cmp     al, CR
    je      .yes
    cmp     al, LF
    je      .yes
    test    al, al
    jz      .yes
    clc
    ret
.yes:
    stc
    ret

lex_expect_punct:
    push    esi
    push    eax
    call    lex_next
    pop     edx
    cmp     al, TOK_PUNCT
    jne     .fail
    cmp     [tok_punct], dl
    jne     .fail
    add     esp, 4
    clc
    ret
.fail:
    pop     esi
    stc
    ret

section '.bss' readable writeable
    tok_num     rw 1
    tok_punct   rb 1
    tok_text    rb TOK_TEXT_MAX