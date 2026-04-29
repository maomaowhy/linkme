import 'dart:io';

import 'package:image_picker/image_picker.dart';

class PhotoService {
  PhotoService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<File?> takePhoto() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (photo == null || photo.path.isEmpty) return null;
    return File(photo.path);
  }
}
