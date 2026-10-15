<#
===============================================================================
  LAÇADOR - Liberar o computador (instalação sem administrador)
===============================================================================
  Normalmente ninguém roda este arquivo à mão: é o que a página "Acesso" do
  Laçador executa quando alguém clica em "Liberar este computador", e o que o
  comando  Lacador.exe /instalar  chama (GPO, linha de comando).

  O que faz (precisa de administrador, uma vez por computador)
    1. Copia o Laçador para  C:\Program Files\Lacador  (o Lacador.exe, com os
       instaladores dentro, e os arquivos do programa)
    2. Cria  C:\ProgramData\Lacador  (fila de pedidos, respostas, registros)
    3. Registra a tarefa agendada "Lacador-Agente" (SYSTEM, só sob demanda)
    4. Cria os atalhos (Menu Iniciar e Área de Trabalho de todos)
  Depois disso o usuário comum instala e repara pelo Laçador sem senha.

  Exemplos (como administrador)
    Lacador.exe /instalar
    Lacador.exe /instalar -Silencioso                      (GPO: sem perguntas)
    Lacador.exe /instalar -Silencioso -Preparar sigadaer -SomenteReparar
    Lacador.exe /instalar -Desinstalar

  Instaladores: ficam dentro do Lacador.exe. Se existir uma pasta "pacotes" ao
  lado, ela também vale (-PastaPacotes X usa a pasta X, de rede por exemplo).
===============================================================================
#>
param(
    [string]$PastaPacotes = '',
    [switch]$CopiarPacotes,
    [string[]]$Preparar,
    [string]$Token = '',
    [switch]$SomenteReparar,
    [switch]$Silencioso,
    [switch]$SemAtalhoNaAreaDeTrabalho,
    [switch]$Forcar,
    [switch]$Desinstalar,
    [string]$Destino = '',
    [string]$Recipiente = '',
    [string]$Resultado = '',
    [switch]$Pausar
)

$ErrorActionPreference = 'Stop'
$origem = Split-Path -Parent $PSScriptRoot
$nomeTarefa = 'Lacador-Agente'
$chaveReg = 'SOFTWARE\Lacador'
$script:Log = $null
$script:UltimaMensagem = ''
# O Lacador.exe de onde esta instalação está saindo (o lançador informa pela variável de ambiente).
if (-not $Recipiente -and $env:LACADOR_EXE) { $Recipiente = [string]$env:LACADOR_EXE }
$recipienteSumiu = ''
if ($Recipiente -and -not (Test-Path -LiteralPath $Recipiente -PathType Leaf)) { $recipienteSumiu = $Recipiente; $Recipiente = '' }
if ($Recipiente) { $env:LACADOR_EXE = $Recipiente }

function Write-Passo {
    param([string]$Texto, [string]$Cor = 'Gray')
    if (-not $Silencioso) { Write-Host $Texto -ForegroundColor $Cor }
    if ($script:Log) {
        try { Add-Content -LiteralPath $script:Log -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Texto) -Encoding UTF8 } catch { }
    }
}

function Exit-Instalador {
    param([int]$Codigo)
    if ($Resultado) {
        # A tela do Laçador lê este arquivo para saber como terminou.
        try {
            $json = ConvertTo-Json -InputObject ([ordered]@{ ok = ($Codigo -eq 0); codigo = $Codigo; mensagem = $script:UltimaMensagem }) -Compress
            [IO.File]::WriteAllText($Resultado, $json, (New-Object System.Text.UTF8Encoding($false)))
        } catch { }
    }
    if ($Pausar -and -not $Silencioso) { Write-Host ''; $null = Read-Host 'Pressione Enter para fechar' }
    exit $Codigo
}

$noWindows = ($env:OS -eq 'Windows_NT')
$admin = $false
if ($noWindows) {
    try { $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { }
}

# Sem administrador: pede a elevação (janela do Windows) e repete os mesmos parâmetros.
if ($noWindows -and -not $admin) {
    if ($Silencioso) { Write-Host 'Instalar-Lacador: precisa rodar como administrador.'; exit 2 }
    $lista = New-Object System.Collections.Generic.List[string]
    foreach ($x in '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath)) { $lista.Add($x) }
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v.IsPresent) { $lista.Add('-' + $k) } }
        elseif ($v -is [array]) { $lista.Add('-' + $k); $lista.Add('"{0}"' -f ($v -join ',')) }
        elseif ([string]$v) { $lista.Add('-' + $k); $lista.Add('"{0}"' -f [string]$v) }
    }
    if (-not $PSBoundParameters.ContainsKey('Pausar')) { $lista.Add('-Pausar') }
    if ($Recipiente -and -not $PSBoundParameters.ContainsKey('Recipiente')) { $lista.Add('-Recipiente'); $lista.Add('"{0}"' -f $Recipiente) }
    Write-Host 'O Windows vai pedir a permissão de administrador...'
    try {
        Start-Process -FilePath (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $lista.ToArray() -Verb RunAs
    } catch {
        Write-Host 'A permissão de administrador não foi concedida. Nada foi instalado.' -ForegroundColor Yellow
        exit 2
    }
    exit 0
}

if (-not $Destino) {
    if ($env:ProgramFiles) { $Destino = Join-Path $env:ProgramFiles 'Lacador' } else { throw 'Informe -Destino.' }
}

function Get-Carimbo {
    # Versão + resumo de todos os arquivos do programa: muda quando qualquer arquivo muda.
    param([string]$PastaPrograma, [string]$Versao)
    $sha = [Security.Cryptography.SHA256]::Create()
    $partes = New-Object System.Collections.Generic.List[string]
    $partes.Add($Versao)
    $arqs = @(Get-ChildItem -LiteralPath $PastaPrograma -Recurse -File | Sort-Object FullName)
    foreach ($a in $arqs) {
        $partes.Add($a.FullName.Substring($PastaPrograma.Length))
        $partes.Add((Get-FileHash -LiteralPath $a.FullName -Algorithm SHA256).Hash)
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($partes -join '|'))
    return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '')
}

function Get-TarefaServico {
    $svc = New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    return $svc
}

function Test-Tarefa {
    try { $null = (Get-TarefaServico).GetFolder('\').GetTask($nomeTarefa); return $true } catch { return $false }
}

function Register-Tarefa {
    param([string]$ArquivoAgente)
    $svc = Get-TarefaServico
    $def = $svc.NewTask(0)
    $def.RegistrationInfo.Description = 'Laçador: instala e repara os programas dos tokens quando o usuário pede pela tela. Só roda sob demanda.'
    $def.RegistrationInfo.Author = 'Laçador'
    $def.Principal.UserId = 'S-1-5-18'
    $def.Principal.LogonType = 5      # conta de serviço (SYSTEM)
    $def.Principal.RunLevel = 1       # privilégios mais altos
    $def.Settings.Enabled = $true
    $def.Settings.AllowDemandStart = $true
    $def.Settings.StartWhenAvailable = $false
    $def.Settings.DisallowStartIfOnBatteries = $false
    $def.Settings.StopIfGoingOnBatteries = $false
    $def.Settings.ExecutionTimeLimit = 'PT3H'
    $def.Settings.MultipleInstances = 1   # enfileira: um pedido feito durante outro não se perde
    $def.Settings.Hidden = $false
    $acao = $def.Actions.Create(0)
    $acao.Path = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $acao.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Fila' -f $ArquivoAgente
    # SYSTEM e Administradores: controle total. Usuários autenticados: ler e executar (é o que deixa o usuário comum acionar o agente).
    $sddl = 'D:(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;AU)'
    $pasta = $svc.GetFolder('\')
    $tarefa = $pasta.RegisterTaskDefinition($nomeTarefa, $def, 6, 'SYSTEM', $null, 5, $sddl)
    try { $tarefa.SetSecurityDescriptor($sddl, 0) } catch { Write-Passo ('  Aviso: não foi possível regravar a permissão da tarefa ({0}).' -f $_.Exception.Message) 'Yellow' }
    $atual = ''
    try { $atual = [string]$tarefa.GetSecurityDescriptor(4) } catch { }
    return $atual
}

function New-Atalho {
    param([string]$Arquivo, [string]$PastaInstalada)
    $w = New-Object -ComObject 'WScript.Shell'
    $s = $w.CreateShortcut($Arquivo)
    $exeInstalado = Join-Path $PastaInstalada 'Lacador.exe'
    if (Test-Path -LiteralPath $exeInstalado) {
        $s.TargetPath = $exeInstalado
    } else {
        $s.TargetPath = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $s.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $PastaInstalada 'programa\Lacador.ps1')
    }
    $s.WorkingDirectory = $PastaInstalada
    $s.IconLocation = '{0},0' -f (Join-Path $PastaInstalada 'programa\interface\img\lacador.ico')
    $s.Description = 'Laçador - Sistema de Gerenciamento de Tokens'
    $s.WindowStyle = 7
    $s.Save()
}

function Get-Atalhos {
    $r = New-Object System.Collections.Generic.List[string]
    try { $r.Add((Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Laçador.lnk')) } catch { }
    try { $r.Add((Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Laçador.lnk')) } catch { }
    return $r.ToArray()
}

$codigo = 0
try {
    # ------------------------------------------------------------- desinstalar
    if ($Desinstalar) {
        if (-not $noWindows) { throw 'A desinstalação só existe no Windows.' }
        Write-Passo 'Removendo o Laçador deste computador...' 'Cyan'
        Set-Location -LiteralPath $env:windir
        try { (Get-TarefaServico).GetFolder('\').DeleteTask($nomeTarefa, 0); Write-Passo '  Tarefa agendada removida.' } catch { Write-Passo '  Tarefa agendada: não existia.' }
        foreach ($a in (Get-Atalhos)) { if (Test-Path -LiteralPath $a) { Remove-Item -LiteralPath $a -Force; Write-Passo ('  Atalho removido: {0}' -f $a) } }
        $pastaReg = ''
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
            $k = $base.OpenSubKey($chaveReg)
            if ($k) { $pastaReg = [string]$k.GetValue('Pasta'); $k.Close() }
            $base.DeleteSubKeyTree($chaveReg, $false)
            $base.Close()
        } catch { }
        $dados = Join-Path $env:ProgramData 'Lacador'
        foreach ($n in 'pedidos', 'respostas') {
            $p = Join-Path $dados $n
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
        foreach ($p in @($pastaReg, $Destino) | Select-Object -Unique) {
            if ($p -and (Test-Path -LiteralPath (Join-Path $p 'programa\Lacador.Motor.psm1'))) {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
                Write-Passo ('  Pasta removida: {0}' -f $p)
            }
        }
        Write-Passo 'Pronto. Os programas instalados pelo Laçador (drivers, assinador, Firefox, Java) e a' 'Green'
        Write-Passo 'configuração da extensão no Firefox continuam no computador.' 'Green'
        $script:UltimaMensagem = 'Liberação removida. Os programas já instalados continuam no computador.'
        Exit-Instalador 0
    }

    # ---------------------------------------------------------------- instalar
    if ($recipienteSumiu) {
        # Acontece quando o Lacador.exe está numa unidade de rede mapeada só para o usuário: a conta de administrador não enxerga.
        throw ('A conta de administrador não conseguiu ler o Lacador.exe em {0}. Copie o Lacador.exe para o próprio computador (a Área de Trabalho, por exemplo) e tente de novo.' -f $recipienteSumiu)
    }
    $programaOrigem = Join-Path $origem 'programa'
    if (-not (Test-Path -LiteralPath (Join-Path $programaOrigem 'Lacador.Motor.psm1'))) { throw ('Pasta do programa não encontrada em {0}' -f $origem) }
    Import-Module (Join-Path $programaOrigem 'Lacador.Motor.psm1') -Force
    $versao = Get-LacadorVersao
    $carimbo = Get-Carimbo $programaOrigem $versao
    if ($Recipiente) { $carimbo = '{0}-{1}' -f $carimbo, (Get-Item -LiteralPath $Recipiente).Length }
    $mesmaPasta = ([IO.Path]::GetFullPath($origem).TrimEnd('\', '/') -ieq [IO.Path]::GetFullPath($Destino).TrimEnd('\', '/'))

    $jaInstalado = $false
    if ($noWindows -and -not $Forcar) {
        $carimboAtual = [string](Get-LacadorValorRegistro 'HKLM' 64 $chaveReg 'Carimbo')
        $pastaAtual = [string](Get-LacadorValorRegistro 'HKLM' 64 $chaveReg 'Pasta')
        $exeOk = ((-not $Recipiente) -or (Test-Path -LiteralPath (Join-Path $pastaAtual 'Lacador.exe')))
        if ($carimboAtual -eq $carimbo -and $pastaAtual -and $exeOk -and (Test-Path -LiteralPath (Join-Path $pastaAtual 'programa\Lacador-Agente.ps1')) -and (Test-Tarefa)) {
            $jaInstalado = $true
            $Destino = $pastaAtual
        }
    }

    if ($jaInstalado) {
        Write-Passo ('O Laçador {0} já está instalado e igual a esta cópia. Nada a fazer.' -f $versao) 'Green'
        $script:UltimaMensagem = 'Este computador já estava liberado.'
    } else {
        Write-Passo ('Instalando o Laçador {0} em {1}' -f $versao, $Destino) 'Cyan'

        # 1. Arquivos do programa
        if (-not $mesmaPasta) {
            if (-not (Test-Path -LiteralPath $Destino)) { New-Item -ItemType Directory -Path $Destino -Force | Out-Null }
            $programaDestino = Join-Path $Destino 'programa'
            if (Test-Path -LiteralPath $programaDestino) { Remove-Item -LiteralPath $programaDestino -Recurse -Force }
            Copy-Item -LiteralPath $programaOrigem -Destination $Destino -Recurse -Force
            $ferr = Join-Path $Destino 'ferramentas'
            if (Test-Path -LiteralPath $ferr) { Remove-Item -LiteralPath $ferr -Recurse -Force }
            Copy-Item -LiteralPath (Join-Path $origem 'ferramentas') -Destination $Destino -Recurse -Force
            foreach ($n in @('LEIA-ME.txt')) {
                $a = Join-Path $origem $n
                if (Test-Path -LiteralPath $a) { Copy-Item -LiteralPath $a -Destination $Destino -Force }
            }
            Write-Passo '  Programa copiado.'
            if ($Recipiente) {
                $exeDestino = Join-Path $Destino 'Lacador.exe'
                if ([IO.Path]::GetFullPath($Recipiente) -ine [IO.Path]::GetFullPath($exeDestino)) {
                    Write-Passo '  Copiando o Lacador.exe (com os instaladores dentro)...'
                    Copy-Item -LiteralPath $Recipiente -Destination $exeDestino -Force
                    # Ajustes da base que estejam ao lado do executável vão junto
                    $cfgLado = Join-Path (Split-Path -Parent $Recipiente) 'Lacador.config.json'
                    if (Test-Path -LiteralPath $cfgLado) { Copy-Item -LiteralPath $cfgLado -Destination $Destino -Force }
                }
            }
        } else {
            Write-Passo '  O instalador já está rodando de dentro da pasta de instalação: arquivos mantidos.'
        }
        if ($noWindows) { try { Get-ChildItem -LiteralPath $Destino -Recurse -File | Unblock-File -ErrorAction SilentlyContinue } catch { } }

        # 2. Instaladores (pacotes)
        $pacotesOrigem = Join-Path $origem 'pacotes'
        $temPacotes = $false
        if (Test-Path -LiteralPath $pacotesOrigem) {
            $temPacotes = (@(Get-ChildItem -LiteralPath $pacotesOrigem -File | Where-Object { '.exe', '.msp', '.xpi' -contains $_.Extension.ToLowerInvariant() }).Count -gt 0)
        }
        $pastaNaConfig = $null    # $null = não mexer; '' = usar <instalação>\pacotes
        if ($PastaPacotes) {
            $pastaNaConfig = $PastaPacotes
            Write-Passo ('  Instaladores: serão lidos de {0}' -f $PastaPacotes)
        } elseif ($temPacotes -and -not $mesmaPasta) {
            if ($pacotesOrigem.StartsWith('\\') -and -not $CopiarPacotes) {
                $pastaNaConfig = $pacotesOrigem
                Write-Passo ('  Instaladores: continuam na rede, em {0}' -f $pacotesOrigem)
            } else {
                $pacotesDestino = Join-Path $Destino 'pacotes'
                Write-Passo '  Copiando os instaladores para o computador (cerca de 400 MB)...'
                if ($noWindows) {
                    $null = & (Join-Path $env:windir 'System32\robocopy.exe') $pacotesOrigem $pacotesDestino '/E' '/R:1' '/W:1' '/NP' '/NFL' '/NDL' '/NJH' '/NJS'
                    if ($LASTEXITCODE -ge 8) { throw ('A cópia dos instaladores falhou (robocopy, código {0}).' -f $LASTEXITCODE) }
                } else {
                    if (-not (Test-Path -LiteralPath $pacotesDestino)) { New-Item -ItemType Directory -Path $pacotesDestino -Force | Out-Null }
                    Copy-Item -Path (Join-Path $pacotesOrigem '*') -Destination $pacotesDestino -Recurse -Force
                }
                $pastaNaConfig = ''
                Write-Passo '  Instaladores copiados.'
            }
        } elseif (-not $temPacotes -and -not $Recipiente) {
            Write-Passo '  Aviso: nenhum instalador encontrado (nem pasta "pacotes", nem Lacador.exe). Informe -PastaPacotes.' 'Yellow'
        }
        if ($null -ne $pastaNaConfig) {
            $arqCfg = Join-Path (Join-Path $Destino 'programa') 'config.json'
            $cfg = Read-LacadorJson $arqCfg
            $cfg | Add-Member -NotePropertyName 'pastaPacotes' -NotePropertyValue $pastaNaConfig -Force
            Write-LacadorJson $arqCfg $cfg
        }

        if ($noWindows) {
            # A partir daqui, usa o motor já instalado
            Import-Module (Join-Path $Destino 'programa\Lacador.Motor.psm1') -Force

            # 3. Pasta de dados protegida, com a fila de pedidos
            $dados = Initialize-LacadorPastaDados -ComFila
            $script:Log = Join-Path $dados 'logs\instalacao.log'
            Write-Passo ('  Pasta de dados pronta: {0}' -f $dados)

            # 4. Registro
            $k = Open-LacadorChave 'HKLM' 64 $chaveReg $true $true
            $k.SetValue('Pasta', $Destino); $k.SetValue('Versao', $versao); $k.SetValue('Carimbo', $carimbo); $k.SetValue('InstaladoEm', (Get-Date).ToString('s'))
            $k.Close()

            # 5. Tarefa do agente
            $sd = Register-Tarefa (Join-Path $Destino 'programa\Lacador-Agente.ps1')
            Write-Passo ('  Tarefa "{0}" registrada (SYSTEM, sob demanda).' -f $nomeTarefa)
            if ($sd -and $sd -notmatch ';;;AU\)') { Write-Passo '  Aviso: a permissão para o usuário comum acionar a tarefa não apareceu. Nesse caso a tela pede a senha de administrador.' 'Yellow' }

            # 6. Atalhos
            $atalhos = @(Get-Atalhos)
            if ($SemAtalhoNaAreaDeTrabalho -and $atalhos.Count -gt 1) { $atalhos = @($atalhos[0]) }
            foreach ($a in $atalhos) {
                try { New-Atalho $a $Destino; Write-Passo ('  Atalho criado: {0}' -f $a) } catch { Write-Passo ('  Aviso: atalho não criado ({0}): {1}' -f $a, $_.Exception.Message) 'Yellow' }
            }
        } else {
            Write-Passo '  (Fora do Windows: só os arquivos foram copiados.)' 'Yellow'
        }
        Write-Passo ('Laçador {0} instalado.' -f $versao) 'Green'
        $script:UltimaMensagem = 'Computador liberado: agora qualquer usuário instala e repara pelo Laçador, sem senha de administrador.'
    }

    # ------------------------------------------- preparar sistemas (opcional)
    if ($Preparar -and $noWindows) {
        $agente = Join-Path $Destino 'programa\Lacador-Agente.ps1'
        $lista = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $agente, '-Preparar', ($Preparar -join ','))
        if ($Token) { $lista += @('-Token', $Token) }
        if ($SomenteReparar) { $lista += '-SomenteReparar' }
        Write-Passo ('Preparando: {0}' -f ($Preparar -join ', ')) 'Cyan'
        & (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe') @lista
        if ($LASTEXITCODE -ne 0) { $codigo = 1; Write-Passo 'O preparo terminou com pendências. Veja C:\ProgramData\Lacador\logs\agente.log' 'Yellow' }
    }
} catch {
    $codigo = 1
    $script:UltimaMensagem = [string]$_.Exception.Message
    Write-Passo ('ERRO: {0}' -f $_.Exception.Message) 'Red'
    if ($Silencioso) { Write-Host ('Instalar-Lacador: ERRO: {0}' -f $_.Exception.Message) }
}
Exit-Instalador $codigo
