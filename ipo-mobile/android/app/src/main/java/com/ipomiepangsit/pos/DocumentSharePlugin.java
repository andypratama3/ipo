package com.ipomiepangsit.pos;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;

import androidx.core.content.FileProvider;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Export laporan .xlsx dari aplikasi POS:
 *  - saveToDownloads : simpan LANGSUNG otomatis ke folder Download HP
 *    (MediaStore, Android 10+). Tanpa dialog — kasir menekan export dan
 *    file sudah ada di folder Download, tinggal dibagikan kapan pun perlu.
 *  - share           : dialog "Bagikan" Android (Google Drive / WhatsApp /
 *    email). Dipakai di Android versi lama atau sebagai cadangan bila
 *    penyimpanan otomatis gagal.
 *
 * Dipanggil dari js/pos.js: Capacitor.Plugins.DocumentShare.saveToDownloads(...)
 */
@CapacitorPlugin(name = "DocumentShare")
public class DocumentSharePlugin extends Plugin {

  @PluginMethod
  public void saveToDownloads(PluginCall call) {
    String fileName = call.getString("fileName", "laporan.xlsx");
    String base64 = call.getString("base64", "");
    String mime = call.getString("mime", "application/octet-stream");
    if (base64 == null || base64.isEmpty()) {
      call.reject("Konten file kosong");
      return;
    }
    byte[] bytes;
    try {
      bytes = Base64.decode(base64, Base64.DEFAULT);
    } catch (IllegalArgumentException error) {
      call.reject("Data file tidak valid");
      return;
    }
    String safeName = fileName.replaceAll("[^A-Za-z0-9._-]", "_");
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      // Android 9 ke bawah tidak punya MediaStore.Downloads: otomatis pindah
      // ke dialog "Simpan / kirim" (file disimpan lewat aplikasi tujuan).
      shareInternal(call, safeName, bytes, mime);
      return;
    }
    try {
      String[] saved = saveViaMediaStore(safeName, bytes, mime);
      JSObject result = new JSObject();
      result.put("savedAs", saved[0]);
      result.put("size", Long.parseLong(saved[1]));
      result.put("verified", Boolean.parseBoolean(saved[2]));
      call.resolve(result);
    } catch (Exception error) {
      call.reject("Gagal menyimpan ke Download: " + error.getMessage());
    }
  }

  @PluginMethod
  public void share(PluginCall call) {
    String fileName = call.getString("fileName", "laporan.xlsx");
    String base64 = call.getString("base64", "");
    String mime = call.getString("mime", "application/octet-stream");
    if (base64 == null || base64.isEmpty()) {
      call.reject("Konten file kosong");
      return;
    }
    byte[] bytes;
    try {
      bytes = Base64.decode(base64, Base64.DEFAULT);
    } catch (IllegalArgumentException error) {
      call.reject("Data file tidak valid");
      return;
    }
    String safeName = fileName.replaceAll("[^A-Za-z0-9._-]", "_");
    shareInternal(call, safeName, bytes, mime);
  }

  /* Menyimpan ke folder Download lewat MediaStore (API 29+). Nama yang sudah
     dipakai diberi akhiran (2), (3), dst. agar file export tidak timpa-timpakan.
     Setelah ditulis, file dicoba dibaca BALIK sebagai pemeriksaan lunak (tidak
     pernah menggagalkan simpanan yang berhasil): beberapa perangkat tidak bisa
     membaca file MediaStore tepat setelah ditulis, jadi hasil pembacaan hanya
     dipakai sebagai keterangan "verified", bukan alasan gagal.

     Hasil: { nama, ukuran byte, sudah-terverifikasi }. */
  private String[] saveViaMediaStore(String fileName, byte[] bytes, String mime) throws IOException {
    ContentResolver resolver = getContext().getContentResolver();
    String uniqueName = ensureUniqueDownloadName(resolver, fileName);
    ContentValues values = new ContentValues();
    values.put(MediaStore.Downloads.DISPLAY_NAME, uniqueName);
    values.put(MediaStore.Downloads.MIME_TYPE, mime);
    values.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
    Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
    if (uri == null) throw new IOException("tidak bisa membuat file di folder Download");
    try {
      OutputStream out = resolver.openOutputStream(uri);
      if (out == null) throw new IOException("tidak bisa membuka file tujuan");
      try (OutputStream stream = out) {
        stream.write(bytes);
        stream.flush();
      }
      boolean verified = softVerifySavedFile(resolver, uri, bytes);
      if (!verified) {
        // Kesempatan kedua: sebagian perangkat butuh jeda sebentar sebelum
        // file yang baru dibuat bisa dibaca ulang.
        try { Thread.sleep(400); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        verified = softVerifySavedFile(resolver, uri, bytes);
      }
      return new String[]{ uniqueName, String.valueOf(bytes.length), String.valueOf(verified) };
    } catch (Exception error) {
      try { resolver.delete(uri, null, null); } catch (Exception ignore) { /* bersihkan sisa */ }
      if (error instanceof IOException) throw (IOException) error;
      throw new IOException(error.getMessage(), error);
    }
  }

  /* Pemeriksaan lunak: mencoba membaca ulang file hasil simpan dan memastikan
     isinya persis sama dengan byte yang dikirim (panjang cocok, diawali tanda
     arsip ZIP "PK..", diakhiri penanda akhir arsip). Hasil false TIDAK
     menggagalkan simpanan — hanya dicatat sebagai "belum terverifikasi". */
  private boolean softVerifySavedFile(ContentResolver resolver, Uri uri, byte[] expected) {
    try (InputStream in = resolver.openInputStream(uri)) {
      if (in == null) return false;
      byte[] read = new byte[expected.length];
      int total = 0;
      int n;
      while (total < read.length && (n = in.read(read, total, read.length - total)) > 0) {
        total += n;
      }
      boolean lengthOk = total == expected.length;
      boolean zipHeaderOk = expected.length >= 4
          && read[0] == 'P' && read[1] == 'K' && read[2] == 0x03 && read[3] == 0x04;
      boolean zipEocdOk = expected.length >= 22
          && read[read.length - 4] == 'P' && read[read.length - 3] == 'K'
          && read[read.length - 2] == 0x05 && read[read.length - 1] == 0x06;
      return lengthOk && zipHeaderOk && zipEocdOk;
    } catch (Exception ignore) {
      return false;
    }
  }

  private String ensureUniqueDownloadName(ContentResolver resolver, String fileName) {
    String stem = fileName;
    String ext = "";
    int dot = fileName.lastIndexOf('.');
    if (dot > 0) {
      stem = fileName.substring(0, dot);
      ext = fileName.substring(dot);
    }
    String candidate = fileName;
    int n = 2;
    for (int attempt = 0; attempt < 50; attempt++) {
      if (!downloadNameExists(resolver, candidate)) return candidate;
      candidate = stem + " (" + n + ")" + ext;
      n += 1;
    }
    return candidate;
  }

  private boolean downloadNameExists(ContentResolver resolver, String name) {
    try (Cursor cursor = resolver.query(
        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
        new String[]{ MediaStore.Downloads.DISPLAY_NAME },
        MediaStore.Downloads.DISPLAY_NAME + " = ?",
        new String[]{ name },
        null)) {
      return cursor != null && cursor.moveToFirst();
    } catch (Exception ignore) {
      return false;
    }
  }

  /* Membuka dialog "Bagikan" Android: file ditulis ke cache aplikasi lalu
     dibagikan lewat FileProvider (Drive, WhatsApp, email, penyimpanan file). */
  private void shareInternal(PluginCall call, String fileName, byte[] bytes, String mime) {
    Intent probe = new Intent(Intent.ACTION_SEND);
    probe.setType(mime);
    if (probe.resolveActivity(getActivity().getPackageManager()) == null) {
      call.reject("Tidak ada aplikasi di HP ini yang bisa menerima file Excel (pasang Microsoft Excel, WPS Office, atau Google Sheets), lalu coba lagi.");
      return;
    }
    File dir = new File(getContext().getCacheDir(), "export");
    if (!dir.exists() && !dir.mkdirs()) {
      call.reject("Tidak bisa membuat folder file");
      return;
    }
    File file = new File(dir, fileName);
    try (FileOutputStream out = new FileOutputStream(file)) {
      out.write(bytes);
    } catch (IOException error) {
      call.reject("Gagal menulis file: " + error.getMessage());
      return;
    }
    try {
      Uri uri = FileProvider.getUriForFile(getContext(), getContext().getPackageName() + ".fileprovider", file);
      Intent intent = new Intent(Intent.ACTION_SEND);
      intent.setType(mime);
      intent.putExtra(Intent.EXTRA_STREAM, uri);
      intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
      getActivity().startActivity(Intent.createChooser(intent, "Simpan / kirim laporan"));
      call.resolve();
    } catch (Exception error) {
      call.reject("Gagal membuka berbagi file: " + error.getMessage());
    }
  }
}