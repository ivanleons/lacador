<#
===============================================================================
  DIAGNÓSTICO DO ASSINADOR DIGITAL + TOKEN  (somente leitura)
===============================================================================
  O que faz : coleta informações do Windows, WMIC, Java, assinador, token,
              certificados, Kaspersky, Firefox/extensão e logs de erro, e salva
              tudo num arquivo .txt na Área de Trabalho.
  O que NÃO faz: não instala, não remove e não altera nada na máquina.
  Privacidade: números de CPF/CNPJ aparecem mascarados no relatório.

  COMO USAR
   1. Conecte o token na porta USB.
   2. Entre no usuário que usa o token (certificados e Firefox são por usuário).
   3. Copie este arquivo para a Área de Trabalho.
   4. Abra o PowerShell (de preferência "Executar como administrador", desde
      que continue sendo o mesmo usuário) e rode:

        Set-Location ([Environment]::GetFolderPath('Desktop'))
        powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnostico-assinador.ps1

   5. No final, o relatório abre sozinho no Bloco de Notas.
===============================================================================
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$script:Relatorio = New-Object System.Collections.Generic.List[string]
$script:Resumo    = New-Object System.Collections.Generic.List[string]

function Secao([string]$Titulo) {
    Write-Host "  - $Titulo" -ForegroundColor Cyan
    $script:Relatorio.Add('')
    $script:Relatorio.Add(('=' * 78))
    $script:Relatorio.Add(" $Titulo")
    $script:Relatorio.Add(('=' * 78))
}
function Linha([string]$Texto) { $script:Relatorio.Add($Texto) }
function Resumo([string]$Texto) { $script:Resumo.Add($Texto) }
function Tabela($Objetos) {
    $lista = @($Objetos | Where-Object { $null -ne $_ })
    if ($lista.Count -eq 0) { Linha '  (nada encontrado)'; return }
    Linha (($lista | Format-Table -AutoSize -Wrap | Out-String -Width 400).TrimEnd())
}
function Mascarar([string]$Texto) {
    if (-not $Texto) { return $Texto }
    $t = $Texto -replace '\d{3}\.\d{3}\.\d{3}-\d{2}', '[mascarado]'
    return ($t -replace '\d{11,14}', '[mascarado]')
}
function Encurtar([string]$Texto, [int]$Max = 350) {
    if (-not $Texto) { return '' }
    $t = (($Texto -replace "`0", '') -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max) + '...' }
    return $t
}
function SimNao($Valor) { if ($Valor) { return 'SIM' } else { return 'NÃO' } }

$padraoProgramas = 'assinador|comaer|certisign|safenet|safesign|gemalto|thales|watchdata|epass|feitian|starsign|giesecke|bry|lacuna|web ?pki|serpro|dexon|dxsafe|dxtoken|token|java|jre|jdk|openjdk|adoptium|temurin|zulu|corretto|kaspersky|firefox'
$padraoAssinador = 'assinador|comaer|signer'
$padraoToken     = 'token|smart ?card|safenet|etoken|ccid|certisign|watchdata|epass|feitian|gemalto|thales|starsign|g\+d|rainbow|dexon|dxtoken|dxsafe'
$padraoLogs      = 'java|javaw|jvm|assinador|comaer|signer|pkcs|etoken|safenet|safesign|scard|smart ?card|wmic'

Write-Host ''
Write-Host 'Diagnóstico do Assinador Digital - coletando informações (somente leitura)...' -ForegroundColor Yellow

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------------------------------------------------------------------
Secao '1. SISTEMA'
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $usuarioSessao = $cs.UserName

    Linha ('Computador         : {0}  ({1} {2})' -f $env:COMPUTERNAME, $cs.Manufacturer, $cs.Model)
    Linha ('Script rodando como: {0}\{1}   Administrador: {2}' -f $env:USERDOMAIN, $env:USERNAME, (SimNao $isAdmin))
    Linha ('Usuário da sessão  : {0}' -f $usuarioSessao)
    if ($usuarioSessao -and -not ($usuarioSessao -like "*\$env:USERNAME")) {
        Linha "ATENÇÃO: o script rodou com um usuário diferente do logado. Certificados e Firefox abaixo são do usuário '$env:USERNAME'."
        Resumo "ATENÇÃO: script rodou como '$env:USERNAME', mas a sessão é de '$usuarioSessao' (itens de usuário podem estar errados)"
    }

    if ($os) {
        $nomeWin = $os.Caption
        Linha ('Windows            : {0}  {1}' -f $os.Caption, $cv.DisplayVersion)
        Linha ('Arquitetura        : {0}' -f $os.OSArchitecture)
        Linha ('Instalado em       : {0}' -f $os.InstallDate)
        Linha ('Último boot        : {0}' -f $os.LastBootUpTime)
    } else {
        $nomeWin = $cv.ProductName
        Linha 'ATENÇÃO: não foi possível consultar o WMI (Win32_OperatingSystem).'
        Resumo 'ATENÇÃO: consulta ao WMI falhou (serviço WMI pode estar com problema)'
        Linha ('Windows            : {0}  {1}' -f $cv.ProductName, $cv.DisplayVersion)
    }
    Linha ('Build              : {0}.{1}' -f $cv.CurrentBuild, $cv.UBR)
    Linha ('Idioma             : interface={0}  formatos={1}  sistema={2}' -f (Get-UICulture).Name, (Get-Culture).Name, (Get-WinSystemLocale).Name)
    Resumo ('Windows: {0} {1} - build {2}.{3}' -f $nomeWin, $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR)
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
Secao '2. WMIC (principal suspeito)'
try {
    $wmic64 = Join-Path $env:windir 'System32\wbem\WMIC.exe'
    $wmic32 = Join-Path $env:windir 'SysWOW64\wbem\WMIC.exe'
    $tem64 = Test-Path $wmic64
    $tem32 = Test-Path $wmic32
    Linha ('WMIC 64 bits ({0}): {1}' -f $wmic64, $(if ($tem64) { 'PRESENTE' } else { 'AUSENTE' }))
    Linha ('WMIC 32 bits ({0}): {1}' -f $wmic32, $(if ($tem32) { 'PRESENTE' } else { 'AUSENTE' }))
    if ($tem64) {
        $teste = cmd.exe /c "$wmic64 os get Caption,Version /value < nul 2>&1" | Out-String
        Linha 'Teste "wmic os get Caption,Version":'
        Linha ('  ' + (Encurtar $teste 300))
    }
    $cmd32 = Join-Path $env:windir 'SysWOW64\cmd.exe'
    if (Test-Path $cmd32) {
        $t32 = & $cmd32 /c "wmic os get Caption /value < nul 2>&1" | Out-String
        $ok32 = $t32 -match 'Caption='
        Linha ('Teste do WMIC visto por programas 32 bits (Firefox x86, assinador): {0}' -f $(if ($ok32) { 'OK' } else { 'FALHOU' }))
        Linha ('  ' + (Encurtar $t32 200))
        Resumo ('WMIC para programas 32 bits (Firefox x86 / assinador): {0}' -f $(if ($ok32) { 'OK' } else { 'NÃO funciona  <-- pode derrubar o assinador quando chamado pelo Firefox' }))
    }
    if ($isAdmin) {
        $cap = Get-WindowsCapability -Online -Name 'WMIC*'
        if ($cap) {
            Tabela ($cap | Select-Object Name, State)
            if (($cap | Where-Object { $_.State -eq 'Installed' }) -and -not $tem64) {
                Linha "OBS: o recurso WMIC consta como 'Installed', mas o WMIC.exe não existe: foi removido pela atualização do Windows."
            }
        }
        else { Linha 'Recurso opcional WMIC: não aparece mais na lista do Windows.' }
    } else {
        Linha 'Recurso opcional WMIC: não verificado (precisa rodar como administrador).'
    }
    $svcWmi = Get-Service -Name Winmgmt
    Linha ('Serviço WMI (Winmgmt): {0} / {1}' -f $svcWmi.Status, $svcWmi.StartType)
    Resumo ('WMIC: {0}' -f $(if ($tem64) { 'PRESENTE' } else { 'AUSENTE   <-- provável causa' }))
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
Secao '3. ATUALIZAÇÕES RECENTES DO WINDOWS'
try {
    $sessao = New-Object -ComObject Microsoft.Update.Session
    $busca  = $sessao.CreateUpdateSearcher()
    $total  = $busca.GetTotalHistoryCount()
    if ($total -gt 0) {
        $hist = $busca.QueryHistory(0, [Math]::Min(25, $total)) | Where-Object { $_.Title } | ForEach-Object {
            $res = switch ($_.ResultCode) { 1 { 'Em andamento' } 2 { 'OK' } 3 { 'OK c/ erros' } 4 { 'FALHOU' } 5 { 'Abortado' } default { $_ } }
            [pscustomobject]@{ Data = $_.Date.ToLocalTime().ToString('dd/MM/yyyy HH:mm'); Resultado = $res; Atualizacao = $_.Title }
        }
        Tabela $hist
    } else {
        Linha 'Histórico do Windows Update vazio. Usando Get-HotFix:'
        Tabela (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 15 HotFixID, Description, InstalledOn)
    }
} catch {
    Linha 'Histórico do Windows Update indisponível. Usando Get-HotFix:'
    Tabela (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 15 HotFixID, Description, InstalledOn)
}

# ---------------------------------------------------------------------------
Secao '4. PROGRAMAS RELACIONADOS INSTALADOS'
try {
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $programas = Get-ItemProperty -Path $chaves |
        Where-Object { $_.DisplayName -and (('{0} {1}' -f $_.DisplayName, $_.Publisher) -match $padraoProgramas) } |
        Select-Object @{n='Programa';e={$_.DisplayName}}, @{n='Versao';e={$_.DisplayVersion}}, @{n='Fabricante';e={$_.Publisher}}, @{n='InstaladoEm';e={$_.InstallDate}}, @{n='Pasta';e={$_.InstallLocation}} |
        Sort-Object Programa, Versao -Unique
    Tabela $programas

    $progAssinador  = @($programas | Where-Object { $_.Programa -match $padraoAssinador })
    $progMiddleware = @($programas | Where-Object { $_.Programa -match 'safenet|safesign|gemalto|thales|watchdata|epass|feitian|starsign|certisign|dexon|dxsafe|token' })
    $progKasp       = @($programas | Where-Object { $_.Programa -match 'kaspersky' })

    Resumo ('Assinador instalado: {0}' -f $(if ($progAssinador.Count) { ($progAssinador | ForEach-Object { "$($_.Programa) $($_.Versao)" }) -join '; ' } else { 'NÃO encontrado na lista de programas' }))
    Resumo ('Driver/gerenciador do token: {0}' -f $(if ($progMiddleware.Count) { ($progMiddleware | ForEach-Object { "$($_.Programa) $($_.Versao)" }) -join '; ' } else { 'NÃO encontrado' }))
    Resumo ('Kaspersky: {0}' -f $(if ($progKasp.Count) { ($progKasp | ForEach-Object { "$($_.Programa) $($_.Versao)" }) -join '; ' } else { 'não encontrado na lista de programas' }))
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
Secao '5. ASSINADOR: ATALHOS, PASTAS E LOGS'
$pastasAssinador = @()
try {
    $listaPastas = New-Object System.Collections.Generic.List[string]
    $shell = New-Object -ComObject WScript.Shell
    $locais = @('Desktop', 'CommonDesktopDirectory', 'Programs', 'CommonPrograms', 'Startup', 'CommonStartup') |
        ForEach-Object { [Environment]::GetFolderPath($_) } | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    $atalhos = foreach ($l in $locais) {
        Get-ChildItem -Path $l -Recurse -Filter '*.lnk' -Force | Where-Object { $_.BaseName -match "$padraoAssinador|token|safenet|safesign|certisign" }
    }
    if (-not $atalhos) { Linha 'Atalhos: nenhum atalho do assinador/token encontrado.' }
    foreach ($a in $atalhos) {
        $lnk = $shell.CreateShortcut($a.FullName)
        Linha "Atalho      : $($a.FullName)"
        Linha "  Alvo      : $($lnk.TargetPath)"
        Linha "  Argumentos: $($lnk.Arguments)"
        Linha "  Iniciar em: $($lnk.WorkingDirectory)"
        Linha ''
        if ($a.BaseName -match $padraoAssinador) {
            if ($lnk.WorkingDirectory -and (Test-Path $lnk.WorkingDirectory)) { $listaPastas.Add($lnk.WorkingDirectory) }
            if ($lnk.Arguments -match '-jar\s+"?([^"]+?\.jar)') {
                $dirJar = Split-Path $matches[1] -Parent
                if ($dirJar -and (Test-Path $dirJar)) { $listaPastas.Add($dirJar) }
            }
            if ($lnk.TargetPath -and ($lnk.TargetPath -notmatch '\\java(w)?\.exe$')) {
                $dirAlvo = Split-Path $lnk.TargetPath -Parent
                if ($dirAlvo -and (Test-Path $dirAlvo)) { $listaPastas.Add($dirAlvo) }
            }
        }
    }

    foreach ($p in $progAssinador) { if ($p.Pasta -and (Test-Path $p.Pasta)) { $listaPastas.Add($p.Pasta) } }

    $raizes = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'), "$env:SystemDrive\", $env:APPDATA, $env:LOCALAPPDATA, $env:USERPROFILE, $env:ProgramData)
    foreach ($r in $raizes) {
        if ($r -and (Test-Path $r)) {
            Get-ChildItem -Path $r -Directory -Force | Where-Object { $_.Name -match $padraoAssinador } | ForEach-Object { $listaPastas.Add($_.FullName) }
        }
    }
    $jars = New-Object System.Collections.Generic.List[string]
    $raizesJar = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, $env:APPDATA, $env:ProgramData, [Environment]::GetFolderPath('Desktop'), (Join-Path $env:USERPROFILE 'Downloads'))
    foreach ($r in $raizesJar) {
        if ($r -and (Test-Path $r)) {
            Get-ChildItem -Path $r -Recurse -Depth 3 -Filter 'assinador-ccasj.jar' -File -Force | ForEach-Object { $jars.Add($_.FullName); $listaPastas.Add($_.DirectoryName) }
        }
    }
    $jars = @($jars | Sort-Object -Unique)
    Linha ('assinador-ccasj.jar: {0}' -f $(if ($jars.Count) { $jars -join '; ' } else { 'NÃO encontrado' }))
    Resumo ('Programa do assinador (assinador-ccasj.jar): {0}' -f $(if ($jars.Count) { $jars -join '; ' } else { 'NÃO encontrado  <-- assinador não está instalado' }))
    Linha ''

    $pastasAssinador = @($listaPastas | ForEach-Object { $_.TrimEnd('\') } | Sort-Object -Unique)

    if (-not $pastasAssinador.Count) { Linha 'Pastas: nenhuma pasta do assinador encontrada.' }
    foreach ($pasta in $pastasAssinador) {
        Linha "Pasta: $pasta"
        $itens = Get-ChildItem -Path $pasta -Force | Select-Object -First 40
        Tabela ($itens | Select-Object Mode, @{n='Modificado';e={$_.LastWriteTime.ToString('dd/MM/yyyy HH:mm')}}, @{n='Tamanho';e={$_.Length}}, Name)
        Linha ''
    }

    # Inicializadores (.bat/.cmd/.vbs) e arquivos de configuracao: mostra o conteudo e destaca WMIC
    $arqsInit = New-Object System.Collections.Generic.List[object]
    foreach ($pasta in $pastasAssinador) {
        Get-ChildItem -Path $pasta -Recurse -Depth 2 -File -Force -Include '*.bat', '*.cmd', '*.vbs', '*.ps1', '*.ini', '*.cfg', '*.properties', '*.conf' |
            Where-Object { $_.Length -lt 60KB -and $_.FullName -notmatch '\\(java32|java64|jre[^\\]*)\\' } | ForEach-Object { $arqsInit.Add($_) }
    }
    foreach ($a in $atalhos) {
        $alvoLnk = $shell.CreateShortcut($a.FullName).TargetPath
        if ($alvoLnk -match '\.(bat|cmd|vbs)$' -and (Test-Path $alvoLnk)) { $arqsInit.Add((Get-Item $alvoLnk)) }
    }
    $arqsInit = @($arqsInit | Sort-Object FullName -Unique | Select-Object -First 12)
    $initComWmic = @()
    $initCorrigidos = @()
    foreach ($ai in $arqsInit) {
        if ((Get-Content -Path $ai.FullName -Raw) -match 'CORRECAO-WMIC') { $initCorrigidos += $ai.Name }
        Linha ''
        Linha "----- Conteúdo de: $($ai.FullName)"
        $n = 0
        foreach ($l in (Get-Content -Path $ai.FullName -TotalCount 250)) {
            $n++
            if ($l -match 'wmic' -and $l -notmatch '^\s*(rem\b|::)') {
                Linha ('  >>> WMIC >>> {0,3}: {1}' -f $n, (Mascarar $l))
                if ($initComWmic -notcontains $ai.FullName) { $initComWmic += $ai.FullName }
            } else {
                Linha ('  {0,3}: {1}' -f $n, (Mascarar $l))
            }
        }
    }
    if ($initComWmic.Count) {
        Resumo ('Inicializador do assinador USA WMIC: {0}  <-- causa provável (ver seção 5)' -f ($initComWmic -join '; '))
    } elseif ($initCorrigidos.Count) {
        Resumo ('Inicializadores do assinador CORRIGIDOS (não dependem mais do WMIC): {0}' -f ($initCorrigidos -join ', '))
    } elseif ($arqsInit.Count) {
        Resumo 'Inicializador do assinador: encontrado, sem chamada ao WMIC'
    } else {
        Resumo 'Inicializador do assinador (.bat/.cmd): NÃO encontrado'
    }

    $logs = New-Object System.Collections.Generic.List[object]
    foreach ($pasta in $pastasAssinador) {
        Get-ChildItem -Path $pasta -Recurse -Depth 4 -File -Force -Include '*.log', '*.txt', '*.out', '*.err' |
            Where-Object { $_.FullName -notmatch '\\(java32|java64|jre[^\\]*)\\' -and $_.Name -notlike 'diagnostico-assinador*' } | ForEach-Object { $logs.Add($_) }
    }
    foreach ($l in @($env:USERPROFILE, [Environment]::GetFolderPath('Desktop'), $env:TEMP, $env:APPDATA, $env:LOCALAPPDATA)) {
        if ($l -and (Test-Path $l)) {
            Get-ChildItem -Path $l -File -Force |
                Where-Object { $_.Name -like 'hs_err_pid*' -or ($_.Name -match $padraoAssinador -and $_.Extension -in '.log', '.txt' -and $_.Name -notlike 'diagnostico-assinador*') } |
                ForEach-Object { $logs.Add($_) }
        }
    }
    $logs = @($logs | Sort-Object FullName -Unique | Sort-Object LastWriteTime -Descending)

    if ($logs.Count) {
        Linha 'Arquivos de log encontrados (mais recentes primeiro):'
        Tabela ($logs | Select-Object -First 15 @{n='Modificado';e={$_.LastWriteTime.ToString('dd/MM/yyyy HH:mm')}}, Length, FullName)
        foreach ($lg in ($logs | Select-Object -First 3)) {
            Linha ''
            Linha "----- Últimas 80 linhas de: $($lg.FullName)"
            Get-Content -Path $lg.FullName -Tail 80 | ForEach-Object { Linha ('  ' + (Mascarar $_)) }
        }
        $logAss = $logs | Where-Object { $_.Name -eq 'assinador.log' } | Select-Object -First 1
        if ($logAss) {
            $txtLog = Get-Content -Path $logAss.FullName -Raw
            if ($txtLog -match 'Rodando em ([^\r\n]+)') {
                Resumo ('assinador.log (última gravação {0}): rodando em {1}' -f $logAss.LastWriteTime.ToString('dd/MM HH:mm'), $matches[1].Trim())
            }
            if ($txtLog -match 'ParametroNaoDefinidoException') {
                Resumo 'assinador.log: o programa foi aberto no modo "Addon" SEM parâmetros (jeito errado de abrir) e fechou  <-- ver seção 5'
            }
            $qtdErros = ([regex]::Matches($txtLog, '\[ERROR\]')).Count
            if ($qtdErros) { Resumo "assinador.log: $qtdErros linha(s) de erro [ERROR]" }
        }
    } else {
        Linha 'Logs: nenhum arquivo de log do assinador encontrado.'
    }
    $hsErr = @($logs | Where-Object { $_.Name -like 'hs_err_pid*' })
    if ($hsErr.Count) { Resumo "Java: $($hsErr.Count) arquivo(s) de travamento do Java (hs_err_pid) encontrado(s)" }
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
Secao '6. JAVA'
try {
    $javaPath = Get-Command java.exe -All
    if ($javaPath) { foreach ($j in $javaPath) { Linha "java.exe no PATH: $($j.Source)" } }
    else { Linha 'java.exe no PATH: NÃO encontrado' }

    $javaVer = cmd.exe /c 'java -version 2>&1' | Out-String
    Linha 'Saída de "java -version":'
    Linha ('  ' + (Encurtar $javaVer 400))
    Linha "JAVA_HOME: $env:JAVA_HOME"

    $locaisJava = @("$env:ProgramFiles\Java", "${env:ProgramFiles(x86)}\Java", "$env:ProgramFiles\Eclipse Adoptium", "$env:ProgramFiles\Zulu", "$env:ProgramFiles\Amazon Corretto", "$env:ProgramFiles\BellSoft") + $pastasAssinador
    $javas = foreach ($l in $locaisJava) {
        if ($l -and (Test-Path $l)) { Get-ChildItem -Path $l -Recurse -Depth 5 -Filter 'java.exe' -File }
    }
    $javas = @($javas | Sort-Object FullName -Unique)
    Linha 'Instalações de Java encontradas:'
    Tabela ($javas | Select-Object @{n='Versao';e={$_.VersionInfo.ProductVersion}}, FullName)
    $versoesJava = @($javas | ForEach-Object { $_.VersionInfo.ProductVersion })
    $antigo = @($versoesJava | Where-Object { $_ -match '^(6|7)\.' })
    Resumo ('Java: {0}{1}' -f $(if ($javas.Count) { $versoesJava -join ', ' } else { 'nenhuma instalação encontrada' }), $(if ($antigo.Count) { '  <-- Java 6/7 é muito antigo e inseguro' } else { '' }))
    if ($javaVer -match 'não pode encontrar|cannot find') { Resumo 'Java: o atalho "javapath" no PATH está quebrado (sobra de Java desinstalado)' }
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
Secao '7. PROCESSOS E PORTAS LOCAIS'
try {
    $procs = Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'java|javaw|assinador|comaer|signer' }
    Linha 'Processos do assinador/Java rodando agora:'
    Tabela ($procs | Select-Object ProcessId, Name, @{n='LinhaDeComando';e={ Mascarar (Encurtar $_.CommandLine 300) }})

    $ignorar = @('System', 'svchost', 'lsass', 'wininit', 'services', 'spoolsv', 'Idle')
    $escuta = Get-NetTCPConnection -State Listen |
        Where-Object { $_.LocalAddress -in '127.0.0.1', '::1', '0.0.0.0', '::' } |
        ForEach-Object {
            $p = Get-Process -Id $_.OwningProcess
            [pscustomobject]@{ Porta = $_.LocalPort; Endereco = $_.LocalAddress; PID = $_.OwningProcess; Processo = $p.ProcessName }
        } |
        Where-Object { $_.Processo -notin $ignorar } |
        Sort-Object Porta, Processo -Unique
    Linha ''
    Linha 'Portas escutando nesta máquina (sem serviços básicos do Windows):'
    Tabela $escuta
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
Secao '8. TOKEN / LEITORA DE CARTÃO'
try {
    foreach ($s in 'SCardSvr', 'ScDeviceEnum', 'CertPropSvc') {
        $x = Get-Service -Name $s
        if ($x) { Linha ('Serviço {0,-13}: {1,-8} / {2,-9} ({3})' -f $s, $x.Status, $x.StartType, $x.DisplayName) }
        else { Linha "Serviço $s : não encontrado" }
    }
    $dispositivos = Get-PnpDevice -PresentOnly | Where-Object { ($_.Class -match 'SmartCard' -or $_.FriendlyName -match $padraoToken) -and $_.InstanceId -notlike 'SWD\SCDEVICEENUMBUS*' }
    Linha ''
    Linha 'Dispositivos de token/cartão conectados agora:'
    Tabela ($dispositivos | Select-Object Status, Class, FriendlyName, InstanceId)
    $tokenOk = @($dispositivos | Where-Object { $_.Status -eq 'OK' })
    Resumo ('Token/leitora conectado e OK: {0}' -f $(if ($tokenOk.Count) { "SIM ($(($tokenOk | ForEach-Object { $_.FriendlyName }) -join '; '))" } else { 'NÃO detectado  <-- o token estava conectado? Se estava, o Windows não o reconheceu' }))

    Linha ''
    Linha 'Bibliotecas de token conhecidas (lista não exaustiva):'
    $achouDll = $false
    foreach ($d in 'aetpkss1.dll', 'DXSafePKCS11.dll', 'DXSafeCSP.dll', 'eps2003csp11.dll', 'eTPKCS11.dll', 'WDPKCS.dll', 'asepkcs.dll') {
        foreach ($dir in @("$env:windir\System32", "$env:windir\SysWOW64")) {
            $caminho = Join-Path $dir $d
            if (Test-Path $caminho) { Linha "  Encontrada: $caminho  (versão $((Get-Item $caminho).VersionInfo.ProductVersion))"; $achouDll = $true }
        }
    }
    if (-not $achouDll) { Linha '  nenhuma da lista encontrada' }
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
Secao '9. CERTIFICADOS DIGITAIS'
try {
    $agora = Get-Date
    $tabCert = Get-ChildItem Cert:\CurrentUser\My | ForEach-Object {
        $cn = if ($_.Subject -match 'CN=([^,]+)') { $matches[1] } else { $_.Subject }
        $em = if ($_.Issuer -match 'CN=([^,]+)') { $matches[1] } else { $_.Issuer }
        $sit = if ($_.NotAfter -lt $agora) { 'VENCIDO' } elseif ($_.NotBefore -gt $agora) { 'AINDA NAO VALIDO' } else { 'valido' }
        [pscustomobject]@{ Titular = (Mascarar $cn); Emissor = $em; ValidoAte = $_.NotAfter.ToString('dd/MM/yyyy'); Situacao = $sit; ChavePrivada = $_.HasPrivateKey }
    }
    Linha 'Certificados pessoais do usuário (Cert:\CurrentUser\My):'
    Tabela $tabCert
    $validos = @($tabCert | Where-Object { $_.ChavePrivada -and $_.Situacao -eq 'valido' })
    $vencidos = @($tabCert | Where-Object { $_.Situacao -eq 'VENCIDO' })
    Resumo ('Certificados válidos com chave privada: {0}   vencidos: {1}' -f $validos.Count, $vencidos.Count)

    $cadeia = Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root, Cert:\LocalMachine\CA, Cert:\CurrentUser\CA |
        Where-Object { $_.Subject -match 'ICP-Brasil|Certisign' } |
        ForEach-Object {
            $nome = if ($_.Subject -match 'CN=([^,]+)') { $matches[1] } else { $_.Subject }
            [pscustomobject]@{ Repositorio = ($_.PSParentPath -replace '^.*::', ''); Nome = $nome; ValidoAte = $_.NotAfter.ToString('dd/MM/yyyy') }
        } | Sort-Object Repositorio, Nome -Unique
    Linha ''
    Linha 'Cadeia ICP-Brasil / Certisign instalada:'
    Tabela $cadeia
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
Secao '10. ANTIVÍRUS / KASPERSKY'
try {
    $av = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct
    Linha 'Antivírus registrados no Windows:'
    Tabela ($av | Select-Object displayName, @{n='Ativo';e={ SimNao (($_.productState -band 0x1000) -ne 0) }}, productState, pathToSignedReportingExe)
    $avAtivos = @($av | Where-Object { ($_.productState -band 0x1000) -ne 0 } | ForEach-Object { $_.displayName })
    $avInativos = @($av | Where-Object { ($_.productState -band 0x1000) -eq 0 } | ForEach-Object { $_.displayName })
    Resumo ('Antivírus ativo: {0}{1}' -f $(if ($avAtivos.Count) { $avAtivos -join ', ' } else { 'NENHUM' }), $(if ($avInativos.Count) { "   (desativado: $($avInativos -join ', '))" } else { '' }))

    $svcKasp = Get-Service | Where-Object { $_.DisplayName -match 'Kaspersky' -or $_.Name -match '^(avp|klnagent|kavfs)' }
    Linha ''
    Linha 'Serviços do Kaspersky:'
    Tabela ($svcKasp | Select-Object Name, DisplayName, Status)

    $logsKasp = Get-WinEvent -ListLog '*Kaspersky*'
    foreach ($lk in $logsKasp) {
        Linha ''
        Linha "Log de eventos '$($lk.LogName)' - eventos dos últimos 14 dias ligados a assinador/Java/token/WMIC:"
        $evK = Get-WinEvent -FilterHashtable @{ LogName = $lk.LogName; StartTime = (Get-Date).AddDays(-14) } -MaxEvents 3000 |
            Where-Object { $_.Message -match $padraoLogs } |
            Select-Object -First 20 @{n='Data';e={$_.TimeCreated.ToString('dd/MM HH:mm')}}, Id, @{n='Mensagem';e={ Mascarar (Encurtar $_.Message 300) }}
        Tabela $evK
        if (@($evK).Count) { Resumo "Kaspersky: $(@($evK).Count) evento(s) recente(s) citando assinador/Java/token/WMIC  <-- conferir seção 10" }
    }
    if (-not $logsKasp) { Linha 'Log de eventos do Kaspersky: não encontrado ou sem permissão (rode como administrador).' }
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
Secao '11. FIREFOX E EXTENSÃO DO ASSINADOR'
try {
    foreach ($chave in 'HKLM:\SOFTWARE\Mozilla\Mozilla Firefox', 'HKLM:\SOFTWARE\WOW6432Node\Mozilla\Mozilla Firefox', 'HKCU:\SOFTWARE\Mozilla\Mozilla Firefox', 'HKLM:\SOFTWARE\Mozilla\Firefox Developer Edition', 'HKCU:\SOFTWARE\Mozilla\Firefox Developer Edition') {
        $v = (Get-ItemProperty -Path $chave).CurrentVersion
        if ($v) { Linha "Registro ($chave): $v" }
    }
    $ffEncontrado = $false
    foreach ($dirFf in @("$env:ProgramFiles\Mozilla Firefox", "${env:ProgramFiles(x86)}\Mozilla Firefox", "$env:LOCALAPPDATA\Mozilla Firefox", "$env:ProgramFiles\Firefox Developer Edition", "${env:ProgramFiles(x86)}\Firefox Developer Edition")) {
        $exe = Join-Path $dirFf 'firefox.exe'
        if (Test-Path $exe) {
            $ffEncontrado = $true
            $canal = Select-String -Path (Join-Path $dirFf 'defaults\pref\channel-prefs.js') -Pattern 'app\.update\.channel' | Select-Object -First 1
            $nomeCanal = if ($canal) { $canal.Line -replace '.*"app\.update\.channel"\s*,\s*"([^"]+)".*', '$1' } else { 'desconhecido' }
            $verFf = (Get-Item $exe).VersionInfo.ProductVersion
            Linha ('Firefox: {0}  versão {1}  canal: {2}' -f $exe, $verFf, $nomeCanal)
            $rotulo = switch ($nomeCanal) { 'aurora' { 'Developer Edition' } 'esr' { 'ESR' } 'nightly' { 'Nightly' } 'release' { 'comum' } default { $nomeCanal } }
            Resumo ('Firefox: versão {0} ({1}){2}' -f $verFf, $rotulo, $(if ($nomeCanal -notin 'esr', 'aurora', 'nightly') { '  <-- esta edição não aceita a extensão do assinador (não assinada)' } else { '' }))
        }
    }
    if (-not $ffEncontrado) { Linha 'Firefox: não encontrado nas pastas padrão.'; Resumo 'Firefox: NÃO encontrado' }

    Linha ''
    Linha 'Native Messaging (ligação extensão <-> programa do computador):'
    $achouNm = $false
    $nmAssinador = $false
    $nmAllowed = @()
    $hostUsaWmic = $false
    $hostCorrigido = $false
    foreach ($raiz in 'HKCU:\SOFTWARE\Mozilla\NativeMessagingHosts', 'HKLM:\SOFTWARE\Mozilla\NativeMessagingHosts', 'HKLM:\SOFTWARE\WOW6432Node\Mozilla\NativeMessagingHosts') {
        Get-ChildItem -Path $raiz | ForEach-Object {
            $achouNm = $true
            $nomeHost = $_.PSChildName
            $manifesto = (Get-ItemProperty -Path $_.PSPath).'(default)'
            $ok = $manifesto -and (Test-Path $manifesto)
            $m = $null
            if ($ok) { $m = Get-Content -Raw -Path $manifesto | ConvertFrom-Json }
            $ehAss = (('{0} {1} {2}' -f $nomeHost, $manifesto, (@($m.allowed_extensions) -join ' ')) -match 'comaer|assinador|ccasj|sigadaer')
            if ($ehAss) { $nmAssinador = $true; $nmAllowed += @($m.allowed_extensions) }
            Linha ('  {0}  ->  {1}  [{2}]{3}' -f $nomeHost, $manifesto, $(if ($ok) { 'manifesto existe' } else { 'MANIFESTO NÃO EXISTE' }), $(if ($ehAss) { '   <== ASSINADOR' } else { '' }))
            if ($ehAss -and -not $ok) { Resumo "Ligação do assinador registrada, mas o arquivo de manifesto NÃO EXISTE: $manifesto" }
            if ($m -and $m.path) {
                $alvo = $m.path
                if (-not [IO.Path]::IsPathRooted($alvo)) { $alvo = Join-Path (Split-Path $manifesto -Parent) $alvo }
                $existe = Test-Path $alvo
                Linha ('      programa: {0}  [{1}]' -f $alvo, $(if ($existe) { 'existe' } else { 'NÃO EXISTE' }))
                if ($ehAss) {
                    Linha '      conteúdo do manifesto:'
                    Get-Content -Path $manifesto -TotalCount 40 | ForEach-Object { Linha ('        ' + $_) }
                    if ($existe -and $alvo -match '\.(bat|cmd|vbs|ps1)$') {
                        Linha '      conteúdo do programa que o Firefox chama:'
                        $n = 0
                        foreach ($l in (Get-Content -Path $alvo -TotalCount 200)) {
                            $n++
                            if ($l -match 'CORRECAO-WMIC') { $hostCorrigido = $true }
                            if ($l -match 'wmic' -and $l -notmatch '^\s*(rem\b|::)') { Linha ('      >>> WMIC >>> {0,3}: {1}' -f $n, (Mascarar $l)); $hostUsaWmic = $true }
                            else { Linha ('        {0,3}: {1}' -f $n, (Mascarar $l)) }
                        }
                    } elseif ($existe) {
                        Linha ('      tipo: {0}   versão: {1}' -f [IO.Path]::GetExtension($alvo), (Get-Item $alvo).VersionInfo.ProductVersion)
                    }
                    if (-not $existe) { Resumo "Programa que o Firefox chama para assinar NÃO EXISTE: $alvo" }
                }
            }
        }
    }
    if (-not $achouNm) { Linha '  nenhum registro encontrado' }
    Resumo ('Ligação Firefox <-> assinador (native messaging): {0}' -f $(if ($nmAssinador) { 'registrada' + $(if ($hostUsaWmic) { '  (o programa que o Firefox chama USA WMIC)' } elseif ($hostCorrigido) { '  (programa corrigido, sem WMIC)' } else { '' }) } else { 'NÃO registrada  <-- a extensão não tem com quem falar (assinador não instalado ou instalação incompleta)' }))

    $perfisEmUso = @()
    $iniInst = Join-Path $env:APPDATA 'Mozilla\Firefox\installs.ini'
    if (Test-Path $iniInst) {
        $perfisEmUso = @(Select-String -Path $iniInst -Pattern '^Default=(.+)$' | ForEach-Object { ($_.Matches[0].Groups[1].Value -replace '^Profiles/', '').Trim() })
        Linha ''
        Linha ('Perfil padrão de cada Firefox instalado (installs.ini): {0}' -f ($perfisEmUso -join ', '))
    }
    $perfis = Get-ChildItem -Path (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles') -Directory
    if (-not $perfis) { Linha ''; Linha 'Perfis do Firefox: nenhum encontrado para este usuário.' }
    foreach ($pf in $perfis) {
      try {
        Linha ''
        $emUso = $perfisEmUso -contains $pf.Name
        Linha ("Perfil: $($pf.Name)  (modificado em $($pf.LastWriteTime.ToString('dd/MM/yyyy HH:mm')))" + $(if ($emUso) { '   <== PERFIL EM USO' } else { '' }))
        $prefs = Join-Path $pf.FullName 'prefs.js'
        if (-not (Test-Path $prefs)) { Linha '  (perfil vazio, sem prefs.js - não é o perfil em uso)'; continue }
        foreach ($pref in 'xpinstall.signatures.required', 'extensions.blocklist.enabled', 'security.enterprise_roots.enabled') {
            $lp = Select-String -Path $prefs -SimpleMatch -Pattern ('"' + $pref + '"') | Select-Object -First 1
            Linha ('  {0,-36}: {1}' -f $pref, $(if ($lp) { $lp.Line.Trim() } else { '(não definido = padrão do Firefox)' }))
        }
        $extJson = Join-Path $pf.FullName 'extensions.json'
        if (Test-Path $extJson) {
            $addons = (Get-Content -Path $extJson -Raw -Encoding UTF8 | ConvertFrom-Json).addons |
                Where-Object { $_.type -eq 'extension' -and $_.location -notmatch 'app-builtin|app-system' }
            Linha '  Extensões instaladas:'
            Tabela ($addons | Select-Object @{n='Extensao';e={$_.defaultLocale.name}}, @{n='Versao';e={$_.version}}, @{n='Ativa';e={$_.active}}, @{n='DesativadaPeloUsuario';e={$_.userDisabled}}, @{n='BloqueadaPeloFirefox';e={$_.appDisabled}}, @{n='Assinatura';e={$_.signedState}}, @{n='Id';e={$_.id}})
            $extAss = @($addons | Where-Object { ('{0} {1}' -f $_.defaultLocale.name, $_.id) -match "$padraoAssinador|certisign|bry|lacuna|pki" })
            if ($extAss.Count) {
                if ($perfisEmUso.Count -eq 0 -or $emUso) {
                    foreach ($e in $extAss) {
                        $autorizada = (-not $nmAssinador) -or ($nmAllowed -contains $e.id)
                        Resumo ('Extensão "{0}" v{1} no perfil {2}{3}: ativa={4}, bloqueada pelo Firefox={5}{6}' -f $e.defaultLocale.name, $e.version, $pf.Name, $(if ($emUso) { ' (EM USO)' } else { '' }), $e.active, $e.appDisabled, $(if ($autorizada) { '' } else { "  <-- o ID $($e.id) NÃO está autorizado no manifesto do assinador" }))
                    }
                }
            } elseif ($perfisEmUso.Count -eq 0 -or $emUso) {
                Resumo "Extensão do assinador: NÃO encontrada no perfil $($pf.Name)"
            }
        }
        $pk = Join-Path $pf.FullName 'pkcs11.txt'
        if (Test-Path $pk) {
            Select-String -Path $pk -Pattern '^(library|name)=' | ForEach-Object { Linha "  pkcs11.txt: $($_.Line)" }
        }
      } catch { Linha "  ERRO ao ler o perfil $($pf.Name): $($_.Exception.Message)" }
    }
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
Secao '12. ERROS RECENTES NO VISUALIZADOR DE EVENTOS (14 dias)'
try {
    $inicio = (Get-Date).AddDays(-14)
    $evApp = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Level = 1, 2, 3; StartTime = $inicio } -MaxEvents 5000 |
        Where-Object { $_.Message -match $padraoLogs } |
        Select-Object -First 30 @{n='Data';e={$_.TimeCreated.ToString('dd/MM HH:mm')}}, @{n='Origem';e={$_.ProviderName}}, Id, @{n='Mensagem';e={ Mascarar (Encurtar $_.Message 350) }}
    Linha 'Eventos ligados a assinador/Java/token/WMIC:'
    Tabela $evApp

    $crashes = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; StartTime = $inicio } -MaxEvents 20 |
        Select-Object @{n='Data';e={$_.TimeCreated.ToString('dd/MM HH:mm')}}, Id, @{n='Mensagem';e={ Mascarar (Encurtar $_.Message 250) }}
    Linha ''
    Linha 'Travamentos de programas (qualquer programa):'
    Tabela $crashes
} catch { Linha "  ERRO nesta seção: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
$cabecalho = @(
    ('#' * 78),
    ' DIAGNÓSTICO DO ASSINADOR DIGITAL + TOKEN',
    (' Gerado em {0} no computador {1}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm'), $env:COMPUTERNAME),
    ' Somente leitura: nada foi alterado na máquina. CPF/CNPJ mascarados.',
    ('#' * 78),
    '',
    ' RESUMO RÁPIDO',
    (' ' + ('-' * 40))
)
$final = @($cabecalho) + @($script:Resumo | ForEach-Object { " * $_" }) + @($script:Relatorio)

$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path $desktop)) { $desktop = $env:USERPROFILE }
$arquivo = Join-Path $desktop ('diagnostico-assinador_{0}_{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm'))
$final | Set-Content -Path $arquivo -Encoding UTF8

Write-Host ''
Write-Host 'Pronto! Relatório salvo em:' -ForegroundColor Green
Write-Host "  $arquivo" -ForegroundColor Green
Start-Process -FilePath notepad.exe -ArgumentList ('"{0}"' -f $arquivo)
