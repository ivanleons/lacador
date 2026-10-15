/* ============================================================================
   LAÇADOR - lançador (Lacador.exe)

   O executável é este pequeno programa seguido de um arquivo .zip (sem
   compressão) com tudo dentro:
       lacador.id            identificação desta versão
       programa/...          o Laçador (PowerShell + tela)
       ferramentas/...       instalação no computador
       pacotes/...           os instaladores (drivers, assinador, Firefox, Java...)

   O que ele faz:
     1. Se existir a pasta "programa" ao lado do .exe (Laçador instalado em
        C:\Program Files\Lacador), usa essa.
        Senão, extrai "programa" e "ferramentas" para
        %LOCALAPPDATA%\Lacador\app\<id>  (só na primeira vez de cada versão).
        Os instaladores NÃO são extraídos: o Laçador lê cada um de dentro do
        .exe só na hora de instalar.
     2. Abre o Laçador com o PowerShell do Windows, sem janela preta.
     3. Enquanto o Laçador verifica o computador, mostra a tela de abertura
        (abertura.c). Ela some quando a janela do programa está pronta: o
        PowerShell avisa por um evento do Windows (LACADOR_ABERTURA) e conta o
        andamento num arquivo temporário (LACADOR_ABERTURA_ARQ).

   Uso:
     Lacador.exe                       abre o Laçador
     Lacador.exe -Demo                 abre em modo demonstração
     Lacador.exe /instalar [opções]    libera o computador (Instalar-Lacador.ps1)
     Lacador.exe /agente [opções]      instala/repara sem tela (Lacador-Agente.ps1)
     Lacador.exe /montar [opções]      monta o Lacador-completo.exe a partir do TOKENS.rar
   Nesses três o lançador espera terminar e devolve o código de saída.
   ============================================================================ */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "abertura.h"
#include "versao.h"

#define CAMINHO 1024
#define TITULO L"La\u00e7ador"

#define LARG(x) L##x
#define AMPLO(x) LARG(x)

static void avisar(const wchar_t *texto) { abertura_fechar_ja(); MessageBoxW(NULL, texto, TITULO, MB_OK | MB_ICONERROR); }

static uint16_t u16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t u32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

static BOOL ler_em(HANDLE h, uint64_t pos, void *buf, DWORD n) {
    LARGE_INTEGER li; DWORD lido = 0;
    li.QuadPart = (LONGLONG)pos;
    if (!SetFilePointerEx(h, li, NULL, FILE_BEGIN)) return FALSE;
    return ReadFile(h, buf, n, &lido, NULL) && lido == n;
}

static BOOL existe(const wchar_t *caminho) { return GetFileAttributesW(caminho) != INVALID_FILE_ATTRIBUTES; }

/* Cria a pasta e todas as pastas acima dela. */
static void criar_pastas(const wchar_t *pasta) {
    wchar_t tmp[CAMINHO]; size_t i, n = wcslen(pasta);
    if (n >= CAMINHO) return;
    wcscpy(tmp, pasta);
    for (i = 3; i < n; i++) {
        if (tmp[i] == L'\\') { tmp[i] = 0; CreateDirectoryW(tmp, NULL); tmp[i] = L'\\'; }
    }
    CreateDirectoryW(tmp, NULL);
}

static void apagar_pasta(const wchar_t *pasta) {
    wchar_t busca[CAMINHO], item[CAMINHO]; WIN32_FIND_DATAW fd; HANDLE h;
    if (wcslen(pasta) + 3 >= CAMINHO) return;
    swprintf(busca, CAMINHO, L"%ls\\*", pasta);
    h = FindFirstFileW(busca, &fd);
    if (h != INVALID_HANDLE_VALUE) {
        do {
            if (!wcscmp(fd.cFileName, L".") || !wcscmp(fd.cFileName, L"..")) continue;
            if (wcslen(pasta) + wcslen(fd.cFileName) + 2 >= CAMINHO) continue;
            swprintf(item, CAMINHO, L"%ls\\%ls", pasta, fd.cFileName);
            if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && !(fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) apagar_pasta(item);
            else { SetFileAttributesW(item, FILE_ATTRIBUTE_NORMAL); DeleteFileW(item); }
        } while (FindNextFileW(h, &fd));
        FindClose(h);
    }
    RemoveDirectoryW(pasta);
}

/* ---- leitura do .zip que fica no fim do executável ---- */
typedef struct {
    HANDLE h;
    uint8_t *dir;        /* diretório central inteiro */
    uint32_t tam_dir;
    uint32_t entradas;
    int64_t delta;       /* soma aos deslocamentos gravados no zip (0 quando já são absolutos) */
} Zip;

static BOOL abrir_zip(const wchar_t *exe, Zip *z) {
    LARGE_INTEGER tam; uint8_t *fim; DWORD nfim; int64_t i, pos_fim = -1; uint64_t ini_fim, pos_dir; uint32_t tam_dir, des_dir; uint8_t sig[4];
    memset(z, 0, sizeof(*z));
    z->h = CreateFileW(exe, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (z->h == INVALID_HANDLE_VALUE) return FALSE;
    if (!GetFileSizeEx(z->h, &tam) || tam.QuadPart < 22) return FALSE;
    nfim = (DWORD)(tam.QuadPart < 65558 ? tam.QuadPart : 65558);
    ini_fim = (uint64_t)tam.QuadPart - nfim;
    fim = (uint8_t *)malloc(nfim);
    if (!fim || !ler_em(z->h, ini_fim, fim, nfim)) { free(fim); return FALSE; }
    for (i = (int64_t)nfim - 22; i >= 0; i--) {
        if (fim[i] == 'P' && fim[i + 1] == 'K' && fim[i + 2] == 5 && fim[i + 3] == 6 && (uint64_t)i + 22 + u16(fim + i + 20) <= nfim) { pos_fim = i; break; }
    }
    if (pos_fim < 0) { free(fim); return FALSE; }
    z->entradas = u16(fim + pos_fim + 10);
    tam_dir = u32(fim + pos_fim + 12);
    des_dir = u32(fim + pos_fim + 16);
    free(fim);
    if (tam_dir == 0 || tam_dir > 32u * 1024 * 1024 || des_dir == 0xFFFFFFFFu) return FALSE;
    /* O diretório central termina onde começa o registro final. */
    pos_dir = ini_fim + (uint64_t)pos_fim - tam_dir;
    z->delta = (int64_t)pos_dir - (int64_t)des_dir;
    if (!ler_em(z->h, pos_dir, sig, 4) || u32(sig) != 0x02014b50u) return FALSE;
    z->dir = (uint8_t *)malloc(tam_dir);
    if (!z->dir || !ler_em(z->h, pos_dir, z->dir, tam_dir)) return FALSE;
    z->tam_dir = tam_dir;
    return TRUE;
}

/* Percorre o diretório central. Devolve o ponteiro da próxima entrada, ou NULL no fim/erro. */
static const uint8_t *entrada(const Zip *z, const uint8_t *p, const char **nome, uint16_t *nnome, uint16_t *metodo, uint32_t *tam_c, uint32_t *tam, uint32_t *des) {
    const uint8_t *fim = z->dir + z->tam_dir; uint16_t n, x, c;
    if (!p) p = z->dir;
    if (p + 46 > fim || u32(p) != 0x02014b50u) return NULL;
    *metodo = u16(p + 10); *tam_c = u32(p + 20); *tam = u32(p + 24);
    n = u16(p + 28); x = u16(p + 30); c = u16(p + 32);
    *des = u32(p + 42);
    if (p + 46 + n + x + c > fim) return NULL;
    *nome = (const char *)(p + 46); *nnome = n;
    return p + 46 + n + x + c;
}

static BOOL nome_seguro(const char *nome, uint16_t n) {
    uint16_t i;
    if (n == 0 || n > 200 || nome[0] == '/') return FALSE;
    for (i = 0; i < n; i++) {
        unsigned char ch = (unsigned char)nome[i];
        if (ch < 32 || ch > 126 || ch == '\\' || ch == ':' || ch == '*' || ch == '?' || ch == '"' || ch == '<' || ch == '>' || ch == '|') return FALSE;
        if (ch == '.' && i + 1 < n && nome[i + 1] == '.') return FALSE;
    }
    return TRUE;
}

static BOOL comeca(const char *nome, uint16_t n, const char *prefixo) { size_t k = strlen(prefixo); return n >= k && !memcmp(nome, prefixo, k); }

/* Copia os bytes de uma entrada (sem compressão) para um arquivo. */
static BOOL extrair(const Zip *z, uint32_t des, uint32_t tam, const wchar_t *destino) {
    uint8_t cab[30]; uint64_t pos; HANDLE o; uint8_t *buf; uint32_t falta = tam; BOOL ok = TRUE;
    if (!ler_em(z->h, (uint64_t)((int64_t)des + z->delta), cab, 30) || u32(cab) != 0x04034b50u) return FALSE;
    pos = (uint64_t)((int64_t)des + z->delta) + 30 + u16(cab + 26) + u16(cab + 28);
    o = CreateFileW(destino, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (o == INVALID_HANDLE_VALUE) return FALSE;
    buf = (uint8_t *)malloc(65536);
    if (!buf) { CloseHandle(o); return FALSE; }
    while (falta && ok) {
        DWORD n = falta > 65536 ? 65536 : falta, gravado = 0;
        ok = ler_em(z->h, pos, buf, n) && WriteFile(o, buf, n, &gravado, NULL) && gravado == n;
        pos += n; falta -= n;
    }
    free(buf); CloseHandle(o);
    return ok;
}

/* Lê o identificador da versão (entrada "lacador.id"): só letras, números, ponto e hífen. */
static BOOL ler_id(const Zip *z, wchar_t *id, size_t max) {
    const uint8_t *p = NULL; const char *nome; uint16_t n, metodo; uint32_t tc, t, des;
    while ((p = entrada(z, p, &nome, &n, &metodo, &tc, &t, &des)) != NULL) {
        if (n == 10 && !memcmp(nome, "lacador.id", 10)) {
            uint8_t cab[30], txt[64]; uint64_t pos; uint32_t i, k = 0;
            if (metodo != 0 || t == 0 || t > 60) return FALSE;
            if (!ler_em(z->h, (uint64_t)((int64_t)des + z->delta), cab, 30) || u32(cab) != 0x04034b50u) return FALSE;
            pos = (uint64_t)((int64_t)des + z->delta) + 30 + u16(cab + 26) + u16(cab + 28);
            if (!ler_em(z->h, pos, txt, t)) return FALSE;
            for (i = 0; i < t && k + 1 < max; i++) {
                uint8_t ch = txt[i];
                if ((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '.' || ch == '-') id[k++] = (wchar_t)ch;
            }
            id[k] = 0;
            return k > 0;
        }
    }
    return FALSE;
}

/* Extrai tudo, menos os instaladores, para a pasta indicada. */
static BOOL extrair_programa(const Zip *z, const wchar_t *pasta) {
    const uint8_t *p = NULL; const char *nome; uint16_t n, metodo, i; uint32_t tc, t, des; int feitos = 0;
    while ((p = entrada(z, p, &nome, &n, &metodo, &tc, &t, &des)) != NULL) {
        wchar_t rel[256], alvo[CAMINHO], dir[CAMINHO]; wchar_t *barra;
        if (comeca(nome, n, "pacotes/")) continue;
        if (n > 0 && nome[n - 1] == '/') continue;                 /* entrada de pasta */
        if (!nome_seguro(nome, n) || metodo != 0 || tc != t) return FALSE;
        for (i = 0; i < n; i++) rel[i] = (nome[i] == '/') ? L'\\' : (wchar_t)(unsigned char)nome[i];
        rel[n] = 0;
        if (wcslen(pasta) + n + 2 >= CAMINHO) return FALSE;
        swprintf(alvo, CAMINHO, L"%ls\\%ls", pasta, rel);
        wcscpy(dir, alvo);
        barra = wcsrchr(dir, L'\\');
        if (barra) { *barra = 0; criar_pastas(dir); }
        if (!extrair(z, des, t, alvo)) return FALSE;
        feitos++;
    }
    return feitos > 0;
}

/* Pula o nome do programa na linha de comando e devolve o resto. */
static const wchar_t *argumentos(void) {
    const wchar_t *c = GetCommandLineW();
    if (*c == L'"') { c++; while (*c && *c != L'"') c++; if (*c) c++; }
    else { while (*c && *c != L' ' && *c != L'\t') c++; }
    while (*c == L' ' || *c == L'\t') c++;
    return c;
}

static BOOL verbo(const wchar_t **resto, const wchar_t *nome) {
    size_t k = wcslen(nome); const wchar_t *r = *resto;
    if (_wcsnicmp(r, nome, k) != 0) return FALSE;
    if (r[k] != 0 && r[k] != L' ' && r[k] != L'\t') return FALSE;
    r += k;
    while (*r == L' ' || *r == L'\t') r++;
    *resto = r;
    return TRUE;
}

static BOOL contem_sem_caixa(const wchar_t *texto, const wchar_t *trecho) {
    size_t k = wcslen(trecho);
    for (; *texto; texto++) if (_wcsnicmp(texto, trecho, k) == 0) return TRUE;
    return FALSE;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE ant, LPWSTR linha, int mostrar) {
    wchar_t exe[CAMINHO], pasta_exe[CAMINHO], raiz[CAMINHO], teste[CAMINHO], ps[CAMINHO], script[CAMINHO];
    wchar_t *barra, *cmd; const wchar_t *resto; const wchar_t *arquivo = L"programa\\Lacador.ps1";
    BOOL esperar = FALSE, oculto = TRUE, montar = FALSE, abertura = FALSE; size_t tam_cmd;
    STARTUPINFOW si; PROCESS_INFORMATION pi; DWORD codigo = 0, n;
    wchar_t arq_abertura[CAMINHO], nome_evento[96]; HANDLE evento = NULL;
    (void)inst; (void)ant; (void)linha; (void)mostrar;

    /* O que abrir */
    resto = argumentos();
    if (verbo(&resto, L"/instalar")) { arquivo = L"ferramentas\\Instalar-Lacador.ps1"; esperar = TRUE; oculto = contem_sem_caixa(resto, L"-silencioso"); }
    else if (verbo(&resto, L"/agente")) { arquivo = L"programa\\Lacador-Agente.ps1"; esperar = TRUE; oculto = FALSE; }
    else if (verbo(&resto, L"/montar")) { arquivo = L"ferramentas\\Preparar-Pacotes.ps1"; esperar = TRUE; oculto = contem_sem_caixa(resto, L"-silencioso"); montar = TRUE; }

    /* Tela de abertura: só ao abrir a tela do Laçador (não nos comandos), e já antes de extrair. */
    if (!esperar && !contem_sem_caixa(resto, L"-semjanela") && GetEnvironmentVariableW(L"LACADOR_SEM_ABERTURA", teste, CAMINHO) == 0) {
        DWORD k = GetTempPathW(CAMINHO - 64, arq_abertura);
        if (k > 0 && k < CAMINHO - 64) {
            swprintf(arq_abertura + k, CAMINHO - k, L"lacador-abertura-%lu.txt", (unsigned long)GetCurrentProcessId());
            DeleteFileW(arq_abertura);
            swprintf(nome_evento, 96, L"Local\\LacadorAbertura-%lu", (unsigned long)GetCurrentProcessId());
            evento = CreateEventW(NULL, TRUE, FALSE, nome_evento);
            if (evento && abertura_iniciar(arq_abertura, L"v" AMPLO(LACADOR_VERSAO_TXT))) abertura = TRUE;
            else { abertura_fechar_ja(); if (evento) { CloseHandle(evento); evento = NULL; } }
        }
    }

    n = GetModuleFileNameW(NULL, exe, CAMINHO);
    if (n == 0 || n >= CAMINHO - 1) { avisar(L"N\u00e3o foi poss\u00edvel localizar o Lacador.exe (caminho longo demais)."); return 1; }
    wcscpy(pasta_exe, exe);
    barra = wcsrchr(pasta_exe, L'\\');
    if (barra) *barra = 0;

    /* 1. Onde está o programa? */
    swprintf(teste, CAMINHO, L"%ls\\programa\\Lacador.ps1", pasta_exe);
    if (existe(teste)) {
        wcscpy(raiz, pasta_exe);
    } else {
        Zip z; wchar_t id[64], base[CAMINHO], marca[CAMINHO], tmp[CAMINHO]; DWORD k;
        if (!abrir_zip(exe, &z) || !ler_id(&z, id, 64)) {
            avisar(L"Este Lacador.exe est\u00e1 incompleto ou foi alterado.\n\nCopie o arquivo de novo a partir do original.");
            return 1;
        }
        k = GetEnvironmentVariableW(L"LOCALAPPDATA", base, CAMINHO);
        if (k == 0 || k >= CAMINHO - 80) {
            if (FAILED(SHGetFolderPathW(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, base))) { avisar(L"N\u00e3o foi poss\u00edvel localizar a pasta do usu\u00e1rio."); return 1; }
        }
        wcscat(base, L"\\Lacador\\app");
        swprintf(raiz, CAMINHO, L"%ls\\%ls", base, id);
        swprintf(marca, CAMINHO, L"%ls\\pronto.txt", raiz);
        if (!existe(marca)) {
            HANDLE m;
            swprintf(tmp, CAMINHO, L"%ls\\%ls.tmp%lu", base, id, (unsigned long)GetCurrentProcessId());
            apagar_pasta(tmp);
            criar_pastas(tmp);
            if (!extrair_programa(&z, tmp)) {
                apagar_pasta(tmp);
                avisar(L"N\u00e3o foi poss\u00edvel preparar o La\u00e7ador.\n\nVerifique se h\u00e1 espa\u00e7o no disco e se o antiv\u00edrus n\u00e3o bloqueou o arquivo.");
                return 1;
            }
            swprintf(marca, CAMINHO, L"%ls\\pronto.txt", tmp);
            m = CreateFileW(marca, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
            if (m != INVALID_HANDLE_VALUE) CloseHandle(m);
            if (!MoveFileExW(tmp, raiz, 0)) {
                /* Já existe uma pasta com esse nome: completa (outra janela abriu junto) ou pela metade. */
                swprintf(marca, CAMINHO, L"%ls\\pronto.txt", raiz);
                if (existe(marca)) apagar_pasta(tmp);
                else { apagar_pasta(raiz); if (!MoveFileExW(tmp, raiz, 0)) wcscpy(raiz, tmp); }
            }
        }
        CloseHandle(z.h);
        free(z.dir);
    }

    /* 2. O script */
    swprintf(script, CAMINHO, L"%ls\\%ls", raiz, arquivo);
    if (!existe(script)) { avisar(L"O La\u00e7ador n\u00e3o foi encontrado depois de preparado.\n\nO antiv\u00edrus pode ter removido os arquivos."); return 1; }

    n = GetSystemDirectoryW(ps, CAMINHO);
    if (n == 0 || n >= CAMINHO - 60) { avisar(L"N\u00e3o foi poss\u00edvel localizar o Windows."); return 1; }
    wcscat(ps, L"\\WindowsPowerShell\\v1.0\\powershell.exe");
    if (!existe(ps)) { avisar(L"O PowerShell do Windows n\u00e3o foi encontrado neste computador."); return 1; }

    tam_cmd = wcslen(ps) + wcslen(script) + wcslen(resto) + 96;
    cmd = (wchar_t *)malloc(tam_cmd * sizeof(wchar_t));
    if (!cmd) return 1;
    swprintf(cmd, tam_cmd, L"\"%ls\" -NoProfile -ExecutionPolicy Bypass -File \"%ls\"%ls%ls%ls", ps, script, montar ? L" -Montar -Pausar" : L"", *resto ? L" " : L"", resto);

    /* O Laçador precisa saber onde está o executável: é dele que saem os instaladores. */
    SetEnvironmentVariableW(L"LACADOR_EXE", exe);
    if (abertura) {
        SetEnvironmentVariableW(L"LACADOR_ABERTURA", nome_evento);
        SetEnvironmentVariableW(L"LACADOR_ABERTURA_ARQ", arq_abertura);
    }

    if (GetEnvironmentVariableW(L"LACADOR_DEPURAR", teste, CAMINHO) > 0) {
        wchar_t reg[CAMINHO]; HANDLE r; DWORD g;
        if (GetTempPathW(CAMINHO - 40, reg) > 0) {
            wcscat(reg, L"lacador-lancador.log");
            r = CreateFileW(reg, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
            if (r != INVALID_HANDLE_VALUE) { WriteFile(r, cmd, (DWORD)(wcslen(cmd) * sizeof(wchar_t)), &g, NULL); CloseHandle(r); }
        }
    }

    /* Console criado já escondido: nenhuma janela preta pisca, nem do PowerShell nem do que ele chamar. */
    memset(&si, 0, sizeof(si)); si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = oculto ? SW_HIDE : SW_SHOWNORMAL;
    if (!CreateProcessW(ps, cmd, NULL, NULL, FALSE, CREATE_NEW_CONSOLE, NULL, raiz, &si, &pi)) {
        avisar(L"N\u00e3o foi poss\u00edvel abrir o PowerShell do Windows.\n\nO antiv\u00edrus ou uma pol\u00edtica do computador pode estar bloqueando.");
        free(cmd);
        return 1;
    }
    if (esperar) { WaitForSingleObject(pi.hProcess, INFINITE); GetExitCodeProcess(pi.hProcess, &codigo); }
    if (abertura) {
        /* Espera a janela do programa ficar pronta. Se algo der errado, a abertura não fica presa na tela. */
        HANDLE alvos[2]; DWORD t0 = GetTickCount(), janela_em = 0;
        alvos[0] = evento; alvos[1] = pi.hProcess;
        AllowSetForegroundWindow(ASFW_ANY);
        for (;;) {
            DWORD r = WaitForMultipleObjects(2, alvos, FALSE, 200), agora = GetTickCount();
            if (r == WAIT_OBJECT_0 || r == WAIT_OBJECT_0 + 1 || r == WAIT_FAILED) break;
            if (abertura_janela_aberta() && !janela_em) janela_em = agora;
            if (janela_em && agora - janela_em > 25000) break;               /* a janela abriu, mas a página não avisou */
            if (!abertura_teve_progresso() && agora - t0 > 45000) break;     /* o PowerShell não deu sinal */
            if (agora - t0 > 240000) break;
        }
        AllowSetForegroundWindow(ASFW_ANY);
        abertura_fechar();
        DeleteFileW(arq_abertura);
        CloseHandle(evento);
    }
    CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
    free(cmd);
    return (int)codigo;
}
