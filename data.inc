MEM_SIZE                equ 110000h

CR                      equ 13
LF                      equ 10
SPACE                   equ 20h
COLON                   equ 3Ah
COMMA                   equ 2Ch
QUOTE_DOUBLE            equ 22h
QUOTE_SINGLE            equ 27h

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

OP_MOV_BX_AX            equ 8Bh
OP_MOV_BX_AX_MODRM      equ 0D8h
OP_ADD_AX               equ 05h
OP_SUB_AX               equ 2Dh

OP_PUSH_CX              equ 51h
OP_POP_CX               equ 59h
OP_DEC_CX               equ 49h

OP_JNZ_REL8             equ 75h

INT_VECTOR_20           equ 20h
INT_VECTOR_21           equ 21h
ENABLE_PROCESSED_INPUT  equ 0001h
ENABLE_LINE_INPUT       equ 0002h
ENABLE_ECHO_INPUT       equ 0004h
INT21_AH_PRINT_STRING   equ 09h
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

    move_src_seg    dw 0
    move_src_off    dw 0
    move_len        dw 0
    move_dst_seg    dw 0
    move_dst_off    dw 0

    edit_seg         dw 0
    edit_off         dw 0
    edit_char        db 0
    edit_chars_read  dd 0
    old_console_mode dd 0
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

    asm_1word_table:
        db "nop",0,OP_NOP,0
        db "int",0,OP_INT,1
        db "ret",0,OP_RET,0
        db "push cx",0,OP_PUSH_CX,0
        db "pop cx",0,OP_POP_CX,0
        db "dec cx",0,OP_DEC_CX,0
        db 0

    asm_2word_table db "mov ax",0,OP_MOV_AX,2
        db "mov bx",0,OP_MOV_BX,2
        db "mov cx",0,OP_MOV_CX,2
        db "mov dx",0,OP_MOV_DX,2
        db "mov al",0,OP_MOV_AL,1
        db "mov cl",0,OP_MOV_CL,1
        db "mov dl",0,OP_MOV_DL,1
        db "mov bl",0,OP_MOV_BL,1
        db "mov ah",0,OP_MOV_AH,1
        db "mov ch",0,OP_MOV_CH,1
        db "mov dh",0,OP_MOV_DH,1
        db "mov bh",0,OP_MOV_BH,1
        db "add ax",0,OP_ADD_AX,2
        db "sub ax",0,OP_SUB_AX,2
        db 0

    asm_3word_table db "mov bx ax",0,OP_MOV_BX_AX,OP_MOV_BX_AX_MODRM
        db 0

    asm_2byte_table db "mov bx,ax",0,OP_MOV_BX_AX,OP_MOV_BX_AX_MODRM
        db "add [bx+si],al",0,00h,00h
        db 0

    help_text db 'assemble              A [адрес]',CR,LF
              db 'unassemble            U [адрес]',CR,LF
              db 'dump                  D [диапазон]',CR,LF
              db 'enter                 E адрес [список]',CR,LF
              db 'fill                  F диапазон список',CR,LF
              db 'move                  M диапазон адрес',CR,LF
              db 'register              R [имя]',CR,LF
              db 'go                    G [=addr] [bp]',CR,LF
              db 'quit                  Q',CR,LF,0
    help_text_len = $ - help_text

    err_text db '^ Error',CR,LF,0
    err_text_len = $ - err_text

    msg_prog_end db CR,LF,'Программа завершилась нормально',CR,LF,0
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
    cmd_entry 'f', cmd_fill
    cmd_entry 'e', cmd_edit
    cmd_entry 'm', cmd_move
    cmd_entry 'g', cmd_go
    cmd_entry 't', cmd_trace
    cmd_entry 'r', cmd_register
    cmd_entry '?', cmd_help
    db 0

    jump_table:
        repeat 256
            dd cmd_go.unknown_insn
        end repeat

        org jump_table + 05h*4
        dd cmd_go.exec_add_ax

        org jump_table + 2Dh*4
        dd cmd_go.exec_sub_ax

        org jump_table + 8Bh*4
        dd cmd_go.exec_mov_bx_ax

        org jump_table + 90h*4
        dd cmd_go.exec_nop

        org jump_table + 0B0h*4
        dd cmd_go.exec_mov_al
        dd cmd_go.exec_mov_cl
        dd cmd_go.exec_mov_dl
        dd cmd_go.exec_mov_bl
        dd cmd_go.exec_mov_ah
        dd cmd_go.exec_mov_ch
        dd cmd_go.exec_mov_dh
        dd cmd_go.exec_mov_bh

        org jump_table + 0B8h*4
        dd cmd_go.exec_mov_ax
        dd cmd_go.exec_mov_cx
        dd cmd_go.exec_mov_dx
        dd cmd_go.exec_mov_bx

        org jump_table + 0C3h*4
        dd cmd_go.exec_ret

        org jump_table + 0CDh*4
        dd cmd_go.exec_int

        org jump_table + 256*4

section '.bss' readable writeable
    input_buffer    rb INPUT_BUFFER_SIZE
    line_buffer     rb LINE_BUFFER_SIZE
    asm_token       rb ASM_TOKEN_SIZE
    asm_bytes       rb ASM_BYTES_SIZE
    memory          rb MEM_SIZE