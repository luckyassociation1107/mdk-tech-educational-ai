import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_models.dart';
import '../auth_store.dart';
import '../catalog_service.dart';
import '../engine_gateway.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'exams_hub_screen.dart';
import 'report_screen.dart';
import 'textbook_screen.dart';

/// Student home — strictly read-only. The student sees only what their
/// teachers published for their school/class: read, watch, ask doubts,
/// take tests. There is no upload or generate control anywhere here.
class StudentHomeScreen extends StatefulWidget {
  final AppUser student;
  final EngineGateway gateway;
  final AppSettings settings;
  final VoidCallback onSignOut;
  const StudentHomeScreen({super.key, required this.student, required this.gateway, required this.settings, required this.onSignOut});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  List<PublishedBook> _books = [];
  List<SharedPdf> _sharedPdfs = [];
  Set<String> _openedPdfIds = {};
  String _schoolName = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final books = await AuthStore.visibleTo(widget.student);
    final pdfs = await AuthStore.visibleSharedPdfs(widget.student);
    final schools = await AuthStore.schools();
    final prefs = await SharedPreferences.getInstance();
    final opened = (prefs.getStringList('sharedpdf_opened_${widget.student.id}') ?? const []).toSet();
    if (!mounted) return;
    setState(() {
      _books = books;
      _sharedPdfs = pdfs;
      _openedPdfIds = opened;
      _schoolName = schools.where((s) => s.id == widget.student.schoolId).firstOrNull?.name ?? '';
      _loading = false;
    });
  }

  Future<void> _openPdf(SharedPdf pdf) async {
    final prefs = await SharedPreferences.getInstance();
    final opened = {..._openedPdfIds, pdf.id};
    await prefs.setStringList('sharedpdf_opened_${widget.student.id}', opened.toList());
    if (!mounted) return;
    setState(() => _openedPdfIds = opened);
    final uri = Uri.parse(pdf.downloadPage);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the download link.')));
    }
  }

  String _size(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final ids = _books.map((b) => b.sessionId).toSet();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 40), children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.face_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.student.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text)),
                  Text('$_schoolName${widget.student.className.isNotEmpty ? ' • ${widget.student.className}' : ''}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
              IconButton(tooltip: 'Sign out', onPressed: widget.onSignOut, icon: const Icon(Icons.logout_rounded, color: AppColors.muted)),
            ]),
            const SizedBox(height: 18),
            GradientCard(
              gradient: AppColors.heroGradient,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Your classroom is ready.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 6),
                const Text('Read your teacher’s published classes, watch the lessons, clear doubts and take tests. New parts unlock as you learn.',
                    style: TextStyle(color: Colors.white70, height: 1.5)),
              ]),
            ),
            const SectionTitle('Academics'),
            Row(children: [
              Expanded(
                child: GradientCard(
                  onTap: ids.isEmpty
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ExamsHubScreen(gateway: widget.gateway, settings: widget.settings, onlySessionIds: ids),
                          )),
                  padding: const EdgeInsets.all(16),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.quiz_rounded, color: AppColors.teal, size: 26),
                    SizedBox(height: 10),
                    Text('Exams & Tests', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 15)),
                    SizedBox(height: 3),
                    Text('Take tests on your published classes', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.45)),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientCard(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReportScreen(gateway: widget.gateway, settings: widget.settings),
                  )),
                  padding: const EdgeInsets.all(16),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.emoji_events_rounded, color: AppColors.amber, size: 26),
                    SizedBox(height: 10),
                    Text('My Report Card', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 15)),
                    SizedBox(height: 3),
                    Text('Marks, grades, rank & level', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.45)),
                  ]),
                ),
              ),
            ]),
            const SectionTitle('PDFs shared by your teachers'),
            if (!_loading && _sharedPdfs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('No PDFs shared yet. When a teacher shares one, download it here and keep it in your phone.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5)),
              )
            else
              ..._sharedPdfs.map((pdf) {
                final opened = _openedPdfIds.contains(pdf.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: GradientCard(
                    onTap: () => _openPdf(pdf),
                    padding: const EdgeInsets.all(15),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(color: AppColors.red.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.red),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(pdf.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14)),
                          const SizedBox(height: 3),
                          Text('${_size(pdf.sizeBytes)} • by ${pdf.uploadedByName}${pdf.className.isNotEmpty ? ' • ${pdf.className}' : ''}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (opened ? AppColors.green : AppColors.teal).withOpacity(0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(opened ? Icons.download_done_rounded : Icons.download_rounded, size: 14, color: opened ? AppColors.green : AppColors.teal),
                          const SizedBox(width: 5),
                          Text(opened ? 'Opened' : 'Download', style: TextStyle(color: opened ? AppColors.green : AppColors.teal, fontSize: 11.5, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ]),
                  ),
                );
              }),
            const SectionTitle('Published by your teachers'),
            if (_loading)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
            else if (_books.isEmpty)
              const EmptyState(
                icon: Icons.menu_book_rounded,
                title: 'Nothing published yet',
                message: 'When your teacher publishes a class for your school/class, it will appear here. You can then read it, watch lessons and take its tests.',
              )
            else
              ..._books.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GradientCard(
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TextbookScreen(
                            gateway: widget.gateway,
                            settings: widget.settings,
                            book: TextbookItem(sessionId: b.sessionId, title: b.title, pageCount: 0, state: 'published', brain: ''),
                            viewer: widget.student,
                          ),
                        ));
                        _load();
                      },
                      child: Row(children: [
                        Container(
                          width: 52,
                          height: 64,
                          decoration: BoxDecoration(gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.text, fontSize: 15)),
                            const SizedBox(height: 5),
                            Text('By ${b.publishedBy}${b.className.isNotEmpty ? ' • ${b.className}' : ' • Whole school'}',
                                style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                            const SizedBox(height: 4),
                            const Row(children: [
                              Icon(Icons.lock_rounded, size: 13, color: AppColors.teal),
                              SizedBox(width: 5),
                              Text('Read-only for students', style: TextStyle(color: AppColors.teal, fontSize: 11.5, fontWeight: FontWeight.w700)),
                            ]),
                          ]),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.muted),
                      ]),
                    ),
                  )),
          ]),
        ),
      ),
    );
  }
}
