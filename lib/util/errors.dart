import '../api/http_api.dart';
import '../l10n/app_strings.dart';

String uploadErrorMessage(Object error) {
  if (error is! ApiException) return strings.couldNotUploadImage(error);
  return switch (error.statusCode) {
    413 => strings.imageTooLarge,
    415 => strings.imageUnsupported,
    422 => strings.imageDimensionsTooBig,
    400 => strings.imageCorrupt,
    429 => strings.uploadRateLimited(error.retryAfter),
    _ => strings.couldNotUploadImage(error),
  };
}
