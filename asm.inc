cmd_assemble:
    mov     esi, [cmd_ptr]

    call    skip_whitespace
    call    is_eol
    jc      .use_default
    
    call    parse_address_cs
    jc      print_error_and_ret
    mov     [asm_seg], ax
    mov     [asm_off], bx

    call    skip_whitespace
    call    is_eol
    jnc     print_error_and_ret
    jmp     .loop

.use_default:
    mov     ax, [reg_CS]
    mov     [asm_seg], ax
    mov     ax, [asm_off]
    test    ax, ax
    jnz     .loop
    mov     word [asm_off], 0100h

.loop:
    cmp     byte [ctrl_c_flag], 0
    jne     .interrupted

    mov     edi, line_buffer
    mov     ax, [asm_seg]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, [asm_off]
    call    put_hex_word
    mov     al, SPACE
    stosb
    stosb
    
    mov     edx, edi
    sub     edx, line_buffer
    mov     [prompt_len], edx
    call    print_line_buffer

    mov     edi, input_buffer
    mov     edx, 255
    call    read_line_console_or_pipe
    cmp     byte [ctrl_c_flag], 0
    jne     .interrupted
    jc      .done
    
    mov     esi, input_buffer
    call    skip_whitespace
    call    is_eol
    jc      .done

    call    parse_instruction
    jc      .error
    
    mov     ax, [asm_seg]
    mov     bx, [asm_off]
    call    calc_linear_addr
    movzx   ecx, word [asm_len]
    call    check_mem_range
    jc      .error
    
    mov     edi, memory
    add     edi, eax
    mov     esi, asm_bytes
    rep     movsb
    
    mov     ax, [asm_len]
    add     [asm_off], ax
    jmp     .loop

.error:
    call    print_error
    jmp     .loop

.interrupted:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer

.done:
    mov     dword [prompt_len], 1
    ret


mem_mnem_table:
    db 'mov', 0, 1, 0
    db 'add', 0, 0, 0
    db 'or',  0, 0, 1
    db 'adc', 0, 0, 2
    db 'sbb', 0, 0, 3
    db 'and', 0, 0, 4
    db 'sub', 0, 0, 5
    db 'xor', 0, 0, 6
    db 'cmp', 0, 0, 7
    db 'test',0, 2, 0
    db 'mul', 0, 3, 4
    db 'not', 0, 3, 2
    db 'neg', 0, 3, 3
    db 'imul', 0, 3, 5
    db 'div', 0, 3, 6
    db 'idiv', 0, 3, 7
    db 'inc', 0, 4, 0
    db 'dec', 0, 4, 1
    db 'push',0, 4, 6
    db 'pop', 0, 5, 0
    db 'rol', 0, 6, 0
    db 'ror', 0, 6, 1
    db 'rcl', 0, 6, 2
    db 'rcr', 0, 6, 3
    db 'shl', 0, 6, 4
    db 'sal', 0, 6, 4
    db 'shr', 0, 6, 5
    db 'sar', 0, 6, 7
    db 'xchg',0, 7, 0
    db 'lea', 0, 8, 8Dh
    db 'lds', 0, 8, 0C5h
    db 'les', 0, 8, 0C4h
    db 'call',0, 9, 2
    db 'jmp', 0, 9, 4
    db 0

; In: edi = pointer to mnemonic string in asm_token
; Out: cl = type, ch = code, CF = 0 if found, CF = 1 if not found
lookup_mnemonic:
    push    esi
    push    edx
    push    ebx
    mov     ebx, mem_mnem_table
.lm_search:
    cmp     byte [ebx], 0
    je      .lm_not_found
    mov     edx, ebx
    mov     esi, edi
.lm_cmp:
    mov     al, [esi]
    mov     ah, [edx]
    cmp     al, ah
    jne     .lm_next
    test    al, al
    jz      .lm_match
    inc     esi
    inc     edx
    jmp     .lm_cmp
.lm_next:
    cmp     byte [ebx], 0
    je      .lm_skip_null
    inc     ebx
    jmp     .lm_next
.lm_skip_null:
    add     ebx, 3
    jmp     .lm_search
.lm_match:
    mov     cl, [edx+1]
    mov     ch, [edx+2]
    pop     ebx
    pop     edx
    pop     esi
    clc
    ret
.lm_not_found:
    pop     ebx
    pop     edx
    pop     esi
    stc
    ret

check_has_bracket:
.scan:
    mov     al, [esi]
    test    al, al
    jz      .no
    cmp     al, CR
    je      .no
    cmp     al, LF
    je      .no
    cmp     al, '['
    je      .yes
    inc     esi
    jmp     .scan
.yes:
    stc
    ret
.no:
    clc
    ret

parse_asm_sreg:
    push    ebx
    mov     ebx, esi
.pas_skip_ws:
    mov     al, [ebx]
    cmp     al, ' '
    je      .pas_inc_ws
    cmp     al, 9
    je      .pas_inc_ws
    jmp     .pas_check
.pas_inc_ws:
    inc     ebx
    jmp     .pas_skip_ws
.pas_check:
    mov     al, [ebx]
    or      al, 20h
    mov     ah, [ebx+1]
    or      ah, 20h
    cmp     ah, 's'
    jne     .pas_fail
    mov     dl, [ebx+2]
    cmp     dl, ' '
    je      .pas_delim_ok
    cmp     dl, 9
    je      .pas_delim_ok
    cmp     dl, ','
    je      .pas_delim_ok
    cmp     dl, CR
    je      .pas_delim_ok
    cmp     dl, LF
    je      .pas_delim_ok
    test    dl, dl
    jz      .pas_delim_ok
    jmp     .pas_fail
.pas_delim_ok:
    cmp     al, 'e'
    jne     .pas_not_es
    mov     al, 0
    jmp     .pas_matched
.pas_not_es:
    cmp     al, 'c'
    jne     .pas_not_cs
    mov     al, 1
    jmp     .pas_matched
.pas_not_cs:
    cmp     al, 's'
    jne     .pas_not_ss
    mov     al, 2
    jmp     .pas_matched
.pas_not_ss:
    cmp     al, 'd'
    jne     .pas_fail
    mov     al, 3
.pas_matched:
    add     ebx, 2
    mov     esi, ebx
    pop     ebx
    clc
    ret
.pas_fail:
    pop     ebx
    stc
    ret

parse_asm_reg:
    push    ebx
    push    ecx
    push    edx

    mov     ebx, esi
.skip_ws:
    mov     al, [ebx]
    cmp     al, ' '
    je      .inc_ws
    cmp     al, 9
    je      .inc_ws
    jmp     .check_chars
.inc_ws:
    inc     ebx
    jmp     .skip_ws

.check_chars:
    mov     al, [ebx]
    test    al, al
    jz      .fail
    cmp     al, CR
    je      .fail
    cmp     al, LF
    je      .fail
    mov     ah, [ebx+1]
    test    ah, ah
    jz      .fail
    cmp     ah, CR
    je      .fail
    cmp     ah, LF
    je      .fail

    cmp     al, 'A'
    jb      .c1_ok
    cmp     al, 'Z'
    ja      .c1_ok
    add     al, 20h
.c1_ok:
    cmp     ah, 'A'
    jb      .c2_ok
    cmp     ah, 'Z'
    ja      .c2_ok
    add     ah, 20h
.c2_ok:

    mov     dl, [ebx+2]
    cmp     dl, ' '
    je      .delim_ok
    cmp     dl, 9
    je      .delim_ok
    cmp     dl, ','
    je      .delim_ok
    cmp     dl, ']'
    je      .delim_ok
    cmp     dl, '+'
    je      .delim_ok
    cmp     dl, '-'
    je      .delim_ok
    cmp     dl, CR
    je      .delim_ok
    cmp     dl, LF
    je      .delim_ok
    test    dl, dl
    jz      .delim_ok
    jmp     .fail

.delim_ok:
    cmp     al, 'a'
    jne     .not_ax
    cmp     ah, 'x'
    jne     .not_ax
    mov     al, 0
    mov     ah, 2
    jmp     .matched
.not_ax:
    cmp     al, 'c'
    jne     .not_cx
    cmp     ah, 'x'
    jne     .not_cx
    mov     al, 1
    mov     ah, 2
    jmp     .matched
.not_cx:
    cmp     al, 'd'
    jne     .not_dx
    cmp     ah, 'x'
    jne     .not_dx
    mov     al, 2
    mov     ah, 2
    jmp     .matched
.not_dx:
    cmp     al, 'b'
    jne     .not_bx
    cmp     ah, 'x'
    jne     .not_bx
    mov     al, 3
    mov     ah, 2
    jmp     .matched
.not_bx:
    cmp     al, 's'
    jne     .not_sp
    cmp     ah, 'p'
    jne     .not_sp
    mov     al, 4
    mov     ah, 2
    jmp     .matched
.not_sp:
    cmp     al, 'b'
    jne     .not_bp
    cmp     ah, 'p'
    jne     .not_bp
    mov     al, 5
    mov     ah, 2
    jmp     .matched
.not_bp:
    cmp     al, 's'
    jne     .not_si
    cmp     ah, 'i'
    jne     .not_si
    mov     al, 6
    mov     ah, 2
    jmp     .matched
.not_si:
    cmp     al, 'd'
    jne     .not_di
    cmp     ah, 'i'
    jne     .not_di
    mov     al, 7
    mov     ah, 2
    jmp     .matched
.not_di:

    cmp     al, 'a'
    jne     .not_al
    cmp     ah, 'l'
    jne     .not_al
    mov     al, 0
    mov     ah, 1
    jmp     .matched
.not_al:
    cmp     al, 'c'
    jne     .not_cl
    cmp     ah, 'l'
    jne     .not_cl
    mov     al, 1
    mov     ah, 1
    jmp     .matched
.not_cl:
    cmp     al, 'd'
    jne     .not_dl
    cmp     ah, 'l'
    jne     .not_dl
    mov     al, 2
    mov     ah, 1
    jmp     .matched
.not_dl:
    cmp     al, 'b'
    jne     .not_bl
    cmp     ah, 'l'
    jne     .not_bl
    mov     al, 3
    mov     ah, 1
    jmp     .matched
.not_bl:
    cmp     al, 'a'
    jne     .not_ah
    cmp     ah, 'h'
    jne     .not_ah
    mov     al, 4
    mov     ah, 1
    jmp     .matched
.not_ah:
    cmp     al, 'c'
    jne     .not_ch
    cmp     ah, 'h'
    jne     .not_ch
    mov     al, 5
    mov     ah, 1
    jmp     .matched
.not_ch:
    cmp     al, 'd'
    jne     .not_dh
    cmp     ah, 'h'
    jne     .not_dh
    mov     al, 6
    mov     ah, 1
    jmp     .matched
.not_dh:
    cmp     al, 'b'
    jne     .not_bh
    cmp     ah, 'h'
    jne     .not_bh
    mov     al, 7
    mov     ah, 1
    jmp     .matched
.not_bh:

.fail:
    pop     edx
    pop     ecx
    pop     ebx
    stc
    ret

.matched:
    add     ebx, 2
    mov     esi, ebx
    pop     edx
    pop     ecx
    pop     ebx
    clc
    ret

parse_size_prefix:
    push    ebx
    push    ecx
    push    edx

    mov     ebx, esi
.psp_skip_ws:
    mov     al, [ebx]
    cmp     al, ' '
    je      .psp_inc_ws
    cmp     al, 9
    je      .psp_inc_ws
    jmp     .psp_check
.psp_inc_ws:
    inc     ebx
    jmp     .psp_skip_ws

.psp_check:
    mov     al, [ebx]
    or      al, 20h
    cmp     al, 'w'
    jne     .psp_check_byte
    mov     al, [ebx+1]
    or      al, 20h
    cmp     al, 'o'
    jne     .psp_check_byte
    mov     al, [ebx+2]
    or      al, 20h
    cmp     al, 'r'
    jne     .psp_check_byte
    mov     al, [ebx+3]
    or      al, 20h
    cmp     al, 'd'
    jne     .psp_check_byte
    mov     al, [ebx+4]
    cmp     al, ' '
    je      .psp_word_match
    cmp     al, 9
    je      .psp_word_match
    cmp     al, '['
    je      .psp_word_match
    jmp     .psp_fail

.psp_word_match:
    add     ebx, 4
    mov     edx, 2
    jmp     .psp_check_ptr

.psp_check_byte:
    mov     al, [ebx]
    or      al, 20h
    cmp     al, 'b'
    jne     .psp_check_far
    mov     al, [ebx+1]
    or      al, 20h
    cmp     al, 'y'
    jne     .psp_check_far
    mov     al, [ebx+2]
    or      al, 20h
    cmp     al, 't'
    jne     .psp_check_far
    mov     al, [ebx+3]
    or      al, 20h
    cmp     al, 'e'
    jne     .psp_check_far
    mov     al, [ebx+4]
    cmp     al, ' '
    je      .psp_byte_match
    cmp     al, 9
    je      .psp_byte_match
    cmp     al, '['
    je      .psp_byte_match
    jmp     .psp_check_far

.psp_byte_match:
    add     ebx, 4
    mov     edx, 1
    jmp     .psp_check_ptr

.psp_check_far:
    mov     al, [ebx]
    or      al, 20h
    cmp     al, 'f'
    jne     .psp_fail
    mov     al, [ebx+1]
    or      al, 20h
    cmp     al, 'a'
    jne     .psp_fail
    mov     al, [ebx+2]
    or      al, 20h
    cmp     al, 'r'
    jne     .psp_fail
    mov     al, [ebx+3]
    cmp     al, ' '
    je      .psp_far_match
    cmp     al, 9
    je      .psp_far_match
    cmp     al, '['
    je      .psp_far_match
    jmp     .psp_fail

.psp_far_match:
    add     ebx, 3
    mov     edx, 4
    jmp     .psp_check_ptr

.psp_check_ptr:
.psp_ptr_ws:
    mov     al, [ebx]
    cmp     al, ' '
    je      .psp_ptr_inc
    cmp     al, 9
    je      .psp_ptr_inc
    jmp     .psp_check_ptr_word
.psp_ptr_inc:
    inc     ebx
    jmp     .psp_ptr_ws

.psp_check_ptr_word:
    mov     al, [ebx]
    or      al, 20h
    cmp     al, 'p'
    jne     .psp_done
    mov     al, [ebx+1]
    or      al, 20h
    cmp     al, 't'
    jne     .psp_done
    mov     al, [ebx+2]
    or      al, 20h
    cmp     al, 'r'
    jne     .psp_done
    mov     al, [ebx+3]
    cmp     al, ' '
    je      .psp_skip_ptr_str
    cmp     al, 9
    je      .psp_skip_ptr_str
    cmp     al, '['
    je      .psp_skip_ptr_str
    jmp     .psp_done
.psp_skip_ptr_str:
    add     ebx, 3
.psp_after_ptr_ws:
    mov     al, [ebx]
    cmp     al, ' '
    je      .psp_after_ptr_inc
    cmp     al, 9
    je      .psp_after_ptr_inc
    jmp     .psp_done
.psp_after_ptr_inc:
    inc     ebx
    jmp     .psp_after_ptr_ws

.psp_done:
    mov     esi, ebx
    mov     eax, edx
    pop     edx
    pop     ecx
    pop     ebx
    clc
    ret

.psp_fail:
    pop     edx
    pop     ecx
    pop     ebx
    xor     eax, eax
    stc
    ret

parse_mem_instruction:
    push    ebp
    mov     ebp, esp
    sub     esp, 128

    virtual at ebp - 128
        .var_type           dd ?
        .var_reg            dd ?
        .var_size           dd ?
        .var_has_bx         dd ?
        .var_has_bp         dd ?
        .var_has_si         dd ?
        .var_has_di         dd ?
        .var_has_disp       dd ?
        .var_sign           dd ?
        .var_disp           dd ?
        .var_mod            dd ?
        .var_rm             dd ?
        .var_disp_len       dd ?
        .var_imm            dd ?
        .var_opcode         dd ?
        .var_modrm          dd ?
        .var_imm_len        dd ?
        .var_dir            dd ?
        .var_is_reg_op      dd ?
        .var_explicit_size  dd ?
        .var_alu_op         dd ?
        .var_seg_pfx        dd ?
        .var_is_sreg        dd ?
        .mnem_buf           rb 36
    end virtual

    mov     dword [.var_type], 0      ; var_type
    mov     dword [.var_reg], 0      ; var_reg
    mov     dword [.var_size], 2     ; var_size (default word = 2)
    mov     dword [.var_has_bx], 0     ; var_has_bx
    mov     dword [.var_has_bp], 0     ; var_has_bp
    mov     dword [.var_has_si], 0     ; var_has_si
    mov     dword [.var_has_di], 0     ; var_has_di
    mov     dword [.var_has_disp], 0     ; var_has_disp
    mov     dword [.var_sign], 1     ; var_sign = 1
    mov     dword [.var_disp], 0     ; var_disp = 0
    mov     dword [.var_mod], 0     ; var_mod = 0
    mov     dword [.var_rm], 0     ; var_rm = 0
    mov     dword [.var_disp_len], 0     ; var_disp_len = 0
    mov     dword [.var_imm], 0     ; var_imm = 0
    mov     dword [.var_opcode], 0     ; var_opcode
    mov     dword [.var_modrm], 0     ; var_modrm
    mov     dword [.var_imm_len], 2     ; var_imm_len = 2
    mov     dword [.var_dir], 0     ; var_dir (0=mem dest, 1=reg dest)
    mov     dword [.var_is_reg_op], 0     ; var_is_reg_op (0=imm, 1=reg)
    mov     dword [.var_explicit_size], 0     ; var_explicit_size (0=none, 1=byte, 2=word)
    mov     dword [.var_alu_op], 0     ; var_alu_op (0..7)
    mov     dword [.var_seg_pfx], 0     ; var_seg_pfx (0=none, or 26h, 2Eh, 36h, 3Eh)
    mov     dword [.var_is_sreg], 0     ; var_is_sreg (0=no, 1=yes)

    call    skip_whitespace
    lea     edi, [.mnem_buf]
.read_mnem:
    call    is_eol
    jc      .mem_err
    mov     al, [esi]
    cmp     al, ' '
    je      .mnem_done
    cmp     al, 9
    je      .mnem_done
    cmp     al, '['
    je      .mnem_done
    cmp     al, 'A'
    jb      .mnem_store
    cmp     al, 'Z'
    ja      .mnem_store
    add     al, 20h
.mnem_store:
    stosb
    inc     esi
    lea     eax, [.mnem_buf+15]
    cmp     edi, eax
    jae     .mem_err
    jmp     .read_mnem
.mnem_done:
    mov     byte [edi], 0

    mov     ebx, mem_mnem_table
.search_mnem:
    cmp     byte [ebx], 0
    je      .mem_err
    lea     edi, [.mnem_buf]
    mov     edx, ebx
.cmp_mnem:
    mov     al, [edi]
    mov     ah, [edx]
    cmp     al, ah
    jne     .next_mnem
    test    al, al
    jz      .found_mnem
    inc     edi
    inc     edx
    jmp     .cmp_mnem
.next_mnem:
    cmp     byte [ebx], 0
    je      .skip_null
    inc     ebx
    jmp     .next_mnem
.skip_null:
    add     ebx, 3
    jmp     .search_mnem

.found_mnem:
    mov     edx, ebx
.find_mnem_null:
    cmp     byte [edx], 0
    je      .got_mnem_null
    inc     edx
    jmp     .find_mnem_null
.got_mnem_null:
    movzx   eax, byte [edx+1]
    mov     dword [.var_type], eax   ; var_type
    movzx   eax, byte [edx+2]
    mov     dword [.var_reg], eax   ; var_reg
    mov     dword [.var_alu_op], eax  ; var_alu_op

    call    skip_whitespace

    ; Check if Operand 1 is a segment register (e.g. MOV DS, [0200])
    cmp     dword [.var_type], 1      ; MOV only
    jne     .check_op1_reg
    call    parse_asm_sreg
    jc      .check_op1_reg
    cmp     al, 1                 ; MOV CS, mem is illegal
    je      .mem_err
    mov     dword [.var_dir], 1     ; reg is destination
    movzx   edx, al
    mov     dword [.var_reg], edx    ; sreg index in var_reg
    mov     dword [.var_size], 2     ; word size
    mov     dword [.var_is_sreg], 1     ; var_is_sreg = 1
    mov     dword [.var_is_reg_op], 1     ; is reg op
    call    skip_whitespace
    cmp     byte [esi], ','
    jne     .sreg_op1_no_comma
    inc     esi
    call    skip_whitespace
.sreg_op1_no_comma:
    call    .parse_seg_prefix
    cmp     byte [esi], '['
    jne     .mem_err
    call    .parse_bracket_content
    jc      .mem_err
    call    skip_whitespace
    call    is_eol
    jnc     .mem_err
    jmp     .encode_instruction

.check_op1_reg:
    ; Check if Operand 1 is a register (e.g. MOV DX, [0200])
    call    parse_asm_reg
    jnc     .op1_is_reg

    ; Operand 1 is MEMORY (e.g. MOV [0200], AX or MOV WORD PTR [BX+8], 0017)
    mov     dword [.var_dir], 0    ; var_dir = 0 (mem is destination)

    call    .parse_seg_prefix
    call    parse_size_prefix
    jc      .op1_no_size_prefix
    mov     [.var_size], eax        ; var_size = 1 or 2
    mov     [.var_explicit_size], eax        ; var_explicit_size = 1 or 2
.op1_no_size_prefix:

    call    skip_whitespace
    call    .parse_seg_prefix
    cmp     byte [esi], '['
    jne     .mem_err

    call    .parse_bracket_content
    jc      .mem_err

    cmp     dword [.var_type], 6
    je      .shift_mem
    cmp     dword [.var_type], 9     ; CALL / JMP memory
    je      .unary_mem_call_jmp
    cmp     dword [.var_type], 7     ; XCHG memory dest
    je      .not_unary_mem
    cmp     dword [.var_type], 3
    jb      .not_unary_mem
    cmp     dword [.var_type], 5
    je      .unary_mem_pop
    cmp     dword [.var_type], 4
    jne     .unary_req_size
    cmp     dword [.var_reg], 6     ; PUSH r/m16?
    je      .unary_mem_push
.unary_req_size:
    cmp     dword [.var_explicit_size], 0
    jz      .mem_err
    call    skip_whitespace
    call    is_eol
    jnc     .mem_err
    cmp     dword [.var_type], 3
    jne     .unary_mem_dec
    mov     dword [.var_opcode], 0F6h
    cmp     dword [.var_size], 2
    jne     .unary_mem_done
    mov     dword [.var_opcode], 0F7h
    jmp     .unary_mem_done
.unary_mem_dec:
    mov     dword [.var_opcode], 0FEh
    cmp     dword [.var_size], 2
    jne     .unary_mem_done
    mov     dword [.var_opcode], 0FFh
    jmp     .unary_mem_done
.unary_mem_push:
    call    skip_whitespace
    call    is_eol
    jnc     .mem_err
    cmp     dword [.var_size], 1
    je      .mem_err             ; PUSH BYTE PTR is illegal
    mov     dword [.var_opcode], 0FFh
    mov     dword [.var_size], 2
    jmp     .unary_mem_done
.unary_mem_pop:
    call    skip_whitespace
    call    is_eol
    jnc     .mem_err
    cmp     dword [.var_size], 1
    je      .mem_err             ; POP BYTE PTR is illegal
    mov     dword [.var_opcode], 8Fh
    mov     dword [.var_reg], 0
    mov     dword [.var_size], 2
    jmp     .unary_mem_done
.unary_mem_call_jmp:
    call    skip_whitespace
    call    is_eol
    jnc     .mem_err
    cmp     dword [.var_size], 1
    je      .mem_err             ; BYTE PTR is illegal
    cmp     dword [.var_size], 4
    jne     .not_far_target
    inc     dword [.var_reg]        ; 2 -> 3 (CALL FAR), 4 -> 5 (JMP FAR)
.not_far_target:
    mov     dword [.var_opcode], 0FFh
    mov     dword [.var_size], 2
.unary_mem_done:
    mov     dword [.var_imm_len], 0
    jmp     .encode_instruction

.shift_mem:
    cmp     dword [.var_explicit_size], 0
    jz      .mem_err
    call    skip_whitespace
    call    parse_asm_reg
    jc      .shift_check_imm
    cmp     ah, 1
    jne     .mem_err
    cmp     al, 1
    jne     .mem_err
    mov     dword [.var_is_reg_op], 1
    jmp     .shift_count_parsed

.shift_check_imm:
    call    parse_hex
    jc      .mem_err
    cmp     ax, 1
    jne     .mem_err
    mov     dword [.var_is_reg_op], 0

.shift_count_parsed:
    call    skip_whitespace
    call    is_eol
    jnc     .mem_err

    mov     eax, 0D0h
    cmp     dword [.var_size], 2
    jne     .shift_size_byte
    inc     eax
.shift_size_byte:
    cmp     dword [.var_is_reg_op], 1
    jne     .shift_op_set
    add     eax, 2
.shift_op_set:
    mov     dword [.var_opcode], eax
    mov     dword [.var_imm_len], 0
    jmp     .encode_instruction
.not_unary_mem:

    call    skip_whitespace
    cmp     byte [esi], ','
    jne     .op1_mem_no_comma
    inc     esi
    call    skip_whitespace
.op1_mem_no_comma:

    ; Check if Operand 2 is a segment register (e.g. MOV [100], DS)
    cmp     dword [.var_type], 1      ; MOV only
    jne     .check_op2_reg
    call    parse_asm_sreg
    jc      .check_op2_reg
    mov     dword [.var_is_reg_op], 1     ; var_is_reg_op = 1
    mov     dword [.var_is_sreg], 1     ; var_is_sreg = 1
    movzx   edx, al
    mov     dword [.var_reg], edx    ; sreg index in var_reg
    mov     dword [.var_size], 2     ; word size
    call    skip_whitespace
    call    is_eol
    jnc     .mem_err
    jmp     .encode_instruction

.check_op2_reg:
    ; Check if Operand 2 is a register
    call    parse_asm_reg
    jc      .op2_is_immediate

    ; Operand 2 IS A REGISTER!
    mov     dword [.var_is_reg_op], 1    ; var_is_reg_op = 1
    movzx   edx, al
    mov     dword [.var_reg], edx   ; var_reg = source reg
    movzx   edx, ah              ; edx = reg size (1 or 2)

    cmp     dword [.var_explicit_size], 0
    jz      .op2_deduce_size
    cmp     [.var_explicit_size], edx
    jne     .mem_err
.op2_deduce_size:
    mov     [.var_size], edx        ; var_size = reg size

    call    skip_whitespace
    call    is_eol
    jnc     .mem_err

    jmp     .encode_instruction

.op2_is_immediate:
    cmp     dword [.var_explicit_size], 0
    jz      .mem_err
    mov     dword [.var_is_reg_op], 0    ; var_is_reg_op = 0
    call    parse_hex
    jc      .mem_err
    cmp     dword [.var_size], 1
    jne     .op2_imm_ok
    test    ah, ah
    jnz     .mem_err
.op2_imm_ok:
    movzx   eax, ax
    mov     dword [.var_imm], eax  ; var_imm = eax

    call    skip_whitespace
    call    is_eol
    jnc     .mem_err

    jmp     .encode_instruction

.op1_is_reg:
    cmp     dword [.var_type], 3
    jb      .op1_reg_type_ok
    cmp     dword [.var_type], 7     ; XCHG
    je      .op1_reg_type_ok
    cmp     dword [.var_type], 8     ; LEA / LDS / LES
    je      .op1_reg_type_8
    jmp     .mem_err

.op1_reg_type_8:
    cmp     ah, 2                ; must be 16-bit register
    jne     .mem_err

.op1_reg_type_ok:
    mov     dword [.var_dir], 1    ; var_dir = 1 (reg is destination)
    movzx   edx, al
    mov     dword [.var_reg], edx   ; var_reg = destination reg
    movzx   edx, ah
    mov     dword [.var_size], edx  ; var_size = reg size (1 or 2)
    mov     dword [.var_is_reg_op], 1    ; var_is_reg_op = 1

    call    skip_whitespace
    cmp     byte [esi], ','
    jne     .op1_reg_no_comma
    inc     esi
    call    skip_whitespace
.op1_reg_no_comma:

    call    .parse_seg_prefix
    call    parse_size_prefix
    jc      .op2_no_size_prefix
    cmp     dword [.var_type], 8     ; LEA/LDS/LES doesn't enforce size prefix matching reg
    je      .op2_no_size_prefix
    cmp     eax, [.var_size]
    jne     .mem_err
.op2_no_size_prefix:

    call    skip_whitespace
    call    .parse_seg_prefix
    cmp     byte [esi], '['
    jne     .mem_err

    call    .parse_bracket_content
    jc      .mem_err

    call    skip_whitespace
    call    is_eol
    jnc     .mem_err

.encode_instruction:
    mov     eax, [.var_mod]        ; var_mod
    shl     al, 6
    mov     edx, [.var_reg]         ; var_reg
    shl     dl, 3
    or      al, dl
    mov     edx, [.var_rm]        ; var_rm
    or      al, dl
    mov     dword [.var_modrm], eax  ; var_modrm

    cmp     dword [.var_type], 3
    jb      .check_reg_op
    cmp     dword [.var_type], 7
    je      .check_reg_op
    cmp     dword [.var_type], 8
    je      .check_reg_op
    jmp     .emit_bytes

.check_reg_op:
    cmp     dword [.var_is_reg_op], 1
    je      .enc_reg_op

    ; --- IMMEDIATE OPERAND ---
    cmp     dword [.var_type], 1     ; MOV?
    je      .enc_mov_imm
    cmp     dword [.var_type], 2     ; TEST?
    je      .enc_test_imm

    ; ALU with immediate
    cmp     dword [.var_size], 1    ; byte?
    jne     .alu_word_imm
    mov     dword [.var_opcode], 80h  ; opcode 80h
    mov     dword [.var_imm_len], 1    ; imm_len = 1
    jmp     .emit_bytes

.alu_word_imm:
    mov     al, byte [.var_imm]
    movsx   eax, al
    cmp     eax, dword [.var_imm]
    jne     .alu_imm16
    mov     dword [.var_opcode], 83h  ; opcode 83h
    mov     dword [.var_imm_len], 1    ; imm_len = 1
    jmp     .emit_bytes

.alu_imm16:
    mov     dword [.var_opcode], 81h  ; opcode 81h
    mov     dword [.var_imm_len], 2    ; imm_len = 2
    jmp     .emit_bytes

.enc_mov_imm:
    cmp     dword [.var_size], 1    ; byte?
    jne     .mov_word_imm
    mov     dword [.var_opcode], 0C6h ; opcode C6h
    mov     dword [.var_imm_len], 1
    jmp     .emit_bytes
.mov_word_imm:
    mov     dword [.var_opcode], 0C7h ; opcode C7h
    mov     dword [.var_imm_len], 2
    jmp     .emit_bytes

.enc_test_imm:
    cmp     dword [.var_size], 1    ; byte?
    jne     .test_word_imm
    mov     dword [.var_opcode], 0F6h ; opcode F6h
    mov     dword [.var_imm_len], 1
    jmp     .emit_bytes
.test_word_imm:
    mov     dword [.var_opcode], 0F7h ; opcode F7h
    mov     dword [.var_imm_len], 2
    jmp     .emit_bytes

    ; --- REGISTER OPERAND ---
.enc_reg_op:
    mov     dword [.var_imm_len], 0    ; imm_len = 0

    cmp     dword [.var_is_sreg], 1    ; segment register?
    jne     .not_sreg_move
    cmp     dword [.var_dir], 1    ; sreg is dest?
    je      .sreg_is_dest
    mov     dword [.var_opcode], 8Ch  ; MOV r/m16, sreg
    jmp     .emit_bytes
.sreg_is_dest:
    mov     dword [.var_opcode], 8Eh  ; MOV sreg, r/m16
    jmp     .emit_bytes
.not_sreg_move:

    cmp     dword [.var_type], 1     ; MOV?
    je      .enc_mov_reg
    cmp     dword [.var_type], 2     ; TEST?
    je      .enc_test_reg
    cmp     dword [.var_type], 7     ; XCHG?
    je      .enc_xchg_reg
    cmp     dword [.var_type], 8     ; LEA / LDS / LES?
    je      .enc_lea_lds_les

    ; ALU with register
    mov     eax, [.var_alu_op]        ; var_alu_op
    shl     eax, 3
    cmp     dword [.var_dir], 1
    jne     .alu_reg_mem_dst
    add     eax, 2
.alu_reg_mem_dst:
    cmp     dword [.var_size], 2
    jne     .alu_reg_set_op
    inc     eax
.alu_reg_set_op:
    mov     dword [.var_opcode], eax
    jmp     .emit_bytes

.enc_xchg_reg:
    cmp     dword [.var_size], 1
    je      .xchg_rm8_r8
    mov     dword [.var_opcode], 87h
    jmp     .emit_bytes
.xchg_rm8_r8:
    mov     dword [.var_opcode], 86h
    jmp     .emit_bytes

.enc_lea_lds_les:
    mov     eax, [.var_alu_op]
    mov     dword [.var_opcode], eax
    jmp     .emit_bytes

.enc_mov_reg:
    cmp     dword [.var_dir], 1
    je      .mov_reg_dst
    cmp     dword [.var_size], 1
    je      .mov_rm8_r8
    mov     dword [.var_opcode], 89h
    jmp     .emit_bytes
.mov_rm8_r8:
    mov     dword [.var_opcode], 88h
    jmp     .emit_bytes

.mov_reg_dst:
    cmp     dword [.var_size], 1
    je      .mov_r8_rm8
    mov     dword [.var_opcode], 8Bh
    jmp     .emit_bytes
.mov_r8_rm8:
    mov     dword [.var_opcode], 8Ah
    jmp     .emit_bytes

.enc_test_reg:
    cmp     dword [.var_size], 1
    je      .test_rm8_r8
    mov     dword [.var_opcode], 85h
    jmp     .emit_bytes
.test_rm8_r8:
    mov     dword [.var_opcode], 84h
    jmp     .emit_bytes

.emit_bytes:
    mov     edi, asm_bytes
    cmp     dword [.var_seg_pfx], 0
    jz      .no_seg_pfx
    mov     al, byte [.var_seg_pfx]
    stosb
.no_seg_pfx:
    mov     al, byte [.var_opcode]    ; opcode
    stosb
    mov     al, byte [.var_modrm]    ; modrm
    stosb

    mov     ecx, [.var_disp_len]        ; disp_len
    test    ecx, ecx
    jz      .emit_imm_check
    mov     al, byte [.var_disp]
    stosb
    cmp     ecx, 2
    jne     .emit_imm_check
    mov     al, byte [.var_disp+1]
    stosb

.emit_imm_check:
    cmp     dword [.var_imm_len], 0
    jz      .emit_done
    mov     al, byte [.var_imm]
    stosb
    cmp     dword [.var_imm_len], 2
    jne     .emit_done
    mov     al, byte [.var_imm+1]
    stosb

.emit_done:
    mov     eax, edi
    sub     eax, asm_bytes
    mov     word [asm_len], ax
    clc
    leave
    ret

.mem_err:
    leave
    stc
    ret

.parse_bracket_content:
    cmp     byte [esi], '['
    jne     .bracket_err
    inc     esi

.bracket_loop:
    call    skip_whitespace
    call    is_eol
    jc      .bracket_err
    mov     al, [esi]
    cmp     al, ']'
    je      .bracket_done

    cmp     al, '+'
    jne     .not_plus
    mov     dword [.var_sign], 1    ; var_sign = 1
    inc     esi
    jmp     .bracket_loop

.not_plus:
    cmp     al, '-'
    jne     .not_minus
    mov     dword [.var_sign], -1   ; var_sign = -1
    inc     esi
    jmp     .bracket_loop

.not_minus:
    mov     al, [esi]
    mov     ah, [esi+1]
    or      al, 20h
    or      ah, 20h
    mov     dl, [esi+2]
    cmp     dl, ' '
    je      .try_reg
    cmp     dl, 9
    je      .try_reg
    cmp     dl, '+'
    je      .try_reg
    cmp     dl, '-'
    je      .try_reg
    cmp     dl, ']'
    je      .try_reg
    jmp     .parse_disp_num

.try_reg:
    cmp     al, 'b'
    jne     .check_reg_bp
    cmp     ah, 'x'
    jne     .check_reg_bp
    cmp     dword [.var_has_bx], 0
    jne     .bracket_err
    mov     dword [.var_has_bx], 1    ; var_has_bx = 1
    add     esi, 2
    jmp     .bracket_loop

.check_reg_bp:
    cmp     al, 'b'
    jne     .check_reg_si
    cmp     ah, 'p'
    jne     .check_reg_si
    cmp     dword [.var_has_bp], 0
    jne     .bracket_err
    mov     dword [.var_has_bp], 1    ; var_has_bp = 1
    add     esi, 2
    jmp     .bracket_loop

.check_reg_si:
    cmp     al, 's'
    jne     .check_reg_di
    cmp     ah, 'i'
    jne     .check_reg_di
    cmp     dword [.var_has_si], 0
    jne     .bracket_err
    mov     dword [.var_has_si], 1    ; var_has_si = 1
    add     esi, 2
    jmp     .bracket_loop

.check_reg_di:
    cmp     al, 'd'
    jne     .parse_disp_num
    cmp     ah, 'i'
    jne     .parse_disp_num
    cmp     dword [.var_has_di], 0
    jne     .bracket_err
    mov     dword [.var_has_di], 1    ; var_has_di = 1
    add     esi, 2
    jmp     .bracket_loop

.parse_disp_num:
    call    parse_hex
    jc      .bracket_err
    movsx   eax, ax
    cmp     dword [.var_sign], -1
    jne     .disp_pos
    neg     eax
.disp_pos:
    add     dword [.var_disp], eax  ; var_disp += eax
    mov     dword [.var_has_disp], 1    ; var_has_disp = 1
    mov     dword [.var_sign], 1    ; reset var_sign = 1
    jmp     .bracket_loop

.bracket_done:
    inc     esi

    mov     eax, [.var_has_bx]
    add     eax, [.var_has_bp]
    cmp     eax, 2
    jae     .bracket_err

    mov     eax, [.var_has_si]
    add     eax, [.var_has_di]
    cmp     eax, 2
    jae     .bracket_err

    cmp     dword [.var_has_bx], 1
    jne     .check_bx_di
    cmp     dword [.var_has_si], 1
    jne     .check_bx_di
    mov     dword [.var_rm], 0    ; RM = 0
    jmp     .got_rm

.check_bx_di:
    cmp     dword [.var_has_bx], 1
    jne     .check_bp_si
    cmp     dword [.var_has_di], 1
    jne     .check_bp_si
    mov     dword [.var_rm], 1    ; RM = 1
    jmp     .got_rm

.check_bp_si:
    cmp     dword [.var_has_bp], 1
    jne     .check_bp_di
    cmp     dword [.var_has_si], 1
    jne     .check_bp_di
    mov     dword [.var_rm], 2    ; RM = 2
    jmp     .got_rm

.check_bp_di:
    cmp     dword [.var_has_bp], 1
    jne     .check_si_only
    cmp     dword [.var_has_di], 1
    jne     .check_si_only
    mov     dword [.var_rm], 3    ; RM = 3
    jmp     .got_rm

.check_si_only:
    cmp     dword [.var_has_si], 1
    jne     .check_di_only
    mov     dword [.var_rm], 4    ; RM = 4
    jmp     .got_rm

.check_di_only:
    cmp     dword [.var_has_di], 1
    jne     .check_bp_only
    mov     dword [.var_rm], 5    ; RM = 5
    jmp     .got_rm

.check_bp_only:
    cmp     dword [.var_has_bp], 1
    jne     .check_bx_only
    mov     dword [.var_rm], 6    ; RM = 6
    jmp     .got_rm

.check_bx_only:
    cmp     dword [.var_has_bx], 1
    jne     .direct_addr
    mov     dword [.var_rm], 7    ; RM = 7
    jmp     .got_rm

.direct_addr:
    mov     dword [.var_rm], 6    ; RM = 6
    mov     dword [.var_mod], 0    ; Mod = 00b
    mov     dword [.var_disp_len], 2    ; disp_len = 2
    jmp     .rm_done

.got_rm:
    cmp     dword [.var_has_disp], 0    ; has_disp?
    jne     .has_some_disp
    cmp     dword [.var_rm], 6    ; BP only?
    jne     .no_disp_zero
    mov     dword [.var_mod], 1    ; Mod = 01b
    mov     dword [.var_disp_len], 1    ; disp_len = 1
    mov     dword [.var_disp], 0
    jmp     .rm_done

.no_disp_zero:
    mov     dword [.var_mod], 0    ; Mod = 00b
    mov     dword [.var_disp_len], 0    ; disp_len = 0
    jmp     .rm_done

.has_some_disp:
    cmp     dword [.var_disp], 0
    jne     .check_disp_size
    cmp     dword [.var_rm], 6    ; BP only?
    je      .disp8_case
    mov     dword [.var_mod], 0    ; Mod = 00b
    mov     dword [.var_disp_len], 0    ; disp_len = 0
    jmp     .rm_done

.check_disp_size:
    mov     al, byte [.var_disp]
    movsx   eax, al
    cmp     eax, dword [.var_disp]
    jne     .disp16_case

.disp8_case:
    mov     dword [.var_mod], 1    ; Mod = 01b
    mov     dword [.var_disp_len], 1    ; disp_len = 1
    jmp     .rm_done

.disp16_case:
    mov     dword [.var_mod], 2    ; Mod = 10b
    mov     dword [.var_disp_len], 2    ; disp_len = 2

.rm_done:
    clc
    ret

.bracket_err:
    stc
    ret

.parse_seg_prefix:
    call    skip_whitespace
    mov     al, [esi]
    or      al, 20h
    mov     ah, [esi+1]
    or      ah, 20h
    cmp     ah, 's'
    jne     .seg_none
    push    ebx
    mov     ebx, esi
    add     ebx, 2
.seg_skip_ws:
    mov     dl, [ebx]
    cmp     dl, ' '
    je      .seg_inc_ws
    cmp     dl, 9
    je      .seg_inc_ws
    jmp     .seg_check_colon
.seg_inc_ws:
    inc     ebx
    jmp     .seg_skip_ws
.seg_check_colon:
    cmp     dl, ':'
    jne     .seg_fail
    inc     ebx
    mov     esi, ebx
    pop     ebx
    cmp     al, 'e'
    jne     .seg_not_es
    mov     dword [.var_seg_pfx], 26h
    call    skip_whitespace
    ret
.seg_not_es:
    cmp     al, 'c'
    jne     .seg_not_cs
    mov     dword [.var_seg_pfx], 2Eh
    call    skip_whitespace
    ret
.seg_not_cs:
    cmp     al, 's'
    jne     .seg_not_ss
    mov     dword [.var_seg_pfx], 36h
    call    skip_whitespace
    ret
.seg_not_ss:
    cmp     al, 'd'
    jne     .seg_none
    mov     dword [.var_seg_pfx], 3Eh
    call    skip_whitespace
    ret
.seg_fail:
    pop     ebx
.seg_none:
    ret

try_parse_reg_insn:
    push    ebp
    push    ebx
    push    esi

    mov     edi, asm_token
    call    lookup_mnemonic
    jc      .prr_backtrack

    cmp     cl, 0
    je      .prr_type_ok
    cmp     cl, 1
    je      .prr_type_ok
    cmp     cl, 2
    je      .prr_type_ok
    cmp     cl, 6
    je      .prr_type_ok
    cmp     cl, 7
    je      .prr_type_ok
    jmp     .prr_backtrack

.prr_type_ok:
    push    ecx
    call    skip_whitespace

    mov     cl, [esp]
    cmp     cl, 1
    jne     .prr_check_reg1
    call    parse_asm_sreg
    jc      .prr_check_reg1

    cmp     al, 1
    je      .prr_syntax_err_pop1
    movzx   ebx, al

    call    skip_whitespace
    cmp     byte [esi], ','
    jne     .sreg1_no_comma
    inc     esi
.sreg1_no_comma:
    call    skip_whitespace

    call    parse_asm_reg
    jc      .prr_syntax_err_pop1
    cmp     ah, 2
    jne     .prr_syntax_err_pop1

    call    skip_whitespace
    call    is_eol
    jnc     .prr_syntax_err_pop1

    mov     byte [asm_bytes], 8Eh
    mov     ah, bl
    shl     ah, 3
    or      ah, 0C0h
    or      ah, al
    mov     byte [asm_bytes+1], ah
    mov     word [asm_len], 2
    add     esp, 4
    add     esp, 4
    pop     ebx
    pop     ebp
    clc
    ret

.prr_check_reg1:
    call    parse_asm_reg
    jc      .prr_backtrack_pop1

    push    eax

    call    skip_whitespace
    cmp     byte [esi], ','
    jne     .reg1_no_comma
    inc     esi
.reg1_no_comma:
    call    skip_whitespace

    mov     cl, [esp+4]

    cmp     cl, 6
    je      .prr_shift

    cmp     cl, 1
    jne     .prr_check_reg2
    cmp     byte [esp+1], 2
    jne     .prr_check_reg2
    call    parse_asm_sreg
    jc      .prr_check_reg2

    call    skip_whitespace
    call    is_eol
    jnc     .prr_syntax_err_pop2

    mov     byte [asm_bytes], 8Ch
    shl     al, 3
    or      al, 0C0h
    or      al, [esp]
    mov     byte [asm_bytes+1], al
    jmp     .prr_success_2bytes

.prr_shift:
    mov     al, [esi]
    cmp     al, '1'
    je      .shift_1
    cmp     al, '0'
    jne     .check_cl
    cmp     byte [esi+1], '1'
    jne     .prr_syntax_err_pop2
    inc     esi
.shift_1:
    inc     esi
    call    skip_whitespace
    call    is_eol
    jnc     .prr_syntax_err_pop2
    mov     al, 0D0h
    add     al, [esp+1]
    dec     al
    mov     [asm_bytes], al
    mov     ah, [esp+5]
    shl     ah, 3
    or      ah, 0C0h
    or      ah, [esp]
    mov     [asm_bytes+1], ah
    jmp     .prr_success_2bytes

.check_cl:
    mov     ah, [esi+1]
    or      al, 20h
    or      ah, 20h
    cmp     al, 'c'
    jne     .prr_syntax_err_pop2
    cmp     ah, 'l'
    jne     .prr_syntax_err_pop2
    add     esi, 2
    call    skip_whitespace
    call    is_eol
    jnc     .prr_syntax_err_pop2
    mov     al, 0D2h
    add     al, [esp+1]
    dec     al
    mov     [asm_bytes], al
    mov     ah, [esp+5]
    shl     ah, 3
    or      ah, 0C0h
    or      ah, [esp]
    mov     [asm_bytes+1], ah
    jmp     .prr_success_2bytes

.prr_check_reg2:
    call    parse_asm_reg
    jc      .prr_op2_not_reg

    cmp     ah, [esp+1]
    jne     .prr_syntax_err_pop2

    mov     dl, al
    shl     dl, 3
    or      dl, 0C0h
    or      dl, [esp]

    call    skip_whitespace
    call    is_eol
    jnc     .prr_syntax_err_pop2

    mov     cl, [esp+4]
    mov     ch, [esp+5]
    mov     bl, [esp+1]
    dec     bl

    cmp     cl, 0
    je      .emit_alu
    cmp     cl, 1
    je      .emit_mov
    cmp     cl, 7
    je      .emit_xchg
    cmp     cl, 2
    je      .emit_test
    jmp     .prr_syntax_err_pop2

.emit_alu:
    shl     ch, 3
    or      ch, bl
    mov     [asm_bytes], ch
    mov     [asm_bytes+1], dl
    jmp     .prr_success_2bytes

.emit_mov:
    mov     al, 88h
    or      al, bl
    mov     [asm_bytes], al
    mov     [asm_bytes+1], dl
    jmp     .prr_success_2bytes

.emit_xchg:
    mov     al, 86h
    or      al, bl
    mov     [asm_bytes], al
    mov     [asm_bytes+1], dl
    jmp     .prr_success_2bytes

.emit_test:
    mov     al, 84h
    or      al, bl
    mov     [asm_bytes], al
    mov     [asm_bytes+1], dl
    jmp     .prr_success_2bytes

.prr_success_2bytes:
    mov     word [asm_len], 2
    add     esp, 8
    add     esp, 4
    pop     ebx
    pop     ebp
    clc
    ret

.prr_op2_not_reg:
    mov     cl, [esp+4]
    cmp     cl, 7
    je      .prr_syntax_err_pop2
    add     esp, 4
.prr_backtrack_pop1:
    add     esp, 4
.prr_backtrack:
    pop     esi
    pop     ebx
    pop     ebp
    xor     al, al
    stc
    ret

.prr_syntax_err_pop2:
    add     esp, 4
.prr_syntax_err_pop1:
    add     esp, 4
    add     esp, 4
    pop     ebx
    pop     ebp
    mov     al, 1
    stc
    ret
parse_instruction:
    call    skip_whitespace
    call    is_eol
    jc      .err

    ; Check for 'db' or 'dw' directive
    mov     al, [esi]
    or      al, 20h
    cmp     al, 'd'
    jne     .not_directive
    mov     ah, [esi+1]
    or      ah, 20h
    cmp     ah, 'b'
    je      .check_db_delim
    cmp     ah, 'w'
    je      .check_dw_delim
    jmp     .not_directive

.check_db_delim:
    mov     al, [esi+2]
    cmp     al, ' '
    je      .parse_db
    cmp     al, 9
    je      .parse_db
    cmp     al, ','
    je      .parse_db
    jmp     .not_directive

.check_dw_delim:
    mov     al, [esi+2]
    cmp     al, ' '
    je      .parse_dw
    cmp     al, 9
    je      .parse_dw
    cmp     al, ','
    je      .parse_dw
    jmp     .not_directive

.parse_db:
    add     esi, 2
    xor     ecx, ecx
    mov     edi, asm_bytes
.db_loop:
    call    skip_whitespace
    call    is_eol
    jc      .db_done
    mov     al, [esi]
    cmp     al, ''''
    je      .db_string
    cmp     al, '"'
    je      .db_string
    call    parse_hex_byte
    jc      .err
    movzx   ecx, cx
    cmp     ecx, ASM_BYTES_SIZE
    jae     .err
    mov     [edi], al
    inc     edi
    inc     ecx
    jmp     .db_loop
.db_string:
    mov     dl, al
    inc     esi
.db_str_loop:
    call    is_eol
    jc      .err
    mov     al, [esi]
    cmp     al, dl
    jne     .db_str_char
    inc     esi
    cmp     byte [esi], dl
    jne     .db_loop
.db_str_char:
    cmp     ecx, ASM_BYTES_SIZE
    jae     .err
    mov     [edi], al
    inc     edi
    inc     ecx
    inc     esi
    jmp     .db_str_loop
.db_done:
    test    ecx, ecx
    jz      .err
    mov     [asm_len], cx
    clc
    ret

.parse_dw:
    add     esi, 2
    xor     ecx, ecx
    mov     edi, asm_bytes
.dw_loop:
    call    skip_whitespace
    call    is_eol
    jc      .dw_done
    call    parse_hex
    jc      .err
    movzx   ecx, cx
    cmp     ecx, ASM_BYTES_SIZE - 2
    ja      .err
    mov     [edi], al
    mov     [edi+1], ah
    add     edi, 2
    add     ecx, 2
    jmp     .dw_loop
.dw_done:
    test    ecx, ecx
    jz      .err
    mov     [asm_len], cx
    clc
    ret

.not_directive:
    push    esi
    call    check_has_bracket
    pop     esi
    jc      parse_mem_instruction

    mov     edi, asm_token
    call    get_token
    
    cmp     byte [asm_token], 0
    je      .err
    
    mov     ebx, asm_1word_table
    call    search_table
    jnc     .found

    mov     ebx, asm_rel8_table
    call    search_table
    jnc     .found_rel8

    ; Check if first token is 'call'
    cmp     dword [asm_token], 'call'
    jne     .not_call_insn
    cmp     byte [asm_token+4], 0
    jne     .not_call_insn

    call    skip_whitespace
    call    is_eol
    jc      .err

    ; Check reg16: call ax, call bx, etc.
    push    esi
    call    parse_asm_reg
    jc      .call_target
    cmp     ah, 2
    jne     .call_target_restore
    push    eax
    call    skip_whitespace
    call    is_eol
    pop     eax
    jnc     .call_target_restore
    add     esp, 4
    mov     byte [asm_bytes], 0FFh
    add     al, 0D0h
    mov     byte [asm_bytes+1], al
    mov     word [asm_len], 2
    clc
    ret

.call_target_restore:
    pop     esi
    jmp     .call_parse_addr

.call_target:
    pop     esi

.call_parse_addr:
    call    parse_hex
    jc      .err
    mov     bx, ax
    call    skip_whitespace
    cmp     byte [esi], ':'
    jne     .call_near

    ; Far call: 9A off seg (5 bytes)
    inc     esi
    call    skip_whitespace
    call    parse_hex
    jc      .err
    push    ax
    call    skip_whitespace
    call    is_eol
    pop     ax
    jnc     .err
    mov     byte [asm_bytes], 9Ah
    mov     [asm_bytes+1], al
    mov     [asm_bytes+2], ah
    mov     [asm_bytes+3], bl
    mov     [asm_bytes+4], bh
    mov     word [asm_len], 5
    clc
    ret

.call_near:
    call    is_eol
    jnc     .err
    mov     ax, bx
    sub     ax, [asm_off]
    sub     ax, 3
    mov     byte [asm_bytes], 0E8h
    mov     [asm_bytes+1], al
    mov     [asm_bytes+2], ah
    mov     word [asm_len], 3
    clc
    ret

.not_call_insn:
    cmp     dword [asm_token], 'out'
    jne     .not_out_imm
    cmp     byte [asm_token+3], 0
    jne     .not_out_imm

    push    esi
    call    skip_whitespace
    mov     al, [esi]
    or      al, 20h
    mov     ah, [esi+1]
    or      ah, 20h
    cmp     al, 'd'
    jne     .try_port_hex
    cmp     ah, 'x'
    je      .not_out_imm_restore
.try_port_hex:
    call    parse_hex
    jc      .not_out_imm_restore
    cmp     ax, 0FFh
    ja      .not_out_imm_restore
    movzx   ebx, al
    call    skip_whitespace
    cmp     byte [esi], ','
    jne     .out_no_comma
    inc     esi
    call    skip_whitespace
.out_no_comma:
    mov     edi, asm_token
    call    get_token
    cmp     word [asm_token], 'al'
    jne     .out_check_ax
    cmp     byte [asm_token+2], 0
    jne     .not_out_imm_restore
    add     esp, 4
    call    skip_whitespace
    call    is_eol
    jnc     .err
    mov     byte [asm_bytes], 0E6h
    mov     byte [asm_bytes+1], bl
    mov     word [asm_len], 2
    clc
    ret

.out_check_ax:
    cmp     word [asm_token], 'ax'
    jne     .not_out_imm_restore
    cmp     byte [asm_token+2], 0
    jne     .not_out_imm_restore
    add     esp, 4
    call    skip_whitespace
    call    is_eol
    jnc     .err
    mov     byte [asm_bytes], 0E7h
    mov     byte [asm_bytes+1], bl
    mov     word [asm_len], 2
    clc
    ret

.not_out_imm_restore:
    pop     esi
.not_out_imm:
    call    try_parse_reg_insn
    jnc     .reg_reg_ok
    test    al, al
    jnz     .err
    mov     edi, asm_token
.find_end:
    cmp     byte [edi], 0
    je      .append_space
    inc     edi
    jmp     .find_end
.append_space:
    mov     byte [edi], ' '
    inc     edi
    
    call    get_token
    cmp     byte [asm_token], 0
    je      .err
    
    push    esi
    
    mov     edi, asm_token
.find_end2:
    cmp     byte [edi], 0
    je      .append_space2
    inc     edi
    jmp     .find_end2
.append_space2:
    mov     byte [edi], ' '
    push    edi
    inc     edi
    
    call    get_token
    
    mov     ebx, asm_3word_table
    call    search_table
    jnc     .found_3word
    
    pop     edi
    mov     byte [edi], 0
    pop     esi
    
    mov     ebx, asm_2word_table
    call    search_table
    jnc     .found
    jmp     parse_alu_reg_imm

.found_3word:
    pop     edi
    pop     esi
    mov     [asm_bytes], al
    test    ah, ah
    jz      .found_3word_1byte
    mov     [asm_bytes+1], ah
    mov     word [asm_len], 2
    clc
    ret
.found_3word_1byte:
    mov     word [asm_len], 1
    clc
    ret

.reg_reg_ok:
    clc
    ret

.found_rel8:
    mov     [asm_bytes], al
    call    skip_whitespace
    call    is_eol
    jc      .err

    cmp     byte [asm_bytes], 0EBh
    jne     .rel8_check_addr

    ; For JMP, check if operand is reg16
    push    esi
    call    parse_asm_reg
    jc      .jmp_not_reg
    cmp     ah, 2
    jne     .jmp_not_reg_restore
    push    eax
    call    skip_whitespace
    call    is_eol
    pop     eax
    jnc     .jmp_not_reg_restore
    add     esp, 4
    mov     byte [asm_bytes], 0FFh
    add     al, 0E0h
    mov     byte [asm_bytes+1], al
    mov     word [asm_len], 2
    clc
    ret

.jmp_not_reg_restore:
    pop     esi
    jmp     .rel8_check_addr

.jmp_not_reg:
    pop     esi

.rel8_check_addr:
    call    parse_hex
    jc      .err
    mov     bx, ax

    call    skip_whitespace
    cmp     byte [esi], ':'
    jne     .rel8_no_colon

    ; Colon is ONLY valid for JMP (0EBh)
    cmp     byte [asm_bytes], 0EBh
    jne     .err

    ; Far jump: EA off seg (5 bytes)
    inc     esi
    call    skip_whitespace
    call    parse_hex
    jc      .err
    push    ax
    call    skip_whitespace
    call    is_eol
    pop     ax
    jnc     .err
    mov     byte [asm_bytes], 0EAh
    mov     [asm_bytes+1], al
    mov     [asm_bytes+2], ah
    mov     [asm_bytes+3], bl
    mov     [asm_bytes+4], bh
    mov     word [asm_len], 5
    clc
    ret

.rel8_no_colon:
    call    is_eol
    jnc     .err

    mov     ax, bx
    sub     ax, [asm_off]
    sub     ax, 2
    movsx   dx, al
    cmp     dx, ax
    jne     .rel8_disp_overflow

    mov     [asm_bytes+1], al
    mov     word [asm_len], 2
    clc
    ret

.rel8_disp_overflow:
    cmp     byte [asm_bytes], 0EBh
    jne     .err

    ; Near jump: E9 disp16 (3 bytes)
    mov     ax, bx
    sub     ax, [asm_off]
    sub     ax, 3
    mov     byte [asm_bytes], 0E9h
    mov     [asm_bytes+1], al
    mov     [asm_bytes+2], ah
    mov     word [asm_len], 3
    clc
    ret

.found:
    mov     [asm_bytes], al
    mov     word [asm_len], INSN_LEN_1
    mov     [asm_arg_size], ah
    
    test    ah, ah
    jnz     .has_args
    call    skip_whitespace
    call    is_eol
    jnc     .check_ret_imm
    clc
    ret

.check_ret_imm:
    cmp     byte [asm_bytes], 0C3h
    je      .do_ret_imm
    cmp     byte [asm_bytes], 0CBh
    je      .do_retf_imm
    jmp     .err

.do_ret_imm:
    mov     byte [asm_bytes], 0C2h
    mov     byte [asm_arg_size], 2
    jmp     .has_immediate

.do_retf_imm:
    mov     byte [asm_bytes], 0CAh
    mov     byte [asm_arg_size], 2
    jmp     .has_immediate

.has_args:
    cmp     ah, 2
    jbe     .has_immediate

    call    skip_whitespace
    call    is_eol
    jnc     .err

    mov     [asm_bytes+1], ah
    mov     word [asm_len], INSN_LEN_2
    clc
    ret

.has_immediate:
    call    skip_whitespace
    cmp     byte [esi], ','
    jne     .no_imm_comma
    inc     esi
    call    skip_whitespace
.no_imm_comma:
    call    parse_hex
    jc      .err

    push    eax
    call    skip_whitespace
    call    is_eol
    pop     eax
    jnc     .err
    
    mov     dl, [asm_arg_size]
    cmp     dl, 1
    je      .arg_byte
    
    mov     [asm_bytes+1], al
    mov     [asm_bytes+2], ah
    mov     word [asm_len], 3
    clc
    ret
    
.arg_byte:
    test    ah, ah
    jnz     .err
    cmp     byte [asm_bytes], 0CDh
    jne     .not_int3
    cmp     al, 3
    jne     .not_int3
    mov     byte [asm_bytes], 0CCh
    mov     word [asm_len], 1
    clc
    ret
.not_int3:
    mov     [asm_bytes+1], al
    mov     word [asm_len], 2
.ok:
    clc
    ret
    
.err:
    stc
    ret

parse_alu_reg_imm:
    mov     edi, asm_token
.pari_find_space:
    mov     al, [edi]
    test    al, al
    jz      .pari_err
    cmp     al, ' '
    je      .pari_found_space
    inc     edi
    jmp     .pari_find_space

.pari_found_space:
    mov     byte [edi], 0
    inc     edi

    mov     ebx, mem_mnem_table
.pari_search_mnem:
    cmp     byte [ebx], 0
    je      .pari_err
    mov     edx, ebx
    mov     ecx, asm_token
.pari_cmp_mnem:
    mov     al, [ecx]
    mov     ah, [edx]
    cmp     al, ah
    jne     .pari_next_mnem
    test    al, al
    jz      .pari_found_mnem
    inc     ecx
    inc     edx
    jmp     .pari_cmp_mnem

.pari_next_mnem:
    cmp     byte [ebx], 0
    je      .pari_skip_null
    inc     ebx
    jmp     .pari_next_mnem
.pari_skip_null:
    add     ebx, 3
    jmp     .pari_search_mnem

.pari_found_mnem:
    mov     cl, [edx+1]
    cmp     cl, 0
    je      .pari_type_ok
    cmp     cl, 2
    jne     .pari_err
.pari_type_ok:
    mov     ch, [edx+2]

    push    esi
    push    ecx
    mov     esi, edi
    call    parse_asm_reg
    pop     ecx
    pop     esi
    jc      .pari_err

    push    eax
    push    ecx

    call    skip_whitespace
    cmp     byte [esi], ','
    jne     .pari_no_comma
    inc     esi
    call    skip_whitespace
.pari_no_comma:
    call    parse_hex
    pop     ecx
    pop     edx
    jc      .pari_err

    push    ax
    push    edx
    push    ecx
    call    skip_whitespace
    call    is_eol
    pop     ecx
    pop     edx
    pop     bx
    jnc     .pari_err

    movzx   eax, ch
    shl     al, 3
    or      al, 0C0h
    or      al, dl
    mov     byte [asm_bytes+1], al

    cmp     cl, 2
    je      .pari_test

    cmp     dh, 1
    jne     .pari_alu_word

    test    bh, bh
    jnz     .pari_err
    mov     byte [asm_bytes], 80h
    mov     byte [asm_bytes+2], bl
    mov     word [asm_len], 3
    clc
    ret

.pari_alu_word:
    movsx   ax, bl
    cmp     ax, bx
    jne     .pari_alu_imm16

    mov     byte [asm_bytes], 83h
    mov     byte [asm_bytes+2], bl
    mov     word [asm_len], 3
    clc
    ret

.pari_alu_imm16:
    mov     byte [asm_bytes], 81h
    mov     byte [asm_bytes+2], bl
    mov     byte [asm_bytes+3], bh
    mov     word [asm_len], 4
    clc
    ret

.pari_test:
    cmp     dh, 1
    jne     .pari_test_word
    test    bh, bh
    jnz     .pari_err
    mov     byte [asm_bytes], 0F6h
    mov     byte [asm_bytes+2], bl
    mov     word [asm_len], 3
    clc
    ret

.pari_test_word:
    mov     byte [asm_bytes], 0F7h
    mov     byte [asm_bytes+2], bl
    mov     byte [asm_bytes+3], bh
    mov     word [asm_len], 4
    clc
    ret

.pari_err:
    stc
    ret

get_token:
    call    skip_whitespace
.loop:
    call    is_eol
    jc      .done
    mov     al, [esi]
    cmp     al, ' '
    je      .done
    cmp     al, 9
    je      .done
    cmp     al, ','
    je      .done
    
    cmp     al, 'A'
    jb      .store
    cmp     al, 'Z'
    ja      .store
    add     al, 20h
.store:
    cmp     edi, asm_token + ASM_TOKEN_SIZE - 1
    jae     .skip_char
    stosb
.skip_char:
    inc     esi
    jmp     .loop
.done:
    cmp     edi, asm_token + ASM_TOKEN_SIZE - 1
    jbe     .null_ok
    mov     edi, asm_token + ASM_TOKEN_SIZE - 1
.null_ok:
    mov     byte [edi], 0
    ret

search_table:
.loop:
    mov     al, [ebx]
    test    al, al
    jz      .not_found
    
    mov     edi, asm_token
    mov     edx, ebx
.cmp:
    mov     cl, [edi]
    mov     ch, [edx]
    cmp     cl, ch
    jne     .next
    test    cl, cl
    jz      .match
    inc     edi
    inc     edx
    jmp     .cmp
    
.next:
    mov     al, [ebx]
    test    al, al
    jz      .skip_done
    inc     ebx
    jmp     .next
.skip_done:
    add     ebx, 3
    jmp     .loop
    
.match:
    inc     edx
    mov     al, [edx]
    mov     ah, [edx+1]
    clc
    ret
    
.not_found:
    stc
    ret

