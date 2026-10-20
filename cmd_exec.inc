handle_exec_interrupted:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer
    jmp     show_cpu_state

handle_exec_prog_end:
    mov     esi, msg_prog_end
    mov     ecx, msg_prog_end_len
    call    print_buffer
    ret

handle_exec_error:
    call    print_error
    ret

handle_step_result:
    call    step
    cmp     eax, STEP_OK
    je      .ok
    cmp     eax, STEP_BREAKPOINT
    je      .ok
    cmp     eax, STEP_PROGRAM_END
    je      .prog_end
    cmp     eax, STEP_UNKNOWN
    je      .unknown
    call    handle_exec_error
    stc
    ret

.prog_end:
    call    handle_exec_prog_end
    stc
    ret

.unknown:
    call    show_cpu_state
    stc
    ret

.ok:
    clc
    ret

cmd_go:
    mov     word [num_breakpoints], 0
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .start_run

    mov     al, [esi]
    cmp     al, '='
    jne     .parse_bp_loop

    inc     esi
    call    parse_address_cs
    jc      print_error_and_ret
    mov     [reg_CS], ax
    mov     [reg_IP], bx

.parse_bp_loop:
    call    skip_whitespace
    call    is_eol
    jc      .start_run
    
    mov     cx, [num_breakpoints]
    cmp     cx, MAX_BREAKPOINTS
    jae     .too_many_bp

    push    cx
    call    parse_address_cs
    pop     cx
    jc      print_error_and_ret
    
    movzx   ecx, cx
    mov     [breakpoints_seg + ecx*2], ax
    mov     [breakpoints_off + ecx*2], bx
    inc     cx
    mov     [num_breakpoints], cx
    jmp     .parse_bp_loop

.start_run:
    mov     byte [ctrl_c_flag], 0
    call    handle_step_result
    jc      .ret
    cmp     eax, STEP_BREAKPOINT
    je      show_cpu_state
    jmp     .run_loop

.run_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     handle_exec_interrupted

    mov     cx, [num_breakpoints]
    test    cx, cx
    jz      .no_bp
    
    movzx   ecx, cx
    xor     edx, edx
.bp_check:
    cmp     edx, ecx
    jae     .no_bp
    mov     ax, [breakpoints_seg + edx*2]
    cmp     ax, [reg_CS]
    jne     .next_bp
    mov     bx, [breakpoints_off + edx*2]
    cmp     bx, [reg_IP]
    je      show_cpu_state

.next_bp:
    inc     edx
    jmp     .bp_check

.no_bp:
    call    handle_step_result
    jc      .ret
    cmp     eax, STEP_BREAKPOINT
    je      show_cpu_state
    jmp     .run_loop

.too_many_bp:
    call    print_bp_error
.ret:
    ret
parse_exec_params:
    mov     ax, 1
    push    eax
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      .pep_ok

    mov     al, [esi]
    cmp     al, '='
    jne     .pep_count

    inc     esi
    call    parse_address_cs
    jc      .pep_err
    mov     [reg_CS], ax
    mov     [reg_IP], bx

    call    skip_whitespace
    call    is_eol
    jc      .pep_ok

.pep_count:
    call    parse_hex
    jc      .pep_err
    test    ax, ax
    jz      .pep_err
    mov     [esp], ax

    call    skip_whitespace
    call    is_eol
    jnc     .pep_err

.pep_ok:
    pop     eax
    clc
    ret

.pep_err:
    add     esp, 4
    call    print_error
    stc
    ret

cmd_trace:
    call    parse_exec_params
    jc      .ret
    mov     [trace_count], ax

.start_trace:
    mov     byte [ctrl_c_flag], 0

.trace_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     handle_exec_interrupted

    call    handle_step_result
    jc      .ret

.step_ok:
    call    show_cpu_state
    dec     word [trace_count]
    jnz     .trace_loop
.ret:
    ret
cmd_proceed:
    call    parse_exec_params
    jc      .ret
    mov     [proceed_count], ax

.start_proceed:
    mov     byte [ctrl_c_flag], 0

.proceed_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     handle_exec_interrupted

    mov     ax, [reg_CS]
    mov     bx, [reg_IP]
    call    calc_linear_addr

    mov     ecx, 1
    call    check_mem_range
    jc      handle_exec_error

    lea     esi, [memory + eax]
    mov     edi, esi
    xor     dl, dl

.prefix_loop:
    mov     eax, edi
    sub     eax, memory
    cmp     eax, MEM_SIZE
    jae     .not_step_over

    mov     al, [edi]
    cmp     al, 26h
    je      .is_override
    cmp     al, 2Eh
    je      .is_override
    cmp     al, 36h
    je      .is_override
    cmp     al, 3Eh
    je      .is_override
    cmp     al, 0F0h
    je      .is_override

    cmp     al, 0F2h
    je      .is_rep
    cmp     al, 0F3h
    je      .is_rep
    jmp     .inspect_opcode

.is_override:
    inc     edi
    jmp     .prefix_loop

.is_rep:
    mov     dl, 1
    inc     edi
    jmp     .prefix_loop

.inspect_opcode:
    test    dl, dl
    jz      .not_rep_string

    cmp     al, 0A4h
    jb      .not_step_over
    cmp     al, 0A7h
    jbe     .is_rep_string
    cmp     al, 0AAh
    jb      .not_step_over
    cmp     al, 0AFh
    jbe     .is_rep_string
    jmp     .not_step_over

.is_rep_string:
    lea     ecx, [edi + 1]
    sub     ecx, esi
    jmp     .do_step_over

.not_rep_string:
    cmp     al, 0E8h
    jne     .not_call_near
    lea     ecx, [edi + 3]
    sub     ecx, esi
    jmp     .do_step_over
.not_call_near:

    cmp     al, 9Ah
    jne     .not_call_far
    lea     ecx, [edi + 5]
    sub     ecx, esi
    jmp     .do_step_over
.not_call_far:

    cmp     al, 0FFh
    jne     .not_call_indirect
    mov     eax, edi
    sub     eax, memory
    inc     eax
    cmp     eax, MEM_SIZE
    jae     .not_step_over

    mov     al, [edi + 1]
    mov     ah, al
    shr     ah, 3
    and     ah, 7
    cmp     ah, 2
    je      .is_ff_call
    cmp     ah, 3
    jne     .not_step_over

.is_ff_call:
    push    esi
    mov     esi, edi
    call    decode_modrm_ea
    pop     esi
    lea     ecx, [edi + ecx + 2]
    sub     ecx, esi
    jmp     .do_step_over
.not_call_indirect:

    cmp     al, 0CDh
    jne     .not_int_imm
    lea     ecx, [edi + 2]
    sub     ecx, esi
    jmp     .do_step_over
.not_int_imm:

    cmp     al, 0CCh
    jne     .not_int3
    lea     ecx, [edi + 1]
    sub     ecx, esi
    jmp     .do_step_over
.not_int3:

    cmp     al, 0CEh
    jne     .not_into
    lea     ecx, [edi + 1]
    sub     ecx, esi
    jmp     .do_step_over
.not_into:

    cmp     al, 0E0h
    je      .is_loop_insn
    cmp     al, 0E1h
    je      .is_loop_insn
    cmp     al, 0E2h
    je      .is_loop_insn
    cmp     al, 0E3h
    je      .is_loop_insn

    jmp     .not_step_over

.is_loop_insn:
    lea     ecx, [edi + 2]
    sub     ecx, esi
    jmp     .do_step_over

.not_step_over:
    call    handle_step_result
    jc      .ret

.proceed_step_ok:
    call    show_cpu_state
    dec     word [proceed_count]
    jnz     .proceed_loop
    ret

.do_step_over:
    mov     ax, [reg_CS]
    mov     [proceed_target_seg], ax
    mov     ax, [reg_IP]
    add     ax, cx
    mov     [proceed_target_off], ax

.proceed_step_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     handle_exec_interrupted

    call    handle_step_result
    jc      .ret
    cmp     eax, STEP_BREAKPOINT
    je      .proceed_hit_target
    jmp     .proceed_check_target

.proceed_check_target:
    mov     ax, [reg_CS]
    cmp     ax, [proceed_target_seg]
    jne     .proceed_step_loop
    mov     bx, [reg_IP]
    cmp     bx, [proceed_target_off]
    jne     .proceed_step_loop

.proceed_hit_target:
    call    show_cpu_state
    dec     word [proceed_count]
    jnz     .proceed_loop
    ret

.ret:
    ret
