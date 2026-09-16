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
import 'src/settings.dart' as p7;
import 'src/tools/tools.dart' as p8;

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
  p3.FinishReasonMapper.ensureInitialized();
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
  p7.SettingMapper.ensureInitialized();
  p7.InheritSettingMapper.ensureInitialized();
  p7.ValueSettingMapper.ensureInitialized();
  p7.ClearSettingMapper.ensureInitialized();
  p7.NativeFieldMapper.ensureInitialized();
  p8.FunctionToolMapper.ensureInitialized();
  p8.ToolChoiceMapper.ensureInitialized();
  p8.AutoToolChoiceMapper.ensureInitialized();
  p8.NoToolChoiceMapper.ensureInitialized();
  p8.RequiredToolChoiceMapper.ensureInitialized();
  p8.NamedToolChoiceMapper.ensureInitialized();
  p8.OutputFormatMapper.ensureInitialized();
  p8.TextOutputMapper.ensureInitialized();
  p8.JsonObjectOutputMapper.ensureInitialized();
  p8.JsonSchemaOutputMapper.ensureInitialized();
  p8.ToolArgumentsMapper.ensureInitialized();
  p8.JsonToolArgumentsMapper.ensureInitialized();
  p8.FreeFormToolArgumentsMapper.ensureInitialized();
  p8.NativeToolArgumentsMapper.ensureInitialized();
  p8.MalformedToolArgumentsMapper.ensureInitialized();
  p8.ToolResultContentMapper.ensureInitialized();
  p8.JsonToolResultContentMapper.ensureInitialized();
  p8.TextToolResultContentMapper.ensureInitialized();
  p8.NativeToolResultContentMapper.ensureInitialized();
  p8.ToolResultMapper.ensureInitialized();
  p8.ToolSuccessMapper.ensureInitialized();
  p8.ToolFailureMapper.ensureInitialized();
}

