$ErrorActionPreference='Stop'
$csc='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $csc)) { throw "C# compiler not found: $csc" }
Push-Location $PSScriptRoot
try {
  & $csc /nologo /codepage:65001 /target:winexe /out:EdgeVisionControl.exe /reference:System.Drawing.dll /reference:System.Windows.Forms.dll BoardProtocol.cs EdgeVisionControl.cs
  if ($LASTEXITCODE -ne 0) { throw 'UI compilation failed' }
} finally { Pop-Location }
