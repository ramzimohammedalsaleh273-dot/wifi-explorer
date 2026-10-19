package com.example.wifi_explorer;

import android.content.Context;
import android.net.wifi.ScanResult;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.Manifest;
import android.content.pm.PackageManager;
import androidx.core.app.ActivityCompat;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class MainActivity extends FlutterActivity {
  private static final String CHANNEL = "wifi_explorer/scan";
  @Override public void configureFlutterEngine(FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
      .setMethodCallHandler((call, result) -> {
        if (!"scanNetworks".equals(call.method)) { result.notImplemented(); return; }
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
          result.error("permission_denied", "Location permission is required for Wi-Fi scanning", null); return;
        }
        try {
          WifiManager wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
          if (wifi == null || !wifi.isWifiEnabled()) { result.error("wifi_disabled", "Turn on Wi-Fi and try again", null); return; }
          wifi.startScan();
          List<ScanResult> scans = wifi.getScanResults();
          List<Map<String,Object>> output = new ArrayList<>();
          for (ScanResult scan : scans) {
            Map<String,Object> item = new HashMap<>();
            item.put("ssid", scan.SSID == null ? "" : scan.SSID);
            item.put("bssid", scan.BSSID == null ? "" : scan.BSSID);
            item.put("level", scan.level);
            item.put("frequency", scan.frequency);
            item.put("channel", frequencyToChannel(scan.frequency));
            String caps = scan.capabilities == null ? "" : scan.capabilities;
            String security = "مفتوحة";
            if (caps.contains("WEP")) security = "WEP";
            if (caps.contains("WPA")) security = caps.contains("SAE") ? "WPA3 / WPA2" : "WPA/WPA2";
            if (caps.contains("EAP")) security = "WPA-Enterprise";
            item.put("security", security);
            output.add(item);
          }
          result.success(output);
        } catch (SecurityException e) { result.error("permission_denied", "Android blocked Wi-Fi scan access", null); }
          catch (Exception e) { result.error("scan_failed", e.getMessage(), null); }
      });
  }
  private int frequencyToChannel(int f) {
    if (f >= 2412 && f <= 2472) return (f - 2407) / 5;
    if (f == 2484) return 14;
    if (f >= 5000 && f <= 5895) return (f - 5000) / 5;
    if (f >= 5955 && f <= 7115) return (f - 5950) / 5;
    return 0;
  }
}
