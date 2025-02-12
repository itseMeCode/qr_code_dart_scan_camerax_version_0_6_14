import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_code_dart_scan/src/qr_code_dart_scan_controller.dart';
import 'package:qr_code_dart_scan/src/util/extensions.dart';
import 'package:qr_code_dart_scan/src/util/image_decode_orientation.dart';
import 'package:qr_code_dart_scan/src/util/qr_code_dart_scan_resolution_preset.dart';
import 'package:zxing_lib/zxing.dart';

import 'decoder/qr_code_dart_scan_decoder.dart';

///
/// Created by
///
/// ─▄▀─▄▀
/// ──▀──▀
/// █▀▀▀▀▀█▄
/// █░░░░░█─█
/// ▀▄▄▄▄▄▀▀
///
/// Rafaelbarbosatec
/// on 12/08/21

enum TypeCamera { back, front }

enum TypeScan { live, takePicture }

typedef TakePictureButtonBuilder = Widget Function(
  BuildContext context,
  QRCodeDartScanController controller,
  bool loading,
);

class QRCodeDartScanView extends StatefulWidget {
  final TypeCamera typeCamera;
  final TypeScan typeScan;
  final ValueChanged<Result>? onCapture;
  final bool scanInvertedQRCode;

  /// Use to limit a specific format
  /// If null use all accepted formats
  final List<BarcodeFormat> formats;
  final QRCodeDartScanController? controller;
  final QRCodeDartScanResolutionPreset resolutionPreset;
  final Widget? child;
  final double? widthPreview;
  final double? heightPreview;
  final TakePictureButtonBuilder? takePictureButtonBuilder;
  final Duration intervalScan;
  final OnResultInterceptorCallback? onResultInterceptor;
  final DeviceOrientation? lockCaptureOrientation;
  final ImageDecodeOrientation imageDecodeOrientation;
  final ValueChanged<String>? onCameraError;
  const QRCodeDartScanView({
    Key? key,
    this.typeCamera = TypeCamera.back,
    this.typeScan = TypeScan.live,
    this.onCapture,
    this.scanInvertedQRCode = false,
    this.resolutionPreset = QRCodeDartScanResolutionPreset.medium,
    this.controller,
    this.formats = QRCodeDartScanDecoder.acceptedFormats,
    this.child,
    this.takePictureButtonBuilder,
    this.widthPreview,
    this.heightPreview,
    this.intervalScan = const Duration(seconds: 1),
    this.onResultInterceptor,
    this.lockCaptureOrientation,
    this.imageDecodeOrientation = ImageDecodeOrientation.original,
    this.onCameraError,
  }) : super(key: key);

  @override
  QRCodeDartScanViewState createState() => QRCodeDartScanViewState();
}

class QRCodeDartScanViewState extends State<QRCodeDartScanView> with WidgetsBindingObserver {
  late QRCodeDartScanController controller;
  bool initialized = false;
  bool _isControllerDisposed = false;
  Key _cameraKey = UniqueKey();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cameraController = controller.cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive && !_isControllerDisposed) {
      _isControllerDisposed = true;
      stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initController();
    }
    super.didChangeAppLifecycleState(state);
  }

  void stopCamera() {
    setState(() {
      controller.state.removeListener(_onStateListener);
      controller.dispose();
      initialized = false;
    });
  }

  void startCamera() {
    if (initialized) {
      return;
    }
    _initController();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    startCamera();
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
    controller.state.removeListener(_onStateListener);
    controller.dispose();
    _isControllerDisposed = true;
    initialized = false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: initialized ? _getCameraWidget(context) : widget.child,
    );
  }

  void _initController() async {
    controller = widget.controller ?? QRCodeDartScanController();
    _isControllerDisposed = false;
    controller.state.addListener(_onStateListener);
    await controller.config(
      widget.formats,
      widget.typeCamera,
      widget.typeScan,
      widget.scanInvertedQRCode,
      widget.imageDecodeOrientation,
      widget.resolutionPreset,
      widget.intervalScan,
      widget.onResultInterceptor,
      widget.lockCaptureOrientation,
      widget.onCameraError,
    );
  }

  Widget _buildButton() {
    return ValueListenableBuilder<PreviewState>(
      valueListenable: controller.state,
      builder: (context, value, child) {
        return widget.takePictureButtonBuilder?.call(
              context,
              controller,
              value.processing,
            ) ??
            _ButtonTakePicture(
              onTakePicture: controller.takePictureAndDecode,
              isLoading: value.processing,
            );
      },
    );
  }

  Widget _getCameraWidget(BuildContext context) {
    var camera = controller.cameraController!.value;
    // fetch screen size
    final size = MediaQuery.of(context).size;

    // calculate scale depending on screen and camera ratios
    // this is actually size.aspectRatio / (1 / camera.aspectRatio)
    // because camera preview size is received as landscape
    // but we're calculating for portrait orientation
    Size sizePreview = size;
    if (widget.widthPreview != null && widget.heightPreview != null) {
      sizePreview = Size(widget.widthPreview!, widget.heightPreview!);
    }

    var scale = sizePreview.aspectRatio * camera.aspectRatio;

    // // to prevent scaling down, invert the value
    if (scale < 1) scale = 1 / scale;

    return ClipRRect(
      child: SizedBox(
        key: _cameraKey,
        width: widget.widthPreview,
        height: widget.heightPreview,
        child: Stack(
          children: [
            Transform.scale(
              scale: scale,
              child: Center(
                child: CameraPreview(
                  controller.cameraController!,
                ),
              ),
            ),
            if (controller.state.value.typeScan == TypeScan.takePicture) _buildButton(),
            widget.child ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  void _onStateListener() {
    final state = controller.state.value;
    if (state.initialized != initialized) {
      postFrame(() {
        setState(() {
          _cameraKey = Key(state.typeCamera.toString());
          initialized = state.initialized;
        });
      });
    }
    if (state.result != null) {
      widget.onCapture?.call(state.result!);
    }
  }
}

class _ButtonTakePicture extends StatelessWidget {
  static const buttonContainerHeight = 150.0;
  static const buttonSize = 80.0;
  static const progressSize = 40.0;
  final VoidCallback onTakePicture;
  final bool isLoading;
  const _ButtonTakePicture({
    Key? key,
    required this.onTakePicture,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: buttonContainerHeight,
        color: Colors.black,
        child: Center(
          child: InkWell(
            onTap: onTakePicture,
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                          width: progressSize,
                          height: progressSize,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// If return true the newResult is passed in 'onCapture'
typedef OnResultInterceptorCallback = bool Function(
  Result? oldREsult,
  Result newResult,
);
