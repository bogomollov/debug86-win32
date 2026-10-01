format PE CONSOLE

entry start

include 'fasm/include/win32a.inc'

section '.data' data readable writeable
    prompt          db '-',0
    hStdOut         dd 0
    chars_written   dd 0

section '.text' code readable executable

start:
    invoke  GetStdHandle, STD_OUTPUT_HANDLE
    mov     [hStdOut], eax

    invoke  WriteConsoleA, [hStdOut], prompt, 1, chars_written, 0

section '.idata' import data readable writeable
    library kernel32, 'KERNEL32.DLL'

    import kernel32,\
           ExitProcess,   'ExitProcess',\
           GetStdHandle,  'GetStdHandle',\
           WriteConsoleA, 'WriteConsoleA'