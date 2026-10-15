// Tela inicial (Início), assistente, engrenagem, fixar o botão e Diagnóstico, na demonstração.
const { chromium } = require('playwright');
const [url, dir] = process.argv.slice(2);
const erros = [];
const ok = (c, m) => { console.log((c ? 'OK   ' : 'FALHA') + ' ' + m); if (!c) erros.push(m); };
(async () => {
  const b = await chromium.launch({ args: ['--no-sandbox'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 880 } });
  const p = await ctx.newPage();
  p.on('console', m => { if (m.type() === 'error') erros.push('[console] ' + m.text()); });
  p.on('pageerror', e => erros.push('[pageerror] ' + e.message));
  p.on('response', r => { if (r.status() >= 400) erros.push('[http ' + r.status() + '] ' + r.url()); });
  await p.goto(url);
  await p.waitForSelector('#app:not([hidden])', { timeout: 20000 });
  await p.waitForTimeout(1200);
  const titulo = await p.locator('#titulo').innerText();
  ok(/^(Bom dia|Boa tarde|Boa noite), 3S Silva$/.test(titulo), 'saudação com o nome: ' + titulo);
  ok(await p.locator('.nav-item[aria-current="page"] .nome').innerText() === 'Início', 'abre na página Início');
  ok(await p.locator('.tarefa').count() === 8, '8 opções em "O que você precisa hoje?"');
  ok((await p.locator('.ini-ficha').count()) === 4, '4 fichas de situação');
  await p.screenshot({ path: dir + '/20-inicio.png' });
  await p.screenshot({ path: dir + '/20b-inicio-inteira.png', fullPage: true });

  // avisos com X
  const antes = await p.locator('.ini-avisos .aviso').count();
  if (antes) {
    await p.locator('.ini-avisos .aviso-fechar').first().click();
    await p.waitForTimeout(300);
    ok(await p.locator('.ini-avisos .aviso').count() === antes - 1, 'aviso some ao clicar no X');
    await p.reload(); await p.waitForSelector('#app:not([hidden])'); await p.waitForTimeout(900);
    ok(await p.locator('.ini-avisos .aviso').count() === antes - 1, 'aviso fechado continua fechado depois de recarregar');
  } else ok(false, 'havia avisos para testar o X');

  // assistente do SIGADAER: na demonstração o assinador precisa de reparo e falta fixar o botão
  await p.locator('.tarefa', { hasText: 'SIGADAER' }).click();
  await p.waitForSelector('#folha .balao');
  await p.waitForTimeout(400);
  const balao = await p.locator('#folha .balao').innerText();
  ok(/Assinador do COMAER/.test(balao) && /fixar o botão/.test(balao), 'assistente do SIGADAER cita o reparo e o botão a fixar');
  ok(await p.locator('#folha button', { hasText: 'Reparar agora' }).count() === 1, 'assistente oferece Reparar agora');
  await p.screenshot({ path: dir + '/21-assistente-sigadaer.png' });
  await p.keyboard.press('Escape');

  // Programas: a extensão pede para fixar o botão; o Laçador pergunta antes de fechar o Firefox
  await p.locator('.nav-item', { hasText: 'Programas' }).click();
  await p.waitForTimeout(500);
  const ex = p.locator('.cartao', { has: p.locator('h2', { hasText: /^Extensão do assinador$/ }) }).first();
  ok(/escondido no menu/.test(await ex.innerText()), 'cartão da extensão diz que o botão está escondido');
  await ex.locator('button', { hasText: 'Fixar na barra' }).click();
  await p.waitForSelector('#folha h2:has-text("Fechar o Firefox?")');
  await p.waitForTimeout(400);
  await p.screenshot({ path: dir + '/22-fechar-firefox.png' });
  await p.locator('#folha button', { hasText: 'Fechar o Firefox e fixar' }).click();
  await p.waitForTimeout(4500);
  ok(/Fixada na barra[\s\S]*está na barra/.test(await ex.innerText()), 'depois de fixar, o cartão mostra o botão na barra');
  await p.locator('.nav-item', { hasText: 'Início' }).click();
  await p.waitForTimeout(500);
  const fichaFf = await p.locator('.ini-ficha', { hasText: 'Firefox' }).innerText();
  ok(/ativa e fixada/.test(fichaFf), 'ficha do Firefox mostra a extensão fixada');

  // SIAFI: falta instalar
  await p.locator('.tarefa', { hasText: 'SIAFI' }).click();
  await p.waitForSelector('#folha .balao');
  ok(/Java 8 Update 91/.test(await p.locator('#folha .balao').innerText()), 'assistente do SIAFI cita o Java 8');
  await p.screenshot({ path: dir + '/23-assistente-siafi.png' });
  await p.keyboard.press('Escape');

  // Programas: engrenagem do Firefox
  await p.locator('.nav-item', { hasText: 'Programas' }).click();
  await p.waitForTimeout(500);
  const ff = p.locator('.cartao', { has: p.locator('h2', { hasText: /^Firefox$/ }) }).first();
  ok(await ff.locator('button', { hasText: 'Abrir' }).count() === 1, 'Firefox tem botão Abrir');
  await ff.locator('button[aria-haspopup="menu"]').click();
  await p.waitForSelector('.menu-flutuante');
  await p.waitForTimeout(300);
  const itens = await p.locator('.menu-flutuante button').allInnerTexts();
  ok(itens.includes('Instalar o ESR (reserva)'), 'engrenagem do Firefox oferece o ESR de reserva: ' + itens.join(' | '));
  await p.screenshot({ path: dir + '/24-programas-engrenagem.png' });
  await p.keyboard.press('Escape');
  const as = p.locator('.cartao', { has: p.locator('h2', { hasText: /^Assinador do COMAER$/ }) }).first();
  await as.locator('button[aria-haspopup="menu"]').click();
  const itens2 = await p.locator('.menu-flutuante button').allInnerTexts();
  const reparoVisivel = (await as.locator('.cartao-pe button', { hasText: /^Reparar$/ }).count()) > 0 || itens2.some(x => /Reparar/.test(x));
  ok(reparoVisivel && itens2.includes('Desinstalar'), 'assinador: Reparar (botão ou engrenagem) e Desinstalar: ' + itens2.join(' | '));
  await p.locator('.menu-flutuante button', { hasText: 'Desinstalar' }).click();
  await p.waitForSelector('#folha .botao.perigo');
  await p.waitForTimeout(400);
  await p.screenshot({ path: dir + '/25-desinstalar.png' });
  await p.locator('#folha .botao.perigo').click();
  await p.waitForSelector('#folha h2:has-text("Desinstalado")', { timeout: 20000 });
  await p.locator('#folha button', { hasText: 'Fechar' }).click();
  await p.waitForTimeout(3500);
  const selo = await as.locator('.selo').first().innerText();
  ok(/Não instalado/.test(selo), 'assinador aparece como não instalado depois de desinstalar: ' + selo);

  // Diagnóstico em linguagem clara
  await p.locator('.nav-item', { hasText: 'Diagnóstico' }).click();
  await p.waitForTimeout(600);
  const frases = await p.locator('.diag-frase').allInnerTexts();
  ok(frases.length >= 5 && /^3S Silva, este é o computador/.test(frases[0]), 'Diagnóstico começa falando com a pessoa: ' + (frases[0] || ''));
  await p.screenshot({ path: dir + '/26-diagnostico.png' });
  const cred = await p.locator('.credito').innerText();
  ok(/Criado por 3S Leon, S2 Dalssasso/.test(cred), 'crédito novo: ' + cred.replace(/\n/g, ' '));
  await b.close();
  console.log('ERROS ' + erros.length); erros.forEach(e => console.log('  ' + e));
  process.exit(erros.length ? 1 : 0);
})();
