import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Why an image was refused, mirroring the backend's typed upload errors so
/// the same strings apply.
enum ImageRejection { tooLarge, unsupported, dimensions, corrupt }

class ImageRejected implements Exception {
  final ImageRejection reason;
  const ImageRejected(this.reason);
  @override
  String toString() => 'ImageRejected(${reason.name})';
}

/// The caps every image is checked against before a pixel buffer is
/// allocated. The defaults match the backend's.
class ImageLimits {
  final int maxBytes;
  final int maxWidth;
  final int maxHeight;
  final int maxPixels;
  final int thumbSize;

  const ImageLimits({
    this.maxBytes = 25 * 1024 * 1024,
    this.maxWidth = 8000,
    this.maxHeight = 8000,
    this.maxPixels = 40 * 1000 * 1000,
    this.thumbSize = 256,
  });
}

/// A sanitized image ready to encrypt: fresh bytes re-encoded from pixels,
/// so nothing of the original file (EXIF, ICC, comments, appended data)
/// survives, plus its thumbnail.
class PreparedImage {
  final Uint8List bytes;
  final String mime;
  final int width;
  final int height;
  final Uint8List thumb;
  final String thumbMime;
  final bool animated;

  const PreparedImage({
    required this.bytes,
    required this.mime,
    required this.width,
    required this.height,
    required this.thumb,
    required this.thumbMime,
    required this.animated,
  });
}

enum _Format { png, jpeg, gif, webp }

/// Only the leading bytes decide the format; the name and declared type
/// are never consulted.
_Format? _sniff(Uint8List b) {
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return _Format.png;
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return _Format.jpeg;
  }
  if (b.length >= 6 &&
      b[0] == 0x47 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x38 &&
      (b[4] == 0x37 || b[4] == 0x39) &&
      b[5] == 0x61) {
    return _Format.gif;
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return _Format.webp;
  }
  return null;
}

img.Decoder _decoderFor(_Format f) => switch (f) {
  _Format.png => img.PngDecoder(),
  _Format.jpeg => img.JpegDecoder(),
  _Format.gif => img.GifDecoder(),
  _Format.webp => img.WebPDecoder(),
};

/// Sanitizes an image the way the backend used to before uploads were
/// encrypted: sniff, header-only dimension check, decode as the sniffed
/// format, bake the EXIF orientation, re-encode from pixels, thumbnail.
/// Runs off the UI isolate.
Future<PreparedImage> prepareImage(
  Uint8List bytes, {
  ImageLimits limits = const ImageLimits(),
}) => compute(_prepare, _PrepareArgs(bytes, limits));

class _PrepareArgs {
  final Uint8List bytes;
  final ImageLimits limits;
  const _PrepareArgs(this.bytes, this.limits);
}

PreparedImage _prepare(_PrepareArgs args) {
  final bytes = args.bytes;
  final limits = args.limits;
  if (bytes.length > limits.maxBytes) {
    throw const ImageRejected(ImageRejection.tooLarge);
  }
  final format = _sniff(bytes);
  if (format == null) throw const ImageRejected(ImageRejection.unsupported);

  // Header first: a 10KB file declaring 60000×60000 must be refused before
  // a pixel buffer for it exists.
  final decoder = _decoderFor(format);
  final info = _guard(() => decoder.startDecode(bytes));
  if (info == null) throw const ImageRejected(ImageRejection.corrupt);
  final frames = decoder.numFrames() < 1 ? 1 : decoder.numFrames();
  checkDimensions(info.width, info.height, frames, limits);

  final decoded = _guard(() => decoder.decode(bytes));
  if (decoded == null) throw const ImageRejected(ImageRejection.corrupt);
  // The JPEG decoder bakes the EXIF orientation into the pixels itself, so
  // a rotated photo legitimately comes back with its axes swapped.
  final swapped =
      format == _Format.jpeg &&
      decoded.width == info.height &&
      decoded.height == info.width;
  if (!swapped &&
      (decoded.width != info.width || decoded.height != info.height)) {
    throw const ImageRejected(ImageRejection.corrupt);
  }

  final animated = format == _Format.gif && decoded.numFrames > 1;
  final upright = animated ? decoded : img.bakeOrientation(decoded);
  upright.exif.clear();
  for (final f in upright.frames) {
    f.exif.clear();
  }

  final Uint8List out;
  final String mime;
  switch (format) {
    case _Format.jpeg:
      out = img.encodeJpg(upright, quality: 85);
      mime = 'image/jpeg';
    case _Format.gif:
      out = img.encodeGif(upright, singleFrame: !animated);
      mime = 'image/gif';
    case _Format.png:
    case _Format.webp:
      out = img.encodePng(upright, singleFrame: true);
      mime = 'image/png';
  }

  final thumb = _thumbnail(upright, animated: animated, size: limits.thumbSize);
  return PreparedImage(
    bytes: out,
    mime: mime,
    width: upright.width,
    height: upright.height,
    thumb: thumb.$1,
    thumbMime: thumb.$2,
    animated: animated,
  );
}

/// The decoders throw on malformed input as readily as they return null;
/// either way the file is corrupt, never a crash.
T? _guard<T>(T? Function() decode) {
  try {
    return decode();
  } on ImageRejected {
    rethrow;
  } catch (_) {
    throw const ImageRejected(ImageRejection.corrupt);
  }
}

/// The check the receiver runs too: per-axis caps and a pixel budget that
/// an animation multiplies by its frame count.
void checkDimensions(int width, int height, int frames, ImageLimits limits) {
  if (width <= 0 || height <= 0) {
    throw const ImageRejected(ImageRejection.corrupt);
  }
  if (width > limits.maxWidth || height > limits.maxHeight) {
    throw const ImageRejected(ImageRejection.dimensions);
  }
  if (width * height * frames > limits.maxPixels) {
    throw const ImageRejected(ImageRejection.dimensions);
  }
}

(Uint8List, String) _thumbnail(
  img.Image image, {
  required bool animated,
  required int size,
}) {
  final longest = image.width > image.height ? image.width : image.height;
  if (animated) {
    if (longest <= size) {
      // Small enough already: the sanitized GIF is its own thumbnail.
      return (img.encodeGif(image), 'image/gif');
    }
    // Frames from the decoder are full composites (disposal already
    // applied), so each can be scaled on its own and keeps its delay.
    final scaled = img.Image(
      width: image.width > image.height
          ? size
          : (image.width * size / image.height).round().clamp(1, size),
      height: image.height >= image.width
          ? size
          : (image.height * size / image.width).round().clamp(1, size),
      numChannels: image.numChannels,
      loopCount: image.loopCount,
      frameType: img.FrameType.animation,
    );
    var first = true;
    for (final frame in image.frames) {
      final resized = img.copyResize(
        frame,
        width: scaled.width,
        height: scaled.height,
        interpolation: img.Interpolation.average,
      )..frameDuration = frame.frameDuration;
      if (first) {
        scaled.frames[0] = resized;
        scaled.frames[0].frameDuration = frame.frameDuration;
        first = false;
      } else {
        scaled.addFrame(resized);
      }
    }
    scaled.frameType = img.FrameType.animation;
    return (img.encodeGif(scaled, samplingFactor: 30), 'image/gif');
  }
  final still = image.numFrames > 1 ? image.frames.first : image;
  if (longest <= size) {
    return (img.encodePng(still, singleFrame: true), 'image/png');
  }
  final resized = img.copyResize(
    still,
    width: still.width >= still.height ? size : null,
    height: still.height > still.width ? size : null,
    interpolation: img.Interpolation.average,
  );
  return (img.encodePng(resized, singleFrame: true), 'image/png');
}

/// What a receiver learns from the header before decoding anything.
class ImageHeader {
  final int width;
  final int height;
  final int frames;
  const ImageHeader(this.width, this.height, this.frames);
}

/// Reads dimensions and frame count without allocating pixels; null when
/// the bytes are not a supported image at all.
ImageHeader? readImageHeader(Uint8List bytes) {
  final format = _sniff(bytes);
  if (format == null) return null;
  final decoder = _decoderFor(format);
  final img.DecodeInfo? info;
  try {
    info = decoder.startDecode(bytes);
  } catch (_) {
    return null;
  }
  if (info == null) return null;
  return ImageHeader(
    info.width,
    info.height,
    decoder.numFrames() < 1 ? 1 : decoder.numFrames(),
  );
}

/// The receiver-side gate: a decrypted blob is handed to the image widget
/// only if it is a supported format whose header fits the limits. A
/// sender's pipeline is not trusted — a modified client can upload anything.
void assertRenderable(
  Uint8List bytes, {
  ImageLimits limits = const ImageLimits(),
}) {
  if (bytes.length > limits.maxBytes) {
    throw const ImageRejected(ImageRejection.tooLarge);
  }
  final header = readImageHeader(bytes);
  if (header == null) throw const ImageRejected(ImageRejection.unsupported);
  checkDimensions(header.width, header.height, header.frames, limits);
}
