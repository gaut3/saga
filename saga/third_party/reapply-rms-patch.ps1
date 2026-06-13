<#
.SYNOPSIS
Re-applies the Saga RMS patch to a freshly vendored just_audio package.

.DESCRIPTION
The vendored fork at third_party/just_audio carries the real-loudness tap
(TeeAudioProcessor prepended to the audio sink's processor chain, RMS emitted
on the com.ryanheise.just_audio.rms EventChannel, audio offload disabled).
On a just_audio version bump:

  1. Delete third_party/just_audio and extract the new vanilla package there
     (https://pub.dev/api/archives/just_audio-VERSION.tar.gz).
  2. Run this script. It applies third_party/just_audio.patch and then greps
     for the structural markers the patch must leave behind.
  3. Fix any rejects by hand (the patch was generated against 0.9.46; a new
     Media3 version may move the context), re-run with -VerifyOnly, build,
     and confirm the Reactive mark still moves with audio.

The tee must stay PREPENDED before Sonic (the speed/pitch processor) so RMS
reflects original-tempo loudness, and audio offload must stay DISABLED or the
tap gets no PCM. See SAGA_NOTES.md / CLAUDE.md.

NOTE: keep this file pure ASCII. Windows PowerShell 5.1 reads BOM-less files
as ANSI, and UTF-8 punctuation decodes into curly quotes that break parsing.
#>
param(
    [string]$TargetDir = (Join-Path $PSScriptRoot 'just_audio'),
    [string]$PatchFile = (Join-Path $PSScriptRoot 'just_audio.patch'),
    # Skip applying (verify markers only), e.g. after fixing rejects by hand.
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $TargetDir)) { throw "Target not found: $TargetDir" }
if (-not (Test-Path $PatchFile)) { throw "Patch not found: $PatchFile" }

if (-not $VerifyOnly) {
    Write-Host "Applying $PatchFile to $TargetDir ..."
    Push-Location $TargetDir
    try {
        # autocrlf off: the patch and the package sources are LF.
        git -c core.autocrlf=false apply --check -p1 $PatchFile
        if ($LASTEXITCODE -ne 0) {
            throw ("Patch does not apply cleanly. Apply by hand " +
                "(git apply -p1 --reject), fix the .rej hunks, then re-run " +
                "with -VerifyOnly.")
        }
        git -c core.autocrlf=false apply -p1 $PatchFile
        if ($LASTEXITCODE -ne 0) { throw 'git apply failed.' }
        Write-Host 'Patch applied.'
    } finally {
        Pop-Location
    }
}

# Structural verification: greps for what the patch must have produced.
# (Do not count on one "// Saga" comment per patch spot; only 3 comment
# blocks exist. The strings below are the load-bearing code.)
$javaDir = Join-Path $TargetDir 'android\src\main\java\com\ryanheise\just_audio'
$checks = @(
    @{ File = 'AudioPlayer.java';     Pattern = 'RmsAudioBufferSink';            Why = 'RMS sink class' },
    @{ File = 'AudioPlayer.java';     Pattern = 'TeeAudioProcessor';             Why = 'tee prepended to processor chain' },
    @{ File = 'AudioPlayer.java';     Pattern = 'AUDIO_OFFLOAD_MODE_DISABLED';   Why = 'offload disabled (tap needs PCM)' },
    @{ File = 'AudioPlayer.java';     Pattern = '// Saga';                       Why = 'patch comment markers' },
    @{ File = 'JustAudioPlugin.java'; Pattern = 'com\.ryanheise\.just_audio\.rms'; Why = 'global RMS EventChannel' },
    @{ File = 'JustAudioPlugin.java'; Pattern = '// Saga';                       Why = 'patch comment marker' }
)

$failed = 0
Write-Host ""
Write-Host "Verification:"
foreach ($c in $checks) {
    $path = Join-Path $javaDir $c.File
    $hit = (Test-Path $path) -and
           (Select-String -Path $path -Pattern $c.Pattern -Quiet)
    if ($hit) { $status = 'PASS' } else { $failed++; $status = 'FAIL' }
    Write-Host ("  [{0}] {1}: {2} ({3})" -f $status, $c.File, $c.Pattern, $c.Why)
}

if ($failed -gt 0) {
    Write-Error "$failed verification check(s) failed - the RMS patch is incomplete."
    exit 1
}
Write-Host ""
Write-Host "All checks passed. Build and confirm the Reactive mark moves with audio."
