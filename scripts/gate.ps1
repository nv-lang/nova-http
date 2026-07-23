# SPDX-License-Identifier: MIT OR Apache-2.0
# nova-http package gate (Plan 222 §9, owner-go 2026-07-23).
#
# Two mandatory steps, in order:
#   1. `nova check src --strict-effects` — the WHOLE package must type-check
#      under strict effects (E_UNDECLARED_TRANSITIVE_EFFECT /
#      E_EFFECT_ERASED_IN_FN_TYPE are errors, not warnings). The ONLY files
#      allowed to FAIL are the deliberate `src/neg/*` EXPECT_COMPILE_ERROR
#      fixtures — any FAIL outside `src\neg\` fails the gate.
#      Lesson driving this step (commit 4019173): the package gate without
#      strict-effects does not catch effect bombs that only detonate in a
#      consumer CU built with `--strict-effects` (flagship precedent:
#      background/log default sink, E_UNDECLARED_TRANSITIVE_EFFECT).
#   2. `nova test src` — the full package test suite (C-codegen pipeline).
#
# Prerequisites (see README "Building standalone"): `nova` on PATH or $env:NOVA,
# NOVA_STD_PATH, NOVA_CG_INCLUDE, NOVA_RT_DIR pointing at a Nova checkout.
# Optional: -TestTimeout <sec> is passed through to `nova test` (`--timeout`)
# for the live-socket tests (servernet/rt, ws/rt) under load.

param(
    [int]$TestTimeout = 0
)

$ErrorActionPreference = "Stop"
$nova = if ($env:NOVA) { $env:NOVA } else { "nova" }

foreach ($v in @("NOVA_STD_PATH", "NOVA_CG_INCLUDE", "NOVA_RT_DIR")) {
    if (-not (Get-Item "env:$v" -ErrorAction SilentlyContinue)) {
        Write-Host "gate: env var $v is not set (see README 'Building standalone')" -ForegroundColor Red
        exit 1
    }
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    # ── step 1: strict-effects check ────────────────────────────────────────
    Write-Host "gate step 1/2: nova check src --strict-effects" -ForegroundColor Cyan
    # NB: stderr merged via `cmd /c` — a bare `2>&1` on a native exe in
    # Windows PowerShell 5.1 wraps every stderr line in a NativeCommandError
    # record and (under $ErrorActionPreference = "Stop") aborts on the first
    # compiler *warning*.
    $checkOut = cmd /c "`"$nova`" check src --strict-effects 2>&1" | Out-String
    # Strip ANSI color codes before parsing.
    $plain = $checkOut -replace "`e\[[0-9;]*m", ""
    $failLines = $plain -split "`r?`n" | Where-Object { $_ -match "^FAIL:\s+(.+)$" } |
        ForEach-Object { ($_ -replace "^FAIL:\s+", "").Trim() }
    $unexpected = @($failLines | Where-Object { $_ -notmatch "^src[\\/]neg[\\/]" })
    if ($unexpected.Count -gt 0) {
        Write-Host "gate: strict-effects FAIL outside src/neg:" -ForegroundColor Red
        $unexpected | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        # Show the error detail for the offending files.
        ($plain -split "`r?`n" | Where-Object { $_ -match "error:" }) | Select-Object -First 20 |
            ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    if ($failLines.Count -eq 0 -and $plain -notmatch "PASS:") {
        Write-Host "gate: could not parse nova check output" -ForegroundColor Red
        Write-Host $plain
        exit 1
    }
    Write-Host ("gate: strict check clean (expected neg/* FAILs: {0})" -f $failLines.Count) -ForegroundColor Green

    # ── step 2: full test suite ─────────────────────────────────────────────
    Write-Host "gate step 2/2: nova test src" -ForegroundColor Cyan
    if ($TestTimeout -gt 0) {
        & $nova test src --timeout $TestTimeout
    } else {
        & $nova test src
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "gate: nova test src failed" -ForegroundColor Red
        exit 1
    }
    Write-Host "gate: GREEN (strict check + full tests)" -ForegroundColor Green
} finally {
    Pop-Location
}
