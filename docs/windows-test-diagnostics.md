# Windows test exit diagnostics

This is a validation-blocker diagnostic, not a product/runtime fix or a crash
upload feature. It preserves Cargo's tests, filters, package working directories,
default libtest concurrency, pixel assertions and nonzero failure behavior.
There is no retry, debugger replay, global serialization, installed application,
desktop input, registry/WER change, or process-name-based termination.

## The still-open failure

[#330](https://github.com/fes/fesTerm/issues/330) recorded run `37250376126`,
attempt 1, Windows job `111576603780`, at head
`748e97cc7530202ddbf133241dbfd3fc9e75e83b`. At `2026-10-05T01:15:10Z`,
`cargo test --workspace` reported `festerm-ui-egui` exit **2173 / 0x0000087d**
without an assertion or identified failing test. Artifact `11321066752`
contained only 28 PNGs. Attempt 2 passed at the same head: that is neither a
cause nor a repair. The separately diagnosed Direct2D `0xc0000005` wrapped-target
retirement repair (#336, superseded by #329) is not a repair of exit 2173.
**Causal reproduction and investigation remain required; do not close #330
based on this runner or another green rerun.**

## Required CI and local execution

The temporary PR345 diagnostic branch calibrates this reviewed runner and
then launches at most three bare/traced pairs (six complete app-test processes),
alternating pair order and stopping on the first nonzero execution, including
before a partner can run. The executable is selected from a full-workspace `--no-run`
build to preserve Cargo feature unification; its original package working
directory, libtest scope, capture, concurrency and level-zero CI profiles stay
unchanged. The required CI workflow and production Rust sources are unchanged.
This is a capture experiment, not a causal repair or merge qualification:
successful controls cannot unblock PR345 or close #330. The first diagnostic
run, [37854116239](https://github.com/fswiderski/fesTerm/actions/runs/37854116239),
completed six traced processes without reproduction; it is preserved separately,
not replaced by the subsequent paired experiment.

Only bounded content-free JSON metadata is uploaded. Build JSONL, ordinary
stdout, PDBs and executable files are not artifacts. Native receipts retain
module offsets when local symbols are
unavailable; local level-1 builds can provide PDB-backed symbol names without
changing the CI workload. Neither PDBs nor executables are uploaded by this
integration.

From a PowerShell session, pass an actual argument array:

```powershell
.\scripts\run-windows-tests.ps1 -CargoArguments @('test', '--workspace')
```

Use `-OutputDirectory <owned-directory>` and `-TimeoutSeconds <1..14400>` to
override `target\windows-test-diagnostics` and the 1800-second
**per-executable** deadline. The caller's `CARGO_TARGET_DIR` is respected. The
Python runner accepts only executables inside this checkout or that explicitly
selected build directory; it cannot attach to an existing PID. Unique receipt
names permit parallel Cargo invocations without overwriting evidence.

The implementation uses installed Windows `kernel32` debug APIs and System32
`dbghelp`, not a required SDK/CDB download. It reuses and extends the controlled
2173 C# exit-calibration fixture from `diagnose/windows-direct2d-native-crash`.
That older replay's CDB command files, raw register/stack/event-log transcripts
and debugger `q` exit semantics are deliberately not copied into CI.
The `feature/crash-exit-diagnostics` application journals remain local and
separate; their raw logs/panic reports are not safe automatic CI artifacts.

## Evidence and privacy boundary

Each root test process is launched under `DEBUG_ONLY_THIS_PROCESS`, suspended
until the debugger owns its startup. Descendants are **not** debugged or
recorded. The child receives a native Unicode environment-block copy with only
`_NO_DEBUG_HEAP=1` overridden: Windows must not enable its debugger-default heap
validation and change allocation behavior compared with ordinary, uninstrumented
tests. Hidden drive entries and UTF-16 values are preserved. The parent
environment and registry are untouched, and environment contents are never
included in receipts. The safe `debug_heap_policy` label records this policy.
The runner observes normal debug events, passes application
exceptions through unchanged, and captures a second-chance fault before
Windows terminates the process. One-shot entry probes at
`ntdll!RtlExitUserProcess` and `ntdll!NtTerminateProcess` capture a nonzero
exit/termination code and stacks; original instructions and the thread's PC
are restored before continuation. The debugger never substitutes its own
success exit for the test status.

Receipts contain source HEAD/tree/dirty flag, executable basename/SHA-256/size,
allowlisted GitHub run identity, root PID, timestamps, unsigned/signed/hex
Windows status, exception code/chance/address, termination API, thread IDs,
bounded PC/module-offset stacks, optional local symbol names, module basenames,
PE timestamp/image size and available PDB GUID/age (not its embedded path).
Symbols are looked up locally; environment symbol-server paths are ignored.
No symbol-server download is configured.

Ordinary test stdout/stderr still reaches the existing CI console. The runner
does **not** upload or persist that transcript. Its only parsed output is
libtest's compile-time test name/result lines. Raw memory, dumps, exception
parameters, arbitrary register values, stack arguments/locals, debug strings,
source/file paths, command arguments, environment dumps, machine/user names,
Application/WER event messages and installed-user journals are excluded.
Debugger memory reads are used internally for PE metadata/unwinding and probe
instruction restoration; those bytes are never written into receipts.

The temporary PR345 experiment additionally opts into
`--d3d12-validation-ids`: at most 256 root debug strings of at most 4,096
characters are read internally. Only canonical D3D12 validation records are
recognized, and at most 64 distinct numeric category/severity/message-ID/thread
tuples and bounded occurrence counts are retained. All message text, resource
names and paths are immediately discarded and never copied into receipts,
console output or error details. Read failures and exhausted bounds explicitly
mark this optional capture partial. Without this flag, debug strings are not
read at all. Observed IDs are not trusted provenance, active-test attribution
or a diagnosed cause. Deliberately private ANSI/Unicode calibration messages
prove this boundary and preserve the fixture's original exit 2173.

The `--bare` control uses ordinary, uninstrumented child creation and the same
output/result-line handling. It reports the original DWORD but explicitly has
no debugger/module/stack capture. Its timeout/error cleanup reuses the same
creation-time-verified, pinned-handle owned-tree logic. It cannot be combined
with validation-ID capture. Neither mode changes Windows debug-layer break
settings, filters, registry, endpoint protection, assertions or concurrency.

The `windows-native-test-metadata` artifact uploads only receipt JSONs, even
on failure, with seven-day retention. Existing snapshot artifacts remain
unchanged. Do not broaden the upload glob to PDBs, dumps or ordinary logs.

## Classification, bounds and exact limitations

- `passed`: original target status 0.
- `rust_test_failure`: status 101 without an observed second-chance exception.
  It is the libtest convention, not proof of which assertion failed.
- `native_exception`: observed second-chance exception; original status retained.
- `native_exit_unknown_cause`: other nonzero exit, including 2173; **not**
  automatically labeled an access violation or diagnosed cause.
- `timeout`: owned execution exceeded its deadline; runner status 124.
- `diagnostic_tool_unavailable`: required API/architecture unavailable; target
  is not started and runner status is 125, never a successful fallback.
- `runner_error`: diagnostic execution/persistence failed; status 125, never
  inferred success. Invalid CLI arguments return 2 before launching a target.

Cargo still returns its ordinary aggregate test failure status (usually 101);
the runner itself preserves the original target DWORD, including statuses above
`INT_MAX`. The receipt separates target status from timeout/runner status.
Optional unwinding/module/probe limitations are explicit within the receipt and
do not turn a failing target into a pass. Missing stack initialization or exit
probes marks capture `partial`, rather than claiming complete native evidence.

Capture currently supports Windows AMD64 with 64-bit Python. Stable parallel
libtest does not publish test-start/thread attribution: completed test names,
native threads and stacks are retained, but **no last-reported test is claimed
as the failing test**. Buffered output may be lost on abrupt exit. A thread in
optimized/managed/generated code may have only a PC; PDBs may be absent, and
module offset/GUID/hash metadata needs matching local binaries/symbols for
further analysis. Doctests and child executables started directly by a test do
not go through Cargo's target runner and are not covered.

Probes are one-shot and perturb scheduling like any debugger. A termination
from another process or kernel may provide only the root exit event, not a
caller stack. An earlier `NtTerminateProcess` invocation targeting a different
process can consume that probe; it is not proof that the root exited there.
No debugger can retrospectively establish the cause of the original run.

### Collector-induced syntax budget failure

The first cumulative gate at
`e7a9a902be5e01160c36238a928745a450ce078a` retained a real status-101 failure:
`festerm-syntax::tests::only_the_range_asked_for_is_queried` produced no spans.
This is separate from #330's unexplained exit 2173. Its original failed gate
and receipt remain evidence, not replaced by a green rerun.

Matched controls used the **same original executable**, SHA-256
`dc7cfc3e5c0621c98cd88654468db8a960a59ff4e1872d4a24c8a9e03357b744`,
without rebuilding or changing the syntax source, its 40 ms parse budget, test
assertions or default test concurrency. Both bare full-scope controls passed;
both original-wrapper full-scope controls failed the same assertion. The
single exact test also passed bare and failed under the original wrapper.
Event-service timing showed no debug events between creation of that test
thread and its assertion panic; startup module handling was sub-millisecond.
This did not support a live symbol/stack-handler pause as the cause.

Changing only `_NO_DEBUG_HEAP=1` made the original wrapper's full and exact
scopes pass. An independent owned fixture read the native heap-validation flag
mask: bare **0**, original debugger **0x70**, fixed debugger **0**. The new
child-only environment policy therefore restores bare heap behavior instead
of increasing the product's deadline or hiding its failure. The fixed wrapper
passed the same full/exact scopes with unchanged event, stack and module
handling. Debugger scheduling overhead still exists; this is not a claim of
zero observation cost or complete workspace qualification.

Limits: 512 event and module records; eight stack captures, 64 threads and up to
24 frames per capture; 8192 reported test names; 512-byte output-line parsing
buffers; a 4 MiB receipt ceiling with explicit truncation. Root execution has
the configured deadline, followed by at most ten seconds of debug-exit draining;
owned descendant exit waits have a shared five-second budget and stdout/stderr
reader cancellation is bounded. System debug/unwind/file APIs themselves are
not forcibly interrupted; no remote symbol requests are made.

Timeout/error cleanup snapshots the descendant tree, validates creation times,
pins exact process handles, terminates descendants before the root and checks
their exits. It never terminates by executable name, inspects unrelated process
content, changes Job Object policy, or kills intentional surviving descendants
after a normal test exit. Depth beyond 32 generations is not a supported test
fixture. The debugger's own process must remain alive to collect a receipt;
whole-runner/job termination can prevent final persistence.

## Focused validation

```powershell
python -m unittest discover -s scripts\tests -p test_windows_test_runner.py -v
python -m unittest discover -s scripts\tests -p "test_windows_*.py" -v
python scripts\check_validation_traceability.py
```

The native suite compiles the owned fixture with the installed Windows Framework
C# compiler; it requires no GPU or desktop interaction. It proves original
0/101/2173/high-bit status propagation, genuine second-chance native exception,
termination stacks, bounded owned-tree timeout cleanup with a same-name foreign
sentinel, argument rejection, explicit unavailable/failed diagnostics,
content-free completed-test context, PowerShell/Cargo argument boundaries,
bare/debugger heap-policy parity and preservation of parent, Unicode and
hidden-drive environment entries without recording their contents.
These are runner proofs, **not** a reproduction of the unexplained UI exit.
