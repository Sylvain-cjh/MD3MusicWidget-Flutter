# GPU cover segmentation dependencies

The application runs local semantic foreground models using DirectML on
a system-selected hardware GPU, preferring an integrated adapter. CPU model
fallback is disabled; no application NPU interface is included.

## Model

Selection priority: reliable anime/human character, then detected text,
then another salient subject. A transparent source may reuse its own alpha.
No reliable split keeps the original cover; this is 2.5D, not full 3D geometry.

### Anime characters

- Author: SkyTNT, https://github.com/SkyTNT/anime-segmentation.
- Weights: https://huggingface.co/skytnt/anime-seg.
- Upstream isnetis.onnx, revision f559c9bd5eef0bf8de7f6a8cbab333738639e8b9.
- Original SHA256: F15622D853E8260172812B657053460E20806F04B9E05147D49AF7BED31A6E99.
- Weight repository explicitly declares Apache-2.0; full license retained in
  ANIME-MODEL-LICENSE. This declaration was checked on 2026-10-11.
- **Modified artifact**: anime-seg-fp16.onnx, converted offline to FP16 internal
  tensors with FP32 I/O; fixed spatial resize constants adapted from 1024 to
  512. This conversion is not new training or endorsement by the author.
- Converted SHA256: 5D33FD498733953C06F87962116B7F5671BCA130B6A1E95F9EA5CF374FFCB96F.
- Reproducible adaptation: tooling/prepare_cover_models.py, onnx 1.19.0 and
  onnxconverter-common 1.16.0. Python tools are not runtime dependencies.

### Human presence and segmentation

- NanoDet: RangiLyu/NanoDet; model port distributed by OpenCV/Open Source Vision
  Foundation, https://github.com/opencv/opencv_zoo/tree/main/models/object_detection_nanodet.
- Unmodified object_detection_nanodet_2022nov.onnx is renamed person-det.onnx.
  https://huggingface.co/opencv/object_detection_nanodet.
- SHA256: 4B82DA9944B88577175EE23A459DCE2E26E6E4BE573DEF65B1055DC2D9720186.
- PPHumanSeg: PaddlePaddle/PaddleHub, port distributed by OpenCV/Open Source
  Vision Foundation, https://github.com/opencv/opencv_zoo/tree/main/models/human_segmentation_pphumanseg.
- Unmodified human_segmentation_pphumanseg_2023mar.onnx is renamed human-seg.onnx.
  https://huggingface.co/opencv/human_segmentation_pphumanseg.
- SHA256: 552D8A984054E59B5D773D24B9B12022B22046CEB2BBC4C9AAEACEB36A9DDF24.
- Apache-2.0 licenses retained in PERSON-DETECTOR-LICENSE and HUMAN-MODEL-LICENSE.
- Person confidence across all three detector scales is checked on GPU before
  trusting the generic human segmentation mask; no host NMS or CPU inference.

### Optional difficult character attachments

- BiRefNet_lite by Zheng Peng et al., https://github.com/ZhengPeng7/BiRefNet.
- Static ONNX export distributed by CoderViking:
  https://huggingface.co/CoderViking/birefnet-lite-onnx,
  revision dc06453148f01ef4131f17e9b791345e32e8ee78.
- Source birefnet-lite-1024.onnx (FP32), 199,681,624 bytes;
  SHA256: 50A57872CC739192446DA2A934159F957C81AF8B5A161DFDA8E3DAA51660CA67.
- MIT model license retained in BIREFNET-MODEL-LICENSE. Checked 2026-10-12.
- **Modified artifact**: attachment-seg-fp16.onnx, 101,653,219 bytes;
  SHA256: 8BC7D72EB824A90B9A397614C1D52B030003EAE136D9F69E3F2D977142641BF1.
- Offline conversion: tooling/prepare_attachment_model.py with onnx 1.19.0 and
  onnxconverter-common 1.16.0. FP32 input/output and numerically sensitive
  LayerNormalization, GridSample, Softmax, Erf, ReduceMean, ReduceSum, Pow,
  Sqrt and Reciprocal operations are preserved; other supported internals use
  FP16. This is not retraining or an upstream endorsement, nor a claim of
  bit-exact parity with the publisher's FP32 model.
- Static 1024x1024 RGB/ImageNet-normalized input; output logits receive sigmoid
  on GPU. The export uses GridSample rather than GatherND/ScatterND chains.
  No remote Python code, PyTorch runtime or CPU model fallback is included.
- Only attempted when a reliable character has a diffuse/fragmented matte.
  The proposal must agree with trusted body anchors; disconnected components
  without sufficient body support are removed. Ordinary covers do not invoke
  this model. Missing/unsupported model or failed component filtering retains
  the established character matte. A generic foreground model cannot reliably
  separate every touching wing, cloud or ornament in flat illustrations.

### Text regions

- Upstream weights: Baidu/PaddleOCR. ONNX conversion by RapidAI/RapidOCR.
  https://github.com/RapidAI/RapidOCR, Apache-2.0.
- ch_PP-OCRv4_det_mobile.onnx, RapidOCR model release v3.9.2, renamed text-det.onnx.
- https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.9.2/onnx/PP-OCRv4/det/ch_PP-OCRv4_det_mobile.onnx.
- Unmodified SHA256: D2A7720D45A54257208B1E13E36A8479894CB74155A5EFE29462512D42F49DA9.
- Preferred independent lettering detector: ch_PP-OCRv5_det_mobile.onnx,
  RapidOCR model release v3.10.0, renamed text-det-v5.onnx; unmodified FP32.
- https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx.
- SHA256: 4D97C44A20D30A81AAD087D6A396B08F786C4635742AFC391F6621F5C6AE78AE.
- Publisher manifest: https://github.com/RapidAI/RapidOCR/blob/main/python/rapidocr/default_models.yaml.
- The v4 detector remains a compatibility fallback. Both conversions are
  distributed by RapidAI under Apache-2.0; weights and attribution checked on
  2026-10-11. Character contours take priority; only confident high-contrast ink
  is given an independent parallax layer. Ambiguous lettering stays attached.
- Full license retained in TEXT-MODEL-LICENSE. Only text detection is used;
  there is no recognition model, dictionary, OCR service, or image upload.

### Other salient subjects

- Architecture and license: https://github.com/xuebinqin/U-2-Net (Apache-2.0).
- ONNX conversion distributed by rembg:
  https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx
- Preprocessing contract and publisher checksum:
  https://github.com/danielgatis/rembg/blob/main/rembg/sessions/u2netp.py
- Model MD5: 8e83ca70e441ab06c318d82300c84806 (matches publisher).
- Model SHA256: 309C8469258DDA742793DCE0EBEA8E6DD393174F89934733ECC8B14C76F4DDD8.
- The upstream model license and rembg license are retained separately in
  MODEL-LICENSE and REMBG-LICENSE. This is foreground segmentation, not full
  3D reconstruction or semantic classification of every cover genre.

## ONNX Runtime DirectML

- Microsoft.ML.OnnxRuntime.DirectML 1.23.0, official NuGet package.
- Build commit: 0b2c4ac474a32ed700fd75435fb180ddfbbb4af6.
- onnxruntime.dll SHA256:
  F5131591EDAC6B0A8090D0E329040A49319D7A689CB5B465235FBF7030FA8027.
- ORT-LICENSE and ORT-NOTICES.txt retain upstream notices.
- https://www.nuget.org/packages/Microsoft.ML.OnnxRuntime.DirectML/1.23.0

## DirectML

- Microsoft.AI.DirectML 1.15.4, the matching official package dependency.
- DirectML.dll SHA256:
  9C9E6D822561C6C41B90E6994B3E8857CF1D66DBFB1E0C4C799C7C89B4E92DA1.
- Include/DirectML.h SHA256:
  3DAEED73AA64905C07B6F5394C7B45EABF0AC17BBCA54B1584C871E03E4F54AD.
- DIRECTML-LICENSE.txt and DIRECTML-NOTICES.txt retain the Microsoft
  redistribution terms and third-party notices. These are not MIT terms.
- https://www.nuget.org/packages/Microsoft.AI.DirectML/1.15.4

The three distributed Microsoft DLLs were verified as Microsoft-signed
binaries. Headers are build-only and excluded from runtime installation.
The application does not install drivers or change system graphics settings.
