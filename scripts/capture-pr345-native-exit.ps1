[CmdletBinding()]
param([ValidateRange(1,6)][int] $Iterations = 6)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if ($env:OS -ne 'Windows_NT') { throw 'Native-exit capture requires Windows.' }
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$head = git rev-parse HEAD
$tree = git rev-parse 'HEAD^{tree}'
if (@(git status --porcelain --untracked-files=no).Count) {
    throw 'Diagnostic source must be clean and committed.'
}
$out = Join-Path $root 'target\pr345-native-capture'
if (Test-Path -LiteralPath $out) { throw 'Preserve existing capture evidence.' }
New-Item -ItemType Directory -Path $out | Out-Null
$observations = [Collections.Generic.List[object]]::new()
$report = [ordered]@{
    source_head=$head;source_tree=$tree;
    logical_candidate_base='bfa31bba84676151092f8d434bde008674017415';
    cargo_build_scope='cargo test --locked --workspace --no-run --message-format json';
    libtest_scope='complete app executable; default concurrency and capture';
    requested_iterations=$Iterations;outcome='building';
    causal_repair_claimed=$false;observations=@()
}
function Save-Report {
    $report.observations = @($observations.ToArray())
    $report | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $out 'supervisor.json') -Encoding utf8
}
Save-Report
try {
    cargo test --locked --workspace --no-run --message-format json 1> (Join-Path $out 'build.jsonl')
    if ($LASTEXITCODE -ne 0) { throw 'Full-workspace feature-parity compilation failed.' }
    $artifacts = Get-Content -LiteralPath (Join-Path $out 'build.jsonl') |
        ForEach-Object {$_ | ConvertFrom-Json} |
        Where-Object {$_.reason -eq 'compiler-artifact' -and $_.target.name -eq 'festerm' -and $_.profile.test -and $_.executable}
    if (@($artifacts).Count -ne 1) { throw 'Expected exactly one compiler-reported app test executable.' }
    $executable = [IO.Path]::GetFullPath($artifacts.executable)
    $target = if ($env:CARGO_TARGET_DIR) {[IO.Path]::GetFullPath($env:CARGO_TARGET_DIR)} else {Join-Path $root 'target'}
    if (-not $executable.StartsWith($target.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Compiler-reported executable is outside the owned build directory.'
    }
    $hash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
    $report.executable = [ordered]@{name=[IO.Path]::GetFileName($executable);sha256=$hash}
    Set-Location (Join-Path $root 'app\festerm')
    for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
        if ((git -C $root rev-parse HEAD) -cne $head -or
            (git -C $root rev-parse 'HEAD^{tree}') -cne $tree -or
            @(git -C $root status --porcelain --untracked-files=no).Count -or
            (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash -cne $hash) {
            throw 'Source or original executable changed during capture.'
        }
        $started = Get-Date
        python (Join-Path $PSScriptRoot 'windows_test_runner.py') --output-root $out --timeout-seconds 300 -- $executable
        $code = $LASTEXITCODE
        $observations.Add([ordered]@{
            iteration=$iteration;runner_exit_code=$code;
            duration_seconds=((Get-Date)-$started).TotalSeconds
        })
        $report.outcome = if ($code -eq 0) {'no_native_failure_observed_yet'} else {'nonzero_original_execution_preserved'}
        Save-Report
        if ($code -ne 0) { throw "Original app execution returned $code; stop and inspect native metadata. No retry." }
    }
    $report.outcome = 'bounded_control_completed_without_reproduction_not_a_repair'
    Save-Report
    Write-Output 'Bounded diagnostic completed without reproduction. This does not repair exit 2173 or unblock PR345.'
} finally {
    Save-Report
    Set-Location $root
}
