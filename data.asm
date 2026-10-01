section '.data' data readable writeable
    prompt          db '-',0
    hStdOut         dd 0
    hStdIn          dd 0
    chars_written   dd 0
    chars_read      dd 0
    input_buffer    rb 256

    dump_seg        dw 0000h
    dump_off        dw 0100h
    dump_len        dw 128

    line_buffer     rb 256
    memory          rb 65536