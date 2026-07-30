package com.s25.desktop.launcher;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.TextView;
import android.widget.Toast;

/**
 * مُشغّل نظام S25 Desktop.
 *
 * التطبيق لا يحتوي محاكياً بنفسه — وظيفته أن يشغّل بضغطة واحدة سلسلة العمل
 * الكاملة: تنفيذ الأمر {@code s25-desktop <mode>} داخل Termux عبر خدمة
 * RUN_COMMAND، ثم الانتقال تلقائياً إلى شاشة العرض (تطبيق Termux:X11).
 */
public class MainActivity extends Activity {

    private static final String TERMUX_PKG = "com.termux";
    private static final String TERMUX_X11_PKG = "com.termux.x11";
    private static final String RUN_COMMAND_SERVICE = "com.termux.app.RunCommandService";
    private static final String ACTION_RUN_COMMAND = "com.termux.RUN_COMMAND";
    private static final String EXTRA_PATH = "com.termux.RUN_COMMAND_PATH";
    private static final String EXTRA_ARGS = "com.termux.RUN_COMMAND_ARGUMENTS";
    private static final String EXTRA_WORKDIR = "com.termux.RUN_COMMAND_WORKDIR";
    private static final String EXTRA_BACKGROUND = "com.termux.RUN_COMMAND_BACKGROUND";
    private static final String EXTRA_SESSION_ACTION = "com.termux.RUN_COMMAND_SESSION_ACTION";

    private static final String TERMUX_BIN = "/data/data/com.termux/files/usr/bin/";
    private static final String TERMUX_HOME = "/data/data/com.termux/files/home";

    /** مهلة قبل الانتقال لشاشة العرض — تكفي لبدء خادم X. */
    private static final long SWITCH_DELAY_MS = 3500L;

    private static final String ENABLE_CMD =
            "echo 'allow-external-apps=true' >> ~/.termux/termux.properties && termux-reload-settings";

    private static final String REPO_URL = "https://github.com/basio96547/turnip-a830-s25ultra";

    /** أمر التثبيت الكامل: يستنسخ المستودع إن لزم ثم يشغّل المُثبّت. */
    private static final String INSTALL_CMD =
            "cd \"$HOME\" && pkg install -y git && "
            + "{ [ -d turnip-a830-s25ultra ] || git clone " + REPO_URL + "; } && "
            + "bash turnip-a830-s25ultra/s25-desktop/install.sh";

    private static final String PREFS = "s25";
    private static final String KEY_INSTALL_STARTED = "install_started";

    private static final String TERMUX_DOWNLOAD = "https://f-droid.org/packages/com.termux/";
    private static final String X11_DOWNLOAD = "https://github.com/termux/termux-x11/releases";

    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView status;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        status = findViewById(R.id.status);

        bind(R.id.btn_install, new Runnable() {
            @Override public void run() { startInstall(); }
        });
        bind(R.id.btn_win_claude, new Runnable() {
            @Override public void run() { launchMode("win-claude"); }
        });
        bind(R.id.btn_win_chrome, new Runnable() {
            @Override public void run() { launchMode("win-chrome"); }
        });
        bind(R.id.btn_desktop, new Runnable() {
            @Override public void run() { launchMode("desktop"); }
        });
        bind(R.id.btn_screen, new Runnable() {
            @Override public void run() { openX11(true); }
        });
        bind(R.id.btn_doctor, new Runnable() {
            @Override public void run() { runDoctor(); }
        });
        bind(R.id.btn_termux, new Runnable() {
            @Override public void run() { openTermux(); }
        });
        bind(R.id.btn_stop, new Runnable() {
            @Override public void run() { stopAll(); }
        });

        handleShortcut(getIntent());
    }

    private void bind(int id, final Runnable action) {
        findViewById(id).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { action.run(); }
        });
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleShortcut(intent);
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshStatus();
    }

    /** اختصارات الشاشة الرئيسية (الضغط الطويل على الأيقونة) تمرر الوضع هنا. */
    private void handleShortcut(Intent intent) {
        if (intent == null) return;
        String mode = intent.getStringExtra("mode");
        if (mode == null || mode.isEmpty()) return;
        // نستهلك القيمة حتى لا تتكرر عند تدوير الشاشة أو العودة للتطبيق
        intent.removeExtra("mode");
        launchMode(mode);
    }

    // ── الحالة ─────────────────────────────────────────────────────────

    private void refreshStatus() {
        boolean termux = isInstalled(TERMUX_PKG);
        boolean x11 = isInstalled(TERMUX_X11_PKG);
        String text = getString(R.string.status_termux) + " " + mark(termux) + "\n"
                + getString(R.string.status_x11) + " " + mark(x11);
        if (!termux || !x11) {
            text = text + "\n\n" + getString(R.string.status_missing_hint);
        }
        status.setText(text);
    }

    private String mark(boolean ok) {
        return getString(ok ? R.string.installed : R.string.not_installed);
    }

    private boolean isInstalled(String pkg) {
        try {
            getPackageManager().getPackageInfo(pkg, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    // ── التشغيل ────────────────────────────────────────────────────────

    private void launchMode(final String mode) {
        if (!isInstalled(TERMUX_PKG)) {
            showInstallDialog(R.string.need_termux, TERMUX_DOWNLOAD);
            return;
        }

        // لم يُثبّت النظام بعد؟ لا نرسله إلى شاشة عرض فارغة
        if (!prefs().getBoolean(KEY_INSTALL_STARTED, false)) {
            showNotInstalledDialog(mode);
            return;
        }

        // الغلاف يشرح السبب داخل Termux لو كان الأمر غير موجود، بدل الصمت
        String script =
                "if command -v s25-desktop >/dev/null 2>&1; then exec s25-desktop " + mode + "; fi; "
                + "printf '\\n\\033[0;31m*** النظام غير مثبت ***\\033[0m\\n'; "
                + "printf 'نفّذ:\\n  bash turnip-a830-s25ultra/s25-desktop/install.sh\\n\\n'; "
                + "exec bash";
        boolean started = runInTermux(TERMUX_BIN + "bash", new String[]{"-lc", script}, false, false);
        if (!started) return;

        String text = getString(R.string.starting, label(mode));
        if (mode.startsWith("win-")) {
            text = text + "\n\n" + getString(R.string.win_first_run);
        }
        status.setText(text);

        if (!isInstalled(TERMUX_X11_PKG)) {
            showInstallDialog(R.string.need_x11, X11_DOWNLOAD);
            return;
        }
        // ننتقل لشاشة العرض بعد أن يبدأ خادم X
        handler.postDelayed(new Runnable() {
            @Override public void run() { openX11(false); }
        }, SWITCH_DELAY_MS);
    }

    private String label(String mode) {
        switch (mode) {
            case "win-claude": return getString(R.string.mode_win_claude);
            case "win-chrome": return getString(R.string.mode_win_chrome);
            default:           return getString(R.string.mode_desktop);
        }
    }

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS, MODE_PRIVATE);
    }

    /** تشغيل التثبيت الكامل في جلسة Termux مرئية ليتابع المستخدم التقدّم. */
    private void startInstall() {
        if (!isInstalled(TERMUX_PKG)) {
            showInstallDialog(R.string.need_termux, TERMUX_DOWNLOAD);
            return;
        }
        if (runInTermux(TERMUX_BIN + "bash", new String[]{"-lc", INSTALL_CMD}, false, true)) {
            prefs().edit().putBoolean(KEY_INSTALL_STARTED, true).apply();
            status.setText(R.string.installing);
        }
    }

    private void showNotInstalledDialog(final String mode) {
        new AlertDialog.Builder(this)
                .setTitle(R.string.not_installed_title)
                .setMessage(R.string.not_installed_body)
                .setPositiveButton(R.string.install_now, new DialogInterface.OnClickListener() {
                    @Override public void onClick(DialogInterface d, int w) { startInstall(); }
                })
                .setNegativeButton(R.string.run_anyway, new DialogInterface.OnClickListener() {
                    @Override public void onClick(DialogInterface d, int w) {
                        prefs().edit().putBoolean(KEY_INSTALL_STARTED, true).apply();
                        launchMode(mode);
                    }
                })
                .show();
    }

    private void runDoctor() {
        if (!isInstalled(TERMUX_PKG)) {
            showInstallDialog(R.string.need_termux, TERMUX_DOWNLOAD);
            return;
        }
        // نفتح جلسة Termux مرئية حتى يقرأ المستخدم نتيجة التشخيص
        runInTermux(TERMUX_BIN + "s25-doctor", new String[]{}, false, true);
    }

    private void stopAll() {
        if (!isInstalled(TERMUX_PKG)) {
            showInstallDialog(R.string.need_termux, TERMUX_DOWNLOAD);
            return;
        }
        if (runInTermux(TERMUX_BIN + "s25-stop", new String[]{}, true, false)) {
            status.setText(R.string.stopped);
            toast(R.string.stopped);
        }
    }

    /**
     * تنفيذ أمر داخل Termux عبر خدمة RUN_COMMAND.
     *
     * @param background لا تُنشئ جلسة طرفية مرئية إطلاقاً
     * @param showTermux افتح واجهة Termux لعرض مخرجات الأمر
     * @return true إن قُبل الطلب
     */
    private boolean runInTermux(String path, String[] args, boolean background, boolean showTermux) {
        Intent intent = new Intent(ACTION_RUN_COMMAND);
        intent.setClassName(TERMUX_PKG, RUN_COMMAND_SERVICE);
        intent.putExtra(EXTRA_PATH, path);
        if (args.length > 0) {
            intent.putExtra(EXTRA_ARGS, args);
        }
        intent.putExtra(EXTRA_WORKDIR, TERMUX_HOME);
        intent.putExtra(EXTRA_BACKGROUND, background);
        // "0" = اجعلها الجلسة الحالية وافتح Termux، "1" = اجعلها الحالية بدون فتح
        intent.putExtra(EXTRA_SESSION_ACTION, showTermux ? "0" : "1");

        try {
            startService(intent);
            return true;
        } catch (SecurityException e) {
            showEnableExternalAppsDialog();
            return false;
        } catch (IllegalStateException e) {
            toast(R.string.err_termux_background);
            return false;
        } catch (RuntimeException e) {
            status.setText(getString(R.string.err_generic, String.valueOf(e.getMessage())));
            return false;
        }
    }

    // ── شاشة العرض و Termux ────────────────────────────────────────────

    private void openX11(boolean manual) {
        Intent intent = new Intent();
        intent.setClassName(TERMUX_X11_PKG, "com.termux.x11.MainActivity");
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        try {
            startActivity(intent);
        } catch (RuntimeException e) {
            if (manual) {
                showInstallDialog(R.string.need_x11, X11_DOWNLOAD);
            }
        }
    }

    private void openTermux() {
        if (!isInstalled(TERMUX_PKG)) {
            showInstallDialog(R.string.need_termux, TERMUX_DOWNLOAD);
            return;
        }
        Intent intent = getPackageManager().getLaunchIntentForPackage(TERMUX_PKG);
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        }
    }

    // ── نوافذ الإرشاد ──────────────────────────────────────────────────

    private void showInstallDialog(int messageRes, final String url) {
        new AlertDialog.Builder(this)
                .setTitle(R.string.missing_app)
                .setMessage(messageRes)
                .setPositiveButton(R.string.download, new DialogInterface.OnClickListener() {
                    @Override public void onClick(DialogInterface d, int w) { openUrl(url); }
                })
                .setNegativeButton(R.string.close, null)
                .show();
    }

    private void showEnableExternalAppsDialog() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.permission_needed)
                .setMessage(getString(R.string.enable_external_apps, ENABLE_CMD))
                .setPositiveButton(R.string.copy_command, new DialogInterface.OnClickListener() {
                    @Override public void onClick(DialogInterface d, int w) {
                        copyToClipboard(ENABLE_CMD);
                        toast(R.string.copied);
                        openTermux();
                    }
                })
                .setNegativeButton(R.string.close, null)
                .show();
    }

    private void copyToClipboard(String text) {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm != null) {
            cm.setPrimaryClip(ClipData.newPlainText("s25", text));
        }
    }

    private void openUrl(String url) {
        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(intent);
        } catch (RuntimeException e) {
            copyToClipboard(url);
            toast(R.string.copied);
        }
    }

    private void toast(int res) {
        Toast.makeText(this, res, Toast.LENGTH_SHORT).show();
    }
}
