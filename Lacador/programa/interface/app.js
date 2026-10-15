/* Laçador - tela do usuário. Conversa só com o serviço local (127.0.0.1) aberto pelo Lacador.ps1. */
(function () {
  'use strict';

  var CHAVE = new URLSearchParams(location.search).get('k') || '';
  // A chave sai da barra de endereço e fica só nesta janela (assim um F5 não derruba a tela).
  try {
    if (CHAVE) sessionStorage.setItem('lacador-chave', CHAVE); else CHAVE = sessionStorage.getItem('lacador-chave') || '';
    history.replaceState(null, '', location.pathname);
  } catch (e) { /* sem problema */ }

  var S = {
    estado: null, rodada: -1, fase: 'verificando', acao: null, pagina: 'inicio',
    tutoriais: [], tutorialAtual: null, historico: null, busca: '',
    appVisivel: false, abertoEm: Date.now(), certTecnicos: false, falhas: 0,
    folha: null, acaoFechada: null, ultimaVerificacao: Date.now(), desconectado: false,
    acesso: null, acessoIgnorar: false, respostaRuim: ''
  };

  // O Lacador.exe já mostrou a tela de abertura dele (a página entra direto no aplicativo).
  var NATIVA = document.documentElement.classList.contains('abertura-nativa');

  /* ---------- utilidades ---------- */
  function $(id) { return document.getElementById(id); }
  function h(tag, attrs) {
    var el = document.createElement(tag), i, k, f;
    attrs = attrs || {};
    for (k in attrs) {
      if (!Object.prototype.hasOwnProperty.call(attrs, k) || attrs[k] === null || attrs[k] === undefined || attrs[k] === false) continue;
      if (k === 'class') el.className = attrs[k];
      else if (k === 'text') el.textContent = attrs[k];
      else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), attrs[k]);
      else if (k === 'dados') { for (f in attrs[k]) el.dataset[f] = attrs[k][f]; }
      else el.setAttribute(k, attrs[k] === true ? '' : attrs[k]);
    }
    for (i = 2; i < arguments.length; i++) {
      f = arguments[i];
      if (f === null || f === undefined || f === false) continue;
      if (Array.isArray(f)) f.forEach(function (x) { if (x) el.append(x); });
      else el.append(f);
    }
    return el;
  }
  function semAcento(t) { return String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase(); }

  var TRACO = 'fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"';
  var ICONES = {
    token: '<rect x="7" y="8" width="10" height="13" rx="2.5"/><path d="M9 8V3h6v5"/><circle cx="12" cy="15" r="1.6"/>',
    caneta: '<path d="M4 20l4-1 10-10-3-3L5 16z"/><path d="M13 8l3 3"/><path d="M14 20h6"/>',
    documento: '<path d="M6 3h9l4 4v14H6z"/><path d="M15 3v4h4"/><path d="M9 12h6M9 16h6"/>',
    terminal: '<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="M7 10l3 2.5L7 15"/><path d="M12.5 15H16"/>',
    carrinho: '<path d="M3 5h2.5l2 10h10l2-7H7"/><circle cx="9.5" cy="19" r="1.4"/><circle cx="16.5" cy="19" r="1.4"/>',
    selo: '<path d="M6 3h9l4 4v14H6z"/><path d="M15 3v4h4"/><circle cx="12" cy="13" r="2.4"/><path d="M10.6 15.1L10 19l2-1 2 1-.6-3.9"/>',
    java: '<path d="M5 10h11v5a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4z"/><path d="M16 11h1.5a2 2 0 0 1 0 4H16"/><path d="M8 3c-1 1.5 1 2.5 0 4M11.5 3c-1 1.5 1 2.5 0 4"/>',
    globo: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.3 3.5 5.2 3.5 8.5s-1 6.2-3.5 8.5c-2.5-2.3-3.5-5.2-3.5-8.5s1-6.2 3.5-8.5"/>',
    extensao: '<path d="M9 4h3a2 2 0 1 1 4 0h3v5a2 2 0 1 0 0 4v6h-5a2 2 0 1 0-4 0H5v-6a2 2 0 1 1 0-4V4z"/>',
    engrenagem: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
    grade: '<rect x="4" y="4" width="7" height="7" rx="2"/><rect x="13" y="4" width="7" height="7" rx="2"/><rect x="4" y="13" width="7" height="7" rx="2"/><rect x="13" y="13" width="7" height="7" rx="2"/>',
    caixa: '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z"/><path d="M4 7.5l8 4.5 8-4.5M12 12v9"/>',
    livro: '<path d="M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z"/><path d="M5 17a3 3 0 0 1 3-3h11"/>',
    escudo: '<path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z"/><path d="M9 12l2 2 4-4"/>',
    ajuda: '<circle cx="12" cy="12" r="8.5"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 .9-1 1.7"/><path d="M12 16.8h.01"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    checkCirculo: '<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.8 2.8L16 10"/>',
    alerta: '<path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17h.01"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
    xis: '<circle cx="12" cy="12" r="9"/><path d="M9 9l6 6M15 9l-6 6"/>',
    ponto: '<circle cx="12" cy="12" r="3.2"/>',
    cadeado: '<rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8.5 10.5V7.5a3.5 3.5 0 0 1 7 0"/><path d="M12 14.5v2.5"/>',
    usuario: '<circle cx="12" cy="8.5" r="3.6"/><path d="M5 20c.8-3.6 3.5-5.5 7-5.5s6.2 1.9 7 5.5"/>',
    usb: '<path d="M12 3v14"/><path d="M9 6l3-3 3 3"/><circle cx="12" cy="19.5" r="2"/><path d="M7 9v3l5 3M17 8v4l-5 3"/>',
    casa: '<path d="M4 11.5L12 4l8 7.5"/><path d="M6.5 9.5V20h11V9.5"/><path d="M10 20v-5.5h4V20"/>',
    fechar: '<path d="M7 7l10 10M17 7L7 17"/>',
    mais: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
    firefox: '<circle cx="12" cy="12" r="8.5"/><path d="M8 7.5c1.2-.8 2.6-1.1 4-1 2.9.3 5 2.8 4.7 5.7-.3 2.6-2.6 4.5-5.2 4.3-2.1-.2-3.7-1.9-3.8-4 .7 1 2 1.6 3.3 1.3 1.6-.3 2.6-1.9 2.2-3.5"/>'
  };
  function icone(nome, tam, peso) {
    var s = h('span', { class: 'ic-svg', 'aria-hidden': 'true' });
    s.style.display = 'inline-flex';
    s.innerHTML = '<svg width="' + (tam || 20) + '" height="' + (tam || 20) + '" viewBox="0 0 24 24" ' + TRACO.replace('1.7', String(peso || 1.7)) + '>' + (ICONES[nome] || ICONES.ponto) + '</svg>';
    return s;
  }

  function api(caminho, corpo) {
    var op = { method: corpo === undefined ? 'GET' : 'POST', headers: { 'X-Lacador-Chave': CHAVE }, cache: 'no-store' };
    if (corpo !== undefined) { op.headers['Content-Type'] = 'application/json'; op.body = JSON.stringify(corpo); }
    return fetch(caminho, op).then(function (r) { return r.text(); }).then(function (t) {
      try { return JSON.parse(t); }
      catch (e) { S.respostaRuim = String(t).slice(0, 160); throw e; }   // o serviço respondeu, mas não em JSON
    });
  }

  var brindeTimer = null;
  function brinde(texto, erro) {
    var b = $('brinde');
    b.textContent = texto;
    b.className = 'brinde' + (erro ? ' erro' : '');
    b.hidden = false;
    clearTimeout(brindeTimer);
    brindeTimer = setTimeout(function () { b.hidden = true; }, erro ? 9000 : 5500);
  }

  function operacao(corpo) {
    return api('/api/usuario', corpo).then(function (r) { brinde(r.mensagem || (r.ok ? 'Feito.' : 'Não foi possível.'), !r.ok); return r; })
      .catch(function () { brinde('O Laçador não respondeu.', true); });
  }

  // Pede uma nova verificação daqui a alguns segundos (depois de abrir o Firefox, fixar o botão...).
  function verificarLogo(seg) {
    setTimeout(function () { S.ultimaVerificacao = Date.now(); api('/api/verificar', {}).catch(function () {}); }, (seg || 1) * 1000);
  }

  /* ---------- quem está usando ---------- */
  function nome(e) { return (e && e.nomeUsuario) || 'você'; }
  function saudacao() { var hr = new Date().getHours(); return hr < 12 ? 'Bom dia' : (hr < 18 ? 'Boa tarde' : 'Boa noite'); }
  function juntar(lista) {
    lista = lista.filter(function (x) { return x; });
    if (lista.length <= 1) return lista.join('');
    return lista.slice(0, -1).join(', ') + ' e ' + lista[lista.length - 1];
  }

  /* ---------- avisos que a pessoa fechou (no X) ---------- */
  var FECHADOS = (function () { try { return JSON.parse(localStorage.getItem('lacador-avisos-fechados') || '[]'); } catch (e) { return []; } })();
  function chaveAviso(a) { return a.titulo + '|' + a.texto; }
  function avisoFechado(a) { return FECHADOS.indexOf(chaveAviso(a)) >= 0; }
  function fecharAviso(a) {
    FECHADOS.push(chaveAviso(a));
    if (FECHADOS.length > 80) FECHADOS = FECHADOS.slice(-80);
    try { localStorage.setItem('lacador-avisos-fechados', JSON.stringify(FECHADOS)); } catch (e) { /* sem problema */ }
    desenhar();
  }

  /* ---------- menu da engrenagem (mais opções) ---------- */
  var menuAberto = null;
  function fecharMenu() { if (menuAberto) { menuAberto.remove(); menuAberto = null; } }
  function engrenagem(opcoes, rotulo) {
    var b = h('button', { class: 'botao icone', type: 'button', title: rotulo || 'Mais opções', 'aria-label': rotulo || 'Mais opções', 'aria-haspopup': 'menu' }, icone('mais', 18, 1.8));
    b.addEventListener('click', function (ev) {
      ev.stopPropagation();
      if (menuAberto && menuAberto.dono === b) { fecharMenu(); return; }
      fecharMenu();
      var m = h('div', { class: 'menu-flutuante', role: 'menu' });
      opcoes.forEach(function (o) {
        if (o === '-') { m.append(h('hr')); return; }
        m.append(h('button', { type: 'button', role: 'menuitem', class: o.perigo ? 'perigo' : null, onclick: function () { fecharMenu(); o.acao(); } }, o.icone ? icone(o.icone, 16, 1.9) : null, h('span', { text: o.rotulo })));
      });
      document.body.append(m);
      var r = b.getBoundingClientRect(), mw = m.offsetWidth, mh = m.offsetHeight;
      var x = Math.min(window.innerWidth - mw - 10, Math.max(10, r.right - mw));
      var y = (r.bottom + 6 + mh > window.innerHeight - 10) ? r.top - mh - 6 : r.bottom + 6;
      m.style.left = x + 'px'; m.style.top = y + 'px';
      m.dono = b;
      menuAberto = m;
      var primeiro = m.querySelector('button'); if (primeiro) primeiro.focus();
    });
    return b;
  }
  document.addEventListener('click', function (ev) { if (menuAberto && !menuAberto.contains(ev.target)) fecharMenu(); });
  document.addEventListener('keydown', function (ev) { if (ev.key === 'Escape') fecharMenu(); });

  /* ---------- abrir programas e passos do Firefox ---------- */
  function abrirAlvo(alvo, edicao) {
    if (alvo === 'firefox') return abrirFirefox(edicao);
    return operacao({ operacao: 'abrir-programa', alvo: alvo });
  }
  function abrirFirefox(edicao, sistema, reabrir) {
    return operacao({ operacao: 'abrir-firefox', edicao: edicao || '', sistema: sistema || '', reabrir: !!reabrir }).then(function (r) {
      if (r && r.ok) { verificarLogo(12); verificarLogo(35); }   // a extensão aparece no perfil depois que o Firefox abre
      return r;
    });
  }
  function fixarExtensao(fechar) {
    return api('/api/usuario', { operacao: 'fixar-extensao', fechar: !!fechar }).then(function (r) {
      if (r.precisaFechar) {
        var fr = document.createDocumentFragment();
        fr.append(h('h2', { id: 'folha-titulo', text: 'Fechar o Firefox?' }),
          h('p', { class: 'sub', text: 'Para fixar o botão do assinador na barra, o Laçador precisa fechar o Firefox. As abas voltam quando você abrir de novo.' }),
          h('div', { class: 'folha-pe' }, h('button', { class: 'botao', type: 'button', text: 'Agora não', onclick: fecharFolha }),
            h('button', { class: 'botao primario', type: 'button', text: 'Fechar o Firefox e fixar', onclick: function () { fecharFolha(); brinde('Fechando o Firefox...'); fixarExtensao(true); } })));
        abrirFolha(fr, 'confirmar');
        return r;
      }
      brinde(r.mensagem || (r.ok ? 'Feito.' : 'Não foi possível.'), !r.ok);
      if (r.ok) verificarLogo(1);
      return r;
    }).catch(function () { brinde('O Laçador não respondeu.', true); });
  }
  // A extensão só entra quando o Firefox abre depois da política: se ele já está aberto, fecha e abre de novo.
  function abrirFirefoxPasso() {
    if (S.estado && S.estado.firefoxAberto) {
      var fr = document.createDocumentFragment();
      fr.append(h('h2', { id: 'folha-titulo', text: 'Fechar e abrir o Firefox?' }),
        h('p', { class: 'sub', text: 'O Firefox está aberto. Para a extensão do assinador entrar, ele precisa ser fechado e aberto de novo. As abas voltam sozinhas.' }),
        h('div', { class: 'folha-pe' }, h('button', { class: 'botao', type: 'button', text: 'Agora não', onclick: fecharFolha }),
          h('button', { class: 'botao primario', type: 'button', text: 'Fechar e abrir o Firefox', onclick: function () { fecharFolha(); brinde('Fechando o Firefox...'); abrirFirefox('', '', true); } })));
      abrirFolha(fr, 'confirmar');
      return;
    }
    abrirFirefox('', '');
  }
  function fazerPasso(passo) {
    if (!passo) return;
    if (passo.acao === 'fixar') fixarExtensao(false);
    else abrirFirefoxPasso();
  }

  /* ---------- páginas ---------- */
  var PAGINAS = [
    { id: 'inicio', nome: 'Início', icone: 'casa' },
    { id: 'sistemas', nome: 'Sistemas', icone: 'grade' },
    { id: 'tokens', nome: 'Tokens', icone: 'token' },
    { id: 'programas', nome: 'Programas', icone: 'caixa' },
    { id: 'certificados', nome: 'Certificados', icone: 'selo' },
    { id: 'tutoriais', nome: 'Tutoriais', icone: 'livro' },
    { id: 'acesso', nome: 'Acesso', icone: 'cadeado' },
    { id: 'diagnostico', nome: 'Diagnóstico', icone: 'escudo' }
  ];

  function itensProgramas(e) { return Object.keys(e.itens).map(function (k) { return e.itens[k]; }).filter(function (i) { return i.categoria !== 'driver'; }); }
  function pessoais(e) { return e.certificados.filter(function (c) { return c.pessoal; }); }

  function contagem(id, e) {
    if (!e) return null;
    if (id === 'inicio') {
      var abertos = e.avisos.filter(function (a) { return !avisoFechado(a); }).length;
      return abertos ? { n: abertos, alerta: true } : null;
    }
    if (id === 'sistemas') return { n: e.sistemas.length };
    if (id === 'tokens') return { n: e.tokens.length };
    if (id === 'programas') {
      var pend = itensProgramas(e).filter(function (i) { return i.estado === 'atencao' || (i.estado === 'ausente' && !i.opcional && !i.legado); }).length;
      return pend ? { n: pend, alerta: true } : null;
    }
    if (id === 'certificados') {
      var ruins = pessoais(e).filter(function (c) { return c.situacao === 'vencido' || c.situacao === 'vencendo'; }).length;
      return ruins ? { n: ruins, alerta: true } : { n: pessoais(e).length };
    }
    if (id === 'tutoriais') return S.tutoriais.length ? { n: S.tutoriais.length } : null;
    return null;
  }

  function subtitulo(id, e) {
    if (!e) return '';
    if (id === 'inicio') return 'Eu confiro este computador e te ajudo com tokens, certificados e sistemas.';
    if (id === 'sistemas') {
      var p = e.sistemas.filter(function (s) { return s.estado === 'pronto'; }).length;
      return p + ' de ' + e.sistemas.length + ' prontos para usar';
    }
    if (id === 'tokens') {
      var c = e.tokens.filter(function (t) { return t.conectado; }).length;
      return e.tokens.length + ' modelos no catálogo · ' + (c === 1 ? '1 conectado agora' : c + ' conectados agora');
    }
    if (id === 'programas') {
      var its = itensProgramas(e), ok = its.filter(function (i) { return i.estado === 'ok'; }).length;
      return ok + ' de ' + its.length + ' em ordem';
    }
    if (id === 'certificados') {
      var n = pessoais(e).length;
      return n === 0 ? 'Nenhum certificado pessoal neste Windows' : (n === 1 ? '1 certificado pessoal neste Windows' : n + ' certificados pessoais neste Windows');
    }
    if (id === 'tutoriais') return 'Passo a passo de acesso a cada sistema';
    if (id === 'acesso') return e.acesso.liberado ? 'Este computador está liberado para instalar sem administrador' : 'Quem pode instalar e reparar neste computador';
    if (id === 'diagnostico') return e.computador + ' · ' + e.windows.nome + ' ' + (e.windows.versao || '');
    return '';
  }

  function desenharNav() {
    var nav = $('nav');
    nav.textContent = '';
    PAGINAS.forEach(function (p) {
      var c = contagem(p.id, S.estado);
      var b = h('button', { class: 'nav-item', type: 'button', 'aria-current': S.pagina === p.id ? 'page' : null, dados: { pagina: p.id }, onclick: function () { irPara(p.id); } },
        icone(p.icone, 18, 1.8), h('span', { class: 'nome', text: p.nome }),
        c ? h('span', { class: 'conta' + (c.alerta ? ' alerta' : ''), text: String(c.n) }) : null);
      nav.append(b);
    });
  }

  function irPara(pagina, alvo) {
    S.pagina = pagina;
    if (pagina === 'tutoriais' && alvo) S.tutorialAtual = alvo;
    if (pagina === 'diagnostico') { S.historico = null; api('/api/historico').then(function (r) { S.historico = r.itens || []; if (S.pagina === 'diagnostico') desenhar(); }).catch(function () { S.historico = []; }); }
    $('busca').value = ''; S.busca = '';
    desenhar();
    $('conteudo').scrollTop = 0;
  }

  /* ---------- peças de tela ---------- */
  function luz() { return h('div', { class: 'luz', 'aria-hidden': 'true' }); }
  function selo(classe, texto, pulsa) { return h('span', { class: 'selo ' + classe + (pulsa ? ' pulsa' : '') }, h('span', { class: 'ponto' }), texto); }
  function marca(estado) {
    if (estado === 'ok') { var a = icone('check', 15, 2.4); a.className = 'marca-ok'; a.setAttribute('aria-label', 'em ordem'); a.removeAttribute('aria-hidden'); return a; }
    if (estado === 'aguardando') { var n = icone('ponto', 15, 2); n.className = 'marca-neutra'; return n; }
    var m = icone('alerta', 15, 2.1); m.className = 'marca-atencao'; m.setAttribute('aria-label', 'pendente'); m.removeAttribute('aria-hidden'); return m;
  }
  function linha(rotulo, valor, classe, extra) {
    return h('div', { class: 'linha' }, h('span', { class: 'rotulo', text: rotulo }), h('span', { class: 'valor' + (classe ? ' ' + classe : '') }, valor, extra || null));
  }
  function linhaDupla(rotulo, detalhe, classe, marcaEl, etiqueta) {
    var r = h('span', { class: 'rotulo', text: rotulo });
    if (etiqueta) r.append(h('span', { class: 'etiqueta', text: etiqueta }));
    return h('div', { class: 'linha dupla' }, h('div', { class: 'dupla-texto' }, r, detalhe ? h('span', { class: 'detalhe' + (classe ? ' ' + classe : ''), text: detalhe }) : null), marcaEl || null);
  }
  function nota(texto, alerta) { return h('div', { class: 'nota' + (alerta ? ' alerta' : '') }, (function () { var i = icone(alerta ? 'alerta' : 'info', 15, 2); i.className = 'ic'; return i; })(), h('span', { text: texto })); }
  function cartao(busca, sobe) {
    var c = h('section', { class: 'cartao' + (sobe === false ? '' : ' sobe'), dados: { luz: 'cartao', busca: semAcento(busca) } }, luz());
    return c;
  }
  function cabeca(ic, titulo, sub, seloEl, etiquetas) {
    var h2 = h('h2', { text: titulo });
    (etiquetas || []).forEach(function (t) { h2.append(h('span', { class: 'etiqueta', text: t })); });
    return h('div', { class: 'cartao-topo' }, h('div', { class: 'cartao-icone' }, icone(ic, 24, 1.6)),
      h('div', { class: 'cartao-titulo' }, h('div', { class: 'cartao-titulo-linha' }, h2, seloEl), sub ? h('p', { text: sub }) : null));
  }

  function avisosTopo(e, pagina, sempre) {
    var lista = e.avisos.filter(function (a) { return (!pagina || a.pagina === pagina) && !avisoFechado(a); });
    if (!lista.length && !sempre) return null;
    var caixa = h('div', { class: 'avisos' });
    lista.forEach(function (a) {
      caixa.append(h('div', { class: 'aviso' + (a.nivel === 'info' ? ' info' : ''), dados: { luz: 'cartao' } }, luz(),
        h('div', { class: 'aviso-icone' }, icone(a.nivel === 'info' ? 'info' : 'alerta', 18, 2)),
        h('div', { class: 'aviso-texto' }, h('strong', { text: a.titulo }), h('span', { text: a.texto })),
        (a.pagina && a.pagina !== S.pagina) ? h('button', { class: 'botao pequeno', type: 'button', text: 'Ver', onclick: function () { irPara(a.pagina); } }) : null,
        h('button', { class: 'aviso-fechar', type: 'button', title: 'Fechar este aviso', 'aria-label': 'Fechar este aviso', onclick: function () { fecharAviso(a); } }, icone('fechar', 16, 2))));
    });
    return caixa;
  }

  /* ---------- Início: situação, avisos e "O que você precisa hoje?" ---------- */
  function principais(e) { return e.sistemas.filter(function (s) { return !s.opcional; }); }
  function situacao(e) {
    var ps = principais(e);
    var porEstado = function (est) { return ps.filter(function (s) { return s.estado === est; }); };
    var prontos = porEstado('pronto'), aguardando = porEstado('aguardando'), falta = porEstado('falta'), atencao = porEstado('atencao'), bloq = porEstado('bloqueado');
    var conectado = e.tokens.filter(function (t) { return t.estado === 'pronto'; })[0];
    var problemas = falta.concat(atencao, bloq);
    if (!problemas.length) {
      if (prontos.length === ps.length) return { classe: '', icone: 'checkCirculo', titulo: 'Tudo pronto para trabalhar', texto: (conectado ? 'O ' + conectado.nome + ' está conectado e ' : '') + 'todos os sistemas estão prontos para usar.' };
      return { classe: '', icone: 'checkCirculo', titulo: 'Tudo instalado', texto: 'Os programas estão em ordem. Conecte o token na porta USB quando for assinar ou entrar nos sistemas.' };
    }
    var nomes = juntar(problemas.map(function (s) { return s.nome; }));
    var titulo = problemas.length === 1 ? 'Falta um ajuste no ' + problemas[0].nome : 'Faltam ajustes em ' + problemas.length + ' sistemas';
    var texto = (problemas.length === 1 ? nomes + ' ainda não está pronto. ' : nomes + ' ainda não estão prontos. ') + 'Escolha abaixo o que você precisa e eu resolvo para você.';
    if (prontos.length || aguardando.length) texto = juntar(prontos.concat(aguardando).map(function (s) { return s.nome; })) + (prontos.length + aguardando.length === 1 ? ' já está' : ' já estão') + ' em ordem. ' + texto;
    return { classe: 'alerta', icone: 'alerta', titulo: titulo, texto: texto };
  }
  function ficha(classe, ic, rotulo, valor, detalhe) {
    return h('div', { class: 'ini-ficha ' + (classe || '') }, h('span', { class: 'ic' }, icone(ic, 18, 1.8)),
      h('span', { class: 'tx' }, h('small', { text: rotulo }), h('strong', { text: valor, title: valor }), detalhe ? h('span', { text: detalhe, title: detalhe }) : null));
  }
  function fichaToken(e) {
    var pronto = e.tokens.filter(function (t) { return t.estado === 'pronto'; })[0];
    if (pronto) return ficha('ok', 'token', 'Token', pronto.nome, 'Conectado e reconhecido');
    var semDriver = e.tokens.filter(function (t) { return t.conectado; })[0];
    if (semDriver) return ficha('alerta', 'token', 'Token', semDriver.nome, semDriver.resumo);
    var comDriver = e.tokens.filter(function (t) { return t.faltando.length === 0 && t.reparar.length === 0; });
    if (comDriver.length) return ficha('', 'token', 'Token', 'Nenhum conectado agora', 'Driver instalado: ' + juntar(comDriver.map(function (t) { return t.nome.replace(/ \(.*\)$/, ''); })));
    return ficha('alerta', 'token', 'Token', 'Nenhum driver instalado', 'Escolha "Instalar ou trocar meu token"');
  }
  function fichaCert(e) {
    var ps = pessoais(e);
    if (!ps.length) return ficha('', 'selo', 'Certificado', 'Nenhum neste Windows', 'Aparece quando o token é conectado');
    var pior = ps.slice().sort(function (a, b) { return a.dias - b.dias; })[0];
    var ok = ps.filter(function (c) { return c.situacao === 'valido'; })[0];
    if (pior.situacao === 'vencido' && !ok) return ficha('erro', 'selo', 'Certificado', 'Vencido em ' + pior.validade, pior.titular);
    if (pior.situacao === 'vencendo') return ficha('alerta', 'selo', 'Certificado', 'Vence em ' + pior.dias + (pior.dias === 1 ? ' dia' : ' dias'), pior.titular);
    var bom = ok || pior;
    return ficha('ok', 'selo', 'Certificado', 'Válido até ' + bom.validade, bom.titular);
  }
  function fichaSistemas(e) {
    var ps = principais(e), ok = ps.filter(function (s) { return s.estado === 'pronto' || s.estado === 'aguardando'; }).length;
    return ficha(ok === ps.length ? 'ok' : 'alerta', 'grade', 'Sistemas', ok + ' de ' + ps.length + ' em ordem', ok === ps.length ? 'Nada pendente' : 'Veja abaixo o que falta');
  }
  function fichaFirefox(e) {
    var ff = e.itens['firefox-esr'], ext = e.itens['extensao-firefox'];
    if (!ff || ff.estado === 'ausente') return ficha('alerta', 'firefox', 'Firefox', 'Não instalado', 'O SIGADAER usa o Developer ou o ESR');
    var det = ext && ext.estado === 'ok' ? 'Extensão ativa e fixada na barra' : (ext && ext.estado === 'ausente' ? 'Falta a extensão do assinador' : (ext && ext.acao === 'fixar' ? 'Falta fixar o botão do assinador' : (ext ? ext.detalhe : '')));
    var eds = ff.temDeveloper && ff.temEsr ? 'Developer e ESR' : (ff.temDeveloper ? 'Developer Edition' : (ff.temEsr ? 'ESR' : ff.detalhe));
    return ficha(ext && ext.estado === 'ok' ? 'ok' : 'alerta', 'firefox', 'Firefox', eds, det);
  }

  var TAREFAS = [
    { id: 'sigadaer', icone: 'caneta', titulo: 'Assinar no SIGADAER', tipo: 'sistema' },
    { id: 'assinar-pdf', icone: 'documento', titulo: 'Assinar um arquivo PDF', tipo: 'sistema' },
    { id: 'siafi', icone: 'terminal', titulo: 'Entrar no SIAFI', tipo: 'sistema' },
    { id: 'compras', icone: 'carrinho', titulo: 'Entrar no Compras.gov.br', tipo: 'sistema' },
    { id: 'token', icone: 'token', titulo: 'Instalar ou trocar meu token', tipo: 'token' },
    { id: 'certificado', icone: 'selo', titulo: 'Ver meu certificado', tipo: 'certificado' },
    { id: 'problema', icone: 'ajuda', titulo: 'Algo não está funcionando', tipo: 'problema' },
    { id: 'tutoriais', icone: 'livro', titulo: 'Ver um passo a passo', tipo: 'tutoriais' }
  ];
  function pendencias(e) {
    var lista = [];
    principais(e).forEach(function (s) { if (s.estado === 'falta' || s.estado === 'atencao' || s.estado === 'bloqueado') lista.push(s.nome + ': ' + s.resumo.charAt(0).toLowerCase() + s.resumo.slice(1)); });
    e.tokens.forEach(function (t) { if (t.conectado && t.estado !== 'pronto') lista.push(t.nome + ': ' + t.resumo.charAt(0).toLowerCase() + t.resumo.slice(1)); });
    pessoais(e).forEach(function (c) { if (c.situacao === 'vencido') lista.push('Certificado de ' + c.titular + ' vencido em ' + c.validade); });
    return lista;
  }
  function estadoTarefa(t, e) {
    if (t.tipo === 'sistema') {
      var s = e.sistemas.filter(function (x) { return x.id === t.id; })[0];
      if (!s) return { classe: '', texto: '' };
      if (s.estado === 'pronto') return { classe: 'ok', texto: 'Pronto para usar' };
      if (s.estado === 'aguardando') return { classe: 'ok', texto: 'Pronto: conecte o token' };
      if (s.estado === 'falta') return { classe: 'alerta', texto: 'Falta instalar' };
      if (s.estado === 'atencao') return { classe: 'alerta', texto: s.reparar.length ? 'Precisa de reparo' : 'Falta um passo' };
      return { classe: 'alerta', texto: 'Bloqueado' };
    }
    if (t.tipo === 'token') {
      var c = e.tokens.filter(function (x) { return x.estado === 'pronto'; })[0];
      if (c) return { classe: 'ok', texto: c.nome.replace(/ \(.*\)$/, '') + ' conectado' };
      return { classe: '', texto: e.tokens.some(function (x) { return x.conectado; }) ? 'Conectado, falta o driver' : 'Nenhum conectado' };
    }
    if (t.tipo === 'certificado') {
      var ps = pessoais(e);
      if (!ps.length) return { classe: '', texto: 'Nenhum encontrado' };
      if (ps.some(function (x) { return x.situacao === 'vencido' || x.situacao === 'vencendo'; })) return { classe: 'alerta', texto: 'Precisa de atenção' };
      return { classe: 'ok', texto: 'Válido' };
    }
    if (t.tipo === 'problema') {
      var n = pendencias(e).length;
      return n ? { classe: 'alerta', texto: n === 1 ? '1 pendência encontrada' : n + ' pendências encontradas' } : { classe: 'ok', texto: 'Nada errado encontrado' };
    }
    return { classe: '', texto: S.tutoriais.length ? S.tutoriais.length + ' guias' : 'Guias de acesso' };
  }

  function paginaInicio(e) {
    var f = document.createDocumentFragment();
    var painel = h('div', { class: 'ini-painel' });

    var sit = situacao(e);
    var c1 = cartao('situacao computador', false);
    var ic = h('div', { class: 'ini-status-icone ' + sit.classe }, icone(sit.icone, 28, 2));
    c1.append(h('div', { class: 'ini-status' }, ic, h('div', null, h('h2', { text: sit.titulo }), h('p', { text: sit.texto }))));
    c1.append(h('div', { class: 'ini-fichas' }, fichaToken(e), fichaCert(e), fichaSistemas(e), fichaFirefox(e)));
    painel.append(c1);

    var c2 = cartao('avisos notificacoes', false);
    c2.classList.add('ini-avisos');
    c2.append(h('h2', { text: 'Avisos' }));
    var av = avisosTopo(e, null, false);
    if (av) {
      var todos = av.children.length;
      if (todos > 3 && !S.avisosTodos) {
        Array.prototype.slice.call(av.children, 3).forEach(function (x) { x.remove(); });
        av.append(h('button', { class: 'botao fantasma pequeno', type: 'button', text: 'Ver mais ' + (todos - 3) + (todos - 3 === 1 ? ' aviso' : ' avisos'), onclick: function () { S.avisosTodos = true; desenhar(); } }));
      }
      c2.append(av);
    }
    else c2.append(h('div', { class: 'ini-vazio' }, icone('checkCirculo', 18, 2), h('span', { text: 'Nenhum aviso agora. Tudo tranquilo por aqui.' })));
    painel.append(c2);
    f.append(painel);

    f.append(h('div', { class: 'ini-pergunta' }, h('h3', { text: 'O que você precisa hoje?' }), h('p', { text: 'Escolha uma opção. Eu confiro o computador e te mostro o caminho.' })));
    var g = h('div', { class: 'tarefas' });
    TAREFAS.forEach(function (t) {
      var est = estadoTarefa(t, e);
      g.append(h('button', { class: 'tarefa', type: 'button', dados: { luz: 'cartao', busca: semAcento(t.titulo) }, onclick: function () { ajudar(t, e); } }, luz(),
        h('span', { class: 'ic' }, icone(t.icone, 22, 1.7)), h('strong', { text: t.titulo }), h('span', { class: 'estado ' + est.classe, text: est.texto })));
    });
    f.append(g);
    return f;
  }

  // Abre a "conversa" do assistente: uma mensagem e os botões do que dá para fazer.
  function assistente(titulo, paragrafos, botoes, lista) {
    var fr = document.createDocumentFragment();
    fr.append(h('h2', { id: 'folha-titulo', text: titulo }));
    var balao = h('div', { class: 'balao' });
    paragrafos.forEach(function (p) { if (p) balao.append(h('p', { text: p })); });
    if (lista && lista.length) { var ul = h('ul'); lista.forEach(function (x) { ul.append(h('li', { text: x })); }); balao.append(ul); }
    fr.append(h('div', { class: 'assistente' }, h('img', { src: 'img/icone.png', alt: '' }), balao));
    var pe = h('div', { class: 'folha-pe' });
    pe.append(h('button', { class: 'botao', type: 'button', text: 'Fechar', onclick: fecharFolha }));
    (botoes || []).forEach(function (b) { if (b) pe.append(b); });
    fr.append(pe);
    abrirFolha(fr, 'assistente');
  }
  function botaoFolha(texto, classe, acao) { return h('button', { class: 'botao ' + (classe || ''), type: 'button', text: texto, onclick: acao }); }
  function viaTexto(e) {
    if (e.demonstracao) return 'É uma demonstração: nada será instalado de verdade.';
    if (e.acesso.liberado) return 'Não precisa de senha de administrador.';
    if (e.acesso.administrador) return 'O Windows vai pedir a sua confirmação: clique em “Sim”.';
    return 'O Windows vai pedir a senha de um administrador. Se você não tem, chame o suporte.';
  }
  function ajudar(t, e) {
    var n = nome(e);
    if (t.tipo === 'sistema') { ajudaSistema(e.sistemas.filter(function (x) { return x.id === t.id; })[0], e); return; }
    if (t.tipo === 'token') {
      var fr = document.createDocumentFragment();
      fr.append(h('h2', { id: 'folha-titulo', text: 'Seu token' }));
      var con = e.tokens.filter(function (x) { return x.conectado; })[0];
      var msg = con ? (con.estado === 'pronto' ? 'O ' + con.nome + ' está conectado e funcionando, ' + n + '.' : 'Vejo o ' + con.nome + ' conectado. ' + con.resumo + '.')
        : 'Não vejo nenhum token conectado agora, ' + n + '. Escolha o modelo do seu token que eu instalo ou confiro o driver dele.';
      fr.append(h('div', { class: 'assistente' }, h('img', { src: 'img/icone.png', alt: '' }), h('div', { class: 'balao' }, h('p', { text: msg }))));
      var esc = h('div', { class: 'escolhas' });
      e.tokens.forEach(function (tk) {
        var falta = tk.faltando.concat(tk.reparar);
        var txt = tk.estado === 'pronto' ? 'Conectado e pronto' : (falta.length ? (tk.faltando.length ? 'Falta instalar o driver' : 'O driver precisa de reparo') : 'Driver instalado');
        esc.append(h('button', { class: 'escolha', type: 'button', onclick: function () {
          if (falta.length) confirmarAcao({ acao: tk.faltando.length ? 'instalar' : 'reparar', itens: falta }, (tk.faltando.length ? 'Instalar o ' : 'Reparar o ') + tk.nome, falta, e);
          else { fecharFolha(); irPara('tokens'); }
        } }, h('span', { class: 'ic' }, icone('token', 22, 1.6)), h('span', { class: 'tx' }, h('strong', { text: tk.nome }), h('span', { text: tk.descricao + ' · ' + txt }))));
      });
      fr.append(esc);
      fr.append(h('div', { class: 'folha-pe' }, h('button', { class: 'botao', type: 'button', text: 'Fechar', onclick: fecharFolha }), h('button', { class: 'botao', type: 'button', text: 'Abrir a página Tokens', onclick: function () { fecharFolha(); irPara('tokens'); } })));
      abrirFolha(fr, 'assistente');
      return;
    }
    if (t.tipo === 'certificado') {
      var ps = pessoais(e);
      var linhas = ps.map(function (c) { return c.titular + ': ' + (c.situacao === 'vencido' ? 'venceu em ' + c.validade : (c.situacao === 'vencendo' ? 'vence em ' + c.dias + ' dias (' + c.validade + ')' : 'válido até ' + c.validade)); });
      assistente('Seu certificado', [ps.length ? (ps.length === 1 ? 'Encontrei 1 certificado seu neste Windows:' : 'Encontrei ' + ps.length + ' certificados seus neste Windows:') : 'Não encontrei nenhum certificado pessoal neste Windows, ' + n + '. Conecte o token: o certificado dele aparece alguns segundos depois de ser reconhecido.',
        ps.some(function (c) { return c.situacao !== 'valido'; }) ? 'Certificado vencido ou perto de vencer: procure o setor responsável pela renovação.' : ''], [
        botaoFolha('Ver certificados', '', function () { fecharFolha(); irPara('certificados'); }),
        botaoFolha('Instalar certificado (.pfx)', 'primario', function () { fecharFolha(); operacao({ operacao: 'importar-certificado' }); })], linhas);
      return;
    }
    if (t.tipo === 'problema') {
      var pend = pendencias(e);
      assistente('Vamos ver o que está acontecendo', [
        pend.length ? n + ', encontrei ' + (pend.length === 1 ? 'isto' : 'estes pontos') + ' no computador:' : 'Conferi tudo e não encontrei nada errado neste computador, ' + n + '.',
        pend.length ? 'Na tela inicial, escolha o sistema que você quer usar e eu resolvo. Se continuar com problema, gere o relatório e mande para o suporte.' : 'Se algo ainda não funciona, clique em Verificar de novo com o token conectado. Se continuar, gere o relatório e mande para o suporte.'], [
        botaoFolha('Verificar de novo', '', function () { fecharFolha(); S.ultimaVerificacao = Date.now(); api('/api/verificar', {}).catch(function () {}); brinde('Verificando o computador...'); }),
        botaoFolha('Gerar relatório para o suporte', 'primario', function () { fecharFolha(); operacao({ operacao: 'relatorio' }); })], pend);
      return;
    }
    // passo a passo
    var fr2 = document.createDocumentFragment();
    fr2.append(h('h2', { id: 'folha-titulo', text: 'Qual passo a passo?' }));
    var esc2 = h('div', { class: 'escolhas' });
    S.tutoriais.forEach(function (tu) {
      esc2.append(h('button', { class: 'escolha', type: 'button', onclick: function () { fecharFolha(); irPara('tutoriais', tu.id); } }, h('span', { class: 'ic' }, icone(tu.icone, 22, 1.6)), h('span', { class: 'tx' }, h('strong', { text: tu.titulo }), h('span', { text: tu.resumo }))));
    });
    fr2.append(esc2);
    fr2.append(h('div', { class: 'folha-pe' }, h('button', { class: 'botao', type: 'button', text: 'Fechar', onclick: fecharFolha })));
    abrirFolha(fr2, 'assistente');
  }
  function ajudaSistema(s, e) {
    if (!s) return;
    var n = nome(e);
    var tut = s.tutorial ? botaoFolha('Ver o passo a passo', '', function () { fecharFolha(); irPara('tutoriais', s.tutorial); }) : null;
    var abrir = null;
    if (s.temSite) abrir = botaoFolha(s.id === 'sigadaer' ? 'Abrir o SIGADAER' : 'Abrir o site', 'primario', function () { fecharFolha(); operacao({ operacao: 'abrir-site', sistema: s.id }); });
    if (s.temPrograma) abrir = botaoFolha('Abrir o assinador', 'primario', function () { fecharFolha(); operacao({ operacao: 'abrir-programa', alvo: s.id === 'adobe' ? 'adobe-xi' : 'assinador' }); });
    var nomesItens = function (ids) { return juntar(ids.map(function (id) { return e.itens[id] ? e.itens[id].nome : id; })); };
    if (s.estado === 'pronto') {
      assistente(s.nome, ['Está tudo pronto para o ' + s.nome + ', ' + n + '.', s.id === 'sigadaer' ? 'Eu abro o site no Firefox. Se ele pedir, escolha o certificado do token.' : (s.temPrograma ? 'É só abrir o assinador e escolher o arquivo.' : 'É só abrir o site e entrar com o certificado do token.')], [tut, abrir]);
    } else if (s.estado === 'aguardando') {
      assistente(s.nome, ['Os programas do ' + s.nome + ' já estão instalados, ' + n + '.', 'Falta só conectar o token na porta USB. Quando você conectar, eu percebo sozinho em alguns segundos.'], [tut, abrir]);
    } else if (s.estado === 'falta') {
      var oque = nomesItens(s.faltando) + (s.escolherToken ? (s.faltando.length ? ' e o driver do seu token' : 'o driver do seu token') : '');
      if (s.semPacote.length) {
        assistente(s.nome, ['Para o ' + s.nome + ' ainda falta: ' + oque + '.', 'Não consigo instalar agora porque falta o instalador de ' + juntar(s.semPacote) + '. Veja a página Diagnóstico.'], [tut]);
      } else {
        assistente(s.nome, ['Para usar o ' + s.nome + ' ainda falta: ' + oque + '.', 'Posso preparar tudo agora, ' + n + '. Leva alguns minutos e eu confiro cada passo no final. ' + viaTexto(e)], [tut,
          botaoFolha('Preparar agora', 'primario', function () { prepararSistema(s, e); })]);
      }
    } else if (s.estado === 'atencao' && s.passo && !s.reparar.length) {
      if (s.passo.acao === 'fixar') assistente(s.nome, ['A extensão do assinador já está no Firefox, ' + n + ', mas o botão dela está escondido no menu de extensões (a peça de quebra-cabeça).', 'Para o SIGADAER funcionar sem susto, o botão precisa ficar na barra. Quer que eu fixe agora?'], [tut, botaoFolha('Fixar na barra', 'primario', function () { fecharFolha(); fixarExtensao(false); })]);
      else assistente(s.nome, ['Eu já deixei a extensão do assinador pronta para entrar no Firefox, ' + n + '.', (e.firefoxAberto ? 'Feche e abra o Firefox' : 'Abra o Firefox uma vez') + ': ela entra sozinha, já fixada na barra. Depois eu confiro se está tudo certo.'], [tut, botaoFolha(e.firefoxAberto ? 'Fechar e abrir o Firefox' : 'Abrir o Firefox', 'primario', function () { fecharFolha(); abrirFirefoxPasso(); })]);
    } else if (s.estado === 'atencao') {
      var det = s.requisitos.filter(function (r) { return r.estado === 'atencao'; }).map(function (r) { return r.nome + ': ' + r.detalhe; });
      var depois = s.passo ? (s.passo.acao === 'fixar' ? 'Depois falta só fixar o botão do assinador na barra do Firefox, que eu também faço.' : 'Depois falta só abrir o Firefox uma vez.') : '';
      assistente(s.nome, ['Encontrei um problema no ' + s.nome + ', ' + n + ':', 'Posso reparar agora. ' + viaTexto(e) + (depois ? ' ' + depois : '')], [tut, botaoFolha('Reparar agora', 'primario', function () { prepararSistema(s, e); })], det);
    } else {
      assistente(s.nome, ['Não dá para preparar o ' + s.nome + ' ainda: ' + s.resumo, 'Fale com o suporte.'], [botaoFolha('Ver detalhes', '', function () { fecharFolha(); irPara('sistemas'); })]);
    }
  }

  /* ---------- Sistemas ---------- */
  function seloSistema(s) {
    if (s.estado === 'pronto') return selo('ok', 'Pronto', true);
    if (s.estado === 'aguardando') return selo('', 'Conecte o token');
    if (s.estado === 'falta') return selo('alerta', 'Falta instalar');
    if (s.estado === 'atencao') return selo('alerta', 'Precisa de reparo');
    return selo('erro', 'Bloqueado');
  }
  function cartaoSistema(s, e) {
    var c = cartao(s.nome + ' ' + s.descricao);
    c.append(cabeca(s.icone, s.nome, s.descricao, seloSistema(s), s.opcional ? ['opcional'] : null));
    var ls = h('div', { class: 'linhas' });
    s.requisitos.forEach(function (r) {
      ls.append(linhaDupla(r.nome, r.detalhe, r.estado === 'ok' || r.estado === 'aguardando' ? '' : 'atencao', marca(r.estado)));
    });
    s.opcionais.forEach(function (r) {
      ls.append(linhaDupla(r.nome, r.estado === 'ok' ? 'Instalado' : 'Não instalado', '', r.estado === 'ok' ? marca('ok') : null, 'opcional'));
    });
    c.append(ls);
    var ns = h('div', { class: 'notas' });
    s.avisos.forEach(function (a) { ns.append(nota(a, true)); });
    if (s.semPacote.length) ns.append(nota('Instalador não encontrado: ' + s.semPacote.join(', ') + '. Veja a página Diagnóstico.', true));
    if (ns.childNodes.length) c.append(ns);

    var pe = h('div', { class: 'cartao-pe' });
    var cls = s.estado === 'pronto' ? 'ok' : (s.estado === 'bloqueado' ? 'erro' : (s.estado === 'aguardando' ? '' : 'alerta'));
    var res = h('span', { class: 'resumo ' + cls }, s.estado === 'pronto' ? icone('checkCirculo', 16, 2.2) : null, h('span', { text: s.resumo }));
    pe.append(res);
    if (s.tutorial) pe.append(h('button', { class: 'botao fantasma', type: 'button', text: 'Tutorial', onclick: function () { irPara('tutoriais', s.tutorial); } }));
    var usavel = (s.estado === 'pronto' || s.estado === 'aguardando');
    if (usavel && s.temSite) pe.append(h('button', { class: 'botao primario', type: 'button', text: 'Abrir', onclick: function () { operacao({ operacao: 'abrir-site', sistema: s.id }); } }));
    if (usavel && s.temPrograma) pe.append(h('button', { class: 'botao primario', type: 'button', text: 'Abrir', onclick: function () { operacao({ operacao: 'abrir-programa', alvo: s.id === 'adobe' ? 'adobe-xi' : 'assinador' }); } }));
    if (s.estado === 'falta') pe.append(h('button', { class: 'botao primario', type: 'button', text: 'Preparar', disabled: s.semPacote.length > 0, onclick: function () { prepararSistema(s, e); } }));
    if (s.estado === 'atencao' && s.reparar.length) pe.append(h('button', { class: 'botao primario', type: 'button', text: 'Reparar', onclick: function () { prepararSistema(s, e); } }));
    else if (s.estado === 'atencao' && s.passo) pe.append(h('button', { class: 'botao primario', type: 'button', text: s.passo.acao === 'fixar' ? 'Fixar na barra' : 'Abrir o Firefox', onclick: function () { fazerPasso(s.passo); } }));
    c.append(pe);
    return c;
  }
  function paginaSistemas(e) {
    var f = document.createDocumentFragment();
    var av = avisosTopo(e); if (av) f.append(av);
    var g = h('div', { class: 'grade' });
    e.sistemas.forEach(function (s) { g.append(cartaoSistema(s, e)); });
    f.append(g);
    return f;
  }

  /* ---------- Tokens ---------- */
  function seloToken(t) {
    if (t.estado === 'pronto') return selo('ok', 'Conectado', true);
    if (t.estado === 'atencao') return selo('alerta', 'Atenção');
    if (t.estado === 'sem-driver') return t.conectado ? selo('alerta', 'Conectado, sem driver') : selo('', 'Não instalado');
    return selo('', 'Desconectado');
  }
  function cartaoToken(t, e) {
    var c = cartao(t.nome + ' ' + t.descricao + ' ' + t.fabricante);
    c.append(cabeca('token', t.nome, t.descricao, seloToken(t)));
    var ls = h('div', { class: 'linhas' });
    t.itens.forEach(function (id) {
      var it = e.itens[id];
      ls.append(linha(it.nome, h('span', { text: it.detalhe }), it.estado === 'ok' ? '' : 'fraco', it.estado === 'ok' ? marca('ok') : null));
    });
    ls.append(linha('Leitor no Windows', h('span', { text: t.leitor || (t.conectado ? 'Reconhecido' : 'Não conectado') }), t.leitor ? '' : 'fraco'));
    ls.append(linha('No assinador', h('span', { text: 'Método ' + t.metodoAssinador })));
    var prontoDriver = (t.faltando.length === 0 && t.reparar.length === 0);
    if (t.ajusteAssinador) {
      var assinadorOk = e.itens.assinador && e.itens.assinador.estado !== 'ausente';
      if (t.ajusteAssinadorFeito) ls.append(linha('Ajuste para o Método Alfa', h('span', { text: 'Feito neste usuário' }), '', marca('ok')));
      else ls.append(linha('Ajuste para o Método Alfa', h('button', { class: 'botao pequeno', type: 'button', text: 'Ajustar', disabled: !(prontoDriver && assinadorOk), title: (prontoDriver && assinadorOk) ? '' : 'Instale o driver do token e o Assinador do COMAER primeiro', onclick: function () { operacao({ operacao: 'assinador-token', token: t.id }); } })));
    }
    c.append(ls);
    var avisos = [];
    t.itens.forEach(function (id) { if (e.itens[id].estado !== 'ok') avisos = avisos.concat(e.itens[id].avisos); });
    if (avisos.length) { var ns = h('div', { class: 'notas' }); avisos.forEach(function (a) { ns.append(nota(a)); }); c.append(ns); }

    var pe = h('div', { class: 'cartao-pe' });
    var cls = t.estado === 'pronto' ? 'ok' : (t.estado === 'desconectado' ? '' : (t.conectado ? 'alerta' : ''));
    pe.append(h('span', { class: 'resumo ' + cls }, t.estado === 'pronto' ? icone('checkCirculo', 16, 2.2) : null, h('span', { text: t.resumo })));
    if (prontoDriver) {
      pe.append(h('button', { class: 'botao', type: 'button', text: 'Abrir o gerenciador', title: t.administrador, onclick: function () { operacao({ operacao: 'abrir-programa', alvo: 'token:' + t.id }); } }));
      var desins = t.itens.filter(function (id) { return e.itens[id] && e.itens[id].podeDesinstalar; });
      var opT = [{ rotulo: 'Reparar o driver', icone: 'engrenagem', acao: function () { confirmarAcao({ acao: 'reparar', itens: t.itens.slice() }, 'Reparar o ' + t.nome, t.itens, e); } }];
      if (desins.length) opT.push('-', { rotulo: 'Desinstalar o driver', icone: 'xis', perigo: true, acao: function () { confirmarAcao({ acao: 'desinstalar', itens: desins }, 'Desinstalar o driver do ' + t.nome, desins, e); } });
      pe.append(engrenagem(opT, 'Mais opções do ' + t.nome));
    } else {
      var semPac = [];
      t.faltando.forEach(function (id) { semPac = semPac.concat(e.itens[id].pacotesFaltando); });
      pe.append(h('button', { class: 'botao primario', type: 'button', text: t.faltando.length ? 'Instalar' : 'Reparar', disabled: semPac.length > 0, title: semPac.length ? 'Instalador não encontrado: ' + semPac.join(', ') : '', onclick: function () { confirmarAcao({ acao: t.faltando.length ? 'instalar' : 'reparar', itens: t.faltando.concat(t.reparar) }, (t.faltando.length ? 'Instalar o ' : 'Reparar o ') + t.nome, t.faltando.concat(t.reparar), e); } }));
    }
    c.append(pe);
    return c;
  }
  function paginaTokens(e) {
    var f = document.createDocumentFragment();
    var av = avisosTopo(e, 'tokens'); if (av) f.append(av);
    var g = h('div', { class: 'grade' });
    e.tokens.forEach(function (t) { g.append(cartaoToken(t, e)); });
    e.leitoresDesconhecidos.forEach(function (l) {
      var c = cartao('leitor ' + l.nome);
      c.append(cabeca('usb', 'Token ou leitor não identificado', l.nome, selo('alerta', 'Conectado')));
      var ns = h('div', { class: 'notas' });
      ns.append(nota('O Windows enxerga este aparelho, mas ele não corresponde a nenhum modelo com driver instalado. Se for o DXToken (Dexon), instale o DXSafe no cartão ao lado e clique em Verificar tudo.'));
      c.append(ns);
      g.append(c);
    });
    f.append(g);
    var sv = e.itens['servico-smartcard'];
    if (sv && sv.estado !== 'ok') {
      var c2 = cartao('servico cartao inteligente');
      c2.append(cabeca('engrenagem', sv.nome, sv.descricao, selo('alerta', 'Precisa de reparo')));
      var pe = h('div', { class: 'cartao-pe' });
      pe.append(h('span', { class: 'resumo alerta', text: sv.detalhe }));
      pe.append(h('button', { class: 'botao primario', type: 'button', text: 'Reparar', onclick: function () { confirmarAcao({ acao: 'reparar', itens: ['servico-smartcard'] }, 'Reparar o serviço de cartão inteligente', ['servico-smartcard'], e); } }));
      c2.append(pe);
      f.append(c2);
    }
    return f;
  }

  /* ---------- Programas ---------- */
  function seloItem(i) {
    if (i.estado === 'ok') return selo('ok', 'Em ordem');
    if (i.estado === 'atencao') return selo('alerta', i.acao === 'instalar' ? 'Atualizar' : 'Precisa de reparo');
    if (i.estado === 'conflito') return selo('erro', 'Conflito');
    return selo('', 'Não instalado');
  }
  function cartaoItem(i, e) {
    var c = cartao(i.nome + ' ' + i.descricao);
    var etq = [];
    if (i.opcional) etq.push('opcional');
    if (i.legado) etq.push('versão antiga');
    c.append(cabeca(i.icone, i.nome, i.descricao, seloItem(i), etq));
    var mostraVersao = i.versao && !/^java/.test(i.id) && i.id !== 'firefox-esr';
    if (i.verificacoes.length || mostraVersao) {
      var ls = h('div', { class: 'linhas' });
      if (mostraVersao) ls.append(linha('Versão do instalador', h('span', { text: i.versao }), 'fraco'));
      i.verificacoes.forEach(function (v) {
        ls.append(linhaDupla(v.nome, v.detalhe, v.ok || v.informativa ? '' : 'atencao', v.ok ? marca('ok') : (v.informativa ? null : marca('x'))));
      });
      c.append(ls);
    }
    var ns = h('div', { class: 'notas' });
    if (i.estado !== 'ok') i.avisos.forEach(function (a) { ns.append(nota(a, i.legado)); });
    if (i.pacotesFaltando.length && i.estado !== 'ok') ns.append(nota('Instalador não encontrado: ' + i.pacotesFaltando.join(', '), true));
    if (ns.childNodes.length) c.append(ns);
    var pe = h('div', { class: 'cartao-pe' });
    var cls = i.estado === 'ok' ? 'ok' : (i.estado === 'conflito' ? 'erro' : (i.estado === 'atencao' ? 'alerta' : ''));
    var curto = i.detalhe;
    if (i.verificacoes.length && i.estado === 'atencao') curto = i.acao === 'instalar' ? 'Precisa atualizar' : 'Precisa de reparo';
    pe.append(h('span', { class: 'resumo ' + cls }, i.estado === 'ok' ? icone('checkCirculo', 16, 2.2) : null, h('span', { text: curto })));
    botoesItem(i, e, pe);
    c.append(pe);
    return c;
  }
  function botoesItem(i, e, pe) {
    var mais = [];
    var instalar = function (titulo) { confirmarAcao({ acao: 'instalar', itens: [i.id] }, titulo || ('Instalar: ' + i.nome), [i.id], e); };
    var reparar = function (titulo) { confirmarAcao({ acao: 'reparar', itens: [i.id] }, titulo || ('Reparar: ' + i.nome), [i.id], e); };
    var desinstalar = function (titulo) { confirmarAcao({ acao: 'desinstalar', itens: [i.id] }, titulo || ('Desinstalar: ' + i.nome), [i.id], e); };
    var semPacote = i.pacotesFaltando.length > 0;
    if (i.id === 'firefox-esr') {
      if (i.estado === 'ausente') pe.append(h('button', { class: 'botao primario', type: 'button', text: 'Instalar o Firefox ESR', disabled: semPacote, onclick: function () { instalar('Instalar o Firefox ESR'); } }));
      else {
        pe.append(h('button', { class: 'botao primario', type: 'button', text: 'Abrir', onclick: function () { abrirFirefox('', ''); } }));
        if (i.temDeveloper && i.temEsr) mais.push({ rotulo: 'Abrir o Developer Edition', icone: 'firefox', acao: function () { abrirFirefox('developer', ''); } }, { rotulo: 'Abrir o ESR', icone: 'firefox', acao: function () { abrirFirefox('esr', ''); } }, '-');
        if (!i.temEsr && !semPacote) mais.push({ rotulo: 'Instalar o ESR (reserva)', icone: 'caixa', acao: function () { instalar('Instalar o Firefox ESR (reserva)'); } });
        if (i.temEsr) mais.push({ rotulo: 'Reparar o ESR', icone: 'engrenagem', acao: function () { reparar('Reparar o Firefox ESR'); } });
        if (i.podeDesinstalar) mais.push('-', { rotulo: 'Desinstalar o ESR', icone: 'xis', perigo: true, acao: function () { desinstalar('Desinstalar o Firefox ESR'); } });
      }
    } else if (i.estado === 'ausente' || (i.estado === 'atencao' && i.acao === 'instalar')) {
      var bloqueado = semPacote || (i.id === 'extensao-firefox' && e.itens['firefox-esr'].estado === 'ausente' && e.itens['firefox-esr'].pacotesFaltando.length > 0);
      pe.append(h('button', { class: 'botao primario', type: 'button', text: i.estado === 'atencao' ? 'Atualizar' : (i.categoria === 'ambiente' ? 'Reparar' : 'Instalar'), disabled: bloqueado, onclick: function () { instalar(); } }));
    } else if (i.estado === 'atencao' && i.acao === 'fixar') {
      pe.append(h('button', { class: 'botao primario', type: 'button', text: 'Fixar na barra', onclick: function () { fixarExtensao(false); } }));
    } else if (i.estado === 'atencao' && i.acao === 'abrir-firefox') {
      pe.append(h('button', { class: 'botao primario', type: 'button', text: 'Abrir o Firefox', onclick: function () { abrirFirefoxPasso(); } }));
    } else if (i.estado === 'atencao') {
      pe.append(h('button', { class: 'botao primario', type: 'button', text: i.reinstalar ? 'Reinstalar' : 'Reparar', onclick: function () { reparar(); } }));
    } else if (i.estado === 'ok' && i.abrir) {
      pe.append(h('button', { class: 'botao primario', type: 'button', text: 'Abrir', onclick: function () { abrirAlvo(i.abrir); } }));
    } else if (i.estado === 'ok' && i.categoria === 'ambiente') {
      mais.push({ rotulo: 'Reparar', icone: 'engrenagem', acao: function () { reparar(); } });
    }
    if (i.id !== 'firefox-esr' && i.estado !== 'ausente' && i.estado !== 'conflito') {
      if (i.podeReparar && !(i.estado === 'atencao' && i.acao === 'reparar')) mais.push({ rotulo: i.reinstalar || i.id === 'extensao-firefox' ? 'Reparar' : 'Reparar (reinstala por cima)', icone: 'engrenagem', acao: function () { reparar(); } });
      if (i.podeDesinstalar) mais.push('-', { rotulo: 'Desinstalar', icone: 'xis', perigo: true, acao: function () { desinstalar(); } });
    }
    while (mais.length && mais[0] === '-') mais.shift();
    while (mais.length && mais[mais.length - 1] === '-') mais.pop();
    if (mais.length) pe.append(engrenagem(mais, 'Mais opções: ' + i.nome));
  }
  function paginaProgramas(e) {
    var f = document.createDocumentFragment();
    var av = avisosTopo(e, 'programas'); if (av) f.append(av);
    var its = itensProgramas(e);
    var principais = its.filter(function (i) { return !i.opcional && !i.legado; });
    var outros = its.filter(function (i) { return i.opcional || i.legado; });
    var g = h('div', { class: 'grade' });
    principais.forEach(function (i) { g.append(cartaoItem(i, e)); });
    f.append(g);
    if (outros.length) {
      f.append(h('h3', { class: 'secao-titulo', text: 'Só para quem precisa' }));
      var g2 = h('div', { class: 'grade' });
      outros.forEach(function (i) { g2.append(cartaoItem(i, e)); });
      f.append(g2);
    }
    return f;
  }

  /* ---------- Certificados ---------- */
  function cartaoCert(c0) {
    var c = cartao(c0.titular + ' ' + c0.emissor, false);
    var s;
    if (c0.situacao === 'vencido') s = selo('erro', 'Vencido');
    else if (c0.situacao === 'vencendo') s = selo('alerta', 'Vence em ' + c0.dias + (c0.dias === 1 ? ' dia' : ' dias'));
    else if (c0.situacao === 'futuro') s = selo('', 'Ainda não vale');
    else s = selo('ok', 'Válido');
    c.append(cabeca('selo', c0.titular, 'Emitido por ' + c0.emissor, s));
    var cls = c0.situacao === 'vencido' ? 'erro' : (c0.situacao === 'vencendo' ? 'alerta' : '');
    var val = h('span', { class: 'validade ' + cls }, h('span', { class: 'trilho' }, (function () { var b = h('span'); b.style.width = Math.max(3, c0.restante) + '%'; return b; })()),
      h('span', { text: c0.validade + (c0.situacao === 'vencido' ? '' : ' · ' + c0.dias + (c0.dias === 1 ? ' dia' : ' dias')) }));
    var ls = h('div', { class: 'linhas' });
    ls.append(linha('Validade', val, c0.situacao === 'vencendo' || c0.situacao === 'vencido' ? 'atencao' : ''));
    ls.append(linha('Chave para assinar', h('span', { text: c0.chavePrivada ? 'Presente (no token ou neste Windows)' : 'Ausente' }), c0.chavePrivada ? '' : 'fraco'));
    c.append(ls);
    return c;
  }
  function paginaCertificados(e) {
    var f = document.createDocumentFragment();
    var av = avisosTopo(e, 'certificados'); if (av) f.append(av);
    f.append(h('div', { class: 'barra-acoes' },
      h('button', { class: 'botao primario', type: 'button', text: 'Instalar certificado em arquivo (.pfx)', onclick: function () { operacao({ operacao: 'importar-certificado' }); } }),
      h('button', { class: 'botao', type: 'button', text: 'Abrir os certificados do Windows', onclick: function () { operacao({ operacao: 'abrir-programa', alvo: 'certificados' }); } })));
    var ps = pessoais(e);
    if (!ps.length) {
      var v = cartao('', false);
      v.append(h('div', { class: 'vazio', text: 'Nenhum certificado pessoal encontrado. Conecte o token e clique em Verificar tudo: o certificado do token aparece aqui alguns segundos depois de ser reconhecido.' }));
      f.append(v);
    } else {
      var g = h('div', { class: 'grade' });
      ps.forEach(function (c) { g.append(cartaoCert(c)); });
      f.append(g);
    }
    var tec = e.certificados.filter(function (c) { return !c.pessoal; });
    if (tec.length) {
      f.append(h('div', { class: 'barra-acoes' }, h('button', { class: 'botao fantasma', type: 'button', text: S.certTecnicos ? 'Esconder os certificados técnicos' : 'Mostrar os ' + tec.length + ' certificados técnicos do Windows', onclick: function () { S.certTecnicos = !S.certTecnicos; desenhar(); } })));
      if (S.certTecnicos) { var g2 = h('div', { class: 'grade' }); tec.forEach(function (c) { g2.append(cartaoCert(c)); }); f.append(g2); }
    }
    return f;
  }

  /* ---------- Tutoriais ---------- */
  function acaoTutorial(a) {
    if (!a) return null;
    return h('button', { class: 'botao pequeno', type: 'button', text: a.rotulo, onclick: function () {
      if (a.tipo === 'pagina') irPara(a.pagina);
      else if (a.tipo === 'abrir-site') operacao({ operacao: 'abrir-site', sistema: a.sistema });
      else if (a.tipo === 'abrir-programa') operacao({ operacao: 'abrir-programa', alvo: a.alvo });
    } });
  }
  function paginaTutoriais(e) {
    var f = document.createDocumentFragment();
    if (!S.tutoriais.length) { var v = cartao('', false); v.append(h('div', { class: 'vazio', text: 'Carregando os tutoriais...' })); f.append(v); return f; }
    var q = semAcento(S.busca);
    var lista = S.tutoriais.filter(function (t) { return !q || semAcento(t.titulo + ' ' + t.resumo + ' ' + t.passos.map(function (p) { return p.titulo + ' ' + p.texto; }).join(' ') + ' ' + (t.dicas || []).join(' ')).indexOf(q) >= 0; });
    var atual = lista.filter(function (t) { return t.id === S.tutorialAtual; })[0] || lista[0];
    var caixa = h('div', { class: 'tutoriais' });
    var col = h('div', { class: 'tuto-lista' });
    lista.forEach(function (t) {
      var ic = h('span', { class: 'ic' }, icone(t.icone, 20, 1.7));
      col.append(h('button', { class: 'tuto-item', type: 'button', 'aria-current': atual && t.id === atual.id ? 'true' : null, onclick: function () { S.tutorialAtual = t.id; desenhar(); } },
        ic, h('span', { class: 'tx' }, h('strong', { text: t.titulo }), h('span', { text: t.resumo }))));
    });
    caixa.append(col);
    if (atual) {
      var c = cartao('', false);
      c.classList.add('tuto');
      c.append(h('h2', { text: atual.titulo }), h('p', { class: 'resumo-tuto', text: atual.resumo }));
      if (atual.sistema) {
        var s = e.sistemas.filter(function (x) { return x.id === atual.sistema; })[0];
        if (s) c.append(h('div', { class: 'barra-acoes', style: 'margin-top:12px' }, seloSistema(s),
          (s.estado === 'falta' || s.estado === 'atencao') ? h('button', { class: 'botao pequeno primario', type: 'button', text: s.estado === 'falta' ? 'Preparar agora' : 'Reparar agora', disabled: s.semPacote.length > 0, onclick: function () { prepararSistema(s, e); } }) : null));
      }
      var ps = h('div', { class: 'passos' });
      atual.passos.forEach(function (p, i) {
        ps.append(h('div', { class: 'passo' }, h('span', { class: 'num', text: String(i + 1) }), h('div', { class: 'corpo' }, h('strong', { text: p.titulo }), h('p', { text: p.texto }), acaoTutorial(p.acao))));
      });
      c.append(ps);
      if (atual.dicas && atual.dicas.length) { var ns = h('div', { class: 'notas' }); atual.dicas.forEach(function (d) { ns.append(nota(d)); }); c.append(ns); }
      if (atual.fonte) c.append(h('p', { class: 'fonte', text: 'Fonte: ' + atual.fonte }));
      caixa.append(c);
    } else {
      var vz = cartao('', false); vz.append(h('div', { class: 'vazio', text: 'Nenhum tutorial com esse termo.' })); caixa.append(vz);
    }
    f.append(caixa);
    return f;
  }

  /* ---------- Acesso (instalar sem administrador) ---------- */
  function paginaAcesso(e) {
    var a = e.acesso;
    var f = document.createDocumentFragment();
    var g = h('div', { class: 'grade' });

    var c1 = cartao('usuario conta administrador', false);
    c1.append(cabeca('usuario', 'Quem está usando', e.computador, a.administrador ? selo('', 'Administrador') : selo('', 'Usuário comum')));
    var l1 = h('div', { class: 'linhas' });
    l1.append(linha('Usuário', h('span', { text: a.usuario || '—' })));
    l1.append(linha('Tipo de conta', h('span', { text: a.administrador ? 'Administrador' : 'Usuário comum' })));
    var como = a.liberado ? 'Um clique, sem senha' : (a.administrador ? 'O Windows pede a sua confirmação (“Sim”)' : 'O Windows pede a senha de um administrador');
    l1.append(linha('Para instalar ou reparar', h('span', { text: como }), '', a.liberado ? marca('ok') : null));
    c1.append(l1);
    var n1 = h('div', { class: 'notas' });
    if (!a.liberado && !a.administrador) n1.append(nota('Sem a senha de administrador este usuário não consegue instalar. O suporte resolve isso de uma vez liberando o computador, no cartão “Instalar sem administrador”.', true));
    n1.append(nota('Em computador pessoal não precisa liberar: abra o Lacador.exe e confirme a janela do Windows quando ela aparecer.'));
    c1.append(n1);
    g.append(c1);

    var c2 = cartao('liberar instalar sem administrador agente', false);
    c2.append(cabeca('cadeado', 'Instalar sem administrador', 'Liberação deste computador, feita uma vez pelo suporte', a.liberado ? selo('ok', 'Liberado') : selo('', 'Não liberado')));
    if (a.liberado) {
      var l2 = h('div', { class: 'linhas' });
      if (a.pasta) l2.append(linha('Laçador instalado em', h('span', { class: 'mono', text: a.pasta })));
      if (a.versaoInstalada) l2.append(linha('Versão instalada', h('span', { text: a.versaoInstalada })));
      c2.append(l2);
    }
    var n2 = h('div', { class: 'notas' });
    if (a.liberado) {
      n2.append(nota('Qualquer usuário deste computador instala e repara pelo Laçador com um clique, sem senha.'));
      if (a.atualizar) n2.append(nota('Esta cópia do Laçador é mais nova que a instalada no computador. Clique em Atualizar.', true));
    } else {
      n2.append(nota('O suporte libera uma vez, com a senha de administrador. Depois disso, qualquer usuário deste computador instala e repara pelo Laçador com um clique, sem senha.'));
      n2.append(nota('O Laçador é copiado para o computador e ganha atalho no Menu Iniciar e na Área de Trabalho.'));
    }
    n2.append(nota('O usuário só instala o que está no catálogo do Laçador, e cada instalador é conferido antes de rodar.'));
    c2.append(n2);
    var p2 = h('div', { class: 'cartao-pe' });
    p2.append(h('span', { class: 'resumo ' + (a.liberado ? 'ok' : '') }, a.liberado ? icone('checkCirculo', 16, 2.2) : null, h('span', { text: a.liberado ? 'Liberado' : 'Precisa de administrador uma vez' })));
    if (a.liberado) {
      p2.append(h('button', { class: 'botao', type: 'button', text: 'Remover a liberação', onclick: function () { confirmarAcesso('remover', e); } }));
      if (a.atualizar) p2.append(h('button', { class: 'botao primario', type: 'button', text: 'Atualizar', onclick: function () { confirmarAcesso('liberar', e); } }));
    } else {
      p2.append(h('button', { class: 'botao primario', type: 'button', text: 'Liberar este computador', onclick: function () { confirmarAcesso('liberar', e); } }));
    }
    c2.append(p2);
    g.append(c2);
    f.append(g);
    return f;
  }

  function confirmarAcesso(tipo, e) {
    var a = e.acesso, liberar = (tipo === 'liberar');
    var fr = document.createDocumentFragment();
    fr.append(h('h2', { id: 'folha-titulo', text: liberar ? (a.liberado ? 'Atualizar o Laçador neste computador' : 'Liberar este computador') : 'Remover a liberação' }));
    var sub = e.demonstracao ? 'Modo demonstração: nada será alterado neste computador.'
      : (a.administrador ? 'O Windows vai pedir a sua confirmação. Clique em “Sim” para autorizar.'
        : 'O Windows vai pedir a senha de um administrador. Chame o suporte se você não tiver.');
    fr.append(h('p', { class: 'sub', text: sub }));
    var lista = h('div', { class: 'folha-lista' });
    var itens = liberar ? [
      ['Copiar o Laçador para o computador', 'Fica em C:\\Program Files\\Lacador, com atalho no Menu Iniciar e na Área de Trabalho.'],
      ['Criar o agente do Laçador', 'Uma tarefa do Windows que instala e repara quando o usuário pede pela tela. Só roda sob demanda.'],
      ['Liberar para todos os usuários', 'Qualquer usuário deste computador passa a instalar e reparar sem senha de administrador.']
    ] : [
      ['Remover o agente, os atalhos e a cópia do Laçador', 'Os usuários comuns voltam a precisar da senha de administrador para instalar.'],
      ['Manter o que já foi instalado', 'Drivers, assinador, Firefox e Java continuam no computador.']
    ];
    itens.forEach(function (it) {
      lista.append(h('div', { class: 'folha-item' }, h('span', { class: 'est' }, (function () { var i = icone('ponto', 16, 2); i.style.color = '#98A2B3'; return i; })()),
        h('span', { class: 'tx' }, h('strong', { text: it[0] }), h('span', { text: it[1] }))));
    });
    fr.append(lista);
    var erro = h('p', { class: 'sub', style: 'color:#A1260D', hidden: true });
    fr.append(erro);
    var ir = h('button', { class: 'botao primario', type: 'button', text: liberar ? (a.liberado ? 'Atualizar' : 'Liberar') : 'Remover', onclick: function () {
      ir.disabled = true; ir.textContent = 'Iniciando...';
      api('/api/acesso', { acao: tipo }).then(function (r) {
        if (!r.ok) { erro.textContent = r.mensagem || 'Não foi possível iniciar.'; erro.hidden = false; ir.disabled = false; ir.textContent = 'Tentar de novo'; return; }
        S.acessoIgnorar = false;
        S.acesso = { tipo: tipo, estado: 'executando', mensagem: '' };
        desenharAcesso();
      }).catch(function () { erro.textContent = 'O Laçador não respondeu.'; erro.hidden = false; ir.disabled = false; ir.textContent = 'Tentar de novo'; });
    } });
    fr.append(h('div', { class: 'folha-pe' }, h('button', { class: 'botao', type: 'button', text: 'Cancelar', onclick: fecharFolha }), ir));
    abrirFolha(fr, 'confirmar');
  }

  function desenharAcesso() {
    var a = S.acesso;
    if (!a) return;
    var liberar = (a.tipo === 'liberar'), fim = (a.estado !== 'executando'), deuCerto = (a.estado === 'concluido');
    var fr = document.createDocumentFragment();
    var titulo = !fim ? (liberar ? 'Liberando este computador...' : 'Removendo a liberação...')
      : (deuCerto ? (liberar ? 'Computador liberado' : 'Liberação removida') : 'Não foi possível concluir');
    fr.append(h('h2', { id: 'folha-titulo', text: titulo }));
    var sub = !fim ? 'Se a janela de administrador do Windows aparecer, autorize. Pode levar um ou dois minutos. Não feche o Laçador.'
      : (a.mensagem || (deuCerto ? 'Concluído.' : 'Veja o registro na página Diagnóstico.'));
    fr.append(h('p', { class: 'sub', text: sub }));
    var est = h('span', { class: 'est' });
    if (!fim) est.append(h('span', { class: 'gira', role: 'img', 'aria-label': 'em andamento' }));
    else { var i1 = icone(deuCerto ? 'checkCirculo' : 'xis', 20, 2); i1.style.color = deuCerto ? '#1E8E3E' : '#C4360F'; est.append(i1); }
    var texto = !fim ? 'Trabalhando...' : (deuCerto ? (liberar ? 'Qualquer usuário já pode instalar e reparar sem senha.' : 'Os usuários comuns voltam a precisar da senha de administrador.') : 'Nada foi alterado, ou a operação ficou pela metade.');
    fr.append(h('div', { class: 'folha-lista' }, h('div', { class: 'folha-item' }, est, h('span', { class: 'tx' }, h('strong', { text: liberar ? 'Instalar sem administrador' : 'Remover a liberação' }), h('span', { class: fim && !deuCerto ? 'erro' : '', text: texto })))));
    if (fim) fr.append(h('div', { class: 'folha-pe' }, h('button', { class: 'botao primario', type: 'button', text: 'Fechar', onclick: function () { S.acessoIgnorar = true; S.acesso = null; fecharFolha(); api('/api/acesso/fechar', {}).catch(function () {}); } })));
    abrirFolha(fr, 'acesso');
  }

  /* ---------- Diagnóstico ---------- */
  function frasesDiagnostico(e) {
    var n = nome(e), fr = [];
    var ok = function (t) { fr.push({ tipo: 'ok', texto: t }); }, alerta = function (t) { fr.push({ tipo: 'alerta', texto: t }); }, info = function (t) { fr.push({ tipo: 'info', texto: t }); };
    var win = (e.windows.nome || 'Windows').replace('Microsoft ', '') + (e.windows.versao ? ' ' + e.windows.versao : '');
    info(n + ', este é o computador ' + e.computador + ', com ' + win + '. Você entrou com uma conta ' + (e.acesso.administrador ? 'de administrador' : 'comum, sem senha de administrador') + '.');
    var ps = principais(e), grupo = function (est) { return ps.filter(function (s) { return s.estado === est; }); };
    var prontos = grupo('pronto'), aguard = grupo('aguardando'), falta = grupo('falta'), aten = grupo('atencao'), bloq = grupo('bloqueado');
    if (prontos.length) ok('Pronto para usar: ' + juntar(prontos.map(function (s) { return s.nome; })) + '.');
    if (aguard.length) ok('Instalado, só falta conectar o token: ' + juntar(aguard.map(function (s) { return s.nome; })) + '.');
    falta.forEach(function (s) { alerta('Para o ' + s.nome + ' falta instalar: ' + juntar(s.faltando.map(function (id) { return e.itens[id] ? e.itens[id].nome : id; }).concat(s.escolherToken ? ['o driver do token'] : [])) + '.'); });
    aten.forEach(function (s) {
      if (s.passo) alerta(s.nome + ': ' + s.resumo.charAt(0).toLowerCase() + s.resumo.slice(1) + '.');
      else alerta('O ' + s.nome + ' precisa de reparo: ' + juntar(s.requisitos.filter(function (r) { return r.estado === 'atencao'; }).map(function (r) { return r.nome + ' (' + r.detalhe.charAt(0).toLowerCase() + r.detalhe.slice(1) + ')'; })) + '.');
    });
    bloq.forEach(function (s) { alerta('O ' + s.nome + ' está bloqueado: ' + s.resumo); });
    var con = e.tokens.filter(function (t) { return t.conectado; })[0];
    if (con && con.estado === 'pronto') ok('Token conectado agora: ' + con.nome + ', funcionando.');
    else if (con) alerta('Token conectado agora: ' + con.nome + '. ' + con.resumo + '.');
    else {
      var drv = e.tokens.filter(function (t) { return t.faltando.length === 0 && t.reparar.length === 0; });
      info('Nenhum token conectado agora.' + (drv.length ? ' Driver instalado: ' + juntar(drv.map(function (t) { return t.nome; })) + '.' : ' Nenhum driver de token instalado.'));
    }
    var cs = pessoais(e);
    if (!cs.length) info('Nenhum certificado pessoal neste Windows (o do token aparece quando ele é conectado).');
    cs.forEach(function (c) {
      if (c.situacao === 'vencido') fr.push({ tipo: 'erro', texto: 'O certificado de ' + c.titular + ' venceu em ' + c.validade + '. Procure o setor responsável para renovar.' });
      else if (c.situacao === 'vencendo') alerta('O certificado de ' + c.titular + ' vence em ' + c.dias + (c.dias === 1 ? ' dia' : ' dias') + ' (' + c.validade + ').');
      else ok('Certificado de ' + c.titular + ': válido até ' + c.validade + '.');
    });
    var ff = e.itens['firefox-esr'], ext = e.itens['extensao-firefox'];
    if (ff) {
      if (ff.estado === 'ausente') alerta('Firefox: ' + ff.detalhe + '. O SIGADAER usa o Firefox Developer Edition (padrão da base) ou o ESR (reserva).');
      else ok('Firefox: ' + ff.detalhe + (ff.temDeveloper && !ff.temEsr ? ' (padrão da base). O ESR, que é a reserva, não está instalado.' : '.'));
    }
    if (ext && ff && ff.estado !== 'ausente') {
      if (ext.estado === 'ok') ok('Extensão do assinador: ativa no Firefox e com o botão fixado na barra.');
      else alerta('Extensão do assinador: ' + ext.detalhe.charAt(0).toLowerCase() + ext.detalhe.slice(1) + '.');
    }
    if (e.acesso.liberado) ok('Este computador está liberado: qualquer usuário instala e repara pelo Laçador sem senha.');
    else if (!e.acesso.administrador) info('Para instalar, o Windows pede a senha de um administrador. O suporte pode liberar este computador uma vez, na página Acesso.');
    var faltamPac = e.pacotes.filter(function (p) { return !p.ok; }).length;
    if (faltamPac) alerta(faltamPac === 1 ? 'Falta 1 instalador dentro deste Laçador.' : 'Faltam ' + faltamPac + ' instaladores dentro deste Laçador.');
    (e.erros || []).forEach(function (x) { alerta('Não consegui ler uma parte do computador: ' + x); });
    return fr;
  }

  function paginaDiagnostico(e) {
    var f = document.createDocumentFragment();
    var c0 = cartao('resumo situacao', false);
    var frases = frasesDiagnostico(e);
    var pend = frases.filter(function (x) { return x.tipo === 'alerta' || x.tipo === 'erro'; }).length;
    c0.append(cabeca('escudo', 'Como está este computador', pend ? (pend === 1 ? 'Encontrei 1 ponto que precisa de atenção' : 'Encontrei ' + pend + ' pontos que precisam de atenção') : 'Nada errado encontrado', pend ? selo('alerta', pend === 1 ? '1 pendência' : pend + ' pendências') : selo('ok', 'Em ordem')));
    var lf = h('div', { class: 'diag-frases' });
    frases.forEach(function (x) {
      var ic = icone(x.tipo === 'ok' ? 'checkCirculo' : (x.tipo === 'info' ? 'info' : 'alerta'), 17, 2); ic.className = 'ic';
      lf.append(h('div', { class: 'diag-frase ' + x.tipo }, ic, h('span', { text: x.texto })));
    });
    c0.append(lf);
    var p0 = h('div', { class: 'cartao-pe' });
    p0.append(h('span', { class: 'resumo', text: 'Verificado às ' + String(e.coletadoEm || '').slice(11, 16) }));
    p0.append(h('button', { class: 'botao', type: 'button', text: 'Verificar de novo', onclick: function () { $('verificar').click(); } }));
    p0.append(h('button', { class: 'botao primario', type: 'button', text: 'Gerar relatório para o suporte', onclick: function () { operacao({ operacao: 'relatorio' }); } }));
    c0.append(p0);
    f.append(c0);
    f.append(h('h3', { class: 'secao-titulo', text: 'Detalhes técnicos' }));
    var g = h('div', { class: 'grade' });

    var c1 = cartao('computador windows', false);
    c1.append(cabeca('escudo', 'Este computador', e.organizacao || '', null));
    var l1 = h('div', { class: 'linhas' });
    l1.append(linha('Computador', h('span', { text: e.computador })));
    l1.append(linha('Usuário', h('span', { text: e.nomeUsuario && e.nomeUsuario !== e.usuario ? e.nomeUsuario + ' (' + e.usuario + ')' : e.usuario })));
    l1.append(linha('Windows', h('span', { text: e.windows.nome + ' ' + (e.windows.versao || '') + ' (' + (e.windows.arquitetura === 'x86' ? '32' : '64') + ' bits)' })));
    l1.append(linha('Build', h('span', { text: e.windows.build || '—' })));
    var modo = (e.acesso.liberado ? 'Liberado: instala sem senha de administrador' : 'Sem liberação: o Windows pede a permissão de administrador') + (e.demonstracao ? ' (demonstração)' : '');
    l1.append(linha('Tipo de conta', h('span', { text: e.acesso.administrador ? 'Administrador' : 'Usuário comum' })));
    l1.append(linha('Instalação', h('span', { text: modo })));
    l1.append(linha('WMIC do Windows', h('span', { text: (e.wmic && (e.wmic.x64 || e.wmic.x86)) ? 'Presente' : 'Removido pelo Windows (o Laçador corrige o assinador para não depender dele)' }), 'fraco'));
    c1.append(l1);
    g.append(c1);

    var c2 = cartao('proxy rede', false);
    c2.append(cabeca('globo', 'Rede (proxy)', 'Usado pelo SIAFI tela preta na rede da FAB', e.proxy.ok ? selo('ok', 'Configurado') : selo('', 'Diferente')));
    var l2 = h('div', { class: 'linhas' });
    l2.append(linha('Esperado na rede da FAB', h('span', { class: 'mono', text: e.proxy.esperado + (e.proxy.porta ? ':' + e.proxy.porta : '') })));
    l2.append(linha('Neste usuário', h('span', { text: e.proxy.atual }), e.proxy.ok ? '' : 'fraco'));
    c2.append(l2);
    var n2 = h('div', { class: 'notas' });
    if (!e.proxy.porta) n2.append(nota('A porta do proxy ainda não foi informada (arquivo Lacador.config.json, explicado no Manual). Com ela, o Laçador passa a aplicar o proxy com um clique.'));
    n2.append(nota('Fora da rede da FAB (em casa, por exemplo) este proxy não se aplica.'));
    c2.append(n2);
    var p2 = h('div', { class: 'cartao-pe' });
    p2.append(h('span', { class: 'resumo' }));
    p2.append(h('button', { class: 'botao', type: 'button', text: 'Abrir a configuração do Windows', onclick: function () { operacao({ operacao: 'abrir-programa', alvo: 'proxy-windows' }); } }));
    if (e.proxy.podeAplicar && !e.proxy.ok) p2.append(h('button', { class: 'botao primario', type: 'button', text: 'Aplicar o proxy', onclick: function () { operacao({ operacao: 'proxy-aplicar' }); } }));
    c2.append(p2);
    g.append(c2);

    var c3 = cartao('instaladores pacotes', false);
    var faltam = e.pacotes.filter(function (p) { return !p.ok; }).length;
    c3.append(cabeca('caixa', 'Instaladores', e.pastaPacotes, faltam ? selo('alerta', faltam + (faltam === 1 ? ' faltando' : ' faltando')) : selo('ok', 'Completos')));
    var t3 = h('div', { class: 'tabela' });
    e.pacotes.forEach(function (p) {
      t3.append(h('div', { class: 'linha' }, h('span', { class: 'rotulo mono', text: p.arquivo }), h('span', { class: 'valor' + (p.ok ? '' : ' atencao') }, h('span', { text: p.ok ? 'Presente' : (p.presente ? 'Tamanho diferente' : 'Faltando') }), p.ok ? marca('ok') : marca('x'))));
    });
    c3.append(t3);
    var p3 = h('div', { class: 'cartao-pe' });
    p3.append(h('span', { class: 'resumo' + (faltam ? ' alerta' : ''), text: faltam ? (e.acesso.executavel ? 'Escolha o TOKENS.rar e o Laçador monta o executável completo.' : 'Sem esses arquivos o Laçador não instala os itens que dependem deles.') : 'O SHA-256 de cada arquivo é conferido na hora de instalar.' }));
    if (faltam) p3.append(h('button', { class: 'botao primario', type: 'button', text: e.acesso.executavel ? 'Montar o Laçador completo' : 'Carregar do TOKENS.rar', onclick: function () { operacao({ operacao: 'abrir-programa', alvo: 'carregar-pacotes' }); } }));
    else p3.append(h('button', { class: 'botao', type: 'button', text: e.pacotesNoExecutavel ? 'Mostrar o Lacador.exe' : 'Abrir a pasta', onclick: function () { operacao({ operacao: 'abrir-programa', alvo: 'pasta-pacotes' }); } }));
    c3.append(p3);
    g.append(c3);

    var c4 = cartao('suporte relatorio historico', false);
    c4.append(cabeca('ajuda', 'Suporte', (e.suporte && e.suporte.nome ? e.suporte.nome : 'Suporte') + (e.suporte && e.suporte.contato ? ' · ' + e.suporte.contato : ''), null));
    var n4 = h('div', { class: 'notas' });
    n4.append(nota('O relatório reúne o que o suporte precisa para entender um problema. CPF e CNPJ saem ocultos.'));
    (e.erros || []).forEach(function (x) { n4.append(nota('Falha ao ler: ' + x, true)); });
    c4.append(n4);
    var l4 = h('div', { class: 'tabela' });
    if (S.historico === null) l4.append(h('div', { class: 'linha' }, h('span', { class: 'rotulo', text: 'Carregando o histórico...' })));
    else if (!S.historico.length) l4.append(h('div', { class: 'linha' }, h('span', { class: 'rotulo', text: 'Nenhuma instalação ou reparo feito por este usuário ainda.' })));
    else S.historico.slice(0, 8).forEach(function (r) {
      var quando = String(r.quando || '').replace('T', ' ').slice(0, 16);
      var nomes = (r.itens || []).map(function (id) { return e.itens[id] ? e.itens[id].nome : id; }).join(', ');
      var feito = r.acao === 'desinstalar' ? 'Desinstalado' : (r.acao === 'reparar' ? 'Reparado' : 'Instalado');
      l4.append(h('div', { class: 'linha' }, h('span', { class: 'rotulo', text: quando + ' · ' + nomes }), h('span', { class: 'valor' + (r.resultado === 'concluido' ? '' : ' atencao') }, h('span', { text: r.resultado === 'concluido' ? feito : 'Com pendência' }), r.resultado === 'concluido' ? marca('ok') : marca('x'))));
    });
    c4.append(l4);
    var p4 = h('div', { class: 'cartao-pe' });
    p4.append(h('span', { class: 'resumo' }));
    p4.append(h('button', { class: 'botao', type: 'button', text: 'Manual', onclick: function () { operacao({ operacao: 'abrir-programa', alvo: 'manual' }); } }));
    p4.append(h('button', { class: 'botao', type: 'button', text: 'Registros', onclick: function () { operacao({ operacao: 'abrir-programa', alvo: 'pasta-registros' }); } }));
    p4.append(h('button', { class: 'botao', type: 'button', text: 'Diagnóstico do assinador', onclick: function () { operacao({ operacao: 'relatorio-assinador' }); } }));
    p4.append(h('button', { class: 'botao primario', type: 'button', text: 'Gerar relatório', onclick: function () { operacao({ operacao: 'relatorio' }); } }));
    c4.append(p4);
    g.append(c4);

    f.append(g);
    return f;
  }

  /* ---------- desenho geral ---------- */
  function desenhar() {
    var e = S.estado;
    desenharNav();
    var pg = PAGINAS.filter(function (p) { return p.id === S.pagina; })[0] || PAGINAS[0];
    $('titulo').textContent = (pg.id === 'inicio' && e) ? saudacao() + ', ' + nome(e) : pg.nome;
    $('subtitulo').textContent = subtitulo(pg.id, e);
    var alvo = $('conteudo');
    var rolagem = alvo.scrollTop;
    alvo.textContent = '';
    if (!e) return;
    $('demo').hidden = !e.demonstracao;
    $('versao').textContent = 'v' + e.versao;
    if (e.credito) document.querySelector('.credito span').textContent = e.credito;
    var pc = $('pc');
    pc.textContent = '';
    pc.append(h('div', { class: 'pc-rotulo', text: 'ESTE COMPUTADOR' }), h('div', { class: 'pc-nome', text: e.computador || '—' }),
      h('div', { class: 'pc-linha', text: (e.windows.nome || 'Windows').replace('Microsoft ', '') + (e.windows.versao ? ' · ' + e.windows.versao : '') }),
      h('div', { class: 'pc-estado' + (S.fase === 'verificando' ? ' ocupado' : ''), id: 'pc-estado' }, h('span', { class: 'ponto', style: 'width:7px;height:7px;border-radius:4px;background:' + (S.fase === 'verificando' ? '#98A2B3' : '#1E8E3E') }), S.fase === 'verificando' ? 'Verificando...' : 'Verificado às ' + String(e.coletadoEm || '').slice(11, 16)));
    var conteudo;
    if (pg.id === 'inicio') conteudo = paginaInicio(e);
    else if (pg.id === 'sistemas') conteudo = paginaSistemas(e);
    else if (pg.id === 'tokens') conteudo = paginaTokens(e);
    else if (pg.id === 'programas') conteudo = paginaProgramas(e);
    else if (pg.id === 'certificados') conteudo = paginaCertificados(e);
    else if (pg.id === 'tutoriais') conteudo = paginaTutoriais(e);
    else if (pg.id === 'acesso') conteudo = paginaAcesso(e);
    else conteudo = paginaDiagnostico(e);
    alvo.append(conteudo);
    filtrar();
    alvo.scrollTop = rolagem;
  }

  function filtrar() {
    if (S.pagina === 'tutoriais') return;
    fecharMenu();
    var q = semAcento(S.busca);
    Array.prototype.forEach.call(document.querySelectorAll('#conteudo [data-busca]'), function (el) {
      if (el.classList.contains('aviso')) return;
      el.hidden = !!q && el.dataset.busca.indexOf(q) < 0;
    });
  }

  /* ---------- folhas: confirmar, escolher token, andamento ---------- */
  function abrirFolha(conteudo, tipo) {
    var f = $('folha');
    f.textContent = '';
    f.append(conteudo);
    S.folha = tipo;
    $('folha-fundo').hidden = false;
    var b = f.querySelector('button.primario') || f.querySelector('button');
    if (b) b.focus();
  }
  function fecharFolha() { $('folha-fundo').hidden = true; S.folha = null; }

  function prepararSistema(s, e) {
    var corpo = { acao: s.faltando.length || s.escolherToken ? 'instalar' : 'reparar', sistemas: [s.id] };
    var previstos = s.faltando.concat(s.reparar);
    var titulo = (corpo.acao === 'instalar' ? 'Preparar: ' : 'Reparar: ') + s.nome;
    if (!s.escolherToken) { confirmarAcao(corpo, titulo, previstos, e); return; }
    var fr = document.createDocumentFragment();
    fr.append(h('h2', { id: 'folha-titulo', text: 'Qual é o seu token?' }), h('p', { class: 'sub', text: 'Nenhum driver de token está instalado ainda. Escolha o modelo para o Laçador instalar o driver certo.' }));
    var esc = h('div', { class: 'escolhas' });
    function opcao(id, nome, desc, itens) {
      return h('button', { class: 'escolha', type: 'button', onclick: function () {
        corpo.token = id;
        var todos = itens.concat(previstos.filter(function (x) { return itens.indexOf(x) < 0; }));
        confirmarAcao(corpo, titulo, todos, e);
      } }, h('span', { class: 'ic' }, icone('token', 22, 1.6)), h('span', { class: 'tx' }, h('strong', { text: nome }), h('span', { text: desc })));
    }
    var todosItens = [];
    e.tokens.forEach(function (t) { esc.append(opcao(t.id, t.nome, t.descricao, t.itens)); todosItens = todosItens.concat(t.itens); });
    esc.append(opcao('todos', 'Instalar os dois', 'Para computador usado com mais de um modelo de token', todosItens));
    fr.append(esc);
    fr.append(h('div', { class: 'folha-pe' }, h('button', { class: 'botao', type: 'button', text: 'Cancelar', onclick: fecharFolha })));
    abrirFolha(fr, 'escolha');
  }

  function confirmarAcao(corpo, titulo, idsPrevistos, e) {
    var fr = document.createDocumentFragment();
    fr.append(h('h2', { id: 'folha-titulo', text: titulo }));
    var via = e.demonstracao ? 'Modo demonstração: nada será instalado de verdade.'
      : (e.acesso.liberado ? 'O Laçador faz tudo sozinho. Não é preciso senha de administrador.'
        : (e.acesso.administrador ? 'O Windows vai pedir a sua confirmação. Clique em “Sim” para autorizar.'
          : 'O Windows vai pedir a senha de um administrador. Se você não tem, peça ao suporte para liberar este computador na página Acesso.'));
    fr.append(h('p', { class: 'sub', text: via }));
    var lista = h('div', { class: 'folha-lista' });
    idsPrevistos.forEach(function (id) {
      var it = e.itens[id]; if (!it) return;
      var tx = h('span', { class: 'tx' }, h('strong', { text: it.nome }));
      var oque;
      if (corpo.acao === 'desinstalar') oque = it.id === 'extensao-firefox' ? 'Tirar a extensão do Firefox (na próxima vez que ele abrir)' : 'Remover do computador' + (it.versaoInstalada ? ' (versão ' + it.versaoInstalada + ')' : '');
      else if (it.id === 'firefox-esr' && corpo.acao === 'instalar' && it.estado !== 'ausente') oque = 'Instalar o Firefox ESR ' + it.versao + ' (reserva) ao lado do Developer Edition';
      else if (it.id === 'firefox-esr' && it.estado === 'ausente') oque = 'Instalar o Firefox ESR ' + it.versao;
      else if (it.estado === 'ausente') oque = (it.categoria === 'ambiente' ? 'Ligar e configurar' : 'Instalar' + (it.versao && !/^java/.test(it.id) ? ' a versão ' + it.versao : ''));
      else if (it.estado === 'atencao') oque = (it.reinstalar ? 'Reinstalar por cima: ' : 'Corrigir: ') + it.detalhe;
      else if (corpo.acao === 'reparar' && it.podeReparar && it.temPacotes && it.id !== 'extensao-firefox') oque = 'Reinstalar por cima e refazer a configuração';
      else oque = 'Conferir e refazer a configuração';
      tx.append(h('span', { text: oque }));
      if (it.estado !== 'ok' && corpo.acao !== 'desinstalar') it.avisos.forEach(function (a) { tx.append(h('span', { text: a })); });
      lista.append(h('div', { class: 'folha-item' }, h('span', { class: 'est' }, (function () { var i = icone('ponto', 16, 2); i.style.color = '#98A2B3'; return i; })()), tx));
    });
    fr.append(lista);
    var erro = h('p', { class: 'sub', style: 'color:#A1260D', hidden: true });
    fr.append(erro);
    if (corpo.acao === 'desinstalar') fr.append(h('p', { class: 'sub', text: 'O que depende deste programa deixa de funcionar até ele ser instalado de novo.' }));
    var ir = h('button', { class: corpo.acao === 'desinstalar' ? 'botao perigo' : 'botao primario', type: 'button', text: corpo.acao === 'desinstalar' ? 'Desinstalar' : 'Continuar', onclick: function () {
      ir.disabled = true; ir.textContent = 'Iniciando...';
      api('/api/acao', corpo).then(function (r) {
        if (!r.ok) { erro.textContent = r.mensagem || 'Não foi possível iniciar.'; erro.hidden = false; ir.disabled = false; ir.textContent = 'Tentar de novo'; return; }
        S.acaoFechada = null;
        S.acao = { id: r.id, acao: corpo.acao, estado: 'executando', passos: idsPrevistos.map(function (id) { return { item: id, nome: e.itens[id] ? e.itens[id].nome : id, estado: 'pendente', mensagens: [] }; }), via: r.via };
        desenharAndamento();
      }).catch(function () { erro.textContent = 'O Laçador não respondeu.'; erro.hidden = false; ir.disabled = false; ir.textContent = 'Tentar de novo'; });
    } });
    fr.append(h('div', { class: 'folha-pe' }, h('button', { class: 'botao', type: 'button', text: 'Cancelar', onclick: fecharFolha }), ir));
    abrirFolha(fr, 'confirmar');
  }

  function desenharAndamento() {
    var a = S.acao;
    if (!a) return;
    var fim = a.estado !== 'executando';
    var fr = document.createDocumentFragment();
    var tira = a.acao === 'desinstalar';
    var titulo = !fim ? (tira ? 'Desinstalando...' : 'Trabalhando...') : (a.estado === 'concluido' ? (tira ? 'Desinstalado' : 'Pronto') : 'Terminou com pendências');
    fr.append(h('h2', { id: 'folha-titulo', text: titulo }));
    var sub = !fim ? (a.via === 'uac' ? 'Se a janela de administrador do Windows aparecer, clique em “Sim”. Não feche o Laçador.' : 'Isso pode levar alguns minutos. Não desligue o computador.')
      : (a.estado === 'concluido' ? (tira ? 'O programa foi removido do computador.' : 'Tudo foi instalado e conferido.') : (a.mensagem || 'Veja abaixo o que ficou pendente. Você pode tentar de novo ou gerar o relatório para o suporte na página Diagnóstico.'));
    fr.append(h('p', { class: 'sub', text: sub }));
    var lista = h('div', { class: 'folha-lista' });
    (a.passos || []).forEach(function (p) {
      var est = h('span', { class: 'est' });
      if (p.estado === 'executando') est.append(h('span', { class: 'gira', role: 'img', 'aria-label': 'em andamento' }));
      else if (p.estado === 'ok') { var i1 = icone('checkCirculo', 20, 2); i1.style.color = '#1E8E3E'; est.append(i1); }
      else if (p.estado === 'erro') { var i2 = icone('xis', 20, 2); i2.style.color = '#C4360F'; est.append(i2); }
      else { var i3 = icone('ponto', 16, 2); i3.style.color = '#98A2B3'; est.append(i3); }
      var tx = h('span', { class: 'tx' }, h('strong', { text: p.nome }));
      var msgs = p.mensagens || [];
      if (msgs.length) tx.append(h('span', { class: p.estado === 'erro' ? 'erro' : '', text: String(msgs[msgs.length - 1]).replace(/^ERRO: /, '') }));
      lista.append(h('div', { class: 'folha-item' }, est, tx));
    });
    fr.append(lista);
    if (fim && a.reiniciar) fr.append(h('p', { class: 'sub', text: 'Um dos instaladores pediu para reiniciar o computador. Reinicie para concluir.' }));
    if (fim) fr.append(h('div', { class: 'folha-pe' }, h('button', { class: 'botao primario', type: 'button', text: 'Fechar', onclick: function () { S.acaoFechada = a.id; S.acao = null; fecharFolha(); api('/api/acao/fechar', {}).catch(function () {}); } })));
    abrirFolha(fr, 'andamento');
  }

  /* ---------- ciclo de atualização ---------- */
  function aplicar(r) {
    var faseAntes = S.fase;
    S.fase = r.fase;
    if (!S.appVisivel) {
      var pct = Math.max(4, Math.min(100, r.percentual || 0));
      $('inicio-cheio').style.width = pct + '%';
      $('inicio-barra').setAttribute('aria-valuenow', String(pct));
      $('inicio-etapa').textContent = r.fase === 'pronto' ? (r.estado ? 'Abrindo...' : 'Não foi possível verificar este computador') : (r.etapa || 'Carregando o sistema...');
      if (r.versao) $('inicio-versao').textContent = 'v' + r.versao;
      if (r.fase === 'pronto' && !r.estado) { $('inicio').classList.add('erro'); if (r.erro) $('inicio-etapa').textContent = r.erro; }
    }
    var mudou = false;
    if (r.estado && r.rodada !== S.rodada) { S.estado = r.estado; S.rodada = r.rodada; S.ultimaVerificacao = Date.now(); mudou = true; }
    if (NATIVA && !S.appVisivel && r.fase === 'pronto' && !r.estado) {
      // A verificação falhou: mostra o erro na abertura da própria página e libera a do Lacador.exe.
      NATIVA = false;
      document.documentElement.classList.remove('abertura-nativa');
      api('/api/pronto', {}).catch(function () {});
    }
    if (S.estado && !S.appVisivel && r.fase === 'pronto' && NATIVA) {
      S.appVisivel = true;
      $('app').hidden = false;
      $('inicio').hidden = true;
      desenhar();
      // Avisa o Lacador.exe só depois que a tela foi desenhada: aí a abertura dele some.
      requestAnimationFrame(function () { requestAnimationFrame(function () { api('/api/pronto', {}).catch(function () {}); }); });
    } else if (S.estado && !S.appVisivel && r.fase === 'pronto') {
      S.appVisivel = true;
      var espera = Math.max(0, 1500 - (Date.now() - S.abertoEm));
      setTimeout(function () {
        $('app').hidden = false;
        $('inicio').classList.add('saindo');
        setTimeout(function () { $('inicio').hidden = true; }, 600);
        desenhar();
      }, espera);
    } else if (S.appVisivel && !$('app').hidden && (mudou || faseAntes !== S.fase)) {
      desenhar();
    }
    var bt = $('verificar');
    bt.disabled = (r.fase === 'verificando');
    $('verificar-texto').textContent = r.fase === 'verificando' ? 'Verificando...' : 'Verificar tudo';

    if (!r.acesso) S.acessoIgnorar = false;
    else if (!S.acessoIgnorar) {
      var antesAcesso = S.acesso ? JSON.stringify(S.acesso) : '';
      S.acesso = r.acesso;
      if ((JSON.stringify(S.acesso) !== antesAcesso || S.folha !== 'acesso') && (S.folha === 'acesso' || S.folha === null || S.folha === 'confirmar')) desenharAcesso();
    }

    if (r.acao && r.acao.id !== S.acaoFechada) {
      var antes = S.acao ? JSON.stringify(S.acao) : '';
      S.acao = r.acao;
      if (JSON.stringify(S.acao) !== antes || S.folha !== 'andamento') { if (S.folha === 'andamento' || S.folha === null || S.folha === 'confirmar') desenharAndamento(); }
    }
  }

  function ciclo() {
    var espera = 3000;
    api('/api/estado').then(function (r) {
      S.falhas = 0; S.respostaRuim = '';
      if (S.desconectado) { S.desconectado = false; fecharFolha(); }
      aplicar(r);
      if (r.fase === 'verificando' || (r.acao && r.acao.estado === 'executando') || (r.acesso && r.acesso.estado === 'executando')) espera = 600;
      // verificação automática: token conectado ou removido aparece sozinho
      if (r.fase === 'pronto' && S.appVisivel && !S.folha && document.visibilityState === 'visible' && Date.now() - S.ultimaVerificacao > 45000) {
        S.ultimaVerificacao = Date.now();
        api('/api/verificar', {}).catch(function () {});
      }
    }).catch(function () {
      S.falhas++;
      espera = 1500;
      if (S.falhas >= 4 && !S.desconectado) {
        S.desconectado = true;
        var fr = document.createDocumentFragment();
        var ruim = S.respostaRuim;
        fr.append(h('h2', { id: 'folha-titulo', text: ruim ? 'O Laçador respondeu algo inesperado' : 'O Laçador foi encerrado' }),
          h('p', { class: 'sub', text: ruim ? 'Mande esta tela para o suporte. Resposta recebida: ' + ruim : 'Feche esta janela e abra o Laçador de novo.' }));
        abrirFolha(fr, 'desconectado');
        if (NATIVA) { NATIVA = false; document.documentElement.classList.remove('abertura-nativa'); }
        if (!S.appVisivel) { $('inicio').classList.add('erro'); $('inicio-etapa').textContent = ruim ? 'Resposta inesperada do Laçador. Avise o suporte.' : 'O Laçador foi encerrado. Abra de novo.'; }
      }
    }).then(function () { setTimeout(ciclo, espera); });
  }

  /* ---------- efeitos: luz líquida e pílula do menu ---------- */
  var semMovimento = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var estadosLuz = new WeakMap(), acesa = null, quadroPedido = false;
  function pintarLuz(el, st) {
    var camada = el.querySelector(':scope > .luz');
    if (!camada) return;
    var lateral = el.dataset.luz === 'lateral';
    var nucleo = lateral ? 'rgba(255,255,255,0.5)' : 'rgba(58,123,213,0.10)';
    var nucleoFim = lateral ? 'rgba(255,255,255,0)' : 'rgba(58,123,213,0)';
    var halo = 'rgba(58,123,213,' + (lateral ? 0.13 : 0.07) + ')';
    camada.style.background = 'radial-gradient(' + (lateral ? 170 : 230) + 'px circle at ' + st.ax.toFixed(1) + 'px ' + st.ay.toFixed(1) + 'px, ' + nucleo + ', ' + nucleoFim + ' 70%), ' +
      'radial-gradient(' + (lateral ? 420 : 540) + 'px circle at ' + st.bx.toFixed(1) + 'px ' + st.by.toFixed(1) + 'px, ' + halo + ', rgba(58,123,213,0) 70%)';
  }
  function quadro() {
    quadroPedido = false;
    if (!acesa || !document.contains(acesa)) return;
    var st = estadosLuz.get(acesa);
    if (!st) return;
    st.ax += (st.tx - st.ax) * 0.14; st.ay += (st.ty - st.ay) * 0.14;
    st.bx += (st.tx - st.bx) * 0.055; st.by += (st.ty - st.by) * 0.055;
    pintarLuz(acesa, st);
    if (Math.abs(st.tx - st.bx) + Math.abs(st.ty - st.by) > 0.6) { quadroPedido = true; requestAnimationFrame(quadro); }
  }
  if (!semMovimento) {
    document.addEventListener('mousemove', function (ev) {
      var el = ev.target && ev.target.closest ? ev.target.closest('[data-luz]') : null;
      if (el !== acesa) { if (acesa) acesa.classList.remove('acesa'); acesa = el; if (el) el.classList.add('acesa'); }
      if (!el) return;
      var r = el.getBoundingClientRect(), x = ev.clientX - r.left, y = ev.clientY - r.top;
      var st = estadosLuz.get(el);
      if (!st) { st = { ax: x, ay: y, bx: x, by: y, tx: x, ty: y }; estadosLuz.set(el, st); }
      st.tx = x; st.ty = y;
      if (!quadroPedido) { quadroPedido = true; requestAnimationFrame(quadro); }
    });
    document.addEventListener('mouseleave', function () { if (acesa) acesa.classList.remove('acesa'); acesa = null; });
  }
  var lateral = $('lateral');
  lateral.dataset.luz = 'lateral';
  lateral.addEventListener('mouseover', function (ev) {
    var item = ev.target.closest ? ev.target.closest('.nav-item') : null;
    var p = $('pilula');
    if (!item) return;
    var rl = lateral.getBoundingClientRect(), ri = item.getBoundingClientRect();
    p.style.top = (ri.top - rl.top) + 'px';
    p.style.height = ri.height + 'px';
    p.style.opacity = '1';
  });
  lateral.addEventListener('mouseleave', function () { $('pilula').style.opacity = '0'; });

  /* ---------- eventos gerais ---------- */
  $('verificar').addEventListener('click', function () { S.ultimaVerificacao = Date.now(); api('/api/verificar', {}).catch(function () {}); $('verificar').disabled = true; $('verificar-texto').textContent = 'Verificando...'; });
  $('busca').addEventListener('input', function (ev) { S.busca = ev.target.value; if (S.pagina === 'tutoriais') desenhar(); else filtrar(); });
  $('folha-fundo').addEventListener('click', function (ev) { if (ev.target === $('folha-fundo') && (S.folha === 'confirmar' || S.folha === 'escolha' || S.folha === 'assistente')) fecharFolha(); });
  document.addEventListener('keydown', function (ev) { if (ev.key === 'Escape' && (S.folha === 'confirmar' || S.folha === 'escolha' || S.folha === 'assistente')) fecharFolha(); });
  window.addEventListener('pagehide', function () { try { navigator.sendBeacon('/api/saindo?k=' + encodeURIComponent(CHAVE)); } catch (e) { /* sem problema */ } });

  api('/api/tutoriais').then(function (r) { S.tutoriais = r.tutoriais || []; if (S.appVisivel && !$('app').hidden) desenhar(); }).catch(function () {});
  ciclo();
})();
