# Research: HuggingFace HTML Structure and lol-html Usage

## HuggingFace GGUF Page HTML Structure Analysis

Based on analyzing the page `https://huggingface.co/bartowski/Nanbeige_Nanbeige4-3B-Thinking-2511-GGUF`, here are the key findings:

### 1. Quantization Variants Table Structure

The quantization variants are displayed in an HTML table with the following structure:

```html
<table>
  <thead>
    <tr>
      <th>Filename</th>
      <th>Quant type</th>
      <th>File Size</th>
      <th>Split</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <!-- Each variant is a table row -->
    <tr>
      <td>
        <a href="https://huggingface.co/.../blob/main/...gguf">Nanbeige_Nanbeige4-3B-Thinking-2511-Q2_K.gguf</a>
      </td>
      <td>Q2_K</td>
      <td>1.62GB</td>
      <td>false</td>
      <td>Very low quality but surprisingly usable.</td>
    </tr>
    <!-- ... more rows -->
  </tbody>
</table>
```

### 2. Key Data Points to Extract

From each table row, we can extract:
- **Filename**: Link text (e.g., `Nanbeige_Nanbeige4-3B-Thinking-2511-Q2_K.gguf`)
- **Direct URL**: `href` attribute from the anchor tag (e.g., `https://huggingface.co/bartowski/Nanbeige_Nanbeige4-3B-Thinking-2511-GGUF/blob/main/Nanbeige_Nanbeige4-3B-Thinking-2511-Q2_K.gguf`)
- **Quantization Type**: Second cell (e.g., `Q2_K`, `IQ2_M`, `Q3_K_L`, etc.)
- **File Size**: Third cell (e.g., `1.62GB`, `1.51GB`, etc.)
- **Split Status**: Fourth cell (boolean as string, e.g., `false`)
- **Description**: Fifth cell (text description)

### 3. Quantization Variants Found

From the example page, the following quantization types were identified:

**2-bit variants:**
- Q2_K
- IQ2_M
- Q2_K_L

**3-bit variants:**
- IQ3_XXS
- IQ3_XS
- Q3_K_S
- IQ3_M
- Q3_K_M
- Q3_K_L
- Q3_K_XL

**4-bit variants:**
- IQ4_XS
- Q4_K_S
- IQ4_NL
- Q4_0
- Q4_1
- Q4_K_L
- Q4_K_M

**5-bit variants:**
- Q5_K_S
- Q5_K_M

**6-bit variants:**
- Q6_K
- Q6_K_L

**8-bit variants:**
- Q8_0

**16-bit variants:**
- BF16

### 4. Additional JSON Files Available

Besides the `.gguf` files in the table, the page metadata includes a `ggufFilePaths` array embedded in the HTML (in a `data-props` attribute) containing:

```json
[
  "Nanbeige_Nanbeige4-3B-Thinking-2511-IQ2_M.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-IQ3_M.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-IQ3_XS.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-IQ3_XXS.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-IQ4_NL.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-IQ4_XS.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q2_K.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q2_K_L.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q3_K_L.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q3_K_M.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q3_K_S.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q3_K_XL.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q4_0.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q4_1.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q4_K_L.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q4_K_M.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q4_K_S.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q5_K_L.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q5_K_M.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q5_K_S.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q6_K.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q6_K_L.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-Q8_0.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-bf16.gguf",
  "Nanbeige_Nanbeige4-3B-Thinking-2511-imatrix.gguf"
]
```

This suggests there's also an `imatrix.gguf` file which may be a JSON/calibration file.

### 5. lol-html API Analysis

Based on the lol-html documentation:

**Key Features:**
- Low output latency streaming HTML rewriter
- CSS-selector based API
- Efficient modification of large HTML documents
- Minimal buffering

**CSS Selector Syntax for lol-html:**
- Uses standard CSS selectors
- Supports namespaces with `|` syntax (e.g., `html|body`)
- Supports attribute selectors (e.g., `[href]`, `[data-props]`)
- Supports pseudo-classes (e.g., `:not()`, `:first-child`)

**Recommended Selectors for HuggingFace Table:**

```css
/* Target the table containing variants */
table tbody tr

/* Extract filename from first cell */
table tbody tr td:first-child a[href]

/* Extract quant type from second cell */
table tbody tr td:nth-child(2)

/* Extract file size from third cell */
table tbody tr td:nth-child(3)

/* Extract description from fifth cell */
table tbody tr td:nth-child(5)
```

### 6. Implementation Strategy

**Option 1: Table Parsing Approach**
- Use lol-html to parse the HTML table structure
- Extract data from each row using selectors
- More robust to HTML structure changes

**Option 2: Embedded JSON Approach**
- Parse the `data-props` attribute containing JSON metadata
- Extract `ggufFilePaths` array directly
- Faster but may be brittle if HuggingFace changes their API

**Recommended Approach:**
Use a hybrid method:
1. First, try to extract from the table structure (more stable across pages)
2. Fallback to parsing embedded JSON if table not found
3. Validate extracted data matches expected patterns

### 7. Output Data Structure

```typescript
interface GGUFVariant {
  filename: string;
  url: string;
  quantType: string;
  size: string;
  split: boolean;
  description?: string;
}
```

### 8. Potential Challenges

1. **Dynamic Loading**: HuggingFace may load data dynamically with JavaScript
2. **Pagination**: If there are many variants, they might be paginated
3. **Authentication**: Some models may be gated/private
4. **Rate Limiting**: HuggingFace may have rate limits
5. **HTML Structure Variations**: Different model pages may have different layouts

### 9. Additional Notes

- The `imatrix.gguf` file appears to be a calibration/quantization matrix file
- URLs can be converted to download URLs by replacing `/blob/` with `/resolve/` or `/raw/`
- The base URL structure is: `https://huggingface.co/{owner}/{repo-name}/blob/main/{filename}`
