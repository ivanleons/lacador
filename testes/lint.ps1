param([string[]]$Arquivos)
# Checa a sintaxe e procura construções que só existem no PowerShell 7 (o alvo é o Windows PowerShell 5.1).
$falhou = $false
foreach ($a in $Arquivos) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $a), [ref]$t, [ref]$e)
    if ($e.Count) { $falhou = $true; $e | ForEach-Object { '{0}:{1}: ERRO DE SINTAXE: {2}' -f $a, $_.Extent.StartLineNumber, $_.Message } }
    $novos = $ast.FindAll({ param($n) $n.GetType().Name -in 'TernaryExpressionAst', 'PipelineChainAst' }, $true)
    foreach ($n in $novos) { $falhou = $true; '{0}:{1}: SO NO PS7: {2}' -f $a, $n.Extent.StartLineNumber, $n.GetType().Name }
    foreach ($tok in $t) {
        if ($tok.Kind.ToString() -in 'QuestionQuestion', 'QuestionQuestionEquals', 'QuestionDot', 'QuestionLBracket', 'AndAnd', 'OrOr') { $falhou = $true; '{0}:{1}: SO NO PS7: operador {2}' -f $a, $tok.Extent.StartLineNumber, $tok.Text }
    }
    # Comandos/parametros que nao existem no 5.1
    $cmds = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $cmds) {
        $nome = $c.GetCommandName()
        $txt = $c.Extent.Text
        if ($nome -eq 'Join-Path' -and @($c.CommandElements | Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] }).Count -gt 3 -and $txt -notmatch '-(ChildPath|Path|Resolve|AdditionalChildPath)') { $falhou = $true; '{0}:{1}: Join-Path com 3+ partes (nao funciona no 5.1)' -f $a, $c.Extent.StartLineNumber }
        if ($nome -eq 'ConvertFrom-Json' -and $txt -match '-AsHashtable|-Depth|-NoEnumerate') { $falhou = $true; '{0}:{1}: ConvertFrom-Json com parametro do PS7' -f $a, $c.Extent.StartLineNumber }
        if ($nome -in 'Test-Json', 'Get-Error', 'Remove-Service', 'ForEach-Object' -and $txt -match '-Parallel|^Test-Json|^Get-Error|^Remove-Service') { $falhou = $true; '{0}:{1}: comando/parametro do PS7: {2}' -f $a, $c.Extent.StartLineNumber, $nome }
    }
    if (-not $falhou) { '{0}: OK ({1} linhas)' -f (Split-Path $a -Leaf), $ast.Extent.EndLineNumber }
}
if ($falhou) { exit 1 }
