format PE CONSOLE

entry start

include 'fasm/include/win32a.inc'

include 'data.inc'

section '.text' code readable executable
include 'hex.inc'
include 'dump.inc'
include 'utils.inc'

ctrl_handler:
    mov     eax, [esp+4]
    cmp     eax, 0
    je      .handled
    cmp     eax, 1
    je      .handled
    xor     eax, eax
    ret     4

.handled:
    mov     byte [ctrl_c_flag], 1
    mov     eax, 1
    ret     4

start:
    invoke  GetStdHandle, STD_OUTPUT_HANDLE
    mov     [hStdOut], eax

    invoke  GetStdHandle, STD_INPUT_HANDLE
    mov     [hStdIn], eax

    invoke  SetConsoleOutputCP, 866

    invoke  SetConsoleCtrlHandler, ctrl_handler, 1

    mov     ecx, MEM_SIZE
    mov     edi, memory
    xor     eax, eax
.init_mem:
    mov     [edi], al
    inc     edi
    loop    .init_mem

    call    init_psp
    mov     ax, [reg_DS]
    mov     [dump_seg], ax
    mov     ax, [reg_CS]
    mov     [unasm_seg], ax
    call    parse_startup_cmdline

main_loop:
    mov     byte [ctrl_c_flag], 0
    mov     dword [prompt_len], 1
    invoke  WriteConsoleA, [hStdOut], prompt, 1, chars_written, 0
    test    eax, eax
    jnz     .prompt_ok
    invoke  WriteFile, [hStdOut], prompt, 1, chars_written, 0
.prompt_ok:

    mov     edi, input_buffer
    mov     edx, INPUT_BUFFER_MAX
    call    read_line_console_or_pipe
    jnc     .check_read_count

    cmp     byte [ctrl_c_flag], 0
    jnz     .read_failed
    jmp     exit_program

.check_read_count:
    cmp     dword [chars_read], 0
    jz      .read_failed

    mov     byte [ctrl_c_flag], 0
    mov     esi, input_buffer
    call    skip_whitespace

    call    is_eol
    jc      main_loop

    mov     [cmd_ptr], esi
    mov     al, [esi]
    or      al, 20h

    mov     esi, COMTAB
.find_cmd:
    mov     bl, [esi + CMD_ENTRY_CHAR_OFF]
    test    bl, bl
    jz      .cmd_not_found
    cmp     bl, al
    je      .run_cmd
    add     esi, COMTAB_RECORD_SIZE
    jmp     .find_cmd
.run_cmd:
    mov     eax, [esi + CMD_ENTRY_HANDLER_OFF]
    inc     dword [cmd_ptr]
    call    eax
    jmp     main_loop

.cmd_not_found:
    mov     esi, [cmd_ptr]
    call    print_error
    jmp     main_loop

.read_failed:
    cmp     byte [ctrl_c_flag], 0
    jnz     .prompt_crlf
    jmp     main_loop

.prompt_crlf:
    mov     byte [ctrl_c_flag], 0
    mov     byte [line_buffer], CR
    mov     byte [line_buffer+1], LF
    mov     esi, line_buffer
    mov     ecx, 2
    call    print_buffer
    jmp     main_loop

cmd_help:
    mov     esi, help_text
    mov     ecx, help_text_len
    call    print_buffer
    ret

include 'cmd_reg.inc'

cmd_quit:
    mov     esi, [cmd_ptr]
    call    skip_whitespace
    call    is_eol
    jc      exit_program
    jmp     print_error_and_ret

include 'dos_file.inc'

include 'cmd_memory.inc'

include 'disasm.inc'

include 'asm.inc'

include 'cmd_exec.inc'

include 'cpu_interrupts.inc'

include 'cpu_step.inc'

section '.idata' import data readable writeable
    library kernel32, 'KERNEL32.DLL'

    import kernel32,\
           ExitProcess,           'ExitProcess',\
           GetStdHandle,          'GetStdHandle',\
           WriteConsoleA,         'WriteConsoleA',\
           ReadConsoleA,          'ReadConsoleA',\
           SetConsoleOutputCP,    'SetConsoleOutputCP',\
           GetConsoleMode,        'GetConsoleMode',\
           SetConsoleMode,        'SetConsoleMode',\
           SetConsoleCtrlHandler, 'SetConsoleCtrlHandler',\
           GetCommandLineA,       'GetCommandLineA',\
           CreateFileA,           'CreateFileA',\
           ReadFile,              'ReadFile',\
           WriteFile,             'WriteFile',\
           CloseHandle,           'CloseHandle',\
           GetFileSize,           'GetFileSize',\
           SetConsoleCursorPosition, 'SetConsoleCursorPosition',\
           PeekConsoleInputA,     'PeekConsoleInputA',\
           ReadConsoleInputA,     'ReadConsoleInputA',\
           PeekNamedPipe,         'PeekNamedPipe',\
           Sleep,                 'Sleep'

section '.bss' readable writeable
    current_filename rb 260
    input_buffer    rb INPUT_BUFFER_SIZE
    int21_input_buf rb INPUT_BUFFER_SIZE
    line_buffer     rb LINE_BUFFER_SIZE
    asm_token       rb ASM_TOKEN_SIZE
    asm_bytes       rb ASM_BYTES_SIZE
    io_ports        rb 10000h
    memory          rb MEM_SIZE
