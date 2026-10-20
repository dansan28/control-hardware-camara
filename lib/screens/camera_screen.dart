import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/file_service.dart';
import 'gallery_screen.dart';
import 'preview_screen.dart';

/// Modo de captura activo (RF-01).
enum CaptureMode { photo, video }

/// Pantalla principal de captura de fotos y video (RF-01).
///
/// Usa [WidgetsBindingObserver] para liberar la cámara cuando la app deja de
/// estar activa (RT-02).
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final _files = const FileService();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  CaptureMode _mode = CaptureMode.photo;
  String? _error;
  bool _busy = false;
  bool _previewOpen = false;

  bool _recording = false;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _files.cleanTemporaryDirectory();
    _initCamera();
  }

  /// Crea e inicializa el controlador. [CameraPreview] dibuja con un `Texture`
  /// nativo (TextureId): la GPU compone los fotogramas sin pasar por la CPU.
  Future<void> _initCamera() async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No se encontró ninguna cámara.');
        return;
      }
      final controller = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: true,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      setState(() => _error = null);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  String _describe(CameraException e) {
    if (e.code.contains('Denied') || e.code.contains('Restricted')) {
      return 'Permiso de cámara/micrófono denegado. Actívalo en Ajustes.';
    }
    return 'Error de cámara: ${e.description ?? e.code}';
  }

  /// RT-02: libera el hardware y sus búferes de inmediato.
  Future<void> _releaseCamera() async {
    _stopTimer();
    final controller = _controller;
    _controller = null;
    _recording = false;
    if (mounted) setState(() {});
    await controller?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _suspendHardware();
        if (state != AppLifecycleState.inactive && !_previewOpen) {
          _files.cleanTemporaryDirectory();
        }
      case AppLifecycleState.resumed:
        if (_controller == null && !_previewOpen && !_busy) _initCamera();
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// Descarta una grabación en curso (quedaría incompleta) y libera la cámara.
  Future<void> _suspendHardware() async {
    final c = _controller;
    if (c != null && c.value.isRecordingVideo) {
      try {
        final f = await c.stopVideoRecording();
        await _files.deleteTemp(f.path);
      } on CameraException catch (_) {}
    }
    await _releaseCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    _files.cleanTemporaryDirectory();
    super.dispose();
  }

  Future<void> _onShutter() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    if (_mode == CaptureMode.photo) {
      await _takePhoto(c);
    } else if (_recording) {
      await _stopRecording(c);
    } else {
      await _startRecording(c);
    }
  }

  Future<void> _takePhoto(CameraController c) async {
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      await _goToPreview(c, shot.path, isVideo: false);
    } on CameraException catch (e) {
      _snack(_describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRecording(CameraController c) async {
    try {
      await c.startVideoRecording();
      _elapsed = Duration.zero;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
      });
      setState(() => _recording = true);
    } on CameraException catch (e) {
      _snack(_describe(e));
    }
  }

  Future<void> _stopRecording(CameraController c) async {
    setState(() => _busy = true);
    _stopTimer();
    try {
      final video = await c.stopVideoRecording();
      if (mounted) setState(() => _recording = false);
      await _goToPreview(c, video.path, isVideo: true);
    } on CameraException catch (e) {
      _snack(_describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// RF-02: pausa el stream y abre la pantalla de confirmación. Al volver
  /// reanuda la vista previa, o reinicia la cámara si se liberó mientras tanto.
  Future<void> _goToPreview(CameraController c, String path,
      {required bool isVideo}) async {
    await c.pausePreview();
    if (!mounted) return;
    _previewOpen = true;
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PreviewScreen(tempPath: path, isVideo: isVideo),
    ));
    _previewOpen = false;
    if (!mounted) return;
    if (_controller == null) {
      await _initCamera();
    } else if (_controller == c && c.value.isInitialized) {
      await c.resumePreview();
    }
  }

  /// Alterna entre cámaras disponibles liberando primero la actual.
  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _recording || _busy) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _releaseCamera();
    await _initCamera();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Formatea la duración como mm:ss.
  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(child: _buildPreview()),
          Positioned(top: 8, left: 8, right: 8, child: _buildTopBar()),
          Positioned(left: 0, right: 0, bottom: 16, child: _buildControls()),
        ]),
      ),
    );
  }

  /// Vista previa acelerada por GPU, o el estado de carga/error.
  Widget _buildPreview() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: 1 / c.value.aspectRatio,
        child: CameraPreview(c),
      ),
    );
  }

  /// Temporizador de grabación (RF-01) y acceso a la galería.
  Widget _buildTopBar() {
    return Row(children: [
      if (_recording)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: Colors.red, borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.fiber_manual_record,
                size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(_fmt(_elapsed),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
        ),
      const Spacer(),
      IconButton(
        icon: const Icon(Icons.photo_library, color: Colors.white),
        onPressed: _recording
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GalleryScreen())),
      ),
    ]);
  }

  /// Selector de modo, botón de disparo/grabación y cambio de cámara.
  Widget _buildControls() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!_recording)
        SegmentedButton<CaptureMode>(
          segments: const [
            ButtonSegment(
                value: CaptureMode.photo,
                icon: Icon(Icons.photo_camera),
                label: Text('Foto')),
            ButtonSegment(
                value: CaptureMode.video,
                icon: Icon(Icons.videocam),
                label: Text('Video')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        const SizedBox(width: 48),
        GestureDetector(
          onTap: _onShutter,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              color: _mode == CaptureMode.video
                  ? Colors.red
                  : Colors.white.withValues(alpha: 0.3),
            ),
            child: _recording
                ? const Icon(Icons.stop, color: Colors.white, size: 36)
                : null,
          ),
        ),
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.cameraswitch, color: Colors.white),
          onPressed: _switchCamera,
        ),
      ]),
    ]);
  }
}
