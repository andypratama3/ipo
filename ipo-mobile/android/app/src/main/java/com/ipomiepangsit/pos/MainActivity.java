package com.ipomiepangsit.pos;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
  @Override
  public void onCreate(Bundle savedInstanceState) {
    registerPlugin(PrintPlugin.class);
    registerPlugin(BluetoothThermalPlugin.class);
    registerPlugin(DocumentSharePlugin.class);
    super.onCreate(savedInstanceState);
    // Ukuran teks mengikuti desain aplikasi (100%). Tanpa baris ini WebView
    // ikut skala font sistem Android — kalau pemilik memilih font besar di
    // pengaturan HP, seluruh tampilan aplikasi ikut membengkak.
    getBridge().getWebView().getSettings().setTextZoom(100);
  }
}
