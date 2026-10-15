#!/usr/bin/env python3
"""Constrói o Lacador.exe completo: o lançador + o programa + os 12 instaladores, tudo num arquivo só.

    python3 construir.py                         usa o que já existe (ver "De onde vêm os instaladores")
    python3 construir.py --tokens ~/Downloads/TOKENS.rar
    python3 construir.py --pacotes pacotes/      pasta com os 12 instaladores já extraídos
    python3 construir.py --sem-instaladores      só o programa (1 MB), para testes rápidos
    python3 construir.py --saida /Volumes/PENDRIVE/Lacador.exe

Roda em macOS, Linux e Windows. Só precisa do Python 3 e, para abrir .rar, do "tar" do sistema
(o do macOS e o do Windows 10/11 abrem .rar) ou do 7-Zip.

De onde vêm os instaladores, nesta ordem:
  1. --pacotes PASTA
  2. --tokens ARQUIVO_OU_PASTA   (o TOKENS.rar da ATIC, ou a pasta onde foi extraído; abre os .zip/.rar de dentro)
  3. a pasta  pacotes/  do projeto, se existir
  4. o  saida/Lacador.exe  anterior, se já tiver os instaladores dentro (é o caso normal ao reconstruir)
Cada instalador é conferido pelo SHA-256 do catálogo antes de entrar. Arquivo diferente fica de fora.

Formato do executável: lancador/lancador.exe seguido de um .zip SEM compressão (o lançador só lê assim):
    lacador.id, LEIA-ME.txt, programa/..., ferramentas/..., pacotes/...
"""
import argparse, hashlib, json, os, shutil, subprocess, sys, tempfile, time, zipfile

AQUI = os.path.dirname(os.path.abspath(__file__))
FONTE = os.path.join(AQUI, 'Lacador')
LANCADOR = os.path.join(AQUI, 'lancador', 'lancador.exe')


def crlf(texto):
    return texto.replace('\r\n', '\n').replace('\r', '\n').replace('\n', '\r\n')


def conteudo(caminho):
    """Bytes do arquivo como devem chegar ao Windows."""
    ext = os.path.splitext(caminho)[1].lower()
    if ext in ('.ps1', '.psm1', '.txt'):
        # O Windows PowerShell 5.1 só lê acentos direito em UTF-8 COM BOM.
        return crlf(open(caminho, encoding='utf-8-sig').read()).encode('utf-8-sig')
    if ext == '.json':
        texto = open(caminho, encoding='utf-8-sig').read()
        json.loads(texto)                        # não deixa passar JSON quebrado
        return crlf(texto).encode('utf-8')
    return open(caminho, 'rb').read()


def arquivos_do_programa():
    lista = []
    for pasta in ('programa', 'ferramentas'):
        for raiz, dirs, nomes in os.walk(os.path.join(FONTE, pasta)):
            dirs.sort()
            for nome in sorted(nomes):
                if nome.startswith('.'):
                    continue
                caminho = os.path.join(raiz, nome)
                lista.append((os.path.relpath(caminho, FONTE).replace(os.sep, '/'), conteudo(caminho)))
    lista.append(('LEIA-ME.txt', conteudo(os.path.join(FONTE, 'LEIA-ME.txt'))))
    return lista


def versao_do_motor(arquivos):
    for nome, dados in arquivos:
        if nome == 'programa/Lacador.Motor.psm1':
            for linha in dados.decode('utf-8-sig').splitlines():
                if linha.startswith('$script:VersaoLacador'):
                    return linha.split("'")[1]
    sys.exit('versão não encontrada em Lacador.Motor.psm1')


def sha256_de(caminho):
    h = hashlib.sha256()
    with open(caminho, 'rb') as f:
        for bloco in iter(lambda: f.read(1 << 20), b''):
            h.update(bloco)
    return h.hexdigest().upper()


def pacotes_do_catalogo():
    catalogo = json.load(open(os.path.join(FONTE, 'programa', 'catalogo.json'), encoding='utf-8'))
    vistos, lista = set(), []
    for item in catalogo['itens']:
        for p in item.get('pacotes', []):
            if p['arquivo'] not in vistos:
                vistos.add(p['arquivo'])
                lista.append(p)
    return lista


# ---- abrir o TOKENS.rar (e os .zip/.rar que vêm dentro dele) --------------------------------

def extrair(arquivo, destino):
    """Extrai um .zip/.rar/.7z em destino. Devolve True se conseguiu."""
    os.makedirs(destino, exist_ok=True)
    if arquivo.lower().endswith('.zip'):
        try:
            with zipfile.ZipFile(arquivo) as z:
                z.extractall(destino)
            return True
        except Exception:
            pass
    for comando in (['7z', 'x', '-y'], ['7zz', 'x', '-y'], ['bsdtar', '-xf'], ['tar', '-xf'], ['unar', '-f']):
        if not shutil.which(comando[0]):
            continue
        r = subprocess.run(comando + [arquivo], cwd=destino, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode == 0 and any(nomes for _, _, nomes in os.walk(destino)):
            return True
    return False


def procurar(pasta, trabalho, nivel=0, achados=None, nao_abriu=None):
    achados = [] if achados is None else achados
    nao_abriu = [] if nao_abriu is None else nao_abriu
    for raiz, _, nomes in os.walk(pasta):
        for nome in nomes:
            caminho = os.path.join(raiz, nome)
            achados.append(caminho)
            if nome.lower().endswith(('.rar', '.zip', '.7z')) and nivel < 3:
                dentro = tempfile.mkdtemp(dir=trabalho)
                print('  abrindo', nome, '...')
                if extrair(caminho, dentro):
                    procurar(dentro, trabalho, nivel + 1, achados, nao_abriu)
                else:
                    nao_abriu.append(nome)
    return achados, nao_abriu


def localizar_instaladores(args, trabalho):
    """Devolve {nome: ('arquivo', caminho) ou ('exe', caminho do exe anterior)} só com o que confere."""
    pacotes = pacotes_do_catalogo()
    fontes = {}
    candidatos = []
    if args.pacotes:
        candidatos, _ = procurar(args.pacotes, trabalho, nivel=3)
    elif args.tokens:
        origem = os.path.expanduser(args.tokens)
        if not os.path.exists(origem):
            sys.exit('não encontrei: ' + origem)
        if os.path.isdir(origem):
            candidatos, nao = procurar(origem, trabalho)
        else:
            raiz = tempfile.mkdtemp(dir=trabalho)
            print('  abrindo', os.path.basename(origem), '...')
            if not extrair(origem, raiz):
                sys.exit('não consegui abrir %s. Instale o 7-Zip (no macOS: brew install sevenzip) ou extraia à mão e use --tokens PASTA.' % origem)
            candidatos, nao = procurar(raiz, trabalho, nivel=1)
        if nao:
            print('  AVISO: não consegui abrir:', ', '.join(nao))
    elif os.path.isdir(os.path.join(AQUI, 'pacotes')):
        candidatos, _ = procurar(os.path.join(AQUI, 'pacotes'), trabalho, nivel=3)
    if candidatos:
        por_nome = {}
        for c in candidatos:
            por_nome.setdefault(os.path.basename(c).lower(), []).append(c)
        for p in pacotes:
            tentativas = list(por_nome.get(p['arquivo'].lower(), []))
            tentativas += [c for c in candidatos if os.path.getsize(c) == p['tamanho'] and c not in tentativas]
            for c in tentativas:
                if os.path.getsize(c) == p['tamanho'] and sha256_de(c) == p['sha256'].upper():
                    fontes[p['arquivo']] = ('arquivo', c)
                    break
    # o que ainda falta pode vir do executável anterior
    anterior = os.path.join(AQUI, 'saida', 'Lacador.exe')
    if os.path.isfile(anterior) and len(fontes) < len(pacotes):
        try:
            with zipfile.ZipFile(anterior) as z:
                dentro = {i.filename: i for i in z.infolist()}
                for p in pacotes:
                    i = dentro.get('pacotes/' + p['arquivo'])
                    if p['arquivo'] not in fontes and i is not None and i.file_size == p['tamanho']:
                        fontes[p['arquivo']] = ('exe', anterior)
        except zipfile.BadZipFile:
            pass
    return pacotes, fontes


def main():
    ap = argparse.ArgumentParser(description='Constrói o Lacador.exe completo.')
    ap.add_argument('--tokens', help='TOKENS.rar da ATIC, ou a pasta onde ele foi extraído')
    ap.add_argument('--pacotes', help='pasta com os instaladores já extraídos')
    ap.add_argument('--saida', default=os.path.join(AQUI, 'saida', 'Lacador.exe'))
    ap.add_argument('--sem-instaladores', action='store_true', help='só o programa (para testes rápidos)')
    args = ap.parse_args()

    if not os.path.isfile(LANCADOR):
        sys.exit('falta lancador/lancador.exe (compile com lancador/compilar.sh)')
    arquivos = arquivos_do_programa()
    versao = versao_do_motor(arquivos)
    resumo = hashlib.sha256()
    for nome, dados in arquivos:
        nome.encode('ascii')                     # o lançador só aceita nomes simples
        resumo.update(nome.encode('ascii')); resumo.update(b'\0'); resumo.update(dados)
    ident = '%s-%s' % (versao, resumo.hexdigest()[:10])
    print('Laçador', ident)

    trabalho = tempfile.mkdtemp(prefix='lacador-construir-')
    saida = os.path.abspath(os.path.expanduser(args.saida))
    os.makedirs(os.path.dirname(saida), exist_ok=True)
    provisorio = saida + '.construindo'
    try:
        pacotes, fontes = ([], {}) if args.sem_instaladores else localizar_instaladores(args, trabalho)
        shutil.copyfile(LANCADOR, provisorio)
        agora = time.localtime()[:6]

        def info(nome):
            i = zipfile.ZipInfo(nome, date_time=agora)
            i.compress_type = zipfile.ZIP_STORED
            i.external_attr = 0o644 << 16
            return i

        anterior_zip = None
        with zipfile.ZipFile(provisorio, 'a', zipfile.ZIP_STORED) as z:
            z.writestr(info('lacador.id'), ident.encode('ascii'))
            for nome, dados in arquivos:
                z.writestr(info(nome), dados)
            for p in pacotes:
                if p['arquivo'] not in fontes:
                    continue
                tipo, caminho = fontes[p['arquivo']]
                h = hashlib.sha256()
                if tipo == 'exe':
                    anterior_zip = anterior_zip or zipfile.ZipFile(caminho)
                    entrada = anterior_zip.open('pacotes/' + p['arquivo'])
                else:
                    entrada = open(caminho, 'rb')
                with entrada, z.open(info('pacotes/' + p['arquivo']), 'w') as destino:
                    for bloco in iter(lambda: entrada.read(1 << 20), b''):
                        h.update(bloco)
                        destino.write(bloco)
                if h.hexdigest().upper() != p['sha256'].upper():
                    sys.exit('SHA-256 diferente ao gravar ' + p['arquivo'])
                print('  %-46s %s' % (p['arquivo'], 'do executável anterior' if tipo == 'exe' else 'conferido'))
        if anterior_zip:
            anterior_zip.close()
        for p in pacotes:
            if p['arquivo'] not in fontes:
                print('  %-46s FALTANDO' % p['arquivo'])

        # confere o resultado inteiro (CRC de todas as entradas) antes de trocar o arquivo
        with zipfile.ZipFile(provisorio) as z:
            ruim = z.testzip()
            if ruim:
                sys.exit('entrada corrompida no resultado: ' + ruim)
            dentro = sum(1 for n in z.namelist() if n.startswith('pacotes/'))
        os.replace(provisorio, saida)
        mb = os.path.getsize(saida) / (1 << 20)
        print('\n%s  (%.0f MB, %d de %d instaladores dentro)' % (saida, mb, dentro, len(pacotes)))
        print('SHA-256:', sha256_de(saida))
        if not args.sem_instaladores and dentro < len(pacotes):
            print('\nATENÇÃO: faltam instaladores. Use --tokens CAMINHO/TOKENS.rar para trazer os que faltam.')
            return 1
        return 0
    finally:
        shutil.rmtree(trabalho, ignore_errors=True)
        if os.path.exists(provisorio):
            os.remove(provisorio)


if __name__ == '__main__':
    sys.exit(main())
