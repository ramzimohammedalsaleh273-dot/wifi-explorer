package com.example.wifi_explorer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.wifi.ScanResult;
import android.net.wifi.WifiManager;
import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
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
  private final Handler handler = new Handler(Looper.getMainLooper());
  private boolean scanReceiverRegistered = false;

  @Override public void configureFlutterEngine(FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
      .setMethodCallHandler((call, result) -> {
        if (!"scanNetworks".equals(call.method)) { result.notImplemented(); return; }
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
          result.error("permission_denied", "Location permission is required for Wi-Fi scanning", null); return;
        }
        WifiManager wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifi == null || !wifi.isWifiEnabled()) {
          result.error("wifi_disabled", "Turn on Wi-Fi and try again", null); return;
        }
        final BroadcastReceiver receiver = new BroadcastReceiver() {
          @Override public void onReceive(Context context, Intent intent) {
            try {
              unregisterReceiver(this);
              scanReceiverRegistered = false;
              handler.removeCallbacksAndMessages(this);
              result.success(toMaps(wifi.getScanResults()));
            } catch (SecurityException e) {
              result.error("permission_denied", "Android blocked Wi-Fi scan access", null);
            } catch (Exception e) {
              result.error("scan_failed", e.getMessage(), null);
            }
          }
        };
        try {
          IntentFilter filter = new IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION);
          if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
          else registerReceiver(receiver, filter);
          scanReceiverRegistered = true;
          boolean started = wifi.startScan();
          if (!started) {
            unregisterReceiver(receiver);
            scanReceiverRegistered = false;
            result.success(toMaps(wifi.getScanResults()));
            return;
          }
          handler.postDelayed(() -> {
            if (scanReceiverRegistered) {
              try { unregisterReceiver(receiver); } catch (Exception ignored) {}
              scanReceiverRegistered = false;
              try { result.success(toMaps(wifi.getScanResults())); }
              catch (Exception e) { result.error("scan_timeout", "Scan timed out; Android may have limited scan frequency", null); }
            }
          }, 12000);
        } catch (SecurityException e) {
          if (scanReceiverRegistered) { try { unregisterReceiver(receiver); } catch (Exception ignored) {} scanReceiverRegistered = false; }
          result.error("permission_denied", "Android blocked Wi-Fi scan access", null);
        } catch (Exception e) {
          if (scanReceiverRegistered) { try { unregisterReceiver(receiver); } catch (Exception ignored) {} scanReceiverRegistered = false; }
          result.error("scan_failed", e.getMessage(), null);
        }
      });
  }

  private List<Map<String,Object>> toMaps(List<ScanResult> scans) {
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
    return output;
  }

  private int frequencyToChannel(int f) {
    if (f >= 2412 && f <= 2472) return (f - 2407) / 5;
    if (f == 2484) return 14;
    if (f >= 5000 && f <= 5895) return (f - 5000) / 5;
    if (f >= 5955 && f <= 7115) return (f - 5950) / 5;
    return 0;
  }
}
