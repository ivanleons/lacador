# Gera, com o motor de verdade, o estado da tela para cada combinação de itens "instalados" na demonstração.
param([string]$Programa, [string]$Saida)
Import-Module (Join-Path $Programa 'Lacador.Motor.psm1') -Force
$cat = Get-LacadorCatalogo
$cfg = Get-LacadorConfig
$base = [IO.File]::ReadAllText((Join-Path $Programa 'demonstracao.json'), [Text.Encoding]::UTF8)
$ordem = @('assinador', 'java8', 'dxsafe', 'java7', 'adobe-xi', 'ajuste-dexon', 'acesso')
$partes = New-Object System.Collections.Generic.List[string]
for ($m = 0; $m -lt [Math]::Pow(2, $ordem.Count); $m++) {
    $ok = @()
    for ($b = 0; $b -lt $ordem.Count; $b++) { if ($m -band (1 -shl $b)) { $ok += $ordem[$b] } }
    $o = $base | ConvertFrom-Json
    $o.coletadoEm = (Get-Date).ToString('s')
    foreach ($c in @($o.certificados)) {
        if ($c -and $null -ne $c.demoDias) {
            $fim = (Get-Date).AddDays([int]$c.demoDias)
            $c.fim = $fim.ToString('s'); $c.inicio = $fim.AddYears(-3).ToString('s')
        }
    }
    $o | Add-Member -NotePropertyName 'simulacao' -NotePropertyValue ([pscustomobject]@{ ok = @($ok) }) -Force
    $fatos = (ConvertTo-Json -InputObject $o -Depth 12 -Compress) | ConvertFrom-Json
    $estado = ConvertTo-LacadorEstado $fatos $cat $cfg
    $partes.Add(('{0}:{1}' -f (ConvertTo-Json ($ok -join ',')), (ConvertTo-Json -InputObject $estado -Depth 12 -Compress)))
}
[IO.File]::WriteAllText($Saida, ('{' + ($partes -join ',') + '}'), (New-Object System.Text.UTF8Encoding($false)))
'{0} estados gravados' -f $partes.Count
