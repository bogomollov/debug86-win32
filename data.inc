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
        db 'ov', 0, 1
        db 'nv', 0, 0
        db 'dn', 1, 1
        db 'up', 1, 0
        db 'ei', 2, 1
        db 'di', 2, 0
        db 'ng', 3, 1
        db 'pl', 3, 0
        db 'sf', 3, 1
        db 'ns', 3, 0
        db 'zr', 4, 1
        db 'nz', 4, 0
        db 'ac', 5, 1
        db 'na', 5, 0
        db 'pe', 6, 1
        db 'po', 6, 0
        db 'cy', 7, 1
        db 'cf', 7, 1
        db 'nc', 7, 0
        db 0

    str_add_bxsi_al db 'ADD [BX+SI],AL',0

    num_breakpoints dw 0
    breakpoints_seg rw 10
    breakpoints_off rw 10

    fill_seg        dw 0
    fill_off        dw 0
    fill_len        dw 0
    fill_patlen     dw 0
    fill_pat        rb 64

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
    edit_wrapped     db 0
    edit_reg_ptr    dd 0
    edit_reg_name   rb 4

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
        db "nop",0,90h,0
        db "int",0,0CDh,1
        db "ret",0,0C3h,0
        db "push cx",0,51h,0
        db "pop cx",0,59h,0
        db "dec cx",0,49h,0
        db 0

    asm_2word_table db "mov ax", 0, 0B8h, 2
                    db "mov bx", 0, 0BBh, 2
                    db "mov cx", 0, 0B9h, 2
                    db "mov dx", 0, 0BAh, 2
                    db "mov al", 0, 0B0h, 1
                    db "mov cl", 0, 0B1h, 1
                    db "mov dl", 0, 0B2h, 1
                    db "mov bl", 0, 0B3h, 1
                    db "mov ah", 0, 0B4h, 1
                    db "mov ch", 0, 0B5h, 1
                    db "mov dh", 0, 0B6h, 1
                    db "mov bh", 0, 0B7h, 1
                    db "add ax", 0, 05h, 2
                    db "sub ax", 0, 2Dh, 2
                    db 0

    asm_3word_table db "mov bx ax", 0, 8Bh, 0D8h
                    db 0

    asm_2byte_table db "mov bx,ax", 0, 8Bh, 0D8h
                    db "add [bx+si],al", 0, 00h, 00h
                    db 0

    help_text db 'assemble              A [адрес]',13,10
              db 'unassemble            U [адрес]',13,10
              db 'dump                  D [диапазон]',13,10
              db 'enter                 E адрес [список]',13,10
              db 'fill                  F диапазон список',13,10
              db 'move                  M диапазон адрес',13,10
              db 'register              R [имя]',13,10
              db 'go                    G [=addr] [bp]',13,10
              db 'quit                  Q',13,10
    help_text_len = $ - help_text

    err_text db '^ Error',13,10
    err_text_len = $ - err_text

    msg_prog_end db 13,10,'Программа завершилась нормально',13,10
    msg_prog_end_len = $ - msg_prog_end

    msg_breakpoint db 'Breakpoint reached',13,10
    msg_breakpoint_len = $ - msg_breakpoint

    msg_unknown_insn db 'Unknown instruction',13,10
    msg_unknown_insn_len = $ - msg_unknown_insn

    MEM_SIZE = 110000h
    
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
    input_buffer    rb 256
    line_buffer     rb 256
    memory          rb MEM_SIZE
    asm_token       rb 32
    asm_bytes       rb 16