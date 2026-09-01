import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterDownloader.initialize(debug: true, ignoreSsl: true);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});
  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController controller;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFEEE9E3))
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            if (await _handleExternalUrl(request.url)) {
              return NavigationDecision.prevent;
            }

            if (request.url.endsWith(".pdf") ||
                request.url.endsWith(".jpg") ||
                request.url.endsWith(".png") ||
                request.url.endsWith(".zip")) {
              await downloadFile(request.url);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            _hideFooter();
          },
          onProgress: (progress) {
            if (progress > 10) {
              _hideFooter();
            }
          },
          onPageFinished: (url) async {
            _hideFooter();
            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
            if (url.contains('/login') || _isPublicWebsiteUrl(url)) {
              await _clearLastUrl();
            } else {
              await _saveLastUrl(url);
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          },
        ),
      );
    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController).setOnShowFileSelector(
        _androidFilePicker,
      );
    } else if (controller.platform is WebKitWebViewController) {
      (controller.platform as WebKitWebViewController)
          .setAllowsBackForwardNavigationGestures(true);
    }

    _loadInitialUrl();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && isLoading) {
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    final bool allowMultiple = params.mode == FileSelectorMode.openMultiple;
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      type: FileType.any,
    );
    if (result != null && result.files.isNotEmpty) {
      return result.files
          .where((file) => file.path != null && file.path!.isNotEmpty)
          .map((file) => Uri.file(file.path!).toString())
          .toList();
    }

    return [];
  }

  Future<void> downloadFile(String url) async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    }
    directory ??= await getApplicationDocumentsDirectory();
    final fileName = url.split('/').last.split('?').first;
    await FlutterDownloader.enqueue(
      url: url,
      savedDir: directory.path,
      fileName: fileName.isNotEmpty ? fileName : null,
      showNotification: true,
      openFileFromNotification: true,
      saveInPublicStorage: Platform.isAndroid,
    );
  }

  Future<void> _loadInitialUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('last_url');
      String urlToLoad = 'https://nutflix-frontend.vercel.app/';
      if (savedUrl != null &&
          savedUrl.isNotEmpty &&
          !_isPublicWebsiteUrl(savedUrl)) {
        urlToLoad = savedUrl;
      }
      controller.loadRequest(Uri.parse(urlToLoad));
    } catch (e) {
      controller.loadRequest(Uri.parse('https://nutflix-frontend.vercel.app/'));
    }
  }

  Future<void> _saveLastUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_url', url);
    } catch (_) {}
  }

  Future<void> _clearLastUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_url');
    } catch (_) {}
  }

  bool _isPublicWebsiteUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (!uri.host.contains('nutflix-frontend.vercel.app')) return false;
    final path = uri.path.toLowerCase().trim();
    final cleanPath = path.replaceAll(RegExp(r'/+$'), '');
    if (cleanPath.isEmpty ||
        cleanPath == '/' ||
        cleanPath == '/home' ||
        cleanPath == '/index' ||
        cleanPath == '/index.php' ||
        cleanPath == '/index.html') {
      return true;
    }
    return false;
  }

  bool _isExitPage(String? url) {
    if (url == null || url.isEmpty) return true;
    final uri = Uri.tryParse(url);
    if (uri == null) return true;
    final path = uri.path.toLowerCase().trim();
    final cleanPath = path.replaceAll(RegExp(r'/+$'), '');
    if (cleanPath.isEmpty ||
        cleanPath == '/' ||
        cleanPath == '/home' ||
        cleanPath == '/index' ||
        cleanPath == '/index.php' ||
        cleanPath == '/index.html') {
      return true;
    }
    if (cleanPath == '/login' || cleanPath.endsWith('/login')) {
      return true;
    }
    if (cleanPath.contains('dashboard')) {
      return true;
    }
    if (cleanPath == '/user' ||
        cleanPath == '/associate' ||
        cleanPath == '/staff' ||
        cleanPath == '/admin') {
      return true;
    }
    return false;
  }

  void _hideFooter() {
    controller.runJavaScript('''
      (function() {
        const styleId = 'hide-app-footer-style';
        if (!document.getElementById(styleId)) {
          const style = document.createElement('style');
          style.id = styleId;
          style.innerHTML = 'footer, .mobile-footer-nav, [class*="footer"], [class*="Footer"] { display: none !important; }';
          (document.head || document.documentElement).appendChild(style);
        }

        const handlerId = 'external-click-handler';
        if (!window[handlerId]) {
          window[handlerId] = true;
          document.addEventListener('click', function(e) {
            let el = e.target;
            while (el && el !== document.body) {
              const href = el.getAttribute ? (el.getAttribute('href') || '') : '';
              const text = (el.innerText || el.textContent || '').trim().toLowerCase();

              if (href.includes('wa.me') || href.includes('whatsapp') || href.startsWith('whatsapp:') || href.startsWith('tel:') || href.startsWith('mailto:')) {
                return;
              }

              if (text.includes('chat on whatsapp') || (text.includes('whatsapp') && (text.includes('98300') || text.includes('support')))) {
                window.location.href = 'https://wa.me/919830055527';
                e.preventDefault();
                break;
              }
              el = el.parentElement;
            }
          }, true);
        }
      })();
    ''');
  }

  Future<bool> _handleExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();

    bool isWhatsApp =
        scheme == 'whatsapp' ||
        host == 'wa.me' ||
        host.endsWith('.wa.me') ||
        host == 'whatsapp.com' ||
        host.endsWith('.whatsapp.com') ||
        url.contains('wa.me/') ||
        url.contains('whatsapp.com/') ||
        url.startsWith('whatsapp://');

    bool isNonWebScheme =
        scheme.isNotEmpty &&
        scheme != 'http' &&
        scheme != 'https' &&
        scheme != 'about' &&
        scheme != 'data' &&
        scheme != 'javascript';

    if (isWhatsApp || isNonWebScheme) {
      await _openExternalUrl(url, isWhatsApp: isWhatsApp);
      return true;
    }

    return false;
  }

  Future<void> _openExternalUrl(String url, {bool isWhatsApp = false}) async {
    try {
      Uri? uri = Uri.tryParse(url);
      if (uri == null) return;

      final scheme = uri.scheme.toLowerCase();

      if (scheme == 'intent') {
        if (url.contains('scheme=whatsapp')) {
          final phoneMatch = RegExp(r'phone=([0-9+]+)').firstMatch(url);
          if (phoneMatch != null) {
            final phone = phoneMatch.group(1);
            uri = Uri.parse('whatsapp://send?phone=$phone');
          }
        }

        bool launched = false;
        try {
          if (await canLaunchUrl(uri)) {
            launched = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
          }
        } catch (_) {}

        if (!launched) {
          try {
            launched = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
          } catch (_) {}
        }

        if (!launched) {
          final fallbackMatch = RegExp(
            r'S\.browser_fallback_url=([^;]+)',
          ).firstMatch(url);
          if (fallbackMatch != null) {
            final fallbackUrl = Uri.decodeFull(fallbackMatch.group(1)!);
            final fallbackUri = Uri.tryParse(fallbackUrl);
            if (fallbackUri != null) {
              try {
                await launchUrl(
                  fallbackUri,
                  mode: LaunchMode.externalApplication,
                );
                return;
              } catch (_) {}
            }
          }

          final schemeMatch = RegExp(r'scheme=([^;]+)').firstMatch(url);
          if (schemeMatch != null) {
            final targetScheme = schemeMatch.group(1)!;
            var convertedUrl = url.replaceFirst(
              RegExp(r'^intent://'),
              '$targetScheme://',
            );
            convertedUrl = convertedUrl.split('#Intent;').first;
            final convertedUri = Uri.tryParse(convertedUrl);
            if (convertedUri != null) {
              try {
                await launchUrl(
                  convertedUri,
                  mode: LaunchMode.externalApplication,
                );
                return;
              } catch (_) {}
            }
          }
        }
        return;
      }

      bool launched = false;
      try {
        if (await canLaunchUrl(uri)) {
          launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}

      if (!launched) {
        try {
          launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {}
      }

      if (!launched && isWhatsApp) {
        final phoneMatch = RegExp(r'\d{10,15}').firstMatch(url);
        if (phoneMatch != null) {
          final phone = phoneMatch.group(0);
          final fallbackUri = Uri.parse('whatsapp://send?phone=$phone');
          try {
            await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error launching external URL $url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final currentUrl = await controller.currentUrl();
        if (_isExitPage(currentUrl)) {
          SystemNavigator.pop();
          return;
        }
        if (await controller.canGoBack()) {
          controller.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFEEE9E3),
        body: Stack(
          children: [
            SafeArea(child: WebViewWidget(controller: controller)),
            if (isLoading)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFFEEE9E3),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Image.asset(
                        'assets/NUt-Flix.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
