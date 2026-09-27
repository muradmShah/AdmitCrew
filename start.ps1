$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Test-Path -LiteralPath '.venv\Scripts\python.exe')) {
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw 'Python virtual environment could not be created.' }
}
& '.\.venv\Scripts\python.exe' -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
if (-not (Test-Path -LiteralPath 'output\pdf\passport-a.pdf')) {
    & '.\.venv\Scripts\python.exe' scripts/create_samples.py
    if ($LASTEXITCODE -ne 0) { throw 'Training document generation failed.' }
}
Write-Host 'Open http://127.0.0.1:8765 in your browser. Press Ctrl+C to stop.'
& '.\.venv\Scripts\python.exe' app.py
