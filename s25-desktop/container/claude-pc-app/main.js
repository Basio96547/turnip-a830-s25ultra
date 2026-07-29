'use strict';
// ═══════════════════════════════════════════════════════════════════════
//  Claude PC — غلاف تطبيق سطح مكتب لـ claude.ai
//
//  نافذة تطبيق مستقلة (بدون واجهة متصفح): أيقونة خاصة، قائمة، اختصارات
//  لوحة مفاتيح، جلسة دخول محفوظة، ووضع ملء الشاشة على شاشة الجوال.
//  الرسوميات تمر عبر ANGLE/Vulkan أي أن تعريف Turnip (A830) يُستخدم مباشرة.
//
//  متغيرات البيئة:
//    S25_CLAUDE_URL       الرابط الافتراضي (افتراضي https://claude.ai/)
//    S25_GPU_ACTIVE       turnip | software  (يضبطه /opt/s25/etc/env.sh)
//    S25_SCALE            معامل تكبير الواجهة
//    S25_APP_FULLSCREEN   1 = ابدأ بملء الشاشة
// ═══════════════════════════════════════════════════════════════════════

const { app, BrowserWindow, Menu, shell, session, dialog } = require('electron');
const path = require('node:path');
const fs = require('node:fs');

const HOME_URL = process.env.S25_CLAUDE_URL || 'https://claude.ai/';
const CHROME_UA =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/141.0.0.0 Safari/537.36';

// مضيفو تسجيل الدخول الخارجيون المسموح بهم داخل التطبيق.
// نطاقات claude.ai / claude.com / anthropic.com تُطابَق بالتعبير في isInternal.
const AUTH_HOSTS = new Set([
  'accounts.google.com',
  'accounts.youtube.com',
  'appleid.apple.com',
  'login.microsoftonline.com',
]);

// ── رايات Chromium: نفس منطق chrome-pc ─────────────────────────────────
const gpuMode = process.env.S25_GPU_ACTIVE || 'software';
app.commandLine.appendSwitch('ozone-platform', 'x11');
app.commandLine.appendSwitch('no-sandbox'); // proot لا يوفر user namespaces
app.commandLine.appendSwitch('disable-dev-shm-usage');
app.commandLine.appendSwitch('password-store', 'basic');
if (gpuMode === 'turnip') {
  app.commandLine.appendSwitch('use-gl', 'angle');
  app.commandLine.appendSwitch('use-angle', 'vulkan');
  app.commandLine.appendSwitch('ignore-gpu-blocklist');
  app.commandLine.appendSwitch('enable-gpu-rasterization');
  app.commandLine.appendSwitch('enable-features', 'Vulkan,VulkanFromANGLE,DefaultANGLEVulkan');
} else {
  app.commandLine.appendSwitch('disable-gpu');
}
if (process.env.S25_SCALE) {
  app.commandLine.appendSwitch('force-device-scale-factor', process.env.S25_SCALE);
}

// ── حفظ أبعاد النافذة بين الجلسات ──────────────────────────────────────
function stateFile() {
  return path.join(app.getPath('userData'), 'window-state.json');
}

function loadState() {
  try {
    const s = JSON.parse(fs.readFileSync(stateFile(), 'utf8'));
    if (typeof s.width === 'number' && typeof s.height === 'number') return s;
  } catch {
    /* أول تشغيل أو ملف تالف — نتجاهل */
  }
  return { width: 1280, height: 800, maximized: true };
}

function saveState(win) {
  if (!win || win.isDestroyed()) return;
  try {
    const b = win.getNormalBounds ? win.getNormalBounds() : win.getBounds();
    fs.mkdirSync(app.getPath('userData'), { recursive: true });
    fs.writeFileSync(
      stateFile(),
      JSON.stringify({
        x: b.x, y: b.y, width: b.width, height: b.height,
        maximized: win.isMaximized(),
      })
    );
  } catch (e) {
    console.warn('[claude-pc] تعذر حفظ حالة النافذة:', e.message);
  }
}

function hostOf(url) {
  try { return new URL(url).host.toLowerCase(); } catch { return ''; }
}

function isInternal(url) {
  const h = hostOf(url);
  if (!h) return false;
  if (AUTH_HOSTS.has(h)) return true;
  // نطاقات claude.ai / claude.com / anthropic.com وفروعها فقط
  return /(^|\.)((claude\.(ai|com))|anthropic\.com)$/.test(h);
}

let mainWindow = null;

function buildMenu(win) {
  const template = [
    {
      label: 'Claude',
      submenu: [
        {
          label: 'الصفحة الرئيسية',
          accelerator: 'CmdOrCtrl+H',
          click: () => win.loadURL(HOME_URL),
        },
        {
          label: 'محادثة جديدة',
          accelerator: 'CmdOrCtrl+N',
          click: () => win.loadURL(new URL('/new', HOME_URL).toString()),
        },
        { type: 'separator' },
        {
          label: 'فتح في كروم',
          click: () => shell.openExternal(win.webContents.getURL()),
        },
        { type: 'separator' },
        { role: 'quit', label: 'إغلاق التطبيق', accelerator: 'CmdOrCtrl+Q' },
      ],
    },
    {
      label: 'تحرير',
      submenu: [
        { role: 'undo', label: 'تراجع' },
        { role: 'redo', label: 'إعادة' },
        { type: 'separator' },
        { role: 'cut', label: 'قص' },
        { role: 'copy', label: 'نسخ' },
        { role: 'paste', label: 'لصق' },
        { role: 'selectAll', label: 'تحديد الكل' },
      ],
    },
    {
      label: 'عرض',
      submenu: [
        { role: 'reload', label: 'تحديث', accelerator: 'CmdOrCtrl+R' },
        { role: 'forceReload', label: 'تحديث كامل' },
        { type: 'separator' },
        { role: 'zoomIn', label: 'تكبير', accelerator: 'CmdOrCtrl+Plus' },
        { role: 'zoomOut', label: 'تصغير', accelerator: 'CmdOrCtrl+-' },
        { role: 'resetZoom', label: 'حجم أصلي', accelerator: 'CmdOrCtrl+0' },
        { type: 'separator' },
        { role: 'togglefullscreen', label: 'ملء الشاشة', accelerator: 'F11' },
        { role: 'toggleDevTools', label: 'أدوات المطور', accelerator: 'F12' },
      ],
    },
    {
      label: 'مساعدة',
      submenu: [
        {
          label: 'معلومات الرسوميات (chrome://gpu)',
          click: () => win.loadURL('chrome://gpu'),
        },
        {
          label: 'عن Claude PC',
          click: () => {
            dialog.showMessageBox(win, {
              type: 'info',
              title: 'عن Claude PC',
              message: 'Claude PC',
              detail:
                `غلاف سطح مكتب لـ ${HOME_URL}\n` +
                `Electron ${process.versions.electron} · Chromium ${process.versions.chrome}\n` +
                `الرسوميات: ${gpuMode === 'turnip' ? 'Turnip/Vulkan (Adreno 830)' : 'المعالج (software)'}\n\n` +
                'هذا غلاف مجتمعي وليس إصداراً رسمياً من Anthropic.',
              buttons: ['حسناً'],
            });
          },
        },
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function createWindow() {
  const state = loadState();

  const win = new BrowserWindow({
    x: state.x,
    y: state.y,
    width: state.width,
    height: state.height,
    minWidth: 420,
    minHeight: 480,
    title: 'Claude PC',
    backgroundColor: '#1f1e1d',
    autoHideMenuBar: false,
    icon: '/usr/share/icons/hicolor/scalable/apps/claude-pc.svg',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false, // proot: لا يوجد user namespace
      spellcheck: true,
      backgroundThrottling: false,
    },
  });

  buildMenu(win);

  if (state.maximized) win.maximize();
  if (process.env.S25_APP_FULLSCREEN === '1') win.setFullScreen(true);

  // واجهة سطح مكتب حقيقية: نُعرّف أنفسنا كـ Chrome على لينكس
  win.webContents.setUserAgent(CHROME_UA);

  // النوافذ المنبثقة: تسجيل الدخول يبقى داخل التطبيق، وغيره يذهب لكروم
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (isInternal(url)) {
      return {
        action: 'allow',
        overrideBrowserWindowOptions: {
          width: 520,
          height: 700,
          autoHideMenuBar: true,
          webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: false },
        },
      };
    }
    shell.openExternal(url).catch(() => {});
    return { action: 'deny' };
  });

  win.webContents.on('will-navigate', (event, url) => {
    if (!isInternal(url) && !url.startsWith('chrome://')) {
      event.preventDefault();
      shell.openExternal(url).catch(() => {});
    }
  });

  win.webContents.on('did-fail-load', (_e, code, desc, url) => {
    if (code === -3) return; // إلغاء عادي
    console.warn(`[claude-pc] فشل تحميل ${url}: ${desc} (${code})`);
  });

  win.on('close', () => saveState(win));

  win.loadURL(HOME_URL, { userAgent: CHROME_UA });
  return win;
}

// نسخة واحدة فقط من التطبيق
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(() => {
    try {
      session.defaultSession.setUserAgent(CHROME_UA);
      session.defaultSession.setSpellCheckerLanguages(['en-US']);
    } catch (e) {
      console.warn('[claude-pc] تهيئة الجلسة:', e.message);
    }

    // صلاحيات: نسمح بالميكروفون/الحافظة فقط
    session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
      const allowed = ['media', 'clipboard-read', 'clipboard-sanitized-write', 'notifications'];
      callback(allowed.includes(permission));
    });

    mainWindow = createWindow();

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) mainWindow = createWindow();
    });
  });

  app.on('window-all-closed', () => app.quit());
}
