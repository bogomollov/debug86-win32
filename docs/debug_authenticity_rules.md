# MS-DOS DEBUG Authenticity Specification & Guidelines

This document outlines the architectural, behavioral, and user experience specification implemented by `debug86-win32` to achieve full authenticity with the classic MS-DOS `DEBUG.EXE` environment.

---

## 1. User Interface, Prompts & Error Reporting

The interface of `DEBUG` is intentionally minimal, exact, and strictly compliant with classic DOS command-line conventions.

### 1.1. Command Prompt
* The standard command prompt is strictly a single hyphen character:
  ```text
  -
  ```
* No trailing space after the prompt unless actively entering input.
* Empty input (pressing Enter on an empty line) immediately prints another prompt `-`.
* **Dynamic Prompt Tracking**: The application tracks prompt length dynamically (`prompt_len`). The main prompt is 1 character (`-`), whereas the inline assembler prompt is 11 characters (`SSSS:OOOO  `). This ensures that syntax error alignment (`^ Error`) works accurately regardless of which prompt is active.

### 1.2. Syntax Error Formatting (`^ Error`)
DEBUG does not emit verbose error messages such as `"Syntax error"` or `"Invalid command"`.

* **Dynamic Column Alignment**:
  When a parsing or syntax error occurs, DEBUG scans the input buffer up to the position of the offending character, prints enough whitespace characters to align directly underneath it, and prints `^ Error`:
  ```text
  -d 100 200 zz
              ^ Error
  ```
* **Tab Stop Handling**: Column offset calculation correctly accounts for horizontal tab characters (ASCII 9), expanding tab positions to 8-column boundaries (`(col + 8) & ~7`) so the caret points precisely to the erroneous token.
* **Buffer Clamping**: The alignment calculation clamps to `LINE_BUFFER_SIZE - 16` (240 characters) to prevent line buffer overflows.
* **Command Pointer Fallback**: If an error is detected during command argument execution where the scan pointer `esi` has advanced beyond the buffer bounds, the error reporting engine automatically falls back to `cmd_ptr`.

### 1.3. Strict Parameter Validation & Trailing Garbage Rejection
Authentic DEBUG strictly validates parameters and rejects any superfluous or trailing garbage at the end of command inputs:
* **Quit (`Q`)**: Entering `Q` with any trailing arguments (e.g. `Q 100`) rejects the command with `^ Error` pointing to the first trailing argument character, and returns to the `-` prompt without exiting.
* **Dump (`D`) & Unassemble (`U`)**: Trailing characters following a range or length specification (e.g. `D 100 120 extra`) trigger `^ Error`.
* **Assemble (`A`)**: Trailing characters following the start address (e.g. `A 100 extra`) trigger `^ Error`.
* **Register (`R`) & Flag (`RF`)**: Trailing tokens following a register name (e.g. `R AX extra`) or after the `RF` command (e.g. `RF extra`) trigger `^ Error`. When editing a register value interactively, entering trailing non-hex characters after the value (e.g. `: 1234 extra`) triggers `^ Error`.
* **Trace (`T`) & Proceed (`P`)**: Trailing tokens after the count parameter (e.g. `T =100 5 extra`) trigger `^ Error`. A count of zero is explicitly rejected.
* **Hex Arithmetic (`H`), Input (`I`), Output (`O`)**: Trailing tokens after the required arguments trigger `^ Error`.
* **File Operations (`L`, `W`)**: Trailing characters after an optional address parameter trigger `^ Error`.
* **Compare (`C`) & Move (`M`)**: Trailing tokens following the destination address parameter (e.g. `M 100 105 200 extra` or `C 100 105 200 extra`) trigger `^ Error`.
* **Hex Number Validation**:
  * Hexadecimal values parsed by `parse_hex` are strictly limited to at most 4 hexadecimal digits (16-bit range). Entering 5 or more hex digits (e.g. `10000`) is immediately rejected with `^ Error`.
  * Byte-level hex parser `parse_hex_byte` validates that the numeric value fits in 8 bits ($\le \text{0FFh}$); out-of-range values trigger `^ Error`.
* **Instruction Immediate Validation**: Assembler commands `INT` and `RET` reject out-of-range immediate byte operands ($> \text{0FFh}$ for `INT`) and trailing garbage with `^ Error`. Memory instructions with immediate operands require explicit size specifiers (`BYTE PTR` / `WORD PTR`), and byte immediates exceeding `0FFh` trigger `^ Error`.
* **String Literals**: Commands accepting string literals (`E`, `F`, `S`, and `DB` directive) enforce matched quotation marks (`'` or `"`). An unclosed string literal triggers `^ Error`.

### 1.4. Specific Error Codes
Certain commands output distinct two-letter error codes instead of `^ Error`:
* **`BR error`** (*Bad Register*): An unrecognized register name was specified during register inspection/modification (e.g., `-r zz`).
* **`BF error`** (*Bad Flag*): An unrecognized flag code was entered during flag editing (e.g., `-rf xx`).
* **`DF error`** (*Duplicate Flag*): The same flag was modified more than once within a single input line (e.g., `-rf ov nv`).
* **`BP error`** (*Breakpoint Error*): More than 10 breakpoints were specified for the `G` (Go) command (`MAX_BREAKPOINTS = 10`).

### 1.5. File & Memory Error Messages
For file operations and memory allocation, DEBUG emits authentic system notices:
* **`File not found`**: Displayed when an `L` (Load) command or startup command-line load cannot open the specified filename, or if no filename has been set via `N`.
* **`File creation error`**: Displayed when a `W` (Write) command fails to create or write to the destination file.
* **`Insufficient memory`**: Displayed when a file exceeds available memory or when a `.COM` binary exceeds the 64 KB segment limit (`0FF00h` / 65,280 bytes).
* **Write Confirmation**: When writing memory to disk, DEBUG outputs:
  * `Writing <BX><CX> bytes` (if `BX > 0`)
  * `Writing <CX> bytes` (if `BX == 0`)

### 1.6. Elimination of Synthetic Banners
* **`?` Help Command**: The `?` command prints the full reference table of supported commands and their syntax templates.
* **No Breakpoint Banner**: Do not print `"Breakpoint reached"` when an execution breakpoint triggers. DEBUG halts execution silently, restores original state, and prints the standard register dump.
* **No "Unknown Instruction" Banner**: 8086 hardware executed or trapped unrecognized bytes; DEBUG disassembles unrecognized opcodes as `DB xx` and displays the register dump if an invalid instruction halts execution.
* **Program Termination**: When a program terminates via `INT 20h` or `INT 21h (AH=4Ch / AH=00h)`, output the exact string:
  ```text
  Program terminated normally
  ```
* **Safe Quit Handling (`Q`)**: Entering `Q` without arguments terminates the debugger cleanly. If trailing arguments are provided (e.g., `Q 100`), the command is rejected for safety with `^ Error` and returns to the `-` prompt without exiting.

### 1.7. Delimiters and Case Sensitivity
* **Case-Insensitive Input**: All commands, register names, hexadecimal values, mnemonics, and flag codes are case-insensitive (`d 100` == `D 100`).
* **Strict Uppercase Output**: All hexadecimal digits (`0-9`, `A-F`), register names, flag abbreviations, and disassembled instructions are displayed in uppercase.
* **Interchangeable Delimiters**: Spaces, tabs, and commas (`,`) are valid parameter separators. Consecutive delimiters are collapsed into a single delimiter (e.g., `d,100,,200` is identical to `d 100 200`).

### 1.8. Console Subsystem, Codepage & Stream Redirection
* **Character Encoding**: The console output codepage is initialized to **Code Page 866** (`SetConsoleOutputCP(866)`), the standard MS-DOS Russian/Cyrillic OEM codepage, ensuring authentic box-drawing and extended ASCII display.
* **Pipeline and Redirection Fallback**: Console input uses `ReadConsoleA` in interactive mode. When standard input is redirected via pipes or batch scripts, the input engine falls back seamlessly to byte-by-byte `ReadFile` streaming (`read_line_console_or_pipe`) and handles EOF cleanly without hanging.
* **Control-C (`^C`) Signal Handling**: Pressing Ctrl+C or Ctrl+Break during long-running operations (`G`, `T`, `P`, `C`, `S`, `D`, `U`, `A`) cleanly aborts the current operation via `SetConsoleCtrlHandler`, emits a CRLF, and either prints the current register state (for execution commands `G`, `T`, `P`) or returns to the `-` prompt (for memory commands `D`, `U`, `A`, `C`, `S`).
* **Console Mode Restoration**: On exit, `exit_program` restores the console input mode (`old_console_mode`) via `SetConsoleMode` to guarantee the host shell remains in its original configuration.

---

## 2. Register & Flag System (`R` Command)

### 2.1. Flag Register Mapping & Codes
The 8086 FLAGS register status bits are displayed and modified using authentic two-letter abbreviations in strict MSB-to-LSB order:

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

Standard display output (all flags cleared except interrupts enabled):
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
* **Line 1**: 8 general and index registers separated by **two spaces** (`AX=0000  BX=...`).
* **Line 2**: 4 segment registers and `IP` separated by two spaces, followed by **three spaces** and the 8 flag codes separated by single spaces.
* **Line 3**: Disassembly of the instruction located at `CS:IP`.

### 2.3. Memory Operand Live Preview
When displaying the current instruction on Line 3 (or during `T` and `P` stepping), if the instruction reads or writes memory via ModR/M addressing or direct displacement, DEBUG resolves the effective address and displays the segment, offset, and dereferenced value on the right margin, padded to column 55:
```text
0958:0100 8B1E2001      MOV     BX,[0120]              DS:0120=004C
0958:0104 8A07          MOV     AL,[BX]                DS:004C=3F
```
* **Format**: `SEG:OFF=VAL` (2 hex digits for byte operands, 4 hex digits for 16-bit word operands).
* Segment overrides (e.g., `ES:`, `SS:`, `CS:`) are dynamically incorporated into effective address computation and preview.

### 2.4. Interactive Register & Flag Editing
* **`R <register>`** (e.g., `R AX`):
  ```text
  -r ax
  AX 0000
  :
  ```
  Prompts with `:` on a new line. If a new hex value is entered, the register is updated. If the user presses Enter without entering a value, the register retains its previous value. Entering an unrecognized register name yields `BR error`. Trailing non-hex characters after the value produce `^ Error`.
* **`R F`**:
  ```text
  -r f
  NV UP EI PL NZ NA PO NC - 
  ```
  Displays the current flag codes followed by `- ` on the same line. The user can enter one or more space-separated flag codes to alter specific bits. Entering an invalid code produces `BF error`; entering duplicate modifications for the same flag in one line produces `DF error`. Trailing arguments on the `-rf` command line itself produce `^ Error`.

---

## 3. Real-Mode Memory Architecture & Addressing

### 3.1. Segmented Address Format & Memory Bounds
* All addresses use 16-bit real-mode format: `Segment:Offset` (`SSSS:OOOO`).
* Linear address computation:
  $$\text{Linear Address} = (\text{Segment} \times 16) + \text{Offset}$$
* **Memory Capacity**: The virtual machine allocates a memory buffer of `MEM_SIZE = 110000h` (1,114,112 bytes = 1 MB conventional RAM + 64 KB High Memory Area). This permits addresses up to `FFFF:FFFF` (`10FFEFh` linear) without segmentation faults.
* **PE Section Layout & Binary Footprint**: Large buffers (`memory`, `io_ports`, console line buffers) reside in the uninitialized `.bss` section (`section '.bss' readable writeable`). This prevents binary bloat, maintaining a compact executable footprint (~82 KB).
* **Universal Range Validation**: Memory accesses across all commands (`D`, `E`, `F`, `M`, `C`, `S`, `A`, `U`, `W`, `L`, and `step()`) are checked via `check_mem_range` to prevent out-of-bounds access.
* **Segment Prefix Notation**: Address specifications across all commands support both 16-bit hexadecimal segment values (e.g. `0958:0100`) and segment register names (`CS:0100`, `DS:0100`, `ES:0100`, `SS:0100`).

### 3.2. Segment Defaults
Commands default to their logical segment if none is explicitly supplied:
* **Code Commands** (`A`, `U`, `G`, `T`, `P`): Default to `CS`.
* **Data Commands** (`D`, `E`, `F`, `M`, `S`, `C`): Default to `DS`.
* **File Operations** (`L`, `W`): Default to `CS:0100h`.

### 3.3. Sticky Offset / Continuation
* **Dump (`D`)**: A bare `D` command continues dumping from where the previous `D` finished (defaulting to 128 bytes). At startup, `dump_seg` is initialized from `DS`.
* **Unassemble (`U`)**: A bare `U` command continues disassembling from the instruction boundary where the previous `U` ended (defaulting to 32 bytes). At startup, `unasm_seg` is initialized from `CS`.
* **Assemble (`A`)**: A bare `A` command continues assembling from where the previous assembly session ended (initially `CS:0100h`).

### 3.4. Range Specifications
Commands that operate on memory ranges (`D`, `C`, `F`, `M`, `S`, `U`) support two syntax forms:
1. `address1 address2` — Start offset and ending offset (e.g., `D 100 12F`). The ending address can optionally specify a full segment:offset (`D 100 0958:012F`).
2. `address1 L count` — Start offset and byte length (e.g., `D 100 L 30`). Length variables are 32-bit (`dd`), supporting `L 0` to denote a full 64 KB block ($10000\text{h}$ bytes). The maximum allowed range length is 64 KB ($10000\text{h}$); exceeding this produces `^ Error`.

---

## 4. `.COM` Execution Environment, PSP & System Services

To execute 16-bit MS-DOS binaries, the execution engine provides a fully initialized Program Segment Prefix (PSP) structure, CPU registers, and simulated DOS/BIOS interrupt dispatchers.

### 4.1. Startup Command-Line Invocation
The debugger supports starting directly with a program and arguments from the host shell:
```text
debug86-win32.exe [filename] [arg1 arg2 ...]
```
* Supports both quoted (`"path with spaces\test.com"`) and unquoted filenames.
* The executable filename is isolated, and all subsequent parameters are forwarded into the virtual PSP command tail.
* The target binary is automatically loaded at `CS:0100h`, `BX:CX` is set to the file size, and `IP` is initialized to `0100h`. If the file is not found, `BX` and `CX` remain zero.

### 4.2. PSP Layout (`0000h` to `00FFh`)
| Offset | Size | Value / Content | Purpose |
| :---: | :---: | :--- | :--- |
| `0000h` | 2 bytes | `CD 20` (`INT 20h`) | CP/M compatibility program terminate vector |
| `0002h` | 2 bytes | `00 A0` (`A000h`) | Top of memory segment limit |
| `0005h` | 3 bytes | `CD 21 CB` (`INT 21h; RETF`) | DOS dispatcher call entry |
| `005Ch` | 16 bytes| Unopened File Control Block 1 | Cleared to zero |
| `006Ch` | 16 bytes| Unopened File Control Block 2 | Cleared to zero |
| `0080h` | 1 byte  | Argument length $N$ | Number of characters in command tail |
| `0081h` | $N$ bytes| Command-line arguments | Arguments string ending with `0Dh` (CR) |

### 4.3. Initial Register State upon Loading `.COM`
When a program is loaded into memory (at startup or via `L` at `CS:0100h`):
* `CS = DS = ES = SS = 0958h`
* `IP = 0100h` (entry point after PSP)
* `SP = FFEEh` (near top of segment)
* **Stack Return Address**: The word at `[SS:SP]` is initialized to `0000h`. Programs exiting with a bare near `RET` pop `0000h` into `IP`, branching to `PSP:0000h` (`INT 20h`) for a clean exit.
* `BX:CX` = File length in bytes (high 16 bits in `BX`, low 16 bits in `CX`).
* `AX = 0000h`, `DX = 0000h`
* `BP = SI = DI = 0000h`
* `FLAGS = NV UP EI PL NZ NA PO NC` (Interrupts enabled `EI`, all others cleared).
* **Reload State Reset**: When a binary is reloaded via `L`, the entire CPU state (including `AX`, `DX`, `BP`, `SI`, `DI`, `SP`, `IP`, flags, and stack return word) is reset to this clean initial state.

### 4.4. Critical DOS & BIOS Interrupt Emulation
The internal execution engine (`step`) intercepts and emulates standard DOS and BIOS software interrupts:

#### `INT 20h` (DOS Program Terminate)
* Terminates program execution immediately and prints `Program terminated normally`.

#### `INT 21h` (DOS Function Dispatcher)
* **`AH=00h`**: Terminate process (identical to `INT 20h`).
* **`AH=01h`**: Console input with character echo (translates CR to CRLF).
* **`AH=02h`**: Console output of single character in `DL`.
* **`AH=06h`**: Direct console I/O:
  * If `DL = FFh`: Checks keyboard status. If a character is available, clears `ZF` and returns character in `AL`; if no character, sets `ZF` and returns `AL = 00h`.
  * If `DL != FFh`: Outputs character in `DL` directly to console.
* **`AH=07h` / `AH=08h`**: Direct console input without echo (unbuffered).
* **`AH=09h`**: Output string terminated by `$` located at `DS:DX`.
* **`AH=0Ah`**: Buffered console input into structure at `DS:DX`:
  * Byte 0: Maximum character capacity.
  * Byte 1: Actual number of characters read (filled by DOS).
  * Bytes 2+: Characters read, terminated by `0Dh`.
* **`AH=0Bh`**: Check console input status (`AL = FFh` if character available, `AL = 00h` if empty).
* **`AH=25h`**: Set Interrupt Vector: sets interrupt vector `AL` in the simulated Interrupt Vector Table (IVT) to `DS:DX`.
* **`AH=30h`**: Get DOS Version: returns `AX = 0002h` (major version 2, minor 0), `BX = 0000h`, `CX = 0000h`.
* **`AH=35h`**: Get Interrupt Vector: returns current vector for interrupt `AL` from the simulated IVT in `ES:BX`.
* **`AH=4Ch`**: Terminate process with return code in `AL`. Emits `Program terminated normally`.

#### `INT 10h` (BIOS Video Services)
* **`AH=0Eh`**: Teletype character write (character in `AL`).
* **`AH=02h`**: Set cursor position (`DH` = row, `DL` = column, `BH` = page).

#### `INT 16h` (BIOS Keyboard Services)
* **`AH=00h`**: Read keyboard keystroke (returns `AL` = ASCII character, `AH` = scan code).
* **`AH=01h`**: Check keyboard buffer status (`ZF = 1` if empty; `ZF = 0` with keystroke in `AL`/`AH` if ready). Maintains a non-destructive keystroke peek buffer.

#### Real-Mode Interrupt Vector Table (IVT)
* An emulated 1024-byte IVT resides at linear address `0000:0000h` to `0000:03FFh` (256 vectors, 4 bytes each: offset then segment), permitting programs to inspect or redirect interrupt vectors via `AH=25h` and `AH=35h`.

### 4.5. Simulated Hardware Port I/O Subsystem
The application maintains a dedicated 64 KB array (`io_ports`, `0000h` to `FFFFh`) in `.bss` simulating the 8086 I/O port address space:
* Debugger commands `I` (Input) and `O` (Output) directly inspect and alter this array.
* CPU instructions `IN` and `OUT`:
  * Byte immediate: `IN AL, imm8` (`E4h`), `OUT imm8, AL` (`E6h`).
  * Word immediate: `IN AX, imm8` (`E5h`), `OUT imm8, AX` (`E7h`).
  * Variable port via `DX`: `IN AL, DX` (`ECh`), `OUT DX, AL` (`EEh`).
  * Word variable via `DX`: `IN AX, DX` (`EDh`), `OUT DX, AX` (`EFh`).
  * **16-Bit DX Port Wrapping**: Word I/O operations access two consecutive byte ports with 16-bit address wrapping (`inc dx; movzx edx, dx`). If `DX = 0FFFFh`, the second byte correctly wraps to port `0000h`.

---

## 5. Required Command Set & Functional Specification

The debugger implements the complete 20-command set of classic MS-DOS DEBUG, including execution enhancements and hardware I/O controls:

| Command | Name | Syntax | Description |
| :---: | :--- | :--- | :--- |
| **`A`** | Assemble | `A [address]` | Line-by-line 8086 assembler with `DB`/`DW` directive support |
| **`C`** | Compare | `C range address` | Compares two memory blocks and prints differing bytes |
| **`D`** | Dump | `D [range]` | Displays hexadecimal and ASCII memory dump |
| **`E`** | Enter | `E address [list]` | Enters byte values (batch list or interactive cell navigation) |
| **`F`** | Fill | `F range list` | Fills memory range with repeating byte/string pattern |
| **`G`** | Go | `G [=address] [bp1 [bp2...]]` | Executes code with up to 10 breakpoints |
| **`H`** | Hex | `H val1 val2` | Outputs 16-bit hexadecimal sum and difference |
| **`I`** | Input | `I port` | Reads and displays a byte from simulated I/O port |
| **`L`** | Load | `L [address]` | Loads file from disk into memory |
| **`M`** | Move | `M range address` | Copies memory block (handles overlapping areas) |
| **`N`** | Name | `N [filename [args]]` | Sets filename and initializes PSP command tail |
| **`O`** | Output| `O port byte` | Writes a byte to simulated I/O port |
| **`P`** | Proceed | `P [=address] [count]` | Steps over subroutine calls, loops, interrupts, string ops |
| **`Q`** | Quit | `Q` | Exits debugger (arguments rejected for safety with `^ Error`) |
| **`R`** | Register | `R [register]` | Displays or modifies registers and flags |
| **`S`** | Search | `S range list` | Searches a range of memory for a byte/string sequence |
| **`T`** | Trace | `T [=address] [count]` | Single-steps instructions with register dump |
| **`U`** | Unassemble | `U [range]` | Disassembles machine code into 8086 mnemonics |
| **`W`** | Write | `W [address]` | Writes `BX:CX` bytes of memory to file |
| **`?`** | Help | `?` | Displays list of available commands and syntax templates |

---

### 5.1. File Management Commands (`N`, `L`, `W`)

#### `N` (Name)
* **Syntax**: `N [filename [args]]`
* Sets the filename for subsequent `L` and `W` commands.
* Supports unquoted and double-quoted filenames (`N "my file.com"`).
* If command-line arguments follow the filename, `N` populates the PSP command tail at `PSP:0080h` (character count) and `PSP:0081h` (arguments ending with `0Dh`).
* A bare `N` command clears the current filename and resets the PSP command tail to empty (count 0, `0Dh` at `0081h`).

#### `L` (Load)
* **Syntax**: `L [address]`
* Loads the file specified by `N` into memory. Defaults to `CS:0100h` if no address is supplied.
* If loading at offset `0100h`, enforces the `.COM` maximum executable limit (`0FF00h` bytes), emitting `Insufficient memory` if exceeded.
* Upon successful load:
  * Sets `BX:CX` to the total file size in bytes (`BX` = high word, `CX` = low word).
  * If loaded to `CS:0100h`, resets `IP = 0100h`, `AX = DX = BP = SI = DI = 0000h`, `SP = FFEEh`, `[SS:SP] = 0000h`, and resets flags to default.
* Emits `File not found` if no filename is set or the file cannot be opened. Trailing characters after address trigger `^ Error`.

#### `W` (Write)
* **Syntax**: `W [address]`
* Writes `BX:CX` bytes from memory starting at `address` (default `CS:0100h`) into the file named by `N`.
* On success, prints the confirmation message:
  * `Writing <BX><CX> bytes` (if `BX > 0`)
  * `Writing <CX> bytes` (if `BX == 0`)
* Emits `File creation error` if filename is empty or file writing fails. Trailing characters after address trigger `^ Error`.

---

### 5.2. Memory Inspection & Manipulation Commands (`D`, `E`, `F`, `M`, `C`, `S`)

#### `D` (Dump)
* **Syntax**: `D [range]`
* Displays memory in 16-byte aligned rows:
  ```text
  0958:0100  B8 00 4C CD 21 90 90 90-90 90 90 90 90 90 90 90  ..L.!...........
  ```
* Hyphen separator placed between 8th and 9th bytes.
* ASCII column renders printable characters (`20h` to `7Eh`); non-printable bytes are rendered as `.`.
* Sticky address continuation: consecutive bare `D` commands dump sequential 128-byte blocks. Trailing garbage triggers `^ Error`. Can be interrupted with Ctrl+C.
* **Unaligned Start Offsets**: If an unaligned start offset is specified (e.g. `D 105`), DEBUG rounds down the displayed row address to the preceding 16-byte boundary (`0100`), space-pads preceding byte columns, and begins hex and ASCII output at the requested offset.

#### `E` (Enter / Edit)
* **Batch Mode**: `E address list`
  * `list` can contain hex bytes and string literals enclosed in single (`'`) or double (`"`) quotes.
  * Example: `E 100 B8 00 4C "Hello",0D,0A,'$'` writes each byte consecutively.
  * Unclosed string quotes trigger `^ Error`.
* **Interactive Mode**: `E address` (no arguments after address)
  * Switches console input to raw unbuffered single-character mode (clearing `ENABLE_LINE_INPUT` and `ENABLE_ECHO_INPUT`).
  * Suppresses leading CR/LF on the initial row.
  * Displays address and current byte value followed by a dot: `0958:0100  B8.`
  * **Hex Entry**: Typing hex characters overwrites the byte. First nibble echoes; second nibble commits the byte.
  * **`Space`**: Commits the current byte (including any pending single nibble) and advances to the next offset. If crossing a 16-byte boundary (`offset mod 16 == 0`), automatically outputs a newline and prints the new address.
  * **`-` (Hyphen)**: Commits any pending nibble and moves backward to the previous offset. Automatically wraps lines across 16-byte boundaries.
  * **`Backspace` (ASCII 8 / 127)**: Cancels the entered nibble and restores the original memory byte using erase sequences (`\b \b`).
  * **`Enter` (CR / LF)**: Commits any pending single nibble, terminates interactive edit mode, and returns to the `-` prompt.

#### `F` (Fill)
* **Syntax**: `F range list`
* Fills the specified memory range repeating the byte/string pattern cyclically until the range is filled.
* Pattern supports hex bytes and quoted strings up to 64 bytes (`FILL_PAT_MAX = 64`). Unclosed quotes trigger `^ Error`.

#### `M` (Move)
* **Syntax**: `M range address`
* Copies memory block from source range to destination address.
* Overlapping memory blocks are safely handled: if destination > source, copies in reverse (decrementing pointers) to prevent overwriting source data. Bounds checked and interruptible with Ctrl+C.

#### `C` (Compare)
* **Syntax**: `C range address`
* Compares memory block in `range` with destination starting at `address`.
* For every mismatched byte, outputs:
  ```text
  SSSS:OOOO  val1  val2  SSSS:OOOO
  ```
  (Source address, source byte, destination byte, destination address). Bounds checked and interruptible with Ctrl+C.

#### `S` (Search)
* **Syntax**: `S range list`
* Searches the memory range for a sequence of hex bytes and/or strings (up to 64 bytes pattern length). Unclosed quotes trigger `^ Error`.
* Outputs the segment:offset of every match found on its own line:
  ```text
  0958:0120
  0958:01A4
  ```
* Bounds checked and interruptible with Ctrl+C.

---

### 5.3. Arithmetic & Hardware Port Commands (`H`, `I`, `O`)

#### `H` (Hex Arithmetic)
* **Syntax**: `H val1 val2`
* Computes 16-bit hexadecimal addition and subtraction:
  ```text
  -h 100 20
  0120  00E0
  ```
* Outputs sum and difference separated by two spaces. Trailing arguments trigger `^ Error`.

#### `I` (Input from Port)
* **Syntax**: `I port`
* Reads a single byte from the simulated 64 KB I/O port address space (`io_ports`) and outputs two uppercase hex digits on a new line. Trailing arguments trigger `^ Error`.

#### `O` (Output to Port)
* **Syntax**: `O port byte`
* Writes `byte` to the specified address in the simulated 64 KB I/O port address space (`io_ports`). Trailing arguments trigger `^ Error`.

---

### 5.4. Execution & Stepping Commands (`G`, `T`, `P`)

#### Shared Parameter Parsing (`parse_exec_params`)
Execution stepping commands `T` and `P` share parameter parsing:
* Syntax: `[=address] [count]`
* Optional `=address` sets `CS:IP` before execution begins.
* Optional `count` specifies the number of instructions to execute (default 1). Must be a non-zero 16-bit hexadecimal value; count of 0 or trailing garbage triggers `^ Error`.

#### `G` (Go)
* **Syntax**: `G [=address] [bp1 [bp2 ... bp10]]`
* Optional `=address` sets `CS:IP` before execution begins.
* Up to 10 breakpoints supported (`MAX_BREAKPOINTS = 10`). Specifying more than 10 breakpoints produces `BP error`.
* Execution continues until:
  * A breakpoint is reached: registers and next instruction are displayed without banner.
  * Program terminates via `INT 20h` or `INT 21h AH=4Ch/00h`: prints `Program terminated normally`.
  * User interrupts with Ctrl+C: prints CRLF and displays current register dump.
  * Trailing invalid characters trigger `^ Error`.

#### `T` (Trace / Step Into)
* **Syntax**: `T [=address] [count]`
* Executes instructions one by one, displaying the full register dump and disassembly after each instruction.
* **Repeated String Instructions (`REP` / `REPE` / `REPNE`)**:
  * Single-stepped **one iteration at a time**.
  * Each step decrements `CX`, executes a single element operation, and keeps `IP` pointing to the prefix until `CX == 0` or the string termination condition (ZF status for CMPS/SCAS) is satisfied.
  * Intervening segment override prefixes (e.g. `REP ES: MOVSB`) are fully supported during single-stepping.
* Interruptible with Ctrl+C (prints CRLF and register dump).

#### `P` (Proceed / Step Over)
* **Syntax**: `P [=address] [count]`
* Steps over subroutines, interrupts, loops, and string operations to the following sequential instruction.
* **Inspection Logic**:
  * **Subroutine Calls**:
    * Near Call: `E8h`
    * Far Call: `9Ah`
    * Indirect Call: `FFh /2` (near) or `FFh /3` (far)
  * **Software Interrupts**:
    * `CDh <imm8>` (e.g. `INT 21h`, `INT 10h`)
    * `CCh` (`INT 3`), `CEh` (`INTO`)
  * **Loop Instructions**:
    * `E0h` (`LOOPNZ` / `LOOPNE`), `E1h` (`LOOPZ` / `LOOPE`), `E2h` (`LOOP`), `E3h` (`JCXZ`)
  * **Repeated String Instructions**:
    * Any string opcode (`A4h-A7h`, `AAh-AFh`) preceded by `F2h` (`REPNE`) or `F3h` (`REP`/`REPE`), including any intervening segment override prefix.
* **Execution Mechanics**:
  * For inspected step-over instructions: computes the target address immediately following the instruction (`proceed_target_off`), runs execution continuously until `CS:IP` reaches the target address (or program terminates / Ctrl+C is pressed), and displays the register dump.
  * For regular sequential instructions (e.g. `MOV`, `ADD`, `JMP`): falls back to single-step execution identical to `T`.

---

## 6. Assembler & Disassembler Specifications

### 6.1. Inline Assembler (`A`)
The inline assembler translates 8086 mnemonics into machine code line by line.

* **Prompt Format**: Displays the current segment and offset followed by two spaces (11 characters total):
  ```text
  -a 100
  0958:0100  
  ```
* Pressing Enter on an empty line exits assemble mode and returns to `-`.
* If a syntax error is encountered, `^ Error` is displayed pointing to the invalid token, and DEBUG prompts for the same address again.
* **Directives**:
  * **`DB`**: Assembles raw bytes and strings into memory:
    ```text
    0958:0100  db 90, 90, 0C3
    0958:0103  db "Hello, world!", 0D, 0A, '$'
    ```
  * **`DW`**: Assembles raw 16-bit words (stored in little-endian order):
    ```text
    0958:0110  dw 1234, 5678, 0000
    ```
* **Supported Instructions**:
  * **Data Transfer**:
    * `MOV`: Register-to-register (both space and comma syntax: `mov ax bx` and `mov ax,bx`), register-to-memory, memory-to-register, register-to-immediate, memory-to-immediate, accumulator direct memory (`A0h..A3h`), segment register moves (`MOV DS,AX`, `MOV AX,DS`).
    * `XCHG`: Register-to-register, accumulator short exchange (`91h..97h`), register-to-memory.
    * `PUSH` / `POP`: 16-bit general registers, memory operands, and segment registers (`PUSH CS`, `PUSH DS`, `PUSH ES`, `PUSH SS`, `POP DS`, `POP ES`, `POP SS`).
    * `LEA`, `LDS`, `LES`: Pointer and effective address loads.
    * `XLAT` / `XLATB`: Table lookup translation (`0D7h`), loading `[DS:BX+AL]` (or with segment override) into `AL`.
  * **Arithmetic & Logic**:
    * `ADD`, `ADC`, `SUB`, `SBB`, `CMP`, `AND`, `OR`, `XOR`, `TEST` across registers, memory operands, and immediate values. Short accumulator immediate opcodes are supported.
    * Signed 8-bit immediate encoding: Opcode `83h` is selected when a 16-bit destination is used with an immediate fitting in a signed byte ($-128$ to $+127$).
  * **Multiply & Divide & Unary**: `MUL`, `IMUL`, `DIV`, `IDIV`, `NOT`, `NEG`, `INC`, `DEC` (with single-byte `40h..4Fh` short forms for 16-bit registers).
  * **Shifts & Rotates**: `SHL`, `SAL`, `SHR`, `SAR`, `ROL`, `ROR`, `RCL`, `RCR` by immediate `1` or register `CL` (`shl ax, 1` or `shl ax, cl`), with memory and register operands.
  * **Jumps & Branches**:
    * Conditional jumps (30 mnemonics): `JE`, `JZ`, `JNE`, `JNZ`, `JA`, `JNBE`, `JAE`, `JNB`, `JNC`, `JB`, `JNAE`, `JC`, `JBE`, `JNA`, `JG`, `JNLE`, `JGE`, `JNL`, `JL`, `JNGE`, `JLE`, `JNG`, `JS`, `JNS`, `JO`, `JNO`, `JP`, `JPE`, `JNP`, `JPO`, `LOOP`, `LOOPE`, `LOOPZ`, `LOOPNE`, `LOOPNZ`, `JCXZ`.
    * Target addresses are specified as absolute hex values; the assembler calculates the relative displacement.
    * `JMP`: Short relative (`EB`), near relative (`E9` on displacement overflow), far direct (`EA off seg`), register indirect (`JMP AX`), memory indirect (`JMP [100]`).
    * `CALL`: Near relative (`E8`), far direct (`9A off seg`), register indirect (`CALL AX`), memory indirect (`CALL [100]`).
  * **Returns**: `RET` (near `C3`, with immediate pop count `C2`), `RETF` (far `CB`, with immediate pop count `CA`).
  * **String Instructions**: `MOVSB`, `MOVSW`, `CMPSB`, `CMPSW`, `LODSB`, `LODSW`, `STOSB`, `STOSW`, `SCASB`, `SCASW` with `REP`, `REPE`, `REPNE` prefixes.
  * **Flags & Processor Control**: `CLC`, `STC`, `CMC`, `CLD`, `STD`, `CLI`, `STI`, `HLT`, `NOP`, `WAIT`, `SAHF`, `LAHF`, `DAA`, `DAS`, `AAA`, `AAS`, `AAM`, `AAD`, `SALC`, `CBW`, `CWD`, `PUSHF`, `POPF`, `INT <imm8>`, `INTO`, `IRET`.
    * **`INT 3` Encoding**: Specifying `INT 3` assembles into the compact single-byte opcode `0CCh` rather than the two-byte `0CDh 03h`.
    * **`AAM` / `AAD` Radix**: Assembles with the default base 10 (`0Ah`) operand (`0D4h 0Ah` and `0D5h 0Ah`).
* **Addressing Syntax & Size Specifiers**:
  * Bracketed memory operands: `[BX+SI]`, `[BX+DI]`, `[BP+SI]`, `[BP+DI]`, `[SI]`, `[DI]`, `[BP]`, `[BX]`, `[disp16]`.
  * Displacements: `[BX+SI+04]`, `[BP-02]`.
  * Segment overrides: `ES:[BX]`, `CS:[100]`, `SS:[BP]`, `DS:[DI]`.
  * **Explicit Size Qualifiers**: `BYTE PTR [...]` or `WORD PTR [...]` required when operand size cannot be deduced from registers (e.g. `mov byte ptr [100], 5`). Memory immediate byte values are validated to $\le \text{0FFh}$.

### 6.2. Disassembler (`U` & Register Line 3)
* Disassembles instructions into standard 8086 mnemonics:
  ```text
  0958:0100 B8004C        MOV     AX,4C00
  0958:0103 CD21          INT     21
  ```
* Displays hex opcode bytes (up to 5 bytes formatted).
* Jump and call targets are rendered as absolute target addresses rather than relative offsets (`JNZ 0105`, `CALL 0250`).
* **Standalone Prefix Disassembly**: Segment override prefixes (`ES:`, `CS:`, `SS:`, `DS:`), repetition prefixes (`REP`, `REPNE`), and `LOCK` appearing as independent opcodes are disassembled on their own line with 12 spaces of opcode padding.
* **Far Indirect Branches**: Disassembled as `CALL FAR [...]` and `JMP FAR [...]`.
* **Signed Immediate Formatting for 83h**: For opcode `83h` (ALU with 16-bit word destination and sign-extended 8-bit immediate), DEBUG displays the immediate with an explicit `+` or `-` sign:
  ```text
  0958:0100 83C305        ADD     BX,+05
  0958:0103 83EB02        SUB     BX,-02
  ```
* **Memory Operand Live Preview**: Resolved on Line 3 of register dumps and stepping displays at column 55.
* **Unrecognized Opcodes**: Disassembled cleanly as `DB xx`.

---

## 7. Instruction Execution Engine (`step()` Architecture)

The execution engine simulates the complete 16-bit 8086 real-mode instruction set through a centralized cycle dispatcher (`step`).

### 7.1. CPU Core State Structure
The virtual processor state is maintained in a centralized `cpu_state` structure:
* **Registers** (13 words): `AX, BX, CX, DX, SP, BP, SI, DI, DS, ES, SS, CS, IP`.
* **Flags** (8 bytes): `OV, DN, EI, NG, ZR, AC, PE, CY`.
* **Stack Return Vector**: `[SS:SP]` initialized to `0000h` to trap program exit via near `RET`.
* **Execution Status Codes**:
  * `STEP_OK` (0): Instruction executed successfully.
  * `STEP_PROGRAM_END` (1): Program terminated (`INT 20h` or `INT 21h AH=4Ch/00h`).
  * `STEP_UNKNOWN` (2): Unrecognized instruction byte encountered; execution halts and displays register dump.
  * `STEP_ERROR` (3): Out-of-bounds memory access encountered; outputs `^ Error`.
  * `STEP_BREAKPOINT` (4): Software interrupt `INT 3` (`CCh`), `INTO` (`CEh`), or `HLT` (`F4h`) triggered; execution halts and displays register dump.

### 7.2. Full ModR/M Addressing Decoder (`decode_modrm`)
* Decodes all 8 base addressing combinations: `BX+SI`, `BX+DI`, `BP+SI`, `BP+DI`, `SI`, `DI`, `BP`, `BX`.
* Handles Mod 00 (no displacement, or 16-bit direct displacement if R/M=6), Mod 01 (8-bit signed displacement), and Mod 10 (16-bit displacement).
* Resolves register operands (Mod 11) for 8-bit and 16-bit register files.
* Applies segment override prefixes (`ES:`, `CS:`, `SS:`, `DS:`). Defaults memory references involving `BP` to `SS`, and all other memory references to `DS`.

### 7.3. Arithmetic, Shift & Flag Mechanics
* **Hardware Flag Emulation**: Status flags (`OF`, `SF`, `ZF`, `AF`, `PF`, `CF`) are calculated via host `EFLAGS` (`update_flags_from_eflags`) after executing ALU operations.
* **Rotates (`ROL`, `ROR`, `RCL`, `RCR`)**: Authentically updates **only `CF`** and (when shift count is 1) **`OF`**. Status flags `ZF`, `SF`, `AF`, and `PF` are strictly preserved without modification.
* **Shifts (`SHL`, `SAL`, `SHR`, `SAR`)**: Updates all status flags. Shifts by `CL` where count is zero skip execution and preserve flags.
* **Carry-In Instructions (`ADC`, `SBB`, `RCL`, `RCR`)**: Loads the carry flag from `flag_states[FLAG_CY]` immediately before execution.
* **Decimal Arithmetic**: Implements `DAA`, `DAS`, `AAA`, `AAS`, `AAM`, `AAD`, and `SALC` with exact 8086 flag side-effects.
* **Stack & Flag Packing**:
  * `PUSHF` packs `cpu_state` flags into the authentic 8086 16-bit FLAGS format (with bit 1 reserved fixed to 1):
    $$\text{Bit: } \text{CF}(0), 1(1), \text{PF}(2), \text{AF}(4), \text{ZF}(6), \text{SF}(7), \text{IF}(9), \text{DF}(10), \text{OF}(11)$$
  * `POPF` unpacks the 16-bit stack word into the 8 virtual flag bytes.
* **Processor Halts & Breakpoints**:
  * `HLT` (`F4h`): Halts execution into breakpoint status (`STEP_BREAKPOINT`), cleanly displaying the register dump.
  * `INT 3` (`CCh`): Traps into breakpoint status without banner.
  * `INTO` (`CEh`): If `OF` is set, traps into breakpoint status; if cleared, continues execution.

---

## 8. Modular Implementation Architecture

The codebase is structured into dedicated, decoupled modules following separation of concerns:

| Source File | Primary Responsibility |
| :--- | :--- |
| `main.asm` | PE console entry point, Win32 API imports, main REPL loop, command dispatch table (`COMTAB`), help and quit handlers. |
| `equates.inc` | Architecture-wide constants, equates, structure offsets, and table generator macros (`cmd_entry`, `reg_entry`, `flag_entry`). |
| `data.inc` | Core data buffers, `cpu_state`, `flag_states`, flag code mappings, text messages, and static dispatch tables. |
| `utils.inc` | Output buffering (`print_buffer`), syntax error caret alignment (`print_error`), address parser (`parse_address`, `parse_address_cs`), range/length parser (`parse_length`), pattern list parser (`parse_pattern_list`), range validation (`check_mem_range`), console/pipe input stream handler. |
| `hex.inc` | Hexadecimal numeric parsing (`parse_hex`, `parse_hex_byte`) and formatted output routines (`put_hex_word`, `put_hex_byte`, `put_hex_nibble`). |
| `dos_file.inc` | PSP initialization (`init_psp`), startup argument parsing (`parse_startup_cmdline`), file loading (`cmd_load`), writing (`cmd_write`), and naming (`cmd_name`). |
| `cmd_reg.inc` | Register and flag inspection/editing (`cmd_register`, `cmd_rf`), and full CPU state formatting (`show_cpu_state`, `print_registers`). |
| `cmd_memory.inc` | Memory inspection and manipulation (`cmd_dump`, `cmd_edit`, `cmd_fill`, `cmd_move`, `cmd_compare`, `cmd_search`), and I/O port/hex arithmetic commands (`cmd_hex`, `cmd_input`, `cmd_output`). |
| `cmd_exec.inc` | Execution flow control (`cmd_go`, `cmd_trace`, `cmd_proceed`), shared execution parameter parsing (`parse_exec_params`), and step-over inspection logic. |
| `cpu_interrupts.inc` | Simulated DOS and BIOS interrupt dispatchers (`INT 20h`, `INT 21h`, `INT 10h`, `INT 16h`), non-blocking keyboard peeking, and emulated IVT. |
| `cpu_step.inc` | Virtual 8086 processor core dispatcher (`step`), ModR/M addressing decoder (`decode_modrm`), ALU, shift/rotate, jump, call, stack, and string operation handlers. |
| `disasm.inc` | 8086 disassembler (`cmd_unassemble`, line 3 instruction disassembly) with effective address resolution and column 55 live memory preview. |
| `asm.inc` / `asm_tables.inc` | Interactive line-by-line 8086 assembler (`cmd_assemble`) with `DB`/`DW` directive support, mnemonic lookup, and instruction encoding tables. |
