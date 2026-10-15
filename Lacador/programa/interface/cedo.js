/* Laçador - roda antes de a página aparecer. Quando o Lacador.exe já mostra a própria tela de abertura,
   a página não repete a abertura dela. */
(function () {
  try {
    if (/[?&]a=1(&|$)/.test(location.search)) sessionStorage.setItem('lacador-abertura', '1');
    if (sessionStorage.getItem('lacador-abertura') === '1') document.documentElement.classList.add('abertura-nativa');
  } catch (e) { /* sem problema */ }
})();
