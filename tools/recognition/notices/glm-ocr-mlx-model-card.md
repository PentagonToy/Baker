---
license: mit
language:
- zh
- en
- fr
- es
- ru
- de
- ja
- ko
pipeline_tag: image-to-text
library_name: transformers
tags:
- mlx
base_model:
- zai-org/GLM-OCR
---

# mlx-community/GLM-OCR-bf16
This model was converted to MLX format from [`zai-org/GLM-OCR`]() using mlx-vlm version **0.3.11**.
Refer to the [original model card](https://huggingface.co/zai-org/GLM-OCR) for more details on the model.
## Use with mlx

```bash
pip install -U mlx-vlm
```

```bash
python -m mlx_vlm.generate --model mlx-community/GLM-OCR-bf16 --max-tokens 100 --temperature 0.0 --prompt "Describe this image." --image <path_to_image>
```