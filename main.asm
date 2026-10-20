format PE CONSOLE

entry start

include 'fasm/include/win32a.inc'

include 'data.inc'

section '.text' code readable executable
include 'hex.inc'
include 'dump.inc'
include 'utils.inc'

ctrl_handler:
    mov     eax, [esp+4]
    cmp     eax, 0
    je      .handled
    cmp     eax, 1
    je      .handled
    xor     eax, eax
    ret     4

.handled:
    mov     byte [ctrl_c_flag], 1
    mov     eax, 1
    ret     4

start:
    invoke  GetStdHandle, STD_OUTPUT_HANDLE
    mov     [hStdOut], eax

    invoke  GetStdHandle, STD_INPUT_HANDLE
    mov     [hStdIn], eax

    invoke  SetConsoleOutputCP, 866

    invoke  SetConsoleCtrlHandler, ctrl_handler, 1

    mov     ecx, MEM_SIZE
    mov     edi, memory
    xor     eax, eax
.init_mem:
    mov     [edi], al
    inc     edi
    loop    .init_mem

    call    init_psp
    mov     ax, [reg_DS]
    mov     [dump_seg], ax
    mov     ax, [reg_CS]
    mov     [unasm_seg], ax
    call    parse_startup_cmdline

main_loop:
    mov     byte [ctrl_c_flag], 0
    mov     dword [prompt_len], 1
    invoke  WriteConsoleA, [hStdOut], prompt, 1, chars_written, 0
    test    eax, eax
    jnz     .prompt_ok
    invoke  WriteFile, [hStdOut], prompt, 1, chars_written, 0
.prompt_ok:

    mov     edi, input_buffer
    mov     edx, INPUT_BUFFER_MAX
    call    read_line_console_or_pipe
    jnc     .check_read_count

    cmp     byte [ctrl_c_flag], 0
    jnz     .read_failed
    jmp     exit_program

.check_read_count:
    cmp     dword [chars_read], 0
    jz      .read_failed

    mov     byte [ctrl_c_flag], 0
    mov     esi, input_buffer
    call    skip_whitespace

    call    is_eol
    jc      main_loop

    mov     [cmd_ptr], esi
    mov     al, [esi]
    or      al, 20h

    mov     esi, COMTAB
.find_cmd:
    mov     bl, [esi + CMD_ENTRY_CHAR_OFF]
    test    bl, bl
    jz      .cmd_not_found
    cmp     bl, al
    je      .run_cmd
    add     esi, COMTAB_RECORD_SIZE
    jmp     .find_cmd
.run_cmd:
    mov     eax, [esi + CMD_ENTRY_HANDLER_OFF]
    inc     dword [cmd_ptr]
    call    eax
    jmp     main_loop

.cmd_not_found:
    mov     esi, [cmd_ptr]
    call    print_error
    jmp     main_loop

.read_failed:
    cmp     byte [ctrl_c_flag], 0
    jnz     .prompt_crlf
    jmp     main_loop

.prompt_crlf:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer
    jmp     main_loop

cmd_help:
    mov     esi, help_text
    mov     ecx, help_text_len
    call    print_buffer
    ret

include 'cmd_reg.inc'

cmd_quit:
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      exit_program
    jmp     print_error_and_ret

include 'dos_file.inc'

include 'cmd_memory.inc'

include 'disasm.inc'

include 'asm.inc'

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
    call    step
    cmp     eax, STEP_OK
    je      .run_loop
    cmp     eax, STEP_BREAKPOINT
    je      show_cpu_state
    cmp     eax, STEP_PROGRAM_END
    je      handle_exec_prog_end
    cmp     eax, STEP_UNKNOWN
    je      show_cpu_state
    jmp     handle_exec_error

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
    call    step
    cmp     eax, STEP_OK
    je      .run_loop
    cmp     eax, STEP_BREAKPOINT
    je      show_cpu_state
    cmp     eax, STEP_PROGRAM_END
    je      handle_exec_prog_end
    cmp     eax, STEP_UNKNOWN
    je      show_cpu_state
    jmp     handle_exec_error

.too_many_bp:
    call    print_bp_error
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

    call    step
    cmp     eax, STEP_OK
    je      .step_ok
    cmp     eax, STEP_BREAKPOINT
    je      .step_ok
    cmp     eax, STEP_PROGRAM_END
    je      handle_exec_prog_end
    cmp     eax, STEP_UNKNOWN
    je      show_cpu_state
    jmp     handle_exec_error

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
    mov     dh, al
    shr     dh, 6
    and     dh, 3
    and     al, 7
    cmp     dh, 3
    je      .ff_len_2
    cmp     dh, 1
    je      .ff_len_3
    cmp     dh, 2
    je      .ff_len_4
    cmp     al, 6
    je      .ff_len_4
.ff_len_2:
    lea     ecx, [edi + 2]
    sub     ecx, esi
    jmp     .do_step_over
.ff_len_3:
    lea     ecx, [edi + 3]
    sub     ecx, esi
    jmp     .do_step_over
.ff_len_4:
    lea     ecx, [edi + 4]
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
    call    step
    cmp     eax, STEP_OK
    je      .proceed_step_ok
    cmp     eax, STEP_BREAKPOINT
    je      .proceed_hit_target
    cmp     eax, STEP_PROGRAM_END
    je      handle_exec_prog_end
    cmp     eax, STEP_UNKNOWN
    je      show_cpu_state
    jmp     handle_exec_error

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

    call    step
    cmp     eax, STEP_OK
    je      .proceed_check_target
    cmp     eax, STEP_BREAKPOINT
    je      .proceed_hit_target
    cmp     eax, STEP_PROGRAM_END
    je      handle_exec_prog_end
    cmp     eax, STEP_UNKNOWN
    je      show_cpu_state
    jmp     handle_exec_error

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

check_char_available:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

    cmp     byte [kbd_peek_valid], 1
    je      .cca_avail

    invoke  GetConsoleMode, [hStdIn], kbd_temp_mode
    test    eax, eax
    jz      .cca_not_console

.cca_console_loop:
    mov     dword [events_read], 0
    invoke  PeekConsoleInputA, [hStdIn], input_record, 1, events_read
    test    eax, eax
    jz      .cca_none
    cmp     dword [events_read], 0
    jz      .cca_none

    cmp     word [input_record], 1
    jne     .cca_discard

    cmp     dword [input_record + 4], 0
    je      .cca_discard

    cmp     byte [input_record + 14], 0
    jne     .cca_got_key

    movzx   eax, word [input_record + 10]
    cmp     eax, 10h    ; VK_SHIFT
    je      .cca_discard
    cmp     eax, 11h    ; VK_CONTROL
    je      .cca_discard
    cmp     eax, 12h    ; VK_MENU
    je      .cca_discard
    cmp     eax, 14h    ; VK_CAPITAL
    je      .cca_discard
    cmp     eax, 90h    ; VK_NUMLOCK
    je      .cca_discard
    cmp     eax, 91h    ; VK_SCROLL
    je      .cca_discard

    cmp     word [input_record + 12], 0
    je      .cca_discard
    jmp     .cca_got_key

.cca_discard:
    invoke  ReadConsoleInputA, [hStdIn], input_record, 1, events_read
    jmp     .cca_console_loop

.cca_got_key:
    invoke  ReadConsoleInputA, [hStdIn], input_record, 1, events_read
    mov     al, [input_record + 14]
    mov     [kbd_peek_char], al
    mov     al, [input_record + 12]
    mov     [kbd_peek_scan], al
    mov     byte [kbd_peek_valid], 1
    jmp     .cca_avail

.cca_not_console:
    mov     dword [temp_pipe_avail], 0
    invoke  PeekNamedPipe, [hStdIn], 0, 0, 0, temp_pipe_avail, 0
    test    eax, eax
    jz      .cca_try_file
    cmp     dword [temp_pipe_avail], 0
    jz      .cca_none
    invoke  ReadFile, [hStdIn], kbd_peek_char, 1, events_read, 0
    test    eax, eax
    jz      .cca_none
    cmp     dword [events_read], 1
    jne     .cca_none
    call    .cca_setup_scan
    mov     byte [kbd_peek_valid], 1
    jmp     .cca_avail

.cca_try_file:
    invoke  ReadFile, [hStdIn], kbd_peek_char, 1, events_read, 0
    test    eax, eax
    jz      .cca_eof
    cmp     dword [events_read], 1
    jne     .cca_eof
    call    .cca_setup_scan
    mov     byte [kbd_peek_valid], 1
    jmp     .cca_avail

.cca_eof:
    mov     byte [stdin_eof], 1
    jmp     .cca_none

.cca_setup_scan:
    mov     byte [kbd_peek_scan], 0
    mov     dl, [kbd_peek_char]
    cmp     dl, 13
    jne     .css_not_cr
    mov     byte [kbd_peek_scan], 1Ch
    ret
.css_not_cr:
    cmp     dl, 8
    jne     .css_not_bs
    mov     byte [kbd_peek_scan], 0Eh
    ret
.css_not_bs:
    cmp     dl, 9
    jne     .css_not_tab
    mov     byte [kbd_peek_scan], 0Fh
    ret
.css_not_tab:
    cmp     dl, 27
    jne     .css_not_esc
    mov     byte [kbd_peek_scan], 01h
    ret
.css_not_esc:
    ret

.cca_avail:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    mov     al, 1
    ret

.cca_none:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    xor     al, al
    ret

get_keystroke:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

.gk_loop:
    cmp     byte [ctrl_c_flag], 0
    jne     .gk_ctrl_c
    cmp     byte [stdin_eof], 0
    jne     .gk_eof
    call    check_char_available
    test    al, al
    jnz     .gk_have_char
    cmp     byte [stdin_eof], 0
    jne     .gk_eof
    invoke  Sleep, 10
    jmp     .gk_loop

.gk_have_char:
    mov     byte [kbd_peek_valid], 0
    mov     al, [kbd_peek_char]
    mov     ah, [kbd_peek_scan]
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

.gk_eof:
    mov     al, 1Ah
    xor     ah, ah
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

.gk_ctrl_c:
    xor     ax, ax
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
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

handle_int21:
    push    ebx
    push    esi
    push    edi
    push    ebp

    mov     ah, byte [reg_AX+1]
    cmp     ah, 00h
    je      .prog_end
    cmp     ah, 01h
    je      .ah01
    cmp     ah, 02h
    je      .ah02
    cmp     ah, 06h
    je      .ah06
    cmp     ah, 07h
    je      .ah07_08
    cmp     ah, 08h
    je      .ah07_08
    cmp     ah, INT21_AH_PRINT_STRING
    je      .ah09
    cmp     ah, INT21_AH_BUFFERED_INPUT
    je      .ah0a
    cmp     ah, 0Bh
    je      .ah0b
    cmp     ah, 25h
    je      .ah25
    cmp     ah, 30h
    je      .ah30
    cmp     ah, 35h
    je      .ah35
    cmp     ah, INT21_AH_EXIT
    je      .prog_end
    jmp     .done

.ah01:
    call    get_keystroke
    mov     byte [reg_AX], al
    cmp     al, CR
    jne     .ah01_not_cr
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer
    jmp     .done
.ah01_not_cr:
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    jmp     .done

.ah02:
    mov     al, byte [reg_DX]
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    mov     al, byte [reg_DX]
    mov     byte [reg_AX], al
    jmp     .done

.ah06:
    cmp     byte [reg_DX], 0FFh
    jne     .ah06_out
    call    check_char_available
    test    al, al
    jz      .ah06_no_char
    mov     byte [kbd_peek_valid], 0
    mov     al, [kbd_peek_char]
    mov     byte [reg_AX], al
    mov     byte [flag_states + FLAG_ZR], 0
    jmp     .done
.ah06_no_char:
    mov     byte [reg_AX], 0
    mov     byte [flag_states + FLAG_ZR], 1
    jmp     .done
.ah06_out:
    mov     al, byte [reg_DX]
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    mov     al, byte [reg_DX]
    mov     byte [reg_AX], al
    jmp     .done

.ah07_08:
    call    get_keystroke
    mov     byte [reg_AX], al
    jmp     .done

.ah09:
    mov     ax, [reg_DS]
    mov     bx, [reg_DX]
    call    calc_linear_addr
    
    mov     ecx, MEM_SIZE
    sub     ecx, eax
    jbe     .done
    
    mov     esi, memory
    add     esi, eax
    mov     edi, esi
    push    ecx
    mov     al, '$'
    repne   scasb
    pop     ecx
    jne     .done
    
    mov     edx, edi
    sub     edx, esi
    dec     edx
    jz      .done
    
    mov     ecx, edx
    call    print_buffer
    jmp     .done

.ah0a:
    mov     ax, [reg_DS]
    mov     bx, [reg_DX]
    call    calc_linear_addr

    cmp     eax, MEM_SIZE - 2
    jae     .done

    mov     edi, memory
    add     edi, eax

    movzx   ecx, byte [edi]
    test    ecx, ecx
    jnz     .ah0a_have_max
    mov     ecx, 255
    mov     byte [edi], cl
.ah0a_have_max:

    mov     edx, MEM_SIZE - 3
    sub     edx, eax
    jbe     .done
    cmp     ecx, edx
    jbe     .ah0a_len_ok
    mov     ecx, edx
.ah0a_len_ok:

    mov     dword [int21_old_console_mode], 0
    invoke  GetConsoleMode, [hStdIn], int21_old_console_mode
    test    eax, eax
    jz      .ah0a_no_setmode
    mov     eax, [int21_old_console_mode]
    or      eax, ENABLE_PROCESSED_INPUT or ENABLE_LINE_INPUT or ENABLE_ECHO_INPUT
    invoke  SetConsoleMode, [hStdIn], eax
.ah0a_no_setmode:

    mov     dword [int21_chars_read], 0
    invoke  ReadConsoleA, [hStdIn], int21_input_buf, 255, int21_chars_read, 0
    test    eax, eax
    jnz     .ah0a_read_ok
    ; Pipe fallback for INT 21h AH=0Ah
    xor     ecx, ecx
.ah0a_pipe_loop:
    cmp     ecx, 254
    jae     .ah0a_pipe_done
    push    ecx
    lea     eax, [int21_input_buf + ecx]
    invoke  ReadFile, [hStdIn], eax, 1, int21_chars_read, 0
    pop     ecx
    test    eax, eax
    jz      .ah0a_pipe_done
    cmp     dword [int21_chars_read], 0
    jz      .ah0a_pipe_done
    mov     al, [int21_input_buf + ecx]
    inc     ecx
    cmp     al, LF
    je      .ah0a_pipe_done
    jmp     .ah0a_pipe_loop
.ah0a_pipe_done:
    mov     [int21_chars_read], ecx
.ah0a_read_ok:

    cmp     dword [int21_old_console_mode], 0
    jz      .ah0a_no_restoremode
    invoke  SetConsoleMode, [hStdIn], [int21_old_console_mode]
.ah0a_no_restoremode:

    cmp     byte [ctrl_c_flag], 0
    jne     .done

    mov     ebx, [int21_chars_read]
    xor     edx, edx
    mov     esi, int21_input_buf
.ah0a_count:
    test    ebx, ebx
    jz      .ah0a_count_done
    mov     al, [esi]
    cmp     al, 13
    je      .ah0a_count_done
    cmp     al, 10
    je      .ah0a_count_done
    inc     esi
    inc     edx
    dec     ebx
    jmp     .ah0a_count
.ah0a_count_done:

    cmp     edx, ecx
    jbe     .ah0a_clamp_ok
    mov     edx, ecx
.ah0a_clamp_ok:

    mov     byte [edi + 1], dl
    push    edi
    push    esi
    push    ecx
    cld
    lea     esi, [int21_input_buf]
    lea     edi, [edi + 2]
    mov     ecx, edx
    rep     movsb
    mov     byte [edi], 13
    pop     ecx
    pop     esi
    pop     edi
    jmp     .done

.ah0b:
    call    check_char_available
    test    al, al
    jz      .ah0b_none
    mov     byte [reg_AX], 0FFh
    jmp     .done
.ah0b_none:
    mov     byte [reg_AX], 00h
    jmp     .done

.ah25:
    movzx   eax, byte [reg_AX]
    shl     eax, 2
    mov     dx, [reg_DX]
    mov     word [memory + eax], dx
    mov     dx, [reg_DS]
    mov     word [memory + eax + 2], dx
    jmp     .done

.ah30:
    mov     word [reg_AX], 0002h
    mov     word [reg_BX], 0000h
    mov     word [reg_CX], 0000h
    jmp     .done

.ah35:
    movzx   eax, byte [reg_AX]
    shl     eax, 2
    mov     bx, word [memory + eax]
    mov     [reg_BX], bx
    mov     bx, word [memory + eax + 2]
    mov     [reg_ES], bx
    jmp     .done

.done:
    add     word [reg_IP], 2
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    mov     eax, STEP_OK
    ret

.prog_end:
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    mov     eax, STEP_PROGRAM_END
    ret


handle_int10:
    push    ebx
    push    esi
    push    edi
    push    ebp

    mov     ah, byte [reg_AX+1]
    cmp     ah, 0Eh
    je      .ah0e
    cmp     ah, 02h
    je      .ah02
    jmp     .done

.ah0e:
    mov     al, byte [reg_AX]
    mov     byte [line_buffer], al
    mov     esi, line_buffer
    mov     ecx, 1
    call    print_buffer
    jmp     .done

.ah02:
    movzx   eax, byte [reg_DX+1]
    shl     eax, 16
    mov     al, byte [reg_DX]
    invoke  SetConsoleCursorPosition, [hStdOut], eax

.done:
    add     word [reg_IP], 2
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    mov     eax, STEP_OK
    ret


handle_int16:
    push    ebx
    push    esi
    push    edi
    push    ebp

    mov     ah, byte [reg_AX+1]
    cmp     ah, 00h
    je      .ah00
    cmp     ah, 01h
    je      .ah01
    jmp     .done

.ah00:
    call    get_keystroke
    mov     word [reg_AX], ax
    jmp     .done

.ah01:
    call    check_char_available
    test    al, al
    jz      .ah01_none
    mov     byte [flag_states + FLAG_ZR], 0
    mov     al, [kbd_peek_char]
    mov     ah, [kbd_peek_scan]
    mov     word [reg_AX], ax
    jmp     .done
.ah01_none:
    mov     byte [flag_states + FLAG_ZR], 1

.done:
    add     word [reg_IP], 2
    pop     ebp
    pop     edi
    pop     esi
    pop     ebx
    mov     eax, STEP_OK
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
    mov     si, [edi]
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     word [memory + eax], si
    add     word [reg_IP], 1
    jmp     .step_ok

.is_pop_r16:
    sub     al, 58h
    movzx   eax, al
    mov     edi, [reg16_ptrs + eax*4]
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     cx, word [memory + eax]
    mov     [edi], cx
    add     word [reg_SP], 2
    add     word [reg_IP], 1
    jmp     .step_ok

.push_es:
    mov     dx, [reg_ES]
    jmp     .do_push_seg
.push_cs:
    mov     dx, [reg_CS]
    jmp     .do_push_seg
.push_ss:
    mov     dx, [reg_SS]
    jmp     .do_push_seg
.push_ds:
    mov     dx, [reg_DS]
.do_push_seg:
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     word [memory + eax], dx
    add     word [reg_IP], 1
    jmp     .step_ok

.pop_es:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, word [memory + eax]
    mov     [reg_ES], dx
    add     word [reg_SP], 2
    add     word [reg_IP], 1
    jmp     .step_ok
.pop_ss:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, word [memory + eax]
    mov     [reg_SS], dx
    add     word [reg_SP], 2
    add     word [reg_IP], 1
    jmp     .step_ok
.pop_ds:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, word [memory + eax]
    mov     [reg_DS], dx
    add     word [reg_SP], 2
    add     word [reg_IP], 1
    jmp     .step_ok

.is_pushf:
    call    pack_flags
    sub     word [reg_SP], 2
    mov     dx, ax
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     word [memory + eax], dx
    add     word [reg_IP], 1
    jmp     .step_ok

.is_popf:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     ax, word [memory + eax]
    add     word [reg_SP], 2
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
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    pop     edi
    pop     ecx
    jc      .out_of_bounds
    mov     dx, word [memory + eax]
    add     word [reg_SP], 2
    mov     word [edi], dx
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
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     cx, word [memory + eax]
    test    cx, cx
    jz      .step_prog_end
    mov     [reg_IP], cx
    add     word [reg_SP], 2
    jmp     .step_ok

.is_ret_imm16:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     cx, word [memory + eax]
    test    cx, cx
    jz      .step_prog_end
    mov     [reg_IP], cx
    add     word [reg_SP], 2
    mov     dx, word [ebp+1]
    add     [reg_SP], dx
    jmp     .step_ok

.is_retf_far:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 4
    call    check_mem_range
    jc      .out_of_bounds
    mov     cx, word [memory + eax]
    mov     dx, word [memory + eax + 2]
    test    cx, cx
    jz      .step_prog_end
    mov     [reg_IP], cx
    mov     [reg_CS], dx
    add     word [reg_SP], 4
    jmp     .step_ok

.is_retf_imm16:
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 4
    call    check_mem_range
    jc      .out_of_bounds
    mov     cx, word [memory + eax]
    mov     dx, word [memory + eax + 2]
    test    cx, cx
    jz      .step_prog_end
    mov     [reg_IP], cx
    mov     [reg_CS], dx
    add     word [reg_SP], 4
    mov     si, word [ebp+1]
    add     [reg_SP], si
    jmp     .step_ok

.is_call_near:
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 2
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, [reg_IP]
    add     dx, 3
    mov     word [memory + eax], dx
    mov     cx, word [ebp+1]
    add     [reg_IP], cx
    add     word [reg_IP], 3
    jmp     .step_ok

.is_call_far:
    sub     word [reg_SP], 4
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    mov     ecx, 4
    call    check_mem_range
    jc      .out_of_bounds
    mov     dx, [reg_IP]
    add     dx, 5
    mov     word [memory + eax], dx
    mov     dx, [reg_CS]
    mov     word [memory + eax + 2], dx
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
    mov     dx, [reg_IP]
    add     dx, cx
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    push    ecx
    mov     ecx, 2
    call    check_mem_range
    pop     ecx
    jc      .out_of_bounds
    mov     word [memory + eax], dx
    mov     [reg_IP], si
    jmp     .step_ok

.ff_call_far:
    test    byte [ebp], 1
    jz      .unknown_insn
    cmp     byte [ebp+1], 0C0h
    jae     .unknown_insn
    mov     si, word [edi]
    mov     dx, [reg_IP]
    add     dx, cx
    sub     word [reg_SP], 4
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    push    ecx
    mov     ecx, 4
    call    check_mem_range
    pop     ecx
    jc      .out_of_bounds
    mov     word [memory + eax], dx
    mov     dx, [reg_CS]
    mov     word [memory + eax+2], dx
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
    mov     si, word [edi]
    sub     word [reg_SP], 2
    mov     ax, [reg_SS]
    mov     bx, [reg_SP]
    call    calc_linear_addr
    push    ecx
    mov     ecx, 2
    call    check_mem_range
    pop     ecx
    jc      .out_of_bounds
    mov     word [memory + eax], si
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


section '.idata' import data readable writeable
    library kernel32, 'KERNEL32.DLL'

    import kernel32,\
           ExitProcess,           'ExitProcess',\
           GetStdHandle,          'GetStdHandle',\
           WriteConsoleA,         'WriteConsoleA',\
           ReadConsoleA,          'ReadConsoleA',\
           SetConsoleOutputCP,    'SetConsoleOutputCP',\
           GetConsoleMode,        'GetConsoleMode',\
           SetConsoleMode,        'SetConsoleMode',\
           SetConsoleCtrlHandler, 'SetConsoleCtrlHandler',\
           GetCommandLineA,       'GetCommandLineA',\
           CreateFileA,           'CreateFileA',\
           ReadFile,              'ReadFile',\
           WriteFile,             'WriteFile',\
           CloseHandle,           'CloseHandle',\
           GetFileSize,           'GetFileSize',\
           SetConsoleCursorPosition, 'SetConsoleCursorPosition',\
           PeekConsoleInputA,     'PeekConsoleInputA',\
           ReadConsoleInputA,     'ReadConsoleInputA',\
           PeekNamedPipe,         'PeekNamedPipe',\
           Sleep,                 'Sleep'

section '.bss' readable writeable
    current_filename rb 260
    input_buffer    rb INPUT_BUFFER_SIZE
    int21_input_buf rb INPUT_BUFFER_SIZE
    line_buffer     rb LINE_BUFFER_SIZE
    asm_token       rb ASM_TOKEN_SIZE
    asm_bytes       rb ASM_BYTES_SIZE
    io_ports        rb 10000h
    memory          rb MEM_SIZE
