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
ASM_BYTES_SIZE          equ 64
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
STEP_BREAKPOINT         equ 4

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

