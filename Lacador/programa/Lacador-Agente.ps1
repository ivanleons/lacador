<#
===============================================================================
  LAÇADOR - Agente (parte que instala e repara, com privilégio de administrador)
===============================================================================
  Quem chama:
   -Fila      a tarefa agendada "Lacador-Agente" (conta SYSTEM), criada pelo
              Instalar-Lacador.ps1. Atende os pedidos que a tela grava em
              C:\ProgramData\Lacador\pedidos. É o modo dos computadores da base,
              onde o usuário não é administrador.
   -Pedido    a própria tela, pela janela de administrador do Windows (UAC).
              É o modo portátil (pendrive, computador pessoal).
   -Preparar  sem tela (GPO, linha de comando): deixa prontos os sistemas
   -Itens     informados, ou instala/repara itens específicos.

  Segurança: o agente só aceita itens que existem no catálogo, nunca recebe
  caminhos nem comandos do usuário, e confere o SHA-256 de cada instalador
  contra o catálogo antes de executar.

  Exemplos (PowerShell como administrador):
    .\Lacador-Agente.ps1 -Preparar sigadaer -Token gd-starsign
    .\Lacador-Agente.ps1 -Preparar sigadaer,siafi -Token todos
    .\Lacador-Agente.ps1 -Itens assinador            (reinstala ou repara o assinador)
    .\Lacador-Agente.ps1 -Preparar sigadaer -SomenteReparar   (só conserta o que já existe)
    Acrescente -Simular para ver o que seria feito, sem instalar nada.
===============================================================================
#>
param(
    [switch]$Fila,
    [string]$Pedido,
    [string[]]$Preparar,
    [string[]]$Itens,
    [string]$Token = '',
    [switch]$SomenteReparar,
    [switch]$Simular,
    [string]$Recipiente = ''
)

$ErrorActionPreference = 'Stop'
# A tela informa onde está o Lacador.exe (com os instaladores dentro) quando chama pela janela de administrador.
if ($Recipiente -and (Test-Path -LiteralPath $Recipiente -PathType Leaf)) { $env:LACADOR_EXE = $Recipiente }
Import-Module (Join-Path $PSScriptRoot 'Lacador.Motor.psm1') -Force

$script:ArquivoLog = $null
function Write-Agente {
    param([string]$Texto)
    $linha = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Texto
    Write-Host $linha
    if ($script:ArquivoLog) {
        try {
            if ((Test-Path -LiteralPath $script:ArquivoLog) -and ((Get-Item -LiteralPath $script:ArquivoLog).Length -gt 2MB)) {
                Move-Item -LiteralPath $script:ArquivoLog -Destination ($script:ArquivoLog + '.antigo') -Force
            }
            Add-Content -LiteralPath $script:ArquivoLog -Value $linha -Encoding UTF8
        } catch { }
    }
}

function Test-PastaSegura {
    # A pasta precisa ser de verdade (não um atalho/junção) e pertencer ao SYSTEM ou aos Administradores.
    param([string]$Pasta)
    try {
        $it = Get-Item -LiteralPath $Pasta -Force
        if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        $dono = (Get-Acl -LiteralPath $Pasta).GetOwner([Security.Principal.SecurityIdentifier]).Value
        return ($dono -eq 'S-1-5-18' -or $dono -eq 'S-1-5-32-544')
    } catch { return $false }
}

function Read-Pedido {
    # Lê e valida um arquivo de pedido. Devolve o pedido ou lança o motivo da recusa.
    param([string]$Arquivo, $Catalogo)
    $it = Get-Item -LiteralPath $Arquivo -Force
    if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'arquivo de pedido inválido' }
    if ($it.Length -gt 8192) { throw 'pedido grande demais' }
    $p = Read-LacadorJson $Arquivo
    $motivo = Test-LacadorPedido $p $Catalogo
    if ($motivo) { throw $motivo }
    if (('{0}.json' -f $p.id) -ne $it.Name) { throw 'o nome do arquivo não confere com o pedido' }
    return $p
}

$admin = $false
try { $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { }
if (-not $admin -and -not $Simular) {
    Write-Host 'O agente do Laçador precisa rodar como administrador.'
    exit 2
}

$dados = Get-LacadorPastaDados
try {
    # Garante que a pasta de dados pertence aos Administradores (ninguém a preparou antes com outra intenção).
    if ($admin -and (Test-LacadorWindows) -and -not $Fila) { $null = Initialize-LacadorPastaDados }
    $pastaLogs = Join-Path $dados 'logs'
    if (-not (Test-Path -LiteralPath $pastaLogs)) { New-Item -ItemType Directory -Path $pastaLogs -Force | Out-Null }
    $script:ArquivoLog = Join-Path $pastaLogs 'agente.log'
} catch { $script:ArquivoLog = $null }

# Um agente por vez: dois instaladores ao mesmo tempo dão problema.
$mutex = $null
$meu = $false
try {
    $mutex = New-Object System.Threading.Mutex($false, 'Global\LacadorAgente')
    try { $meu = $mutex.WaitOne([TimeSpan]::FromMinutes(40)) } catch [System.Threading.AbandonedMutexException] { $meu = $true }
} catch { $meu = $true }
if (-not $meu) { Write-Agente 'Outro agente ainda está trabalhando. Saindo.'; exit 1 }

$codigo = 0
try {
    $cat = Get-LacadorCatalogo
    $registrar = { param($t) Write-Agente $t }
    $contaAtual = ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME)

    if ($Fila) {
        Write-Agente ('=== Agente {0} (fila) em {1} como {2} ===' -f (Get-LacadorVersao), $env:COMPUTERNAME, $contaAtual)
        $pedidos = Join-Path $dados 'pedidos'
        $respostas = Join-Path $dados 'respostas'
        foreach ($p in $pedidos, $respostas) {
            if (-not (Test-Path -LiteralPath $p)) { throw ('Pasta ausente: {0}. Rode o Instalar-Lacador.ps1 de novo.' -f $p) }
            if (-not $Simular -and -not (Test-PastaSegura $p)) { throw ('A pasta {0} não é segura (dono ou tipo inesperado). Rode o Instalar-Lacador.ps1 de novo.' -f $p) }
        }
        # Limpa respostas antigas
        Get-ChildItem -LiteralPath $respostas -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force -ErrorAction SilentlyContinue
        $rodadas = 0
        while ($rodadas -lt 40) {
            $rodadas++
            $arqs = @(Get-ChildItem -LiteralPath $pedidos -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
            if (-not $arqs.Count) { break }
            foreach ($a in $arqs) {
                $resp = $null
                try {
                    if ($a.Name -notmatch '^[0-9a-f]{32}\.json$') { throw 'nome de arquivo inválido' }
                    $resp = Join-Path $respostas $a.Name
                    $ped = Read-Pedido $a.FullName $cat
                    Write-Agente ('Pedido {0}: {1} [{2}] (de {3})' -f $ped.id, $ped.acao, (@($ped.itens) -join ', '), $ped.usuario)
                    $r = Invoke-LacadorPedido -Pedido $ped -ArquivoResposta $resp -Simular:$Simular -Registrar $registrar
                    Write-Agente ('Pedido {0}: {1}' -f $ped.id, $r.estado)
                    if ($r.estado -ne 'concluido') { $codigo = 1 }
                } catch {
                    $codigo = 1
                    Write-Agente ('Pedido recusado ({0}): {1}' -f $a.Name, $_.Exception.Message)
                    if ($resp) {
                        try { Write-LacadorJson $resp ([ordered]@{ id = $a.BaseName; estado = 'recusado'; mensagem = [string]$_.Exception.Message; passos = @(); fim = (Get-Date).ToString('s') }) } catch { }
                    }
                } finally {
                    Remove-Item -LiteralPath $a.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    elseif ($Pedido) {
        Write-Agente ('=== Agente {0} (pedido da tela) em {1} como {2} ===' -f (Get-LacadorVersao), $env:COMPUTERNAME, $contaAtual)
        $arq = (Resolve-Path -LiteralPath $Pedido).ProviderPath
        $ped = Read-Pedido $arq $cat
        $resp = Join-Path (Split-Path -Parent $arq) ('{0}.resposta.json' -f $ped.id)
        Write-Agente ('Pedido {0}: {1} [{2}]' -f $ped.id, $ped.acao, (@($ped.itens) -join ', '))
        $r = Invoke-LacadorPedido -Pedido $ped -ArquivoResposta $resp -Simular:$Simular -Registrar $registrar
        Write-Agente ('Pedido {0}: {1}' -f $ped.id, $r.estado)
        if ($r.estado -ne 'concluido') { $codigo = 1 }
        Remove-Item -LiteralPath $arq -Force -ErrorAction SilentlyContinue
    }
    elseif ($Preparar -or $Itens) {
        Write-Agente ('=== Agente {0} (sem tela) em {1} como {2} ===' -f (Get-LacadorVersao), $env:COMPUTERNAME, $contaAtual)
        # Aceita tanto -Preparar a,b quanto -Preparar "a,b" (como chega de um .cmd)
        $sis = @($Preparar | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $its = @($Itens | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $validosS = @($cat.sistemas | ForEach-Object { [string]$_.id })
        foreach ($s in $sis) { if ($validosS -notcontains $s) { throw ('Sistema fora do catálogo: {0}. Válidos: {1}' -f $s, ($validosS -join ', ')) } }
        if ($Token -and $Token -ne 'todos' -and (@($cat.tokens | ForEach-Object { [string]$_.id }) -notcontains $Token)) {
            throw ('Token fora do catálogo: {0}. Válidos: {1}, todos' -f $Token, (@($cat.tokens | ForEach-Object { $_.id }) -join ', '))
        }
        $estado = Get-LacadorEstado
        $plano = @(Resolve-LacadorPlano -Catalogo $cat -Itens $its -Sistemas $sis -Token $Token -Estado $estado)
        $fazer = New-Object System.Collections.Generic.List[string]
        foreach ($id in $plano) {
            $e = $estado.itens[$id]
            $pedidoDireto = ($its -contains $id)
            if ($e.estado -eq 'ok' -and -not $pedidoDireto) { Write-Agente ('{0}: já está em ordem' -f $id); continue }
            if ($e.estado -eq 'conflito') { Write-Agente ('{0}: {1}' -f $id, $e.detalhe); $codigo = 1; continue }
            if ($SomenteReparar -and $e.estado -eq 'ausente') { Write-Agente ('{0}: não instalado (modo somente reparo, nada a fazer)' -f $id); continue }
            if ($e.pacotesFaltando.Count -and ($e.estado -eq 'ausente' -or $e.acao -eq 'instalar')) { Write-Agente ('{0}: instalador não encontrado ({1})' -f $id, ($e.pacotesFaltando -join ', ')); $codigo = 1; continue }
            $fazer.Add($id)
        }
        if (-not $fazer.Count) {
            Write-Agente 'Nada a fazer.'
        } else {
            $ped = [pscustomobject]@{ id = [guid]::NewGuid().ToString('N'); acao = 'instalar'; itens = $fazer.ToArray(); usuario = $contaAtual }
            $resp = $null
            try {
                $pr = Join-Path $dados 'respostas'
                if (-not (Test-Path -LiteralPath $pr)) { New-Item -ItemType Directory -Path $pr -Force | Out-Null }
                $resp = Join-Path $pr 'ultimo-preparo.json'
            } catch { $resp = $null }
            Write-Agente ('Itens: {0}' -f ($fazer -join ', '))
            $r = Invoke-LacadorPedido -Pedido $ped -ArquivoResposta $resp -Simular:$Simular -Registrar $registrar
            foreach ($p in $r.passos) { Write-Agente ('  {0,-18} {1}' -f $p.item, $p.estado.ToUpperInvariant()) }
            if ($r.reiniciar) { Write-Agente 'Um dos instaladores pediu para reiniciar o computador.' }
            if ($r.estado -ne 'concluido') { $codigo = 1 }
        }
    }
    else {
        Write-Host 'Uso: Lacador-Agente.ps1 -Preparar <sistemas> [-Token <modelo|todos>] | -Itens <itens> [-SomenteReparar] [-Simular]'
        Write-Host ('Sistemas: {0}' -f (@($cat.sistemas | ForEach-Object { $_.id }) -join ', '))
        Write-Host ('Itens:    {0}' -f (@($cat.itens | ForEach-Object { $_.id }) -join ', '))
        Write-Host ('Tokens:   {0}, todos' -f (@($cat.tokens | ForEach-Object { $_.id }) -join ', '))
        $codigo = 2
    }
} catch {
    $codigo = 1
    Write-Agente ('ERRO: {0}' -f $_.Exception.Message)
} finally {
    if ($mutex) { try { $mutex.ReleaseMutex() } catch { }; $mutex.Dispose() }
}
exit $codigo
