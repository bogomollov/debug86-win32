; ===== Именованные константы =====
MEM_SIZE                equ 110000h

CR                      equ 13
LF                      equ 10
SPACE                   equ 20h
COLON                   equ 3Ah
COMMA                   equ 2Ch

INPUT_BUFFER_MAX        equ 255
INPUT_BUFFER_SIZE       equ 256
LINE_BUFFER_SIZE        equ 256
ASM_TOKEN_SIZE          equ 32
ASM_BYTES_SIZE          equ 16
REG_NAME_BUFFER_SIZE    equ 4
REG_NAME_MAX_LEN        equ 3

COMTAB_RECORD_SIZE      equ 5
REG_NAME_RECORD_SIZE    equ 7
FLAG_MAP_RECORD_SIZE    equ 4

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
INT21_AH_PRINT_STRING   equ 09h
INT21_AH_EXIT           equ 4Ch

INSN_LEN_1              equ 1
INSN_LEN_2              equ 2
INSN_LEN_3              equ 3

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

    reg_DS          dw 0958h
    reg_CS          dw 0958h
    reg_ES          dw 0958h
    reg_SS          dw 0958h
    reg_IP          dw 0100h
    reg_AX          dw 0000h
    reg_BX          dw 0000h
    reg_CX          dw 0000h
    reg_DX          dw 0000h
    reg_SP          dw 0FFEEh
    reg_BP          dw 0000h
    reg_SI          dw 0000h
    reg_DI          dw 0000h

    flag_states     db 0, 0, 1, 0, 0, 0, 0, 0
    flag_set_codes   db 'OV','DN','EI','NG','ZR','AC','PE','CY'
    flag_clr_codes   db 'NV','UP','DI','PL','NZ','NA','PO','NC'

    flag_map:
        db 'ov', FLAG_OV, 1
        db 'nv', FLAG_OV, 0
        db 'dn', FLAG_DN, 1
        db 'up', FLAG_DN, 0
        db 'ei', FLAG_EI, 1
        db 'di', FLAG_EI, 0
        db 'ng', FLAG_NG, 1
        db 'pl', FLAG_NG, 0
        db 'sf', FLAG_NG, 1
        db 'ns', FLAG_NG, 0
        db 'zr', FLAG_ZR, 1
        db 'nz', FLAG_ZR, 0
        db 'ac', FLAG_AC, 1
        db 'na', FLAG_AC, 0
        db 'pe', FLAG_PE, 1
        db 'po', FLAG_PE, 0
        db 'cy', FLAG_CY, 1
        db 'cf', FLAG_CY, 1
        db 'nc', FLAG_CY, 0
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

    reg_name_table:
        db 'ax', 0
        dd reg_AX
        db 'bx', 0
        dd reg_BX
        db 'cx', 0
        dd reg_CX
        db 'dx', 0
        dd reg_DX
        db 'sp', 0
        dd reg_SP
        db 'bp', 0
        dd reg_BP
        db 'si', 0
        dd reg_SI
        db 'di', 0
        dd reg_DI
        db 'ds', 0
        dd reg_DS
        db 'es', 0
        dd reg_ES
        db 'ss', 0
        dd reg_SS
        db 'cs', 0
        dd reg_CS
        db 'ip', 0
        dd reg_IP
        db 0

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
              db 'quit                  Q',CR,LF
    help_text_len = $ - help_text

    err_text db '^ Error',CR,LF
    err_text_len = $ - err_text

    msg_prog_end db CR,LF,'Программа завершилась нормально',CR,LF
    msg_prog_end_len = $ - msg_prog_end

    msg_breakpoint db 'Breakpoint reached',CR,LF
    msg_breakpoint_len = $ - msg_breakpoint

    msg_unknown_insn db 'Unknown instruction',CR,LF
    msg_unknown_insn_len = $ - msg_unknown_insn
    
COMTAB:
    db 'a'
    dd cmd_assemble
    db 'u'
    dd cmd_unassemble
    db 'q'
    dd cmd_quit
    db 'd'
    dd cmd_dump
    db 'f'
    dd cmd_fill
    db 'e'
    dd cmd_edit
    db 'm'
    dd cmd_move
    db 'g'
    dd cmd_go
    db 'r'
    dd cmd_register
    db '?'
    dd cmd_help
    db 0

section '.bss' readable writeable
    input_buffer    rb INPUT_BUFFER_SIZE
    line_buffer     rb LINE_BUFFER_SIZE
    asm_token       rb ASM_TOKEN_SIZE
    asm_bytes       rb ASM_BYTES_SIZE
    memory          rb MEM_SIZE