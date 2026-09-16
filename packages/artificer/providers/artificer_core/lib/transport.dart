/// Provider HTTP support with bounded JSON decoding and scoped Dio ownership.
library;

export 'src/transport/provider_dio_adapter.dart' show ProviderDioAdapter;
export 'src/transport/provider_http_client.dart' show ProviderHttpClient, ProviderJsonResponse;
