param(
    [string]$EfinityHome = 'C:\Efinity\2026.1',
    [ValidateSet('all','interface','map','pnr','pgm')][string]$Stage = 'all'
)
$ErrorActionPreference = 'Stop'
$runner = Join-Path $EfinityHome 'bin\efx_run.bat'
if (!(Test-Path -LiteralPath $runner)) { throw "Efinity not found: $runner" }
$projectRoot = $PSScriptRoot
$src = Join-Path $projectRoot 'src'
$logs = Join-Path $projectRoot 'reports'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$stages = if ($Stage -eq 'all') { @('interface','map','pnr','pgm') } else { @($Stage) }
Push-Location $src
try {
    foreach ($flow in $stages) {
        Write-Host "=== Efinity $flow ==="
        & $runner ti60f225_oob.xml --flow $flow 2>&1 | Tee-Object -FilePath (Join-Path $logs "$flow.log")
        if ($LASTEXITCODE -ne 0) { throw "Efinity $flow failed: $LASTEXITCODE" }
        if ($flow -eq 'pnr') {
            $timing = Get-Content -Raw -LiteralPath 'outflow\ti60f225_oob.timing.rpt'
            $relationships = [regex]::Match($timing,'(?s)Setup \(Max\) Clock Relationship(.*?)Clock Relationship Summary \(end\)').Value
            $rows = [regex]::Matches($relationships,'(?m)^\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\(')
            if ($rows.Count -eq 0) { throw 'No timing relationships found; inspect the timing report.' }
            foreach ($row in $rows) {
                if ([double]::Parse($row.Groups[2].Value,[cultureinfo]::InvariantCulture) -lt 0) {
                    throw "Timing violation: $($row.Value)"
                }
            }
            $route = Get-Content -Raw -LiteralPath 'outflow\ti60f225_oob.route.out'
            if ($route -match 'CombinationalLoopDetected') { throw 'Routing detected a combinational loop; inspect route.out.' }
        }
        if ($flow -eq 'interface') {
            # Keep the interface-generated I/O constraints and PLL clock periods.
            # Unspecified external clocks are declared explicitly below.
            $sdc = Get-Content -LiteralPath 'outflow\ti60f225_oob.pt.sdc' | Where-Object { $_ -notmatch '<USER_PERIOD>' }
            $sdc += '# Board reference input and unrelated clock-domain groups.'
            $sdc += 'create_clock -period 40.000 -name CLK_25M [get_ports {CLK_25M}]'
            $sdc += 'set_clock_groups -asynchronous -group {core_clk} -group {hdmi_tx_slow_clk} -group {hdmi_rx_slow_clk} -group {CLK_25M} -group {sdram_clk tx_cal_clk rx_cal_clk tx_cal_clk_90edge}'
            [IO.File]::WriteAllLines((Join-Path $src 'ti60f225_oob.sdc'),$sdc,[Text.UTF8Encoding]::new($false))
        }
    }
    if ($stages -contains 'pgm') {
        $firmware = Join-Path $projectRoot 'firmware\drink4_26frames_20261103'
        New-Item -ItemType Directory -Force -Path $firmware | Out-Null
        foreach ($ext in @('bit','hex')) {
            $file = Join-Path $src "outflow\ti60f225_oob.$ext"
            if (!(Test-Path -LiteralPath $file)) { throw "Missing generated firmware: $file" }
            Copy-Item -LiteralPath $file -Destination (Join-Path $firmware "hdmi_drink4_26frames_20261103.$ext")
        }
        Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $firmware 'hdmi_drink4_26frames_20261103.bit'),(Join-Path $firmware 'hdmi_drink4_26frames_20261103.hex') |
          ForEach-Object { "$($_.Hash.ToLower())  $([IO.Path]::GetFileName($_.Path))" } |
          Set-Content -Encoding ascii -LiteralPath (Join-Path $firmware 'SHA256SUMS.txt')
    }
} finally { Pop-Location }
# This script only builds. It never invokes a programmer or opens JTAG.
