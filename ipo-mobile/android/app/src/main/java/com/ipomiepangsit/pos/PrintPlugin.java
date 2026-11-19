package com.ipomiepangsit.pos;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintJob;
import android.print.PrintManager;
import android.webkit.WebView;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * Plugin cetak untuk APK.
 *
 * WebView Android tidak mengimplementasikan window.print(), jadi JS di dalam
 * aplikasi tidak bisa membuka dialog cetak sendiri. Plugin ini mencetak
 * WebView UTAMA aplikasi (bukan WebView tersembunyi): WebView tersembunyi yang
 * tidak pernah ditempelkan ke layar tidak pernah di-layout sehingga dokumen
 * yang dihasilkan renderer Chromium KOSONG — petaka yang mengakibatkan hasil
 * cetak v4 berupa kertas/PDF polos.
 *
 * Alurnya: JS menyiapkan isi struk di #printArea lalu menambah kelas
 * body.is-printing-receipt (sama seperti jalur window.print() di web; di media
 * cetak semua isi halaman disembunyikan kecuali .print-area), kemudian memanggil
 * print({ name, paperSize }). Plugin lalu mengambil adapter cetak dari WebView
 * utama — konten, @page, dan kelas .is-printing-receipt semuanya sudah berada
 * di halaman itu juga. Setelah pekerjaan cetak selesai/dibatalkan/gagal,
 * plugin membangkitkan event "mpj-print-done" di halaman supaya JS
 * mengembalikan tampilan normal.
 *
 * Catatan SDK: android.jar yang dipakai di sini tidak memuat
 * PrintManager.PrintJobStateChangeListener (addPrintJobStateChangeListener),
 * jadi status pekerjaan cetak dipantau lewat polling getInfo() yang dibungkus
 * Handler — hasil akhirnya sama, dan lebih mudah diverifikasi.
 *
 * Dipanggil dari js/pos.js: Capacitor.Plugins.Print.print({ name, paperSize })
 */
@CapacitorPlugin(name = "Print")
public class PrintPlugin extends Plugin {

  // Rentang maksimum memantau pekerjaan cetak sebelum memberi tahu JS
  // (10 menit jauh melebihi durasi dialog cetak yang wajar).
  private static final long WATCH_TIMEOUT_MS = 10 * 60 * 1000L;
  private static final long WATCH_INTERVAL_MS = 750L;

  @PluginMethod
  public void print(PluginCall call) {
    String name = call.getString("name", "Struk Mie Pangsit Jakarta");
    String paperSize = call.getString("paperSize", "58mm");

    getActivity().runOnUiThread(() -> {
      try {
        WebView webView = getBridge().getWebView();
        if (webView == null) {
          call.reject("WebView utama tidak tersedia");
          return;
        }
        PrintManager printManager = (PrintManager) getContext().getSystemService(Context.PRINT_SERVICE);
        if (printManager == null) {
          call.reject("PrintManager tidak tersedia di perangkat ini");
          return;
        }
        PrintDocumentAdapter adapter = webView.createPrintDocumentAdapter(name);
        PrintAttributes.Builder attributes = new PrintAttributes.Builder();
        PrintAttributes.MediaSize media = mediaSizeFor(paperSize);
        if (media != null) attributes.setMediaSize(media);

        // Dialog cetak Android terbuka; konten diambil dari WebView utama yang
        // sedang menampilkan .print-area (kelas is-printing-receipt sudah
        // disiapkan JS sebelum pemanggilan ini).
        PrintJob job = printManager.print(name, adapter, attributes.build());
        if (job != null) {
          watchJobTermination(job, webView);
        }
        call.resolve();
      } catch (Exception error) {
        call.reject("Gagal menyiapkan cetak: " + error.getMessage());
      }
    });
  }

  /** Pantau status pekerjaan cetak; kirim "mpj-print-done" begitu selesai. */
  private void watchJobTermination(final PrintJob job, final WebView webView) {
    final Handler handler = new Handler(Looper.getMainLooper());
    final long startedAt = System.currentTimeMillis();
    final boolean[] done = { false };
    final Runnable poll = new Runnable() {
      @Override
      public void run() {
        if (done[0]) return;
        boolean report = false;
        try {
          boolean terminal = job.isCompleted() || job.isCancelled() || job.isFailed();
          boolean timeout = System.currentTimeMillis() - startedAt > WATCH_TIMEOUT_MS;
          report = terminal || timeout;
        } catch (Exception ignored) {
          // Pekerjaan cetak sudah tidak dikenal sistem (mis. antrian direset)
          // -> anggap selesai supaya tampilan tidak menunggu selamanya.
          report = true;
        }
        if (report) {
          done[0] = true;
          webView.evaluateJavascript("window.dispatchEvent(new Event('mpj-print-done'))", result -> { });
          return;
        }
        handler.postDelayed(this, WATCH_INTERVAL_MS);
      }
    };
    handler.postDelayed(poll, WATCH_INTERVAL_MS);
  }

  /** Petakan pilihan ukuran kertas struk ke media cetak Android. */
  private PrintAttributes.MediaSize mediaSizeFor(String paperSize) {
    // satuan mil = 1/1000 inci. 58 mm ≈ 2283 mil, 80 mm ≈ 3150 mil.
    if ("58mm".equals(paperSize)) {
      return new PrintAttributes.MediaSize("CUSTOM_58MM", "58 mm", 2283, 8000);
    }
    if ("80mm".equals(paperSize)) {
      return new PrintAttributes.MediaSize("CUSTOM_80MM", "80 mm", 3150, 8000);
    }
    if ("a4".equals(paperSize)) {
      return PrintAttributes.MediaSize.ISO_A4.asPortrait();
    }
    return null; // ukuran bawaan printer
  }
}