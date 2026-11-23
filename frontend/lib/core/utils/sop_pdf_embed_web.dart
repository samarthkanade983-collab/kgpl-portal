import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../theme/app_theme.dart';

class SopPdfEmbed extends StatefulWidget {
  final String url;
  final double height;

  const SopPdfEmbed({super.key, required this.url, this.height = 620});

  @override
  State<SopPdfEmbed> createState() => _SopPdfEmbedState();
}

class _SopPdfEmbedState extends State<SopPdfEmbed> {
  static final Set<String> _registered = {};
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'sop-pdf-${widget.url.hashCode}';
    if (!_registered.contains(_viewType)) {
      _registered.add(_viewType);
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final iframe = web.HTMLIFrameElement()
          ..src = widget.url
          ..style.setProperty('width', '100%')
          ..style.setProperty('height', '100%')
          ..style.setProperty('border', 'none')
          ..style.setProperty('background', '#ffffff');
        iframe.setAttribute('title', 'SOP PDF document preview');
        return iframe;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}