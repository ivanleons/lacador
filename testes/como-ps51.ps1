# Roda o Lacador.ps1 imitando uma diferença do Windows PowerShell 5.1 que o PowerShell 7 esconde:
# no 5.1, "ConvertTo-Json -InputObject $null" não devolve NADA (no 7 devolve o texto null).
# Uso: pwsh testes/como-ps51.ps1 -Demo -SemJanela -Porta 47800
function global:ConvertTo-Json {
    [CmdletBinding()]
    param([Parameter(Position = 0, ValueFromPipeline = $true)][AllowNull()]$InputObject, [int]$Depth = 2, [switch]$Compress)
    process {
        if ($null -eq $InputObject) { return }
        Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress:$Compress
    }
}
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Lacador/programa/Lacador.ps1') @args
