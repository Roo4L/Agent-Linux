#!/usr/bin/env python3
"""tests/bats/helpers/tty-driver.py — Plan 15-01 TTY simulation helper.

Spawns the given command inside a freshly-allocated pty (so the spawned
program sees [[ -t 0 ]] == true), feeds the provided input bytes to the
pty master, captures everything the program writes back, and exits with
the child's exit code.

Used by tests/bats/15-preflight-ux.bats (Tests 7-8, 12) to exercise the
TTY per-action prompt loop. Reliable across container environments where
`script(1)`'s pipe-stdin-to-pty forwarding has been observed to wedge.

Usage:
    tty-driver.py INPUT_STRING -- CMD [ARGS...]

INPUT_STRING uses Python `\\n` escapes (literally backslash-n in the
argv; the script interprets them via .encode().decode('unicode_escape')).

Example:
    tty-driver.py 'Y\\nY\\n' -- bash /opt/agentlinux-src/plugin/bin/agentlinux-install

Output:
    The full child stdout+stderr is written to this script's stdout.
    Exits with the child's exit code (or 1 on internal failure).
"""

from __future__ import annotations

import os
import pty
import select
import signal
import sys
import time


def main() -> int:
    if len(sys.argv) < 4 or sys.argv[2] != "--":
        sys.stderr.write(
            "usage: tty-driver.py INPUT_STRING -- CMD [ARGS...]\n"
            f"got: {sys.argv!r}\n"
        )
        return 1

    raw_input = sys.argv[1]
    cmd = sys.argv[3:]

    # Convert backslash escapes (\n, \t, \r, etc.) the same way bash printf
    # %b would. We use unicode_escape on the encoded bytes so '\\n' becomes
    # a literal newline (0x0a).
    try:
        input_bytes = bytes(raw_input, "utf-8").decode("unicode_escape").encode("utf-8")
    except UnicodeDecodeError as exc:
        sys.stderr.write(f"tty-driver: cannot decode INPUT_STRING ({exc})\n")
        return 1

    pid, fd = pty.fork()
    if pid == 0:
        # Child process: replace self with the target command.
        try:
            os.execvp(cmd[0], cmd)
        except FileNotFoundError as exc:
            sys.stderr.write(f"tty-driver: cannot exec {cmd[0]}: {exc}\n")
            os._exit(127)
        except OSError as exc:
            sys.stderr.write(f"tty-driver: exec failed for {cmd[0]}: {exc}\n")
            os._exit(126)

    # Parent process: feed input to the pty master + capture all output.
    #
    # CRITICAL TIMING: writing all input bytes immediately (before the child
    # has reached its first `read`) can race — the bytes land in the pty's
    # input buffer before the child's stdin descriptor is fully wired up,
    # and bash's later `read` blocks forever. The reliable pattern is:
    # write one byte at a time, AFTER each prompt arrives. We trigger a
    # write when the most recent output chunk ends with the prompt sentinel
    # 'Proceed with this remediation? [Y/n] (...)' or — more conservatively
    # — when output activity has been quiet for one select cycle (the child
    # is presumably blocked on read).
    #
    # See plugin/lib/prompt.sh for the prompt format.
    PROMPT_QUIET_THRESHOLD = 2  # consecutive empty-read cycles → assume read-block
    EOF_AFTER_EMPTY_QUIET = 6  # cycles of quiet AFTER write_buf is empty → send EOF (^D)
    write_buf = input_bytes
    output: list[bytes] = []
    quiet_cycles = 0
    eof_sent = False

    # Bounded overall timeout — DEFENSIVE.
    #
    # This driver waits on a `select` loop with no upper bound; an unexpected or
    # stuck prompt (e.g. the EL9 15-preflight-ux brownfield-fixture mis-state)
    # therefore blocked ~13 min on a single test before. A wall-clock deadline
    # converts that hang into a fast, diagnosable non-zero exit. The select loop
    # is the pexpect analog for this raw-pty driver, so the bound lives here as
    # a deadline rather than a pexpect `timeout=` kwarg. The underlying cause is
    # fixed upstream (brownfield.bash EL9 generalization); this bound
    # ensures an unbounded wait can never hang the suite again.
    #
    # Generous enough for a real installer prompt cycle (detection probes run
    # `sudo -i` npm reads), far under the suite's prior 13-min tolerance.
    # Overridable via TTY_DRIVER_TIMEOUT (seconds) for unusually slow hosts.
    try:
        overall_timeout = float(os.environ.get("TTY_DRIVER_TIMEOUT", "120"))
    except ValueError:
        overall_timeout = 120.0
    deadline = time.monotonic() + overall_timeout

    while True:
        if time.monotonic() > deadline:
            # Stuck/unexpected prompt: the child neither consumed our input nor
            # produced an expected prompt within the bound. Surface the awaited
            # state — remaining unsent input plus the TAIL of captured output,
            # which IS the prompt we were blocked on — then fail fast (exit 124,
            # the GNU `timeout` convention) instead of hanging the bats suite.
            awaited = b"".join(output)[-512:]
            sys.stderr.write(
                f"tty-driver: TIMEOUT after {overall_timeout:.0f}s waiting on "
                f"child {cmd[0]!r} "
                f"(unsent_input={len(write_buf)} bytes, eof_sent={eof_sent}); "
                "awaited prompt (last output) follows:\n"
            )
            sys.stderr.flush()
            sys.stderr.buffer.write(awaited)
            sys.stderr.buffer.write(b"\n")
            sys.stderr.buffer.flush()
            sys.stdout.buffer.write(b"".join(output))
            sys.stdout.flush()
            try:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            except (ProcessLookupError, ChildProcessError, OSError):
                pass
            return 124
        rlist = [fd]
        try:
            r, _, _ = select.select(rlist, [], [], 0.5)
        except OSError:
            break
        if fd in r:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                # pty closed (child exited)
                break
            if not chunk:
                break
            output.append(chunk)
            quiet_cycles = 0
        else:
            quiet_cycles += 1
            # When output goes quiet, the child is probably blocked on read.
            # Feed one byte at a time so each prompt sees its own byte.
            if quiet_cycles >= PROMPT_QUIET_THRESHOLD and write_buf:
                try:
                    os.write(fd, write_buf[:1])
                    write_buf = write_buf[1:]
                    quiet_cycles = 0
                except OSError:
                    break
            # Plan 15-02 (UX-04 Test 15): once input is exhausted AND the child
            # is still blocked on read, send EOF (^D = 0x04 in canonical/ICANON
            # pty mode) so `read -r response` returns non-zero and the alt-user
            # prompt's EOF-bail path fires. Without this, Test 15 (decline-and-
            # bail via EOF) hangs forever because pty.fork()'s slave-side TTY
            # never closes on its own.
            elif (
                quiet_cycles >= EOF_AFTER_EMPTY_QUIET
                and not write_buf
                and not eof_sent
            ):
                try:
                    os.write(fd, b"\x04")  # Ctrl-D / EOT
                    eof_sent = True
                    quiet_cycles = 0
                except OSError:
                    break
        # Reap child non-blockingly so the loop terminates after the child
        # closes its pty side.
        try:
            wpid, status = os.waitpid(pid, os.WNOHANG)
            if wpid != 0:
                # Drain any remaining output before returning.
                while True:
                    try:
                        chunk = os.read(fd, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output.append(chunk)
                sys.stdout.buffer.write(b"".join(output))
                sys.stdout.flush()
                # Surface the child's exit code (POSIX bit-packed in `status`).
                if os.WIFEXITED(status):
                    return os.WEXITSTATUS(status)
                if os.WIFSIGNALED(status):
                    return 128 + os.WTERMSIG(status)
                return 1
        except ChildProcessError:
            break

    # Reap if we exited the loop before the WNOHANG branch saw the child.
    sys.stdout.buffer.write(b"".join(output))
    sys.stdout.flush()
    try:
        _, status = os.waitpid(pid, 0)
        if os.WIFEXITED(status):
            return os.WEXITSTATUS(status)
        if os.WIFSIGNALED(status):
            return 128 + os.WTERMSIG(status)
    except ChildProcessError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
