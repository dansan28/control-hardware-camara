import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Capa de persistencia: separa el almacenamiento temporal (cache) del
/// persistente (documents) y depura la basura temporal.
class FileService {
  const FileService();

  /// Directorio persistente donde viven los archivos confirmados.
  Future<Directory> _mediaDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'media'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// RF-03: elimina un archivo temporal; ignora si ya no existe.
  Future<void> deleteTemp(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on FileSystemException catch (_) {}
  }

  /// RF-03: borra todo el contenido de `getTemporaryDirectory()`.
  /// Devuelve cuántos elementos se eliminaron.
  Future<int> cleanTemporaryDirectory() async {
    var removed = 0;
    final tmp = await getTemporaryDirectory();
    if (!await tmp.exists()) return 0;
    await for (final entity in tmp.list()) {
      try {
        await entity.delete(recursive: true);
        removed++;
      } on FileSystemException catch (_) {}
    }
    return removed;
  }

  /// Reemplaza caracteres no válidos en nombres de archivo.
  String sanitizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  /// RF-04: mueve el temporal al directorio persistente con el nuevo nombre,
  /// conservando la extensión y sin sobrescribir archivos existentes.
  Future<File> saveToDocuments(String tempPath, String name) async {
    final dir = await _mediaDir();
    final ext = p.extension(tempPath);
    final base = sanitizeName(name);
    var target = File(p.join(dir.path, '$base$ext'));
    var i = 1;
    while (await target.exists()) {
      target = File(p.join(dir.path, '$base ($i)$ext'));
      i++;
    }
    final saved = await File(tempPath).copy(target.path);
    await deleteTemp(tempPath);
    return saved;
  }

  /// Lista los archivos confirmados, más recientes primero.
  Future<List<File>> listSaved() async {
    final dir = await _mediaDir();
    final files =
        await dir.list().where((e) => e is File).cast<File>().toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> deleteSaved(File file) => file.delete();
}
