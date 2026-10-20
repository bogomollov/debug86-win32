import os
import subprocess
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import List, Optional, Union

# Path to the debug86-win32.exe executable
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEBUG_EXE = PROJECT_ROOT / "debug86-win32.exe"


class DebugResult:
    """Encapsulates the result of running debug86-win32."""

    def __init__(self, stdout: str, stderr: str, returncode: int):
        self.stdout = stdout
        self.stderr = stderr
        self.returncode = returncode
        self.lines = stdout.splitlines()

    def contains(self, text: str) -> bool:
        return text in self.stdout

    def has_error(self) -> bool:
        error_indicators = [
            "^ Error",
            "BR error",
            "BF error",
            "DF error",
            "BP error",
            "File not found",
            "File creation error",
            "Insufficient memory",
        ]
        return any(err in self.stdout for err in error_indicators)

    def __repr__(self):
        return f"<DebugResult returncode={self.returncode} stdout_len={len(self.stdout)}>"


def run_debug(
    commands: Optional[Union[List[str], str]] = None,
    args: Optional[List[str]] = None,
    timeout: float = 5.0,
    cwd: Optional[Union[str, Path]] = None,
    input_bytes: Optional[bytes] = None,
) -> DebugResult:
    """
    Executes debug86-win32.exe with optional CLI arguments and stdin commands.
    """
    if not DEBUG_EXE.exists():
        raise FileNotFoundError(f"debug86-win32.exe not found at {DEBUG_EXE}")

    cmd = [str(DEBUG_EXE)]
    if args:
        cmd.extend(args)

    if input_bytes is not None:
        stdin_data = input_bytes
    elif commands is not None:
        if isinstance(commands, list):
            script = "\n".join(commands) + "\n"
        else:
            script = commands
            if not script.endswith("\n"):
                script += "\n"
        stdin_data = script.encode("cp866", errors="replace")
    else:
        stdin_data = b""

    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=cwd or PROJECT_ROOT,
    )

    try:
        stdout_raw, stderr_raw = proc.communicate(stdin_data, timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout_raw, stderr_raw = proc.communicate()
        raise TimeoutError(f"debug86-win32 timed out after {timeout} seconds")

    stdout = stdout_raw.decode("cp866", errors="replace")
    stderr = stderr_raw.decode("cp866", errors="replace")

    return DebugResult(stdout, stderr, proc.returncode)


@contextmanager
def temporary_binary(content: bytes, filename: Optional[str] = None):
    """
    Creates a temporary binary file in the project directory, yields its Path,
    and removes it upon exit.
    """
    if filename:
        temp_path = PROJECT_ROOT / filename
    else:
        temp_file = tempfile.NamedTemporaryFile(
            dir=PROJECT_ROOT, prefix="dbg_", suffix=".com", delete=False
        )
        temp_file.close()
        temp_path = Path(temp_file.name)

    temp_path.write_bytes(content)
    try:
        yield temp_path
    finally:
        if temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass
