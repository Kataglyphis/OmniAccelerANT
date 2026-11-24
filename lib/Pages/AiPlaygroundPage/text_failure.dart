import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';

/// A failed turn as a sentence, OxidANT's English detail kept behind it; a new kind fails this switch until it has one.
String describeTextFailure(TextFailure failure, AppLocalizations l10n) {
  final detail = failure.message;
  return switch (failure.kind) {
    TextFailureKind.modelLoadFailed => l10n.aiErrorModelLoad(detail),
    TextFailureKind.libraryUnavailable => l10n.aiErrorLibrary(detail),
    TextFailureKind.providerUnavailable => l10n.aiErrorProvider(detail),
    TextFailureKind.endpointUnreachable ||
    TextFailureKind.endpointStatus => l10n.aiErrorEndpoint(detail),
    TextFailureKind.endpointTimedOut => l10n.aiErrorTimedOut(detail),
    TextFailureKind.invalidOptions => l10n.aiErrorInvalid(detail),
    TextFailureKind.tokenizerFailed => l10n.aiErrorTokenizer(detail),
    TextFailureKind.chatTemplateFailed => l10n.aiErrorChatTemplate(detail),
    TextFailureKind.encodeFailed => l10n.aiErrorEncode(detail),
    TextFailureKind.generationFailed => l10n.aiErrorGeneration(detail),
    TextFailureKind.streamLineTooLong => l10n.aiErrorStreamLine(detail),
    TextFailureKind.jsonSchemaUnsupported => l10n.aiErrorJsonSchema(detail),
    TextFailureKind.embeddingsUnsupported => l10n.aiErrorEmbeddings(detail),
    TextFailureKind.contextLengthExceeded => l10n.aiErrorContextLength(detail),
    TextFailureKind.noAnswer => l10n.aiErrorNoAnswer(detail),
  };
}
