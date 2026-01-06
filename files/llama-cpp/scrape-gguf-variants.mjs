#!/usr/bin/env node

import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import https from 'node:https';

const __dirname = dirname(fileURLToPath(import.meta.url));

function fetchHTML(url) {
  return new Promise((resolve, reject) => {
    https.get(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; huggingface-scraper/1.0)',
      },
    }, (res) => {
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP error! status: ${res.statusCode}`));
        return;
      }

      let data = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        resolve(data);
      });
    }).on('error', reject);
  });
}

function extractVariantsFromTable(html) {
  const variants = [];

  const tableStart = html.indexOf('<table');
  if (tableStart === -1) {
    return [];
  }

  const tableEnd = html.indexOf('</table>', tableStart);
  if (tableEnd === -1) {
    return [];
  }

  const tableHTML = html.slice(tableStart, tableEnd + 8);

  const rowRegex = /<tr[^>]*>[\s\S]*?<\/tr>/gi;
  let rowMatch;
  const rows = [];

  while ((rowMatch = rowRegex.exec(tableHTML)) !== null) {
    rows.push(rowMatch[0]);
  }

  for (const row of rows) {
    try {
      const cellRegex = /<td[^>]*>([\s\S]*?)<\/td>/gi;
      const cells = [];

      let cellMatch;
      while ((cellMatch = cellRegex.exec(row)) !== null) {
        cells.push(cellMatch[1]);
      }

      if (cells.length < 4) {
        continue;
      }

      const filenameCell = cells[0];
      const filenameMatch = filenameCell.match(/<a[^>]+href="([^"]+)"[^>]*>([^<]+)<\/a>/i);
      if (!filenameMatch) {
        continue;
      }

      const filename = filenameMatch[2].trim();
      const url = filenameMatch[1].trim();

      const quantTypeCell = cells[1];
      const quantType = quantTypeCell.replace(/<[^>]+>/g, '').trim();

      const sizeCell = cells[2];
      const size = sizeCell.replace(/<[^>]+>/g, '').trim();

      const splitCell = cells[3];
      const splitValue = splitCell.replace(/<[^>]+>/g, '').trim().toLowerCase();
      const split = splitValue === 'true';

      const descriptionCell = cells[4];
      const description = descriptionCell ? descriptionCell.replace(/<[^>]+>/g, '').trim() : undefined;

      variants.push({
        filename,
        url,
        quantType,
        size,
        split,
        description,
      });
    } catch (error) {
      console.warn('Failed to parse row:', error);
    }
  }

  return variants;
}

function extractVariantsFromJSON(html) {
  const variants = [];

  const dataPropsRegex = /data-props="({[^"]*ggufFilePaths[^"]*})"/;
  const match = html.match(dataPropsRegex);

  if (!match) {
    return [];
  }

  try {
    let jsonStr = match[1];
    
    jsonStr = jsonStr.replace(/&quot;/g, '"');
    jsonStr = jsonStr.replace(/&#x27;/g, "'");
    jsonStr = jsonStr.replace(/&amp;/g, '&');
    jsonStr = jsonStr.replace(/&lt;/g, '<');
    jsonStr = jsonStr.replace(/&gt;/g, '>');

    const data = JSON.parse(jsonStr);

    if (data.gguf && Array.isArray(data.gguf.ggufFilePaths)) {
      const pageUrlMatch = html.match(/<link[^>]+rel="canonical"[^>]+href="([^"]+)"/i);
      const pageUrl = pageUrlMatch ? pageUrlMatch[1] : '';

      return data.gguf.ggufFilePaths.map((filename) => {
        const url = constructDownloadURL(filename, pageUrl);
        return {
          filename,
          url,
          quantType: '',
          size: '',
          split: false,
        };
      });
    }

    return [];
  } catch (error) {
    console.warn('Failed to parse embedded JSON:', error);
    return [];
  }
}

function constructDownloadURL(filename, pageUrl) {
  if (!pageUrl) {
    return '';
  }

  try {
    const url = new URL(pageUrl);
    const pathParts = url.pathname.split('/').filter(Boolean);

    if (pathParts.length < 2) {
      return '';
    }

    const owner = pathParts[0];
    const repo = pathParts[1];

    return `https://huggingface.co/${owner}/${repo}/raw/main/${filename}`;
  } catch {
    return '';
  }
}

function saveVariantsAsJSON(variants, outputDir, modelName) {
  const outputPath = join(outputDir, `${modelName}.json`);
  const jsonOutput = JSON.stringify(variants, null, 2);
  writeFileSync(outputPath, jsonOutput, 'utf-8');
  console.log(`Saved ${variants.length} variants to ${outputPath}`);
}

async function scrapeHuggingFaceGGUF(modelUrl, outputDir) {
  console.log(`Scraping ${modelUrl}...`);

  const html = await fetchHTML(modelUrl);

  const url = new URL(modelUrl);
  const pathParts = url.pathname.split('/').filter(Boolean);
  const modelName = pathParts[pathParts.length - 1];

  console.log(`Parsing variants for model: ${modelName}`);

  let variants = [];

  try {
    variants = extractVariantsFromTable(html);
    console.log(`Parsed ${variants.length} variants from table`);
  } catch (error) {
    console.warn('Table parsing failed, trying embedded JSON:', error);
  }

  if (variants.length === 0) {
    console.warn('No variants from table, trying embedded JSON...');
    variants = extractVariantsFromJSON(html);
    console.log(`Parsed ${variants.length} variants from embedded JSON`);
  }

  if (variants.length === 0) {
    throw new Error('No variants found');
  }

  saveVariantsAsJSON(variants, outputDir, modelName);
}

function printUsage() {
  console.log(`
Usage: node scrape-gguf-variants.mjs <model-url>

Arguments:
  model-url    URL of the HuggingFace GGUF model page

Example:
  node scrape-gguf-variants.mjs https://huggingface.co/bartowski/Nanbeige_Nanbeige4-3B-Thinking-2511-GGUF

Output:
  JSON file saved to files/llama-cpp/<model-name>.json
  
  The JSON file contains an array of variant objects with:
  - filename: The GGUF filename
  - url: Direct download URL
  - quantType: Quantization type (e.g., Q2_K, IQ3_M)
  - size: File size (e.g., 1.62GB)
  - split: Whether the file is split across multiple parts
  - description: Optional description of the quant
`);
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === '--help' || args[0] === '-h') {
    printUsage();
    process.exit(0);
  }

  const modelUrl = args[0];
  const outputDir = resolve(__dirname, 'files', 'llama-cpp');

  if (!existsSync(outputDir)) {
    mkdirSync(outputDir, { recursive: true });
  }

  try {
    await scrapeHuggingFaceGGUF(modelUrl, outputDir);
    console.log('Done!');
  } catch (error) {
    console.error('Error:', error instanceof Error ? error.message : error);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, '/')}`) {
  main().catch((error) => {
    console.error('Unhandled error:', error);
    process.exit(1);
  });
}

export { scrapeHuggingFaceGGUF, extractVariantsFromTable, extractVariantsFromJSON };
