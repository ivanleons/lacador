<#
===============================================================================
  LAÇADOR - Sistema de Gerenciamento de Tokens (tela do usuário)
===============================================================================
  Abre a janela do Laçador. Roda como o próprio usuário, sem administrador.
  A tela é uma página local servida só para este computador (127.0.0.1) e
  aberta numa janela própria do Edge ou do Chrome.

  Quando o usuário manda instalar ou reparar, a tela entrega o pedido ao agente:
   - pela tarefa "Lacador-Agente", se o Laçador foi instalado no computador; ou
   - pela janela de administrador do Windows (UAC), no modo portátil.

  Parâmetros:
    -Demo           modo demonstração: usa dados de exemplo e não instala nada
    -Cenario <arq>  demonstração com um arquivo de fatos específico (testes)
    -Porta <n>      porta fixa (padrão: uma porta livre qualquer)
    -SemJanela      não abre o navegador; só escreve o endereço (testes)
  Criado por 3S Leon, S2 Dalssasso - ATIC - Base Aérea de Canoas
===============================================================================
#>
param(
    [switch]$Demo,
    [string]$Cenario,
    [int]$Porta = 0,
    [switch]$SemJanela
)

$ErrorActionPreference = 'Stop'
$script:Modulo = Join-Path $PSScriptRoot 'Lacador.Motor.psm1'
Import-Module $script:Modulo -Force

$script:PastaUsuario = Get-LacadorPastaUsuario
$script:ArquivoLog = Join-Path $script:PastaUsuario 'lacador.log'
$script:PastaInterface = Join-Path $PSScriptRoot 'interface'
$script:Sync = [hashtable]::Synchronized(@{ fase = 'verificando'; percentual = 0; etapa = 'Carregando o sistema...'; estadoJson = $null; erro = $null; rodada = 0 })
$script:Varredura = $null
$script:Acao = $null
$script:Acesso = $null
$script:Tarefas = New-Object System.Collections.ArrayList
$script:SimJson = $null
$script:SimOk = New-Object System.Collections.Generic.List[string]
$script:Rodando = $true
$script:UltimoContato = $null
$script:Inicio = Get-Date
$script:ProcJanela = $null
$script:Saindo = $null

# Tela de abertura do Lacador.exe (lancador/abertura.c): ela fica na tela até a janela do programa estar pronta.
# O lançador passa o nome de um evento do Windows (avisar que pode sumir) e um arquivo (o andamento para mostrar).
$script:AberturaEvento = [string]$env:LACADOR_ABERTURA
$script:AberturaArq = [string]$env:LACADOR_ABERTURA_ARQ
$script:AberturaUltimo = ''
$script:AberturaFechada = $false
$script:AberturaEm = Get-Date
$script:JanelaAbertaEm = $null
foreach ($v in 'LACADOR_ABERTURA', 'LACADOR_ABERTURA_ARQ') { Remove-Item -LiteralPath ('Env:' + $v) -ErrorAction SilentlyContinue }
if ($SemJanela) { $script:AberturaEvento = ''; $script:AberturaArq = '' }

function Write-Ui {
    param([string]$Texto)
    try {
        if ((Test-Path -LiteralPath $script:ArquivoLog) -and ((Get-Item -LiteralPath $script:ArquivoLog).Length -gt 1MB)) {
            Move-Item -LiteralPath $script:ArquivoLog -Destination ($script:ArquivoLog + '.antigo') -Force
        }
        Add-Content -LiteralPath $script:ArquivoLog -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Texto) -Encoding UTF8
    } catch { }
}

#region Tela de abertura ----------------------------------------------------------

function Set-Abertura {
    # Conta o andamento para a tela de abertura: "percentual<TAB>fase<TAB>etapa".
    param([int]$Percentual, [string]$Fase, [string]$Etapa)
    if (-not $script:AberturaArq -or $script:AberturaFechada) { return }
    $linha = "{0}`t{1}`t{2}" -f $Percentual, $Fase, $Etapa
    if ($linha -eq $script:AberturaUltimo) { return }
    try {
        [IO.File]::WriteAllText($script:AberturaArq, $linha, (New-Object System.Text.UTF8Encoding($false)))
        $script:AberturaUltimo = $linha
    } catch { }
}

function Close-Abertura {
    # Avisa o lançador que a janela do programa está pronta: a abertura some.
    if ($script:AberturaFechada) { return }
    $script:AberturaFechada = $true
    if (-not $script:AberturaEvento) { return }
    try {
        $ev = [System.Threading.EventWaitHandle]::OpenExisting($script:AberturaEvento)
        [void]$ev.Set()
        $ev.Close()
    } catch { }
}

#endregion

#region Verificação em segundo plano --------------------------------------------

function Get-SimulacaoAtual {
    # Devolve o JSON de fatos simulados já com os itens "instalados" durante a demonstração.
    if (-not $script:SimJson) { return $null }
    $o = $script:SimJson | ConvertFrom-Json
    # Na demonstração, a hora da verificação e as datas dos certificados são sempre relativas a agora.
    $o.coletadoEm = (Get-Date).ToString('s')
    foreach ($c in @($o.certificados)) {
        if ($c -and $null -ne $c.demoDias) {
            $fim = (Get-Date).AddDays([int]$c.demoDias)
            $c.fim = $fim.ToString('s')
            $c.inicio = $fim.AddYears(-3).ToString('s')
        }
    }
    $o | Add-Member -NotePropertyName 'simulacao' -NotePropertyValue ([pscustomobject]@{ ok = @($script:SimOk.ToArray()) }) -Force
    return (ConvertTo-Json -InputObject $o -Depth 12 -Compress)
}

function Start-Verificacao {
    if ($script:Varredura -and -not $script:Varredura.Alca.IsCompleted) { return }
    if ($script:Varredura) { try { $script:Varredura.PS.Dispose() } catch { } }
    $script:Sync['fase'] = 'verificando'
    $script:Sync['percentual'] = 2
    $script:Sync['etapa'] = 'Carregando o sistema...'
    $ps = [powershell]::Create()
    $null = $ps.AddScript({
        param($modulo, $sync, $simulado)
        try {
            Import-Module $modulo -Force
            $cat = Get-LacadorCatalogo
            $cfg = Get-LacadorConfig
            if ($simulado) {
                foreach ($p in @(@(12, 'Lendo o Windows...'), @(30, 'Procurando tokens conectados...'), @(52, 'Lendo os certificados...'), @(72, 'Verificando o Firefox e a extensão...'), @(90, 'Verificando o Java...'))) {
                    $sync['percentual'] = $p[0]; $sync['etapa'] = $p[1]
                    Start-Sleep -Milliseconds 230
                }
                $fatos = $simulado | ConvertFrom-Json
            } else {
                $fatos = Get-LacadorFatos -Catalogo $cat -Config $cfg -Progresso $sync
            }
            $estado = ConvertTo-LacadorEstado $fatos $cat $cfg
            $sync['estadoJson'] = (ConvertTo-Json -InputObject $estado -Depth 12 -Compress)
            $sync['erro'] = $null
        } catch {
            $sync['erro'] = [string]$_.Exception.Message
        } finally {
            $sync['percentual'] = 100
            $sync['rodada'] = [int]$sync['rodada'] + 1
            $sync['fase'] = 'pronto'
        }
    }).AddArgument($script:Modulo).AddArgument($script:Sync).AddArgument((Get-SimulacaoAtual))
    $script:Varredura = @{ PS = $ps; Alca = $ps.BeginInvoke() }
}

function Get-EstadoObjeto {
    if (-not $script:Sync['estadoJson']) { return $null }
    return ([string]$script:Sync['estadoJson'] | ConvertFrom-Json)
}

#endregion

#region Ações (instalar / reparar) -----------------------------------------------

function Add-Historico {
    param($Registro)
    try {
        $linha = ConvertTo-Json -InputObject $Registro -Depth 6 -Compress
        Add-Content -LiteralPath (Join-Path $script:PastaUsuario 'historico.jsonl') -Value $linha -Encoding UTF8
    } catch { }
}

function Get-Historico {
    $arq = Join-Path $script:PastaUsuario 'historico.jsonl'
    $res = New-Object System.Collections.Generic.List[object]
    if (Test-Path -LiteralPath $arq) {
        try {
            $linhas = @([IO.File]::ReadAllLines($arq, [Text.Encoding]::UTF8) | Where-Object { $_ })
            $ini = [Math]::Max(0, $linhas.Count - 40)
            for ($i = $linhas.Count - 1; $i -ge $ini; $i--) {
                try {
                    $reg = $linhas[$i] | ConvertFrom-Json
                    # O que foi feito em modo demonstração só aparece na demonstração.
                    if ([bool]$reg.demonstracao -eq [bool]$script:SimJson) { $res.Add($reg) }
                } catch { }
            }
        } catch { }
    }
    return $res.ToArray()
}

function Start-Acao {
    param($Corpo)
    if ($script:Acao -and $script:Acao.estado -eq 'executando') { return [ordered]@{ ok = $false; mensagem = 'Já existe uma instalação em andamento. Espere terminar.' } }
    $estado = Get-EstadoObjeto
    if (-not $estado) { return [ordered]@{ ok = $false; mensagem = 'A verificação ainda não terminou.' } }
    $cat = Get-LacadorCatalogo
    $acao = [string]$Corpo.acao
    if ($acao -notin 'instalar', 'reparar', 'desinstalar') { return [ordered]@{ ok = $false; mensagem = 'Ação inválida.' } }
    $itens = @($Corpo.itens | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $sistemas = @($Corpo.sistemas | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $token = [string]$Corpo.token
    $idsItens = @($cat.itens | ForEach-Object { [string]$_.id })
    $idsSis = @($cat.sistemas | ForEach-Object { [string]$_.id })
    $idsTok = @($cat.tokens | ForEach-Object { [string]$_.id }) + 'todos'
    foreach ($i in $itens) { if ($idsItens -notcontains $i) { return [ordered]@{ ok = $false; mensagem = 'Item fora do catálogo.' } } }
    foreach ($s in $sistemas) { if ($idsSis -notcontains $s) { return [ordered]@{ ok = $false; mensagem = 'Sistema fora do catálogo.' } } }
    if ($token -and ($idsTok -notcontains $token)) { return [ordered]@{ ok = $false; mensagem = 'Token fora do catálogo.' } }

    $fazer = New-Object System.Collections.Generic.List[string]
    $plano = @()
    if ($acao -eq 'desinstalar') {
        if ($sistemas.Count -or -not $itens.Count) { return [ordered]@{ ok = $false; mensagem = 'Escolha o programa a desinstalar.' } }
        foreach ($i in $itens) {
            $e = Get-LacadorProp $estado.itens $i
            if (-not $e -or -not $e.podeDesinstalar) { return [ordered]@{ ok = $false; mensagem = ('O Laçador não desinstala este item: {0}.' -f $i) } }
            $fazer.Add($i)
        }
    } else {
        $plano = @(Resolve-LacadorPlano -Catalogo $cat -Itens $itens -Sistemas $sistemas -Token $token -Estado $estado)
    }
    foreach ($id in $plano) {
        $e = Get-LacadorProp $estado.itens $id
        if (-not $e) { continue }
        if ($e.estado -eq 'conflito') { return [ordered]@{ ok = $false; mensagem = [string]$e.detalhe } }
        if ($e.estado -eq 'ok' -and ($itens -notcontains $id)) { continue }
        if (@($e.pacotesFaltando).Count -and ($e.estado -eq 'ausente' -or $e.acao -eq 'instalar')) {
            return [ordered]@{ ok = $false; mensagem = ('Instalador não encontrado: {0}' -f (@($e.pacotesFaltando) -join ', ')) }
        }
        $fazer.Add($id)
    }
    if (-not $fazer.Count) { return [ordered]@{ ok = $false; mensagem = 'Nada a fazer: já está tudo em ordem.' } }

    $id = [guid]::NewGuid().ToString('N')
    $pedido = [ordered]@{ id = $id; acao = $acao; itens = $fazer.ToArray(); usuario = ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME); criado = (Get-Date).ToString('s') }
    $nova = @{ id = $id; acao = $acao; itens = $fazer.ToArray(); estado = 'executando'; inicio = (Get-Date); via = ''; resposta = ''; ultimo = $null; processo = $null; mensagem = ''; registrada = $false }

    if ($script:SimJson) {
        # Demonstração: roda o mesmo fluxo, mas sem instalar nada.
        $pastaPed = Join-Path $script:PastaUsuario 'pedidos'
        if (-not (Test-Path -LiteralPath $pastaPed)) { New-Item -ItemType Directory -Path $pastaPed -Force | Out-Null }
        $nova.via = 'demonstracao'
        $nova.resposta = Join-Path $pastaPed ('{0}.resposta.json' -f $id)
        $ps = [powershell]::Create()
        $null = $ps.AddScript({
            param($modulo, $pedidoJson, $arquivo)
            Import-Module $modulo -Force
            $null = Invoke-LacadorPedido -Pedido ($pedidoJson | ConvertFrom-Json) -ArquivoResposta $arquivo -Simular
        }).AddArgument($script:Modulo).AddArgument((ConvertTo-Json -InputObject $pedido -Depth 5 -Compress)).AddArgument($nova.resposta)
        $null = $script:Tarefas.Add(@{ PS = $ps; Alca = $ps.BeginInvoke() })
        $script:Acao = $nova
        return [ordered]@{ ok = $true; id = $id; via = $nova.via }
    }

    $viaAgente = [bool]$estado.agente.tarefa
    if ($viaAgente) {
        try {
            $dados = Get-LacadorPastaDados
            $arq = Join-Path (Join-Path $dados 'pedidos') ('{0}.json' -f $id)
            Write-LacadorJson $arq $pedido
            $null = & schtasks.exe /Run /TN ('\{0}' -f (Get-LacadorNomeTarefa)) 2>&1
            if ($LASTEXITCODE -ne 0) { throw 'a tarefa do agente não pôde ser iniciada' }
            $nova.via = 'agente'
            $nova.resposta = Join-Path (Join-Path $dados 'respostas') ('{0}.json' -f $id)
        } catch {
            Write-Ui ('Agente indisponível ({0}); usando a janela de administrador.' -f $_.Exception.Message)
            try { Remove-Item -LiteralPath $arq -Force -ErrorAction SilentlyContinue } catch { }
            $viaAgente = $false
        }
    }
    if (-not $viaAgente) {
        $pastaPed = Join-Path $script:PastaUsuario 'pedidos'
        if (-not (Test-Path -LiteralPath $pastaPed)) { New-Item -ItemType Directory -Path $pastaPed -Force | Out-Null }
        $arq = Join-Path $pastaPed ('{0}.json' -f $id)
        Write-LacadorJson $arq $pedido
        $agente = Join-Path $PSScriptRoot 'Lacador-Agente.ps1'
        $argumentos = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Pedido "{1}"' -f $agente, $arq
        $exeAtual = Get-LacadorRecipiente
        if ($exeAtual) { $argumentos += (' -Recipiente "{0}"' -f $exeAtual) }
        try {
            $nova.processo = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -Verb RunAs -WindowStyle Hidden -PassThru
        } catch {
            Remove-Item -LiteralPath $arq -Force -ErrorAction SilentlyContinue
            return [ordered]@{ ok = $false; mensagem = 'A permissão de administrador não foi concedida. Sem ela o Windows não deixa instalar. Chame o suporte se você não tiver a senha de administrador.' }
        }
        $nova.via = 'uac'
        $nova.resposta = Join-Path $pastaPed ('{0}.resposta.json' -f $id)
    }
    $script:Acao = $nova
    Write-Ui ('Ação {0} iniciada via {1}: {2} [{3}]' -f $id, $nova.via, $acao, ($fazer -join ', '))
    return [ordered]@{ ok = $true; id = $id; via = $nova.via }
}

function Start-Acesso {
    <# Libera este computador para instalar sem administrador (ou remove a liberação).
       Precisa de administrador uma vez: o Windows mostra a janela de permissão. #>
    param($Corpo)
    $tipo = [string]$Corpo.acao
    if ($tipo -notin 'liberar', 'remover') { return [ordered]@{ ok = $false; mensagem = 'Ação inválida.' } }
    if ($script:Acesso -and $script:Acesso.estado -eq 'executando') { return [ordered]@{ ok = $false; mensagem = 'Já existe uma operação em andamento.' } }
    if ($script:Acao -and $script:Acao.estado -eq 'executando') { return [ordered]@{ ok = $false; mensagem = 'Espere a instalação em andamento terminar.' } }
    $nova = @{ tipo = $tipo; estado = 'executando'; inicio = (Get-Date); processo = $null; resultado = ''; mensagem = ''; simulado = $false; saiuEm = $null }
    if ($script:SimJson) {
        $nova.simulado = $true
        $script:Acesso = $nova
        return [ordered]@{ ok = $true }
    }
    $inst = Join-Path (Join-Path (Get-LacadorRaiz) 'ferramentas') 'Instalar-Lacador.ps1'
    if (-not (Test-Path -LiteralPath $inst)) { return [ordered]@{ ok = $false; mensagem = 'O instalador do Laçador não foi encontrado nesta cópia.' } }
    $res = Join-Path $script:PastaUsuario ('acesso-{0}.json' -f ([guid]::NewGuid().ToString('N').Substring(0, 12)))
    $argumentos = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Silencioso -Resultado "{1}"' -f $inst, $res
    if ($tipo -eq 'remover') { $argumentos += ' -Desinstalar' }
    else {
        $argumentos += ' -Forcar'
        $exeAtual = Get-LacadorRecipiente
        if ($exeAtual) { $argumentos += (' -Recipiente "{0}"' -f $exeAtual) }
    }
    try {
        $nova.processo = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -Verb RunAs -WindowStyle Hidden -PassThru
    } catch {
        return [ordered]@{ ok = $false; mensagem = 'A permissão de administrador não foi concedida. Peça ao suporte para liberar este computador.' }
    }
    $nova.resultado = $res
    $script:Acesso = $nova
    Write-Ui ('Acesso: {0} iniciado.' -f $tipo)
    return [ordered]@{ ok = $true }
}

function Get-AcessoAtual {
    $a = $script:Acesso
    if (-not $a) { return $null }
    if ($a.estado -eq 'executando') {
        $seg = ((Get-Date) - $a.inicio).TotalSeconds
        $fim = $false
        if ($a.simulado) {
            if ($seg -gt 2.4) {
                if ($a.tipo -eq 'liberar') { if (-not $script:SimOk.Contains('acesso')) { $script:SimOk.Add('acesso') } } else { $null = $script:SimOk.Remove('acesso') }
                $a.estado = 'concluido'; $a.mensagem = 'Simulação: nada foi alterado neste computador.'; $fim = $true
            }
        } else {
            $r = $null
            if (Test-Path -LiteralPath $a.resultado) { try { $r = Read-LacadorJson $a.resultado } catch { $r = $null } }
            if ($r) {
                if ($r.ok) { $a.estado = 'concluido' } else { $a.estado = 'erro' }
                $a.mensagem = [string]$r.mensagem
                Remove-Item -LiteralPath $a.resultado -Force -ErrorAction SilentlyContinue
                $fim = $true
            } else {
                $saiu = $false
                if ($a.processo) { try { $saiu = [bool]$a.processo.HasExited } catch { $saiu = $false } }
                if ($saiu -and -not $a.saiuEm) { $a.saiuEm = Get-Date }
                if ($a.saiuEm -and ((Get-Date) - $a.saiuEm).TotalSeconds -gt 4) {
                    $a.estado = 'erro'; $a.mensagem = 'O instalador fechou sem responder. Veja C:\ProgramData\Lacador\logs\instalacao.log'; $fim = $true
                } elseif ($seg -gt 1800) {
                    $a.estado = 'erro'; $a.mensagem = 'A operação passou de 30 minutos e foi dada como travada.'; $fim = $true
                }
            }
        }
        if ($fim) {
            Write-Ui ('Acesso: {0} terminou: {1} {2}' -f $a.tipo, $a.estado, $a.mensagem)
            Start-Verificacao
        }
    }
    return [ordered]@{ tipo = $a.tipo; estado = $a.estado; mensagem = $a.mensagem }
}

function Get-AcaoAtual {
    $a = $script:Acao
    if (-not $a) { return $null }
    if ($a.estado -eq 'executando') {
        if ($a.resposta -and (Test-Path -LiteralPath $a.resposta)) {
            try { $a.ultimo = Read-LacadorJson $a.resposta } catch { }
        }
        $fim = $false
        if ($a.ultimo -and ([string]$a.ultimo.estado -in 'concluido', 'erro', 'recusado')) {
            $a.estado = [string]$a.ultimo.estado
            if ($a.ultimo.mensagem) { $a.mensagem = [string]$a.ultimo.mensagem }
            $fim = $true
        } else {
            $seg = ((Get-Date) - $a.inicio).TotalSeconds
            $saiu = $false
            if ($a.processo) { try { $saiu = [bool]$a.processo.HasExited } catch { $saiu = $false } }
            if ($a.via -eq 'uac' -and $saiu -and $seg -gt 6 -and -not $a.ultimo) {
                $a.estado = 'erro'; $a.mensagem = 'O agente fechou sem responder. Veja a página Diagnóstico e gere o relatório para o suporte.'; $fim = $true
            } elseif ($a.via -eq 'agente' -and -not $a.ultimo -and $seg -gt 90) {
                $a.estado = 'erro'; $a.mensagem = 'O agente do Laçador não respondeu. Avise o suporte: a tarefa "Lacador-Agente" pode estar desativada.'; $fim = $true
            } elseif ($seg -gt 7200) {
                $a.estado = 'erro'; $a.mensagem = 'A instalação passou de duas horas e foi dada como travada.'; $fim = $true
            }
        }
        if ($fim -and -not $a.registrada) {
            $a.registrada = $true
            $okIds = @()
            if ($a.ultimo) { $okIds = @($a.ultimo.passos | Where-Object { $_.estado -eq 'ok' } | ForEach-Object { [string]$_.item }) }
            if ($script:SimJson) {
                foreach ($x in $okIds) {
                    if ($a.acao -eq 'desinstalar') { $null = $script:SimOk.Remove($x); if (-not $script:SimOk.Contains('removido:' + $x)) { $script:SimOk.Add('removido:' + $x) } }
                    else { $null = $script:SimOk.Remove('removido:' + $x); if (-not $script:SimOk.Contains($x)) { $script:SimOk.Add($x) } }
                }
            }
            Add-Historico ([ordered]@{ quando = (Get-Date).ToString('s'); acao = $a.acao; itens = $a.itens; resultado = $a.estado; via = $a.via; demonstracao = [bool]$script:SimJson })
            Write-Ui ('Ação {0} terminou: {1}' -f $a.id, $a.estado)
            Start-Verificacao
        }
    }
    $passos = @()
    $reiniciar = $false
    if ($a.ultimo) { $passos = @($a.ultimo.passos); $reiniciar = [bool]$a.ultimo.reiniciar }
    if (-not $passos.Count) {
        $cat = Get-LacadorCatalogo
        $passos = @($a.itens | ForEach-Object { $i = $_; [ordered]@{ item = $i; nome = [string](@($cat.itens | Where-Object { $_.id -eq $i })[0].nome); estado = 'pendente'; mensagens = @() } })
    }
    return [ordered]@{ id = $a.id; acao = $a.acao; via = $a.via; estado = $a.estado; mensagem = $a.mensagem; reiniciar = $reiniciar; passos = $passos }
}

function Invoke-OperacaoUsuario {
    param($Corpo)
    $op = [string]$Corpo.operacao
    if ($script:SimJson) {
        if ($op -eq 'assinador-token') {
            if (-not $script:SimOk.Contains('ajuste-dexon')) { $script:SimOk.Add('ajuste-dexon') }
            Start-Verificacao
        }
        if ($op -eq 'fixar-extensao') {
            if (-not $Corpo.fechar) { return [ordered]@{ ok = $false; precisaFechar = $true; mensagem = 'O Firefox está aberto.' } }
            if (-not $script:SimOk.Contains('fixar-extensao')) { $script:SimOk.Add('fixar-extensao') }
            Start-Verificacao
            return [ordered]@{ ok = $true; mensagem = 'Demonstração: o botão do assinador foi fixado na barra do Firefox.' }
        }
        return [ordered]@{ ok = $true; mensagem = 'Demonstração: no uso real, esta ação seria executada agora.' }
    }
    $r = Invoke-LacadorOperacaoUsuario -Operacao $op -Parametros $Corpo
    Write-Ui ('Operação {0}: {1}' -f $op, $r.mensagem)
    if ($r.ok -and $op -in 'proxy-aplicar', 'assinador-token') { Start-Verificacao }
    return $r
}

#endregion

#region Servidor local -----------------------------------------------------------

$script:Tipos = @{
    '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.ico' = 'image/x-icon'; '.svg' = 'image/svg+xml'
}
$script:Latin1 = [Text.Encoding]::GetEncoding(28591)
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function Send-Resposta {
    param($Cliente, [int]$Codigo, [string]$Tipo, [byte[]]$Corpo, [string]$Extra = '')
    $motivo = 'OK'
    switch ($Codigo) { 400 { $motivo = 'Bad Request' } 403 { $motivo = 'Forbidden' } 404 { $motivo = 'Not Found' } 405 { $motivo = 'Method Not Allowed' } 413 { $motivo = 'Payload Too Large' } 500 { $motivo = 'Internal Server Error' } }
    if ($null -eq $Corpo) { $Corpo = New-Object byte[] 0 }
    $cab = "HTTP/1.1 $Codigo $motivo`r`nContent-Type: $Tipo`r`nContent-Length: $($Corpo.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nReferrer-Policy: no-referrer`r`nConnection: close`r`n$Extra`r`n"
    try {
        $st = $Cliente.GetStream()
        $b = $script:Latin1.GetBytes($cab)
        $st.Write($b, 0, $b.Length)
        if ($Corpo.Length) { $st.Write($Corpo, 0, $Corpo.Length) }
        $st.Flush()
        try { $Cliente.Client.Shutdown([System.Net.Sockets.SocketShutdown]::Send) } catch { }
    } catch { } finally { try { $Cliente.Close() } catch { } }
}

function ConvertTo-TextoJson {
    # Um texto (ou nada) como valor JSON. No Windows PowerShell 5.1 o ConvertTo-Json não devolve NADA
    # quando recebe $null (o 7 devolve "null"), e a resposta saía quebrada: por isso o tratamento à mão.
    param($Valor)
    if ($null -eq $Valor) { return 'null' }
    $r = ConvertTo-Json -InputObject ([string]$Valor) -Compress
    if (-not $r) { return '""' }
    return [string]$r
}

function Send-Json {
    param($Cliente, [string]$Json, [int]$Codigo = 200)
    Send-Resposta $Cliente $Codigo 'application/json; charset=utf-8' ($script:Utf8.GetBytes($Json))
}

function ConvertFrom-Requisicao {
    # Devolve $null se a requisição ainda não chegou inteira.
    param([byte[]]$Bytes)
    $txt = $script:Latin1.GetString($Bytes)
    $fimCab = $txt.IndexOf("`r`n`r`n")
    if ($fimCab -lt 0) { return $null }
    $linhas = $txt.Substring(0, $fimCab) -split "`r`n"
    $partes = $linhas[0] -split ' '
    if ($partes.Count -lt 2) { return @{ invalida = $true } }
    $cab = @{}
    for ($i = 1; $i -lt $linhas.Count; $i++) {
        $p = $linhas[$i].IndexOf(':')
        if ($p -gt 0) { $cab[$linhas[$i].Substring(0, $p).Trim().ToLowerInvariant()] = $linhas[$i].Substring($p + 1).Trim() }
    }
    $tam = 0
    if ($cab.ContainsKey('content-length')) { [void][int]::TryParse($cab['content-length'], [ref]$tam) }
    if ($tam -lt 0 -or $tam -gt 65536) { return @{ invalida = $true } }
    $ini = $fimCab + 4
    if ($Bytes.Length -lt ($ini + $tam)) { return $null }
    $alvo = $partes[1]
    $caminho = $alvo
    $consulta = @{}
    $q = $alvo.IndexOf('?')
    if ($q -ge 0) {
        $caminho = $alvo.Substring(0, $q)
        foreach ($par in ($alvo.Substring($q + 1) -split '&')) {
            $kv = $par -split '=', 2
            if ($kv[0]) { $v = ''; if ($kv.Count -gt 1) { $v = [Uri]::UnescapeDataString($kv[1]) }; $consulta[$kv[0]] = $v }
        }
    }
    $corpo = ''
    if ($tam -gt 0) { $corpo = $script:Utf8.GetString($Bytes, $ini, $tam) }
    return @{ metodo = $partes[0].ToUpperInvariant(); caminho = $caminho; consulta = $consulta; cabecalhos = $cab; corpo = $corpo }
}

function Invoke-Requisicao {
    param($Cliente, $Req)
    if ($Req.invalida) { Send-Resposta $Cliente 400 'text/plain; charset=utf-8' ($script:Utf8.GetBytes('requisição inválida')); return }
    # Só atende quem chama pelo endereço local (protege contra páginas de fora apontando para cá).
    $hostEsperado = @(('127.0.0.1:{0}' -f $script:PortaReal), ('localhost:{0}' -f $script:PortaReal))
    if ($hostEsperado -notcontains [string]$Req.cabecalhos['host']) { Send-Resposta $Cliente 403 'text/plain; charset=utf-8' ($script:Utf8.GetBytes('acesso negado')); return }
    $caminho = [string]$Req.caminho

    if ($caminho -like '/api/*') {
        $chave = [string]$Req.cabecalhos['x-lacador-chave']
        if (-not $chave -and $caminho -eq '/api/saindo') { $chave = [string]$Req.consulta['k'] }
        if ($chave -ne $script:Chave) { Send-Resposta $Cliente 403 'text/plain; charset=utf-8' ($script:Utf8.GetBytes('acesso negado')); return }
        $origem = [string]$Req.cabecalhos['origin']
        if ($origem -and ($origem -notin @(('http://127.0.0.1:{0}' -f $script:PortaReal), ('http://localhost:{0}' -f $script:PortaReal)))) { Send-Resposta $Cliente 403 'text/plain; charset=utf-8' ($script:Utf8.GetBytes('acesso negado')); return }
        if ($caminho -eq '/api/saindo') {
            # A página avisa que está fechando (ou recarregando). Se ninguém chamar de novo em alguns segundos, encerra.
            $script:Saindo = Get-Date
            Send-Json $Cliente '{"ok":true}'
            return
        }
        $script:UltimoContato = Get-Date
        $script:Saindo = $null
        $corpo = $null
        if ($Req.metodo -eq 'POST' -and $Req.corpo) { try { $corpo = $Req.corpo | ConvertFrom-Json } catch { Send-Json $Cliente '{"ok":false,"mensagem":"corpo inválido"}' 400; return } }
        try {
            switch ('{0} {1}' -f $Req.metodo, $caminho) {
                'GET /api/estado' {
                    $acao = Get-AcaoAtual
                    $acaoJson = 'null'
                    if ($acao) { $acaoJson = ConvertTo-Json -InputObject $acao -Depth 8 -Compress }
                    $estJson = 'null'
                    if ($script:Sync['estadoJson']) { $estJson = [string]$script:Sync['estadoJson'] }
                    $acesso = Get-AcessoAtual
                    $acessoJson = 'null'
                    if ($acesso) { $acessoJson = ConvertTo-Json -InputObject $acesso -Depth 4 -Compress }
                    $json = '{"fase":"' + [string]$script:Sync['fase'] + '","percentual":' + [int]$script:Sync['percentual'] +
                        ',"etapa":' + (ConvertTo-TextoJson $script:Sync['etapa']) + ',"rodada":' + [int]$script:Sync['rodada'] +
                        ',"erro":' + (ConvertTo-TextoJson $script:Sync['erro']) + ',"versao":"' + (Get-LacadorVersao) + '","estado":' + $estJson + ',"acao":' + $acaoJson + ',"acesso":' + $acessoJson + '}'
                    Send-Json $Cliente $json
                }
                'POST /api/verificar' { Start-Verificacao; Send-Json $Cliente '{"ok":true}' }
                'POST /api/pronto' {
                    # A página já está desenhada: a tela de abertura pode sumir.
                    if (-not $script:AberturaFechada) { Write-Ui ('Janela pronta em {0:N1} s.' -f ((Get-Date) - $script:AberturaEm).TotalSeconds) }
                    Close-Abertura
                    Send-Json $Cliente '{"ok":true}'
                }
                'POST /api/acao' { Send-Json $Cliente (ConvertTo-Json -InputObject (Start-Acao $corpo) -Depth 5 -Compress) }
                'POST /api/acao/fechar' {
                    if ($script:Acao -and $script:Acao.estado -ne 'executando') { $script:Acao = $null }
                    Send-Json $Cliente '{"ok":true}'
                }
                'POST /api/acesso' { Send-Json $Cliente (ConvertTo-Json -InputObject (Start-Acesso $corpo) -Depth 4 -Compress) }
                'POST /api/acesso/fechar' {
                    if ($script:Acesso -and $script:Acesso.estado -ne 'executando') { $script:Acesso = $null }
                    Send-Json $Cliente '{"ok":true}'
                }
                'POST /api/usuario' { Send-Json $Cliente (ConvertTo-Json -InputObject (Invoke-OperacaoUsuario $corpo) -Depth 5 -Compress) }
                'GET /api/tutoriais' { Send-Resposta $Cliente 200 'application/json; charset=utf-8' ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'tutoriais.json'))) }
                'GET /api/historico' { Send-Json $Cliente (ConvertTo-Json -InputObject ([ordered]@{ itens = @(Get-Historico) }) -Depth 6 -Compress) }
                default { Send-Json $Cliente '{"ok":false,"mensagem":"não encontrado"}' 404 }
            }
        } catch {
            Write-Ui ('Erro em {0}: {1}' -f $caminho, $_.Exception.Message)
            Send-Json $Cliente (ConvertTo-Json -InputObject ([ordered]@{ ok = $false; mensagem = [string]$_.Exception.Message }) -Compress) 500
        }
        return
    }

    if ($Req.metodo -ne 'GET') { Send-Resposta $Cliente 405 'text/plain; charset=utf-8' ($script:Utf8.GetBytes('método não permitido')); return }
    if ($caminho -eq '/') { $caminho = '/index.html' }
    if ($caminho -notmatch '^/[A-Za-z0-9_\-./]+$' -or $caminho.Contains('..')) { Send-Resposta $Cliente 404 'text/plain; charset=utf-8' ($script:Utf8.GetBytes('não encontrado')); return }
    $arq = Join-Path $script:PastaInterface ($caminho.TrimStart('/') -replace '/', [IO.Path]::DirectorySeparatorChar)
    $ext = [IO.Path]::GetExtension($arq).ToLowerInvariant()
    if (-not $script:Tipos.ContainsKey($ext) -or -not (Test-Path -LiteralPath $arq -PathType Leaf)) { Send-Resposta $Cliente 404 'text/plain; charset=utf-8' ($script:Utf8.GetBytes('não encontrado')); return }
    $extra = ''
    if ($ext -eq '.html') { $extra = "Content-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`r`n" }
    Send-Resposta $Cliente 200 $script:Tipos[$ext] ([IO.File]::ReadAllBytes($arq)) $extra
}

function Open-Janela {
    param([string]$Url)
    $cfg = Get-LacadorConfig
    $pref = [string]$cfg.interface.navegador
    $nav = Get-LacadorNavegadores
    $exe = ''
    if ($pref -in 'auto', 'edge', '') { $exe = [string]$nav.edge }
    if (-not $exe -and $pref -in 'auto', 'chrome', '') { $exe = [string]$nav.chrome }
    if ($pref -eq 'padrao') { $exe = '' }
    if ($exe) {
        $larg = 1280; $alt = 880; $posicao = ''
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
            $larg = [Math]::Min(1280, $wa.Width - 24); $alt = [Math]::Min(900, $wa.Height - 24)
            $posicao = (' --window-position={0},{1}' -f ([int](($wa.Width - $larg) / 2) + $wa.X), ([int](($wa.Height - $alt) / 2) + $wa.Y))
        } catch { }
        $perfil = Join-Path $script:PastaUsuario 'janela'
        $argumentos = ('--app="{0}" --user-data-dir="{1}" --window-size={2},{3}{4} --no-first-run --no-default-browser-check --disable-sync --disable-features=Translate' -f $Url, $perfil, $larg, $alt, $posicao)
        try {
            $script:ProcJanela = Start-Process -FilePath $exe -ArgumentList $argumentos -PassThru
            Write-Ui ('Janela aberta com {0}' -f $exe)
            return
        } catch { Write-Ui ('Não consegui abrir {0}: {1}' -f $exe, $_.Exception.Message) }
    }
    Start-Process $Url
    Write-Ui 'Janela aberta no navegador padrão.'
}

#endregion

#region Principal ----------------------------------------------------------------

try {
    Write-Ui ('=== Laçador {0} iniciado por {1}\{2} ===' -f (Get-LacadorVersao), $env:USERDOMAIN, $env:USERNAME)

    if ($Cenario) { $script:SimJson = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Cenario).ProviderPath, [Text.Encoding]::UTF8) }
    elseif ($Demo) { $script:SimJson = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'demonstracao.json'), [Text.Encoding]::UTF8) }

    # Já existe uma janela do Laçador deste usuário? Então só mostra a que está aberta.
    $arqInstancia = Join-Path $script:PastaUsuario 'instancia.json'
    if (-not $SemJanela -and -not $script:SimJson -and (Test-Path -LiteralPath $arqInstancia)) {
        try {
            $inst = Read-LacadorJson $arqInstancia
            $vivo = Get-Process -Id ([int]$inst.pid) -ErrorAction SilentlyContinue
            if ($vivo -and $vivo.ProcessName -like 'powershell*') {
                $t = New-Object System.Net.Sockets.TcpClient
                $t.Connect('127.0.0.1', [int]$inst.porta)
                $t.Close()
                Close-Abertura
                Open-Janela ('http://127.0.0.1:{0}/?k={1}' -f $inst.porta, $inst.chave)
                exit 0
            }
        } catch { }
    }

    $escuta = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Porta)
    $escuta.Start()
    $script:PortaReal = ([System.Net.IPEndPoint]$escuta.LocalEndpoint).Port
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytesChave = New-Object byte[] 16
    $rng.GetBytes($bytesChave)
    $script:Chave = -join ($bytesChave | ForEach-Object { $_.ToString('x2') })
    $url = 'http://127.0.0.1:{0}/?k={1}' -f $script:PortaReal, $script:Chave
    if (-not $script:SimJson) {
        try { Write-LacadorJson $arqInstancia ([ordered]@{ pid = $PID; porta = $script:PortaReal; chave = $script:Chave }) } catch { }
    }

    # O Lacador.exe extrai o programa em %LOCALAPPDATA%\Lacador\app\<versão>. Apaga as cópias antigas (de outras versões).
    try {
        $pastaApp = Join-Path $script:PastaUsuario 'app'
        $minha = Split-Path -Parent $PSScriptRoot
        if ((Test-Path -LiteralPath $pastaApp) -and ((Split-Path -Parent $minha) -eq $pastaApp)) {
            Get-ChildItem -LiteralPath $pastaApp -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -ne $minha -and $_.LastWriteTime -lt (Get-Date).AddDays(-2) } |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } catch { }

    Start-Verificacao
    if ($SemJanela) { Write-Host ('LACADOR_URL={0}' -f $url) }
    elseif ($script:AberturaEvento) { Set-Abertura 1 'verificando' 'Carregando o sistema...' }   # a janela abre quando a verificação terminar
    else { Open-Janela $url }

    $clientes = New-Object System.Collections.ArrayList
    $ultimaFaxina = Get-Date
    while ($script:Rodando) {
        $trabalhou = $false
        while ($escuta.Pending()) {
            $c = $escuta.AcceptTcpClient()
            $c.NoDelay = $true
            $null = $clientes.Add(@{ c = $c; t = (Get-Date); buf = (New-Object System.IO.MemoryStream) })
            $trabalhou = $true
        }
        foreach ($x in @($clientes.ToArray())) {
            $fechar = $false
            try {
                $st = $x.c.GetStream()
                if ($st.DataAvailable) {
                    $trabalhou = $true
                    $tmp = New-Object byte[] 8192
                    while ($st.DataAvailable) {
                        $n = $st.Read($tmp, 0, $tmp.Length)
                        if ($n -le 0) { break }
                        $x.buf.Write($tmp, 0, $n)
                        if ($x.buf.Length -gt 131072) { break }
                    }
                    if ($x.buf.Length -gt 131072) { Send-Resposta $x.c 413 'text/plain; charset=utf-8' ($script:Utf8.GetBytes('grande demais')); $fechar = $true }
                    else {
                        $req = ConvertFrom-Requisicao $x.buf.ToArray()
                        if ($req) { Invoke-Requisicao $x.c $req; $fechar = $true }
                    }
                } elseif (((Get-Date) - $x.t).TotalSeconds -gt 12) {
                    try { $x.c.Close() } catch { }
                    $fechar = $true
                }
            } catch {
                try { $x.c.Close() } catch { }
                $fechar = $true
            }
            if ($fechar) { $clientes.Remove($x) }
        }

        if (((Get-Date) - $ultimaFaxina).TotalMilliseconds -gt 500) {
            $ultimaFaxina = Get-Date
            # tarefas de demonstração terminadas
            foreach ($t in @($script:Tarefas.ToArray())) { if ($t.Alca.IsCompleted) { try { $t.PS.Dispose() } catch { }; $script:Tarefas.Remove($t) } }
            # a ação segue sendo acompanhada mesmo se a página demorar a perguntar
            if ($script:Acao -and $script:Acao.estado -eq 'executando') { $null = Get-AcaoAtual }
            if ($script:Acesso -and $script:Acesso.estado -eq 'executando') { $null = Get-AcessoAtual }
            # janela fechada? (a página deixa de chamar)
            $agora = Get-Date
            if ($script:UltimoContato) {
                # Com a janela minimizada o navegador espaça as chamadas para até 1 por minuto: por isso a folga.
                $semContato = ($agora - $script:UltimoContato).TotalSeconds
                $janelaFechou = $false
                if ($script:ProcJanela) { try { $janelaFechou = [bool]$script:ProcJanela.HasExited } catch { } }
                $avisouSaida = ($script:Saindo -and ($agora - $script:Saindo).TotalSeconds -gt 5)
                if ($semContato -gt 150 -or ($janelaFechou -and $semContato -gt 8) -or $avisouSaida) { $script:Rodando = $false }
            } elseif (($agora - $script:Inicio).TotalSeconds -gt 180) {
                $script:Rodando = $false
            }
        }
        # Tela de abertura: mostra o andamento e, com a verificação pronta, abre a janela do programa por baixo dela.
        if ($script:AberturaEvento -and -not $script:AberturaFechada) {
            if (-not $script:JanelaAbertaEm) {
                if ($script:Sync['fase'] -eq 'pronto') {
                    Set-Abertura 100 'janela' 'Abrindo o Laçador...'
                    Open-Janela ($url + '&a=1')
                    $script:JanelaAbertaEm = Get-Date
                } else {
                    Set-Abertura ([int]([int]$script:Sync['percentual'] * 0.92)) 'verificando' ([string]$script:Sync['etapa'])
                }
            } elseif (((Get-Date) - $script:JanelaAbertaEm).TotalSeconds -gt 20) {
                Write-Ui 'A página não avisou que abriu; fechando a tela de abertura assim mesmo.'
                Close-Abertura
            }
        }
        if (-not $trabalhou) { Start-Sleep -Milliseconds 15 }
    }
    Write-Ui 'Laçador encerrado.'
    try { $escuta.Stop() } catch { }
    if (-not $script:SimJson) { Remove-Item -LiteralPath $arqInstancia -Force -ErrorAction SilentlyContinue }
} catch {
    $msg = ("{0}`r`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
    Write-Ui ('ERRO FATAL: ' + $msg)
    Close-Abertura
    if (-not $SemJanela) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show(("O Laçador não conseguiu abrir.`r`n`r`n{0}`r`n`r`nO registro está em:`r`n{1}" -f $_.Exception.Message, $script:ArquivoLog), 'Laçador', 'OK', 'Error')
        } catch { }
    } else { Write-Host ('ERRO: ' + $msg) }
    exit 1
}

#endregion
