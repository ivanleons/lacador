# Testes do motor do Laçador (lógica pura). Roda em qualquer PowerShell; não toca no computador.
param([string]$Bats)
$ErrorActionPreference = 'Stop'
# Os .bat originais do assinador ficam em testes/bats: sem -Bats, usa esses.
if (-not $Bats -and (Test-Path (Join-Path $PSScriptRoot 'bats'))) { $Bats = Join-Path $PSScriptRoot 'bats' }
$raiz = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $raiz 'Lacador/programa/Lacador.Motor.psm1') -Force
$cat = Get-LacadorCatalogo
$cfg = Get-LacadorConfig
$agora = [datetime]'2026-10-06T12:00:00'
$script:falhas = 0; $script:total = 0
function Confere($nome, $obtido, $esperado) {
    $script:total++
    $a = ($obtido | ConvertTo-Json -Compress -Depth 5); $b = ($esperado | ConvertTo-Json -Compress -Depth 5)
    if ($a -ne $b) { $script:falhas++; Write-Host ("FALHOU  {0}`n        obtido  : {1}`n        esperado: {2}" -f $nome, $a, $b) -ForegroundColor Red }
}
function Estado($cenario) {
    $f = Get-Content -Raw (Join-Path $PSScriptRoot "cenarios/$cenario.json") | ConvertFrom-Json
    return (ConvertTo-LacadorEstado $f $cat $cfg $agora)
}
function Sis($e, $id) { return @($e.sistemas | Where-Object { $_.id -eq $id })[0] }
function Tok($e, $id) { return @($e.tokens | Where-Object { $_.id -eq $id })[0] }

# --- versões
Confere 'versao 3.0.97 = 3.0.97.0' (Compare-LacadorVersao '3.0.97' '3.0.97.0') 0
Confere 'versao 1.7.17.0 >= 1.7.17' (Compare-LacadorVersao '1.7.17.0' '1.7.17') 0
Confere 'versao 11.0.10 < 11.0.23' (Compare-LacadorVersao '11.0.10' '11.0.23') (-1)
Confere 'versao 2.0.12 > 2.0.9' (Compare-LacadorVersao '2.0.12' '2.0.9') 1

# --- cenário 1: notebook de um usuário antes do conserto
$e = Estado 'notebook-antes'
Confere 'c1 safesign' $e.itens['safesign'].estado 'ok'
Confere 'c1 starsign' $e.itens['starsign'].estado 'ok'
Confere 'c1 dxsafe' $e.itens['dxsafe'].estado 'ausente'
Confere 'c1 assinador' $e.itens['assinador'].estado 'ausente'
Confere 'c1 firefox' $e.itens['firefox-esr'].estado 'ok'
Confere 'c1 firefox detalhe' $e.itens['firefox-esr'].detalhe 'ESR 153.3.0'
Confere 'c1 firefox edicoes' @($e.itens['firefox-esr'].edicoes | ForEach-Object { $_.nome + ' ' + $_.bits }) @('Firefox ESR 32 bits')
Confere 'c1 extensao (manual no perfil)' $e.itens['extensao-firefox'].estado 'ok'
Confere 'c1 java7' $e.itens['java7'].estado 'ok'
Confere 'c1 java8' $e.itens['java8'].estado 'ausente'
Confere 'c1 servico' $e.itens['servico-smartcard'].estado 'ok'
Confere 'c1 token gd' (Tok $e 'gd-starsign').estado 'desconectado'
Confere 'c1 token dexon' (Tok $e 'dexon-dxtoken').estado 'sem-driver'
Confere 'c1 sigadaer' (Sis $e 'sigadaer').estado 'falta'
Confere 'c1 sigadaer faltando' @((Sis $e 'sigadaer').faltando) @('assinador')
Confere 'c1 sigadaer nao pede escolha de token' (Sis $e 'sigadaer').escolherToken $false
Confere 'c1 siafi faltando' @((Sis $e 'siafi').faltando) @('java8')
Confere 'c1 compras' (Sis $e 'compras').estado 'aguardando'
Confere 'c1 certificados pessoais' @($e.certificados | Where-Object { $_.pessoal } | ForEach-Object { $_.titular }) @('FULANO DE TAL')
Confere 'c1 sem avisos de certificado' @($e.avisos | Where-Object { $_.pagina -eq 'certificados' }).Count 0

# --- cenário 2: depois do conserto
$e = Estado 'notebook-depois'
Confere 'c2 assinador' $e.itens['assinador'].estado 'ok'
Confere 'c2 token gd pronto' (Tok $e 'gd-starsign').estado 'pronto'
Confere 'c2 sigadaer pronto' (Sis $e 'sigadaer').estado 'pronto'
Confere 'c2 assinar-pdf pronto' (Sis $e 'assinar-pdf').estado 'pronto'
Confere 'c2 siafi falta java8' @((Sis $e 'siafi').faltando) @('java8')
Confere 'c2 compras pronto' (Sis $e 'compras').estado 'pronto'
Confere 'c2 sem avisos' $e.avisos.Count 0
Confere 'c2 sem leitor desconhecido' $e.leitoresDesconhecidos.Count 0

# --- cenário 3: computador novo
$e = Estado 'pc-novo'
Confere 'c3 firefox comum nao serve' $e.itens['firefox-esr'].estado 'ausente'
Confere 'c3 firefox detalhe' $e.itens['firefox-esr'].detalhe 'Só o Firefox comum está instalado. O SIGADAER pede o Developer Edition ou o ESR.'
Confere 'c3 extensao' $e.itens['extensao-firefox'].estado 'ausente'
Confere 'c3 leitor generico aparece' @($e.leitoresDesconhecidos | ForEach-Object { $_.nome }) @('Microsoft Usbccid Smartcard Reader (WUDF)')
Confere 'c3 sigadaer pede token' (Sis $e 'sigadaer').escolherToken $true
Confere 'c3 sigadaer faltando' @((Sis $e 'sigadaer').faltando) @('assinador', 'firefox-esr', 'extensao-firefox')
Confere 'c3 servico parado com leitor' $e.itens['servico-smartcard'].estado 'atencao'
Confere 'c3 avisos informativos' @($e.avisos | Where-Object { $_.nivel -eq 'info' } | ForEach-Object { $_.titulo }) @('Token ou leitor não identificado', 'Este usuário não é administrador')
Confere 'c3 acesso: usuario comum' $e.acesso.administrador $false
Confere 'c3 acesso: nao liberado' $e.acesso.liberado $false
Confere 'c3 instaladores em pasta' $e.pacotesNoExecutavel $false

# --- acesso: computador liberado (demonstração) e administrador sem elevação
$f = Get-Content -Raw (Join-Path $PSScriptRoot 'cenarios/pc-novo.json') | ConvertFrom-Json
$f | Add-Member -NotePropertyName 'simulacao' -NotePropertyValue ([pscustomobject]@{ ok = @('acesso') }) -Force
$e = ConvertTo-LacadorEstado $f $cat $cfg $agora
Confere 'acesso liberado na demonstracao' $e.acesso.liberado $true
Confere 'acesso liberado: agente visto pela tela' $e.agente.tarefa $true
Confere 'acesso liberado: sem aviso de administrador' @($e.avisos | Where-Object { $_.pagina -eq 'acesso' }).Count 0
$f = Get-Content -Raw (Join-Path $PSScriptRoot 'cenarios/pc-novo.json') | ConvertFrom-Json
$f | Add-Member -NotePropertyName 'grupoAdmin' -NotePropertyValue $true -Force
$e = ConvertTo-LacadorEstado $f $cat $cfg $agora
Confere 'administrador sem elevacao conta como administrador' $e.acesso.administrador $true
Confere 'administrador sem elevacao: sem aviso' @($e.avisos | Where-Object { $_.pagina -eq 'acesso' }).Count 0
$f = Get-Content -Raw (Join-Path $PSScriptRoot 'cenarios/tudo-pronto.json') | ConvertFrom-Json
$f.agente.tarefa = $true; $f.agente.versao = '1.0.0'
$e = ConvertTo-LacadorEstado $f $cat $cfg $agora
Confere 'instalacao antiga pede atualizacao' $e.acesso.atualizar $true

# --- cenário 4: assinador quebrado, certificado vencendo, conflito do Adobe, pacote faltando
$e = Estado 'assinador-quebrado'
Confere 'c4 assinador atencao' $e.itens['assinador'].estado 'atencao'
Confere 'c4 assinador acao' $e.itens['assinador'].acao 'reparar'
Confere 'c4 sigadaer atencao' (Sis $e 'sigadaer').estado 'atencao'
Confere 'c4 sigadaer reparar' @((Sis $e 'sigadaer').reparar) @('assinador')
Confere 'c4 adobe conflito' $e.itens['adobe-xi'].estado 'conflito'
Confere 'c4 sistema adobe bloqueado' (Sis $e 'adobe').estado 'bloqueado'
Confere 'c4 java8 sem instalador' @($e.itens['java8'].pacotesFaltando) @('jre-8u91-windows-i586.exe')
Confere 'c4 siafi sem pacote' @((Sis $e 'siafi').semPacote) @('Java 8 Update 91')
Confere 'c4 certificado vencendo' @($e.certificados | Where-Object { $_.situacao -eq 'vencendo' } | ForEach-Object { $_.dias }) @(12)
Confere 'c4 certificado vencido' @($e.certificados | Where-Object { $_.situacao -eq 'vencido' }).Count 1
Confere 'c4 avisos' @($e.avisos | ForEach-Object { $_.titulo }) @('Falta 1 instalador', 'O Laçador instalado neste computador é o 1.0.0', 'Certificado vencido', 'Certificado perto de vencer', 'O Assinador do COMAER precisa de reparo')

# --- cenário 5: tudo pronto
$e = Estado 'tudo-pronto'
foreach ($id in 'safesign', 'starsign', 'dxsafe', 'java8', 'assinador', 'firefox-esr', 'extensao-firefox', 'adobe-xi', 'servico-smartcard') { Confere "c5 $id" $e.itens[$id].estado 'ok' }
foreach ($id in 'sigadaer', 'assinar-pdf', 'siafi', 'compras', 'adobe') { Confere "c5 sistema $id" (Sis $e $id).estado 'pronto' }
Confere 'c5 dexon pronto' (Tok $e 'dexon-dxtoken').estado 'pronto'
Confere 'c5 dexon ajustado no assinador' (Tok $e 'dexon-dxtoken').ajusteAssinadorFeito $true
Confere 'c5 proxy ok' $e.proxy.ok $true
Confere 'c5 siafi sem avisos' (Sis $e 'siafi').avisos.Count 0
Confere 'c5 java7 opcional aparece' @((Sis $e 'siafi').opcionais | ForEach-Object { $_.id }) @('java7')

# --- cenário 6: Firefox Developer Edition (padrão da base), extensão ativa mas escondida no menu
$e = Estado 'developer-sem-fixar'
Confere 'c6 firefox ok com o Developer' $e.itens['firefox-esr'].estado 'ok'
Confere 'c6 firefox detalhe' $e.itens['firefox-esr'].detalhe 'Developer Edition 145.0b9'
Confere 'c6 sem ESR nao desinstala' $e.itens['firefox-esr'].podeDesinstalar $false
Confere 'c6 extensao pede para fixar' @($e.itens['extensao-firefox'].estado, $e.itens['extensao-firefox'].acao) @('atencao', 'fixar')
Confere 'c6 sigadaer: passo do usuario' @((Sis $e 'sigadaer').estado, (Sis $e 'sigadaer').passo.acao) @('atencao', 'fixar')
Confere 'c6 sigadaer nao manda reparar' @((Sis $e 'sigadaer').reparar).Count 0
Confere 'c6 nome do usuario' $e.nomeUsuario '3S BMB Leon'

# --- cenário 7: ESR e política gravados, Firefox ainda não aberto
$e = Estado 'firefox-nao-aberto'
Confere 'c7 extensao pede para abrir o Firefox' @($e.itens['extensao-firefox'].estado, $e.itens['extensao-firefox'].acao) @('atencao', 'abrir-firefox')
Confere 'c7 sigadaer resumo' (Sis $e 'sigadaer').resumo 'Falta abrir o Firefox uma vez para a extensão entrar'

# --- cenário 7b/7c: política gravada às 12:18; o Firefox fechado mexeu no perfil depois (recusou) / está aberto agora
$f7 = Get-Content -Raw (Join-Path $PSScriptRoot 'cenarios/firefox-nao-aberto.json') | ConvertFrom-Json
$f7.firefox.politica | Add-Member -NotePropertyName gravadaEm -NotePropertyValue '2026-10-14T12:18:05' -Force
$f7.firefox.perfis[0] | Add-Member -NotePropertyName atualizadoEm -NotePropertyValue '2026-10-14T12:40:00' -Force
$f7.firefox | Add-Member -NotePropertyName aberto -NotePropertyValue $false -Force
$e = ConvertTo-LacadorEstado $f7 $cat $cfg $agora
Confere 'c7b Firefox recusou: reparar' @($e.itens['extensao-firefox'].estado, $e.itens['extensao-firefox'].acao, $e.itens['extensao-firefox'].recusada) @('atencao', 'reparar', $true)
$f7.firefox.aberto = $true
$e = ConvertTo-LacadorEstado $f7 $cat $cfg $agora
Confere 'c7c Firefox aberto: fechar e abrir' @($e.itens['extensao-firefox'].acao, $e.firefoxAberto) @('abrir-firefox', $true)

# --- cenário 8: SafeSign registrado, mas sem a biblioteca do token: reinstala por cima
$e = Estado 'safesign-quebrado'
Confere 'c8 safesign reparar' @($e.itens['safesign'].estado, $e.itens['safesign'].acao, $e.itens['safesign'].reinstalar) @('atencao', 'reparar', $true)
Confere 'c8 firefox: Developer e ESR' $e.itens['firefox-esr'].detalhe 'Developer Edition e ESR instalados'
Confere 'c8 com ESR pode desinstalar' $e.itens['firefox-esr'].podeDesinstalar $true
Confere 'c8 safesign pode desinstalar' $e.itens['safesign'].podeDesinstalar $true
Confere 'c8 servico nao desinstala' $e.itens['servico-smartcard'].podeDesinstalar $false

# --- Laçador instalado mais antigo: aviso para atualizar
$e = Estado 'assinador-quebrado'
Confere 'instalado antigo: aviso' @($e.avisos | Where-Object { $_.pagina -eq 'acesso' -and $_.nivel -eq 'alerta' } | ForEach-Object { $_.titulo }) @('O Laçador instalado neste computador é o 1.0.0')

# --- nome do usuário
Confere 'nome: maiusculas' (Format-LacadorNome 'IVAN LOPES DA SILVA') 'Ivan Lopes da Silva'
Confere 'nome: posto fica' (Format-LacadorNome '3S BMB LEON') '3S BMB Leon'
Confere 'nome: login' (Format-LacadorNome 'ivan.leon') 'Ivan Leon'
Confere 'nome: ja bonito' (Format-LacadorNome 'Ivan Leon') 'Ivan Leon'

# --- botão da extensão na barra do Firefox (prefs.js)
Confere 'id do botao' (Get-LacadorIdBotaoExtensao 'assinador_comaer@fab.mil.br') 'assinador_comaer_fab_mil_br-browser-action'
$pf = Join-Path ([IO.Path]::GetTempPath()) ('lacador-ff-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $pf | Out-Null
$estadoBarra = '{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":["assinador_comaer_fab_mil_br-browser-action"],"nav-bar":["back-button","forward-button","urlbar-container","downloads-button","unified-extensions-button"],"TabsToolbar":["tabbrowser-tabs"]},"seen":["assinador_comaer_fab_mil_br-browser-action"],"dirtyAreaCache":["nav-bar"],"currentVersion":20,"newElementCount":2}'
$linhaPref = 'user_pref("browser.uiCustomization.state", "' + ($estadoBarra -replace '"', '\"') + '");'
[IO.File]::WriteAllText((Join-Path $pf 'prefs.js'), ("// Mozilla User Preferences`r`nuser_pref(""a.b"", true);`r`n" + $linhaPref + "`r`nuser_pref(""c.d"", 1);`r`n"))
$botao = 'assinador_comaer_fab_mil_br-browser-action'
Confere 'barra: escondido no menu' (Test-LacadorExtensaoFixada (Get-LacadorBarraFirefox $pf) $botao) $false
Confere 'barra: fixar' (Set-LacadorBotaoNaBarra $pf $botao) 'fixado'
$b2 = Get-LacadorBarraFirefox $pf
Confere 'barra: agora fixado' (Test-LacadorExtensaoFixada $b2 $botao) $true
Confere 'barra: antes do botao de extensoes' @($b2.placements.'nav-bar') @('back-button', 'forward-button', 'urlbar-container', 'downloads-button', $botao, 'unified-extensions-button')
Confere 'barra: saiu do menu' @($b2.placements.'unified-extensions-area').Count 0
Confere 'barra: outras preferencias intactas' (@([IO.File]::ReadAllLines((Join-Path $pf 'prefs.js')) | Where-Object { $_ -match '^user_pref\("(a\.b|c\.d)"' }).Count) 2
Confere 'barra: de novo' (Set-LacadorBotaoNaBarra $pf $botao) 'ja-estava'
Confere 'barra: copia de seguranca' (Test-Path (Join-Path $pf 'prefs.js.lacador')) $true
Remove-Item -Recurse -Force $pf
Confere 'barra: perfil sem preferencias' (Test-LacadorExtensaoFixada $null $botao) $null

# --- desinstalação: comando montado a partir do registro
$msiProg = [pscustomobject]@{ nome = 'SafeSign 64-bits'; chave = '{12345678-1234-1234-1234-1234567890AB}'; msi = $true; desinstalar = 'MsiExec.exe /X{12345678-1234-1234-1234-1234567890AB}' }
$env:windir = if ($env:windir) { $env:windir } else { 'C:\Windows' }
$c = Get-LacadorComandoDesinstalar $msiProg 'msi'
Confere 'desinstalar msi' $c.argumentos '/x {12345678-1234-1234-1234-1234567890AB} /qn /norestart'
Confere 'pedido: desinstalar programa' (Test-LacadorPedido ([pscustomobject]@{ id = ('b' * 32); acao = 'desinstalar'; itens = @('safesign') }) $cat) $null
Confere 'pedido: desinstalar servico nao' (Test-LacadorPedido ([pscustomobject]@{ id = ('b' * 32); acao = 'desinstalar'; itens = @('servico-smartcard') }) $cat) 'o Laçador não desinstala: servico-smartcard'

# --- plano de instalação: ordem do catálogo e dependências
Confere 'plano sigadaer + gd' @(Resolve-LacadorPlano -Catalogo $cat -Sistemas @('sigadaer') -Token 'gd-starsign') @('safesign', 'starsign', 'assinador', 'firefox-esr', 'extensao-firefox')
Confere 'plano siafi + dexon' @(Resolve-LacadorPlano -Catalogo $cat -Sistemas @('siafi') -Token 'dexon-dxtoken') @('dxsafe', 'java8')
Confere 'plano extensao puxa firefox' @(Resolve-LacadorPlano -Catalogo $cat -Itens @('extensao-firefox')) @('firefox-esr', 'extensao-firefox')
Confere 'plano java: 7 antes do 8' @(Resolve-LacadorPlano -Catalogo $cat -Itens @('java8', 'java7')) @('java7', 'java8')

# --- validação de pedidos
$bom = [pscustomobject]@{ id = ('a' * 32); acao = 'instalar'; itens = @('safesign', 'starsign') }
Confere 'pedido bom' (Test-LacadorPedido $bom $cat) $null
Confere 'pedido: item fora do catalogo' (Test-LacadorPedido ([pscustomobject]@{ id = ('a' * 32); acao = 'instalar'; itens = @('calc') }) $cat) 'item fora do catálogo: calc'
Confere 'pedido: caminho como item' (Test-LacadorPedido ([pscustomobject]@{ id = ('a' * 32); acao = 'instalar'; itens = @('..\x.exe') }) $cat) 'item com nome inválido'
Confere 'pedido: acao invalida' (Test-LacadorPedido ([pscustomobject]@{ id = ('a' * 32); acao = 'executar'; itens = @('safesign') }) $cat) 'ação inválida'
Confere 'pedido: id invalido' (Test-LacadorPedido ([pscustomobject]@{ id = '../../x'; acao = 'instalar'; itens = @('safesign') }) $cat) 'identificador inválido'

# --- correção do WMIC nos .bat ORIGINAIS do instalador do assinador
if ($Bats) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('lacador-bats-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    foreach ($n in 'assinador_comaer.bat', 'assinador_standalone.bat') {
        $alvo = Join-Path $tmp $n
        Copy-Item (Join-Path $Bats $n) $alvo
        $antes = [IO.File]::ReadAllLines($alvo, [Text.Encoding]::ASCII)
        Confere "$n original usa wmic" (Test-LacadorUsaWmic $antes) $true
        Confere "$n corrigir" (Update-LacadorBat $alvo ([Text.Encoding]::ASCII)) 'CORRIGIDO'
        Confere "$n repetir" (Update-LacadorBat $alvo ([Text.Encoding]::ASCII)) 'JA_CORRIGIDO'
        $depois = [IO.File]::ReadAllLines($alvo, [Text.Encoding]::ASCII)
        Confere "$n nao usa mais wmic" (Test-LacadorUsaWmic $depois) $false
        Confere "$n 3 linhas a mais" ($depois.Count - $antes.Count) 3
        Confere "$n backup igual ao original" ((Get-FileHash "$alvo.original").Hash) ((Get-FileHash (Join-Path $Bats $n)).Hash)
        Confere "$n resto intacto" (@($depois | Where-Object { $_ -notmatch 'CORRECAO-WMIC|FREEMEMORY=$|powershell\.exe|if not defined|salvo como' }) -join '|') (@($antes | Where-Object { $_ -notmatch 'wmic|%torun%' }) -join '|')
        Confere "$n termina com CRLF" ([IO.File]::ReadAllText($alvo).Contains("`r`n")) $true
    }
    Remove-Item -Recurse -Force $tmp
}

# --- ajuste do token Dexon no config.properties do assinador
$perfil = Join-Path ([IO.Path]::GetTempPath()) ('lacador-perfil-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path (Join-Path $perfil 'Assinador Digital COMAER') -Force | Out-Null
$dll = Join-Path $perfil 'DXSafePKCS11.dll'; Set-Content -Path $dll -Value 'x'
$cfgAss = Join-Path $perfil 'Assinador Digital COMAER/config.properties'
[IO.File]::WriteAllText($cfgAss, "##TOKEN##`r`n#token.[nome do token]=[path PKCS11 do driver]`r`n", [Text.Encoding]::GetEncoding(28591))
$antigo = $env:USERPROFILE; $env:USERPROFILE = $perfil
try {
    $m = Add-LacadorTokenAoAssinador 'dexon' $dll
    $m = Add-LacadorTokenAoAssinador 'dexon' $dll
    $linhas = [IO.File]::ReadAllLines((Get-LacadorCaminhoConfigAssinador))
    Confere 'config.properties: uma linha do token' @($linhas | Where-Object { $_ -match '^token\.dexon=' }).Count 1
    Confere 'config.properties: comentario preservado' @($linhas | Where-Object { $_ -match '^#token\.' }).Count 1
    Confere 'config.properties: backup criado' (Test-Path ((Get-LacadorCaminhoConfigAssinador) + '.original')) $true
} finally { $env:USERPROFILE = $antigo; Remove-Item -Recurse -Force $perfil }

# --- instaladores guardados dentro do Lacador.exe (um .zip no fim do arquivo)
$tmpExe = Join-Path ([IO.Path]::GetTempPath()) ('lacador-recipiente-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $tmpExe -Force | Out-Null
$exeFalso = Join-Path $tmpExe 'Lacador.exe'
$conteudo = New-Object byte[] 70000; (New-Object Random 7).NextBytes($conteudo)
$prefixo = New-Object byte[] 5000; (New-Object Random 3).NextBytes($prefixo)
[IO.File]::WriteAllBytes($exeFalso, $prefixo)
try { Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop } catch { }
$fs = New-Object IO.FileStream($exeFalso, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite)
$null = $fs.Seek(0, [IO.SeekOrigin]::End)
$zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
foreach ($par in @(@('programa/leia.txt', [Text.Encoding]::ASCII.GetBytes('oi')), @('pacotes/Java1.7_51.exe', $conteudo))) {
    $en = $zip.CreateEntry($par[0], [IO.Compression.CompressionLevel]::NoCompression)
    $st = $en.Open(); $st.Write($par[1], 0, $par[1].Length); $st.Dispose()
}
$zip.Dispose(); $fs.Dispose()
$antigoExe = $env:LACADOR_EXE; $env:LACADOR_EXE = $exeFalso
try {
    Confere 'recipiente encontrado' (Get-LacadorRecipiente) $exeFalso
    $ind = Get-LacadorIndiceRecipiente
    Confere 'recipiente: so a pasta pacotes entra no indice' @($ind.Keys) @('java1.7_51.exe')
    Confere 'recipiente: tamanho' $ind['java1.7_51.exe'] 70000
    $o = Get-LacadorOrigemPacote 'Java1.7_51.exe' $cfg
    Confere 'recipiente: origem do pacote' $o.origem 'executavel'
    Confere 'recipiente: pacote ausente' (Get-LacadorOrigemPacote 'nao-existe.exe' $cfg).existe $false
    $saidaPac = Join-Path $tmpExe 'copia.exe'
    Copy-LacadorPacote 'Java1.7_51.exe' $saidaPac $cfg
    Confere 'recipiente: copia identica' ((Get-FileHash $saidaPac).Hash) ((Get-FileHash -InputStream (New-Object IO.MemoryStream(, $conteudo))).Hash)
    $erroCopia = ''
    try { Copy-LacadorPacote '..\..\programa\leia.txt' (Join-Path $tmpExe 'x') $cfg } catch { $erroCopia = 'recusado' }
    Confere 'recipiente: nao sai da pasta pacotes' $erroCopia 'recusado'
    # ajustes ao lado do executável
    [IO.File]::WriteAllText((Join-Path $tmpExe 'Lacador.config.json'), '{ "proxy": { "porta": 3128 }, "suporte": { "contato": "ramal 1234" } }')
    $c2 = Get-LacadorConfig
    Confere 'config ao lado do exe: porta' $c2.proxy.porta 3128
    Confere 'config ao lado do exe: mantem o resto' $c2.proxy.servidor 'proxy.exemplo.intranet'
} finally { $env:LACADOR_EXE = $antigoExe; Remove-Item -Recurse -Force $tmpExe }

Write-Host ''
if ($script:falhas) { Write-Host ("{0} de {1} verificações FALHARAM" -f $script:falhas, $script:total) -ForegroundColor Red; exit 1 }
Write-Host ("Todas as {0} verificações passaram" -f $script:total) -ForegroundColor Green
