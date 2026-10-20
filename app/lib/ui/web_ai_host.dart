import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../ai/web_ai_engine.dart';
import '../widgets.dart';

/// Hosts the single WebView that the free AI mode drives.
///
/// It lives above the navigator so the website session survives screen
/// changes (the PDF stays uploaded between the extraction and every lesson
/// script). While the site works, a small panel shows the live page and what
/// is happening — the teacher can see the automation, and it can be closed
/// with the stop button.
class WebAiHost extends StatefulWidget {
  const WebAiHost({super.key, required this.child});
  final Widget child;

  @override
  State<WebAiHost> createState() => _WebAiHostState();
}

class _WebAiHostState extends State<WebAiHost> {
  WebViewController? _controller;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Created up-front so switching the mode in Settings works without a
    // restart; nothing is loaded until the free mode is actually used.
    if (WebAiEngine.instance.supported) {
      final c = WebViewController();
      WebAiEngine.instance.attach(c);
      _controller = c;
    }
    WebAiEngine.instance.busy.addListener(_onBusy);
  }

  void _onBusy() {
    if (!mounted) return;
    setState(() => _expanded = WebAiEngine.instance.busy.value);
  }

  @override
  void dispose() {
    WebAiEngine.instance.busy.removeListener(_onBusy);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(children: [
      widget.child,
      if (controller != null && _expanded)
        Positioned(
          right: 12,
          bottom: 12,
          child: _Panel(
            controller: controller,
            onHide: () => setState(() => _expanded = false),
          ),
        ),
    ]);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.controller, required this.onHide});
  final WebViewController controller;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.stroke),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 22,
                spreadRadius: 2)
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
            child: Row(children: [
              Icon(Icons.public_rounded, size: 15, color: AppColors.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Free AI · website',
                    style: TextStyle(
                        color: AppColors.text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900)),
              ),
              InkWell(
                onTap: onHide,
                child: Icon(Icons.expand_more_rounded,
                    size: 18, color: AppColors.muted),
              ),
            ]),
          ),
          ValueListenableBuilder<String>(
            valueListenable: WebAiEngine.instance.stage,
            builder: (_, stage, __) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                stage.isEmpty ? 'Working…' : stage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.muted, fontSize: 10.5, height: 1.35),
              ),
            ),
          ),
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(15)),
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: WebViewWidget(controller: controller),
            ),
          ),
        ]),
      ),
    );
  }
}
