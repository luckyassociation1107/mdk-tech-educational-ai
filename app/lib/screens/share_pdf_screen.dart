import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../auth_models.dart';
import '../auth_store.dart';
import '../gofile_service.dart';
import '../widgets.dart';

/// Teacher/principal PDF shelf: upload PDFs to Gofile (free), publish the
/// link to the whole school or one class. Videos are NOT uploaded here —
/// they always come from the Playwright-automation engine. Free links
/// stay alive while students download them; the countdown + one-tap
/// refresh (a genuine re-upload) keeps them alive honestly.
class SharePdfScreen extends StatefulWidget {
  final AppUser user;
  const SharePdfScreen({super.key, required this.user});

  @override
  State<SharePdfScreen> createState() => _SharePdfScreenState();
}

class _SharePdfScreenState extends State<SharePdfScreen> {
  List<SharedPdf> _items = [];
  bool _loading = true;
  bool _uploading = false;
  final _classCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _classCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await AuthStore.sharedPdfs();
    final mine = all.where((e) => e.schoolId == widget.user.schoolId).toList();
    final s = widget.settings;
    if (s != null) {
      final cloud = await CatalogService.fetch(s);
      if (cloud.isNotEmpty) {
        final have = mine.map((p) => p.downloadPage).toSet();
        var i = 0;
        for (final e in cloud) {
          if (e.u.isEmpty || have.contains(e.u)) continue;
          have.add(e.u);
          mine.add(SharedPdf(
            id: 'cloud_${e.ts}_${i++}',
            title: e.t,
            fileId: '',
            downloadPage: e.u,
            sizeBytes: 0,
            schoolId: widget.user.schoolId,
            className: e.cls,
            uploadedById: '',
            uploadedByName: e.by,
            uploadedAtMillis: e.ts,
          ));
        }
        mine.sort((a, b) => b.uploadedAtMillis.compareTo(a.uploadedAtMillis));
      }
    }
    if (!mounted) return;
    setState(() {
      _items = mine;
      _loading = false;
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _size(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() => _uploading = true);
    try {
      final file = File(path);
      final up = await GofileService.uploadPdf(file: file, userId: widget.user.id);
      final pdf = SharedPdf(
        id: 'pdf${DateTime.now().millisecondsSinceEpoch}',
        title: up.name,
        fileId: up.fileId,
        downloadPage: up.downloadPage,
        sizeBytes: up.size,
        schoolId: widget.user.schoolId,
        className: _classCtrl.text.trim(),
        uploadedById: widget.user.id,
        uploadedByName: widget.user.name,
        uploadedAtMillis: DateTime.now().millisecondsSinceEpoch,
        localPath: path,
      );
      await AuthStore.addSharedPdf(pdf);
      var posted = false;
      final s = widget.settings;
      if (s != null) {
        posted = await CatalogService.post(
          s,
          CatalogEntry(
              t: up.name,
              u: up.downloadPage,
              by: widget.user.name,
              cls: _classCtrl.text.trim(),
              ts: DateTime.now().millisecondsSinceEpoch),
        );
      }
      _classCtrl.clear();
      _snack(posted ? 'PDF shared + added to the cloud catalog.' : 'PDF shared. Students can download it now.');
      _load();
    } catch (e) {
      _snack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _refresh(SharedPdf pdf) async {
    if (pdf.uploadedById != widget.user.id) {
      _snack('Only the teacher who uploaded this PDF can refresh it from their device.');
      return;
    }
    final file = File(pdf.localPath);
    if (!await file.exists()) {
      _snack('The original PDF is no longer on this device, so it cannot be re-uploaded.');
      return;
    }
    setState(() => _uploading = true);
    try {
      final up = await GofileService.uploadPdf(file: file, userId: widget.user.id);
      await AuthStore.updateSharedPdf(pdf.refreshed(fileId: up.fileId, downloadPage: up.downloadPage, sizeBytes: up.size));
      _snack('Link refreshed — 10 more days on the free shelf.');
      _load();
    } catch (e) {
      _snack('Refresh failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _remove(SharedPdf pdf) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Stop sharing this PDF?', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
        content: Text('“${pdf.title}” will disappear from student apps.', style: const TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (go != true) return;
    await AuthStore.removeSharedPdf(pdf.id);
    await GofileService.deleteFile(fileId: pdf.fileId, userId: widget.user.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Share PDFs', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
          GradientCard(
            gradient: AppColors.heroGradient,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.cloud_upload_rounded, color: Colors.white),
                SizedBox(width: 9),
                Text('Free PDF shelf (Gofile)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              ]),
              const SizedBox(height: 8),
              const Text('Upload a PDF and publish its link to your students. Lesson videos are generated by the teaching engine — only PDFs are shared here.',
                  style: TextStyle(color: Colors.white70, height: 1.5)),
              const SizedBox(height: 14),
              TextField(
                controller: _classCtrl,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  labelText: 'Class (blank = whole school)',
                  hintText: 'e.g. Class 10-A',
                  filled: true,
                  fillColor: AppColors.card,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _uploading ? null : _upload,
                  icon: _uploading
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_file_rounded, size: 19),
                  label: Text(_uploading ? 'Uploading…' : 'Upload & share PDF'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
          ),
          const SectionTitle('Shared with your school'),
          if (_loading)
            const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            const EmptyState(
              icon: Icons.picture_as_pdf_rounded,
              title: 'No PDFs shared yet',
              message: 'Upload the first PDF above. Students in your school/class will see it in their app and can download it into their phones.',
            )
          else
            ..._items.map((pdf) {
              final days = pdf.approxDaysLeft;
              final low = days <= 3;
              return Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: GradientCard(
                  padding: const EdgeInsets.all(15),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.red.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.red),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(pdf.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14)),
                          const SizedBox(height: 3),
                          Text('${_size(pdf.sizeBytes)} • ${pdf.className.isEmpty ? 'Whole school' : pdf.className} • by ${pdf.uploadedByName}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 11),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (low ? AppColors.amber : AppColors.teal).withOpacity(0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.hourglass_bottom_rounded, size: 13, color: low ? AppColors.amber : AppColors.teal),
                          const SizedBox(width: 5),
                          Text(days == 0 ? 'May retire anytime — refresh now' : '~$days day(s) left on free shelf',
                              style: TextStyle(color: low ? AppColors.amber : AppColors.teal, fontSize: 11.5, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                      const Spacer(),
                      if (pdf.id.startsWith('cloud_'))
                        const Text('CLOUD CATALOG', style: TextStyle(color: AppColors.teal, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.6))
                      else ...[
                        IconButton(tooltip: 'Refresh link (re-upload)', onPressed: _uploading ? null : () => _refresh(pdf), icon: const Icon(Icons.refresh_rounded, color: AppColors.teal)),
                        IconButton(tooltip: 'Stop sharing', onPressed: () => _remove(pdf), icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red)),
                      ],
                    ]),
                    Text(
                        pdf.id.startsWith('cloud_')
                            ? 'Added by another device through the cloud catalog. Manage it from the device that uploaded it.'
                            : 'Real student downloads also keep the link alive. Refresh re-uploads from this device.',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
                  ]),
                ),
              );
            }),
        ]),
      ),
    );
  }
}
