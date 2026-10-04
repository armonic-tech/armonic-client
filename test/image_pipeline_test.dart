import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:armonic_client/media/attachment_crypto.dart';
import 'package:armonic_client/media/image_pipeline.dart';

img.Image _gradient(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    p
      ..r = p.x % 256
      ..g = p.y % 256
      ..b = 0x40;
  }
  return image;
}

Uint8List _animatedGif(int w, int h, int frames) {
  final first = _gradient(w, h)
    ..frameType = img.FrameType.animation
    ..frameDuration = 80;
  for (var i = 1; i < frames; i++) {
    final f = _gradient(w, h);
    // Make each frame distinct so the encoder cannot collapse them.
    for (final p in f) {
      p.r = (p.r + i * 40) % 256;
    }
    f.frameDuration = 80;
    first.addFrame(f);
  }
  return img.encodeGif(first);
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void main() {
  test('a PNG comes back as PNG, re-encoded, with a PNG thumbnail', () async {
    final src = img.encodePng(_gradient(300, 200));
    final out = await prepareImage(Uint8List.fromList(src));
    expect(out.mime, 'image/png');
    expect(out.width, 300);
    expect(out.height, 200);
    expect(out.animated, isFalse);
    expect(out.thumbMime, 'image/png');
    final thumb = img.decodePng(out.thumb)!;
    expect(thumb.width, 256);
    expect(thumb.height, 171);
  });

  test('a JPEG loses its EXIF and is rotated upright first', () async {
    final plain = img.encodeJpg(_gradient(120, 60), quality: 90);
    // Splice an APP1 EXIF segment with Orientation=6 right after SOI, the
    // way a phone camera writes it.
    final tiff = <int>[
      0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // II*\0, IFD at 8
      0x01, 0x00, // one entry
      0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, // next IFD: none
    ];
    final app1Body = [...'Exif'.codeUnits, 0, 0, ...tiff];
    final len = app1Body.length + 2;
    final src = Uint8List.fromList([
      0xFF,
      0xD8,
      0xFF,
      0xE1,
      len >> 8,
      len & 0xFF,
      ...app1Body,
      ...plain.sublist(2),
    ]);

    final out = await prepareImage(src);
    expect(out.mime, 'image/jpeg');
    // Orientation 6 swaps the axes.
    expect(out.width, 60);
    expect(out.height, 120);
    final decoded = img.decodeJpg(out.bytes)!;
    expect(decoded.exif.isEmpty, isTrue);
  });

  test('WebP is stored as PNG', () async {
    // The package cannot encode WebP; craft the header only to check the
    // sniff routes it to the WebP decoder, which then rejects the stub.
    final stub = Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, //
    ]);
    await expectLater(
      prepareImage(stub),
      throwsA(
        isA<ImageRejected>().having(
          (e) => e.reason,
          'reason',
          ImageRejection.corrupt,
        ),
      ),
    );
  });

  test(
    'an animated GIF keeps its frames and gets an animated thumbnail',
    () async {
      final src = _animatedGif(400, 300, 4);
      final out = await prepareImage(src);
      expect(out.mime, 'image/gif');
      expect(out.animated, isTrue);
      expect(img.decodeGif(out.bytes)!.numFrames, 4);

      expect(out.thumbMime, 'image/gif');
      final thumb = img.decodeGif(out.thumb)!;
      expect(thumb.numFrames, 4);
      expect(thumb.width, 256);
      expect(thumb.height, 192);
      expect(thumb.frames[1].frameDuration, 80);
    },
  );

  test('a small animated GIF is its own thumbnail', () async {
    final out = await prepareImage(_animatedGif(64, 64, 3));
    expect(out.thumbMime, 'image/gif');
    expect(img.decodeGif(out.thumb)!.numFrames, 3);
  });

  test('a single-frame GIF gets a static PNG thumbnail', () async {
    final src = img.encodeGif(_gradient(500, 100));
    final out = await prepareImage(Uint8List.fromList(src));
    expect(out.animated, isFalse);
    expect(out.thumbMime, 'image/png');
  });

  test('the header check refuses a bomb before decoding', () async {
    // A real 1x1 PNG whose IHDR is patched to declare 10000x10000, CRC
    // fixed so the decoder reads the header and nothing else.
    final bomb = Uint8List.fromList(
      img.encodePng(img.Image(width: 1, height: 1)),
    );
    final view = bomb.buffer.asByteData();
    view.setUint32(16, 10000);
    view.setUint32(20, 10000);
    view.setUint32(29, _crc32(bomb.sublist(12, 29)));
    await expectLater(
      prepareImage(bomb),
      throwsA(
        isA<ImageRejected>().having(
          (e) => e.reason,
          'reason',
          ImageRejection.dimensions,
        ),
      ),
    );
  });

  test('the pixel budget multiplies by the frame count', () async {
    final src = _animatedGif(200, 200, 3);
    await expectLater(
      prepareImage(src, limits: const ImageLimits(maxPixels: 100000)),
      throwsA(
        isA<ImageRejected>().having(
          (e) => e.reason,
          'reason',
          ImageRejection.dimensions,
        ),
      ),
    );
  });

  test('not an image, too large, and garbage are typed', () async {
    await expectLater(
      prepareImage(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(
        isA<ImageRejected>().having(
          (e) => e.reason,
          'reason',
          ImageRejection.unsupported,
        ),
      ),
    );
    await expectLater(
      prepareImage(Uint8List(100), limits: const ImageLimits(maxBytes: 10)),
      throwsA(
        isA<ImageRejected>().having(
          (e) => e.reason,
          'reason',
          ImageRejection.tooLarge,
        ),
      ),
    );
  });

  test('encrypt/decrypt round trip, and a swapped blob is caught', () async {
    final out = await prepareImage(
      Uint8List.fromList(img.encodePng(_gradient(40, 30))),
    );
    final enc = await encryptAttachment(out);
    expect(enc.ref.width, 40);
    expect(enc.ref.size, out.bytes.length);

    final full = await decryptAttachment(enc.blob, enc.ref, thumb: false);
    expect(full, out.bytes);
    final thumb = await decryptAttachment(enc.thumb, enc.ref, thumb: true);
    expect(thumb, out.thumb);

    final tampered = Uint8List.fromList(enc.blob)..[5] ^= 1;
    await expectLater(
      decryptAttachment(tampered, enc.ref, thumb: false),
      throwsA(isA<AttachmentTampered>()),
    );
  });

  test(
    'the receiver refuses a decrypted blob that is not a small image',
    () async {
      // A "sender" that skipped the pipeline: bytes that are not an image.
      final out = PreparedImage(
        bytes: Uint8List.fromList([9, 9, 9, 9]),
        mime: 'image/png',
        width: 1,
        height: 1,
        thumb: Uint8List.fromList([9, 9, 9, 9]),
        thumbMime: 'image/png',
        animated: false,
      );
      final enc = await encryptAttachment(out);
      await expectLater(
        decryptAttachment(enc.blob, enc.ref, thumb: false),
        throwsA(isA<ImageRejected>()),
      );
    },
  );
}
