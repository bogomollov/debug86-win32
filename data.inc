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

    reg_DS          dw 0000h
    reg_CS          dw 0000h
    reg_ES          dw 0000h
    reg_SS          dw 0000h
    reg_IP          dw 0100h
    reg_AX          dw 0000h
    reg_BX          dw 0000h
    reg_CX          dw 0000h
    reg_DX          dw 0000h

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

    asm_seg         dw 0
    asm_off         dw 0
    asm_len         dw 0
    asm_arg_size    db 0
    
    unasm_seg       dw 0
    unasm_off       dw 0100h
    unasm_len       dw 32

    asm_1word_table db "nop", 0, 90h, 0
                    db "int", 0, 0CDh, 1
                    db "ret", 0, 0C3h, 0
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

    help_text db 'assemble              A [адрес]',13,10
              db 'unassemble            U [адрес]',13,10
              db 'dump                  D [диапазон]',13,10
              db 'enter                 E адрес [список]',13,10
              db 'fill                  F диапазон список',13,10
              db 'move                  M блокнач блоккон',13,10
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
    db '?'
    dd cmd_help
    db 0

section '.bss' readable writeable
    input_buffer    rb 256
    line_buffer     rb 256
    memory          rb MEM_SIZE
    asm_token       rb 32
    asm_bytes       rb 16