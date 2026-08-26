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
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
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
      })();
    ''');
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
        body: Stack(
          children: [
            SafeArea(child: WebViewWidget(controller: controller)),
            if (isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.white,
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
