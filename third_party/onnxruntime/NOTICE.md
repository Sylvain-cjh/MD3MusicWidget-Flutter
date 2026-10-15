# DirectML cover segmentation C API headers

Only the unmodified C API headers from Microsoft ONNX Runtime v1.23.2 and its
MIT license are included here. DirectML runtime binaries and model attribution
are tracked separately in `third_party/cover_gpu/`.

Source: https://github.com/microsoft/onnxruntime/tree/v1.23.2/include/onnxruntime/core/session

SHA256:

- onnxruntime_c_api.h: 71125E66180A991D65C9BDBAD4AA20DAAA1F7A48C7A5C0FA5F18F250AC839A02
- onnxruntime_ep_c_api.h: B92778F50C36ECDF53D0344E0129A78B306AFED653F81BBA8A9597E3E6E9546F
- LICENSE: 2F07C72751AED99790B8A4869CF2311DF85A860B22DED05FA22803587A48922C

The additional dml_provider_factory.h comes from the same v1.23.2 source tree:
https://github.com/microsoft/onnxruntime/blob/v1.23.2/include/onnxruntime/core/providers/dml/dml_provider_factory.h

SHA256 dml_provider_factory.h:
F135B19B9EC96CD373A6A3B57D24E05324BF323EAF72734AE45CB4C34E174A95

The application uses DirectML hardware GPU execution with CPU inference
fallback disabled. There is no application-owned NPU interface. The headers
retain the complete upstream general-purpose API, not just the subset used.
