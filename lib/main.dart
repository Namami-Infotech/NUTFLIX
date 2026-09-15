import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:image_picker/image_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFFEEE9E3),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  await FlutterDownloader.initialize(debug: true, ignoreSsl: true);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFEEE9E3),
        canvasColor: const Color(0xFFEEE9E3),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEEE9E3),
          surface: const Color(0xFFEEE9E3),
          brightness: Brightness.light,
        ),
      ),
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});
  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> with CodeAutoFill {
  late final WebViewController controller;
  bool isLoading = true;
  @override
  void initState() {
    super.initState();
    _initSmsListener();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFEEE9E3))
      ..setUserAgent(
        Platform.isIOS
            ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/605.1.15'
            : 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel(
        'FlutterShare',
        onMessageReceived: (JavaScriptMessage message) {
          _handleShareMessage(message.message);
        },
      )
      ..addJavaScriptChannel(
        'FlutterOTP',
        onMessageReceived: (JavaScriptMessage message) {
          _initSmsListener();
        },
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
    _checkForUpdate();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && isLoading) {
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  Future<void> _checkForUpdate() async {
    if (!Platform.isAndroid) return;
    try {
      final AppUpdateInfo info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else if (info.flexibleUpdateAllowed) {
          await InAppUpdate.startFlexibleUpdate();
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } catch (e) {
      debugPrint("InAppUpdate check error: $e");
    }
  }

  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    if (!mounted) return [];

    try {
      final String? selectedSource = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (BuildContext sheetContext) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              top: 12,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(sheetContext).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Upload Image / Proof',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF222222),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose Camera to take photo or Gallery to select',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildPickerOption(
                        icon: Icons.camera_alt_rounded,
                        label: 'Camera',
                        sublabel: 'Take Photo',
                        iconBgColor: const Color(0xFFE8F5E9),
                        iconColor: const Color(0xFF2E7D32),
                        onTap: () => Navigator.of(sheetContext).pop('camera'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildPickerOption(
                        icon: Icons.photo_library_rounded,
                        label: 'Gallery',
                        sublabel: 'Choose Image',
                        iconBgColor: const Color(0xFFFFF3E0),
                        iconColor: const Color(0xFFE65100),
                        onTap: () => Navigator.of(sheetContext).pop('gallery'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildPickerOption(
                        icon: Icons.folder_open_rounded,
                        label: 'Files',
                        sublabel: 'Browse Device',
                        iconBgColor: const Color(0xFFE3F2FD),
                        iconColor: const Color(0xFF1565C0),
                        onTap: () => Navigator.of(sheetContext).pop('files'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.of(sheetContext).pop(null),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );

      if (selectedSource == null) {
        return [];
      }

      final bool allowMultiple = params.mode == FileSelectorMode.openMultiple;
      final ImagePicker picker = ImagePicker();

      if (selectedSource == 'camera') {
        final XFile? photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (photo != null && photo.path.isNotEmpty) {
          return [Uri.file(photo.path).toString()];
        }
        return [];
      } else if (selectedSource == 'gallery') {
        if (allowMultiple) {
          final List<XFile> images = await picker.pickMultiImage(
            imageQuality: 85,
          );
          return images
              .where((file) => file.path.isNotEmpty)
              .map((file) => Uri.file(file.path).toString())
              .toList();
        } else {
          final XFile? image = await picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 85,
          );
          if (image != null && image.path.isNotEmpty) {
            return [Uri.file(image.path).toString()];
          }
          return [];
        }
      } else if (selectedSource == 'files') {
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
    } catch (e) {
      debugPrint("File picker error: $e");
    }
    return [];
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color iconBgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF222222),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
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
      String urlToLoad = 'https://www.nut-flix.in/';
      if (savedUrl != null &&
          savedUrl.isNotEmpty &&
          !_isPublicWebsiteUrl(savedUrl)) {
        urlToLoad = savedUrl;
      }
      controller.loadRequest(Uri.parse(urlToLoad));
    } catch (e) {
      controller.loadRequest(Uri.parse('https://www.nut-flix.in/'));
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

  void _handleShareMessage(String messageText) {
    try {
      String shareUrl = '';
      String shareTitle = '';
      String shareText = '';
      if (messageText.startsWith('{') && messageText.endsWith('}')) {
        final Map<String, dynamic> data = jsonDecode(messageText);
        shareUrl = data['url']?.toString() ?? '';
        shareTitle = data['title']?.toString() ?? '';
        shareText = data['text']?.toString() ?? '';
      } else {
        shareUrl = messageText;
      }

      if (shareUrl.isEmpty) {
        controller.currentUrl().then((url) {
          if (url != null && url.isNotEmpty) {
            // ignore: deprecated_member_use
            Share.share(url);
          }
        });
        return;
      }

      final String finalShareText =
          (shareText.isNotEmpty && !shareText.contains(shareUrl))
          ? '$shareText\n$shareUrl'
          : shareUrl;

      // ignore: deprecated_member_use
      Share.share(
        finalShareText,
        subject: shareTitle.isNotEmpty ? shareTitle : 'Nutflix',
      );
    } catch (e) {
      debugPrint('Error handling share: $e');
    }
  }

  @override
  void dispose() {
    SmsAutoFill().unregisterListener();
    cancel();
    super.dispose();
  }

  @override
  void codeUpdated() {
    debugPrint("SMS Code received: $code");
    if (code != null && code!.isNotEmpty) {
      final extractedOtp = _extractOtp(code!);
      if (extractedOtp.isNotEmpty) {
        _fillOtpInWebView(extractedOtp);
      }
    }
  }

  void _initSmsListener() async {
    try {
      await SmsAutoFill().listenForCode();
      listenForCode();
    } catch (e) {
      debugPrint("Error listening for SMS OTP: $e");
    }
  }

  String _extractOtp(String text) {
    final match = RegExp(r'\b\d{4,6}\b').firstMatch(text);
    return match != null ? match.group(0)! : '';
  }

  void _fillOtpInWebView(String otpCode) {
    if (otpCode.isEmpty) return;
    controller.runJavaScript('''
      if (typeof window.fillOtpCode === 'function') {
        window.fillOtpCode('$otpCode');
      }
    ''');
  }

  void _hideFooter() {
    controller.runJavaScript('''
      (function() {
        // Disable viewport zoom & pinch zoom
        let meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          (document.head || document.documentElement).appendChild(meta);
        }
        meta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no');

        // Prevent pinch zoom and double tap zoom events
        const zoomHandlerId = 'disable-zoom-handler';
        if (!window[zoomHandlerId]) {
          window[zoomHandlerId] = true;
          document.addEventListener('touchstart', function(e) {
            if (e.touches && e.touches.length > 1) {
              e.preventDefault();
            }
          }, { passive: false });

          let lastTouchEnd = 0;
          document.addEventListener('touchend', function(e) {
            const now = Date.now();
            if (now - lastTouchEnd <= 300) {
              e.preventDefault();
            }
            lastTouchEnd = now;
          }, false);

          document.addEventListener('gesturestart', function(e) {
            e.preventDefault();
          });
        }

        const styleId = 'hide-app-footer-style';
        let style = document.getElementById(styleId);
        if (!style) {
          style = document.createElement('style');
          style.id = styleId;
          (document.head || document.documentElement).appendChild(style);
        }
        style.innerHTML = 'html, body { touch-action: manipulation !important; -webkit-user-select: none; -webkit-tap-highlight-color: transparent; overscroll-behavior-y: none; } footer, .website-footer, body > footer { display: none !important; } .product-grid-container { grid-template-columns: repeat(2, 1fr) !important; }';

        // 1. Web Share & CanShare API Polyfill
        const sharePolyfillFn = function(shareData) {
          var url = (shareData && shareData.url) ? shareData.url : window.location.href;
          var title = (shareData && shareData.title) ? shareData.title : document.title;
          var text = (shareData && shareData.text) ? shareData.text : '';
          if (window.FlutterShare) {
            window.FlutterShare.postMessage(JSON.stringify({
              url: url,
              title: title,
              text: text
            }));
          }
          return Promise.resolve();
        };

        try {
          Object.defineProperty(navigator, 'share', {
            value: sharePolyfillFn,
            configurable: true,
            writable: true
          });
        } catch(e) {
          navigator.share = sharePolyfillFn;
        }

        try {
          Object.defineProperty(navigator, 'canShare', {
            value: function() { return true; },
            configurable: true,
            writable: true
          });
        } catch(e) {
          navigator.canShare = function() { return true; };
        }

        // 2. Clipboard writeText Interceptor
        const clipHandlerId = 'flutter-clip-handler';
        if (!window[clipHandlerId]) {
          window[clipHandlerId] = true;
          if (navigator.clipboard && navigator.clipboard.writeText) {
            const origWriteText = navigator.clipboard.writeText.bind(navigator.clipboard);
            navigator.clipboard.writeText = function(text) {
              if (text && typeof text === 'string' && (text.startsWith('http://') || text.startsWith('https://'))) {
                if (window.FlutterShare) {
                  window.FlutterShare.postMessage(JSON.stringify({
                    url: text,
                    title: document.title || 'Nutflix',
                    text: text
                  }));
                }
              }
              return origWriteText(text);
            };
          }
        }

        // 3. Robust Click Interceptor for Share Buttons
        const shareClickHandlerId = 'flutter-share-click-handler';
        if (!window[shareClickHandlerId]) {
          window[shareClickHandlerId] = true;
          document.addEventListener('click', function(e) {
            let target = e.target;
            const btn = (target && target.closest)
              ? target.closest('.product-share-btn, .share-btn, .share-button, [title*="Share" i], [aria-label*="Share" i], [data-action*="Share" i], svg.lucide-share2')
              : null;
            if (btn) {
              e.preventDefault();
              e.stopPropagation();
              e.stopImmediatePropagation();
              const currentUrl = window.location.href;
              const pageTitle = document.title || 'Nutflix';
              if (window.FlutterShare) {
                window.FlutterShare.postMessage(JSON.stringify({
                  url: currentUrl,
                  title: pageTitle,
                  text: 'Check out ' + pageTitle + ' on Nutflix!'
                }));
              }
            }
          }, true);
        }

        const handlerId = 'external-click-handler';
        if (!window[handlerId]) {
          window[handlerId] = true;
          document.addEventListener('click', function(e) {
            let target = e.target;
            const btn = (target && target.closest)
              ? target.closest('a, button, [role="button"], .whatsapp-btn, [data-action*="whatsapp" i]')
              : null;
            if (btn) {
              const href = btn.getAttribute ? (btn.getAttribute('href') || '') : '';
              if (href.includes('wa.me') || href.includes('whatsapp') || href.startsWith('whatsapp:') || href.startsWith('tel:') || href.startsWith('mailto:')) {
                return;
              }
              const text = (btn.innerText || btn.textContent || '').trim().toLowerCase();
              if (text.length < 80 && (text === 'chat on whatsapp' || text.includes('chat on whatsapp'))) {
                window.location.href = 'https://wa.me/919830055527';
                e.preventDefault();
              }
            }
          }, true);
        }
        // 4. OTP AutoFill Helper & DOM Tagging
        const otpInitId = 'flutter-otp-init-handler';
        if (!window[otpInitId]) {
          window[otpInitId] = true;
          window.fillOtpCode = function(otp) {
            if (!otp) return;
            const singleInputs = Array.from(document.querySelectorAll('input[type="text"], input[type="number"], input[type="tel"], input[autocomplete="one-time-code"]')).filter(function(el) {
              const attrs = ((el.name || '') + ' ' + (el.id || '') + ' ' + (el.placeholder || '') + ' ' + (el.className || '')).toLowerCase();
              return attrs.includes('otp') || attrs.includes('code') || attrs.includes('pin') || el.getAttribute('autocomplete') === 'one-time-code';
            });
            if (singleInputs.length > 0) {
              const input = singleInputs[0];
              input.value = otp;
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
              input.dispatchEvent(new Event('blur', { bubbles: true }));
              return;
            }
            const boxInputs = Array.from(document.querySelectorAll('input[maxlength="1"]'));
            if (boxInputs.length >= otp.length) {
              for (let i = 0; i < otp.length; i++) {
                boxInputs[i].value = otp[i];
                boxInputs[i].dispatchEvent(new Event('input', { bubbles: true }));
                boxInputs[i].dispatchEvent(new Event('change', { bubbles: true }));
                boxInputs[i].dispatchEvent(new Event('blur', { bubbles: true }));
              }
              return;
            }
            const anyInput = document.querySelector('input:not([type="hidden"]):not([type="checkbox"]):not([type="radio"])');
            if (anyInput) {
              anyInput.value = otp;
              anyInput.dispatchEvent(new Event('input', { bubbles: true }));
              anyInput.dispatchEvent(new Event('change', { bubbles: true }));
              anyInput.dispatchEvent(new Event('blur', { bubbles: true }));
            }
          };
          const setupOtpInputs = function() {
            const inputs = document.querySelectorAll('input');
            inputs.forEach(function(input) {
              const attrs = ((input.name || '') + ' ' + (input.id || '') + ' ' + (input.placeholder || '') + ' ' + (input.className || '')).toLowerCase();
              if (attrs.includes('otp') || attrs.includes('code') || attrs.includes('pin')) {
                if (!input.getAttribute('autocomplete')) {
                  input.setAttribute('autocomplete', 'one-time-code');
                }
                if (!input.getAttribute('inputmode')) {
                  input.setAttribute('inputmode', 'numeric');
                }
              }
            });
          };

          setupOtpInputs();
          const observer = new MutationObserver(function() {
            setupOtpInputs();
          });
          observer.observe(document.body || document.documentElement, { childList: true, subtree: true });

          document.addEventListener('click', function(e) {
            let target = e.target;
            const btn = (target && target.closest)
              ? target.closest('button, input[type="submit"], [role="button"], a')
              : null;
            if (btn) {
              const text = (btn.innerText || btn.textContent || btn.value || '').trim().toLowerCase();
              if (text.includes('otp') || text.includes('send') || text.includes('login') || text.includes('get code') || text.includes('resend')) {
                if (window.FlutterOTP) {
                  window.FlutterOTP.postMessage('listen');
                }
              }
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
            SafeArea(
              bottom: false,
              child: WebViewWidget(controller: controller),
            ),
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
