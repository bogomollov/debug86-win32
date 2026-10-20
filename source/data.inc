include 'equates.inc'

section '.data' data readable writeable
    ctrl_c_flag     db 0

    prompt          db '-',0
    prompt_len      dd 1
    hStdOut         dd 0
    hStdIn          dd 0
    chars_written   dd 0
    chars_read      dd 0

    cmd_ptr         dd 0

    dump_seg        dw 0958h
    dump_off        dw 0100h
    dump_len        dd 128
    dd_skip         dw 0
    dd_line_bytes   dw 0

    msg_file_not_found  db 'File not found',CR,LF,0
    msg_file_not_found_len = $ - msg_file_not_found

    msg_file_create_err db 'File creation error',CR,LF,0
    msg_file_create_err_len = $ - msg_file_create_err

    msg_no_memory       db 'Insufficient memory',CR,LF,0
    msg_no_memory_len   = $ - msg_no_memory

    msg_writing         db 'Writing ',0
    msg_writing_len     = $ - msg_writing

    msg_bytes           db ' bytes',CR,LF,0
    msg_bytes_len       = $ - msg_bytes

    file_handle         dd 0
    file_size           dd 0
    file_bytes_rw       dd 0
    load_seg            dw 0
    load_off            dw 0

    cpu_state:
        dw 0000h   ; AX
        dw 0000h   ; BX
        dw 0000h   ; CX
        dw 0000h   ; DX
        dw 0FFEEh  ; SP
        dw 0000h   ; BP
        dw 0000h   ; SI
        dw 0000h   ; DI
        dw 0958h   ; DS
        dw 0958h   ; ES
        dw 0958h   ; SS
        dw 0958h   ; CS
        dw 0100h   ; IP

    reg_DS  equ     cpu_state + CPU_STATE_DS
    reg_CS  equ     cpu_state + CPU_STATE_CS
    reg_ES  equ     cpu_state + CPU_STATE_ES
    reg_SS  equ     cpu_state + CPU_STATE_SS
    reg_IP  equ     cpu_state + CPU_STATE_IP
    reg_AX  equ     cpu_state + CPU_STATE_AX
    reg_BX  equ     cpu_state + CPU_STATE_BX
    reg_CX  equ     cpu_state + CPU_STATE_CX
    reg_DX  equ     cpu_state + CPU_STATE_DX
    reg_SP  equ     cpu_state + CPU_STATE_SP
    reg_BP  equ     cpu_state + CPU_STATE_BP
    reg_SI  equ     cpu_state + CPU_STATE_SI
    reg_DI  equ     cpu_state + CPU_STATE_DI

    reg_names:
        dw 'AX','BX','CX','DX','SP','BP','SI','DI','DS','ES','SS','CS','IP'

    flag_states     db 0, 0, 1, 0, 0, 0, 0, 0
    flag_set_codes   db 'OV','DN','EI','NG','ZR','AC','PE','CY'
    flag_clr_codes   db 'NV','UP','DI','PL','NZ','NA','PO','NC'

    flag_map:
        flag_entry 'ov', FLAG_OV, 1
        flag_entry 'nv', FLAG_OV, 0
        flag_entry 'dn', FLAG_DN, 1
        flag_entry 'up', FLAG_DN, 0
        flag_entry 'ei', FLAG_EI, 1
        flag_entry 'di', FLAG_EI, 0
        flag_entry 'ng', FLAG_NG, 1
        flag_entry 'pl', FLAG_NG, 0
        flag_entry 'zr', FLAG_ZR, 1
        flag_entry 'nz', FLAG_ZR, 0
        flag_entry 'ac', FLAG_AC, 1
        flag_entry 'na', FLAG_AC, 0
        flag_entry 'pe', FLAG_PE, 1
        flag_entry 'po', FLAG_PE, 0
        flag_entry 'cy', FLAG_CY, 1
        flag_entry 'nc', FLAG_CY, 0
        db 0


    num_breakpoints dw 0
    breakpoints_seg rw MAX_BREAKPOINTS
    breakpoints_off rw MAX_BREAKPOINTS

    fill_seg        dw 0
    fill_off        dw 0
    fill_len        dd 0
    fill_patlen     dw 0
    fill_pat        rb FILL_PAT_MAX
    search_seg      dw 0
    search_off      dw 0
    search_len      dd 0
    search_patlen   dw 0
    search_pat      rb FILL_PAT_MAX

    move_src_seg    dw 0
    move_src_off    dw 0
    move_len        dd 0
    move_dst_seg    dw 0
    move_dst_off    dw 0

    comp_src_seg    dw 0
    comp_src_off    dw 0
    comp_len        dd 0
    comp_dst_seg    dw 0
    comp_dst_off    dw 0
    comp_val1       db 0
    comp_val2       db 0


    edit_seg         dw 0
    edit_off         dw 0
    edit_char        db 0
    edit_chars_read  dd 0
    old_console_mode dd 0
    int21_old_console_mode dd 0
    int21_chars_read dd 0
    kbd_peek_valid   db 0
    kbd_peek_char    db 0
    kbd_peek_scan    db 0
    stdin_eof        db 0
    kbd_temp_mode    dd 0
    events_read      dd 0
    temp_pipe_avail  dd 0
    input_record     rb 32
    edit_nibble      db 0
    edit_have_nibble db 0
    edit_cell_done   db 0
    edit_orig_byte   db 0
    edit_reg_ptr    dd 0
    edit_reg_name   rb REG_NAME_BUFFER_SIZE

    asm_seg         dw 0
    asm_off         dw 0
    asm_len         dw 0
    asm_arg_size    db 0
    
    unasm_seg       dw 0958h
    unasm_off       dw 0100h
    unasm_len       dd 32

    trace_count     dw 1
    proceed_count   dw 1
    proceed_target_seg dw 0
    proceed_target_off dw 0
    seg_override    dd 0
    prefix_len      dd 0
    step_initial_ip dw 0
    
    dis_is_word     dd 0
    dis_dir         dd 0
    dis_imm_len     dd 0
    dis_disp_len    dd 0
    dis_mnem_ptr    dd 0
    dis_is_sreg     dd 0
    dis_is_unary    dd 0
    dis_is_shift    dd 0

    sreg_names      dw 'ES', 'CS', 'SS', 'DS'
    op_reg8_names   dw 'AL', 'CL', 'DL', 'BL', 'AH', 'CH', 'DH', 'BH'
    alu_op_names    db 'ADD ', 'OR  ', 'ADC ', 'SBB ', 'AND ', 'SUB ', 'XOR ', 'CMP '
    modrm_base_names:
        db 'BX+SI', 0, 0, 0
        db 'BX+DI', 0, 0, 0
        db 'BP+SI', 0, 0, 0
        db 'BP+DI', 0, 0, 0
        db 'SI', 0, 0, 0, 0, 0, 0
        db 'DI', 0, 0, 0, 0, 0, 0
        db 'BP', 0, 0, 0, 0, 0, 0
        db 'BX', 0, 0, 0, 0, 0, 0
    str_mnem_mov    db 'MOV ', 0
    str_mnem_lea    db 'LEA ', 0
    str_mnem_test   db 'TEST', 0
    str_mnem_xchg   db 'XCHG', 0
    str_mnem_les    db 'LES ', 0
    str_mnem_lds    db 'LDS ', 0
    str_mnem_pop    db 'POP ', 0
    str_mnem_not    db 'NOT ', 0
    str_mnem_neg    db 'NEG ', 0
    str_mnem_mul    db 'MUL ', 0
    str_mnem_imul   db 'IMUL', 0
    str_mnem_div    db 'DIV ', 0
    str_mnem_idiv   db 'IDIV', 0
    str_mnem_inc    db 'INC ', 0
    str_mnem_dec    db 'DEC ', 0
    str_mnem_push   db 'PUSH', 0
    str_mnem_call   db 'CALL', 0
    str_mnem_jmp    db 'JMP ', 0
    str_mnem_rol    db 'ROL ', 0
    str_mnem_ror    db 'ROR ', 0
    str_mnem_rcl    db 'RCL ', 0
    str_mnem_rcr    db 'RCR ', 0
    str_mnem_shl    db 'SHL ', 0
    str_mnem_shr    db 'SHR ', 0
    str_mnem_sar    db 'SAR ', 0

    f6_f7_mnems:
        dd str_mnem_test
        dd 0
        dd str_mnem_not
        dd str_mnem_neg
        dd str_mnem_mul
        dd str_mnem_imul
        dd str_mnem_div
        dd str_mnem_idiv

    fe_ff_mnems:
        dd str_mnem_inc
        dd str_mnem_dec
        dd str_mnem_call
        dd str_mnem_call
        dd str_mnem_jmp
        dd str_mnem_jmp
        dd str_mnem_push
        dd 0

    shift_mnems:
        dd str_mnem_rol
        dd str_mnem_ror
        dd str_mnem_rcl
        dd str_mnem_rcr
        dd str_mnem_shl
        dd str_mnem_shr
        dd 0
        dd str_mnem_sar
    
    reg_name_table:
        reg_entry 'ax', reg_AX
        reg_entry 'bx', reg_BX
        reg_entry 'cx', reg_CX
        reg_entry 'dx', reg_DX
        reg_entry 'sp', reg_SP
        reg_entry 'bp', reg_BP
        reg_entry 'si', reg_SI
        reg_entry 'di', reg_DI
        reg_entry 'ds', reg_DS
        reg_entry 'es', reg_ES
        reg_entry 'ss', reg_SS
        reg_entry 'cs', reg_CS
        reg_entry 'ip', reg_IP
        db 0

    reg_print_table:
        dw 'AX'
        dd reg_AX
        dw 'BX'
        dd reg_BX
        dw 'CX'
        dd reg_CX
        dw 'DX'
        dd reg_DX
        dw 'SP'
        dd reg_SP
        dw 'BP'
        dd reg_BP
        dw 'SI'
        dd reg_SI
        dw 'DI'
        dd reg_DI
        dw 'DS'
        dd reg_DS
        dw 'ES'
        dd reg_ES
        dw 'SS'
        dd reg_SS
        dw 'CS'
        dd reg_CS
        dw 'IP'
        dd reg_IP

include 'asm_tables.inc'

    help_text db 'assemble              A [address]',CR,LF
              db 'compare               C range address',CR,LF
              db 'dump                  D [range]',CR,LF
              db 'enter                 E address [list]',CR,LF
              db 'fill                  F range list',CR,LF
              db 'go                    G [=addr] [bp]',CR,LF
              db 'hex                   H value1 value2',CR,LF
              db 'input                 I port',CR,LF
              db 'load                  L [address]',CR,LF
              db 'move                  M range address',CR,LF
              db 'name                  N [pathname] [arglist]',CR,LF
              db 'output                O port byte',CR,LF
              db 'proceed               P [=addr] [count]',CR,LF
              db 'quit                  Q',CR,LF
              db 'register              R [name]',CR,LF
              db 'search                S range list',CR,LF
              db 'trace                 T [=addr] [count]',CR,LF
              db 'unassemble            U [range]',CR,LF
              db 'write                 W [address]',CR,LF
    help_text_len = $ - help_text
              db 0

    err_text db '^ Error',CR,LF,0
    err_text_len = $ - err_text

    msg_prog_end db CR,LF,'Program terminated normally',CR,LF,0
    msg_prog_end_len = $ - msg_prog_end

    msg_br_error db 'BR error',CR,LF,0
    msg_br_error_len = $ - msg_br_error

    msg_bf_error db 'BF error',CR,LF,0
    msg_bf_error_len = $ - msg_bf_error

    msg_df_error db 'DF error',CR,LF,0
    msg_df_error_len = $ - msg_df_error

    msg_bp_error db 'BP error',CR,LF,0
    msg_bp_error_len = $ - msg_bp_error

COMTAB:
    cmd_entry 'a', cmd_assemble
    cmd_entry 'u', cmd_unassemble
    cmd_entry 'q', cmd_quit
    cmd_entry 'd', cmd_dump
    cmd_entry 'c', cmd_compare
    cmd_entry 'f', cmd_fill
    cmd_entry 'e', cmd_edit
    cmd_entry 'm', cmd_move
    cmd_entry 's', cmd_search
    cmd_entry 'n', cmd_name
    cmd_entry 'l', cmd_load
    cmd_entry 'w', cmd_write
    cmd_entry 'h', cmd_hex
    cmd_entry 'i', cmd_input
    cmd_entry 'o', cmd_output
    cmd_entry 'g', cmd_go
    cmd_entry 't', cmd_trace
    cmd_entry 'p', cmd_proceed
    cmd_entry 'r', cmd_register
    cmd_entry '?', cmd_help
    db 0

    reg16_ptrs:
        dd reg_AX, reg_CX, reg_DX, reg_BX
        dd reg_SP, reg_BP, reg_SI, reg_DI

    sreg_ptrs:
        dd reg_ES, reg_CS, reg_SS, reg_DS

    reg8_ptrs:
        dd reg_AX,   reg_CX,   reg_DX,   reg_BX
        dd reg_AX+1, reg_CX+1, reg_DX+1, reg_BX+1

    modrm_offset dw 0


