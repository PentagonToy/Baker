---
tags:
- latex-ocr
- math-ocr
- math-formula-recognition
- mfr
- pix2text
- p2t
- image-to-text
license: mit
library_name: transformers
---

# Model Card: Pix2Text-MFR-1.5
Mathematical Formula Recognition (MFR) model from [Pix2Text (P2T)](https://github.com/breezedeus/Pix2Text).
**Version: 1.5**.

## Model Details / 模型细节

This MFR model utilizes the [TrOCR](https://huggingface.co/docs/transformers/model_doc/trocr) architecture developed by Microsoft, starting with its initial values and retrained using a dataset of mathematical formula images. 
The resulting MFR model can be used to convert images of mathematical formulas into LaTeX text representation. More detailed can be found: [Pix2Text V1.0 New Release: The Best Open-Source Formula Recognition Model | Breezedeus.com](https://www.breezedeus.com/article/p2t-v1.0).


此 MFR 模型使用了微软的 [TrOCR](https://huggingface.co/docs/transformers/model_doc/trocr) 架构，以其为初始值并利用数学公式图片数据集进行了重新训练。
获得的 MFR 模型可用于把数学公式图片转换为 LaTeX 文本表示。更多细节请见：[Pix2Text V1.0 新版发布：最好的开源公式识别模型 | Breezedeus.com](https://www.breezedeus.com/article/p2t-v1.0)。



## Usage and Limitations / 使用和限制

- **Purpose**: This model is a mathematical formula recognition model, capable of converting input images of mathematical formulas into LaTeX text representation.
- **Limitation**: Since the model is trained on images of mathematical formulas, it may not work when recognizing other types of images.


- **用途**：此模型为数学公式识别模型，它可以把输入的数学公式图片转换为 LaTeX 文本表示。
- **限制**：由于模型是在数学公式图片数据上训练的，它在识别其他类型的图片时可能无法工作。



## Documents / 文档
- [Pix2Text New Mathematical Formula Detection and Recognition Models：V1.5 | Breezedeus.com](https://www.breezedeus.com/article/pix2text-model-1.5) ;
- [Pix2Text V1.0 New Release: The Best Open-Source Formula Recognition Model | Breezedeus.com](https://www.breezedeus.com/article/p2t-v1.0) ;
- Pix2Text (P2T) Github: [breezedeus/pix2text](https://github.com/breezedeus/Pix2Text) ;
- Pix2Text Online Free Service: [p2t.breezedeus.com](https://p2t.breezedeus.com/) ;
- Pix2Text Online Docs: [Docs](https://pix2text.readthedocs.io) ;
- Pix2Text More: [breezedeus.com/pix2text](https://breezedeus.com/article/pix2text) ;
- Pix2Text Discard: https://discord.gg/GgD87WM8Tf


## Examples / 示例

### Printed Math Formula Images / 印刷体公式图片

![printed-formula examples](https://www.notion.so/image/https%3A%2F%2Fprod-files-secure.s3.us-west-2.amazonaws.com%2F9341931a-53f0-48e1-b026-0f1ad17b457c%2F26046b54-ae87-4faa-ab18-9acda74fd920%2FUntitled.jpeg?table=block&id=f422e590-4465-4648-8edd-ce2e1b00d959)


### Handwritten Math Formula Images / 印刷体公式图片

![handwritten-formula examples](https://www.notion.so/image/https%3A%2F%2Fprod-files-secure.s3.us-west-2.amazonaws.com%2F9341931a-53f0-48e1-b026-0f1ad17b457c%2Fcdbebff6-5b01-4e2a-a6f0-250da5cc39fe%2FUntitled.jpeg?table=block&id=e1029b05-25c5-40f0-9c3e-505744c0afa5)


## Model Use / 模型使用

### Method 1: Using the model Directly

This method doesn't need to install pix2text, but can only recognize pure formula images.

这种方法无需安装 pix2text，但只能识别纯公式图片。

```python
#! pip install transformers>=4.37.0 pillow optimum[onnxruntime]
from PIL import Image
from transformers import TrOCRProcessor
from optimum.onnxruntime import ORTModelForVision2Seq

processor = TrOCRProcessor.from_pretrained('breezedeus/pix2text-mfr-1.5')
model = ORTModelForVision2Seq.from_pretrained('breezedeus/pix2text-mfr-1.5', use_cache=False)

image_fps = [
    'examples/example.jpg',
    'examples/42.png',
    'examples/0000186.png',
]
images = [Image.open(fp).convert('RGB') for fp in image_fps]
pixel_values = processor(images=images, return_tensors="pt").pixel_values
generated_ids = model.generate(pixel_values)
generated_text = processor.batch_decode(generated_ids, skip_special_tokens=True)
print(f'generated_ids: {generated_ids}, \ngenerated text: {generated_text}')

```

### Method 2: Using Pix2Text

This method requires the installation of pix2text, utilizing the Mathematical Formula Detection model (MFD) within Pix2Text. It is capable of recognizing not only pure formula images but also mixed images containing text.

这种方法需要安装 pix2text，借助 Pix2Text 中的数学公式检测模型（MFD），它不仅可以识别纯公式图片，还可以识别包含文本的混合图片。

```bash
$ pip install pix2text>=1.1
```

```python
#! pip install pix2text>=1.1.4

from pix2text import Pix2Text, merge_line_texts

image_fps = [
    'examples/example.jpg',
    'examples/42.png',
    'examples/0000186.png',
]
p2t = Pix2Text.from_config()
outs = p2t.recognize_formula(image_fps)  # recognize pure formula images

outs2 = p2t.recognize('examples/mixed.jpg', file_type='text_formula', return_text=True, save_analysis_res='mixed-out.jpg')  # recognize mixed images
print(outs2)
```

### Method 3: Notebook

Just try Pix2Text with this notebook: [https://github.com/breezedeus/Pix2Text/blob/main/pix2text_v1_1.ipynb](https://github.com/breezedeus/Pix2Text/blob/main/pix2text_v1_1.ipynb).


## Performance / 性能

The original images for the test data are derived from real data uploaded by users on the [Pix2Text Online Service](https://p2t.breezedeus.com). Initially, real user data from a specific period is selected, and then the Mathematical Formula Detection model (MFD) within Pix2Text is used to detect the mathematical formulas in these images and crop the corresponding parts. A subset of these formula images is then randomly chosen for manual annotation to create the test dataset. The following image shows some sample pictures from the test dataset. It is evident that the images in the test dataset are quite diverse, including mathematical formulas of various lengths and complexities, from single letters to formula groups and even matrices. This test dataset includes `485` images.

测试数据对应的原始图片来源于 [Pix2Text 网页版](https://p2t.breezedeus.com) 用户上传的真实数据。首先选取一段时间内用户的真实数据，然后利用 Pix2Text 中数学公式检测模型（MFD）检测出这些图片中的数学公式并截取出对应的部分，再从中随机选取部分公式图片进行人工标注。就获得了用于测试的测试数据集了。下图是测试数据集中的部分样例图片。从中可以看出测试数据集中的图片比较多样，包括了各种不同长度和复杂度的数学公式，有单个字母的图片，也有公式组甚至矩阵图片。本测试数据集包括了 `485` 张图片。

![Examples from test data](https://www.notion.so/image/https%3A%2F%2Fprod-files-secure.s3.us-west-2.amazonaws.com%2F9341931a-53f0-48e1-b026-0f1ad17b457c%2Ffb23b2d4-cdcf-46c9-9095-027591402a54%2FUntitled.png?table=block&id=269900d5-299a-4dcd-a26c-6555e831caff)

Below are the Character Error Rates (CER, the lower, the better) of various models on this test dataset. For the true annotated results, as well as the output of each model, normalization was first performed to ensure that irrelevant factors such as spaces do not affect the test outcomes. For the recognition results of Texify, the leading and trailing symbols `$` or `$$` of the formula are removed first.

以下是各个模型在此测试数据集上的 CER（字错误率，越小越好）。其中对真实标注结果，以及每个模型的输出都首先进行了标准化，以保证不会因为空格等无关因素影响测试结果。对 Texify 的识别结果会首先去掉公式的首尾符号$或$$。

![CER Comparison Among Different MFR Models](https://www.notion.so/image/https%3A%2F%2Fprod-files-secure.s3.us-west-2.amazonaws.com%2F9341931a-53f0-48e1-b026-0f1ad17b457c%2F976b6c14-879d-4a3b-b027-6d2b15ce28b3%2FUntitled.png?table=block&id=6c503402-9b34-4937-a103-e4fd3bdbe754)

As can be seen from the figure above, the Pix2Text V1.0 MFR open-source free version model has significantly outperformed the previous versions of the paid model. Moreover, compared to the V1.0 MFR open-source free model, the precision of the Pix2Text V1.0 MFR paid model has been further improved.

由上图可见，Pix2Text V1.0 MFR 开源免费版模型已经大大优于之前版本的付费模型。而相比 V1.0 MFR 开源免费模型，Pix2Text V1.0 MFR 付费模型精度得到了进一步的提升。

> [Texify](https://github.com/VikParuchuri/texify) is more suited for recognizing images with standard formatting. It performs poorly in recognizing images containing single letters. This is the main reason why Texify's performance on this test dataset is inferior to that of Latex-OCR.
> 
> [Texify](https://github.com/VikParuchuri/texify) 更适用于识别标准排版的图片，它对包含单字母的图片识别较差。这也是 Texify 在此测试数据集上效果比 Latex-OCR 还差的主要原因。


## Feedback / 反馈

> Where to send questions or comments about the model.

Welcome to contact the author [Breezedeus](https://www.breezedeus.com/article/join-group).

欢迎联系作者  [Breezedeus](https://www.breezedeus.com/article/join-group) 。
