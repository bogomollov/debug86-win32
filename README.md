<div align="center">
<h1>Debug86 Win32</h1>
<p align="center">An authentic MS-DOS DEBUG.EXE-style console debugger for modern Windows built in x86 assembly. It features an emulated 16-bit 8086 real-mode CPU, a segmented memory architecture, and an integrated assembler and disassembler. Supports single-stepping, breakpoints, simulated DOS/BIOS interrupts, and direct execution of 16-bit .COM programs.</p>
</div>

**Debug86 Win32** is a native 32-bit Windows console debugger (PE console, written in Flat Assembler) that replicates the authentic interface, command set, and behavior of the classic MS-DOS `DEBUG.EXE`. It provides a full 16-bit 8086 real-mode virtual environment with a segmented 1 MB + 64 KB memory space, allowing developers and retrocomputing enthusiasts to load, inspect, disassemble, assemble, and execute MS-DOS `.COM` programs directly on modern 32-bit and 64-bit Windows without needing an external emulator like DOSBox.

### Key Features

* **Virtual 8086 Real-Mode Environment**: Complete register architecture (`AX`, `BX`, `CX`, `DX`, `SP`, `BP`, `SI`, `DI`, `CS`, `DS`, `SS`, `ES`, `IP`) and 8086 FLAGS (`OF`, `DF`, `IF`, `SF`, `ZF`, `AF`, `PF`, `CF`).
* **Segmented Memory Model**: 1,114,112 bytes (1 MB conventional memory + 64 KB HMA) supporting full `Segment:Offset` real-mode addressing, segment overrides, and boundary safety checks.
* **Full 20-Command Set**: Implements the complete classic MS-DOS DEBUG command suite:
  * **Memory**: `D` (Dump), `E` (Enter/Edit &mdash; batch list and interactive single-cell modes), `F` (Fill), `M` (Move with overlap safety), `C` (Compare), `S` (Search).
  * **Code & Assembly**: `A` (Line-by-line assembler with `DB`/`DW` directives), `U` (Unassemble with live effective address dereference previews at column 55).
  * **Execution**: `G` (Go with up to 10 breakpoints), `T` (Trace single-step into, stepping repeated string ops per iteration), `P` (Proceed step-over calls, loops, software interrupts, and string ops).
  * **Registers & Ports**: `R` / `RF` (Inspect and modify registers and flags), `I` / `O` (Read/write from simulated 64 KB I/O port address space), `H` (Hexadecimal addition and subtraction).
  * **File Operations**: `N` (Name file and set PSP argument tail), `L` (Load file into memory), `W` (Write memory block to disk).
  * **Control**: `Q` (Quit with strict argument validation), `?` (Command syntax reference).
* **Authentic DOS & BIOS Emulation**:
  * **PSP Layout**: Automatic Program Segment Prefix generation at `CS:0000h` (`INT 20h` exit, `A000h` memory ceiling, `INT 21h; RETF` dispatcher, FCBs, command tail at `80h`, and near `RET` termination).
  * **Interrupt Dispatchers**: Emulates `INT 20h` (terminate), `INT 21h` (functions `00h`, `01h`, `02h`, `06h`, `07h`/`08h`, `09h`, `0Ah`, `0Bh`, `25h`, `30h`, `35h`, `4Ch`), `INT 10h` (BIOS teletype and cursor positioning), and `INT 16h` (BIOS keyboard input with peek buffer).
* **Strict MS-DOS Authenticity**:
  * Dynamic column-aligned caret error formatting (`^ Error`) accounting for tab stops and prompt lengths.
  * Classic error designations: `BR error` (bad register), `BF error` (bad flag), `DF error` (duplicate flag), and `BP error` (too many breakpoints).
  * Native Code Page 866 (MS-DOS OEM Cyrillic/box-drawing) support.
  * Standard stream redirection support (pipes and batch scripts) with automated input fallback and Ctrl+C interrupt handling.
