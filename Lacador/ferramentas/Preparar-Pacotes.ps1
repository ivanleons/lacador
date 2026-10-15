<#
===============================================================================
  LAÇADOR - Colocar os instaladores dentro do Lacador.exe
===============================================================================
  Para que serve
    O Lacador.exe pode chegar "pequeno", sem os instaladores (uns 375 MB).
    Este script pega o pacote da ATIC (o arquivo TOKENS.rar, ou a pasta onde
    ele foi extraído), acha os instaladores lá dentro, mesmo os que estão em
    .zip/.rar internos, confere cada um pelo SHA-256 do catálogo e monta o
    Lacador-completo.exe: o mesmo programa, agora com tudo dentro.

  Não instala nada e não precisa de administrador.

  Uso
    Pela tela: página Diagnóstico > "Montar o Laçador completo".
    Pela linha de comando:
      Lacador.exe /montar
      Lacador.exe /montar -Origem "D:\Downloads\TOKENS.rar"
      Lacador.exe /montar -Origem "D:\TOKENS" -Saida "E:\Lacador.exe"

  Sem -Montar, o script só junta os instaladores numa pasta (-Destino).

  Para abrir arquivos .rar ele usa, nesta ordem, o que existir no computador:
  7-Zip, WinRAR ou o tar.exe do próprio Windows 10/11.
===============================================================================
#>
param(
    [string]$Origem = '',
    [string]$Destino = '',
    [switch]$Montar,
    [string]$Recipiente = '',
    [string]$Saida = '',
    [switch]$Silencioso,
    [switch]$Pausar
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$noWindows = ($env:OS -eq 'Windows_NT')
if ($Montar -and -not $Recipiente) { $Recipiente = [string]$env:LACADOR_EXE }
if ($Recipiente) { $Montar = $true }
if (-not $Montar -and -not $Destino) { $Destino = Join-Path $raiz 'pacotes' }

function Write-Passo {
    param([string]$Texto, [string]$Cor = 'Gray')
    if (-not $Silencioso) { Write-Host $Texto -ForegroundColor $Cor }
}
function Exit-Script {
    param([int]$Codigo)
    if ($Pausar -and -not $Silencioso) { Write-Host ''; $null = Read-Host 'Pressione Enter para fechar' }
    exit $Codigo
}

function Select-Origem {
    # Janela para escolher o arquivo do pacote; se cancelar, oferece escolher uma pasta.
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Title = 'Laçador: escolha o pacote com os instaladores (TOKENS.rar)'
    $d.Filter = 'Pacote (*.rar;*.zip;*.7z)|*.rar;*.zip;*.7z|Todos os arquivos|*.*'
    if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $d.FileName }
    $p = New-Object System.Windows.Forms.FolderBrowserDialog
    $p.Description = 'Ou escolha a pasta onde os instaladores já estão (pode ter subpastas)'
    if ($p.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $p.SelectedPath }
    return ''
}

function Get-Extratores {
    $r = New-Object System.Collections.Generic.List[object]
    if ($noWindows) {
        $pf = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
        foreach ($b in $pf) { $x = Join-Path $b '7-Zip\7z.exe'; if (Test-Path -LiteralPath $x) { $r.Add(@{ nome = '7-Zip'; exe = $x; args = @('x', '-y') }) } }
        foreach ($b in $pf) { $x = Join-Path $b 'WinRAR\UnRAR.exe'; if (Test-Path -LiteralPath $x) { $r.Add(@{ nome = 'WinRAR'; exe = $x; args = @('x', '-o+', '-y') }) } }
        foreach ($b in $pf) { $x = Join-Path $b 'WinRAR\WinRAR.exe'; if (Test-Path -LiteralPath $x) { $r.Add(@{ nome = 'WinRAR'; exe = $x; args = @('x', '-ibck', '-o+', '-y') }) } }
        $t = Join-Path $env:windir 'System32\tar.exe'
        if (Test-Path -LiteralPath $t) { $r.Add(@{ nome = 'tar do Windows'; exe = $t; args = @('-xf') }) }
    } else {
        foreach ($n in '7z', 'bsdtar') {
            $c = Get-Command $n -ErrorAction SilentlyContinue
            if ($c) { if ($n -eq '7z') { $r.Add(@{ nome = '7z'; exe = $c.Source; args = @('x', '-y') }) } else { $r.Add(@{ nome = 'bsdtar'; exe = $c.Source; args = @('-xf') }) } }
        }
    }
    return $r.ToArray()
}

function Expand-Pacote {
    # Extrai $Arquivo dentro de $Para. Devolve o nome da ferramenta que conseguiu, ou '' se nenhuma conseguiu.
    param([string]$Arquivo, [string]$Para)
    $ErrorActionPreference = 'Continue'
    if (-not (Test-Path -LiteralPath $Para)) { New-Item -ItemType Directory -Path $Para -Force | Out-Null }
    if ([IO.Path]::GetExtension($Arquivo) -ieq '.zip') {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($Arquivo, $Para)
            return 'Windows'
        } catch { }
    }
    foreach ($e in $script:Extratores) {
        Push-Location -LiteralPath $Para
        try {
            $lista = @($e.args) + @($Arquivo)
            $null = & $e.exe @lista 2>&1
            $ok = ($LASTEXITCODE -eq 0)
        } catch { $ok = $false } finally { Pop-Location }
        if ($ok -and @(Get-ChildItem -LiteralPath $Para -Recurse -File -Force -ErrorAction SilentlyContinue).Count) { return [string]$e.nome }
    }
    return ''
}

$script:Achados = New-Object System.Collections.Generic.List[object]
$script:NaoAbriu = New-Object System.Collections.Generic.List[string]
$script:Contador = 0

function Search-Pasta {
    param([string]$Pasta, [int]$Nivel)
    foreach ($f in @(Get-ChildItem -LiteralPath $Pasta -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $script:Achados.Add($f)
        $ext = $f.Extension.ToLowerInvariant()
        if ('.rar', '.zip', '.7z' -contains $ext -and $Nivel -lt 3 -and $f.Length -lt 2GB) {
            $script:Contador++
            $d = Join-Path $script:Trabalho ('{0:d2}' -f $script:Contador)
            Write-Passo ('  Abrindo {0} ...' -f $f.Name)
            $com = Expand-Pacote $f.FullName $d
            if ($com) { Search-Pasta $d ($Nivel + 1) } else { $script:NaoAbriu.Add($f.Name) }
        }
    }
}

# ---- montagem do executável completo -------------------------------------------------
# O Lacador.exe é o lançador seguido de um .zip SEM compressão. Aqui o .zip é reescrito com os
# instaladores dentro. Tudo à mão (cabeçalhos do formato ZIP), porque o lançador só lê entradas
# sem compressão e o .NET do Windows PowerShell 5.1 não grava assim.

function Read-Bytes {
    param($Fluxo, [long]$Posicao, [int]$Quantos)
    $b = New-Object byte[] $Quantos
    $null = $Fluxo.Seek($Posicao, [IO.SeekOrigin]::Begin)
    $lidos = 0
    while ($lidos -lt $Quantos) {
        $n = $Fluxo.Read($b, $lidos, $Quantos - $lidos)
        if ($n -le 0) { throw 'O Lacador.exe terminou antes da hora (arquivo incompleto).' }
        $lidos += $n
    }
    return , $b
}

function Get-EntradasBase {
    # Lê o diretório do .zip embutido no Lacador.exe. Devolve as entradas e onde o .zip começa.
    param($Fluxo)
    $tam = [long]$Fluxo.Length
    if ($tam -lt 22) { throw 'Este Lacador.exe não tem conteúdo.' }
    $nFim = [int][Math]::Min($tam, 65558)
    $fim = Read-Bytes $Fluxo ($tam - $nFim) $nFim
    $pos = -1
    for ($i = $nFim - 22; $i -ge 0; $i--) {
        if ($fim[$i] -eq 0x50 -and $fim[$i + 1] -eq 0x4B -and $fim[$i + 2] -eq 5 -and $fim[$i + 3] -eq 6) { $pos = $i; break }
    }
    if ($pos -lt 0) { throw 'Este Lacador.exe não tem o conteúdo esperado.' }
    $tamDir = [long][BitConverter]::ToUInt32($fim, $pos + 12)
    $desDir = [long][BitConverter]::ToUInt32($fim, $pos + 16)
    $posDir = ($tam - $nFim) + $pos - $tamDir
    $delta = $posDir - $desDir
    $dir = Read-Bytes $Fluxo $posDir ([int]$tamDir)
    $lista = New-Object System.Collections.Generic.List[object]
    $p = 0
    $inicio = [long]::MaxValue
    while ($p + 46 -le $dir.Length -and [BitConverter]::ToUInt32($dir, $p) -eq 0x02014b50) {
        $metodo = [int][BitConverter]::ToUInt16($dir, $p + 10)
        $crc = [BitConverter]::ToUInt32($dir, $p + 16)
        $tamC = [long][BitConverter]::ToUInt32($dir, $p + 20)
        $tamU = [long][BitConverter]::ToUInt32($dir, $p + 24)
        $nNome = [int][BitConverter]::ToUInt16($dir, $p + 28)
        $nExtra = [int][BitConverter]::ToUInt16($dir, $p + 30)
        $nCom = [int][BitConverter]::ToUInt16($dir, $p + 32)
        $cab = [long][BitConverter]::ToUInt32($dir, $p + 42) + $delta
        $nome = [Text.Encoding]::ASCII.GetString($dir, $p + 46, $nNome)
        if ($metodo -ne 0 -or $tamC -ne $tamU) { throw ('Entrada comprimida no Lacador.exe: {0}' -f $nome) }
        $local = Read-Bytes $Fluxo $cab 30
        if ([BitConverter]::ToUInt32($local, 0) -ne 0x04034b50) { throw 'Conteúdo do Lacador.exe fora do lugar.' }
        $dados = $cab + 30 + [int][BitConverter]::ToUInt16($local, 26) + [int][BitConverter]::ToUInt16($local, 28)
        if ($cab -lt $inicio) { $inicio = $cab }
        $lista.Add([pscustomobject]@{ nome = $nome; crc = $crc; tamanho = $tamU; dados = $dados })
        $p += 46 + $nNome + $nExtra + $nCom
    }
    if (-not $lista.Count) { throw 'Este Lacador.exe não tem conteúdo.' }
    return [pscustomobject]@{ entradas = $lista.ToArray(); inicio = $inicio }
}

function Copy-Trecho {
    param($De, [long]$Posicao, [long]$Quantos, $Para)
    $buf = New-Object byte[] 1048576
    $null = $De.Seek($Posicao, [IO.SeekOrigin]::Begin)
    $falta = $Quantos
    while ($falta -gt 0) {
        $n = $De.Read($buf, 0, [int][Math]::Min($falta, $buf.Length))
        if ($n -le 0) { throw 'Leitura interrompida.' }
        $Para.Write($buf, 0, $n)
        $falta -= $n
    }
}

function New-LacadorCompleto {
    <# $Base: Lacador.exe de partida.  $Fontes: nome do instalador -> arquivo conferido.  $Pacotes: lista do catálogo (com crc32). #>
    param([string]$Base, [string]$Saida, [hashtable]$Fontes, $Pacotes)
    $tmp = $Saida + '.montando'
    $agora = Get-Date
    $hora = [uint16](($agora.Hour -shl 11) -bor ($agora.Minute -shl 5) -bor [int][Math]::Floor($agora.Second / 2))
    $data = [uint16]((($agora.Year - 1980) -shl 9) -bor ($agora.Month -shl 5) -bor $agora.Day)
    $ent = New-Object System.Collections.Generic.List[object]
    $in = [IO.File]::Open($Base, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $b = Get-EntradasBase $in
        $mz = Read-Bytes $in 0 2
        if ($mz[0] -ne 0x4D -or $mz[1] -ne 0x5A -or $b.inicio -lt 1024) { throw 'O arquivo de partida não é um Lacador.exe.' }
        $out = [IO.File]::Open($tmp, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $w = New-Object IO.BinaryWriter($out)
            Copy-Trecho $in 0 $b.inicio $out                      # o lançador
            $gravarCabecalho = {
                param($nome, $crc, $tamanho)
                $bytesNome = [Text.Encoding]::ASCII.GetBytes($nome)
                $pos = [long]$out.Position
                $w.Write([uint32]0x04034b50); $w.Write([uint16]20); $w.Write([uint16]0); $w.Write([uint16]0)
                $w.Write($hora); $w.Write($data); $w.Write([uint32]$crc); $w.Write([uint32]$tamanho); $w.Write([uint32]$tamanho)
                $w.Write([uint16]$bytesNome.Length); $w.Write([uint16]0); $w.Write($bytesNome)
                $w.Flush()
                $ent.Add([pscustomobject]@{ nome = $bytesNome; crc = [uint32]$crc; tamanho = [uint32]$tamanho; pos = [uint32]$pos })
            }
            $jaTem = @{}
            foreach ($e in $b.entradas) {                          # o programa (e instaladores que a base já tiver)
                $nomeCurto = ''
                if ($e.nome -like 'pacotes/*') { $nomeCurto = $e.nome.Substring(8) }
                if ($nomeCurto -and $Fontes.ContainsKey($nomeCurto)) { continue }   # será regravado a partir do arquivo conferido
                & $gravarCabecalho $e.nome $e.crc $e.tamanho
                Copy-Trecho $in $e.dados $e.tamanho $out
                if ($nomeCurto) { $jaTem[$nomeCurto] = $true }
            }
            foreach ($p in $Pacotes) {                             # os instaladores
                if (-not $Fontes.ContainsKey($p.arquivo)) { continue }
                if (-not $p.crc32) { throw ('O catálogo não tem o CRC-32 de {0}.' -f $p.arquivo) }
                Write-Passo ('  Guardando {0} ...' -f $p.arquivo)
                & $gravarCabecalho ('pacotes/' + $p.arquivo) ([Convert]::ToUInt32([string]$p.crc32, 16)) $p.tamanho
                $f = [IO.File]::OpenRead($Fontes[$p.arquivo])
                try { $f.CopyTo($out, 1048576) } finally { $f.Dispose() }
            }
            $posDir = [long]$out.Position
            foreach ($e in $ent) {
                $w.Write([uint32]0x02014b50); $w.Write([uint16]20); $w.Write([uint16]20); $w.Write([uint16]0); $w.Write([uint16]0)
                $w.Write($hora); $w.Write($data); $w.Write($e.crc); $w.Write($e.tamanho); $w.Write($e.tamanho)
                $w.Write([uint16]$e.nome.Length); $w.Write([uint16]0); $w.Write([uint16]0); $w.Write([uint16]0); $w.Write([uint16]0)
                $w.Write([uint32]0); $w.Write($e.pos); $w.Write($e.nome)
            }
            $w.Flush()
            $tamDir = [long]$out.Position - $posDir
            if ($out.Position -gt 4000000000 -or $ent.Count -gt 60000) { throw 'O executável ficaria grande demais para este formato.' }
            $w.Write([uint32]0x06054b50); $w.Write([uint16]0); $w.Write([uint16]0); $w.Write([uint16]$ent.Count); $w.Write([uint16]$ent.Count)
            $w.Write([uint32]$tamDir); $w.Write([uint32]$posDir); $w.Write([uint16]0)
            $w.Flush()
        } finally { $out.Dispose() }
    } finally { $in.Dispose() }

    # Confere o resultado: abre como o Laçador vai abrir e recalcula o SHA-256 de cada instalador lá de dentro.
    Write-Passo '  Conferindo o executável montado ...'
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop } catch { }
    $zip = [IO.Compression.ZipFile]::OpenRead($tmp)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        foreach ($p in $Pacotes) {
            if (-not $Fontes.ContainsKey($p.arquivo)) { continue }
            $e = $zip.GetEntry('pacotes/' + $p.arquivo)
            if (-not $e -or [long]$e.Length -ne [long]$p.tamanho) { throw ('{0} não ficou certo dentro do executável.' -f $p.arquivo) }
            $s = $e.Open()
            try { $h = ([BitConverter]::ToString($sha.ComputeHash($s)) -replace '-', '') } finally { $s.Dispose() }
            if ($h -ne ([string]$p.sha256).ToUpperInvariant()) { throw ('{0} não confere depois de guardado.' -f $p.arquivo) }
        }
    } finally { $zip.Dispose() }
    if (Test-Path -LiteralPath $Saida) { Remove-Item -LiteralPath $Saida -Force }
    Move-Item -LiteralPath $tmp -Destination $Saida
}

# ---- principal -----------------------------------------------------------------------
$codigo = 0
$script:Trabalho = $null
try {
    Import-Module (Join-Path $raiz 'programa\Lacador.Motor.psm1') -Force
    $cat = Get-LacadorCatalogo

    if ($Montar) {
        if (-not $Recipiente -or -not (Test-Path -LiteralPath $Recipiente -PathType Leaf)) { throw 'Não encontrei o Lacador.exe de partida. Use: Lacador.exe /montar' }
        $Recipiente = (Resolve-Path -LiteralPath $Recipiente).ProviderPath
        if (-not $Saida) { $Saida = Join-Path (Split-Path -Parent $Recipiente) 'Lacador-completo.exe' }
        if ([IO.Path]::GetFullPath($Saida) -ieq [IO.Path]::GetFullPath($Recipiente)) { throw 'A saída precisa ser um arquivo diferente do Lacador.exe de partida.' }
    }

    if (-not $Origem) {
        if ($Silencioso -or -not $noWindows) { throw 'Informe -Origem (o arquivo TOKENS.rar ou a pasta com os instaladores).' }
        $Origem = Select-Origem
        if (-not $Origem) { Write-Passo 'Nada escolhido. Nada foi feito.' 'Yellow'; Exit-Script 0 }
    }
    if (-not (Test-Path -LiteralPath $Origem)) { throw ('Não encontrei: {0}' -f $Origem) }
    $Origem = (Resolve-Path -LiteralPath $Origem).ProviderPath
    if (-not $Montar -and -not (Test-Path -LiteralPath $Destino)) { New-Item -ItemType Directory -Path $Destino -Force | Out-Null }

    $script:Extratores = @(Get-Extratores)
    $script:Trabalho = Join-Path ([IO.Path]::GetTempPath()) ('lacador-pacotes-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $script:Trabalho -Force | Out-Null

    if ($Montar) { Write-Passo 'Laçador: montando o executável completo' 'Cyan' } else { Write-Passo 'Laçador: preparando a pasta de instaladores' 'Cyan' }
    Write-Passo ('  Origem:  {0}' -f $Origem)
    if ($Montar) { Write-Passo ('  Saída:   {0}' -f $Saida) } else { Write-Passo ('  Destino: {0}' -f $Destino) }

    if (Test-Path -LiteralPath $Origem -PathType Container) {
        Search-Pasta $Origem 0
    } else {
        $d0 = Join-Path $script:Trabalho '00'
        Write-Passo ('  Abrindo {0} ...' -f (Split-Path -Leaf $Origem))
        $com = Expand-Pacote $Origem $d0
        if (-not $com) {
            throw 'Não consegui abrir o arquivo. Instale o 7-Zip (ou o WinRAR), ou extraia o pacote à mão e escolha a pasta extraída.'
        }
        Search-Pasta $d0 1
    }

    # Um por um, na ordem do catálogo
    $pacotes = New-Object System.Collections.Generic.List[object]
    $vistos = @{}
    foreach ($i in $cat.itens) {
        foreach ($p in @($i.pacotes)) {
            if (-not $p -or -not $p.arquivo -or $vistos.ContainsKey([string]$p.arquivo)) { continue }
            $vistos[[string]$p.arquivo] = $true
            $pacotes.Add([pscustomobject]@{ item = [string]$i.nome; arquivo = [string]$p.arquivo; tamanho = [long]$p.tamanho; sha256 = [string]$p.sha256; crc32 = [string]$p.crc32 })
        }
    }

    Write-Passo ''
    $faltam = 0
    $fontes = @{}
    foreach ($p in $pacotes) {
        $situacao = ''
        $alvo = ''
        if (-not $Montar) { $alvo = Join-Path $Destino $p.arquivo }
        if ($alvo -and (Test-Path -LiteralPath $alvo) -and ((Get-Item -LiteralPath $alvo).Length -eq $p.tamanho) -and (Test-LacadorHash $alvo $p.sha256)) {
            $situacao = 'já estava na pasta'
        } else {
            $porNome = @($script:Achados | Where-Object { $_.Name -ieq $p.arquivo })
            $porTamanho = @($script:Achados | Where-Object { $_.Length -eq $p.tamanho -and $_.Name -ine $p.arquivo })
            $fonte = $null
            foreach ($c in ($porNome + $porTamanho)) {
                if ($c.Length -eq $p.tamanho -and (Test-LacadorHash $c.FullName $p.sha256)) { $fonte = $c; break }
            }
            if ($fonte) {
                if ($Montar) {
                    $fontes[$p.arquivo] = $fonte.FullName
                    $situacao = 'conferido'
                } else {
                    Copy-Item -LiteralPath $fonte.FullName -Destination $alvo -Force
                    if ($noWindows) { try { Unblock-File -LiteralPath $alvo -ErrorAction SilentlyContinue } catch { } }
                    $situacao = 'copiado'
                }
                if ($fonte.Name -ine $p.arquivo) { $situacao = ('{0} (estava como "{1}")' -f $situacao, $fonte.Name) }
            } elseif ($porNome.Count) {
                $situacao = 'DIFERENTE do catálogo (SHA-256 não confere): ficou de fora'
                $faltam++
            } else {
                $situacao = 'NÃO ENCONTRADO'
                $faltam++
            }
        }
        $cor = 'Green'
        if ($situacao -cmatch 'NÃO|DIFERENTE') { $cor = 'Yellow' }
        Write-Passo ('  {0,-46} {1}' -f $p.arquivo, $situacao) $cor
    }

    Write-Passo ''
    if ($script:NaoAbriu.Count) {
        Write-Passo ('Não consegui abrir: {0}' -f ($script:NaoAbriu -join ', ')) 'Yellow'
        Write-Passo 'Instale o 7-Zip (ou o WinRAR) e rode de novo, ou extraia esses arquivos à mão na mesma pasta.' 'Yellow'
    }

    if ($Montar) {
        if (-not $fontes.Count) { throw 'Nenhum instalador foi encontrado nesse pacote. Nada foi montado.' }
        New-LacadorCompleto -Base $Recipiente -Saida $Saida -Fontes $fontes -Pacotes $pacotes
        if ($noWindows) { try { Unblock-File -LiteralPath $Saida -ErrorAction SilentlyContinue } catch { } }
        $mb = [Math]::Round((Get-Item -LiteralPath $Saida).Length / 1MB)
        Write-Passo ''
        if ($faltam) {
            $codigo = 1
            Write-Passo ('Montado com {0} de {1} instaladores ({2} MB). Os que faltaram não poderão ser instalados por ele.' -f $fontes.Count, $pacotes.Count, $mb) 'Yellow'
        } else {
            Write-Passo ('Pronto: o Laçador completo tem os {0} instaladores dentro ({1} MB).' -f $pacotes.Count, $mb) 'Green'
        }
        Write-Passo ('  {0}' -f $Saida) 'Green'
        Write-Passo 'Feche o Laçador que está aberto e use esse arquivo daqui em diante. Pode renomear para Lacador.exe.'
        if ($noWindows -and -not $Silencioso) { try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $Saida) } catch { } }
    } elseif ($faltam) {
        $codigo = 1
        Write-Passo ('Faltaram {0} de {1} instaladores. O Laçador funciona, mas não consegue instalar os itens que dependem deles.' -f $faltam, $pacotes.Count) 'Yellow'
    } else {
        Write-Passo ('Pronto: os {0} instaladores estão na pasta e conferem com o catálogo.' -f $pacotes.Count) 'Green'
    }
} catch {
    $codigo = 1
    Write-Passo ('ERRO: {0}' -f $_.Exception.Message) 'Red'
    if ($Silencioso) { Write-Host ('Preparar-Pacotes: ERRO: {0}' -f $_.Exception.Message) }
    if ($Saida -and (Test-Path -LiteralPath ($Saida + '.montando'))) { Remove-Item -LiteralPath ($Saida + '.montando') -Force -ErrorAction SilentlyContinue }
} finally {
    if ($script:Trabalho -and (Test-Path -LiteralPath $script:Trabalho)) { Remove-Item -LiteralPath $script:Trabalho -Recurse -Force -ErrorAction SilentlyContinue }
}
Exit-Script $codigo
