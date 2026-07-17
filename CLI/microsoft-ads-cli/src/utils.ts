import { inflateRawSync } from "node:zlib";

export function output(data: unknown, format: string): void {
  const json =
    format === "compact"
      ? JSON.stringify(data)
      : JSON.stringify(data, null, 2);
  process.stdout.write(json + "\n");
}

export function fatal(message: string): never {
  process.stderr.write(JSON.stringify({ error: message }) + "\n");
  process.exit(1);
}

/** Strip dashes so "123-456-7890"-style IDs work */
export function normalizeId(id: string): string {
  return id.replace(/-/g, "");
}

export function commaList(value: string): string[] {
  return value.split(",").map((v) => v.trim()).filter(Boolean);
}

/** Extract the first file from a ZIP archive (Bing report downloads are single-file ZIPs). */
export function unzipFirstEntry(buf: Buffer): Buffer {
  // Locate End of Central Directory record (signature 0x06054b50), scanning back over the comment
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 65535); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error("Report download is not a valid ZIP archive");

  const cdOffset = buf.readUInt32LE(eocd + 16);
  if (buf.readUInt32LE(cdOffset) !== 0x02014b50) {
    throw new Error("ZIP central directory not found");
  }
  const method = buf.readUInt16LE(cdOffset + 10);
  const compressedSize = buf.readUInt32LE(cdOffset + 20);
  const localOffset = buf.readUInt32LE(cdOffset + 42);

  if (buf.readUInt32LE(localOffset) !== 0x04034b50) {
    throw new Error("ZIP local file header not found");
  }
  const nameLen = buf.readUInt16LE(localOffset + 26);
  const extraLen = buf.readUInt16LE(localOffset + 28);
  const dataStart = localOffset + 30 + nameLen + extraLen;
  const data = buf.subarray(dataStart, dataStart + compressedSize);

  if (method === 0) return Buffer.from(data);
  if (method === 8) return inflateRawSync(data);
  throw new Error(`Unsupported ZIP compression method: ${method}`);
}

/** Parse CSV text (quoted fields, embedded commas/newlines, doubled quotes) into rows of strings. */
export function parseCsv(text: string): string[][] {
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += c;
      }
    } else if (c === '"') {
      inQuotes = true;
    } else if (c === ",") {
      row.push(field);
      field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      field = "";
      rows.push(row);
      row = [];
    } else {
      field += c;
    }
  }
  if (field !== "" || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter((r) => !(r.length === 1 && r[0] === ""));
}

/** Convert CSV rows (first row = header) into an array of objects. */
export function csvToObjects(rows: string[][]): Record<string, string>[] {
  if (rows.length === 0) return [];
  const header = rows[0];
  return rows.slice(1).map((r) => {
    const obj: Record<string, string> = {};
    header.forEach((h, i) => {
      obj[h] = r[i] ?? "";
    });
    return obj;
  });
}
