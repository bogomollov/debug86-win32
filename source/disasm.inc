cmd_unassemble:
    mov     esi, [cmd_ptr]
    mov     dword [unasm_len], UNASM_DEFAULT_LEN

    call    skip_whitespace
    call    is_eol
    jc      .do_it

    call    parse_address_cs
    jc      print_error_and_ret
    mov     [unasm_seg], ax
    mov     [unasm_off], bx
    mov     bp, ax

    mov     dx, bx
    call    skip_whitespace
    call    is_eol
    jc      .do_it

    call    parse_length
    jc      print_error_and_ret
    mov     [unasm_len], ecx

    call    skip_whitespace
    call    is_eol
    jnc     print_error_and_ret

.do_it:
    mov     byte [ctrl_c_flag], 0
    mov     ax, [unasm_seg]
    mov     bx, [unasm_off]
    call    calc_linear_addr
    mov     ecx, [unasm_len]
    call    check_mem_range
    jc      print_error_and_ret

.unasm_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     .unasm_interrupted

    mov     ecx, [unasm_len]
    test    ecx, ecx
    jz      .done

    mov     ax, [unasm_seg]
    mov     bx, [unasm_off]
    xor     cl, cl
    call    disasm_line
    add     [unasm_off], bx

    mov     eax, [unasm_len]
    movzx   ebx, bx
    sub     eax, ebx
    jbe     .done
    mov     [unasm_len], eax
    jmp     .unasm_loop

.unasm_interrupted:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer

.done:
    ret

disasm_line:
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp
    sub     esp, 16

    movzx   edx, ax
    mov     [esp+0], edx
    movzx   edx, bx
    mov     [esp+4], edx
    movzx   edx, cl
    mov     [esp+8], edx
    mov     dword [esp+12], 1
    mov     dword [dis_is_unary], 0
    mov     dword [dis_is_shift], 0

    mov     edi, line_buffer
    mov     ax, [esp+0]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, [esp+4]
    call    put_hex_word
    mov     al, SPACE
    stosb

    mov     ax, [esp+0]
    mov     bx, [esp+4]
    call    calc_linear_addr
    cmp     eax, MEM_SIZE
    jae     .out_of_mem

    mov     ebp, memory
    add     ebp, eax

    mov     al, [ebp]

    cmp     al, 70h
    jb      .not_dis_jcc
    cmp     al, 7Fh
    jbe     .dis_jcc
.not_dis_jcc:

    cmp     al, 0EBh
    je      .dis_jmp_short
    cmp     al, 0E9h
    je      .dis_jmp_near
    cmp     al, 0E8h
    je      .dis_call_near
    cmp     al, 0E0h
    je      .dis_loopnz
    cmp     al, 0E1h
    je      .dis_loopz
    cmp     al, 0E2h
    je      .dis_loop
    cmp     al, 0E3h
    je      .dis_jcxz

    cmp     al, 40h
    jb      .not_dis_inc
    cmp     al, 47h
    jbe     .dis_inc_r16
.not_dis_inc:

    cmp     al, 50h
    jb      .not_dis_push
    cmp     al, 57h
    jbe     .dis_push_r16
.not_dis_push:

    cmp     al, 58h
    jb      .not_dis_pop
    cmp     al, 5Fh
    jbe     .dis_pop_r16
.not_dis_pop:

    cmp     al, 91h
    jb      .not_dis_xchg_ax
    cmp     al, 97h
    jbe     .dis_xchg_ax_r16
.not_dis_xchg_ax:

    cmp     al, 9Ah
    je      .dis_call_far
    cmp     al, 0EAh
    je      .dis_jmp_far
    cmp     al, 0E6h
    je      .dis_out_imm
    cmp     al, 0E7h
    je      .dis_out_imm
    cmp     al, 0D4h
    je      .dis_aam_aad
    cmp     al, 0D5h
    je      .dis_aam_aad

    call    find_opcode
    jc      .try_dis_modrm


    movzx   ebx, dl
    inc     ebx
    mov     [esp+12], ebx

    mov     eax, ebp
    sub     eax, memory
    add     eax, ebx
    cmp     eax, MEM_SIZE
    jbe     .have_bytes

.not_found:
    mov     dword [esp+12], 1
    mov     al, [ebp]
    call    put_hex_byte

    mov     ecx, 12
    mov     al, SPACE
    rep     stosb

    mov     al, 'D'
    stosb
    mov     al, 'B'
    stosb

    mov     ecx, 6
    mov     al, SPACE
    rep     stosb

    mov     al, [ebp]
    call    put_hex_byte
    jmp     .line_done

.out_of_mem:
    mov     al, '?'
    stosb
    mov     al, '?'
    stosb
    mov     dword [esp+12], 1
    jmp     .write_line

.have_bytes:
    push    esi
    push    edx
    push    ebx
    push    ecx

    mov     esi, ebp
    mov     ecx, ebx
.hex_loop:
    lodsb
    call    put_hex_byte
    dec     ecx
    jnz     .hex_loop

    mov     eax, 14
    sub     eax, ebx
    sub     eax, ebx
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb

    pop     ecx
    pop     ebx
    pop     edx
    pop     esi

.str_loop:
    xor     ecx, ecx
.str_mnem:
    lodsb
    test    al, al
    jz      .str_pad_only
    cmp     al, SPACE
    je      .str_have_ops
    cmp     al, 'a'
    jb      .str_store_m
    cmp     al, 'z'
    ja      .str_store_m
    sub     al, 20h
.str_store_m:
    stosb
    inc     ecx
    jmp     .str_mnem

.str_have_ops:
    mov     eax, 8
    sub     eax, ecx
    jle     .str_ops
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb
.str_ops:
    lodsb
    test    al, al
    jz      .str_done
    cmp     al, 'a'
    jb      .str_store_op
    cmp     al, 'z'
    ja      .str_store_op
    sub     al, 20h
.str_store_op:
    stosb
    jmp     .str_ops

.str_pad_only:
    mov     eax, 8
    sub     eax, ecx
    jle     .str_done
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb
.str_done:
    test    dl, dl
    jz      .line_done

    cmp     dh, 2
    je      .line_done

    cmp     dh, 1
    je      .use_comma
    mov     al, SPACE
    jmp     .put_sep
.use_comma:
    mov     al, COMMA
.put_sep:
    stosb

    cmp     dl, 1
    je      .arg_byte

    mov     al, [ebp+2]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte
    jmp     .line_done

.arg_byte:
    mov     al, [ebp+1]
    call    put_hex_byte

.line_done:
    cmp     dword [esp+8], 0
    jz      .write_line

    ; Memory Operand Preview
    mov     esi, ebp
    xor     edx, edx            ; override segment name (2 chars), 0 = none
    mov     al, [esi]
    cmp     al, 26h
    jne     .res_chk_cs
    mov     edx, 'ES'
    inc     esi
    jmp     .res_got_prefix
.res_chk_cs:
    cmp     al, 2Eh
    jne     .res_chk_ss
    mov     edx, 'CS'
    inc     esi
    jmp     .res_got_prefix
.res_chk_ss:
    cmp     al, 36h
    jne     .res_chk_ds
    mov     edx, 'SS'
    inc     esi
    jmp     .res_got_prefix
.res_chk_ds:
    cmp     al, 3Eh
    jne     .res_chk_ext
    mov     edx, 'DS'
    inc     esi
    jmp     .res_got_prefix
.res_chk_ext:
    cmp     dword [seg_override], 0
    jz      .res_got_prefix
    cmp     dword [seg_override], reg_ES
    jne     .res_ext_cs
    mov     edx, 'ES'
    jmp     .res_got_prefix
.res_ext_cs:
    cmp     dword [seg_override], reg_CS
    jne     .res_ext_ss
    mov     edx, 'CS'
    jmp     .res_got_prefix
.res_ext_ss:
    cmp     dword [seg_override], reg_SS
    jne     .res_ext_ds
    mov     edx, 'SS'
    jmp     .res_got_prefix
.res_ext_ds:
    cmp     dword [seg_override], reg_DS
    jne     .res_got_prefix
    mov     edx, 'DS'
.res_got_prefix:

    mov     al, [esi]

    ; Direct MOV A0..A3
    cmp     al, 0A0h
    jb      .res_not_direct
    cmp     al, 0A3h
    ja      .res_not_direct
    movzx   ebx, word [esi+1]
    mov     cl, al
    and     cl, 1               ; is_word
    test    edx, edx
    jnz     .res_direct_seg
    mov     edx, 'DS'
.res_direct_seg:
    jmp     .res_have_ea

.res_not_direct:
    ; ALU 00..03, 08..0B, 10..13, 18..1B, 20..23, 28..2B, 30..33, 38..3B
    cmp     al, 3Bh
    ja      .res_chk_mov
    mov     ah, al
    and     ah, 07h
    cmp     ah, 3
    ja      .res_no_mem
    mov     cl, al
    and     cl, 1               ; is_word
    jmp     .res_is_modrm

.res_chk_mov:
    cmp     al, 88h
    jb      .res_chk_imm_alu
    cmp     al, 8Bh
    ja      .res_chk_mov_imm
    mov     cl, al
    and     cl, 1               ; is_word
    jmp     .res_is_modrm

.res_chk_mov_imm:
    cmp     al, 0C6h
    je      .res_c6
    cmp     al, 0C7h
    je      .res_c7
    jmp     .res_chk_lea_sreg
.res_c6:
    mov     cl, 0
    jmp     .res_is_modrm
.res_c7:
    mov     cl, 1
    jmp     .res_is_modrm

.res_chk_lea_sreg:
    cmp     al, 8Ch
    jb      .res_chk_test_xchg
    cmp     al, 8Fh
    jbe     .res_modrm_word
    cmp     al, 0C4h
    je      .res_modrm_word
    cmp     al, 0C5h
    je      .res_modrm_word
    jmp     .res_chk_test_xchg
.res_modrm_word:
    mov     cl, 1
    jmp     .res_is_modrm

.res_chk_test_xchg:
    cmp     al, 84h
    jb      .res_chk_f6_f7
    cmp     al, 87h
    ja      .res_chk_f6_f7
    mov     cl, al
    and     cl, 1
    jmp     .res_is_modrm

.res_chk_f6_f7:
    cmp     al, 0F6h
    je      .res_f6
    cmp     al, 0F7h
    je      .res_f7
    cmp     al, 0D0h
    jb      .res_chk_fe_ff
    cmp     al, 0D3h
    jbe     .res_shift
    jmp     .res_chk_fe_ff
.res_shift:
    mov     cl, al
    and     cl, 1
    jmp     .res_is_modrm
.res_f6:
    mov     cl, 0
    jmp     .res_is_modrm
.res_f7:
    mov     cl, 1
    jmp     .res_is_modrm

.res_chk_fe_ff:
    cmp     al, 0FEh
    je      .res_fe
    cmp     al, 0FFh
    je      .res_ff
    jmp     .res_no_mem
.res_fe:
    mov     cl, 0
    jmp     .res_is_modrm
.res_ff:
    mov     cl, 1
    jmp     .res_is_modrm

.res_chk_imm_alu:
    cmp     al, 80h
    jb      .res_no_mem
    cmp     al, 83h
    ja      .res_no_mem
    mov     cl, 0
    cmp     al, 81h
    je      .res_imm_w
    cmp     al, 83h
    je      .res_imm_w
    jmp     .res_is_modrm
.res_imm_w:
    mov     cl, 1

.res_is_modrm:
    mov     ah, [esi+1]         ; modrm byte
    cmp     ah, 0C0h
    jae     .res_no_mem         ; mod == 3 -> not memory!

    push    ecx                 ; [esp]: is_word
    push    edx                 ; [esp+4]: override seg name

    call    decode_modrm_ea
    mov     edx, eax            ; default seg name ('DS' or 'SS')
    pop     eax                 ; override seg name
    test    eax, eax
    jz      .res_default_seg_kept
    mov     edx, eax
.res_default_seg_kept:
    pop     ecx                 ; cl = is_word

.res_have_ea:
    push    ecx                 ; [esp+8]: is_word
    push    edx                 ; [esp+4]: segment name ('DS', 'SS', etc.)
    push    ebx                 ; [esp+0]: offset

    cmp     edx, 'SS'
    je      .res_val_ss
    cmp     edx, 'ES'
    je      .res_val_es
    cmp     edx, 'CS'
    je      .res_val_cs
    mov     ax, word [reg_DS]
    jmp     .res_calc_linear
.res_val_ss:
    mov     ax, word [reg_SS]
    jmp     .res_calc_linear
.res_val_es:
    mov     ax, word [reg_ES]
    jmp     .res_calc_linear
.res_val_cs:
    mov     ax, word [reg_CS]

.res_calc_linear:
    call    calc_linear_addr
    cmp     eax, MEM_SIZE
    jae     .res_skip_preview
    cmp     byte [esp+8], 1     ; is_word?
    jne     .res_read_val
    cmp     eax, MEM_SIZE - 1
    jae     .res_skip_preview

.res_read_val:
    cmp     byte [esp+8], 1
    jne     .res_byte_val
    movzx   esi, word [memory + eax]
    jmp     .res_align_col
.res_byte_val:
    movzx   esi, byte [memory + eax]

.res_align_col:
    mov     eax, edi
    sub     eax, line_buffer
    cmp     eax, 55
    jae     .res_pad_one
    mov     ecx, 55
    sub     ecx, eax
    mov     al, SPACE
    rep     stosb
    jmp     .res_output_str
.res_pad_one:
    mov     al, SPACE
    stosb

.res_output_str:
    pop     ebx                 ; offset
    pop     edx                 ; segment name
    pop     ecx                 ; is_word

    mov     ax, dx
    stosw
    mov     al, COLON
    stosb
    mov     ax, bx
    call    put_hex_word
    mov     al, '='
    stosb
    test    cl, cl
    jnz     .res_val_w
    mov     eax, esi
    call    put_hex_byte
    jmp     .write_line
.res_val_w:
    mov     ax, si
    call    put_hex_word
    jmp     .write_line

.res_skip_preview:
    pop     ebx
    pop     edx
    pop     ecx
    jmp     .write_line

.res_no_mem:

.write_line:
    mov     al, CR
    stosb
    mov     al, LF
    stosb

    call    print_line_buffer

    mov     ebx, [esp+12]
    add     esp, 16
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    ret

.try_dis_modrm:
    mov     al, [ebp]

    ; Check for segment override or instruction prefix byte at [ebp]
    cmp     al, 26h
    je      .dis_pref_es
    cmp     al, 2Eh
    je      .dis_pref_cs
    cmp     al, 36h
    je      .dis_pref_ss
    cmp     al, 3Eh
    je      .dis_pref_ds
    cmp     al, 0F3h
    je      .dis_pref_rep
    cmp     al, 0F2h
    je      .dis_pref_repne
    cmp     al, 0F0h
    je      .dis_pref_lock
    jmp     .dis_check_direct

.dis_pref_es:
    mov     ax, 'ES'
    jmp     .dis_emit_prefix
.dis_pref_cs:
    mov     ax, 'CS'
    jmp     .dis_emit_prefix
.dis_pref_ss:
    mov     ax, 'SS'
    jmp     .dis_emit_prefix
.dis_pref_ds:
    mov     ax, 'DS'
.dis_emit_prefix:
    mov     dword [esp+12], 1
    push    eax
    mov     al, [ebp]
    call    put_hex_byte
    mov     ecx, 12
    mov     al, SPACE
    rep     stosb
    pop     eax
    mov     [edi], ax
    add     edi, 2
    mov     al, COLON
    stosb
    jmp     .line_done

.dis_pref_rep:
    mov     dword [esp+12], 1
    mov     al, [ebp]
    call    put_hex_byte
    mov     ecx, 12
    mov     al, SPACE
    rep     stosb
    mov     byte [edi], 'R'
    mov     byte [edi+1], 'E'
    mov     byte [edi+2], 'P'
    add     edi, 3
    jmp     .line_done

.dis_pref_repne:
    mov     dword [esp+12], 1
    mov     al, [ebp]
    call    put_hex_byte
    mov     ecx, 12
    mov     al, SPACE
    rep     stosb
    mov     dword [edi], 'REPN'
    mov     byte [edi+4], 'E'
    add     edi, 5
    jmp     .line_done

.dis_pref_lock:
    mov     dword [esp+12], 1
    mov     al, [ebp]
    call    put_hex_byte
    mov     ecx, 12
    mov     al, SPACE
    rep     stosb
    mov     dword [edi], 'LOCK'
    add     edi, 4
    jmp     .line_done

.dis_check_direct:
    ; Check for direct memory moves: A0h..A3h
    cmp     al, 0A0h
    jb      .dis_not_direct
    cmp     al, 0A3h
    ja      .dis_not_direct

    ; Length = 3
    mov     eax, ebp
    sub     eax, memory
    add     eax, 3
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     dword [esp+12], 3

    mov     al, [ebp]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte
    mov     al, [ebp+2]
    call    put_hex_byte

    mov     ecx, 8
    mov     al, SPACE
    rep     stosb

    mov     al, 'M'
    stosb
    mov     al, 'O'
    stosb
    mov     al, 'V'
    stosb
    mov     ecx, 5
    mov     al, SPACE
    rep     stosb

    mov     al, [ebp]
    cmp     al, 0A0h
    je      .dis_dm_al_from_mem
    cmp     al, 0A1h
    je      .dis_dm_ax_from_mem
    cmp     al, 0A2h
    je      .dis_dm_mem_from_al
    ; A3h: MOV [disp], AX
    mov     al, '['
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    mov     al, ']'
    stosb
    mov     al, COMMA
    stosb
    mov     ax, 'AX'
    stosw
    jmp     .line_done

.dis_dm_mem_from_al:
    mov     al, '['
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    mov     al, ']'
    stosb
    mov     al, COMMA
    stosb
    mov     ax, 'AL'
    stosw
    jmp     .line_done

.dis_dm_al_from_mem:
    mov     ax, 'AL'
    stosw
    mov     al, COMMA
    stosb
    mov     al, '['
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    mov     al, ']'
    stosb
    jmp     .line_done

.dis_dm_ax_from_mem:
    mov     ax, 'AX'
    stosw
    mov     al, COMMA
    stosb
    mov     al, '['
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    mov     al, ']'
    stosb
    jmp     .line_done

.dis_not_direct:
    mov     dword [dis_is_unary], 0
    mov     dword [dis_is_shift], 0
    ; Check ModR/M opcodes
    cmp     al, 3Bh
    ja      .dis_chk_mov
    mov     ah, al
    and     ah, 07h
    cmp     ah, 3
    ja      .not_found
    ; ALU 00..03, 08..0B, 10..13, 18..1B, 20..23, 28..2B, 30..33, 38..3B
    movzx   edx, al
    and     edx, 1
    mov     [dis_is_word], edx
    movzx   edx, al
    shr     edx, 1
    and     edx, 1
    mov     [dis_dir], edx
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    movzx   edx, al
    shr     edx, 3
    and     edx, 7
    shl     edx, 2
    lea     edx, [alu_op_names + edx]
    mov     [dis_mnem_ptr], edx
    jmp     .dis_have_modrm_params

.dis_chk_mov:
    cmp     al, 88h
    jb      .dis_chk_imm_alu
    cmp     al, 8Bh
    ja      .dis_chk_mov_imm
    ; MOV 88..8B
    movzx   edx, al
    and     edx, 1
    mov     [dis_is_word], edx
    movzx   edx, al
    shr     edx, 1
    and     edx, 1
    mov     [dis_dir], edx
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_mov
    jmp     .dis_have_modrm_params

.dis_chk_mov_imm:
    cmp     al, 0C6h
    je      .dis_mov_c6
    cmp     al, 0C7h
    je      .dis_mov_c7
    jmp     .dis_chk_sreg
.dis_mov_c6:
    mov     dword [dis_is_word], 0
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 1
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_mov
    jmp     .dis_have_modrm_params
.dis_mov_c7:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 2
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_mov
    jmp     .dis_have_modrm_params

.dis_chk_sreg:
    cmp     al, 8Ch
    je      .dis_mov_to_rm_sreg
    cmp     al, 8Eh
    je      .dis_mov_to_sreg_rm
    cmp     al, 8Fh
    je      .dis_pop_rm16
    jmp     .dis_chk_lea
.dis_pop_rm16:
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    jnz     .not_found
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_is_unary], 1
    mov     dword [dis_mnem_ptr], str_mnem_pop
    jmp     .dis_have_modrm_params
.dis_mov_to_rm_sreg:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 1
    mov     dword [dis_mnem_ptr], str_mnem_mov
    jmp     .dis_have_modrm_params
.dis_mov_to_sreg_rm:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 1
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 1
    mov     dword [dis_mnem_ptr], str_mnem_mov
    jmp     .dis_have_modrm_params

.dis_chk_lea:
    cmp     al, 8Dh
    jne     .dis_chk_test_xchg
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 1
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_lea
    jmp     .dis_have_modrm_params

.dis_chk_test_xchg:
    cmp     al, 84h
    je      .dis_op_test_b
    cmp     al, 85h
    je      .dis_op_test_w
    cmp     al, 86h
    je      .dis_op_xchg_b
    cmp     al, 87h
    je      .dis_op_xchg_w
    cmp     al, 0C4h
    je      .dis_op_les
    cmp     al, 0C5h
    je      .dis_op_lds
    cmp     al, 0D0h
    jb      .dis_chk_f6_f7
    cmp     al, 0D3h
    jbe     .dis_op_shift
.dis_chk_f6_f7:
    cmp     al, 0F6h
    je      .dis_op_f6
    cmp     al, 0F7h
    je      .dis_op_f7
    cmp     al, 0FEh
    je      .dis_op_fe
    cmp     al, 0FFh
    je      .dis_op_ff
    jmp     .not_found
.dis_op_test_b:
    mov     dword [dis_is_word], 0
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_test
    jmp     .dis_have_modrm_params
.dis_op_test_w:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_test
    jmp     .dis_have_modrm_params
.dis_op_xchg_b:
    mov     dword [dis_is_word], 0
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_xchg
    jmp     .dis_have_modrm_params
.dis_op_xchg_w:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_xchg
    jmp     .dis_have_modrm_params
.dis_op_les:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 1
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_les
    jmp     .dis_have_modrm_params
.dis_op_lds:
    mov     dword [dis_is_word], 1
    mov     dword [dis_dir], 1
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_mnem_ptr], str_mnem_lds
    jmp     .dis_have_modrm_params

.dis_op_shift:
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    cmp     edx, 6
    je      .not_found
    mov     eax, [shift_mnems + edx*4]
    test    eax, eax
    jz      .not_found
    mov     [dis_mnem_ptr], eax
    mov     al, [ebp]
    movzx   edx, al
    and     edx, 1
    mov     [dis_is_word], edx
    movzx   edx, al
    shr     edx, 1
    and     edx, 1
    inc     edx
    mov     [dis_is_shift], edx
    mov     dword [dis_imm_len], 0
    mov     dword [dis_dir], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_is_unary], 0
    jmp     .dis_have_modrm_params

.dis_op_f6:
    mov     dword [dis_is_word], 0
    jmp     .dis_f6_f7_common
.dis_op_f7:
    mov     dword [dis_is_word], 1
.dis_f6_f7_common:
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    mov     eax, [f6_f7_mnems + edx*4]
    test    eax, eax
    jz      .not_found
    mov     [dis_mnem_ptr], eax
    mov     dword [dis_dir], 0
    mov     dword [dis_is_sreg], 0
    test    edx, edx
    jnz     .dis_f67_unary
    mov     eax, [dis_is_word]
    inc     eax
    mov     [dis_imm_len], eax
    mov     dword [dis_is_unary], 0
    jmp     .dis_have_modrm_params
.dis_f67_unary:
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_unary], 2
    jmp     .dis_have_modrm_params

.dis_op_fe:
    mov     dword [dis_is_word], 0
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    cmp     edx, 1
    ja      .not_found
    mov     eax, [fe_ff_mnems + edx*4]
    mov     [dis_mnem_ptr], eax
    mov     dword [dis_dir], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_imm_len], 0
    mov     dword [dis_is_unary], 2
    jmp     .dis_have_modrm_params

.dis_op_ff:
    mov     dword [dis_is_word], 1
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    cmp     edx, 6
    ja      .not_found
    mov     eax, [fe_ff_mnems + edx*4]
    test    eax, eax
    jz      .not_found
    mov     [dis_mnem_ptr], eax
    mov     dword [dis_dir], 0
    mov     dword [dis_is_sreg], 0
    mov     dword [dis_imm_len], 0
    cmp     edx, 6
    je      .dis_ff_push
    cmp     edx, 3
    je      .dis_ff_far
    cmp     edx, 5
    je      .dis_ff_far
    mov     dword [dis_is_unary], 2
    jmp     .dis_have_modrm_params
.dis_ff_far:
    cmp     byte [ebp+1], 0C0h
    jae     .not_found
    mov     dword [dis_is_unary], 3
    jmp     .dis_have_modrm_params
.dis_ff_push:
    mov     dword [dis_is_unary], 1
    jmp     .dis_have_modrm_params

.dis_chk_imm_alu:
    cmp     al, 80h
    jb      .not_found
    cmp     al, 83h
    ja      .dis_chk_test_xchg
    mov     dword [dis_dir], 0
    mov     dword [dis_is_sreg], 0
    cmp     al, 80h
    je      .dis_alu_imm_80
    cmp     al, 81h
    je      .dis_alu_imm_81
    cmp     al, 82h
    je      .dis_alu_imm_80
    ; 83h: is_word = 1, imm_len = 1
    mov     dword [dis_is_word], 1
    mov     dword [dis_imm_len], 1
    jmp     .dis_imm_alu_mnem
.dis_alu_imm_80:
    mov     dword [dis_is_word], 0
    mov     dword [dis_imm_len], 1
    jmp     .dis_imm_alu_mnem
.dis_alu_imm_81:
    mov     dword [dis_is_word], 1
    mov     dword [dis_imm_len], 2
.dis_imm_alu_mnem:
    movzx   edx, byte [ebp+1]
    shr     edx, 3
    and     edx, 7
    shl     edx, 2
    lea     edx, [alu_op_names + edx]
    mov     [dis_mnem_ptr], edx

.dis_have_modrm_params:
    movzx   eax, byte [ebp+1]   ; modrm byte
    mov     ecx, eax
    shr     ecx, 6              ; mod
    and     eax, 7              ; rm
    xor     edx, edx
    test    ecx, ecx
    jnz     .dis_mod1_chk
    cmp     eax, 6
    jne     .dis_got_disp_len
    mov     edx, 2
    jmp     .dis_got_disp_len
.dis_mod1_chk:
    cmp     ecx, 1
    jne     .dis_mod2_chk
    mov     edx, 1
    jmp     .dis_got_disp_len
.dis_mod2_chk:
    cmp     ecx, 2
    jne     .dis_got_disp_len
    mov     edx, 2
.dis_got_disp_len:
    mov     [dis_disp_len], edx

    mov     eax, 2
    add     eax, edx
    add     eax, [dis_imm_len]
    mov     [esp+12], eax       ; insn_len

    mov     edx, ebp
    sub     edx, memory
    add     edx, eax
    cmp     edx, MEM_SIZE
    ja      .not_found

    ; Output hex bytes:
    mov     esi, ebp
    mov     ecx, [esp+12]
.dis_hex_loop:
    lodsb
    call    put_hex_byte
    loop    .dis_hex_loop

    mov     eax, 14
    mov     ecx, [esp+12]
    sub     eax, ecx
    sub     eax, ecx
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb

    ; Output mnemonic:
    mov     esi, [dis_mnem_ptr]
    xor     ecx, ecx
.dis_mnem_loop:
    lodsb
    test    al, al
    jz      .dis_mnem_pad
    cmp     al, SPACE
    je      .dis_mnem_pad
    stosb
    inc     ecx
    cmp     ecx, 4
    jb      .dis_mnem_loop
.dis_mnem_pad:
    mov     eax, 8
    sub     eax, ecx
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb

    ; Output operands:
    cmp     dword [dis_is_shift], 0
    jnz     .dis_ops_shift

    cmp     dword [dis_is_unary], 0
    jz      .dis_not_unary
    call    .dm_write_rm
    jmp     .line_done

.dis_ops_shift:
    call    .dm_write_rm
    mov     al, COMMA
    stosb
    cmp     dword [dis_is_shift], 2
    je      .dis_shift_cl
    mov     al, '1'
    stosb
    jmp     .line_done
.dis_shift_cl:
    mov     ax, 'CL'
    stosw
    jmp     .line_done

.dis_not_unary:
    cmp     dword [dis_imm_len], 0
    jnz     .dis_ops_rm_imm

    cmp     dword [dis_dir], 1
    je      .dis_ops_reg_rm

    ; dir == 0: r/m, reg
    call    .dm_write_rm
    mov     al, COMMA
    stosb
    call    .dm_write_reg
    jmp     .line_done

.dis_ops_reg_rm:
    call    .dm_write_reg
    mov     al, COMMA
    stosb
    call    .dm_write_rm
    jmp     .line_done

.dis_ops_rm_imm:
    call    .dm_write_rm
    mov     al, COMMA
    stosb
    mov     edx, 2
    add     edx, [dis_disp_len]
    cmp     dword [dis_imm_len], 1
    je      .dis_ops_imm8
    mov     ax, word [ebp + edx]
    call    put_hex_word
    jmp     .line_done
.dis_ops_imm8:
    mov     al, byte [ebp + edx]
    cmp     dword [dis_is_word], 1
    jne     .dis_imm8_unsigned
    cmp     al, 0
    jge     .dis_imm8_pos
    mov     byte [edi], '-'
    inc     edi
    neg     al
    call    put_hex_byte
    jmp     .line_done
.dis_imm8_pos:
    mov     byte [edi], '+'
    inc     edi
    call    put_hex_byte
    jmp     .line_done
.dis_imm8_unsigned:
    call    put_hex_byte
    jmp     .line_done

.dm_write_reg:
    movzx   eax, byte [ebp+1]
    shr     eax, 3
    and     eax, 7
    cmp     dword [dis_is_sreg], 1
    jne     .dm_not_sreg
    and     eax, 3
    lea     edx, [sreg_names + eax*2]
    mov     ax, [edx]
    stosw
    ret
.dm_not_sreg:
    cmp     dword [dis_is_word], 1
    jne     .dm_reg8
    lea     edx, [op_reg16_names + eax*2]
    mov     ax, [edx]
    stosw
    ret
.dm_reg8:
    lea     edx, [op_reg8_names + eax*2]
    mov     ax, [edx]
    stosw
    ret

.dm_write_rm:
    movzx   eax, byte [ebp+1]
    mov     ecx, eax
    shr     ecx, 6              ; mod
    and     eax, 7              ; rm
    cmp     ecx, 3
    jne     .dm_rm_mem
    cmp     dword [dis_is_word], 1
    jne     .dm_rm_r8
    lea     edx, [op_reg16_names + eax*2]
    mov     ax, [edx]
    stosw
    ret
.dm_rm_r8:
    lea     edx, [op_reg8_names + eax*2]
    mov     ax, [edx]
    stosw
    ret

.dm_rm_mem:
    cmp     dword [dis_is_unary], 3
    je      .dm_print_far_prefix
    cmp     dword [dis_imm_len], 0
    jnz     .dm_print_size_prefix
    cmp     dword [dis_is_unary], 2
    je      .dm_print_size_prefix
    cmp     dword [dis_is_shift], 0
    jnz     .dm_print_size_prefix
    jmp     .dm_no_size_spec

.dm_print_far_prefix:
    mov     dword [edi], 'FAR '
    add     edi, 4
    jmp     .dm_no_size_spec

.dm_print_size_prefix:
    cmp     dword [dis_is_word], 1
    jne     .dm_spec_b
    mov     eax, 'WORD'
    stosd
    mov     al, SPACE
    stosb
    mov     ax, 'PT'
    stosw
    mov     al, 'R'
    stosb
    mov     al, SPACE
    stosb
    jmp     .dm_no_size_spec
.dm_spec_b:
    mov     eax, 'BYTE'
    stosd
    mov     al, SPACE
    stosb
    mov     ax, 'PT'
    stosw
    mov     al, 'R'
    stosb
    mov     al, SPACE
    stosb

.dm_no_size_spec:
    movzx   eax, byte [ebp+1]
    mov     ecx, eax
    shr     ecx, 6              ; mod
    and     eax, 7              ; rm
    mov     byte [edi], '['
    inc     edi
    test    ecx, ecx
    jnz     .dm_mem_has_base
    cmp     eax, 6
    jne     .dm_mem_has_base
    ; mod == 0, rm == 6: direct address
    mov     ax, word [ebp+2]
    call    put_hex_word
    mov     byte [edi], ']'
    inc     edi
    ret

.dm_mem_has_base:
    lea     esi, [modrm_base_names + eax*8]
.dm_copy_base_chars:
    lodsb
    test    al, al
    jz      .dm_base_copied
    stosb
    jmp     .dm_copy_base_chars
.dm_base_copied:
    cmp     ecx, 1
    jne     .dm_disp_word_chk
    mov     al, byte [ebp+2]
    cmp     al, 0
    jge     .dm_disp_byte_pos
    mov     byte [edi], '-'
    inc     edi
    neg     al
    call    put_hex_byte
    jmp     .dm_close_rm_bracket
.dm_disp_byte_pos:
    mov     byte [edi], '+'
    inc     edi
    call    put_hex_byte
    jmp     .dm_close_rm_bracket
.dm_disp_word_chk:
    cmp     ecx, 2
    jne     .dm_close_rm_bracket
    mov     byte [edi], '+'
    inc     edi
    mov     ax, word [ebp+2]
    call    put_hex_word
.dm_close_rm_bracket:
    mov     byte [edi], ']'
    inc     edi
    ret

.put_mnem_padded:
    push    eax
    push    ecx
    xor     ecx, ecx
.pmp_loop:
    lodsb
    test    al, al
    jz      .pmp_pad
    cmp     al, SPACE
    je      .pmp_pad
    stosb
    inc     ecx
    jmp     .pmp_loop
.pmp_pad:
    mov     eax, 8
    sub     eax, ecx
    mov     ecx, eax
    mov     al, SPACE
    rep     stosb
    pop     ecx
    pop     eax
    ret

.dis_jcc:
    movzx   eax, byte [ebp]
    sub     eax, 70h
    shl     eax, 2
    lea     edx, [jcc_names + eax]
    jmp     .dis_rel8_common

.dis_jmp_short:
    mov     edx, dis_str_jmp
    jmp     .dis_rel8_common

.dis_loopnz:
    mov     edx, dis_str_loopnz
    jmp     .dis_rel8_common

.dis_loopz:
    mov     edx, dis_str_loopz
    jmp     .dis_rel8_common

.dis_loop:
    mov     edx, dis_str_loop
    jmp     .dis_rel8_common

.dis_jcxz:
    mov     edx, dis_str_jcxz
    jmp     .dis_rel8_common

.dis_rel8_common:
    mov     dword [esp+12], 2
    mov     eax, ebp
    sub     eax, memory
    add     eax, 2
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     al, [ebp]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte

    mov     ecx, 10
    mov     al, SPACE
    rep     stosb

    mov     esi, edx
    call    .put_mnem_padded

    movsx   eax, byte [ebp+1]
    add     ax, [esp+4]
    add     ax, 2
    call    put_hex_word
    jmp     .line_done

.dis_jmp_near:
    mov     edx, dis_str_jmp
    jmp     .dis_near_common

.dis_call_near:
    mov     edx, dis_str_call
    jmp     .dis_near_common

.dis_near_common:
    mov     dword [esp+12], 3
    mov     eax, ebp
    sub     eax, memory
    add     eax, 3
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     al, [ebp]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte
    mov     al, [ebp+2]
    call    put_hex_byte

    mov     ecx, 8
    mov     al, SPACE
    rep     stosb

    mov     esi, edx
    call    .put_mnem_padded

    mov     ax, word [ebp+1]
    add     ax, [esp+4]
    add     ax, 3
    call    put_hex_word
    jmp     .line_done

.dis_inc_r16:
    mov     edx, dis_str_inc
    jmp     .dis_r16_unary_common

.dis_push_r16:
    mov     edx, dis_str_push
    jmp     .dis_r16_unary_common

.dis_pop_r16:
    mov     edx, dis_str_pop
    jmp     .dis_r16_unary_common

.dis_r16_unary_common:
    mov     dword [esp+12], 1
    mov     al, [ebp]
    call    put_hex_byte

    mov     ecx, 12
    mov     al, SPACE
    rep     stosb

    mov     esi, edx
    call    .put_mnem_padded

    movzx   eax, byte [ebp]
    and     eax, 7
    shl     eax, 1
    lea     esi, [op_reg16_names + eax]
    lodsw
    stosw
    jmp     .line_done

.dis_xchg_ax_r16:
    mov     dword [esp+12], 1
    mov     al, [ebp]
    call    put_hex_byte

    mov     ecx, 12
    mov     al, SPACE
    rep     stosb

    mov     al, 'X'
    stosb
    mov     al, 'C'
    stosb
    mov     al, 'H'
    stosb
    mov     al, 'G'
    stosb

    mov     ecx, 4
    mov     al, SPACE
    rep     stosb

    mov     ax, 'AX'
    stosw
    mov     al, COMMA
    stosb

    movzx   eax, byte [ebp]
    sub     eax, 90h
    shl     eax, 1
    lea     esi, [op_reg16_names + eax]
    lodsw
    stosw
    jmp     .line_done

.dis_call_far:
    mov     edx, dis_str_call
    jmp     .dis_far_common

.dis_jmp_far:
    mov     edx, dis_str_jmp
    jmp     .dis_far_common

.dis_far_common:
    mov     dword [esp+12], 5
    mov     eax, ebp
    sub     eax, memory
    add     eax, 5
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     esi, ebp
    mov     ecx, 5
.dis_far_hex:
    lodsb
    call    put_hex_byte
    loop    .dis_far_hex

    mov     ecx, 4
    mov     al, SPACE
    rep     stosb

    mov     esi, edx
    call    .put_mnem_padded

    mov     ax, word [ebp+3]
    call    put_hex_word
    mov     al, COLON
    stosb
    mov     ax, word [ebp+1]
    call    put_hex_word
    jmp     .line_done

.dis_out_imm:
    mov     dword [esp+12], 2
    mov     eax, ebp
    sub     eax, memory
    add     eax, 2
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     al, [ebp]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte

    mov     ecx, 10
    mov     al, SPACE
    rep     stosb

    mov     al, 'O'
    stosb
    mov     al, 'U'
    stosb
    mov     al, 'T'
    stosb
    mov     ecx, 5
    mov     al, SPACE
    rep     stosb

    mov     al, [ebp+1]
    call    put_hex_byte
    mov     al, COMMA
    stosb
    cmp     byte [ebp], 0E7h
    je      .dis_out_ax
    mov     ax, 'AL'
    stosw
    jmp     .line_done
.dis_out_ax:
    mov     ax, 'AX'
    stosw
    jmp     .line_done

.dis_aam_aad:
    mov     dword [esp+12], 2
    mov     eax, ebp
    sub     eax, memory
    add     eax, 2
    cmp     eax, MEM_SIZE
    ja      .not_found

    mov     al, [ebp]
    call    put_hex_byte
    mov     al, [ebp+1]
    call    put_hex_byte

    mov     ecx, 10
    mov     al, SPACE
    rep     stosb

    cmp     byte [ebp], 0D4h
    jne     .dis_is_aad
    mov     al, 'A'
    stosb
    mov     al, 'A'
    stosb
    mov     al, 'M'
    stosb
    jmp     .dis_aam_ops
.dis_is_aad:
    mov     al, 'A'
    stosb
    mov     al, 'A'
    stosb
    mov     al, 'D'
    stosb
.dis_aam_ops:
    cmp     byte [ebp+1], 0Ah
    je      .line_done
    mov     ecx, 5
    mov     al, SPACE
    rep     stosb
    mov     al, [ebp+1]
    call    put_hex_byte
    jmp     .line_done

op_reg16_names:
    dw 'AX', 'CX', 'DX', 'BX', 'SP', 'BP', 'SI', 'DI'

jcc_names:
    db 'JO ', 0, 'JNO', 0, 'JB ', 0, 'JAE', 0
    db 'JZ ', 0, 'JNZ', 0, 'JBE', 0, 'JA ', 0
    db 'JS ', 0, 'JNS', 0, 'JP ', 0, 'JNP', 0
    db 'JL ', 0, 'JGE', 0, 'JLE', 0, 'JG ', 0

dis_str_jmp     db 'JMP', 0
dis_str_call    db 'CALL', 0
dis_str_loopnz  db 'LOOPNZ', 0
dis_str_loopz   db 'LOOPZ', 0
dis_str_loop    db 'LOOP', 0
dis_str_jcxz    db 'JCXZ', 0
dis_str_inc     db 'INC', 0
dis_str_push    db 'PUSH', 0
dis_str_pop     db 'POP', 0


find_opcode:
    push    edi
    
    cmp     al, 0F2h
    je      .check_rep
    cmp     al, 0F3h
    jne     .end3
.check_rep:
    mov     edi, asm_2word_table
.loop3:
    cmp     byte [edi], 0
    je      .end3
    mov     ebx, edi
.skip3:
    cmp     byte [ebx], 0
    je      .found_null3
    inc     ebx
    jmp     .skip3
.found_null3:
    inc     ebx
    cmp     al, [ebx]
    jne     .next3
    mov     ah, [ebp+1]
    cmp     ah, [ebx+1]
    jne     .next3
    mov     esi, edi
    mov     dl, 1
    mov     dh, 2
    pop     edi
    clc
    ret
.next3:
    add     ebx, 2
    mov     edi, ebx
    jmp     .loop3
.end3:

    mov     edi, asm_1word_table
.loop1:
    cmp     byte [edi], 0
    je      .end1
    mov     ebx, edi
.skip1:
    cmp     byte [ebx], 0
    je      .found_null1
    inc     ebx
    jmp     .skip1
.found_null1:
    inc     ebx
    cmp     al, [ebx]
    jne     .next1
    mov     esi, edi
    mov     dl, [ebx+1]
    mov     dh, 0
    pop     edi
    clc
    ret
.next1:
    add     ebx, 2
    mov     edi, ebx
    jmp     .loop1
.end1:

    mov     edi, asm_2word_table
.loop2:
    cmp     byte [edi], 0
    je      .end2
    mov     ebx, edi
.skip2:
    cmp     byte [ebx], 0
    je      .found_null2
    inc     ebx
    jmp     .skip2
.found_null2:
    inc     ebx
    cmp     al, [ebx]
    jne     .next2
    cmp     byte [ebx+1], 2
    ja      .next2
    mov     esi, edi
    mov     dl, [ebx+1]
    mov     dh, 1
    pop     edi
    clc
    ret
.next2:
    add     ebx, 2
    mov     edi, ebx
    jmp     .loop2
.end2:
    pop     edi
    stc
    ret

