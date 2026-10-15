/* ============================================================================
   LAÇADOR - tela de abertura

   Uma janela própria, sem bordas, com a arte da estátua, que aparece assim que
   o Lacador.exe é aberto e fica até a janela do programa estar pronta. Mostra o
   andamento real da verificação: o PowerShell escreve "percentual<TAB>fase<TAB>etapa"
   num arquivo temporário e esta tela lê esse arquivo.

   Desenho com GDI+ numa janela com transparência por pixel (cantos arredondados
   suaves e sombra), no tamanho certo para a escala da tela (DPI).
   ============================================================================ */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <shlwapi.h>
#include <math.h>
#include <string.h>
#include <wchar.h>
#include "abertura.h"
#include "versao.h"

#define ID_ARTE      2            /* recurso RCDATA com a arte (JPEG) */
#define MSG_FECHAR   (WM_APP + 1)
#define MSG_SUMIR    (WM_APP + 2)
#define BASE_L       720.0f       /* tamanho da abertura, em pixels de 96 DPI */
#define BASE_A       450.0f
#define CSS(v)       ((float)(v) * A.f)   /* medidas do desenho original (quadro de 800x500) */

#define COR(a, r, g, b) ((ARGB)(((DWORD)(BYTE)(a) << 24) | ((DWORD)(BYTE)(r) << 16) | ((DWORD)(BYTE)(g) << 8) | (DWORD)(BYTE)(b)))
#define LARG(x) L##x
#define AMPLO(x) LARG(x)

static struct {
    HWND jan;
    HANDLE thread, criada;
    BOOL ativa;
    wchar_t arq[1024];
    wchar_t versao[40];
    wchar_t etapa[200];
    volatile LONG janela_aberta, teve_progresso;
    int alvo;
    double mostrado;
    float s, f;                 /* s: escala da tela; f: escala sobre o quadro de 800x500 */
    int margem, larg, alt, jl, ja, x, y;
    int alfa, fase;             /* fase: 0 entrando, 1 parada, 2 saindo */
    DWORD t0, lido_em;
    ULONG_PTR gdip;
    IStream *fluxo;
    GpBitmap *arte;
    GpFontFamily *fam, *fam_semi;
    HDC dc;
    HBITMAP dib, dib_velho;
    BYTE *bits;
    BYTE *fundo;                /* cópia do fundo pronto (arte, sombra e textos fixos) */
    GpBitmap *quadro;           /* GDI+ desenhando direto nos bits do DIB */
} A;

/* ---------- utilidades ---------- */

static UINT dpi_do_monitor(HMONITOR m) {
    typedef HRESULT (WINAPI *GetDpiForMonitor_t)(HMONITOR, int, UINT *, UINT *);
    HMODULE sh = LoadLibraryW(L"shcore.dll");
    UINT x = 0, y = 0;
    if (sh) {
        GetDpiForMonitor_t f = (GetDpiForMonitor_t)(void *)GetProcAddress(sh, "GetDpiForMonitor");
        if (f && f(m, 0, &x, &y) == S_OK && x >= 72) { FreeLibrary(sh); return x; }
        FreeLibrary(sh);
    }
    {
        HDC t = GetDC(NULL);
        x = (UINT)GetDeviceCaps(t, LOGPIXELSX);
        ReleaseDC(NULL, t);
    }
    return x >= 72 ? x : 96;
}

static GpBitmap *carregar_arte(void) {
    HRSRC r = FindResourceW(NULL, MAKEINTRESOURCEW(ID_ARTE), (LPCWSTR)RT_RCDATA);
    HGLOBAL g; const BYTE *p; DWORD n; GpBitmap *b = NULL;
    if (!r) return NULL;
    g = LoadResource(NULL, r);
    if (!g) return NULL;
    p = (const BYTE *)LockResource(g);
    n = SizeofResource(NULL, r);
    if (!p || !n) return NULL;
    A.fluxo = SHCreateMemStream(p, n);
    if (!A.fluxo) return NULL;
    if (GdipCreateBitmapFromStream(A.fluxo, &b) != Ok) return NULL;
    return b;
}

static GpFontFamily *familia(const wchar_t *nome) {
    GpFontFamily *f = NULL;
    if (GdipCreateFontFamilyFromName(nome, NULL, &f) == Ok) return f;
    if (GdipCreateFontFamilyFromName(L"Segoe UI", NULL, &f) == Ok) return f;
    GdipGetGenericFontFamilySansSerif(&f);
    return f;
}

static void caminho_arredondado(GpPath *p, float x, float y, float w, float h, float r) {
    float d = r * 2;
    if (d > w) d = w;
    if (d > h) d = h;
    GdipAddPathArc(p, x, y, d, d, 180, 90);
    GdipAddPathArc(p, x + w - d, y, d, d, 270, 90);
    GdipAddPathArc(p, x + w - d, y + h - d, d, d, 0, 90);
    GdipAddPathArc(p, x, y + h - d, d, d, 90, 90);
    GdipClosePathFigure(p);
}

static void preencher_arredondado(GpGraphics *g, GpBrush *b, float x, float y, float w, float h, float r) {
    GpPath *p = NULL;
    if (GdipCreatePath(FillModeAlternate, &p) != Ok) return;
    caminho_arredondado(p, x, y, w, h, r);
    GdipFillPath(g, b, p);
    GdipDeletePath(p);
}

/* alinhar: 0 esquerda, 1 centro, 2 direita */
static void escrever(GpGraphics *g, const wchar_t *texto, GpFontFamily *fam, float px, ARGB cor, float x, float y, float w, float h, int alinhar) {
    GpFont *fonte = NULL; GpSolidFill *pincel = NULL; GpStringFormat *fmt = NULL; RectF r;
    if (!texto || !*texto) return;
    if (GdipCreateFont(fam, px, FontStyleRegular, UnitPixel, &fonte) != Ok) return;
    GdipCreateSolidFill(cor, &pincel);
    GdipCreateStringFormat(StringFormatFlagsNoWrap, LANG_NEUTRAL, &fmt);
    GdipSetStringFormatAlign(fmt, alinhar == 1 ? StringAlignmentCenter : (alinhar == 2 ? StringAlignmentFar : StringAlignmentNear));
    GdipSetStringFormatLineAlign(fmt, StringAlignmentCenter);
    GdipSetStringFormatTrimming(fmt, StringTrimmingEllipsisCharacter);
    r.X = x; r.Y = y; r.Width = w; r.Height = h;
    GdipDrawString(g, texto, -1, fonte, &r, fmt, (GpBrush *)pincel);
    GdipDeleteStringFormat(fmt);
    GdipDeleteBrush((GpBrush *)pincel);
    GdipDeleteFont(fonte);
}

/* Texto centralizado com espaço entre as letras (o subtítulo da abertura). */
static void escrever_espacado(GpGraphics *g, const wchar_t *texto, GpFontFamily *fam, float px, float espaco, ARGB cor, float cx, float y, float h) {
    GpFont *fonte = NULL; GpSolidFill *pincel = NULL; GpStringFormat *fmt = NULL;
    float larguras[96], total = 0, x; int n = (int)wcslen(texto), i;
    if (n <= 0 || n > 96) return;
    if (GdipCreateFont(fam, px, FontStyleRegular, UnitPixel, &fonte) != Ok) return;
    GdipCreateSolidFill(cor, &pincel);
    {   /* cópia do formato tipográfico (o original é compartilhado e não pode ser alterado) */
        GpStringFormat *gen = NULL;
        GdipStringFormatGetGenericTypographic(&gen);
        if (!gen || GdipCloneStringFormat(gen, &fmt) != Ok) { GdipDeleteBrush((GpBrush *)pincel); GdipDeleteFont(fonte); return; }
    }
    GdipSetStringFormatFlags(fmt, StringFormatFlagsNoWrap | StringFormatFlagsNoClip | StringFormatFlagsMeasureTrailingSpaces);
    for (i = 0; i < n; i++) {
        RectF lay = { 0, 0, 1000, 200 }, caixa = { 0, 0, 0, 0 };
        GdipMeasureString(g, texto + i, 1, fonte, &lay, fmt, &caixa, NULL, NULL);
        larguras[i] = caixa.Width;
        total += caixa.Width;
    }
    total += espaco * (float)(n - 1);
    x = cx - total / 2;
    for (i = 0; i < n; i++) {
        RectF r; r.X = x; r.Y = y; r.Width = larguras[i] + 4; r.Height = h;
        if (texto[i] != L' ') GdipDrawString(g, texto + i, 1, fonte, &r, fmt, (GpBrush *)pincel);
        x += larguras[i] + espaco;
    }
    GdipDeleteStringFormat(fmt);
    GdipDeleteBrush((GpBrush *)pincel);
    GdipDeleteFont(fonte);
}

/* ---------- desenho ---------- */

/* Fundo: sombra, arte com cantos arredondados e os textos que não mudam. Feito uma vez. */
static BOOL preparar_fundo(void) {
    GpGraphics *g = NULL; GpBitmap *escalada = NULL; GpGraphics *ge = NULL; GpTexture *tex = NULL; GpSolidFill *sombra = NULL;
    float m = (float)A.margem, raio = 16.0f * A.s; int i, camadas = 16;
    size_t tam = (size_t)A.jl * (size_t)A.ja * 4;

    memset(A.bits, 0, tam);
    if (GdipGetImageGraphicsContext((GpImage *)A.quadro, &g) != Ok) return FALSE;
    GdipSetSmoothingMode(g, SmoothingModeAntiAlias);
    GdipSetPixelOffsetMode(g, PixelOffsetModeHighQuality);
    GdipSetTextRenderingHint(g, TextRenderingHintAntiAliasGridFit);

    /* sombra suave: camadas arredondadas cada vez menores, quase transparentes */
    for (i = 0; i < camadas; i++) {
        float k = (float)i / (float)camadas, recuo = m * (1.0f - k) * 0.95f;
        GdipCreateSolidFill(COR((BYTE)(4 + i / 3), 4, 14, 32), &sombra);
        preencher_arredondado(g, (GpBrush *)sombra, m - recuo, m - recuo + 8.0f * A.s * (1.0f - k * 0.5f), (float)A.larg + 2 * recuo, (float)A.alt + 2 * recuo, raio + recuo);
        GdipDeleteBrush((GpBrush *)sombra);
    }

    /* a arte, já no tamanho final, vira a textura de um retângulo arredondado (borda suave) */
    if (GdipCreateBitmapFromScan0(A.larg, A.alt, 0, PixelFormat32bppPARGB, NULL, &escalada) != Ok) { GdipDeleteGraphics(g); return FALSE; }
    GdipGetImageGraphicsContext((GpImage *)escalada, &ge);
    GdipSetInterpolationMode(ge, InterpolationModeHighQualityBicubic);
    GdipSetPixelOffsetMode(ge, PixelOffsetModeHighQuality);
    GdipDrawImageRectI(ge, (GpImage *)A.arte, 0, 0, A.larg, A.alt);
    GdipDeleteGraphics(ge);
    if (GdipCreateTexture((GpImage *)escalada, WrapModeClamp, &tex) == Ok) {
        GdipTranslateTextureTransform(tex, m, m, MatrixOrderAppend);
        preencher_arredondado(g, (GpBrush *)tex, m, m, (float)A.larg, (float)A.alt, raio);
        GdipDeleteBrush((GpBrush *)tex);
    }
    GdipDisposeImage((GpImage *)escalada);

    /* textos fixos (posições do desenho aprovado, quadro de 800x500) */
    escrever_espacado(g, L"SISTEMA DE GERENCIAMENTO DE TOKENS", A.fam_semi, CSS(13), CSS(3.9), COR(255, 0xE8, 0xEE, 0xF5), m + CSS(400), m + CSS(412), CSS(18));
    escrever(g, AMPLO(LACADOR_CREDITO), A.fam, CSS(11), COR(255, 0xA9, 0xBC, 0xD9), m + CSS(28), m + CSS(464), CSS(260), CSS(20), 0);
    escrever(g, A.versao, A.fam, CSS(11), COR(255, 0xA9, 0xBC, 0xD9), m + CSS(600), m + CSS(464), CSS(172), CSS(20), 2);
    GdipDeleteGraphics(g);
    GdipFlush(NULL, FlushIntentionSync);
    memcpy(A.fundo, A.bits, tam);
    return TRUE;
}

static double suave(double t) { return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2; }

static void compor_e_mostrar(void) {
    GpGraphics *g = NULL; GpSolidFill *b = NULL; GpPath *p = NULL; GpLineGradient *brilho = NULL;
    float m = (float)A.margem, bl = CSS(264), bh = CSS(5), bx = m + CSS(400) - bl / 2, by = m + CSS(450), cheio;
    POINT origem = { 0, 0 }, pos; SIZE tam; BLENDFUNCTION mistura;

    memcpy(A.bits, A.fundo, (size_t)A.jl * (size_t)A.ja * 4);
    if (GdipGetImageGraphicsContext((GpImage *)A.quadro, &g) == Ok) {
        GdipSetSmoothingMode(g, SmoothingModeAntiAlias);
        GdipSetPixelOffsetMode(g, PixelOffsetModeHighQuality);
        GdipSetTextRenderingHint(g, TextRenderingHintAntiAliasGridFit);

        /* trilho da barra */
        GdipCreateSolidFill(COR(46, 0xE8, 0xEE, 0xF5), &b);
        preencher_arredondado(g, (GpBrush *)b, bx, by, bl, bh, bh / 2);
        GdipDeleteBrush((GpBrush *)b);

        /* parte cheia + brilho que corre por dentro dela */
        cheio = bl * (float)(A.mostrado < 4 ? 4 : A.mostrado) / 100.0f;
        if (GdipCreatePath(FillModeAlternate, &p) == Ok) {
            caminho_arredondado(p, bx, by, cheio, bh, bh / 2);
            GdipCreateSolidFill(COR(255, 0x3A, 0x7B, 0xD5), &b);
            GdipFillPath(g, (GpBrush *)b, p);
            GdipDeleteBrush((GpBrush *)b);
            {
                double t = (double)((GetTickCount() - A.t0) % 1900) / 1900.0;
                float lb = cheio * 0.4f, x0 = bx + (float)((-1.2 + 4.4 * suave(t)) * lb);
                GpPointF p1, p2; ARGB cores[3]; REAL posicoes[3] = { 0.0f, 0.5f, 1.0f };
                p1.X = x0; p1.Y = by; p2.X = x0 + lb; p2.Y = by;
                cores[0] = COR(0, 255, 255, 255); cores[1] = COR(153, 255, 255, 255); cores[2] = COR(0, 255, 255, 255);
                if (lb > 1 && GdipCreateLineBrush(&p1, &p2, cores[0], cores[2], WrapModeTileFlipX, &brilho) == Ok) {
                    GdipSetLinePresetBlend(brilho, cores, posicoes, 3);
                    GdipSetClipPath(g, p, CombineModeReplace);
                    GdipFillRectangle(g, (GpBrush *)brilho, x0, by, lb, bh);
                    GdipResetClip(g);
                    GdipDeleteBrush((GpBrush *)brilho);
                }
            }
            GdipDeletePath(p);
        }

        /* etapa atual */
        escrever(g, A.etapa, A.fam, CSS(12.5), COR(255, 0xD3, 0xDE, 0xEE), m + CSS(230), m + CSS(464), CSS(340), CSS(20), 1);
        GdipDeleteGraphics(g);
        GdipFlush(NULL, FlushIntentionSync);
    }

    pos.x = A.x; pos.y = A.y; tam.cx = A.jl; tam.cy = A.ja;
    mistura.BlendOp = AC_SRC_OVER; mistura.BlendFlags = 0; mistura.SourceConstantAlpha = (BYTE)A.alfa; mistura.AlphaFormat = AC_SRC_ALPHA;
    UpdateLayeredWindow(A.jan, NULL, &pos, &tam, A.dc, &origem, 0, &mistura, ULW_ALPHA);
}

/* ---------- andamento escrito pelo PowerShell ---------- */

static void ler_andamento(void) {
    HANDLE h; char buf[1024]; DWORD n = 0; wchar_t w[600], *tab1, *tab2; int k;
    h = CreateFileW(A.arq, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    if (!ReadFile(h, buf, sizeof(buf) - 1, &n, NULL)) n = 0;
    CloseHandle(h);
    if (n < 3) return;
    buf[n] = 0;
    k = MultiByteToWideChar(CP_UTF8, 0, buf, (int)n, w, 599);
    if (k <= 0) return;
    w[k] = 0;
    tab1 = wcschr(w, L'\t');
    if (!tab1) return;
    *tab1 = 0;
    tab2 = wcschr(tab1 + 1, L'\t');
    if (!tab2) return;
    *tab2 = 0;
    {
        int pct = _wtoi(w);
        wchar_t *fim;
        if (pct < 0) pct = 0;
        if (pct > 100) pct = 100;
        A.alvo = pct;
        if (!wcscmp(tab1 + 1, L"janela")) InterlockedExchange(&A.janela_aberta, 1);
        for (fim = tab2 + 1; *fim; fim++) if (*fim == L'\r' || *fim == L'\n') { *fim = 0; break; }
        if (tab2[1]) lstrcpynW(A.etapa, tab2 + 1, 200);
        InterlockedExchange(&A.teve_progresso, 1);
    }
}

/* ---------- janela ---------- */

static LRESULT CALLBACK proc(HWND j, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_TIMER: {
        DWORD agora = GetTickCount();
        if (A.fase == 0) { A.alfa += 30; if (A.alfa >= 255) { A.alfa = 255; A.fase = 1; } }
        else if (A.fase == 2) { A.alfa -= 26; if (A.alfa <= 0) { A.alfa = 0; DestroyWindow(j); return 0; } }
        if (agora - A.lido_em > 140) {
            A.lido_em = agora;
            ler_andamento();
            /* Antes do primeiro andamento, a barra anda devagar sozinha (o PowerShell está abrindo). */
            if (!A.teve_progresso) { int falso = (int)((agora - A.t0) / 350); A.alvo = falso > 18 ? 18 : falso; }
        }
        A.mostrado += ((double)A.alvo - A.mostrado) * 0.12;
        compor_e_mostrar();
        return 0;
    }
    case MSG_FECHAR:
        if (A.fase != 2) A.fase = 2;
        return 0;
    case MSG_SUMIR:
        DestroyWindow(j);
        return 0;
    case WM_CLOSE:
        A.fase = 2;
        return 0;
    case WM_SETCURSOR:
        SetCursor(LoadCursorW(NULL, (LPCWSTR)IDC_APPSTARTING));
        return TRUE;
    case WM_DESTROY:
        KillTimer(j, 1);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(j, msg, wp, lp);
}

static DWORD WINAPI linha_abertura(LPVOID nada) {
    WNDCLASSEXW wc; MSG m; HINSTANCE inst = GetModuleHandleW(NULL); POINT cur; HMONITOR mon; MONITORINFO mi; UINT dpi;
    GdiplusStartupInput gsi = { 1, NULL, FALSE, FALSE }; BITMAPINFO bi; HDC tela;
    (void)nada;

    if (GdiplusStartup(&A.gdip, &gsi, NULL) != Ok) goto falhou;
    A.arte = carregar_arte();
    if (!A.arte) goto falhou;
    A.fam = familia(L"Segoe UI");
    A.fam_semi = familia(L"Segoe UI Semibold");

    GetCursorPos(&cur);
    mon = MonitorFromPoint(cur, MONITOR_DEFAULTTOPRIMARY);
    mi.cbSize = sizeof(mi);
    GetMonitorInfoW(mon, &mi);
    dpi = dpi_do_monitor(mon);
    A.s = (float)dpi / 96.0f;
    A.larg = (int)(BASE_L * A.s + 0.5f);
    A.alt = (int)(BASE_A * A.s + 0.5f);
    {   /* telas pequenas: a abertura cabe com folga */
        int lt = mi.rcWork.right - mi.rcWork.left, at = mi.rcWork.bottom - mi.rcWork.top;
        if (A.larg > lt * 0.85) { float k = (float)(lt * 0.85) / (float)A.larg; A.larg = (int)(A.larg * k); A.alt = (int)(A.alt * k); A.s *= k; }
        if (A.alt > at * 0.85) { float k = (float)(at * 0.85) / (float)A.alt; A.larg = (int)(A.larg * k); A.alt = (int)(A.alt * k); A.s *= k; }
    }
    A.f = (float)A.larg / 800.0f;
    A.margem = (int)(28 * A.s + 0.5f);
    A.jl = A.larg + 2 * A.margem;
    A.ja = A.alt + 2 * A.margem;
    A.x = mi.rcWork.left + ((mi.rcWork.right - mi.rcWork.left) - A.larg) / 2 - A.margem;
    A.y = mi.rcWork.top + ((mi.rcWork.bottom - mi.rcWork.top) - A.alt) / 2 - A.margem;

    tela = GetDC(NULL);
    A.dc = CreateCompatibleDC(tela);
    ReleaseDC(NULL, tela);
    memset(&bi, 0, sizeof(bi));
    bi.bmiHeader.biSize = sizeof(bi.bmiHeader);
    bi.bmiHeader.biWidth = A.jl;
    bi.bmiHeader.biHeight = -A.ja;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    A.dib = CreateDIBSection(A.dc, &bi, DIB_RGB_COLORS, (void **)&A.bits, NULL, 0);
    if (!A.dib || !A.bits) goto falhou;
    A.dib_velho = (HBITMAP)SelectObject(A.dc, A.dib);
    if (GdipCreateBitmapFromScan0(A.jl, A.ja, A.jl * 4, PixelFormat32bppPARGB, A.bits, &A.quadro) != Ok) goto falhou;
    A.fundo = (BYTE *)malloc((size_t)A.jl * (size_t)A.ja * 4);
    if (!A.fundo || !preparar_fundo()) goto falhou;

    memset(&wc, 0, sizeof(wc));
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = proc;
    wc.hInstance = inst;
    wc.hIcon = LoadIconW(inst, MAKEINTRESOURCEW(1));
    wc.hIconSm = wc.hIcon;
    wc.hCursor = LoadCursorW(NULL, (LPCWSTR)IDC_APPSTARTING);
    wc.lpszClassName = L"LacadorAbertura";
    RegisterClassExW(&wc);
    A.jan = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOPMOST, L"LacadorAbertura", L"Laçador", WS_POPUP, A.x, A.y, A.jl, A.ja, NULL, NULL, inst, NULL);
    if (!A.jan) goto falhou;
    A.t0 = GetTickCount();
    A.alfa = 0; A.fase = 0;
    compor_e_mostrar();
    ShowWindow(A.jan, SW_SHOWNOACTIVATE);
    SetForegroundWindow(A.jan);
    SetTimer(A.jan, 1, 15, NULL);
    A.ativa = TRUE;
    SetEvent(A.criada);
    while (GetMessageW(&m, NULL, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageW(&m); }
    A.jan = NULL;
    A.ativa = FALSE;
    return 0;

falhou:
    A.ativa = FALSE;
    SetEvent(A.criada);
    return 1;
}

/* ---------- interface ---------- */

BOOL abertura_iniciar(const wchar_t *arq_progresso, const wchar_t *versao) {
    memset(&A, 0, sizeof(A));
    lstrcpynW(A.arq, arq_progresso, 1024);
    lstrcpynW(A.versao, versao, 40);
    lstrcpynW(A.etapa, L"Carregando o sistema...", 200);
    A.criada = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!A.criada) return FALSE;
    A.thread = CreateThread(NULL, 0, linha_abertura, NULL, 0, NULL);
    if (!A.thread) return FALSE;
    WaitForSingleObject(A.criada, 3000);
    return A.ativa;
}

LONG abertura_janela_aberta(void) { return A.janela_aberta; }
LONG abertura_teve_progresso(void) { return A.teve_progresso; }

void abertura_fechar(void) {
    if (!A.thread) return;
    if (A.jan) PostMessageW(A.jan, MSG_FECHAR, 0, 0);
    WaitForSingleObject(A.thread, 2500);
}

void abertura_fechar_ja(void) {
    if (!A.thread) return;
    if (A.jan) PostMessageW(A.jan, MSG_SUMIR, 0, 0);
    WaitForSingleObject(A.thread, 1500);
}
