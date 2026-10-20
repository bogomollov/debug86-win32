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

macro gen_r16_only prefix, opcode, modrm_base {
    db prefix, 'ax', 0, opcode, modrm_base + 0
    db prefix, 'cx', 0, opcode, modrm_base + 1
    db prefix, 'dx', 0, opcode, modrm_base + 2
    db prefix, 'bx', 0, opcode, modrm_base + 3
    db prefix, 'sp', 0, opcode, modrm_base + 4
    db prefix, 'bp', 0, opcode, modrm_base + 5
    db prefix, 'si', 0, opcode, modrm_base + 6
    db prefix, 'di', 0, opcode, modrm_base + 7
}

    asm_1word_table:
        db "nop",0,OP_NOP,0
        db "int 3",0,0CCh,0
        db "int",0,OP_INT,1
        db "ret",0,OP_RET,0
        db "retf",0,0CBh,0
        db "ret",0,0C2h,2
        db "retf",0,0CAh,2
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
        db "cbw",0,98h,0
        db "cwd",0,99h,0
        db "pushf",0,9Ch,0
        db "popf",0,9Dh,0
        db "sahf",0,9Eh,0
        db "lahf",0,9Fh,0
        db "xlat",0,0D7h,0
        db "clc",0,0F8h,0
        db "stc",0,0F9h,0
        db "cmc",0,0F5h,0
        db "cld",0,0FCh,0
        db "std",0,0FDh,0
        db "cli",0,0FAh,0
        db "sti",0,0FBh,0
        db "hlt",0,0F4h,0
        db "iret",0,0CFh,0
        db "into",0,0CEh,0
        db "wait",0,9Bh,0
        db "daa",0,27h,0
        db "das",0,2Fh,0
        db "aaa",0,37h,0
        db "aas",0,3Fh,0
        db "salc",0,0D6h,0
        db "aam",0,0D4h,0Ah
        db "aad",0,0D5h,0Ah
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
        db "in al",0,0E4h,1
        db "in ax",0,0E5h,1
        db "in al,dx",0,0ECh,0
        db "in ax,dx",0,0EDh,0
        db "out dx,al",0,0EEh,0
        db "out dx,ax",0,0EFh,0
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
        db "add al",0,04h,1
        db "adc ax",0,15h,2
        db "adc al",0,14h,1
        db "sub ax",0,OP_SUB_AX,2
        db "sub al",0,2Ch,1
        db "sbb ax",0,1Dh,2
        db "sbb al",0,1Ch,1
        db "xor ax",0,35h,2
        db "xor al",0,34h,1
        db "and ax",0,25h,2
        db "and al",0,24h,1
        db "or ax",0,0Dh,2
        db "or al",0,0Ch,1
        db "test ax",0,0A9h,2
        db "test al",0,0A8h,1
        gen_r16_unary 'not ', 0F7h, 0F6h, 0D0h
        gen_r16_unary 'neg ', 0F7h, 0F6h, 0D8h
        gen_r16_unary 'shl ', 0D1h, 0D0h, 0E0h
        gen_r16_unary 'sal ', 0D1h, 0D0h, 0E0h
        gen_r16_unary 'shr ', 0D1h, 0D0h, 0E8h
        gen_r16_unary 'sar ', 0D1h, 0D0h, 0F8h
        gen_r16_unary 'rol ', 0D1h, 0D0h, 0C0h
        gen_r16_unary 'ror ', 0D1h, 0D0h, 0C8h
        gen_r16_unary 'rcl ', 0D1h, 0D0h, 0D0h
        gen_r16_unary 'rcr ', 0D1h, 0D0h, 0D8h
        gen_r16_unary 'mul ', 0F7h, 0F6h, 0E0h
        gen_r16_unary 'imul ', 0F7h, 0F6h, 0E8h
        gen_r16_unary 'div ', 0F7h, 0F6h, 0F0h
        gen_r16_unary 'idiv ', 0F7h, 0F6h, 0F8h
        gen_dec_16
        gen_dec_8
        gen_r16_only 'call ', 0FFh, 0D0h
        gen_r16_only 'jmp ',  0FFh, 0E0h
        db 0

    asm_3word_table:
        db "in al dx",0,0ECh,0
        db "in ax dx",0,0EDh,0
        db "out dx al",0,0EEh,0
        db "out dx ax",0,0EFh,0
        db 0

    asm_2byte_table:
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

