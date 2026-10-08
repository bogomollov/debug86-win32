MEM_SIZE                equ 110000h

CR                      equ 13
LF                      equ 10
SPACE                   equ 20h
COLON                   equ 3Ah
COMMA                   equ 2Ch
QUOTE_DOUBLE            equ 22h
QUOTE_SINGLE            equ 27h

GENERIC_READ            equ 80000000h
GENERIC_WRITE           equ 40000000h
FILE_SHARE_READ         equ 1
FILE_SHARE_WRITE        equ 2
CREATE_ALWAYS           equ 2
OPEN_EXISTING           equ 3
FILE_ATTRIBUTE_NORMAL   equ 80h
INVALID_HANDLE_VALUE    equ -1

INPUT_BUFFER_MAX        equ 255
INPUT_BUFFER_SIZE       equ 256
LINE_BUFFER_SIZE        equ 256
ASM_TOKEN_SIZE          equ 32
ASM_BYTES_SIZE          equ 16
REG_NAME_BUFFER_SIZE    equ 4
REG_NAME_MAX_LEN        equ 3
REG_PRINT_COUNT         equ 13

FLAG_COUNT              equ 8
MAX_BREAKPOINTS         equ 10
FILL_PAT_MAX            equ 64

DUMP_DEFAULT_LEN        equ 128
DUMP_LINE_BYTES         equ 16
UNASM_DEFAULT_LEN       equ 32

FLAG_OV                 equ 0
FLAG_DN                 equ 1
FLAG_EI                 equ 2
FLAG_NG                 equ 3
FLAG_ZR                 equ 4
FLAG_AC                 equ 5
FLAG_PE                 equ 6
FLAG_CY                 equ 7

OP_NOP                  equ 90h
OP_RET                  equ 0C3h
OP_INT                  equ 0CDh

OP_MOV_AX               equ 0B8h
OP_MOV_BX               equ 0BBh
OP_MOV_CX               equ 0B9h
OP_MOV_DX               equ 0BAh
OP_MOV_AL               equ 0B0h
OP_MOV_CL               equ 0B1h
OP_MOV_DL               equ 0B2h
OP_MOV_BL               equ 0B3h
OP_MOV_AH               equ 0B4h
OP_MOV_CH               equ 0B5h
OP_MOV_DH               equ 0B6h
OP_MOV_BH               equ 0B7h
OP_MOV_SP               equ 0BCh
OP_MOV_BP               equ 0BDh
OP_MOV_SI               equ 0BEh
OP_MOV_DI               equ 0BFh

OP_MOV_BX_AX            equ 8Bh
OP_MOV_BX_AX_MODRM      equ 0D8h
OP_ADD_AX               equ 05h
OP_SUB_AX               equ 2Dh

OP_PUSH_CX              equ 51h
OP_POP_CX               equ 59h
OP_DEC_CX               equ 49h

OP_JNZ_REL8             equ 75h

INT_VECTOR_10           equ 10h
INT_VECTOR_16           equ 16h
INT_VECTOR_20           equ 20h
INT_VECTOR_21           equ 21h
ENABLE_PROCESSED_INPUT  equ 0001h
ENABLE_LINE_INPUT       equ 0002h
ENABLE_ECHO_INPUT       equ 0004h
INT21_AH_PRINT_STRING   equ 09h
INT21_AH_BUFFERED_INPUT equ 0Ah
INT21_AH_EXIT           equ 4Ch

INSN_LEN_1              equ 1
INSN_LEN_2              equ 2
INSN_LEN_3              equ 3

STEP_OK                 equ 0
STEP_PROGRAM_END        equ 1
STEP_UNKNOWN            equ 2
STEP_ERROR              equ 3

; ============================================================
;  Записи таблиц через макросы + именованные смещения полей.
;  Параметры макросов подставляются текстуально, поэтому
;  строковые литералы ('ov', 'ax', ...) работают как надо.
;  Смещения и размеры полей заданы константами ? единый
;  источник правды и для сборки данных, и для доступа к ним.
; ============================================================

; --- Запись таблицы команд (COMTAB) ---
CMD_ENTRY_CHAR_OFF       equ 0     ; db  ? символ команды
CMD_ENTRY_HANDLER_OFF    equ 1     ; dd  ? указатель на обработчик
CMD_ENTRY_CHAR_SIZE      equ 1
CMD_ENTRY_HANDLER_SIZE   equ 4
COMTAB_RECORD_SIZE       equ CMD_ENTRY_CHAR_SIZE + CMD_ENTRY_HANDLER_SIZE

macro cmd_entry cmd_char, cmd_handler {
    db  cmd_char                       ; +0: символ команды
    dd  cmd_handler                    ; +1: обработчик
}

; --- Запись таблицы имён регистров (reg_name_table) ---
REG_ENTRY_NAME_OFF       equ 0     ; 'ax' ? 2 символа
REG_ENTRY_NUL_OFF        equ 2     ; терминатор
REG_ENTRY_PTR_OFF        equ 3     ; dd ? указатель на регистр
REG_ENTRY_NAME_SIZE      equ 2
REG_ENTRY_NUL_SIZE       equ 1
REG_ENTRY_PTR_SIZE       equ 4
REG_NAME_RECORD_SIZE     equ REG_ENTRY_NAME_SIZE + REG_ENTRY_NUL_SIZE + REG_ENTRY_PTR_SIZE

macro reg_entry reg_name, reg_ptr {
    db  reg_name                       ; +0: имя (2 символа)
    db  0                              ; +2: терминатор
    dd  reg_ptr                        ; +3: указатель
}

; --- Запись таблицы флагов (flag_map) ---
FLAG_ENTRY_NAME_OFF      equ 0     ; 'ov' ? 2 символа
FLAG_ENTRY_INDEX_OFF     equ 2     ; db ? индекс флага
FLAG_ENTRY_VALUE_OFF     equ 3     ; db ? значение
FLAG_ENTRY_NAME_SIZE     equ 2
FLAG_ENTRY_INDEX_SIZE    equ 1
FLAG_ENTRY_VALUE_SIZE    equ 1
FLAG_MAP_RECORD_SIZE     equ FLAG_ENTRY_NAME_SIZE + FLAG_ENTRY_INDEX_SIZE + FLAG_ENTRY_VALUE_SIZE

macro flag_entry flag_name, flag_idx, flag_val {
    db  flag_name                      ; +0: имя (2 символа)
    db  flag_idx                       ; +2: индекс флага
    db  flag_val                       ; +3: значение
}

CPU_STATE_AX    equ 0
CPU_STATE_BX    equ 2
CPU_STATE_CX    equ 4
CPU_STATE_DX    equ 6
CPU_STATE_SP    equ 8
CPU_STATE_BP    equ 10
CPU_STATE_SI    equ 12
CPU_STATE_DI    equ 14
CPU_STATE_DS    equ 16
CPU_STATE_ES    equ 18
CPU_STATE_SS    equ 20
CPU_STATE_CS    equ 22
CPU_STATE_IP    equ 24
CPU_STATE_SIZE  equ 26

    mov8_reg_offsets:
        db CPU_STATE_AX,   CPU_STATE_CX,   CPU_STATE_DX,   CPU_STATE_BX
        db CPU_STATE_AX+1, CPU_STATE_CX+1, CPU_STATE_DX+1, CPU_STATE_BX+1

    mov16_reg_offsets:
        db CPU_STATE_AX, CPU_STATE_CX, CPU_STATE_DX, CPU_STATE_BX

section '.data' data readable writeable
    prompt          db '-',0
    prompt_len      dd 1
    hStdOut         dd 0
    hStdIn          dd 0
    chars_written   dd 0
    chars_read      dd 0

    cmd_ptr         dd 0

    dump_seg        dw 0000h
    dump_off        dw 0100h
    dump_len        dw 128
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
    flag_set_codes   db 'OF','DF','EI','SF','ZF','AF','PF','CF'
    flag_clr_codes   db 'NO','ND','DI','NS','NZ','NA','NP','NC'

    flag_map:
        flag_entry 'of', FLAG_OV, 1
        flag_entry 'ov', FLAG_OV, 1
        flag_entry 'no', FLAG_OV, 0
        flag_entry 'nv', FLAG_OV, 0
        flag_entry 'df', FLAG_DN, 1
        flag_entry 'dn', FLAG_DN, 1
        flag_entry 'nd', FLAG_DN, 0
        flag_entry 'up', FLAG_DN, 0
        flag_entry 'ei', FLAG_EI, 1
        flag_entry 'di', FLAG_EI, 0
        flag_entry 'sf', FLAG_NG, 1
        flag_entry 'ng', FLAG_NG, 1
        flag_entry 'ns', FLAG_NG, 0
        flag_entry 'pl', FLAG_NG, 0
        flag_entry 'zf', FLAG_ZR, 1
        flag_entry 'zr', FLAG_ZR, 1
        flag_entry 'nz', FLAG_ZR, 0
        flag_entry 'af', FLAG_AC, 1
        flag_entry 'ac', FLAG_AC, 1
        flag_entry 'na', FLAG_AC, 0
        flag_entry 'pf', FLAG_PE, 1
        flag_entry 'pe', FLAG_PE, 1
        flag_entry 'np', FLAG_PE, 0
        flag_entry 'po', FLAG_PE, 0
        flag_entry 'cf', FLAG_CY, 1
        flag_entry 'cy', FLAG_CY, 1
        flag_entry 'nc', FLAG_CY, 0
        db 0

    str_add_bxsi_al db 'ADD [BX+SI],AL',0

    num_breakpoints dw 0
    breakpoints_seg rw MAX_BREAKPOINTS
    breakpoints_off rw MAX_BREAKPOINTS

    fill_seg        dw 0
    fill_off        dw 0
    fill_len        dw 0
    fill_patlen     dw 0
    fill_pat        rb FILL_PAT_MAX
    search_seg      dw 0
    search_off      dw 0
    search_len      dd 0
    search_patlen   dw 0
    search_pat      rb FILL_PAT_MAX

    move_src_seg    dw 0
    move_src_off    dw 0
    move_len        dw 0
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
    
    unasm_seg       dw 0
    unasm_off       dw 0100h
    unasm_len       dw 32

    trace_count     dw 1
    proceed_count   dw 1
    proceed_target_seg dw 0
    proceed_target_off dw 0
    
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

macro gen_r16_unary prefix, op16, op8, modrm_base {
    db prefix, 'ax', 0, op16, modrm_base + 0
    db prefix, 'cx', 0, op16, modrm_base + 1
    db prefix, 'dx', 0, op16, modrm_base + 2
    db prefix, 'bx', 0, op16, modrm_base + 3
    db prefix, 'sp', 0, op16, modrm_base + 4
    db prefix, 'bp', 0, op16, modrm_base + 5
    db prefix, 'si', 0, op16, modrm_base + 6
    db prefix, 'di', 0, op16, modrm_base + 7
    db prefix, 'al', 0, op8,  modrm_base + 0
    db prefix, 'cl', 0, op8,  modrm_base + 1
    db prefix, 'dl', 0, op8,  modrm_base + 2
    db prefix, 'bl', 0, op8,  modrm_base + 3
    db prefix, 'ah', 0, op8,  modrm_base + 4
    db prefix, 'ch', 0, op8,  modrm_base + 5
    db prefix, 'dh', 0, op8,  modrm_base + 6
    db prefix, 'bh', 0, op8,  modrm_base + 7
}

macro gen_inc_16 {
    db 'inc ax', 0, 40h, 0
    db 'inc cx', 0, 41h, 0
    db 'inc dx', 0, 42h, 0
    db 'inc bx', 0, 43h, 0
    db 'inc sp', 0, 44h, 0
    db 'inc bp', 0, 45h, 0
    db 'inc si', 0, 46h, 0
    db 'inc di', 0, 47h, 0
}

macro gen_inc_8 {
    db 'inc al', 0, 0FEh, 0C0h
    db 'inc cl', 0, 0FEh, 0C1h
    db 'inc dl', 0, 0FEh, 0C2h
    db 'inc bl', 0, 0FEh, 0C3h
    db 'inc ah', 0, 0FEh, 0C4h
    db 'inc ch', 0, 0FEh, 0C5h
    db 'inc dh', 0, 0FEh, 0C6h
    db 'inc bh', 0, 0FEh, 0C7h
}

macro gen_push_16 {
    db 'push ax', 0, 50h, 0
    db 'push cx', 0, 51h, 0
    db 'push dx', 0, 52h, 0
    db 'push bx', 0, 53h, 0
    db 'push sp', 0, 54h, 0
    db 'push bp', 0, 55h, 0
    db 'push si', 0, 56h, 0
    db 'push di', 0, 57h, 0
    db 'push es', 0, 06h, 0
    db 'push cs', 0, 0Eh, 0
    db 'push ss', 0, 16h, 0
    db 'push ds', 0, 1Eh, 0
}

macro gen_pop_16 {
    db 'pop ax', 0, 58h, 0
    db 'pop cx', 0, 59h, 0
    db 'pop dx', 0, 5Ah, 0
    db 'pop bx', 0, 5Bh, 0
    db 'pop sp', 0, 5Ch, 0
    db 'pop bp', 0, 5Dh, 0
    db 'pop si', 0, 5Eh, 0
    db 'pop di', 0, 5Fh, 0
    db 'pop es', 0, 07h, 0
    db 'pop ss', 0, 17h, 0
    db 'pop ds', 0, 1Fh, 0
}

macro gen_dec_16 {
    db 'dec ax', 0, 48h, 0
    db 'dec cx', 0, 49h, 0
    db 'dec dx', 0, 4Ah, 0
    db 'dec bx', 0, 4Bh, 0
    db 'dec sp', 0, 4Ch, 0
    db 'dec bp', 0, 4Dh, 0
    db 'dec si', 0, 4Eh, 0
    db 'dec di', 0, 4Fh, 0
}

macro gen_dec_8 {
    db 'dec al', 0, 0FEh, 0C8h
    db 'dec cl', 0, 0FEh, 0C9h
    db 'dec dl', 0, 0FEh, 0CAh
    db 'dec bl', 0, 0FEh, 0CBh
    db 'dec ah', 0, 0FEh, 0CCh
    db 'dec ch', 0, 0FEh, 0CDh
    db 'dec dh', 0, 0FEh, 0CEh
    db 'dec bh', 0, 0FEh, 0CFh
}

macro gen_shift_1 op, op16, op8, modrm_base {
    db op, ' ax 1', 0, op16, modrm_base + 0
    db op, ' ax 01', 0, op16, modrm_base + 0
    db op, ' cx 1', 0, op16, modrm_base + 1
    db op, ' cx 01', 0, op16, modrm_base + 1
    db op, ' dx 1', 0, op16, modrm_base + 2
    db op, ' dx 01', 0, op16, modrm_base + 2
    db op, ' bx 1', 0, op16, modrm_base + 3
    db op, ' bx 01', 0, op16, modrm_base + 3
    db op, ' sp 1', 0, op16, modrm_base + 4
    db op, ' sp 01', 0, op16, modrm_base + 4
    db op, ' bp 1', 0, op16, modrm_base + 5
    db op, ' bp 01', 0, op16, modrm_base + 5
    db op, ' si 1', 0, op16, modrm_base + 6
    db op, ' si 01', 0, op16, modrm_base + 6
    db op, ' di 1', 0, op16, modrm_base + 7
    db op, ' di 01', 0, op16, modrm_base + 7
    db op, ' al 1', 0, op8,  modrm_base + 0
    db op, ' al 01', 0, op8,  modrm_base + 0
    db op, ' cl 1', 0, op8,  modrm_base + 1
    db op, ' cl 01', 0, op8,  modrm_base + 1
    db op, ' dl 1', 0, op8,  modrm_base + 2
    db op, ' dl 01', 0, op8,  modrm_base + 2
    db op, ' bl 1', 0, op8,  modrm_base + 3
    db op, ' bl 01', 0, op8,  modrm_base + 3
    db op, ' ah 1', 0, op8,  modrm_base + 4
    db op, ' ah 01', 0, op8,  modrm_base + 4
    db op, ' ch 1', 0, op8,  modrm_base + 5
    db op, ' ch 01', 0, op8,  modrm_base + 5
    db op, ' dh 1', 0, op8,  modrm_base + 6
    db op, ' dh 01', 0, op8,  modrm_base + 6
    db op, ' bh 1', 0, op8,  modrm_base + 7
    db op, ' bh 01', 0, op8,  modrm_base + 7
}

macro gen_shift_cl op, op16, op8, modrm_base {
    db op, ' ax cl', 0, op16, modrm_base + 0
    db op, ' cx cl', 0, op16, modrm_base + 1
    db op, ' dx cl', 0, op16, modrm_base + 2
    db op, ' bx cl', 0, op16, modrm_base + 3
    db op, ' sp cl', 0, op16, modrm_base + 4
    db op, ' bp cl', 0, op16, modrm_base + 5
    db op, ' si cl', 0, op16, modrm_base + 6
    db op, ' di cl', 0, op16, modrm_base + 7
    db op, ' al cl', 0, op8,  modrm_base + 0
    db op, ' cl cl', 0, op8,  modrm_base + 1
    db op, ' dl cl', 0, op8,  modrm_base + 2
    db op, ' bl cl', 0, op8,  modrm_base + 3
    db op, ' ah cl', 0, op8,  modrm_base + 4
    db op, ' ch cl', 0, op8,  modrm_base + 5
    db op, ' dh cl', 0, op8,  modrm_base + 6
    db op, ' bh cl', 0, op8,  modrm_base + 7
}

macro gen_logic_dst op, sep, opcode, d, d_idx, r0, r1, r2, r3, r4, r5, r6, r7 {
    db op, ' ', d, sep, r0, 0, opcode, 0C0h + (0 shl 3) + d_idx
    db op, ' ', d, sep, r1, 0, opcode, 0C0h + (1 shl 3) + d_idx
    db op, ' ', d, sep, r2, 0, opcode, 0C0h + (2 shl 3) + d_idx
    db op, ' ', d, sep, r3, 0, opcode, 0C0h + (3 shl 3) + d_idx
    db op, ' ', d, sep, r4, 0, opcode, 0C0h + (4 shl 3) + d_idx
    db op, ' ', d, sep, r5, 0, opcode, 0C0h + (5 shl 3) + d_idx
    db op, ' ', d, sep, r6, 0, opcode, 0C0h + (6 shl 3) + d_idx
    db op, ' ', d, sep, r7, 0, opcode, 0C0h + (7 shl 3) + d_idx
}

macro gen_logic_all op, sep, op16, op8 {
    gen_logic_dst op, sep, op16, 'ax', 0, 'ax','cx','dx','bx','sp','bp','si','di'
    gen_logic_dst op, sep, op16, 'cx', 1, 'ax','cx','dx','bx','sp','bp','si','di'
    gen_logic_dst op, sep, op16, 'dx', 2, 'ax','cx','dx','bx','sp','bp','si','di'
    gen_logic_dst op, sep, op16, 'bx', 3, 'ax','cx','dx','bx','sp','bp','si','di'
    gen_logic_dst op, sep, op16, 'sp', 4, 'ax','cx','dx','bx','sp','bp','si','di'
    gen_logic_dst op, sep, op16, 'bp', 5, 'ax','cx','dx','bx','sp','bp','si','di'
    gen_logic_dst op, sep, op16, 'si', 6, 'ax','cx','dx','bx','sp','bp','si','di'
    gen_logic_dst op, sep, op16, 'di', 7, 'ax','cx','dx','bx','sp','bp','si','di'

    gen_logic_dst op, sep, op8, 'al', 0, 'al','cl','dl','bl','ah','ch','dh','bh'
    gen_logic_dst op, sep, op8, 'cl', 1, 'al','cl','dl','bl','ah','ch','dh','bh'
    gen_logic_dst op, sep, op8, 'dl', 2, 'al','cl','dl','bl','ah','ch','dh','bh'
    gen_logic_dst op, sep, op8, 'bl', 3, 'al','cl','dl','bl','ah','ch','dh','bh'
    gen_logic_dst op, sep, op8, 'ah', 4, 'al','cl','dl','bl','ah','ch','dh','bh'
    gen_logic_dst op, sep, op8, 'ch', 5, 'al','cl','dl','bl','ah','ch','dh','bh'
    gen_logic_dst op, sep, op8, 'dh', 6, 'al','cl','dl','bl','ah','ch','dh','bh'
    gen_logic_dst op, sep, op8, 'bh', 7, 'al','cl','dl','bl','ah','ch','dh','bh'
}

macro gen_shift_2byte op, op16, op8, modrm_base {
    db op, ' ax,1', 0, op16, modrm_base + 0
    db op, ' cx,1', 0, op16, modrm_base + 1
    db op, ' dx,1', 0, op16, modrm_base + 2
    db op, ' bx,1', 0, op16, modrm_base + 3
    db op, ' sp,1', 0, op16, modrm_base + 4
    db op, ' bp,1', 0, op16, modrm_base + 5
    db op, ' si,1', 0, op16, modrm_base + 6
    db op, ' di,1', 0, op16, modrm_base + 7
    db op, ' al,1', 0, op8,  modrm_base + 0
    db op, ' cl,1', 0, op8,  modrm_base + 1
    db op, ' dl,1', 0, op8,  modrm_base + 2
    db op, ' bl,1', 0, op8,  modrm_base + 3
    db op, ' ah,1', 0, op8,  modrm_base + 4
    db op, ' ch,1', 0, op8,  modrm_base + 5
    db op, ' dh,1', 0, op8,  modrm_base + 6
    db op, ' bh,1', 0, op8,  modrm_base + 7
    db op, ' ax,cl', 0, op16 + 2, modrm_base + 0
    db op, ' cx,cl', 0, op16 + 2, modrm_base + 1
    db op, ' dx,cl', 0, op16 + 2, modrm_base + 2
    db op, ' bx,cl', 0, op16 + 2, modrm_base + 3
    db op, ' sp,cl', 0, op16 + 2, modrm_base + 4
    db op, ' bp,cl', 0, op16 + 2, modrm_base + 5
    db op, ' si,cl', 0, op16 + 2, modrm_base + 6
    db op, ' di,cl', 0, op16 + 2, modrm_base + 7
    db op, ' al,cl', 0, op8  + 2, modrm_base + 0
    db op, ' cl,cl', 0, op8  + 2, modrm_base + 1
    db op, ' dl,cl', 0, op8  + 2, modrm_base + 2
    db op, ' bl,cl', 0, op8  + 2, modrm_base + 3
    db op, ' ah,cl', 0, op8  + 2, modrm_base + 4
    db op, ' ch,cl', 0, op8  + 2, modrm_base + 5
    db op, ' dh,cl', 0, op8  + 2, modrm_base + 6
    db op, ' bh,cl', 0, op8  + 2, modrm_base + 7
}

    asm_1word_table:
        db "nop",0,OP_NOP,0
        db "int",0,OP_INT,1
        db "ret",0,OP_RET,0
        db "push cx",0,OP_PUSH_CX,0
        db "pop cx",0,OP_POP_CX,0
        db "movsb",0,0A4h,0
        db "movsw",0,0A5h,0
        db "cmpsb",0,0A6h,0
        db "cmpsw",0,0A7h,0
        db "stosb",0,0AAh,0
        db "stosw",0,0ABh,0
        db "lodsb",0,0ACh,0
        db "lodsw",0,0ADh,0
        db "scasb",0,0AEh,0
        db "scasw",0,0AFh,0
        gen_dec_16
        db 0

    asm_2word_table db "mov ax",0,OP_MOV_AX,2
        db "mov bx",0,OP_MOV_BX,2
        db "mov cx",0,OP_MOV_CX,2
        db "mov dx",0,OP_MOV_DX,2
        db "mov sp",0,OP_MOV_SP,2
        db "mov bp",0,OP_MOV_BP,2
        db "mov si",0,OP_MOV_SI,2
        db "mov di",0,OP_MOV_DI,2
        db "mov al",0,OP_MOV_AL,1
        db "mov cl",0,OP_MOV_CL,1
        db "mov dl",0,OP_MOV_DL,1
        db "mov bl",0,OP_MOV_BL,1
        db "mov ah",0,OP_MOV_AH,1
        db "mov ch",0,OP_MOV_CH,1
        db "mov dh",0,OP_MOV_DH,1
        db "mov bh",0,OP_MOV_BH,1
        db "cmp ax",0,3Dh,2
        db "cmp al",0,3Ch,1
        db "rep stosb",0,0F3h,0AAh
        db "rep stosw",0,0F3h,0ABh
        db "rep movsb",0,0F3h,0A4h
        db "rep movsw",0,0F3h,0A5h
        db "rep lodsb",0,0F3h,0ACh
        db "rep lodsw",0,0F3h,0ADh
        db "rep cmpsb",0,0F3h,0A6h
        db "rep cmpsw",0,0F3h,0A7h
        db "rep scasb",0,0F3h,0AEh
        db "rep scasw",0,0F3h,0AFh
        db "repe cmpsb",0,0F3h,0A6h
        db "repe cmpsw",0,0F3h,0A7h
        db "repe scasb",0,0F3h,0AEh
        db "repe scasw",0,0F3h,0AFh
        db "repne cmpsb",0,0F2h,0A6h
        db "repne cmpsw",0,0F2h,0A7h
        db "repne scasb",0,0F2h,0AEh
        db "repne scasw",0,0F2h,0AFh
        gen_push_16
        gen_pop_16
        gen_inc_16
        gen_inc_8
        db "add ax",0,OP_ADD_AX,2
        db "sub ax",0,OP_SUB_AX,2
        db "xor ax",0,35h,2
        db "xor al",0,34h,1
        db "and ax",0,25h,2
        db "and al",0,24h,1
        db "or ax",0,0Dh,2
        db "or al",0,0Ch,1
        db "test ax",0,0A9h,2
        db "test al",0,0A8h,1
        gen_r16_unary 'not ', 0F7h, 0F6h, 0D0h
        gen_r16_unary 'shl ', 0D1h, 0D0h, 0E0h
        gen_r16_unary 'sal ', 0D1h, 0D0h, 0E0h
        gen_r16_unary 'shr ', 0D1h, 0D0h, 0E8h
        gen_r16_unary 'sar ', 0D1h, 0D0h, 0F8h
        gen_r16_unary 'rol ', 0D1h, 0D0h, 0C0h
        gen_r16_unary 'ror ', 0D1h, 0D0h, 0C8h
        gen_r16_unary 'rcl ', 0D1h, 0D0h, 0D0h
        gen_r16_unary 'rcr ', 0D1h, 0D0h, 0D8h
        gen_r16_unary 'mul ', 0F7h, 0F6h, 0E0h
        gen_dec_16
        gen_dec_8
        db 0

    asm_3word_table db "mov bx ax",0,OP_MOV_BX_AX,OP_MOV_BX_AX_MODRM
        gen_shift_1 'shl', 0D1h, 0D0h, 0E0h
        gen_shift_1 'sal', 0D1h, 0D0h, 0E0h
        gen_shift_1 'shr', 0D1h, 0D0h, 0E8h
        gen_shift_1 'sar', 0D1h, 0D0h, 0F8h
        gen_shift_1 'rol', 0D1h, 0D0h, 0C0h
        gen_shift_1 'ror', 0D1h, 0D0h, 0C8h
        gen_shift_1 'rcl', 0D1h, 0D0h, 0D0h
        gen_shift_1 'rcr', 0D1h, 0D0h, 0D8h
        gen_shift_cl 'shl', 0D3h, 0D2h, 0E0h
        gen_shift_cl 'sal', 0D3h, 0D2h, 0E0h
        gen_shift_cl 'shr', 0D3h, 0D2h, 0E8h
        gen_shift_cl 'sar', 0D3h, 0D2h, 0F8h
        gen_shift_cl 'rol', 0D3h, 0D2h, 0C0h
        gen_shift_cl 'ror', 0D3h, 0D2h, 0C8h
        gen_shift_cl 'rcl', 0D3h, 0D2h, 0D0h
        gen_shift_cl 'rcr', 0D3h, 0D2h, 0D8h
        gen_logic_all 'xor', ' ', 31h, 30h
        gen_logic_all 'and', ' ', 21h, 20h
        gen_logic_all 'or',  ' ', 09h, 08h
        gen_logic_all 'test',' ', 85h, 84h
        db 0

    asm_2byte_table db "mov bx,ax",0,OP_MOV_BX_AX,OP_MOV_BX_AX_MODRM
        db "add [bx+si],al",0,00h,00h
        db "rep stosb",0,0F3h,0AAh
        db "rep stosw",0,0F3h,0ABh
        db "rep movsb",0,0F3h,0A4h
        db "rep movsw",0,0F3h,0A5h
        db "rep lodsb",0,0F3h,0ACh
        db "rep lodsw",0,0F3h,0ADh
        db "repe cmpsb",0,0F3h,0A6h
        db "repe cmpsw",0,0F3h,0A7h
        db "repe scasb",0,0F3h,0AEh
        db "repe scasw",0,0F3h,0AFh
        db "repne cmpsb",0,0F2h,0A6h
        db "repne cmpsw",0,0F2h,0A7h
        db "repne scasb",0,0F2h,0AEh
        db "repne scasw",0,0F2h,0AFh
        gen_inc_8
        gen_r16_unary 'not ', 0F7h, 0F6h, 0D0h
        gen_shift_2byte 'shl', 0D1h, 0D0h, 0E0h
        gen_shift_2byte 'shr', 0D1h, 0D0h, 0E8h
        gen_shift_2byte 'sar', 0D1h, 0D0h, 0F8h
        gen_shift_2byte 'rol', 0D1h, 0D0h, 0C0h
        gen_shift_2byte 'ror', 0D1h, 0D0h, 0C8h
        gen_shift_2byte 'rcl', 0D1h, 0D0h, 0D0h
        gen_shift_2byte 'rcr', 0D1h, 0D0h, 0D8h
        gen_logic_all 'xor', ',', 31h, 30h
        gen_logic_all 'and', ',', 21h, 20h
        gen_logic_all 'or',  ',', 09h, 08h
        gen_logic_all 'test',',', 85h, 84h
        gen_r16_unary 'mul ', 0F7h, 0F6h, 0E0h
        gen_dec_8
        db 0

    asm_rel8_table:
        db "jne",0,75h,0
        db "jnz",0,75h,0
        db "je",0,74h,0
        db "jz",0,74h,0
        db "loop",0,0E2h,0
        db "loope",0,0E1h,0
        db "loopz",0,0E1h,0
        db "loopne",0,0E0h,0
        db "loopnz",0,0E0h,0
        db "jcxz",0,0E3h,0
        db "jmp",0,0EBh,0
        db "ja",0,77h,0
        db "jnbe",0,77h,0
        db "jae",0,73h,0
        db "jnb",0,73h,0
        db "jnc",0,73h,0
        db "jb",0,72h,0
        db "jnae",0,72h,0
        db "jc",0,72h,0
        db "jbe",0,76h,0
        db "jna",0,76h,0
        db "jg",0,7Fh,0
        db "jnle",0,7Fh,0
        db "jge",0,7Dh,0
        db "jnl",0,7Dh,0
        db "jl",0,7Ch,0
        db "jnge",0,7Ch,0
        db "jle",0,7Eh,0
        db "jng",0,7Eh,0
        db "js",0,78h,0
        db "jns",0,79h,0
        db "jo",0,70h,0
        db "jno",0,71h,0
        db "jp",0,7Ah,0
        db "jpe",0,7Ah,0
        db "jnp",0,7Bh,0
        db "jpo",0,7Bh,0
        db 0

    help_text db 'assemble              A [address]',CR,LF
              db 'unassemble            U [address]',CR,LF
              db 'dump                  D [range]',CR,LF
              db 'enter                 E address [list]',CR,LF
              db 'fill                  F range list',CR,LF
              db 'move                  M range address',CR,LF
              db 'search                S range list',CR,LF
              db 'register              R [name]',CR,LF
              db 'go                    G [=addr] [bp]',CR,LF
              db 'proceed               P [=addr] [count]',CR,LF
              db 'quit                  Q',CR,LF
    help_text_len = $ - help_text
              db 0

    err_text db '^ Error',CR,LF,0
    err_text_len = $ - err_text

    msg_prog_end db CR,LF,'Program terminated normally',CR,LF,0
    msg_prog_end_len = $ - msg_prog_end

    msg_breakpoint db 'Breakpoint reached',CR,LF,0
    msg_breakpoint_len = $ - msg_breakpoint

    msg_unknown_insn db 'Unknown instruction',CR,LF,0
    msg_unknown_insn_len = $ - msg_unknown_insn
    
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

    reg8_ptrs:
        dd reg_AX,   reg_CX,   reg_DX,   reg_BX
        dd reg_AX+1, reg_CX+1, reg_DX+1, reg_BX+1


section '.bss' readable writeable
    current_filename rb 260
    input_buffer    rb INPUT_BUFFER_SIZE
    int21_input_buf rb INPUT_BUFFER_SIZE
    line_buffer     rb LINE_BUFFER_SIZE
    asm_token       rb ASM_TOKEN_SIZE
    asm_bytes       rb ASM_BYTES_SIZE
    io_ports        rb 10000h
    memory          rb MEM_SIZE
