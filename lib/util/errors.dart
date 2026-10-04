import '../api/http_api.dart';
import '../l10n/app_strings.dart';
import '../media/image_pipeline.dart';

String uploadErrorMessage(Object error) {
  if (error is! ApiException) return strings.couldNotUploadImage(error);
  return switch (error.statusCode) {
    413 => strings.imageTooLarge,
    415 => strings.imageUnsupported,
    422 => strings.imageDimensionsTooBig,
    400 => strings.imageCorrupt,
    429 => strings.uploadRateLimited(error.retryAfter),
    507 => strings.storageQuotaExceeded,
    _ => strings.couldNotUploadImage(error),
  };
}

String imageRejectionMessage(ImageRejection reason) => switch (reason) {
  ImageRejection.tooLarge => strings.imageTooLarge,
  ImageRejection.unsupported => strings.imageUnsupported,
  ImageRejection.dimensions => strings.imageDimensionsTooBig,
  ImageRejection.corrupt => strings.imageCorrupt,
};
