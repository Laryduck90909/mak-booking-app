import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';

class PickedFile {
  final String name;
  final Uint8List bytes;
  PickedFile(this.name, this.bytes);
}

/// يفتح منتقي الملفات ويتحقق من الحجم والامتداد. يعيد قائمة فارغة عند الإلغاء.
Future<List<PickedFile>> pickFiles(BuildContext context, {bool multiple = true, List<String>? ext}) async {
  final res = await FilePicker.platform.pickFiles(
    allowMultiple: multiple,
    type: FileType.custom,
    allowedExtensions: ext ?? AppConfig.allowedUploadExt,
    withData: true,
  );
  if (res == null) return [];
  final out = <PickedFile>[];
  for (final f in res.files) {
    final b = f.bytes;
    if (b == null) continue;
    if (b.length > AppConfig.maxUploadMb * 1024 * 1024) {
      if (context.mounted) {
        toast(context, t('الملف ${f.name} أكبر من ${AppConfig.maxUploadMb}MB', '${f.name} is larger than ${AppConfig.maxUploadMb}MB'), error: true);
      }
      continue;
    }
    out.add(PickedFile(f.name, b));
  }
  return out;
}

bool isImageName(String n) {
  final l = n.toLowerCase();
  return l.endsWith('.png') || l.endsWith('.jpg') || l.endsWith('.jpeg') || l.endsWith('.webp');
}

String shortName(String path) {
  final n = path.split('/').last;
  // نحذف البادئة الزمنية 1234567890_
  final m = RegExp(r'^\d{10,}_(.+)$').firstMatch(n);
  return m == null ? n : m.group(1)!;
}

/// يفتح ملفاً (رابط موقّع) في المتصفح/التطبيق الخارجي.
Future<void> openStoredFile(BuildContext context, String bucket, String path) async {
  try {
    final url = await repo.fileUrl(bucket, path);
    if (url.isEmpty) {
      if (context.mounted) toast(context, t('الملف غير متاح في الوضع التجريبي', 'File not available in demo mode'));
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) toast(context, errMsg(e), error: true);
  }
}

/// صورة بعلامة مائية "M.A.K • PREVIEW" (للمعاينات قبل السداد).
class WatermarkedImage extends StatelessWidget {
  final String url;
  final bool watermark;
  const WatermarkedImage({super.key, required this.url, this.watermark = true});

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      Image.network(url, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.broken_image_outlined, size: 40)),
      if (watermark)
        Positioned.fill(
          child: IgnorePointer(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (i) {
                return Transform.rotate(
                  angle: -0.5,
                  child: Text(
                    'M.A.K • PREVIEW    M.A.K • PREVIEW',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white.fade(0.38), shadows: const [Shadow(color: Colors.black54, blurRadius: 4)]),
                  ),
                );
              }),
            ),
          ),
        ),
    ]);
  }
}

/// لوحة ملفات طلب داخل مجلد/Bucket معيّن.
class FilesPanel extends StatefulWidget {
  final String title, bucket, orderId;
  final bool canUpload;
  final String uploadLabel;
  final List<String>? allowedExt;
  const FilesPanel({
    super.key, required this.title, required this.bucket, required this.orderId,
    this.canUpload = false, this.uploadLabel = '', this.allowedExt,
  });

  @override
  State<FilesPanel> createState() => _FilesPanelState();
}

class _FilesPanelState extends State<FilesPanel> {
  Future<void> _upload() async {
    final files = await pickFiles(context, ext: widget.allowedExt);
    if (files.isEmpty) return;
    for (final f in files) {
      await repo.uploadFile(widget.bucket, widget.orderId, f.name, f.bytes);
    }
    if (mounted) toast(context, t('تم رفع ${files.length} ملف', '${files.length} file(s) uploaded'));
  }

  Future<void> _open(FileRef f) async {
    if (widget.bucket == 'previews' && isImageName(f.name)) {
      try {
        final url = await repo.fileUrl(f.bucket, f.path);
        if (url.isEmpty) {
          if (mounted) toast(context, t('المعاينة غير متاحة في الوضع التجريبي', 'Preview not available in demo mode'));
          return;
        }
        if (!mounted) return;
        await showPanelDialog<void>(context, title: shortName(f.name), width: 720, builder: (ctx) => SizedBox(height: 420, child: WatermarkedImage(url: url)));
      } catch (e) {
        if (mounted) toast(context, errMsg(e), error: true);
      }
      return;
    }
    await openStoredFile(context, f.bucket, f.path);
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Panel(
      title: widget.title,
      trailing: widget.canUpload ? MakButton(widget.uploadLabel.isEmpty ? t('رفع ملف', 'Upload') : widget.uploadLabel, icon: Icons.upload_file, kind: 'soft', dense: true, onPressed: _upload) : null,
      child: AsyncData<List<FileRef>>(
        load: () => repo.listFiles(widget.bucket, widget.orderId),
        builder: (context, files) {
          if (files.isEmpty) return EmptyState(t('لا توجد ملفات', 'No files'), icon: Icons.folder_open);
          return Column(
            children: files.map((f) {
              return InkWell(
                onTap: () => _open(f),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(children: [
                    Icon(isImageName(f.name) ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 18, color: p.accent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(shortName(f.name), style: ts(p, size: 12.5, color: p.fg), overflow: TextOverflow.ellipsis)),
                    Icon(Icons.open_in_new, size: 15, color: p.muted),
                  ]),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
