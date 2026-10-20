import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/file_service.dart';

/// Pantalla de confirmación (RF-02): muestra la captura y pide un nombre.
///
/// "Aceptar" persiste el archivo (RF-04); cualquier otra salida lo borra
/// del directorio temporal (RF-03).
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    super.key,
    required this.tempPath,
    required this.isVideo,
  });

  final String tempPath;
  final bool isVideo;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final _files = const FileService();
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  VideoPlayerController? _video;
  bool _accepted = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.isVideo ? 'video' : 'foto';
    if (widget.isVideo) _initVideo();
  }

  /// Prepara y reproduce en bucle el video capturado.
  Future<void> _initVideo() async {
    final v = VideoPlayerController.file(File(widget.tempPath));
    _video = v;
    await v.initialize();
    await v.setLooping(true);
    if (!mounted) return;
    setState(() {});
    await v.play();
  }

  @override
  void dispose() {
    // RT-02: destruye el reproductor al salir de la pantalla.
    _video?.dispose();
    _nameCtrl.dispose();
    // RF-03: sin "Aceptar" el temporal se elimina de inmediato.
    if (!_accepted) _files.deleteTemp(widget.tempPath);
    super.dispose();
  }

  /// Valida el nombre y mueve el archivo al directorio persistente (RF-04).
  Future<void> _accept() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _video?.pause();
      await _files.saveToDocuments(widget.tempPath, _nameCtrl.text);
      _accepted = true;
      if (mounted) Navigator.of(context).pop(true);
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: ${e.message}')));
    }
  }

  void _cancel() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar captura')),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: Center(child: _buildMedia())),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del archivo',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || _files.sanitizeName(v).isEmpty) {
                    return 'Escribe un nombre';
                  }
                  return null;
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: _saving ? null : _cancel,
                    child: const Text('Cancelar')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                    onPressed: _saving ? null : _accept,
                    child: const Text('Aceptar')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Imagen o reproductor según el tipo de captura.
  Widget _buildMedia() {
    if (!widget.isVideo) return Image.file(File(widget.tempPath));
    final v = _video;
    if (v == null || !v.value.isInitialized) {
      return const CircularProgressIndicator();
    }
    return AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v));
  }
}
