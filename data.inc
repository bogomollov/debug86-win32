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

    reg_DS          dw 0000h
    reg_CS          dw 0000h
    reg_ES          dw 0000h
    reg_SS          dw 0000h

    fill_seg        dw 0
    fill_off        dw 0
    fill_len        dw 0
    fill_patlen     dw 0
    fill_pat        rb 64

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

    help_text db 'dump                  D [диапазон]',13,10
              db 'enter                 E адрес [список]',13,10
              db 'fill                  F диапазон список',13,10
              db 'quit                  Q',13,10
    help_text_len = $ - help_text

    err_text db '^ Error',13,10
    err_text_len = $ - err_text

    MEM_SIZE = 110000h
    

COMTAB:
    db 'q'
    dd cmd_quit
    db 'd'
    dd cmd_dump
    db 'f'
    dd cmd_fill
    db 'e'
    dd cmd_edit
    db '?'
    dd cmd_help
    db 0

section '.bss' readable writeable
    input_buffer    rb 256
    line_buffer     rb 256
    memory          rb MEM_SIZE