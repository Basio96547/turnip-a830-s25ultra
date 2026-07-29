'use strict';
// preload آمن: لا يُعرّض أي واجهة Node للصفحة.
// وظيفته الوحيدة وسم الصفحة بأنها تعمل داخل تطبيق سطح المكتب (مفيد للتشخيص)
// وتحسين سلوك اللمس على شاشة الجوال.

window.addEventListener('DOMContentLoaded', () => {
  try {
    document.documentElement.dataset.s25App = 'claude-pc';
    const style = document.createElement('style');
    style.textContent = `
      /* أشرطة تمرير أعرض قليلاً لتسهيل السحب بالإصبع */
      ::-webkit-scrollbar { width: 12px; height: 12px; }
      ::-webkit-scrollbar-thumb { border-radius: 6px; background: rgba(128,128,128,.55); }
      ::-webkit-scrollbar-thumb:hover { background: rgba(128,128,128,.8); }
    `;
    document.head.appendChild(style);
  } catch (e) {
    console.warn('[claude-pc] preload:', e.message);
  }
});
