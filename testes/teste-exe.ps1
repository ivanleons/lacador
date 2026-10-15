# Confere o Lacador.exe pronto: o motor acha os instaladores lá dentro e cada cópia bate com o SHA-256 do catálogo.
param([string]$Exe)
$ErrorActionPreference = 'Stop'
$env:LACADOR_EXE = $Exe
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Lacador/programa/Lacador.Motor.psm1') -Force
$cat = Get-LacadorCatalogo; $cfg = Get-LacadorConfig
$ind = Get-LacadorIndiceRecipiente
'instaladores dentro do executável: {0}' -f $ind.Count
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('lacador-exe-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $tmp | Out-Null
$falhas = 0; $n = 0
foreach ($it in $cat.itens) {
    foreach ($p in @($it.pacotes)) {
        if (-not $p) { continue }
        $n++
        $o = Get-LacadorOrigemPacote ([string]$p.arquivo) $cfg
        $alvo = Join-Path $tmp ([string]$p.arquivo)
        Copy-LacadorPacote ([string]$p.arquivo) $alvo $cfg
        $ok = ($o.origem -eq 'executavel') -and ([long]$o.tamanho -eq [long]$p.tamanho) -and (Test-LacadorHash $alvo ([string]$p.sha256))
        if (-not $ok) { $falhas++ }
        '  {0,-46} {1}' -f $p.arquivo, $(if ($ok) { 'confere' } else { 'DIFERENTE' })
        Remove-Item -LiteralPath $alvo -Force
    }
}
Remove-Item -Recurse -Force $tmp
# O estado que a tela mostraria (a leitura do Windows falha fora do Windows, mas a parte dos instaladores vale)
$e = Get-LacadorEstado
'tela: instaladores no executável = {0}; presentes e do tamanho certo = {1} de {2}' -f $e.pacotesNoExecutavel, @($e.pacotes | Where-Object { $_.ok }).Count, @($e.pacotes).Count
if ($falhas) { "$falhas de $n FALHARAM"; exit 1 }
"Todos os $n instaladores conferem"
