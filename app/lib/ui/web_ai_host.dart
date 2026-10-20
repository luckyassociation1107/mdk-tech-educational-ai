import 'package:flutter/material.dart';

import '../ai/web_ai_engine.dart';
import '../widgets.dart';

/// Shows what the free AI is doing.
///
/// The website itself runs in a headless WebView (Android WebView / Windows
/// WebView2), so it needs no screen space. While a request is running this
/// small panel appears above the app with the live stage — "Uploading the
/// PDF… 40%", "The free AI is answering… 620 chars" — and can be dismissed.
class WebAiHost extends StatefulWidget {
  const WebAiHost({super.key, required this.child});
  final Widget child;

  @override
  State<WebAiHost> createState() => _WebAiHostState();
}

class _WebAiHostState extends State<WebAiHost> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    WebAiEngine.instance.busy.addListener(_onBusy);
    _expanded = WebAiEngine.instance.busy.value;
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
    return Stack(children: [
      widget.child,
      if (_expanded)
        Positioned(
          right: 12,
          bottom: 12,
          child: _Panel(onHide: () => setState(() => _expanded = false)),
        ),
    ]);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.onHide});
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
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                stage.isEmpty ? 'Working…' : stage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.muted, fontSize: 10.5, height: 1.35),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.teal),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Running in the background — the book stays on this device.',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: 10, height: 1.35),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
