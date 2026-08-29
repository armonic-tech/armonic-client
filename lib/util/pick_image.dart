import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class PickedImage {
  final Uint8List bytes;
  final String name;

  const PickedImage(this.bytes, this.name);
}

typedef ImagePicker = Future<PickedImage?> Function();

const _imageTypes = XTypeGroup(
  label: 'images',
  extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp'],
  mimeTypes: <String>['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
);

Future<PickedImage?> pickImageFile() async {
  final file = await openFile(acceptedTypeGroups: const [_imageTypes]);
  if (file == null) return null;
  return PickedImage(await file.readAsBytes(), file.name);
}