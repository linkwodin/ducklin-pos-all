# Load Visual Studio C++ build tools into the current PowerShell session.
# Fixes wrong cvtres.exe on PATH (common cause of LNK1123 / CVT1103).

function Import-VisualStudioDevEnvironment {
    if ($env:POS_VS_DEVENV_LOADED -eq '1') {
        return $true
    }

    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $installPath = $null

    if (Test-Path $vswhere) {
        $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    }

    $devCmdCandidates = @()
    if ($installPath) {
        $devCmdCandidates += Join-Path $installPath 'Common7\Tools\VsDevCmd.bat'
        $devCmdCandidates += Join-Path $installPath 'VC\Auxiliary\Build\vcvars64.bat'
    }
    $devCmdCandidates += @(
        'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat',
        'C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
    )

    $devCmd = $devCmdCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $devCmd) {
        Write-Warning 'Visual Studio Dev Command Prompt not found. Install VS 2022 with Desktop development with C++.'
        return $false
    }

    Write-Host "[INFO] Loading VS environment: $devCmd" -ForegroundColor Green

    $envDump = cmd /c "`"$devCmd`" -no_logo -arch=amd64 -host_arch=amd64 >nul 2>&1 && set"
    foreach ($line in $envDump) {
        $eq = $line.IndexOf('=')
        if ($eq -le 0) { continue }
        $name = $line.Substring(0, $eq)
        $value = $line.Substring($eq + 1)
        Set-Item -Path "Env:$name" -Value $value
    }

    # Prefer MSVC cvtres over older .NET Framework copies (LNK1123).
    $msvcBin = $null
    if ($env:VCINSTALLDIR) {
        $candidate = Join-Path $env:VCINSTALLDIR 'bin\Hostx64\x64'
        if (Test-Path (Join-Path $candidate 'cvtres.exe')) {
            $msvcBin = $candidate
        }
    }
    if ($msvcBin) {
        $env:PATH = "$msvcBin;$env:PATH"
        Write-Host "[INFO] Prepended MSVC tools: $msvcBin" -ForegroundColor Green
    }

    $env:POS_VS_DEVENV_LOADED = '1'
    return $true
}

if ($MyInvocation.InvocationName -ne '.') {
    Import-VisualStudioDevEnvironment | Out-Null
}
