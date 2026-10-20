# Reporte técnico – Control de hardware (cámara) en Flutter

## 1. Arquitectura por capas

| Capa | Archivo | Responsabilidad |
|---|---|---|
| Presentación | `lib/screens/camera_screen.dart` | Vista previa, modo foto/video, temporizador, ciclo de vida del hardware |
| Presentación | `lib/screens/preview_screen.dart` | Confirmación, renombrado, Aceptar/Cancelar |
| Presentación | `lib/screens/gallery_screen.dart` | Lista de archivos persistidos |
| Servicio | `lib/services/file_service.dart` | Temporal vs. persistente, limpieza |

Paquetes: `camera`, `video_player`, `path_provider`, `path`.

## 2. Aceleración por GPU (RT-01)

- `CameraPreview` renderiza con un widget `Texture(textureId)`. En Android el
  plugin crea una `SurfaceTexture` nativa y la cámara escribe los fotogramas
  directamente en ella; Flutter solo compone esa textura en la GPU.
- Los fotogramas **no pasan por la CPU ni por Dart**: la app nunca llama a
  `startImageStream` ni procesa arreglos `Uint8List` frame a frame, por lo que
  el hilo principal no se carga con copias de búferes.
- `AndroidManifest.xml` declara `android:hardwareAccelerated="true"` en
  `<application>` (y en `<activity>`).

## 3. Liberación de recursos (RT-02)

- `_CameraScreenState` usa `WidgetsBindingObserver`. En `inactive`, `paused` y
  `detached` se detiene cualquier grabación (descartando el video incompleto) y
  se llama `CameraController.dispose()`; en `resumed` se reinicializa.
- La limpieza de temporales en `paused`/`detached` se omite mientras la
  pantalla de confirmación está abierta, para no borrar un archivo aún sin
  decidir; al volver, si la cámara se liberó, se reinicializa.
- `dispose()` del widget quita el observer, cancela el `Timer` y libera el
  controlador.
- `PreviewScreen.dispose()` destruye el `VideoPlayerController`.
- Si el widget se destruye mientras `initialize()` está en curso, el
  controlador recién creado se libera igualmente (evita fuga).
- Al abrir la pantalla de confirmación se llama `pausePreview()` y al volver
  `resumePreview()`.
- La galería decodifica miniaturas con `cacheWidth` para reducir RAM.

## 4. Persistencia y limpieza (RF-03, RF-04)

- La cámara escribe en el directorio temporal (`getTemporaryDirectory()`).
- **Cancelar**, botón atrás o gesto de salida: `PreviewScreen.dispose()` borra
  el temporal si no se aceptó.
- **Aceptar**: `saveToDocuments` copia el archivo a
  `getApplicationDocumentsDirectory()/media/<nombre><ext>` (nombre saneado, sin
  sobrescribir) y elimina el temporal.
- `cleanTemporaryDirectory()` recorre y borra todo el directorio temporal al
  iniciar la pantalla, al pasar a segundo plano y al destruir el widget.

## 5. Mapa de requisitos

| Req. | Dónde |
|---|---|
| RF-01 | `camera_screen.dart` (`SegmentedButton`, `_fmt`, `Timer`) |
| RF-02 | `_goToPreview`, `PreviewScreen` (campo de nombre) |
| RF-03 | `deleteTemp`, `cleanTemporaryDirectory` |
| RF-04 | `saveToDocuments` |
| RT-01 | `CameraPreview`, manifest |
| RT-02 | `WidgetsBindingObserver`, `dispose()` |

## 6. Pruebas sugeridas (dispositivo real)

1. Foto → nombrar → Aceptar: aparece en la galería, temporal borrado.
2. Foto/video → Cancelar: no queda archivo en cache.
3. Grabar y enviar la app a segundo plano: la cámara se libera y el video
   parcial se descarta.
4. Revisar en Android Studio Profiler (Memory) que la RAM no crece tras varias
   capturas.
