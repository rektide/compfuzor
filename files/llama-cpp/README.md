# HuggingFace GGUF JSON Variant Scraper

A Node.js script to scrape all quantization variants from HuggingFace GGUF model pages.

## Installation

No additional dependencies required - uses native Node.js modules.

## Usage

```bash
node scrape-gguf-variants.mjs <model-url>
```

**Example:**
```bash
node scrape-gguf-variants.mjs https://huggingface.co/bartowski/Nanbeige_Nanbeige4-3B-Thinking-2511-GGUF
```

**Output:**
JSON file saved to `files/llama-cpp/<model-name>.json`

## Output Format

The script creates a JSON file containing an array of variant objects:

```json
[
  {
    "filename": "Nanbeige_Nanbeige4-3B-Thinking-2511-Q2_K.gguf",
    "url": "https://huggingface.co/bartowski/Nanbeige_Nanbeige4-3B-Thinking-2511-GGUF/blob/main/Nanbeige_Nanbeige4-3B-Thinking-2511-Q2_K.gguf",
    "quantType": "Q2_K",
    "size": "1.62GB",
    "split": false,
    "description": "Very low quality but surprisingly usable."
  }
]
```

### Fields

- `filename`: The GGUF filename
- `url`: Direct URL to the file on HuggingFace
- `quantType`: Quantization type (e.g., Q2_K, IQ3_M, BF16)
- `size`: File size (e.g., 1.62GB)
- `split`: Whether the file is split across multiple parts
- `description`: Optional description of the quantization

## Parsing Strategy

The script uses a hybrid approach:

1. **Primary Method**: Parse HTML table structure to extract variant information
   - More robust to page structure changes
   - Extracts full metadata (filename, quant type, size, description)

2. **Fallback Method**: Parse embedded JSON from `data-props` attribute
   - Faster if table parsing fails
   - Provides basic filename list

## Features

- Extracts all quantization variants from GGUF model pages
- Handles various quantization formats (Q-series, I-series, BF16)
- Captures file sizes and descriptions
- Error handling and logging
- Automatic output directory creation

## Quantization Types

The script can识别以下 quantization types:

- **2-bit**: Q2_K, IQ2_M, Q2_K_L
- **3-bit**: IQ3_XXS, IQ3_XS, Q3_K_S, IQ3_M, Q3_K_M, Q3_K_L, Q3_K_XL
- **4-bit**: IQ4_XS, Q4_K_S, IQ4_NL, Q4_0, Q4_1, Q4_K_L, Q4_K_M
- **5-bit**: Q5_K_S, Q5_K_M
- **6-bit**: Q6_K, Q6_K_L
- **8-bit**: Q8_0
- **16-bit**: BF16

## About lol-html

Note: While lol-html was requested for this project, it is primarily designed as an **HTML rewriter** for streaming HTML modification, not as a parser for data extraction. lol-html's strength is in rewriting HTML content efficiently as it streams through, using CSS selectors to identify elements to modify.

For this scraping use case, direct string/regex parsing is more appropriate and provides the functionality needed. The script could be adapted to use lol-html's `HTMLRewriter` class if needed for complex HTML transformation scenarios.

## License

Same as parent project.
