update_flags_from_eflags:
    push    eax
    mov     eax, edx
    shr     eax, 11
    and     al, 1
    mov     [flag_states + FLAG_OV], al

    mov     eax, edx
    shr     eax, 7
    and     al, 1
    mov     [flag_states + FLAG_NG], al

    mov     eax, edx
    shr     eax, 6
    and     al, 1
    mov     [flag_states + FLAG_ZR], al

    mov     eax, edx
    shr     eax, 4
    and     al, 1
    mov     [flag_states + FLAG_AC], al

    mov     eax, edx
    shr     eax, 2
    and     al, 1
    mov     [flag_states + FLAG_PE], al

    mov     eax, edx
    and     al, 1
    mov     [flag_states + FLAG_CY], al

    pop     eax
    ret

pack_flags:
    push    ecx
    mov     ax, 0002h
    movzx   ecx, byte [flag_states + FLAG_CY]
    and     ecx, 1
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_PE]
    and     ecx, 1
    shl     ecx, 2
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_AC]
    and     ecx, 1
    shl     ecx, 4
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_ZR]
    and     ecx, 1
    shl     ecx, 6
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_NG]
    and     ecx, 1
    shl     ecx, 7
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_EI]
    and     ecx, 1
    shl     ecx, 9
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_DN]
    and     ecx, 1
    shl     ecx, 10
    or      ax, cx
    movzx   ecx, byte [flag_states + FLAG_OV]
    and     ecx, 1
    shl     ecx, 11
    or      ax, cx
    pop     ecx
    ret

unpack_flags:
    push    eax
    push    ecx
    mov     cx, ax
    mov     al, cl
    and     al, 1
    mov     [flag_states + FLAG_CY], al
    mov     al, cl
    shr     al, 2
    and     al, 1
    mov     [flag_states + FLAG_PE], al
    mov     al, cl
    shr     al, 4
    and     al, 1
    mov     [flag_states + FLAG_AC], al
    mov     al, cl
    shr     al, 6
    and     al, 1
    mov     [flag_states + FLAG_ZR], al
    mov     al, cl
    shr     al, 7
    and     al, 1
    mov     [flag_states + FLAG_NG], al
    mov     ax, cx
    shr     ax, 9
    and     al, 1
    mov     [flag_states + FLAG_EI], al
    mov     ax, cx
    shr     ax, 10
    and     al, 1
    mov     [flag_states + FLAG_DN], al
    mov     ax, cx
    shr     ax, 11
    and     al, 1
    mov     [flag_states + FLAG_OV], al
    pop     ecx
    pop     eax
    ret

; ----------------------------------------------------------------------------
; Stack Helper Routines (16-bit real mode stack)
; ----------------------------------------------------------------------------
; In: ax = value to push
; Out: CF = 0 on success, CF = 1 on out-of-bounds error
; Preserves: ebx, ecx, edx, esi, edi, ebp
cpu_push16:
    push    ebx
    push    ecx
    push    edx
    movzx   edx, ax
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .push16_fail
    mov     word [memory + eax], dx
    pop     edx
    pop     ecx
    pop     ebx
    clc
    ret
.push16_fail:
    pop     edx
    pop     ecx
    pop     ebx
    stc
    ret

; In: none
; Out: ax = popped 16-bit value, CF = 0 on success, CF = 1 on out-of-bounds
; Preserves: ebx, ecx, edx, esi, edi, ebp
cpu_pop16:
    push    ebx
    push    ecx
    push    edx
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .pop16_fail
    movzx   edx, word [memory + eax]
    add     word [reg_SP], 2
    mov     ax, dx
    pop     edx
    pop     ecx
    pop     ebx
    clc
    ret
.pop16_fail:
    pop     edx
    pop     ecx
    pop     ebx
    stc
    ret

; In: ax = offset (IP), dx = segment (CS)
; Out: CF = 0 on success, CF = 1 on out-of-bounds
; Preserves: ebx, ecx, edx, esi, edi, ebp
cpu_push_far:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    movzx   esi, ax
    movzx   edi, dx
    sub     word [reg_SP], 4
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 4
    call    check_mem_range
    jc      .push_far_fail
    mov     word [memory + eax], si
    mov     word [memory + eax + 2], di
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    clc
    ret
.push_far_fail:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    stc
    ret

; In: none
; Out: ax = offset (IP), dx = segment (CS), CF = 0 on success, CF = 1 on error
; Preserves: ebx, ecx, esi, edi, ebp
cpu_pop_far:
    push    ebx
    push    ecx
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 4
    call    check_mem_range
    jc      .pop_far_fail
    mov     cx, word [memory + eax]
    mov     dx, word [memory + eax + 2]
    add     word [reg_SP], 4
    mov     ax, cx
    pop     ecx
    pop     ebx
    clc
    ret
.pop_far_fail:
    pop     ecx
    pop     ebx
    stc
    ret

decode_modrm:
    push    ebp
    mov     ebp, esp
    sub     esp, 16

    movzx   eax, bl
    mov     [ebp-4], eax
    mov     eax, [ebp]
    mov     [ebp-16], eax

    mov     eax, [ebp-16]
    movzx   eax, byte [eax+1]

    mov     edx, eax
    shr     edx, 3
    and     edx, 7
    mov     [ebp-8], edx

    cmp     dword [ebp-4], 0
    jz      .reg_byte
    mov     esi, [reg16_ptrs + edx*4]
    jmp     .check_mod
.reg_byte:
    mov     esi, [reg8_ptrs + edx*4]

.check_mod:
    mov     ecx, eax
    shr     ecx, 6
    and     ecx, 3
    cmp     ecx, 3
    jne     .is_mem

    and     eax, 7
    cmp     dword [ebp-4], 0
    jz      .rm_reg_byte
    mov     edi, [reg16_ptrs + eax*4]
    jmp     .rm_reg_done
.rm_reg_byte:
    mov     edi, [reg8_ptrs + eax*4]
.rm_reg_done:
    mov     ecx, 2
    mov     edx, [ebp-8]
    leave
    clc
    ret

.is_mem:
    and     eax, 7
    mov     dword [ebp-12], 0

    cmp     eax, 0
    jne     .not_rm0
    movzx   ebx, word [reg_BX]
    add     bx, word [reg_SI]
    mov     dx, word [reg_DS]
    jmp     .got_base
.not_rm0:
    cmp     eax, 1
    jne     .not_rm1
    movzx   ebx, word [reg_BX]
    add     bx, word [reg_DI]
    mov     dx, word [reg_DS]
    jmp     .got_base
.not_rm1:
    cmp     eax, 2
    jne     .not_rm2
    movzx   ebx, word [reg_BP]
    add     bx, word [reg_SI]
    mov     dx, word [reg_SS]
    jmp     .got_base
.not_rm2:
    cmp     eax, 3
    jne     .not_rm3
    movzx   ebx, word [reg_BP]
    add     bx, word [reg_DI]
    mov     dx, word [reg_SS]
    jmp     .got_base
.not_rm3:
    cmp     eax, 4
    jne     .not_rm4
    movzx   ebx, word [reg_SI]
    mov     dx, word [reg_DS]
    jmp     .got_base
.not_rm4:
    cmp     eax, 5
    jne     .not_rm5
    movzx   ebx, word [reg_DI]
    mov     dx, word [reg_DS]
    jmp     .got_base
.not_rm5:
    cmp     eax, 6
    jne     .not_rm6
    test    ecx, ecx
    jnz     .bp_base
    mov     eax, [ebp-16]
    mov     bx, word [eax+2]
    mov     dx, word [reg_DS]
    mov     dword [ebp-12], 2
    jmp     .disp_done
.bp_base:
    movzx   ebx, word [reg_BP]
    mov     dx, word [reg_SS]
    jmp     .got_base
.not_rm6:
    movzx   ebx, word [reg_BX]
    mov     dx, word [reg_DS]

.got_base:
    test    ecx, ecx
    jz      .disp_zero
    cmp     ecx, 1
    je      .disp_byte
    mov     eax, [ebp-16]
    add     bx, word [eax+2]
    mov     dword [ebp-12], 2
    jmp     .disp_done
.disp_byte:
    mov     eax, [ebp-16]
    movsx   ax, byte [eax+2]
    add     bx, ax
    mov     dword [ebp-12], 1
    jmp     .disp_done
.disp_zero:
    mov     dword [ebp-12], 0

.disp_done:
    mov     [modrm_offset], bx
    cmp     dword [seg_override], 0
    jz      .no_seg_override
    mov     eax, [seg_override]
    mov     dx, [eax]
.no_seg_override:
    mov     ax, dx
    call    calc_linear_addr

    mov     edx, [ebp-4]
    inc     edx
    lea     edi, [eax + edx]
    cmp     edi, MEM_SIZE
    ja      .modrm_err

    lea     edi, [memory + eax]
    mov     ecx, [ebp-12]
    add     ecx, 2
    mov     edx, [ebp-8]
    mov     ebx, [ebp-4]
    leave
    clc
    ret

.modrm_err:
    leave
    stc
    ret

get_str_src_seg:
    cmp     dword [seg_override], 0
    jz      .default_ds
    mov     edx, [seg_override]
    mov     ax, [edx]
    ret
.default_ds:
    mov     ax, [reg_DS]
    ret

exec_one_string_op:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    cmp     al, 0A4h
    je      .op_movsb
    cmp     al, 0A5h
    je      .op_movsw
    cmp     al, 0A6h
    je      .op_cmpsb
    cmp     al, 0A7h
    je      .op_cmpsw
    cmp     al, 0AAh
    je      .op_stosb
    cmp     al, 0ABh
    je      .op_stosw
    cmp     al, 0ACh
    je      .op_lodsb
    cmp     al, 0ADh
    je      .op_lodsw
    cmp     al, 0AEh
    je      .op_scasb
    cmp     al, 0AFh
    je      .op_scasw
    jmp     .fail

.op_movsb:
    call    get_str_src_seg
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    movzx   edx, byte [memory + eax]

    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    mov     byte [memory + eax], dl

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .movsb_dec
    inc     word [reg_SI]
    inc     word [reg_DI]
    jmp     .ok
.movsb_dec:
    dec     word [reg_SI]
    dec     word [reg_DI]
    jmp     .ok

.op_movsw:
    call    get_str_src_seg
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    movzx   edx, word [memory + eax]

    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    mov     word [memory + eax], dx

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .movsw_dec
    add     word [reg_SI], 2
    add     word [reg_DI], 2
    jmp     .ok
.movsw_dec:
    sub     word [reg_SI], 2
    sub     word [reg_DI], 2
    jmp     .ok

.op_cmpsb:
    call    get_str_src_seg
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    movzx   edx, byte [memory + eax]

    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    mov     cl, byte [memory + eax]

    cmp     dl, cl
    pushfd
    pop     edx
    call    update_flags_from_eflags

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .cmpsb_dec
    inc     word [reg_SI]
    inc     word [reg_DI]
    jmp     .ok
.cmpsb_dec:
    dec     word [reg_SI]
    dec     word [reg_DI]
    jmp     .ok

.op_cmpsw:
    call    get_str_src_seg
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    movzx   esi, word [memory + eax]

    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    mov     cx, word [memory + eax]

    cmp     si, cx
    pushfd
    pop     edx
    call    update_flags_from_eflags

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .cmpsw_dec
    add     word [reg_SI], 2
    add     word [reg_DI], 2
    jmp     .ok
.cmpsw_dec:
    sub     word [reg_SI], 2
    sub     word [reg_DI], 2
    jmp     .ok

.op_stosb:
    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    mov     dl, byte [reg_AX]
    mov     byte [memory + eax], dl

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .stosb_dec
    inc     word [reg_DI]
    jmp     .ok
.stosb_dec:
    dec     word [reg_DI]
    jmp     .ok

.op_stosw:
    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    mov     dx, word [reg_AX]
    mov     word [memory + eax], dx

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .stosw_dec
    add     word [reg_DI], 2
    jmp     .ok
.stosw_dec:
    sub     word [reg_DI], 2
    jmp     .ok

.op_lodsb:
    call    get_str_src_seg
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    mov     dl, byte [memory + eax]
    mov     byte [reg_AX], dl

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .lodsb_dec
    inc     word [reg_SI]
    jmp     .ok
.lodsb_dec:
    dec     word [reg_SI]
    jmp     .ok

.op_lodsw:
    call    get_str_src_seg
    mov     bx, [reg_SI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    mov     dx, word [memory + eax]
    mov     word [reg_AX], dx

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .lodsw_dec
    add     word [reg_SI], 2
    jmp     .ok
.lodsw_dec:
    sub     word [reg_SI], 2
    jmp     .ok

.op_scasb:
    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .fail
    mov     dl, byte [reg_AX]
    cmp     dl, byte [memory + eax]
    pushfd
    pop     edx
    call    update_flags_from_eflags

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .scasb_dec
    inc     word [reg_DI]
    jmp     .ok
.scasb_dec:
    dec     word [reg_DI]
    jmp     .ok

.op_scasw:
    mov     ax, [reg_ES]
    mov     bx, [reg_DI]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .fail
    mov     dx, word [reg_AX]
    cmp     dx, word [memory + eax]
    pushfd
    pop     edx
    call    update_flags_from_eflags

    cmp     byte [flag_states + FLAG_DN], 0
    jne     .scasw_dec
    add     word [reg_DI], 2
    jmp     .ok
.scasw_dec:
    sub     word [reg_DI], 2
    jmp     .ok

.ok:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    clc
    ret

.fail:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    stc
    ret

step:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp

    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    mov     [step_initial_ip], bx
    mov     dword [seg_override], 0
    mov     dword [prefix_len], 0
    call    calc_linear_addr

    mov     ecx, 1
    call    check_mem_range
    jc      .out_of_bounds

    mov     ebp, memory
    add     ebp, eax

; ----------------------------------------------------------------------------
; 1. Instruction Decode Stage (Structured Prefix & Opcode Fetch)
; ----------------------------------------------------------------------------
.decode_prefix:
    mov     eax, ebp
    sub     eax, memory
    cmp     eax, MEM_SIZE
    jae     .out_of_bounds

    movzx   eax, byte [ebp]

    ; Check segment override (26h=ES, 2Eh=CS, 36h=SS, 3Eh=DS)
    ; (al & 0E7h) == 26h matches only 26h, 2Eh, 36h, 3Eh in the entire byte space
    mov     edx, eax
    and     dl, 0E7h
    cmp     dl, 26h
    jne     .check_lock

    ; Extract segment index: (al >> 3) & 3 -> 0:ES, 1:CS, 2:SS, 3:DS
    shr     eax, 3
    and     eax, 3
    mov     edx, [sreg_ptrs + eax*4]
    mov     [seg_override], edx
    inc     ebp
    inc     dword [prefix_len]
    jmp     .decode_prefix

.check_lock:
    cmp     al, 0F0h            ; LOCK prefix
    jne     .decode_done
    inc     ebp
    inc     dword [prefix_len]
    jmp     .decode_prefix

.decode_done:
    mov     ax, word [prefix_len]
    add     [reg_IP], ax
    movzx   eax, byte [ebp]

; ----------------------------------------------------------------------------
; 2. Instruction Category Dispatch
; ----------------------------------------------------------------------------
    cmp     al, 3Fh
    jbe     .dispatch_00_3f

    cmp     al, 4Fh
    jbe     .dispatch_40_4f

    cmp     al, 5Fh
    jbe     .dispatch_50_5f

    cmp     al, 7Fh
    jbe     .dispatch_70_7f

    cmp     al, 8Fh
    jbe     .dispatch_80_8f

    cmp     al, 9Fh
    jbe     .dispatch_90_9f

    cmp     al, 0AFh
    jbe     .dispatch_a0_af

    cmp     al, 0BFh
    jbe     .dispatch_b0_bf

    cmp     al, 0CFh
    jbe     .dispatch_c0_cf

    cmp     al, 0D7h
    jbe     .dispatch_d0_d7

    cmp     al, 0EFh
    jbe     .dispatch_e0_ef

    jmp     .dispatch_f0_ff

.dispatch_00_3f:
    cmp     al, 06h
    je      .push_es
    cmp     al, 0Eh
    je      .push_cs
    cmp     al, 16h
    je      .push_ss
    cmp     al, 1Eh
    je      .push_ds

    cmp     al, 07h
    je      .pop_es
    cmp     al, 17h
    je      .pop_ss
    cmp     al, 1Fh
    je      .pop_ds

    cmp     al, 27h
    je      .is_daa
    cmp     al, 2Fh
    je      .is_das
    cmp     al, 37h
    je      .is_aaa
    cmp     al, 3Fh
    je      .is_aas

    cmp     al, 04h
    je      .al_imm_add
    cmp     al, 0Ch
    je      .al_imm_or
    cmp     al, 14h
    je      .al_imm_adc
    cmp     al, 1Ch
    je      .al_imm_sbb
    cmp     al, 24h
    je      .al_imm_and
    cmp     al, 2Ch
    je      .al_imm_sub
    cmp     al, 34h
    je      .al_imm_xor
    cmp     al, 3Ch
    je      .al_imm_cmp

    cmp     al, 05h
    je      .ax_imm_add
    cmp     al, 0Dh
    je      .ax_imm_or
    cmp     al, 15h
    je      .ax_imm_adc
    cmp     al, 1Dh
    je      .ax_imm_sbb
    cmp     al, 25h
    je      .ax_imm_and
    cmp     al, 2Dh
    je      .ax_imm_sub
    cmp     al, 35h
    je      .ax_imm_xor
    cmp     al, 3Dh
    je      .ax_imm_cmp

    jmp     .is_reg_alu

.dispatch_40_4f:
    cmp     al, 47h
    jbe     .is_inc_r16
    jmp     .is_dec_r16

.dispatch_50_5f:
    cmp     al, 57h
    jbe     .is_push_r16
    jmp     .is_pop_r16

.dispatch_70_7f:
    cmp     al, 70h
    jb      .unknown_insn
    jmp     .is_jcc

.dispatch_80_8f:
    cmp     al, 83h
    jbe     .is_alu_imm
    cmp     al, 85h
    jbe     .is_test_reg
    cmp     al, 86h
    je      .is_xchg_rm8_r8
    cmp     al, 87h
    je      .is_xchg_rm16_r16
    cmp     al, 88h
    je      .is_mov_rm8_r8
    cmp     al, 89h
    je      .is_mov_rm16_r16
    cmp     al, 8Ah
    je      .is_mov_r8_rm8
    cmp     al, 8Bh
    je      .is_mov_r16_rm16
    cmp     al, 8Ch
    je      .is_mov_rm16_sreg
    cmp     al, 8Dh
    je      .is_lea
    cmp     al, 8Eh
    je      .is_mov_sreg_rm16
    cmp     al, 8Fh
    je      .is_pop_rm16
    jmp     .unknown_insn

.dispatch_90_9f:
    cmp     al, 90h
    je      .is_nop
    cmp     al, 97h
    jbe     .is_xchg_ax_r16
    cmp     al, 98h
    je      .is_cbw
    cmp     al, 99h
    je      .is_cwd
    cmp     al, 9Ah
    je      .is_call_far
    cmp     al, 9Bh
    je      .is_wait
    cmp     al, 9Ch
    je      .is_pushf
    cmp     al, 9Dh
    je      .is_popf
    cmp     al, 9Eh
    je      .is_sahf
    cmp     al, 9Fh
    je      .is_lahf
    jmp     .unknown_insn

.dispatch_a0_af:
    cmp     al, 0A3h
    jbe     .is_mov_accum_mem
    cmp     al, 0A7h
    jbe     .is_single_string_op
    cmp     al, 0A8h
    je      .al_imm_test
    cmp     al, 0A9h
    je      .ax_imm_test
    jmp     .is_single_string_op

.dispatch_b0_bf:
    cmp     al, 0B7h
    jbe     .is_mov_r8_imm
    jmp     .is_mov_r16_imm

.dispatch_c0_cf:
    cmp     al, 0C2h
    je      .is_ret_imm16
    cmp     al, 0C3h
    je      .is_ret_near
    cmp     al, 0C4h
    je      .is_les
    cmp     al, 0C5h
    je      .is_lds
    cmp     al, 0C6h
    je      .is_mov_rm8_imm8
    cmp     al, 0C7h
    je      .is_mov_rm16_imm16
    cmp     al, 0CAh
    je      .is_retf_imm16
    cmp     al, 0CBh
    je      .is_retf_far
    cmp     al, 0CCh
    je      .is_int3
    cmp     al, 0CDh
    je      .op_int
    cmp     al, 0CEh
    je      .is_into
    cmp     al, 0CFh
    je      .is_iret
    jmp     .unknown_insn

.dispatch_d0_d7:
    cmp     al, 0D3h
    jbe     .is_shift
    cmp     al, 0D4h
    je      .is_aam
    cmp     al, 0D5h
    je      .is_aad
    cmp     al, 0D6h
    je      .is_salc
    cmp     al, 0D7h
    je      .is_xlat
    jmp     .unknown_insn

.dispatch_e0_ef:
    cmp     al, 0E0h
    je      .is_loopnz
    cmp     al, 0E1h
    je      .is_loopz
    cmp     al, 0E2h
    je      .is_loop
    cmp     al, 0E3h
    je      .is_jcxz
    cmp     al, 0E4h
    je      .in_al_imm
    cmp     al, 0E5h
    je      .in_ax_imm
    cmp     al, 0E6h
    je      .out_al_imm
    cmp     al, 0E7h
    je      .out_ax_imm
    cmp     al, 0E8h
    je      .is_call_near
    cmp     al, 0E9h
    je      .is_jmp_near
    cmp     al, 0EAh
    je      .is_jmp_far
    cmp     al, 0EBh
    je      .is_jmp_short
    cmp     al, 0ECh
    je      .in_al_dx
    cmp     al, 0EDh
    je      .in_ax_dx
    cmp     al, 0EEh
    je      .out_dx_al
    cmp     al, 0EFh
    je      .out_dx_ax
    jmp     .unknown_insn

.dispatch_f0_ff:
    cmp     al, 0F2h
    je      .is_rep_prefix
    cmp     al, 0F3h
    je      .is_rep_prefix
    cmp     al, 0F4h
    je      .is_hlt
    cmp     al, 0F5h
    je      .is_cmc
    cmp     al, 0F6h
    je      .is_f6_f7
    cmp     al, 0F7h
    je      .is_f6_f7
    cmp     al, 0F8h
    je      .is_clc
    cmp     al, 0F9h
    je      .is_stc
    cmp     al, 0FAh
    je      .is_cli
    cmp     al, 0FBh
    je      .is_sti
    cmp     al, 0FCh
    je      .is_cld
    cmp     al, 0FDh
    je      .is_std
    cmp     al, 0FEh
    jae     .is_fe_ff
    jmp     .unknown_insn

; ============================================================================
; 3. CATEGORY: DATA MOVEMENT
; ============================================================================
.is_mov_r8_imm:
    sub     al, 0B0h
    movzx   eax, al
    mov     edi, [reg8_ptrs + eax*4]
    mov     dl, [ebp+1]
    mov     [edi], dl
    add     word [reg_IP], 2
    jmp     .step_ok

.is_mov_r16_imm:
    sub     al, 0B8h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    mov     dx, word [ebp+1]
    mov     [edi], dx
    add     word [reg_IP], 3
    jmp     .step_ok

.is_mov_rm8_r8:
    xor     bl, bl
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [esi]
    mov     [edi], al
    add     [reg_IP], cx
    jmp     .step_ok

.is_mov_rm16_r16:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     ax, [esi]
    mov     [edi], ax
    add     [reg_IP], cx
    jmp     .step_ok

.is_mov_r8_rm8:
    xor     bl, bl
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [edi]
    mov     [esi], al
    add     [reg_IP], cx
    jmp     .step_ok

.is_mov_r16_rm16:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     ax, [edi]
    mov     [esi], ax
    add     [reg_IP], cx
    jmp     .step_ok

.is_mov_rm8_imm8:
    xor     bl, bl
    call    decode_modrm
    jc      .out_of_bounds
    test    edx, edx
    jnz     .unknown_insn
    mov     al, [ebp + ecx]
    mov     [edi], al
    inc     ecx
    add     [reg_IP], cx
    jmp     .step_ok

.is_mov_rm16_imm16:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    test    edx, edx
    jnz     .unknown_insn
    mov     ax, word [ebp + ecx]
    mov     [edi], ax
    add     ecx, 2
    add     [reg_IP], cx
    jmp     .step_ok

.is_mov_accum_mem:
    mov     bx, word [ebp+1]
    mov     dx, [reg_DS]
    cmp     dword [seg_override], 0
    jz      .mov_accum_no_override
    mov     eax, [seg_override]
    mov     dx, [eax]
.mov_accum_no_override:
    mov     ax, dx
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    lea     edi, [memory + eax]

    movzx   eax, byte [ebp]
    cmp     al, 0A0h
    je      .exec_a0
    cmp     al, 0A1h
    je      .exec_a1
    cmp     al, 0A2h
    je      .exec_a2
    mov     ax, word [reg_AX]
    mov     word [edi], ax
    add     word [reg_IP], 3
    jmp     .step_ok

.exec_a0:
    mov     al, byte [edi]
    mov     byte [reg_AX], al
    add     word [reg_IP], 3
    jmp     .step_ok

.exec_a1:
    mov     ax, word [edi]
    mov     word [reg_AX], ax
    add     word [reg_IP], 3
    jmp     .step_ok

.exec_a2:
    mov     al, byte [reg_AX]
    mov     byte [edi], al
    add     word [reg_IP], 3
    jmp     .step_ok

.is_mov_rm16_sreg:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     edx, [ebp+1]
    shr     edx, 3
    and     edx, 3
    mov     esi, [sreg_ptrs + edx*4]
    mov     ax, word [esi]
    mov     word [edi], ax
    add     [reg_IP], cx
    jmp     .step_ok

.is_mov_sreg_rm16:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     ax, word [edi]
    mov     edx, [ebp+1]
    shr     edx, 3
    and     edx, 3
    mov     esi, [sreg_ptrs + edx*4]
    mov     [esi], ax
    add     [reg_IP], cx
    jmp     .step_ok

.is_xchg_ax_r16:
    sub     al, 90h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    mov     ax, [reg_AX]
    xchg    ax, [edi]
    mov     [reg_AX], ax
    add     word [reg_IP], 1
    jmp     .step_ok

.is_xchg_rm8_r8:
    xor     bl, bl
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [esi]
    xchg    al, [edi]
    mov     [esi], al
    add     [reg_IP], cx
    jmp     .step_ok

.is_xchg_rm16_r16:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     ax, [esi]
    xchg    ax, [edi]
    mov     [esi], ax
    add     [reg_IP], cx
    jmp     .step_ok

.is_lea:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [ebp+1]
    shr     al, 6
    cmp     al, 3
    je      .unknown_insn
    mov     ax, [modrm_offset]
    mov     [esi], ax
    add     [reg_IP], cx
    jmp     .step_ok

.is_les:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [ebp+1]
    shr     al, 6
    cmp     al, 3
    je      .unknown_insn
    push    ecx
    mov     eax, edi
    sub     eax, memory
    mov     ecx, 4
    call    check_mem_range
    pop     ecx
    jc      .out_of_bounds
    mov     ax, word [edi]
    mov     dx, word [edi+2]
    mov     [esi], ax
    mov     [reg_ES], dx
    add     [reg_IP], cx
    jmp     .step_ok

.is_lds:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    mov     al, [ebp+1]
    shr     al, 6
    cmp     al, 3
    je      .unknown_insn
    push    ecx
    mov     eax, edi
    sub     eax, memory
    mov     ecx, 4
    call    check_mem_range
    pop     ecx
    jc      .out_of_bounds
    mov     ax, word [edi]
    mov     dx, word [edi+2]
    mov     [esi], ax
    mov     [reg_DS], dx
    add     [reg_IP], cx
    jmp     .step_ok

.is_xlat:
    movzx   ebx, byte [reg_AX]
    add     bx, word [reg_BX]
    mov     dx, word [reg_DS]
    cmp     dword [seg_override], 0
    jz      .xlat_no_override
    mov     eax, [seg_override]
    mov     dx, [eax]
.xlat_no_override:
    mov     ax, dx
    call    calc_linear_addr
    mov     ecx, 1
    call    check_mem_range
    jc      .out_of_bounds
    mov     al, byte [memory + eax]
    mov     byte [reg_AX], al
    add     word [reg_IP], 1
    jmp     .step_ok

; ============================================================================
; 4. CATEGORY: STACK OPERATIONS
; ============================================================================
.is_push_r16:
    sub     al, 50h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    mov     ax, [edi]
    call    cpu_push16
    jc      .out_of_bounds
    add     word [reg_IP], 1
    jmp     .step_ok

.is_pop_r16:
    sub     al, 58h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    call    cpu_pop16
    jc      .out_of_bounds
    mov     [edi], ax
    add     word [reg_IP], 1
    jmp     .step_ok

.push_es:
    mov     ax, [reg_ES]
    jmp     .do_push_seg
.push_cs:
    mov     ax, [reg_CS]
    jmp     .do_push_seg
.push_ss:
    mov     ax, [reg_SS]
    jmp     .do_push_seg
.push_ds:
    mov     ax, [reg_DS]
.do_push_seg:
    call    cpu_push16
    jc      .out_of_bounds
    add     word [reg_IP], 1
    jmp     .step_ok

.pop_es:
    call    cpu_pop16
    jc      .out_of_bounds
    mov     [reg_ES], ax
    add     word [reg_IP], 1
    jmp     .step_ok
.pop_ss:
    call    cpu_pop16
    jc      .out_of_bounds
    mov     [reg_SS], ax
    add     word [reg_IP], 1
    jmp     .step_ok
.pop_ds:
    call    cpu_pop16
    jc      .out_of_bounds
    mov     [reg_DS], ax
    add     word [reg_IP], 1
    jmp     .step_ok

.is_pushf:
    call    pack_flags
    call    cpu_push16
    jc      .out_of_bounds
    add     word [reg_IP], 1
    jmp     .step_ok

.is_popf:
    call    cpu_pop16
    jc      .out_of_bounds
    call    unpack_flags
    add     word [reg_IP], 1
    jmp     .step_ok

.is_pop_rm16:
    mov     bl, 1
    call    decode_modrm
    jc      .out_of_bounds
    test    edx, edx
    jnz     .unknown_insn
    push    ecx
    push    edi
    call    cpu_pop16
    pop     edi
    pop     ecx
    jc      .out_of_bounds
    mov     word [edi], ax
    add     [reg_IP], cx
    jmp     .step_ok

; ============================================================================
; 5. CATEGORY: ALU & LOGIC
; ============================================================================
.is_inc_r16:
    sub     al, 40h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    inc     word [edi]
    pushfd
    pop     edx
    mov     cl, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], cl
    add     word [reg_IP], 1
    jmp     .step_ok

.is_dec_r16:
    sub     al, 48h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    dec     word [edi]
    pushfd
    pop     edx
    mov     cl, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], cl
    add     word [reg_IP], 1
    jmp     .step_ok

.is_alu_imm:
    cmp     byte [ebp], 81h
    je      .alu_imm_w
    cmp     byte [ebp], 83h
    je      .alu_imm_w
    xor     bl, bl
    jmp     .alu_imm_modrm
.alu_imm_w:
    mov     bl, 1
.alu_imm_modrm:
    call    decode_modrm
    jc      .out_of_bounds

    test    bl, bl
    jz      .alu_imm_read_b

    cmp     byte [ebp], 83h
    je      .alu_imm_sign_ext
    mov     ax, word [ebp + ecx]
    add     ecx, 2
    jmp     .alu_imm_exec_w
.alu_imm_sign_ext:
    movsx   ax, byte [ebp + ecx]
    inc     ecx

.alu_imm_exec_w:
    push    ecx
    cmp     edx, 0
    je      .alu_w_add
    cmp     edx, 1
    je      .alu_w_or
    cmp     edx, 2
    je      .alu_w_adc
    cmp     edx, 3
    je      .alu_w_sbb
    cmp     edx, 4
    je      .alu_w_and
    cmp     edx, 5
    je      .alu_w_sub
    cmp     edx, 6
    je      .alu_w_xor
    cmp     edx, 7
    je      .alu_w_cmp
    pop     ecx
    jmp     .unknown_insn

.alu_w_add:
    add     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_or:
    or      word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_adc:
    bt      word [flag_states + FLAG_CY], 0
    adc     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_sbb:
    bt      word [flag_states + FLAG_CY], 0
    sbb     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_and:
    and     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_sub:
    sub     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_xor:
    xor     word [edi], ax
    jmp     .alu_imm_w_done
.alu_w_cmp:
    cmp     word [edi], ax
    jmp     .alu_imm_w_done

.alu_imm_w_done:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    pop     ecx
    add     [reg_IP], cx
    jmp     .step_ok

.alu_imm_read_b:
    mov     al, byte [ebp + ecx]
    inc     ecx
    push    ecx
    cmp     edx, 0
    je      .alu_b_add
    cmp     edx, 1
    je      .alu_b_or
    cmp     edx, 2
    je      .alu_b_adc
    cmp     edx, 3
    je      .alu_b_sbb
    cmp     edx, 4
    je      .alu_b_and
    cmp     edx, 5
    je      .alu_b_sub
    cmp     edx, 6
    je      .alu_b_xor
    cmp     edx, 7
    je      .alu_b_cmp
    pop     ecx
    jmp     .unknown_insn

.alu_b_add:
    add     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_or:
    or      byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_adc:
    bt      word [flag_states + FLAG_CY], 0
    adc     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_sbb:
    bt      word [flag_states + FLAG_CY], 0
    sbb     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_and:
    and     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_sub:
    sub     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_xor:
    xor     byte [edi], al
    jmp     .alu_imm_b_done
.alu_b_cmp:
    cmp     byte [edi], al
    jmp     .alu_imm_b_done

.alu_imm_b_done:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    pop     ecx
    add     [reg_IP], cx
    jmp     .step_ok

.is_test_reg:
    and     al, 1
    mov     bl, al
    call    decode_modrm
    jc      .out_of_bounds
    test    bl, bl
    jz      .test_b
    mov     ax, word [esi]
    test    word [edi], ax
    jmp     .test_flags
.test_b:
    mov     al, byte [esi]
    test    byte [edi], al
.test_flags:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok

.is_reg_alu:
    mov     al, byte [ebp]
    and     al, 7
    cmp     al, 3
    ja      .unknown_insn

    mov     bl, byte [ebp]
    and     bl, 1
    call    decode_modrm
    jc      .out_of_bounds

    mov     dl, byte [ebp]
    shr     dl, 3
    test    byte [ebp], 2
    jz      .dir_rm_dst
    xchg    esi, edi

.dir_rm_dst:
    push    ecx
    movzx   edx, dl
    test    bl, bl
    jz      .reg_alu_byte

    mov     ax, word [esi]
    cmp     edx, 0
    je      .alu_w_add
    cmp     edx, 1
    je      .alu_w_or
    cmp     edx, 2
    je      .alu_w_adc
    cmp     edx, 3
    je      .alu_w_sbb
    cmp     edx, 4
    je      .alu_w_and
    cmp     edx, 5
    je      .alu_w_sub
    cmp     edx, 6
    je      .alu_w_xor
    cmp     edx, 7
    je      .alu_w_cmp
    pop     ecx
    jmp     .unknown_insn

.reg_alu_byte:
    mov     al, byte [esi]
    cmp     edx, 0
    je      .alu_b_add
    cmp     edx, 1
    je      .alu_b_or
    cmp     edx, 2
    je      .alu_b_adc
    cmp     edx, 3
    je      .alu_b_sbb
    cmp     edx, 4
    je      .alu_b_and
    cmp     edx, 5
    je      .alu_b_sub
    cmp     edx, 6
    je      .alu_b_xor
    cmp     edx, 7
    je      .alu_b_cmp
    pop     ecx
    jmp     .unknown_insn

.ax_imm_add:
    mov     ax, word [ebp+1]
    add     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_or:
    mov     ax, word [ebp+1]
    or      word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_adc:
    bt      word [flag_states + FLAG_CY], 0
    mov     ax, word [ebp+1]
    adc     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_sbb:
    bt      word [flag_states + FLAG_CY], 0
    mov     ax, word [ebp+1]
    sbb     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_and:
    mov     ax, word [ebp+1]
    and     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_sub:
    mov     ax, word [ebp+1]
    sub     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_xor:
    mov     ax, word [ebp+1]
    xor     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_cmp:
    mov     ax, word [ebp+1]
    cmp     word [reg_AX], ax
    jmp     .ax_imm_flags
.ax_imm_test:
    mov     ax, word [ebp+1]
    test    word [reg_AX], ax
    jmp     .ax_imm_flags

.ax_imm_flags:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 3
    jmp     .step_ok

.al_imm_add:
    mov     al, byte [ebp+1]
    add     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_or:
    mov     al, byte [ebp+1]
    or      byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_adc:
    bt      word [flag_states + FLAG_CY], 0
    mov     al, byte [ebp+1]
    adc     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_sbb:
    bt      word [flag_states + FLAG_CY], 0
    mov     al, byte [ebp+1]
    sbb     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_and:
    mov     al, byte [ebp+1]
    and     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_sub:
    mov     al, byte [ebp+1]
    sub     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_xor:
    mov     al, byte [ebp+1]
    xor     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_cmp:
    mov     al, byte [ebp+1]
    cmp     byte [reg_AX], al
    jmp     .al_imm_flags
.al_imm_test:
    mov     al, byte [ebp+1]
    test    byte [reg_AX], al
    jmp     .al_imm_flags

.al_imm_flags:
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 2
    jmp     .step_ok

.is_shift:
    mov     bl, byte [ebp]
    and     bl, 1
    call    decode_modrm
    jc      .out_of_bounds

    push    ecx

    test    byte [ebp], 2
    jnz     .shift_cl
    mov     cl, 1
    jmp     .shift_count_ok
.shift_cl:
    mov     cl, byte [reg_CX]
    and     cl, 1Fh
    jz      .shift_done
.shift_count_ok:

    test    bl, bl
    jz      .shift_byte

    cmp     edx, 0
    je      .sh16_rol
    cmp     edx, 1
    je      .sh16_ror
    cmp     edx, 2
    je      .sh16_rcl
    cmp     edx, 3
    je      .sh16_rcr
    cmp     edx, 4
    je      .sh16_shl
    cmp     edx, 5
    je      .sh16_shr
    cmp     edx, 7
    je      .sh16_sar
    pop     ecx
    jmp     .unknown_insn

.sh16_rol:
    rol     word [edi], cl
    jmp     .rotate_flags
.sh16_ror:
    ror     word [edi], cl
    jmp     .rotate_flags
.sh16_rcl:
    bt      word [flag_states + FLAG_CY], 0
    rcl     word [edi], cl
    jmp     .rotate_flags
.sh16_rcr:
    bt      word [flag_states + FLAG_CY], 0
    rcr     word [edi], cl
    jmp     .rotate_flags
.sh16_shl:
    shl     word [edi], cl
    jmp     .shift_flags
.sh16_shr:
    shr     word [edi], cl
    jmp     .shift_flags
.sh16_sar:
    sar     word [edi], cl
    jmp     .shift_flags

.shift_byte:
    cmp     edx, 0
    je      .sh8_rol
    cmp     edx, 1
    je      .sh8_ror
    cmp     edx, 2
    je      .sh8_rcl
    cmp     edx, 3
    je      .sh8_rcr
    cmp     edx, 4
    je      .sh8_shl
    cmp     edx, 5
    je      .sh8_shr
    cmp     edx, 7
    je      .sh8_sar
    pop     ecx
    jmp     .unknown_insn

.sh8_rol:
    rol     byte [edi], cl
    jmp     .rotate_flags
.sh8_ror:
    ror     byte [edi], cl
    jmp     .rotate_flags
.sh8_rcl:
    bt      word [flag_states + FLAG_CY], 0
    rcl     byte [edi], cl
    jmp     .rotate_flags
.sh8_rcr:
    bt      word [flag_states + FLAG_CY], 0
    rcr     byte [edi], cl
    jmp     .rotate_flags
.sh8_shl:
    shl     byte [edi], cl
    jmp     .shift_flags
.sh8_shr:
    shr     byte [edi], cl
    jmp     .shift_flags
.sh8_sar:
    sar     byte [edi], cl
    jmp     .shift_flags

.rotate_flags:
    pushfd
    pop     edx
    mov     eax, edx
    and     al, 1
    mov     [flag_states + FLAG_CY], al
    cmp     cl, 1
    jne     .shift_done
    mov     eax, edx
    shr     eax, 11
    and     al, 1
    mov     [flag_states + FLAG_OV], al
    jmp     .shift_done

.shift_flags:
    pushfd
    pop     edx
    call    update_flags_from_eflags
.shift_done:
    pop     ecx
    add     [reg_IP], cx
    jmp     .step_ok

.is_f6_f7:
    mov     ah, al
    and     al, 1
    mov     bl, al
    call    decode_modrm
    jc      .out_of_bounds

    cmp     edx, 0
    je      .f67_test
    cmp     edx, 2
    je      .f67_not
    cmp     edx, 3
    je      .f67_neg
    cmp     edx, 4
    je      .f67_mul
    cmp     edx, 5
    je      .f67_imul
    cmp     edx, 6
    je      .f67_div
    cmp     edx, 7
    je      .f67_idiv
    jmp     .unknown_insn

.f67_test:
    test    bl, bl
    jz      .f6_test_b
    mov     ax, word [ebp + ecx]
    add     ecx, 2
    test    word [edi], ax
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok
.f6_test_b:
    mov     al, byte [ebp + ecx]
    inc     ecx
    test    byte [edi], al
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok

.f67_not:
    test    bl, bl
    jz      .f6_not_b
    not     word [edi]
    add     [reg_IP], cx
    jmp     .step_ok
.f6_not_b:
    not     byte [edi]
    add     [reg_IP], cx
    jmp     .step_ok

.f67_neg:
    test    bl, bl
    jz      .f6_neg_b
    neg     word [edi]
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok
.f6_neg_b:
    neg     byte [edi]
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok

.f67_mul:
    test    bl, bl
    jz      .f6_mul_b
    mov     ax, word [reg_AX]
    mul     word [edi]
    mov     word [reg_AX], ax
    mov     word [reg_DX], dx
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok
.f6_mul_b:
    mov     al, byte [reg_AX]
    mul     byte [edi]
    mov     word [reg_AX], ax
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok

.f67_imul:
    test    bl, bl
    jz      .f6_imul_b
    mov     ax, word [reg_AX]
    imul    word [edi]
    mov     word [reg_AX], ax
    mov     word [reg_DX], dx
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok
.f6_imul_b:
    mov     al, byte [reg_AX]
    imul    byte [edi]
    mov     word [reg_AX], ax
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     [reg_IP], cx
    jmp     .step_ok

.f67_div:
    test    bl, bl
    jz      .f6_div_b
    movzx   ebx, word [edi]
    test    ebx, ebx
    jz      .unknown_insn
    movzx   eax, word [reg_AX]
    movzx   edx, word [reg_DX]
    shl     edx, 16
    or      eax, edx
    xor     edx, edx
    div     ebx
    cmp     eax, 0FFFFh
    ja      .unknown_insn
    mov     word [reg_AX], ax
    mov     word [reg_DX], dx
    add     [reg_IP], cx
    jmp     .step_ok
.f6_div_b:
    movzx   ebx, byte [edi]
    test    ebx, ebx
    jz      .unknown_insn
    movzx   eax, byte [reg_AX]
    xor     edx, edx
    div     ebx
    cmp     eax, 0FFh
    ja      .unknown_insn
    mov     byte [reg_AX], al
    mov     byte [reg_AX+1], dl
    add     [reg_IP], cx
    jmp     .step_ok

.f67_idiv:
    test    bl, bl
    jz      .f6_idiv_b
    movsx   ebx, word [edi]
    test    ebx, ebx
    jz      .unknown_insn
    movzx   eax, word [reg_AX]
    movzx   edx, word [reg_DX]
    shl     edx, 16
    or      eax, edx
    cdq
    idiv    ebx
    cmp     eax, -32768
    jl      .unknown_insn
    cmp     eax, 32767
    jg      .unknown_insn
    mov     word [reg_AX], ax
    mov     word [reg_DX], dx
    add     [reg_IP], cx
    jmp     .step_ok
.f6_idiv_b:
    movsx   ebx, byte [edi]
    test    ebx, ebx
    jz      .unknown_insn
    movsx   eax, word [reg_AX]
    cdq
    idiv    ebx
    cmp     eax, -128
    jl      .unknown_insn
    cmp     eax, 127
    jg      .unknown_insn
    mov     byte [reg_AX], al
    mov     byte [reg_AX+1], dl
    add     [reg_IP], cx
    jmp     .step_ok

.is_daa:
    call    pack_flags
    mov     ah, al
    sahf
    mov     al, byte [reg_AX]
    daa
    mov     byte [reg_AX], al
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 1
    jmp     .step_ok

.is_das:
    call    pack_flags
    mov     ah, al
    sahf
    mov     al, byte [reg_AX]
    das
    mov     byte [reg_AX], al
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 1
    jmp     .step_ok

.is_aaa:
    call    pack_flags
    mov     ah, al
    sahf
    mov     al, byte [reg_AX]
    mov     ah, byte [reg_AX+1]
    aaa
    mov     word [reg_AX], ax
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 1
    jmp     .step_ok

.is_aas:
    call    pack_flags
    mov     ah, al
    sahf
    mov     al, byte [reg_AX]
    mov     ah, byte [reg_AX+1]
    aas
    mov     word [reg_AX], ax
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 1
    jmp     .step_ok

.is_aam:
    movzx   ecx, byte [ebp+1]
    test    ecx, ecx
    jz      .unknown_insn
    movzx   eax, byte [reg_AX]
    xor     edx, edx
    div     ecx
    mov     byte [reg_AX+1], al   ; AH = AL / imm8
    mov     byte [reg_AX], dl     ; AL = AL % imm8
    test    dl, dl
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 2
    jmp     .step_ok

.is_aad:
    movzx   ecx, byte [ebp+1]
    movzx   eax, byte [reg_AX+1] ; AH
    imul    eax, ecx
    movzx   edx, byte [reg_AX]   ; AL
    add     eax, edx
    and     eax, 0FFh
    mov     byte [reg_AX], al
    mov     byte [reg_AX+1], 0
    test    al, al
    pushfd
    pop     edx
    call    update_flags_from_eflags
    add     word [reg_IP], 2
    jmp     .step_ok

.is_salc:
    cmp     byte [flag_states + FLAG_CY], 0
    jz      .salc_nc
    mov     byte [reg_AX], 0FFh
    jmp     .salc_done
.salc_nc:
    mov     byte [reg_AX], 0
.salc_done:
    add     word [reg_IP], 1
    jmp     .step_ok

.is_cbw:
    mov     al, byte [reg_AX]
    cbw
    mov     [reg_AX], ax
    add     word [reg_IP], 1
    jmp     .step_ok

.is_cwd:
    mov     ax, word [reg_AX]
    cwd
    mov     [reg_DX], dx
    add     word [reg_IP], 1
    jmp     .step_ok

.is_sahf:
    mov     al, byte [reg_AX+1]
    mov     cl, al
    and     al, 1
    mov     [flag_states + FLAG_CY], al
    mov     al, cl
    shr     al, 2
    and     al, 1
    mov     [flag_states + FLAG_PE], al
    mov     al, cl
    shr     al, 4
    and     al, 1
    mov     [flag_states + FLAG_AC], al
    mov     al, cl
    shr     al, 6
    and     al, 1
    mov     [flag_states + FLAG_ZR], al
    mov     al, cl
    shr     al, 7
    and     al, 1
    mov     [flag_states + FLAG_NG], al
    add     word [reg_IP], 1
    jmp     .step_ok

.is_lahf:
    call    pack_flags
    mov     byte [reg_AX+1], al
    add     word [reg_IP], 1
    jmp     .step_ok

.is_clc:
    mov     byte [flag_states + FLAG_CY], 0
    add     word [reg_IP], 1
    jmp     .step_ok

.is_stc:
    mov     byte [flag_states + FLAG_CY], 1
    add     word [reg_IP], 1
    jmp     .step_ok

.is_cmc:
    xor     byte [flag_states + FLAG_CY], 1
    add     word [reg_IP], 1
    jmp     .step_ok

.is_cld:
    mov     byte [flag_states + FLAG_DN], 0
    add     word [reg_IP], 1
    jmp     .step_ok

.is_std:
    mov     byte [flag_states + FLAG_DN], 1
    add     word [reg_IP], 1
    jmp     .step_ok

.is_cli:
    mov     byte [flag_states + FLAG_EI], 0
    add     word [reg_IP], 1
    jmp     .step_ok

.is_sti:
    mov     byte [flag_states + FLAG_EI], 1
    add     word [reg_IP], 1
    jmp     .step_ok

; ============================================================================
; 6. CATEGORY: BRANCH & CALL
; ============================================================================
.is_ret_near:
    call    cpu_pop16
    jc      .out_of_bounds
    test    ax, ax
    jz      .step_prog_end
    mov     [reg_IP], ax
    jmp     .step_ok

.is_ret_imm16:
    call    cpu_pop16
    jc      .out_of_bounds
    test    ax, ax
    jz      .step_prog_end
    mov     [reg_IP], ax
    mov     dx, word [ebp+1]
    add     [reg_SP], dx
    jmp     .step_ok

.is_retf_far:
    call    cpu_pop_far
    jc      .out_of_bounds
    test    ax, ax
    jz      .step_prog_end
    mov     [reg_IP], ax
    mov     [reg_CS], dx
    jmp     .step_ok

.is_retf_imm16:
    call    cpu_pop_far
    jc      .out_of_bounds
    test    ax, ax
    jz      .step_prog_end
    mov     [reg_IP], ax
    mov     [reg_CS], dx
    mov     si, word [ebp+1]
    add     [reg_SP], si
    jmp     .step_ok

.is_call_near:
    mov     ax, [reg_IP]
    add     ax, 3
    call    cpu_push16
    jc      .out_of_bounds
    mov     cx, word [ebp+1]
    add     [reg_IP], cx
    add     word [reg_IP], 3
    jmp     .step_ok

.is_call_far:
    mov     ax, [reg_IP]
    add     ax, 5
    mov     dx, [reg_CS]
    call    cpu_push_far
    jc      .out_of_bounds
    mov     cx, word [ebp+1]
    mov     dx, word [ebp+3]
    mov     [reg_IP], cx
    mov     [reg_CS], dx
    jmp     .step_ok

.is_jmp_far:
    mov     cx, word [ebp+1]
    mov     dx, word [ebp+3]
    mov     [reg_IP], cx
    mov     [reg_CS], dx
    jmp     .step_ok

.is_jmp_near:
    mov     cx, word [ebp+1]
    add     word [reg_IP], 3
    add     [reg_IP], cx
    jmp     .step_ok

.is_jmp_short:
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    add     [reg_IP], cx
    jmp     .step_ok

.is_loopnz:
    dec     word [reg_CX]
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    cmp     word [reg_CX], 0
    je      .step_ok
    cmp     byte [flag_states + FLAG_ZR], 0
    jne     .step_ok
    add     [reg_IP], cx
    jmp     .step_ok

.is_loopz:
    dec     word [reg_CX]
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    cmp     word [reg_CX], 0
    je      .step_ok
    cmp     byte [flag_states + FLAG_ZR], 1
    jne     .step_ok
    add     [reg_IP], cx
    jmp     .step_ok

.is_loop:
    dec     word [reg_CX]
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    cmp     word [reg_CX], 0
    je      .step_ok
    add     [reg_IP], cx
    jmp     .step_ok

.is_jcxz:
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    cmp     word [reg_CX], 0
    jne     .step_ok
    add     [reg_IP], cx
    jmp     .step_ok

.is_jcc:
    mov     dl, al
    and     dl, 1

    shr     al, 1
    and     al, 7

    cmp     al, 0
    jne     .jcc_1
    mov     dh, [flag_states + FLAG_OV]
    jmp     .jcc_eval_done

.jcc_1:
    cmp     al, 1
    jne     .jcc_2
    mov     dh, [flag_states + FLAG_CY]
    jmp     .jcc_eval_done

.jcc_2:
    cmp     al, 2
    jne     .jcc_3
    mov     dh, [flag_states + FLAG_ZR]
    jmp     .jcc_eval_done

.jcc_3:
    cmp     al, 3
    jne     .jcc_4
    mov     dh, [flag_states + FLAG_CY]
    or      dh, [flag_states + FLAG_ZR]
    jmp     .jcc_eval_done

.jcc_4:
    cmp     al, 4
    jne     .jcc_5
    mov     dh, [flag_states + FLAG_NG]
    jmp     .jcc_eval_done

.jcc_5:
    cmp     al, 5
    jne     .jcc_6
    mov     dh, [flag_states + FLAG_PE]
    jmp     .jcc_eval_done

.jcc_6:
    cmp     al, 6
    jne     .jcc_7
    mov     dh, [flag_states + FLAG_NG]
    cmp     dh, [flag_states + FLAG_OV]
    setne   dh
    jmp     .jcc_eval_done

.jcc_7:
    mov     dh, [flag_states + FLAG_NG]
    cmp     dh, [flag_states + FLAG_OV]
    setne   dh
    or      dh, [flag_states + FLAG_ZR]

.jcc_eval_done:
    xor     dh, dl
    movsx   cx, byte [ebp+1]
    add     word [reg_IP], 2
    test    dh, dh
    jz      .step_ok
    add     [reg_IP], cx
    jmp     .step_ok

.is_fe_ff:
    mov     ah, al
    and     al, 1
    mov     bl, al
    call    decode_modrm
    jc      .out_of_bounds
    test    edx, edx
    jz      .fe_ff_inc
    cmp     edx, 1
    je      .fe_ff_dec
    cmp     edx, 2
    je      .ff_call_near
    cmp     edx, 3
    je      .ff_call_far
    cmp     edx, 4
    je      .ff_jmp_near
    cmp     edx, 5
    je      .ff_jmp_far
    cmp     edx, 6
    je      .ff_push
    jmp     .unknown_insn

.fe_ff_dec:
    test    byte [ebp], 1
    jz      .fe_dec_b
    dec     word [edi]
    pushfd
    pop     edx
    mov     al, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], al
    add     [reg_IP], cx
    jmp     .step_ok
.fe_dec_b:
    dec     byte [edi]
    pushfd
    pop     edx
    mov     al, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], al
    add     [reg_IP], cx
    jmp     .step_ok

.fe_ff_inc:
    test    byte [ebp], 1
    jz      .fe_inc_b
    inc     word [edi]
    pushfd
    pop     edx
    mov     al, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], al
    add     [reg_IP], cx
    jmp     .step_ok
.fe_inc_b:
    inc     byte [edi]
    pushfd
    pop     edx
    mov     al, [flag_states + FLAG_CY]
    call    update_flags_from_eflags
    mov     [flag_states + FLAG_CY], al
    add     [reg_IP], cx
    jmp     .step_ok

.ff_call_near:
    test    byte [ebp], 1
    jz      .unknown_insn
    mov     si, word [edi]
    mov     ax, [reg_IP]
    add     ax, cx
    call    cpu_push16
    jc      .out_of_bounds
    mov     [reg_IP], si
    jmp     .step_ok

.ff_call_far:
    test    byte [ebp], 1
    jz      .unknown_insn
    cmp     byte [ebp+1], 0C0h
    jae     .unknown_insn
    mov     si, word [edi]
    mov     ax, [reg_IP]
    add     ax, cx
    mov     dx, [reg_CS]
    call    cpu_push_far
    jc      .out_of_bounds
    mov     dx, word [edi+2]
    mov     [reg_IP], si
    mov     [reg_CS], dx
    jmp     .step_ok

.ff_jmp_near:
    test    byte [ebp], 1
    jz      .unknown_insn
    mov     si, word [edi]
    mov     [reg_IP], si
    jmp     .step_ok

.ff_jmp_far:
    test    byte [ebp], 1
    jz      .unknown_insn
    cmp     byte [ebp+1], 0C0h
    jae     .unknown_insn
    mov     si, word [edi]
    mov     dx, word [edi+2]
    mov     [reg_IP], si
    mov     [reg_CS], dx
    jmp     .step_ok

.ff_push:
    test    byte [ebp], 1
    jz      .unknown_insn
    mov     ax, word [edi]
    push    ecx
    call    cpu_push16
    pop     ecx
    jc      .out_of_bounds
    add     [reg_IP], cx
    jmp     .step_ok

; ============================================================================
; 7. CATEGORY: STRING OPERATIONS
; ============================================================================
.is_rep_prefix:
    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds

    mov     dh, byte [ebp]      ; dh = prefix (F3h or F2h)
    mov     dl, byte [ebp+1]    ; dl = opcode or segment prefix

    cmp     dl, 26h
    je      .rep_has_es
    cmp     dl, 2Eh
    je      .rep_has_cs
    cmp     dl, 36h
    je      .rep_has_ss
    cmp     dl, 3Eh
    je      .rep_has_ds

    push    2                   ; [esp] = insn_len (relative to ebp)
    jmp     .rep_check_opcode

.rep_has_es:
    mov     dword [seg_override], reg_ES
    jmp     .rep_has_override
.rep_has_cs:
    mov     dword [seg_override], reg_CS
    jmp     .rep_has_override
.rep_has_ss:
    mov     dword [seg_override], reg_SS
    jmp     .rep_has_override
.rep_has_ds:
    mov     dword [seg_override], reg_DS

.rep_has_override:
    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    call    calc_linear_addr
    mov     ecx, 3
    call    check_mem_range
    jc      .out_of_bounds
    mov     dl, byte [ebp+2]    ; opcode after segment prefix
    push    3                   ; [esp] = insn_len (relative to ebp)

.rep_check_opcode:
    cmp     dl, 0A4h
    jb      .rep_invalid
    cmp     dl, 0A7h
    jbe     .rep_opcode_ok
    cmp     dl, 0AAh
    jb      .rep_invalid
    cmp     dl, 0AFh
    jbe     .rep_opcode_ok

.rep_invalid:
    pop     eax
    jmp     .unknown_insn

.rep_opcode_ok:
    cmp     word [reg_CX], 0
    je      .rep_complete

    mov     al, dl              ; al = opcode
    call    exec_one_string_op
    jnc     .rep_op_succeeded
    pop     eax
    jmp     .out_of_bounds

.rep_op_succeeded:
    dec     word [reg_CX]
    jz      .rep_complete

    cmp     dl, 0A6h
    je      .rep_check_zf
    cmp     dl, 0A7h
    je      .rep_check_zf
    cmp     dl, 0AEh
    je      .rep_check_zf
    cmp     dl, 0AFh
    je      .rep_check_zf
    jmp     .rep_not_complete

.rep_check_zf:
    cmp     dh, 0F3h
    je      .rep_check_repe
    ; REPNE (F2h): terminate if ZF == 1
    cmp     byte [flag_states + FLAG_ZR], 0
    jne     .rep_complete
    jmp     .rep_not_complete

.rep_check_repe:
    ; REPE (F3h): terminate if ZF == 0
    cmp     byte [flag_states + FLAG_ZR], 0
    je      .rep_complete

.rep_not_complete:
    pop     eax
    mov     ax, [step_initial_ip]
    mov     [reg_IP], ax
    jmp     .step_ok

.rep_complete:
    pop     eax                 ; insn_len relative to ebp
    add     ax, word [prefix_len]
    add     ax, [step_initial_ip]
    mov     [reg_IP], ax
    jmp     .step_ok

.is_single_string_op:
    call    exec_one_string_op
    jc      .out_of_bounds
    add     word [reg_IP], 1
    jmp     .step_ok

; ============================================================================
; 8. CATEGORY: INPUT / OUTPUT (I/O)
; ============================================================================
.in_al_imm:
    movzx   edx, byte [ebp+1]
    mov     al, [io_ports + edx]
    mov     byte [reg_AX], al
    add     word [reg_IP], 2
    jmp     .step_ok

.in_ax_imm:
    movzx   edx, byte [ebp+1]
    mov     ax, word [io_ports + edx]
    mov     word [reg_AX], ax
    add     word [reg_IP], 2
    jmp     .step_ok

.out_al_imm:
    movzx   edx, byte [ebp+1]
    mov     al, byte [reg_AX]
    mov     [io_ports + edx], al
    add     word [reg_IP], 2
    jmp     .step_ok

.out_ax_imm:
    movzx   edx, byte [ebp+1]
    mov     ax, word [reg_AX]
    mov     word [io_ports + edx], ax
    add     word [reg_IP], 2
    jmp     .step_ok

.in_al_dx:
    movzx   edx, word [reg_DX]
    mov     al, [io_ports + edx]
    mov     byte [reg_AX], al
    add     word [reg_IP], 1
    jmp     .step_ok

.in_ax_dx:
    movzx   edx, word [reg_DX]
    mov     al, [io_ports + edx]
    mov     byte [reg_AX], al
    inc     dx
    movzx   edx, dx
    mov     al, [io_ports + edx]
    mov     byte [reg_AX+1], al
    add     word [reg_IP], 1
    jmp     .step_ok

.out_dx_al:
    movzx   edx, word [reg_DX]
    mov     al, byte [reg_AX]
    mov     [io_ports + edx], al
    add     word [reg_IP], 1
    jmp     .step_ok

.out_dx_ax:
    movzx   edx, word [reg_DX]
    mov     al, byte [reg_AX]
    mov     [io_ports + edx], al
    inc     dx
    movzx   edx, dx
    mov     al, byte [reg_AX+1]
    mov     [io_ports + edx], al
    add     word [reg_IP], 1
    jmp     .step_ok

; ============================================================================
; 9. CATEGORY: INTERRUPTS & SYSTEM CONTROL
; ============================================================================
.op_int:
    mov     al, [ebp+1]
    cmp     al, INT_VECTOR_20
    je      .step_prog_end
    cmp     al, INT_VECTOR_21
    je      .exec_int21
    cmp     al, INT_VECTOR_10
    je      .exec_int10
    cmp     al, INT_VECTOR_16
    je      .exec_int16
    add     word [reg_IP], 2
    jmp     .step_ok

.exec_int21:
    call    handle_int21
    cmp     eax, STEP_PROGRAM_END
    je      .step_prog_end
    jmp     .step_ok

.exec_int10:
    call    handle_int10
    jmp     .step_ok

.exec_int16:
    call    handle_int16
    jmp     .step_ok

.is_nop:
    add     word [reg_IP], 1
    jmp     .step_ok

.is_wait:
    add     word [reg_IP], 1
    jmp     .step_ok

.is_hlt:
    add     word [reg_IP], 1
    jmp     .step_breakpoint

.is_int3:
    add     word [reg_IP], 1
    jmp     .step_breakpoint

.is_into:
    add     word [reg_IP], 1
    cmp     byte [flag_states + FLAG_OV], 0
    jz      .step_ok
    jmp     .step_breakpoint

.is_iret:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 6
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, word [memory + eax]
    mov     [reg_IP], dx
    mov     dx, word [memory + eax + 2]
    mov     [reg_CS], dx
    mov     ax, word [memory + eax + 4]
    add     word [reg_SP], 6
    call    unpack_flags
    jmp     .step_ok

; ============================================================================
; 10. COMMON TERMINATION HANDLERS
; ============================================================================
.unknown_insn:
    mov     dword [seg_override], 0
    mov     ax, [step_initial_ip]
    mov     [reg_IP], ax
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     eax, STEP_UNKNOWN
    ret

.out_of_bounds:
    mov     dword [seg_override], 0
    mov     ax, [step_initial_ip]
    mov     [reg_IP], ax
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     eax, STEP_ERROR
    ret

.step_prog_end:
    mov     dword [seg_override], 0
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     eax, STEP_PROGRAM_END
    ret

.step_ok:
    mov     dword [seg_override], 0
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     eax, STEP_OK
    ret

.step_breakpoint:
    mov     dword [seg_override], 0
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     eax, STEP_BREAKPOINT
    ret


