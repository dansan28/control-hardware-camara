import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/file_service.dart';

/// Lista los archivos confirmados en el directorio persistente (RF-04).
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _files = const FileService();
  late Future<List<File>> _future = _files.listSaved();

  bool _isVideo(File f) =>
      const ['.mp4', '.mov', '.3gp'].contains(p.extension(f.path).toLowerCase());

  /// Elimina un archivo guardado y refresca la lista.
  Future<void> _delete(File f) async {
    await _files.deleteSaved(f);
    setState(() => _future = _files.listSaved());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archivos guardados')),
      body: FutureBuilder<List<File>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(child: Text('Aún no hay archivos.'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final f = items[i];
              return ListTile(
                leading: _isVideo(f)
                    ? const Icon(Icons.videocam, size: 40)
                    : Image.file(f,
                        width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 112),
                title: Text(p.basename(f.path)),
                trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(f)),
              );
            },
          );
        },
      ),
    );
  }
}
