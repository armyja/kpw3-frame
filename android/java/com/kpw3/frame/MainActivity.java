package com.kpw3.frame;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.List;

public class MainActivity extends Activity {

    private static final int REQ_IMAGES = 1;
    private static final int REQ_TREE = 2;

    private static final int[] ROTATIONS = {0, 90, 180, 270};
    private static final String[] FITS = {"满屏裁边 (cover)", "完整留白 (contain)"};
    private static final int[] LEVELS = {2, 4, 8, 16, 32};

    private TextView statusView;
    private TextView imagesView;
    private EditText portEdit;
    private EditText intervalEdit;
    private Spinner rotateSpinner;
    private Spinner fitSpinner;
    private Spinner levelsSpinner;
    private Switch rotateModeSwitch;

    // ---------------------------------------------------------------- lifecycle

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(buildUi());
        refresh();

        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 9);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        refresh();
    }

    // ---------------------------------------------------------------- ui

    private View buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(16);
        root.setPadding(pad, pad, pad, pad);

        statusView = new TextView(this);
        statusView.setTextSize(16);
        root.addView(statusView);

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        buttons.setPadding(0, dp(8), 0, dp(8));
        buttons.addView(button("启动服务器", v -> {
            saveSettings();
            FrameService.start(this);
            statusView.postDelayed(this::refresh, 400);
        }));
        buttons.addView(button("停止服务器", v -> {
            FrameService.stop(this);
            statusView.postDelayed(this::refresh, 400);
        }));
        buttons.addView(button("复制地址", v -> {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (cm != null) {
                cm.setPrimaryClip(ClipData.newPlainText("url", Net.frameUrl(this)));
                toast("已复制：" + Net.frameUrl(this));
            }
        }));
        root.addView(buttons);

        root.addView(label("图片（可多选）"));
        imagesView = new TextView(this);
        imagesView.setTextSize(13);
        root.addView(imagesView);
        LinearLayout imgButtons = new LinearLayout(this);
        imgButtons.addView(button("选择图片", v -> pickImages()));
        imgButtons.addView(button("清空", v -> {
            Prefs.images(this, new ArrayList<>());
            refresh();
        }));
        root.addView(imgButtons);

        root.addView(label("转向"));
        rotateSpinner = new Spinner(this);
        ArrayAdapter<String> rot = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_dropdown_item,
                new String[]{"不旋转 (0°)", "顺时针 90°", "180°", "顺时针 270°"});
        rotateSpinner.setAdapter(rot);
        root.addView(rotateSpinner);

        root.addView(label("缩放"));
        fitSpinner = new Spinner(this);
        fitSpinner.setAdapter(new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_dropdown_item, FITS));
        root.addView(fitSpinner);

        root.addView(label("灰度级数"));
        levelsSpinner = new Spinner(this);
        ArrayAdapter<String> lev = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_dropdown_item,
                new String[]{"2", "4", "8", "16（推荐）", "32"});
        levelsSpinner.setAdapter(lev);
        root.addView(levelsSpinner);

        rotateModeSwitch = new Switch(this);
        rotateModeSwitch.setText("多张图片时轮播（关掉＝固定第一张）");
        root.addView(rotateModeSwitch);

        root.addView(label("端口"));
        portEdit = new EditText(this);
        portEdit.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
        root.addView(portEdit);

        root.addView(label("Kindle 刷新间隔（秒）"));
        intervalEdit = new EditText(this);
        intervalEdit.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
        root.addView(intervalEdit);

        LinearLayout saveRow = new LinearLayout(this);
        saveRow.addView(button("保存设置", v -> {
            saveSettings();
            if (FrameService.running) {
                FrameService.stop(this);
                statusView.postDelayed(() -> {
                    FrameService.start(this);
                    refresh();
                }, 300);
            }
            toast("已保存");
            refresh();
        }));
        saveRow.addView(button("写入 Kindle（USB）", v -> pickKindleTree()));
        root.addView(saveRow);

        TextView note = new TextView(this);
        note.setTextSize(12);
        note.setText("\nKindle 端：KUAL → Server → Auto-detect on Wi-Fi 可自动指向本机。\n"
                + "USB 写入：先用 OTG 线连 Kindle（Kindle 会作为 U 盘出现），再点“写入 Kindle”，选中 Kindle 盘根目录。\n"
                + "长时间运行请在系统设置里把本应用加入“电池优化白名单”。");
        root.addView(note);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        return scroll;
    }

    private TextView label(String text) {
        TextView v = new TextView(this);
        v.setText(text);
        v.setPadding(0, dp(10), 0, 0);
        return v;
    }

    private Button button(String text, View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setOnClickListener(l);
        return b;
    }

    private void toast(String s) {
        Toast.makeText(this, s, Toast.LENGTH_SHORT).show();
    }

    private int dp(int v) {
        return Math.round(getResources().getDisplayMetrics().density * v);
    }

    // ---------------------------------------------------------------- settings

    private void loadSettings() {
        int rotate = Prefs.rotate(this);
        int rotIndex = 1;
        for (int n = 0; n < ROTATIONS.length; n++) {
            if (ROTATIONS[n] == rotate) {
                rotIndex = n;
            }
        }
        rotateSpinner.setSelection(rotIndex);
        fitSpinner.setSelection(Prefs.cover(this) ? 0 : 1);
        int levels = Prefs.levels(this);
        int levIndex = 3;
        for (int n = 0; n < LEVELS.length; n++) {
            if (LEVELS[n] == levels) {
                levIndex = n;
            }
        }
        levelsSpinner.setSelection(levIndex);
        rotateModeSwitch.setChecked(Prefs.rotateMode(this));
        portEdit.setText(String.valueOf(Prefs.port(this)));
        intervalEdit.setText(String.valueOf(Prefs.interval(this)));
    }

    private void saveSettings() {
        Prefs.rotate(this, ROTATIONS[rotateSpinner.getSelectedItemPosition()]);
        Prefs.cover(this, fitSpinner.getSelectedItemPosition() == 0);
        Prefs.levels(this, LEVELS[levelsSpinner.getSelectedItemPosition()]);
        Prefs.rotateMode(this, rotateModeSwitch.isChecked());
        try {
            Prefs.port(this, Integer.parseInt(portEdit.getText().toString().trim()));
        } catch (NumberFormatException ignored) {
        }
        try {
            Prefs.interval(this, Integer.parseInt(intervalEdit.getText().toString().trim()));
        } catch (NumberFormatException ignored) {
        }
    }

    private void refresh() {
        if (portEdit != null) {
            loadSettings();
        }
        String state = FrameService.running ? "运行中" : "已停止";
        statusView.setText("服务器：" + state + "\nKindle 地址：\n" + Net.frameUrl(this));
        List<String> images = Prefs.images(this);
        if (images.isEmpty()) {
            imagesView.setText("（还没有选择图片）");
        } else {
            StringBuilder sb = new StringBuilder();
            for (int n = 0; n < images.size(); n++) {
                String name = Uri.parse(images.get(n)).getLastPathSegment();
                sb.append("• ").append(name == null ? images.get(n) : name).append('\n');
            }
            imagesView.setText(sb.toString().trim());
        }
    }

    // ---------------------------------------------------------------- pickers

    private void pickImages() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("image/*");
        i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(i, REQ_IMAGES);
    }

    private void pickKindleTree() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(i, REQ_TREE);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        if (requestCode == REQ_IMAGES && resultCode == RESULT_OK && data != null) {
            List<String> images = new ArrayList<>(Prefs.images(this));
            ClipData clip = data.getClipData();
            if (clip != null) {
                for (int n = 0; n < clip.getItemCount(); n++) {
                    addImage(images, clip.getItemAt(n).getUri());
                }
            } else if (data.getData() != null) {
                addImage(images, data.getData());
            }
            Prefs.images(this, images);
            refresh();
            return;
        }

        if (requestCode == REQ_TREE && resultCode == RESULT_OK && data != null && data.getData() != null) {
            Uri tree = data.getData();
            try {
                getContentResolver().takePersistableUriPermission(tree,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            } catch (Exception ignored) {
            }
            try {
                String result = KindleWriter.apply(this, tree, Net.frameUrl(this), Prefs.interval(this));
                toast("已写入 Kindle");
                new android.app.AlertDialog.Builder(this)
                        .setTitle("写入结果")
                        .setMessage(result)
                        .setPositiveButton("好", null)
                        .show();
            } catch (Exception e) {
                new android.app.AlertDialog.Builder(this)
                        .setTitle("写入失败")
                        .setMessage(String.valueOf(e.getMessage()))
                        .setPositiveButton("好", null)
                        .show();
            }
        }
    }

    private void addImage(List<String> list, Uri uri) {
        try {
            getContentResolver().takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (Exception ignored) {
        }
        String s = uri.toString();
        if (!list.contains(s)) {
            list.add(s);
        }
    }
}
