import '../api/http_api.dart';
import '../l10n/app_strings.dart';
import '../media/image_pipeline.dart';

/// [featureMissingOn404]: a 404 from an upload route means the *route* is not
/// there — instances are self-hosted and run whatever version their operator
/// deployed, so an older one simply has no server-logo endpoint. Saying
/// "could not upload" there sends the user hunting for a problem with their
/// image.
String uploadErrorMessage(Object error, {bool featureMissingOn404 = false}) {
  if (error is! ApiException) return strings.couldNotUploadImage(error);
  if (error.statusCode == 404 && featureMissingOn404) {
    return strings.instanceTooOldForFeature;
  }
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
