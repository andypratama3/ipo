package com.ipomiepangsit.pos;

import android.Manifest;
import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothSocket;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

import org.json.JSONArray;
import org.json.JSONException;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Printer thermal Bluetooth 58 mm (iware X58BT II / MP58 dan sejenisnya)
 * memakai sambungan Bluetooth SPP dan bahasa ESC/POS — tidak bisa dipakai
 * lewat dialog cetak Android biasa. Plugin ini:
 *
 *  - listDevices(): daftar perangkat Bluetooth yang sudah dipasangkan
 *    (getBondedDevices) untuk dipilih dari Pengaturan.
 *  - print({ address, data, width }): sambung via UUID SPP standar
 *    00001101-0000-1000-8000-00805F9B34FB, kirim byte ESC/POS hasil
 *    terjemahan "data" (JSON array baris [teks, perataan, tebal, ukuran])
 *    lalu potong kertas.
 *
 * Dipanggil dari js/pos.js lewat Capacitor.Plugins.BluetoothThermal
 * (nativeBluetoothPrinter / tryBluetoothPrint / testBluetoothPrint).
 */
@CapacitorPlugin(
    name = "BluetoothThermal",
    permissions = {
        @Permission(strings = { Manifest.permission.BLUETOOTH_CONNECT }, alias = "bluetooth")
    }
)
public class BluetoothThermalPlugin extends Plugin {

  private static final String TAG = "BluetoothThermal";
  private static final UUID SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");
  private static final long CONNECT_TIMEOUT_MS = 10000L;

  private final ExecutorService executor = Executors.newSingleThreadExecutor();
  private final Handler mainHandler = new Handler(Looper.getMainLooper());

  private volatile BluetoothSocket activeSocket;
  private volatile String activeAddress;

  private BluetoothAdapter adapter() {
    BluetoothManager manager = (BluetoothManager) getContext().getSystemService(Context.BLUETOOTH_SERVICE);
    return manager == null ? null : manager.getAdapter();
  }

  private boolean hasConnectPermission() {
    // Di bawah Android 12 izin Bluetooth cukup dari pemasangan APK
    // (BLUETOOTH/BLUETOOTH_ADMIN di manifest). Di 31+ butuh BLUETOOTH_CONNECT.
    if (Build.VERSION.SDK_INT < 31) return true;
    return getContext().checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
  }

  @SuppressLint("MissingPermission")
  @PluginMethod
  public void listDevices(PluginCall call) {
    if (!hasConnectPermission()) {
      requestPermissionForAlias("bluetooth", call, "listDevicesPermitted");
      return;
    }
    BluetoothAdapter adapter = adapter();
    if (adapter == null) {
      call.reject("Bluetooth tidak tersedia di perangkat ini");
      return;
    }
    try {
      Set<BluetoothDevice> bonded = adapter.getBondedDevices();
      JSArray result = new JSArray();
      for (BluetoothDevice device : bonded) {
        JSObject item = new JSObject();
        item.put("name", device.getName() == null ? device.getAddress() : device.getName());
        item.put("address", device.getAddress());
        result.put(item);
      }
      call.resolve(new JSObject().put("devices", result));
    } catch (SecurityException error) {
      call.reject("Izin Bluetooth belum diberikan. Buka Pengaturan aplikasi lalu izinkan Bluetooth.");
    }
  }

  @PermissionCallback
  private void listDevicesPermitted(PluginCall call) {
    listDevices(call);
  }

  @PluginMethod
  public void print(PluginCall call) {
    String address = call.getString("address", "");
    String data = call.getString("data", "");
    int width = call.getInt("width", 32);
    if (data == null || data.isEmpty()) {
      call.reject("Tidak ada data struk");
      return;
    }
    if (!hasConnectPermission()) {
      requestPermissionForAlias("bluetooth", call, "printPermitted");
      return;
    }
    printInternal(call, address, data, Math.min(48, Math.max(32, width)));
  }

  @PermissionCallback
  private void printPermitted(PluginCall call) {
    print(call);
  }

  private void printInternal(final PluginCall call, final String wantedAddress, final String data, final int width) {
    executor.execute(() -> {
      BluetoothSocket socket = null;
      try {
        socket = openSocket(wantedAddress);
        if (socket == null) {
          failOnMain(call, "Tidak bisa terhubung ke printer. Pastikan printer menyala, sudah dipasangkan di Bluetooth HP (kode 0000/1234), lalu muat ulang daftar perangkat.");
          return;
        }
        OutputStream output = socket.getOutputStream();
        output.write(escpos(data, width));
        output.flush();
        try { Thread.sleep(350); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
        closeQuietly(output);
        closeQuietly(socket);
        activeSocket = null;
        activeAddress = null;
        succeedOnMain(call);
      } catch (Exception error) {
        Log.e(TAG, "print failed", error);
        closeQuietly(socket);
        activeSocket = null;
        activeAddress = null;
        failOnMain(call, "Cetak gagal: " + friendlyMessage(error));
      }
    });
  }

  /** Membuka Pengaturan Bluetooth HP agar pengguna bisa memasangkan printer.
   *  Beberapa printer clone memerlukan pemasangan lewat menu sistem ini dulu. */
  @PluginMethod
  public void openBluetoothSettings(PluginCall call) {
    try {
      Intent intent = new Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS);
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      getContext().startActivity(intent);
      call.resolve();
    } catch (Exception error) {
      call.reject("Tidak bisa membuka pengaturan Bluetooth: " + friendlyMessage(error));
    }
  }

  /** Buka (atau pakai ulang) soket SPP ke printer. Blok maksimal ~10 detik per
   *  percobaan. Karena banyak printer murah hanya menerima kanal tertentu,
   *  dicoba berurutan: SPP aman (secure) → SPP tak aman (insecure) -> kanal 1. */
  private BluetoothSocket openSocket(String wantedAddress) throws IOException {
    BluetoothSocket existing = activeSocket;
    if (existing != null && existing.isConnected()
        && activeAddress != null && (wantedAddress == null || wantedAddress.isEmpty() || activeAddress.equals(wantedAddress))) {
      return existing;
    }
    closeQuietly(existing);
    activeSocket = null;
    activeAddress = null;

    BluetoothAdapter adapter = adapter();
    if (adapter == null) return null;
    if (wantedAddress == null || wantedAddress.isEmpty()) return null; // tanpa alamat harus sudah punya soket aktif
    try { adapter.cancelDiscovery(); } catch (SecurityException ignored) { /* butuh izin; lanjut saja */ }
    BluetoothDevice device = adapter.getRemoteDevice(wantedAddress);
    if (device == null) return null;

    // 1) SPP standar (secure) — dipakai hampir semua printer POS.
    BluetoothSocket socket = connectWithTimeout(createSocket(device, true));
    // 2) SPP tanpa enkripsi — sebagian clone menolak sambungan secure.
    if (socket == null) socket = connectWithTimeout(createSocket(device, false));
    // 3) Paksa kanal RFCOMM 1 (reflection) — upaya terakhir untuk clone rewel.
    if (socket == null) socket = connectWithTimeout(createChannelOneSocket(device));
    if (socket == null) return null;

    activeSocket = socket;
    activeAddress = wantedAddress;
    return socket;
  }

  private BluetoothSocket createSocket(BluetoothDevice device, boolean secure) {
    try {
      return secure
          ? device.createRfcommSocketToServiceRecord(SPP_UUID)
          : device.createInsecureRfcommSocketToServiceRecord(SPP_UUID);
    } catch (IOException error) {
      return null;
    }
  }

  private BluetoothSocket createChannelOneSocket(BluetoothDevice device) {
    try {
      Method method = device.getClass().getMethod("createInsecureRfcommSocket", int.class);
      return (BluetoothSocket) method.invoke(device, 1);
    } catch (Exception error) {
      return null;
    }
  }

  /** connect() memblokir tanpa batas; jalankan di utas terpisah dan beri batas
   *  waktu supaya aplikasi tidak menggantung saat printer tidak merespons. */
  private BluetoothSocket connectWithTimeout(final BluetoothSocket socket) {
    if (socket == null) return null;
    final boolean[] connecting = { true };
    Thread connector = new Thread(() -> {
      try { socket.connect(); } catch (IOException ignored) { }
      finally { connecting[0] = false; }
    });
    connector.start();
    long deadline = System.currentTimeMillis() + CONNECT_TIMEOUT_MS;
    while (connecting[0] && System.currentTimeMillis() < deadline) {
      try { Thread.sleep(40); } catch (InterruptedException e) { Thread.currentThread().interrupt(); break; }
    }
    if (socket.isConnected()) return socket;
    try { socket.close(); } catch (IOException ignored) { }
    return null;
  }

  /** Terjemahkan baris JSON menjadi byte ESC/POS (teks + potong kertas). */
  private byte[] escpos(String jsonData, int width) throws IOException, JSONException {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    out.write(new byte[] { 0x1B, 0x40 }); // ESC @ — inisialisasi
    JSONArray lines = new JSONArray(jsonData);
    for (int i = 0; i < lines.length(); i++) {
      JSONArray line = lines.getJSONArray(i);
      String text = line.optString(0, "");
      int align = line.optInt(1, 0);
      int bold = line.optInt(2, 0);
      int size = line.optInt(3, 0);
      out.write(new byte[] { 0x1B, 0x61, (byte) Math.min(2, Math.max(0, align)) }); // perataan
      out.write(new byte[] { 0x1B, 0x45, (byte) (bold == 1 ? 1 : 0) });              // tebal
      int mode = (size & 1) | ((size & 2) == 0 ? 0 : 2);                              // GS ! ukuran
      out.write(new byte[] { 0x1D, 0x21, (byte) mode });
      out.write(renderLine(text, width).getBytes(StandardCharsets.ISO_8859_1));
      out.write(0x0A);
    }
    for (int i = 0; i < 4; i++) out.write(0x0A);   // ruang setelah struk
    out.write(new byte[] { 0x1D, 0x56, 0x42, 0x00 }); // GS V B 0 — potong sebagian
    return out.toByteArray();
  }

  private String renderLine(String rawText, int width) {
    String text = rawText == null ? "" : rawText;
    int tabIndex = text.indexOf('\t');
    if (tabIndex >= 0) {
      String left = text.substring(0, tabIndex).trim();
      String right = text.substring(tabIndex + 1).trim();
      int rightLen = latin1Length(right);
      // Sisa ruang untuk kolom kiri; kalau harga + label melebihi lebar
      // kertas, kolom kiri dipotong agar nilai tetap di tepi kanan.
      int leftBudget = width - rightLen - 1;
      if (leftBudget < 1) return wrapLatin1(text.replace('\t', ' ').trim(), width);
      left = truncateLatin1(left, leftBudget);
      int pad = width - latin1Length(left) - rightLen;
      if (pad < 1) pad = 1;
      return padRight(left, pad) + right;
    }
    return wrapLatin1(text, width);
  }

  /** Teks panjang (nama menu/alamat) dibungkus ke baris berikutnya pada
   *  lebar kertas, diusahakan pada spasi, supaya tidak terpotong. */
  private String wrapLatin1(String text, int width) {
    if (width < 1) width = 32;
    if (latin1Length(text) <= width) return text;
    StringBuilder out = new StringBuilder();
    String remaining = text;
    boolean firstLine = true;
    while (latin1Length(remaining) > width) {
      int limit = Math.min(width, remaining.length());
      int breakAt = -1;
      for (int i = limit - 1; i > 0; i--) {
        if (remaining.charAt(i) == ' ') { breakAt = i; break; }
      }
      int take = breakAt > 0 ? breakAt : limit;
      if (!firstLine) out.append('\n');
      out.append(remaining.substring(0, take).trim());
      firstLine = false;
      remaining = remaining.substring(take).replaceFirst("^ +", "");
    }
    if (!firstLine) out.append('\n');
    out.append(remaining.trim());
    return out.toString();
  }

  private int latin1Length(String text) {
    return text.getBytes(StandardCharsets.ISO_8859_1).length;
  }

  private String padRight(String text, int spaces) {
    StringBuilder sb = new StringBuilder(text);
    for (int i = 0; i < spaces; i++) sb.append(' ');
    return sb.toString();
  }

  private String truncateLatin1(String text, int maxWidth) {
    byte[] bytes = text.getBytes(StandardCharsets.ISO_8859_1);
    if (bytes.length <= maxWidth) return text;
    return new String(bytes, 0, maxWidth, StandardCharsets.ISO_8859_1);
  }

  private String friendlyMessage(Exception error) {
    String message = error == null || error.getMessage() == null ? "" : error.getMessage().toLowerCase();
    if (message.contains("socket") || message.contains("connect") || message.contains("timed out")
        || message.contains("broken pipe") || message.contains("unable")) {
      return "printer tidak merespons. Pastikan printer menyala dan dekat dengan HP, lalu coba lagi.";
    }
    if (message.contains("permission")) {
      return "izin Bluetooth belum diberikan. Buka Pengaturan aplikasi lalu izinkan Bluetooth.";
    }
    return message.isEmpty() ? "periksa koneksi printer." : error.getMessage();
  }

  private void failOnMain(final PluginCall call, final String message) {
    mainHandler.post(() -> {
      if (call != null) call.reject(message);
    });
  }

  private void succeedOnMain(final PluginCall call) {
    mainHandler.post(() -> {
      if (call != null) call.resolve();
    });
  }

  private void closeQuietly(OutputStream stream) {
    if (stream == null) return;
    try { stream.close(); } catch (IOException ignored) { }
  }

  private void closeQuietly(BluetoothSocket socket) {
    if (socket == null) return;
    try { socket.close(); } catch (IOException ignored) { }
  }
}