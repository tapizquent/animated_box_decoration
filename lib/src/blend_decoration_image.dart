import 'dart:developer' as developer;
import 'dart:ui' as ui show Image;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter/material.dart';

/// The painter for a [BlendDecorationImage].
///
/// To obtain a painter, call [BlendDecorationImage.createPainter].
///
/// To paint, call [paint]. The `onChanged` callback passed to
/// [BlendDecorationImage.createPainter] will be called if the image needs to paint
/// again (e.g. because it is animated or because it had not yet loaded the
/// first time the [paint] method was called).
///
/// This object should be disposed using the [dispose] method when it is no
/// longer needed.
class BlendDecorationImagePainter {
  BlendDecorationImagePainter(this.details, this.onChanged)
      : assert(details != null);

  final DecorationImage details;
  final VoidCallback onChanged;

  ImageStream? _imageStream;
  ImageInfo? _image;

  /// Draw the image onto the given canvas.
  ///
  /// The image is drawn at the position and size given by the `rect` argument.
  ///
  /// The image is clipped to the given `clipPath`, if any.
  ///
  /// The `configuration` object is used to resolve the image (e.g. to pick
  /// resolution-specific assets), and to implement the
  /// [BlendDecorationImage.matchTextDirection] feature.
  ///
  /// If the image needs to be painted again, e.g. because it is animated or
  /// because it had not yet been loaded the first time this method was called,
  /// then the `onChanged` callback passed to [BlendDecorationImage.createPainter]
  /// will be called.
  void paint(Canvas canvas, Rect rect, Path? clipPath,
      ImageConfiguration configuration, BlendMode blendMode) {
    assert(canvas != null);
    assert(rect != null);
    assert(configuration != null);

    bool flipHorizontally = false;
    if (details.matchTextDirection) {
      assert(() {
        // We check this first so that the assert will fire immediately, not just
        // when the image is ready.
        if (configuration.textDirection == null) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary(
                'DecorationImage.matchTextDirection can only be used when a TextDirection is available.'),
            ErrorDescription(
              'When DecorationImagePainter.paint() was called, there was no text direction provided '
              'in the ImageConfiguration object to match.',
            ),
            DiagnosticsProperty<DecorationImage>(
                'The DecorationImage was', details,
                style: DiagnosticsTreeStyle.errorProperty),
            DiagnosticsProperty<ImageConfiguration>(
                'The ImageConfiguration was', configuration,
                style: DiagnosticsTreeStyle.errorProperty),
          ]);
        }
        return true;
      }());
      if (configuration.textDirection == TextDirection.rtl)
        flipHorizontally = true;
    }

    final ImageStream newImageStream = details.image.resolve(configuration);
    if (newImageStream.key != _imageStream?.key) {
      final ImageStreamListener listener = ImageStreamListener(
        _handleImage,
        onError: details.onError,
      );
      _imageStream?.removeListener(listener);
      _imageStream = newImageStream;
      _imageStream!.addListener(listener);
    }
    if (_image == null) return;

    if (clipPath != null) {
      canvas.save();
      canvas.clipPath(clipPath);
    }

    paintImage(
      canvas: canvas,
      rect: rect,
      blendMode: blendMode,
      image: _image!.image,
      debugImageLabel: _image!.debugLabel,
      scale: details.scale * _image!.scale,
      colorFilter: details.colorFilter,
      fit: details.fit,
      alignment: details.alignment.resolve(configuration.textDirection),
      centerSlice: details.centerSlice,
      repeat: details.repeat,
      flipHorizontally: flipHorizontally,
      opacity: details.opacity,
      filterQuality: details.filterQuality,
      invertColors: details.invertColors,
      isAntiAlias: details.isAntiAlias,
    );

    if (clipPath != null) canvas.restore();
  }

  void _handleImage(ImageInfo value, bool synchronousCall) {
    if (_image == value) return;
    if (_image != null && _image!.isCloneOf(value)) {
      value.dispose();
      return;
    }
    _image?.dispose();
    _image = value;
    assert(onChanged != null);
    if (!synchronousCall) onChanged();
  }

  /// Releases the resources used by this painter.
  ///
  /// This should be called whenever the painter is no longer needed.
  ///
  /// After this method has been called, the object is no longer usable.
  @mustCallSuper
  void dispose() {
    _imageStream?.removeListener(ImageStreamListener(
      _handleImage,
      onError: details.onError,
    ));
    _image?.dispose();
    _image = null;
  }

  @override
  String toString() {
    return '${objectRuntimeType(this, 'DecorationImagePainter')}(stream: $_imageStream, image: $_image) for $details';
  }
}

/// Used by [paintImage] to report image sizes drawn at the end of the frame.
Map<String, ImageSizeInfo> _pendingImageSizeInfo = <String, ImageSizeInfo>{};

/// [ImageSizeInfo]s that were reported on the last frame.
///
/// Used to prevent duplicative reports from frame to frame.
Set<ImageSizeInfo> _lastFrameImageSizeInfo = <ImageSizeInfo>{};

/// Flushes inter-frame tracking of image size information from [paintImage].
///
/// Has no effect if asserts are disabled.
@visibleForTesting
void debugFlushLastFrameImageSizeInfo() {
  assert(() {
    _lastFrameImageSizeInfo = <ImageSizeInfo>{};
    return true;
  }());
}

/// Paints an image into the given rectangle on the canvas.
///
/// The arguments have the following meanings:
///
///  * `canvas`: The canvas onto which the image will be painted.
///
///  * `rect`: The region of the canvas into which the image will be painted.
///    The image might not fill the entire rectangle (e.g., depending on the
///    `fit`). If `rect` is empty, nothing is painted.
///
///  * `image`: The image to paint onto the canvas.
///
///  * `scale`: The number of image pixels for each logical pixel.
///
///  * `opacity`: The opacity to paint the image onto the canvas with.
///
///  * `colorFilter`: If non-null, the color filter to apply when painting the
///    image.
///
///  * `fit`: How the image should be inscribed into `rect`. If null, the
///    default behavior depends on `centerSlice`. If `centerSlice` is also null,
///    the default behavior is [BoxFit.scaleDown]. If `centerSlice` is
///    non-null, the default behavior is [BoxFit.fill]. See [BoxFit] for
///    details.
///
///  * `alignment`: How the destination rectangle defined by applying `fit` is
///    aligned within `rect`. For example, if `fit` is [BoxFit.contain] and
///    `alignment` is [Alignment.bottomRight], the image will be as large
///    as possible within `rect` and placed with its bottom right corner at the
///    bottom right corner of `rect`. Defaults to [Alignment.center].
///
///  * `centerSlice`: The image is drawn in nine portions described by splitting
///    the image by drawing two horizontal lines and two vertical lines, where
///    `centerSlice` describes the rectangle formed by the four points where
///    these four lines intersect each other. (This forms a 3-by-3 grid
///    of regions, the center region being described by `centerSlice`.)
///    The four regions in the corners are drawn, without scaling, in the four
///    corners of the destination rectangle defined by applying `fit`. The
///    remaining five regions are drawn by stretching them to fit such that they
///    exactly cover the destination rectangle while maintaining their relative
///    positions.
///
///  * `repeat`: If the image does not fill `rect`, whether and how the image
///    should be repeated to fill `rect`. By default, the image is not repeated.
///    See [ImageRepeat] for details.
///
///  * `flipHorizontally`: Whether to flip the image horizontally. This is
///    occasionally used with images in right-to-left environments, for images
///    that were designed for left-to-right locales (or vice versa). Be careful,
///    when using this, to not flip images with integral shadows, text, or other
///    effects that will look incorrect when flipped.
///
///  * `invertColors`: Inverting the colors of an image applies a new color
///    filter to the paint. If there is another specified color filter, the
///    invert will be applied after it. This is primarily used for implementing
///    smart invert on iOS.
///
///  * `filterQuality`: Use this to change the quality when scaling an image.
///     Use the [FilterQuality.low] quality setting to scale the image, which corresponds to
///     bilinear interpolation, rather than the default [FilterQuality.none] which corresponds
///     to nearest-neighbor.
///
/// The `canvas`, `rect`, `image`, `scale`, `alignment`, `repeat`, `flipHorizontally` and `filterQuality`
/// arguments must not be null.
///
/// See also:
///
///  * [paintBorder], which paints a border around a rectangle on a canvas.
///  * [BlendDecorationImage], which holds a configuration for calling this function.
///  * [BoxDecoration], which uses this function to paint a [BlendDecorationImage].
void paintImage({
  required Canvas canvas,
  required Rect rect,
  required ui.Image image,
  required BlendMode blendMode,
  String? debugImageLabel,
  double scale = 1.0,
  double opacity = 1.0,
  ColorFilter? colorFilter,
  BoxFit? fit,
  Alignment alignment = Alignment.center,
  Rect? centerSlice,
  ImageRepeat repeat = ImageRepeat.noRepeat,
  bool flipHorizontally = false,
  bool invertColors = false,
  FilterQuality filterQuality = FilterQuality.low,
  bool isAntiAlias = false,
}) {
  assert(canvas != null);
  assert(image != null);
  assert(alignment != null);
  assert(repeat != null);
  assert(flipHorizontally != null);
  assert(isAntiAlias != null);
  assert(
    image.debugGetOpenHandleStackTraces()?.isNotEmpty ?? true,
    'Cannot paint an image that is disposed.\n'
    'The caller of paintImage is expected to wait to dispose the image until '
    'after painting has completed.',
  );
  if (rect.isEmpty) return;
  Size outputSize = rect.size;
  Size inputSize = Size(image.width.toDouble(), image.height.toDouble());
  Offset? sliceBorder;
  if (centerSlice != null) {
    sliceBorder = inputSize / scale - centerSlice.size as Offset;
    outputSize = outputSize - sliceBorder as Size;
    inputSize = inputSize - sliceBorder * scale as Size;
  }
  fit ??= centerSlice == null ? BoxFit.scaleDown : BoxFit.fill;
  assert(centerSlice == null || (fit != BoxFit.none && fit != BoxFit.cover));
  final FittedSizes fittedSizes =
      applyBoxFit(fit, inputSize / scale, outputSize);
  final Size sourceSize = fittedSizes.source * scale;
  Size destinationSize = fittedSizes.destination;
  if (centerSlice != null) {
    outputSize += sliceBorder!;
    destinationSize += sliceBorder;
    // We don't have the ability to draw a subset of the image at the same time
    // as we apply a nine-patch stretch.
    assert(sourceSize == inputSize,
        'centerSlice was used with a BoxFit that does not guarantee that the image is fully visible.');
  }

  if (repeat != ImageRepeat.noRepeat && destinationSize == outputSize) {
    // There's no need to repeat the image because we're exactly filling the
    // output rect with the image.
    repeat = ImageRepeat.noRepeat;
  }
  final Paint paint = Paint()..isAntiAlias = isAntiAlias;
  if (colorFilter != null) paint.colorFilter = colorFilter;
  paint.color = Color.fromRGBO(0, 0, 0, opacity);
  paint.filterQuality = filterQuality;
  paint.invertColors = invertColors;
  paint.blendMode = blendMode;
  final double halfWidthDelta =
      (outputSize.width - destinationSize.width) / 2.0;
  final double halfHeightDelta =
      (outputSize.height - destinationSize.height) / 2.0;
  final double dx = halfWidthDelta +
      (flipHorizontally ? -alignment.x : alignment.x) * halfWidthDelta;
  final double dy = halfHeightDelta + alignment.y * halfHeightDelta;
  final Offset destinationPosition = rect.topLeft.translate(dx, dy);
  final Rect destinationRect = destinationPosition & destinationSize;

  // Set to true if we added a saveLayer to the canvas to invert/flip the image.
  bool invertedCanvas = false;
  // Output size and destination rect are fully calculated.
  if (!kReleaseMode) {
    final ImageSizeInfo sizeInfo = ImageSizeInfo(
      // Some ImageProvider implementations may not have given this.
      source:
          debugImageLabel ?? '<Unknown Image(${image.width}×${image.height})>',
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      // It's ok to use this instead of a MediaQuery because if this changes,
      // whatever is aware of the MediaQuery will be repainting the image anyway.
      displaySize:
          outputSize * PaintingBinding.instance.window.devicePixelRatio,
    );
    assert(() {
      if (debugInvertOversizedImages &&
          sizeInfo.decodedSizeInBytes >
              sizeInfo.displaySizeInBytes + debugImageOverheadAllowance) {
        final int overheadInKilobytes =
            (sizeInfo.decodedSizeInBytes - sizeInfo.displaySizeInBytes) ~/ 1024;
        final int outputWidth = sizeInfo.displaySize.width.toInt();
        final int outputHeight = sizeInfo.displaySize.height.toInt();
        FlutterError.reportError(FlutterErrorDetails(
          exception: 'Image $debugImageLabel has a display size of '
              '$outputWidth×$outputHeight but a decode size of '
              '${image.width}×${image.height}, which uses an additional '
              '${overheadInKilobytes}KB.\n\n'
              'Consider resizing the asset ahead of time, supplying a cacheWidth '
              'parameter of $outputWidth, a cacheHeight parameter of '
              '$outputHeight, or using a ResizeImage.',
          library: 'painting library',
          context: ErrorDescription('while painting an image'),
        ));
        // Invert the colors of the canvas.
        canvas.saveLayer(
          destinationRect,
          Paint()
            ..colorFilter = const ColorFilter.matrix(<double>[
              -1,
              0,
              0,
              0,
              255,
              0,
              -1,
              0,
              0,
              255,
              0,
              0,
              -1,
              0,
              255,
              0,
              0,
              0,
              1,
              0,
            ]),
        );
        // Flip the canvas vertically.
        final double dy = -(rect.top + rect.height / 2.0);
        canvas.translate(0.0, -dy);
        canvas.scale(1.0, -1.0);
        canvas.translate(0.0, dy);
        invertedCanvas = true;
      }
      return true;
    }());
    // Avoid emitting events that are the same as those emitted in the last frame.
    if (!_lastFrameImageSizeInfo.contains(sizeInfo)) {
      final ImageSizeInfo? existingSizeInfo =
          _pendingImageSizeInfo[sizeInfo.source];
      if (existingSizeInfo == null ||
          existingSizeInfo.displaySizeInBytes < sizeInfo.displaySizeInBytes) {
        _pendingImageSizeInfo[sizeInfo.source!] = sizeInfo;
      }
      debugOnPaintImage?.call(sizeInfo);
      SchedulerBinding.instance.addPostFrameCallback((Duration timeStamp) {
        _lastFrameImageSizeInfo = _pendingImageSizeInfo.values.toSet();
        if (_pendingImageSizeInfo.isEmpty) {
          return;
        }
        developer.postEvent(
          'Flutter.ImageSizesForFrame',
          <String, Object>{
            for (ImageSizeInfo imageSizeInfo in _pendingImageSizeInfo.values)
              imageSizeInfo.source!: imageSizeInfo.toJson(),
          },
        );
        _pendingImageSizeInfo = <String, ImageSizeInfo>{};
      });
    }
  }

  final bool needSave =
      centerSlice != null || repeat != ImageRepeat.noRepeat || flipHorizontally;
  if (needSave) canvas.save();
  if (repeat != ImageRepeat.noRepeat) canvas.clipRect(rect);
  if (flipHorizontally) {
    final double dx = -(rect.left + rect.width / 2.0);
    canvas.translate(-dx, 0.0);
    canvas.scale(-1.0, 1.0);
    canvas.translate(dx, 0.0);
  }
  if (centerSlice == null) {
    final Rect sourceRect = alignment.inscribe(
      sourceSize,
      Offset.zero & inputSize,
    );
    if (repeat == ImageRepeat.noRepeat) {
      canvas.drawImageRect(image, sourceRect, destinationRect, paint);
    } else {
      for (final Rect tileRect
          in _generateImageTileRects(rect, destinationRect, repeat))
        canvas.drawImageRect(image, sourceRect, tileRect, paint);
    }
  } else {
    canvas.scale(1 / scale);
    if (repeat == ImageRepeat.noRepeat) {
      canvas.drawImageNine(image, _scaleRect(centerSlice, scale),
          _scaleRect(destinationRect, scale), paint);
    } else {
      for (final Rect tileRect
          in _generateImageTileRects(rect, destinationRect, repeat))
        canvas.drawImageNine(image, _scaleRect(centerSlice, scale),
            _scaleRect(tileRect, scale), paint);
    }
  }
  if (needSave) canvas.restore();

  if (invertedCanvas) {
    canvas.restore();
  }
}

Iterable<Rect> _generateImageTileRects(
    Rect outputRect, Rect fundamentalRect, ImageRepeat repeat) {
  int startX = 0;
  int startY = 0;
  int stopX = 0;
  int stopY = 0;
  final double strideX = fundamentalRect.width;
  final double strideY = fundamentalRect.height;

  if (repeat == ImageRepeat.repeat || repeat == ImageRepeat.repeatX) {
    startX = ((outputRect.left - fundamentalRect.left) / strideX).floor();
    stopX = ((outputRect.right - fundamentalRect.right) / strideX).ceil();
  }

  if (repeat == ImageRepeat.repeat || repeat == ImageRepeat.repeatY) {
    startY = ((outputRect.top - fundamentalRect.top) / strideY).floor();
    stopY = ((outputRect.bottom - fundamentalRect.bottom) / strideY).ceil();
  }

  return <Rect>[
    for (int i = startX; i <= stopX; ++i)
      for (int j = startY; j <= stopY; ++j)
        fundamentalRect.shift(Offset(i * strideX, j * strideY)),
  ];
}

Rect _scaleRect(Rect rect, double scale) => Rect.fromLTRB(rect.left * scale,
    rect.top * scale, rect.right * scale, rect.bottom * scale);
