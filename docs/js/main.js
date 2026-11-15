// 言語メニューと季節タブ。
// 各言語のページは build.pl が docs/<言語>/index.html として生成します。
(function () {
  var STORAGE_KEY = "irodori-lang";
  var select = document.getElementById("lang-select");

  // 言語メニュー: 選んだ言語のページへ移動し、次回のために記憶する
  select.addEventListener("change", function () {
    try { localStorage.setItem(STORAGE_KEY, select.value); } catch (e) {}
    location.href = "../" + select.value.toLowerCase() + "/" + location.hash;
  });
  // ブラウザの「戻る」で戻ってきたとき、メニューの表示を今のページの言語に戻す
  window.addEventListener("pageshow", function () {
    select.value = document.documentElement.lang;
  });

  // 季節タブ
  var section = document.getElementById("seasons");
  var tabs = Array.prototype.slice.call(section.querySelectorAll('[role="tab"]'));

  function selectTab(tab, focus) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute("aria-selected", on ? "true" : "false");
      t.tabIndex = on ? 0 : -1;
      document.getElementById(t.getAttribute("aria-controls")).hidden = !on;
    });
    section.dataset.season = tab.dataset.season;
    if (focus) tab.focus();
  }

  tabs.forEach(function (tab, i) {
    tab.addEventListener("click", function () { selectTab(tab, false); });
    tab.addEventListener("keydown", function (e) {
      var step = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (!step) return;
      e.preventDefault();
      selectTab(tabs[(i + step + tabs.length) % tabs.length], true);
    });
  });
})();
