# MS-DOS DEBUG v2.0 Authenticity Specification & Guidelines

This document outlines the architectural, behavioral, and user experience rules required to achieve full authenticity with the original MS-DOS `DEBUG.EXE` v2.0 (1983).

---

## 1. User Interface & Error Reporting

The interface of `DEBUG.EXE` was intentionally minimal and exact. Replicating its exact behavior preserves original user expectations and tool compatibility.

### 1.1. Command Prompt
* The command prompt is strictly a single hyphen character:
  ```text
  -
  ```
* No trailing space after the prompt unless actively entering input.
* Empty input (pressing Enter on an empty line) immediately prints another prompt `-`.

### 1.2. Syntax Error Formatting (`^ Error`)
Original DEBUG never emitted descriptive errors such as `"Syntax error"` or `"Invalid command"`.

* **Dynamic Column Alignment**:
  When a parsing or syntax error occurs, DEBUG scans the input buffer to the position of the invalid character, prints enough spaces/tabs to align directly underneath it, and prints `^ Error`:
  ```text
  -d 100 200 zz
              ^ Error
  ```
* Implementation detail: Calculate column offset as `bad_char_ptr - input_buffer_start`, output that many whitespace characters, then print `^ Error` followed by CRLF and a new `-` prompt.

### 1.3. Specific Register & Flag Error Codes
When interacting with registers or flags, DEBUG does not emit `^ Error`. It uses distinct two-letter error codes:
* **`BR error`** (*Bad Register*): An unrecognized register name was specified (e.g., `-r zz`).
* **`BF error`** (*Bad Flag*): An unrecognized flag code was passed during flag modification.
* **`DF error`** (*Duplicate Flag*): The same flag was modified more than once in a single input line.

### 1.4. Elimination of Synthetic Banners
* **`?` Help Command**: The `?` command must output all available program commands from `help_text`.
* **No Breakpoint Banner**: Do not print `"Breakpoint reached"` when an execution breakpoint triggers. DEBUG silently removes the `INT 3` opcode, rewinds `IP` by 1, and displays the standard register state.
* **No "Unknown Instruction" Banner**: 8086 hardware executed or trapped unrecognized bytes; DEBUG disassembled unrecognized bytes as `DB xx` and never displayed an execution banner like `"Unknown instruction"`.
* **Program Termination**: When a program terminates via `INT 20h` or `INT 21h (AH=4Ch / AH=00h)`, output the exact string:
  ```text
  Program terminated normally
  ```

### 1.5. Delimiters and Case Sensitivity
* **Case Insensitive Input**: Commands, register names, hex values, and flag codes are case-insensitive (`d 100` == `D 100`).
* **Strict Uppercase Output**: All hex digits (`0-9`, `A-F`), register names, and disassembled mnemonics must be rendered in uppercase.
* **Flexible Delimiters**: Spaces, tabs, and commas (`,`) are interchangeable parameter separators. Consecutive delimiters are treated as a single delimiter (e.g., `d,100,,200` is identical to `d 100 200`).

---

## 2. Register & Flag System (`R` Command)

### 2.1. Flag Register Mapping & Codes
The 8086 FLAGS register status bits must be rendered in strict MSB-to-LSB order using authentic two-letter abbreviations:

| Bit Position | Flag Name | Set (1) Code | Clear (0) Code | Description |
| :---: | :---: | :---: | :---: | :--- |
| **Bit 11** | Overflow (`OF`) | `OV` | `NV` | Overflow / No Overflow |
| **Bit 10** | Direction (`DF`)| `DN` | `UP` | Down / Up |
| **Bit 9**  | Interrupt (`IF`)| `EI` | `DI` | Enable / Disable Interrupts |
| **Bit 7**  | Sign (`SF`)     | `NG` | `PL` | Negative / Plus |
| **Bit 6**  | Zero (`ZF`)     | `ZR` | `NZ` | Zero / Not Zero |
| **Bit 4**  | Aux Carry (`AF`)| `AC` | `NA` | Aux Carry / No Aux Carry |
| **Bit 2**  | Parity (`PF`)   | `PE` | `PO` | Parity Even / Parity Odd |
| **Bit 0**  | Carry (`CF`)    | `CY` | `NC` | Carry / No Carry |

Standard display output (all cleared except interrupts enabled):
```text
NV UP EI PL NZ NA PO NC
```

### 2.2. Register Dump Formatting
When `R` is entered without parameters:

```text
AX=0000  BX=0000  CX=0000  DX=0000  SP=FFEE  BP=0000  SI=0000  DI=0000
DS=0958  ES=0958  SS=0958  CS=0958  IP=0100   NV UP EI PL NZ NA PO NC
0958:0100 B8004C        MOV     AX,4C00
```

Formatting rules:
* **Line 1**: 8 general/index registers separated by **two spaces** (`AX=0000  BX=...`).
* **Line 2**: 4 segment registers and `IP` separated by two spaces, followed by **three spaces** and the 8 flag codes separated by single spaces.
* **Line 3**: Disassembly of the instruction located at `CS:IP`.

### 2.3. Memory Operand Preview
When displaying the current instruction on Line 3 (or during `T` single-step), if the instruction reads or writes memory, DEBUG resolves the effective address and displays the segment, offset, and dereferenced value on the right margin:
```text
0958:0100 8B1E2001      MOV     BX,[0120]              DS:0120=004C
0958:0104 8A07          MOV     AL,[BX]                DS:004C=3F
```

### 2.4. Interactive Register Editing
* `R <reg>` (e.g., `R AX`):
  ```text
  AX 0000
  :
  ```
  If a new hex value is entered, the register is updated. If the user presses Enter without input, the value is preserved.
* `R F`:
  ```text
  NV UP EI PL NZ NA PO NC - 
  ```
  Allows entering one or more flag codes separated by spaces to alter flags.

---

## 3. Real-Mode Memory Model & Addressing

### 3.1. Segmented Address Format (`Segment:Offset`)
* All addresses are represented in 16-bit real-mode format: `SSSS:OOOO`.
* Linear address computation:
  $$\text{Linear Address} = (\text{Segment} \times 16) + \text{Offset}$$
* In true 8086 hardware, addresses wrap around at 1 MB ($100000\text{h}$) modulo $2^{20}$, unless simulating an enabled A20 gate.

### 3.2. Segment Defaults
Commands must default to their logical segment if not explicitly provided:
* **Code Commands** (`A`, `U`, `G`, `T`): Default to `CS`.
* **Data Commands** (`D`, `E`, `F`, `M`, `S`, `C`): Default to `DS`.

### 3.3. Sticky Offset / Address Continuation
* **Dump (`D`)**: A bare `D` command continues dumping from where the previous `D` finished (default 128 bytes).
* **Unassemble (`U`)**: A bare `U` command continues disassembling from the instruction boundary where the previous `U` ended (default 32 bytes).
* **Assemble (`A`)**: A bare `A` command continues assembling from where the previous assembly stopped (initially `CS:0100`).

### 3.4. Range Specifications
Commands that take memory ranges (`D`, `C`, `F`, `M`, `S`, `U`) must support both syntax variants:
1. `address1 address2` — Start offset and ending offset (e.g., `D 100 12F`).
2. `address1 L count` — Start offset and byte length (e.g., `D 100 L 30`).

---

## 4. `.COM` File Environment & Program Segment Prefix (PSP)

To execute authentic 16-bit MS-DOS binaries, the execution environment must initialize the full Program Segment Prefix (PSP) structure.

### 4.1. PSP Layout (`0000h` to `00FFh`)
| Offset | Size | Value / Content | Purpose |
| :---: | :---: | :--- | :--- |
| `0000h` | 2 bytes | `CD 20` (`INT 20h`) | CP/M compatibility exit vector |
| `0002h` | 2 bytes | Segment of top of memory | Memory size limit |
| `0005h` | 5 bytes | `CD 21 CB` (`INT 21h; RETF`) | DOS function dispatcher call |
| `005Ch` | 16 bytes| Unopened File Control Block 1 | Parsed from 1st command-line argument |
| `006Ch` | 16 bytes| Unopened File Control Block 2 | Parsed from 2nd command-line argument |
| `0080h` | 1 byte  | Argument length $N$ | Number of characters in command tail |
| `0081h` | $N$ bytes| Command-line arguments | Arguments string ending with `0Dh` (CR) |
| `0080h` | 128 bytes| Default DTA (Disk Transfer Area) | Buffer for directory/disk ops |

### 4.2. Initial Register State upon Loading `.COM`
When a program is loaded into memory:
* `CS = DS = ES = SS = PSP_Segment`
* `IP = 0100h` (entry point after PSP)
* `SP = FFFEh` (or top of the 64 KB segment)
* **Stack Return Address**: The word at `[SP]` must be initialized to `0000h`. Many early .COM programs exit with a bare near `RET`. Popping `0000h` into `IP` branches to `PSP:0000h`, which executes `INT 20h` and terminates cleanly.
* `BX:CX` = File length in bytes (high word in `BX`, low word in `CX`).
* `AX = 0000h` (or FCB validity flag: `0000h` if valid, `FFFFh` if invalid drive).
* `BP = SI = DI = 0000h`.
* `FLAGS = 7202h` (all flags cleared except Interrupts Enabled `EI`).

### 4.3. Critical Interrupts Emulation
Programs in DOS rely on basic DOS and BIOS services:
* **`INT 20h`**: Program Terminate.
* **`INT 21h`**:
  * `AH=00h`: Program Terminate.
  * `AH=01h`: Console Input with echo.
  * `AH=02h`: Console Character Output (character in `DL`).
  * `AH=06h`: Direct Console I/O.
  * `AH=07h` / `AH=08h`: Direct Console Input without echo.
  * `AH=09h`: Display `$`-terminated string (`DS:DX`).
  * `AH=0Ah`: Buffered Keyboard Input.
  * `AH=0Bh`: Check Console Input Status.
  * `AH=25h` / `AH=35h`: Set/Get Interrupt Vector.
  * `AH=30h`: Get DOS Version (returns `AL=02h, AH=00h` for MS-DOS 2.0).
  * `AH=4Ch`: Terminate Process with Return Code (`AL`).
* **`INT 10h`**: BIOS Video services (`AH=0Eh` TTY write, `AH=02h` set cursor).
* **`INT 16h`**: BIOS Keyboard services (`AH=00h` read keystroke, `AH=01h` check status).

---

## 5. Required Command Set & Fulfillment Checklist

The debugger implementation must fulfill the core command set of the classic DOS debugger, including standard MS-DOS v2.0 commands and the essential `P` (Proceed) enhancement:

| Command | Name | Syntax | Description |
| :---: | :--- | :--- | :--- |
| **`A`** | Assemble | `A [address]` | Line-by-line 8086 assembler (introduced in MS-DOS 2.0) |
| **`C`** | Compare | `C range address` | Compares two memory blocks and prints differing bytes |
| **`D`** | Dump | `D [range]` | Displays hex and ASCII dump of memory |
| **`E`** | Enter | `E address [list]` | Enters byte values into memory (batch or interactive) |
| **`F`** | Fill | `F range list` | Fills memory with repeating byte patterns |
| **`G`** | Go | `G [=address] [bp1 [bp2...]]` | Executes code with up to 10 breakpoints |
| **`H`** | Hex | `H val1 val2` | Outputs the hexadecimal sum and difference (`sum diff`) |
| **`I`** | Input | `I port` | Reads a byte from an I/O port |
| **`L`** | Load | `L [address] [drive sector count]` | Loads a file or disk sectors into memory |
| **`M`** | Move | `M range address` | Copies memory block (handles overlapping areas) |
| **`N`** | Name | `N [filename [args]]` | Sets filename and initializes command tail for `L`/`W` |
| **`O`** | Output| `O port byte` | Writes a byte to an I/O port |
| **`P`** | Proceed | `P [=address] [count]` | Executes subroutine/loop/interrupt/string op to completion (Step Over) |
| **`Q`** | Quit | `Q` | Exits the debugger |
| **`R`** | Register | `R [register]` | Displays or modifies registers and flags |
| **`S`** | Search | `S range list` | Searches a range of memory for a byte sequence or string |
| **`T`** | Trace | `T [=address] [count]` | Single-steps one or more instructions with register dump |
| **`U`** | Unassemble | `U [range]` | Disassembles machine code into 8086 mnemonics |
| **`W`** | Write | `W [address] [drive sector count]` | Writes `BX:CX` bytes of memory to file or disk sectors |

### 5.1. Command `P` (Proceed / Step Over) Fulfillment Specification

The `P` command serves as the critical "Step Over" counterpart to `T` (Trace / Step Into). Although introduced as a standard enhancement (popularized in SYMDEB and MS-DOS 3.0+), it is an essential fulfillment requirement for practical debugging of `.COM` programs without tracing through repetitive loops or system interrupt dispatchers.

#### Syntax
```text
P [=address] [count]
```
* `=address`: Optional start address to set `CS:IP` before execution begins.
* `count`: Optional hexadecimal execution count (default is `1`).

#### Behavioral Rules & Logic
1. **Instruction Inspection**:
   Before executing the instruction at `CS:IP`, the debugger inspects the current opcode:
   * **Subroutine Calls**:
     * Near Call: `E8h`
     * Far Call: `9Ah`
     * Indirect Call: `FFh` with ModR/M reg field `010b` (near indirect) or `011b` (far indirect)
   * **Software Interrupts**:
     * `CDh <imm8>` (e.g. `INT 21h`, `INT 10h`)
     * `CCh` (`INT 3`), `CEh` (`INTO`)
   * **Loops**:
     * `E0h` (`LOOPNZ` / `LOOPNE`)
     * `E1h` (`LOOPZ` / `LOOPE`)
     * `E2h` (`LOOP`)
     * `E3h` (`JCXZ`)
   * **Repeated String Instructions**:
     * Instruction preceded by `F2h` (`REPNE`/`REPNZ`) or `F3h` (`REP`/`REPE`/`REPZ`) prefixes (e.g. `REP MOVSB`, `REP STOSW`).
2. **Proceed (Step Over) Mechanics**:
   * If the current instruction matches any of the categories above:
     * Compute the linear address of the instruction immediately following the current instruction: `next_IP = current_IP + instruction_length`.
     * Set a temporary breakpoint (internal or `INT 3`) at `next_IP`.
     * Execute the program until that breakpoint is reached (or program terminates / user aborts via Ctrl+C).
     * Remove the temporary breakpoint, restore the original byte, and print the register dump.
   * If the instruction is a regular sequential instruction (e.g., `MOV`, `ADD`, `JMP`, `CMP`):
     * Fall back to single-step execution identical to `T` (Trace).
3. **Count Parameter**:
   * If `count` is specified, repeat the procedure `count` times, displaying the register state after each completed step.
   * If an unhandled breakpoint or termination is encountered before the count finishes, halt execution immediately.


---

## 6. Disassembler & Assembler Specifics

### 6.1. Instruction Set Boundaries
* Strictly 8086 / 8088 instructions plus 8087 coprocessor mnemonics.
* Do not include 80186+ instructions (`ENTER`, `LEAVE`, `PUSHA`, `POPA`, `BOUND`, shift by immediate) or 32-bit registers (`EAX`, `EBX`, etc.).

### 6.2. Disassembly Notation
* Operands do not have trailing `h` suffixes (`MOV AX,0100`, not `MOV AX,0100h`).
* Memory dereference syntax: `[0100]`, `[BX+SI+04]`.
* Segment overrides: `CS:`, `DS:`, `ES:`, `SS:`.
* Explicit size specifiers only when ambiguous: `BYTE PTR [...]` or `WORD PTR [...]`.
* Unrecognized or invalid opcodes must be rendered as `DB xx`.

### 6.3. Assembler (`A`) Behavior
* Prompt format displays the current address followed by a space:
  ```text
  -a 100
  0958:0100 
  ```
* Pressing Enter on an empty line terminates assembly mode and returns to `-`.
* If a syntax error is encountered during assembly, display `^ Error` pointing to the error token and re-prompt for the same address.

---

## 7. Console Subsystem & Environment

* **Character Encoding**: MS-DOS ran natively under IBM OEM **Code Page 437**. When creating an authentic English MS-DOS experience, configure the Windows console to Code Page 437 (`SetConsoleOutputCP(437)`) to ensure box-drawing and extended ASCII characters match the IBM PC font.
* **Control-C (`^C`) Handling**: Pressing Ctrl+C during long-running operations (`D`, `U`, `T`, `G`, `A`) terminates the command, echoes `^C`, outputs a CRLF, and returns to the `-` prompt.
