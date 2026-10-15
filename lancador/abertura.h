/* LAÇADOR - tela de abertura (janela própria, antes da janela do programa). */
#ifndef LACADOR_ABERTURA_H
#define LACADOR_ABERTURA_H
#include <windows.h>

/* Mostra a abertura numa linha de execução própria. arq_progresso: arquivo que o PowerShell
   escreve com "percentual<TAB>fase<TAB>etapa". Devolve FALSE se não conseguiu mostrar. */
BOOL abertura_iniciar(const wchar_t *arq_progresso, const wchar_t *versao);
/* 1 depois que o PowerShell avisou que abriu a janela do programa. */
LONG abertura_janela_aberta(void);
/* 1 depois que o PowerShell escreveu o primeiro andamento. */
LONG abertura_teve_progresso(void);
/* Some com a abertura (esmaecendo) e espera ela terminar. Pode ser chamada mais de uma vez. */
void abertura_fechar(void);
/* Some na hora, sem esmaecer (antes de mostrar uma mensagem de erro). */
void abertura_fechar_ja(void);

#endif
