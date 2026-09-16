// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element

import 'src/embeddings/compatible_embedding_model.dart' as p0;
import 'src/embeddings/embeddings.dart' as p1;
import 'src/errors.dart' as p2;
import 'src/generation/generation.dart' as p3;
import 'src/messages/messages.dart' as p4;
import 'src/models.dart' as p5;
import 'src/native.dart' as p6;
import 'src/protocols/sse.dart' as p7;
import 'src/settings.dart' as p8;
import 'src/tools/tools.dart' as p9;

void initializeMappers() {
  p0.EmbeddingOptionsMapper.ensureInitialized();
  p1.EmbeddingInputMapper.ensureInitialized();
  p1.EmbeddingRequestMapper.ensureInitialized();
  p1.EmbeddingCapabilitiesMapper.ensureInitialized();
  p1.EmbeddingResultMapper.ensureInitialized();
  p1.IndexedEmbeddingMapper.ensureInitialized();
  p1.EmbeddingBatchMapper.ensureInitialized();
  p2.AiErrorMapper.ensureInitialized();
  p2.InvalidRequestErrorMapper.ensureInitialized();
  p2.UnsupportedFeatureErrorMapper.ensureInitialized();
  p2.ProviderErrorMapper.ensureInitialized();
  p2.TransportErrorMapper.ensureInitialized();
  p2.ProtocolErrorMapper.ensureInitialized();
  p2.ResponseLimitErrorMapper.ensureInitialized();
  p2.ClientClosedErrorMapper.ensureInitialized();
  p2.DeliveryStateMapper.ensureInitialized();
  p3.GenerationOptionsMapper.ensureInitialized();
  p3.ResolvedGenerationOptionsMapper.ensureInitialized();
  p3.GenerationRequestMapper.ensureInitialized();
  p3.UsageMapper.ensureInitialized();
  p3.GenerationResultMapper.ensureInitialized();
  p3.GenerationEventMapper.ensureInitialized();
  p3.GenerationFinishedMapper.ensureInitialized();
  p3.ContentDeltaMapper.ensureInitialized();
  p3.TextDeltaMapper.ensureInitialized();
  p3.ReasoningDeltaMapper.ensureInitialized();
  p3.ToolArgumentsDeltaMapper.ensureInitialized();
  p3.GenerationStartedMapper.ensureInitialized();
  p3.PartStartedMapper.ensureInitialized();
  p3.PartDeltaMapper.ensureInitialized();
  p3.PartFinishedMapper.ensureInitialized();
  p3.UsageUpdatedMapper.ensureInitialized();
  p3.ProviderEventMapper.ensureInitialized();
  p3.FinishReasonMapper.ensureInitialized();
  p3.GenerationPartKindMapper.ensureInitialized();
  p4.MessageMapper.ensureInitialized();
  p4.UserMessageMapper.ensureInitialized();
  p4.AssistantMessageMapper.ensureInitialized();
  p4.InputPartMapper.ensureInitialized();
  p4.TextInputPartMapper.ensureInitialized();
  p4.OutputPartMapper.ensureInitialized();
  p4.TextOutputPartMapper.ensureInitialized();
  p4.ToolMessageMapper.ensureInitialized();
  p4.CitationMapper.ensureInitialized();
  p4.ProviderReplayMapper.ensureInitialized();
  p4.ReasoningOutputPartMapper.ensureInitialized();
  p4.RefusalOutputPartMapper.ensureInitialized();
  p4.OpaqueOutputPartMapper.ensureInitialized();
  p4.ToolCallPartMapper.ensureInitialized();
  p4.ProviderToolPartMapper.ensureInitialized();
  p4.ToolExecutionOwnerMapper.ensureInitialized();
  p4.ToolStatusMapper.ensureInitialized();
  p5.ModelCapabilitiesMapper.ensureInitialized();
  p5.CapabilitySupportMapper.ensureInitialized();
  p5.ModelCapabilityMapper.ensureInitialized();
  p6.ResponseMetadataMapper.ensureInitialized();
  p6.NativePayloadMapper.ensureInitialized();
  p6.NativeResponseMapper.ensureInitialized();
  p7.SseEventMapper.ensureInitialized();
  p8.SettingMapper.ensureInitialized();
  p8.InheritSettingMapper.ensureInitialized();
  p8.ValueSettingMapper.ensureInitialized();
  p8.ClearSettingMapper.ensureInitialized();
  p8.NativeFieldMapper.ensureInitialized();
  p9.FunctionToolMapper.ensureInitialized();
  p9.ToolChoiceMapper.ensureInitialized();
  p9.AutoToolChoiceMapper.ensureInitialized();
  p9.NoToolChoiceMapper.ensureInitialized();
  p9.RequiredToolChoiceMapper.ensureInitialized();
  p9.NamedToolChoiceMapper.ensureInitialized();
  p9.OutputFormatMapper.ensureInitialized();
  p9.TextOutputMapper.ensureInitialized();
  p9.JsonObjectOutputMapper.ensureInitialized();
  p9.JsonSchemaOutputMapper.ensureInitialized();
  p9.ToolArgumentsMapper.ensureInitialized();
  p9.JsonToolArgumentsMapper.ensureInitialized();
  p9.FreeFormToolArgumentsMapper.ensureInitialized();
  p9.NativeToolArgumentsMapper.ensureInitialized();
  p9.MalformedToolArgumentsMapper.ensureInitialized();
  p9.ToolResultContentMapper.ensureInitialized();
  p9.JsonToolResultContentMapper.ensureInitialized();
  p9.TextToolResultContentMapper.ensureInitialized();
  p9.NativeToolResultContentMapper.ensureInitialized();
  p9.ToolResultMapper.ensureInitialized();
  p9.ToolSuccessMapper.ensureInitialized();
  p9.ToolFailureMapper.ensureInitialized();
}

