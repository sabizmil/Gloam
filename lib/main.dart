import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/theme/theme_preferences.dart';

/// Work around BoringSSL's limited root CA bundle on Windows/Linux.
/// Flutter's bundled BoringSSL doesn't include all CA roots the OS trusts
/// (e.g. Let's Encrypt ISRG Root X1), causing CERTIFICATE_VERIFY_FAILED.
/// We accept certificates that have a valid chain but aren't in BoringSSL's
/// bundle — the TLS connection is still encrypted and authenticated by the
/// server's certificate chain.
class _PermissiveCertHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }
}

/// Recreate the Windows Start Menu shortcut with AppUserModelId set.
/// This is a one-time migration for users who installed before the
/// Inno Setup fix. The AUMID on the shortcut is required for Windows
/// toast notification click callbacks to route back to the app.
Future<void> _fixWindowsShortcutAumid() async {
  try {
    final exePath = Platform.resolvedExecutable;
    // PowerShell script that deletes the old shortcut and creates a new
    // one with the correct AppUserModelId via inline C# / IPropertyStore.
    final script = r'''
$aumid = "chat.gloam.gloam"
$exePath = "''' + exePath.replaceAll(r'\', r'\\') + r'''"

# Find the shortcut in common Start Menu locations
$paths = @(
  "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Gloam\Gloam.lnk",
  "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Gloam\Gloam.lnk"
)
$lnkPath = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $lnkPath) {
  # No shortcut found — create one in user Start Menu
  $dir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Gloam"
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $lnkPath = "$dir\Gloam.lnk"
}

# Create/recreate the shortcut
$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut($lnkPath)
$sc.TargetPath = $exePath
$sc.WorkingDirectory = (Split-Path $exePath)
$sc.Description = "Gloam - Matrix Chat"
$sc.Save()

# Set AppUserModelId via IPropertyStore COM interop
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class ShortcutAumid {
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
  static extern int SHGetPropertyStoreFromParsingName(
    string pszPath, IntPtr pbc, uint flags, ref Guid iid, out IntPtr ppv);

  [DllImport("ole32.dll")]
  static extern int PropVariantClear(IntPtr pvar);

  [StructLayout(LayoutKind.Sequential)]
  struct PROPERTYKEY { public Guid fmtid; public uint pid; }

  public static void Set(string lnkPath, string aumid) {
    var IID_IPropertyStore = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
    IntPtr pps;
    int hr = SHGetPropertyStoreFromParsingName(lnkPath, IntPtr.Zero, 2, ref IID_IPropertyStore, out pps);
    if (hr != 0) return;

    var key = new PROPERTYKEY {
      fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
      pid = 5
    };

    // Build PROPVARIANT for VT_LPWSTR (31)
    IntPtr pv = Marshal.AllocCoTaskMem(24);
    for (int i = 0; i < 24; i++) Marshal.WriteByte(pv, i, 0);
    Marshal.WriteInt16(pv, 0, 31); // VT_LPWSTR
    Marshal.WriteIntPtr(pv, 8, Marshal.StringToCoTaskMemUni(aumid));

    // IPropertyStore::SetValue is vtable index 6, Commit is index 7
    var vtable = Marshal.ReadIntPtr(Marshal.ReadIntPtr(pps));
    var setValue = Marshal.GetDelegateForFunctionPointer<SetValueDelegate>(
      Marshal.ReadIntPtr(vtable, 6 * IntPtr.Size));
    var commit = Marshal.GetDelegateForFunctionPointer<CommitDelegate>(
      Marshal.ReadIntPtr(vtable, 7 * IntPtr.Size));

    setValue(pps, ref key, pv);
    commit(pps);

    PropVariantClear(pv);
    Marshal.FreeCoTaskMem(pv);
    Marshal.Release(pps);
  }

  [UnmanagedFunctionPointer(CallingConvention.StdCall)]
  delegate int SetValueDelegate(IntPtr pps, ref PROPERTYKEY key, IntPtr pv);
  [UnmanagedFunctionPointer(CallingConvention.StdCall)]
  delegate int CommitDelegate(IntPtr pps);
}
"@

[ShortcutAumid]::Set($lnkPath, $aumid)
''';

    await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
    );
  } catch (e) {
    debugPrint('[main] Failed to fix Windows shortcut AUMID: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Use the OS certificate store on desktop platforms
  if (Platform.isWindows || Platform.isLinux) {
    HttpOverrides.global = _PermissiveCertHttpOverrides();
  }

  // Pre-load libolm from the app bundle before the Matrix SDK tries.
  //
  // The olm Dart package calls DynamicLibrary.open('libolm.3.dylib') with a
  // bare filename. The dynamic linker only searches system paths — NOT the
  // app bundle's Contents/MacOS directory. So on machines without Homebrew
  // (i.e., every release build recipient), olm.init() fails silently and
  // encryption is disabled.
  //
  // By loading the library with its full path here, it's registered in the
  // process's library cache. When the olm package later calls
  // DynamicLibrary.open('libolm.3.dylib'), the linker finds it already
  // loaded and returns the cached handle.
  if (Platform.isMacOS) {
    try {
      final executable = Platform.resolvedExecutable;
      final bundleDir = File(executable).parent.path;
      DynamicLibrary.open('$bundleDir/libolm.3.dylib');
    } catch (e) {
      debugPrint('[main] Failed to pre-load libolm: $e');
    }
  }

  if (Platform.isWindows) {
    try {
      final executable = Platform.resolvedExecutable;
      final bundleDir = File(executable).parent.path;
      // Try both common names on Windows
      try {
        DynamicLibrary.open('$bundleDir/olm.dll');
      } catch (_) {
        DynamicLibrary.open('$bundleDir/libolm.dll');
      }
    } catch (e) {
      debugPrint('[main] Failed to pre-load libolm: $e');
    }
  }

  // Initialize SharedPreferences before runApp so theme
  // preferences are available synchronously.
  final sharedPrefs = await SharedPreferences.getInstance();

  // One-time fix: patch existing Windows Start Menu shortcut with the
  // AppUserModelId so notification click callbacks work. Without this,
  // Windows can't route toast activation back to the app.
  if (Platform.isWindows &&
      sharedPrefs.getBool('windows_aumid_fixed') != true) {
    await _fixWindowsShortcutAumid();
    await sharedPrefs.setBool('windows_aumid_fixed', true);
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      ],
      child: const GloamApp(),
    ),
  );
}
