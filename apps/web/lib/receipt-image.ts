const MAXIMUM_DIMENSION = 1_800;
const TARGET_BYTES = 600 * 1024;
const JPEG_QUALITIES = [0.78, 0.72, 0.66, 0.60] as const;

export async function prepareReceiptFiles(files: File[]): Promise<File[]> {
  return Promise.all(files.map(prepareReceiptFile));
}

export async function prepareReceiptFile(file: File): Promise<File> {
  if (!file.type.toLowerCase().startsWith("image/")) return file;

  let image: HTMLImageElement;
  try {
    image = await loadImage(file);
  } catch {
    // Preserve the existing upload path for image formats that the browser cannot
    // decode into a canvas (for example, HEIC support varies by browser/device).
    return file;
  }

  const sourceWidth = image.naturalWidth || image.width;
  const sourceHeight = image.naturalHeight || image.height;
  if (sourceWidth <= 0 || sourceHeight <= 0) return file;

  const longestSide = Math.max(sourceWidth, sourceHeight);
  const scale = longestSide > MAXIMUM_DIMENSION ? MAXIMUM_DIMENSION / longestSide : 1;
  const width = Math.max(1, Math.round(sourceWidth * scale));
  const height = Math.max(1, Math.round(sourceHeight * scale));

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) return file;

  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, width, height);
  context.drawImage(image, 0, 0, width, height);

  let smallest: Blob | null = null;
  for (const quality of JPEG_QUALITIES) {
    const blob = await canvasToBlob(canvas, quality);
    if (!smallest || blob.size < smallest.size) smallest = blob;
    if (blob.size <= TARGET_BYTES) break;
  }

  if (!smallest) return file;

  // Avoid making an already-small receipt larger just to normalize the format.
  if (smallest.size >= file.size && file.size <= TARGET_BYTES) return file;

  return new File([smallest], replaceExtension(file.name, "jpg"), {
    type: "image/jpeg",
    lastModified: file.lastModified,
  });
}

function loadImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("The receipt image could not be decoded."));
    };
    image.src = url;
  });
}

function canvasToBlob(canvas: HTMLCanvasElement, quality: number): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error("The receipt image could not be compressed."));
    }, "image/jpeg", quality);
  });
}

function replaceExtension(fileName: string, extension: string) {
  const base = fileName.replace(/\.[^.]+$/, "") || "receipt";
  return `${base}.${extension}`;
}
