import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

/**
 * Content-level upload validation (defense in depth for file uploads).
 *
 * The Storage rules already enforce `image/*` content-type + 10 MB at
 * upload time — but `contentType` is client-supplied metadata, so a
 * tampered client can claim `image/jpeg` while uploading arbitrary bytes.
 * This `onObjectFinalized` trigger reads the first 32 bytes of every new
 * object under `listingMedia/` and `avatars/` and DELETES anything whose
 * magic bytes aren't a real image (JPEG, PNG, WebP, GIF, HEIC/HEIF, AVIF).
 *
 * Why deletion is safe: uploads are never executed anywhere. Storage
 * objects are served as static bytes with `X-Content-Type-Options: nosniff`
 * and there is no web root / code execution path — so the residual risk of
 * a non-image sitting in the bucket for the ~1s before this trigger runs is
 * nil. The trigger just keeps the bucket clean and closes the "fake image"
 * hole for good.
 */

const PREFIXES = ["listingMedia/", "avatars/"];

/** Returns the image kind from magic bytes, or null if not an image. */
function sniff(head: Buffer): string | null {
  if (
    head.length >= 3 &&
    head[0] === 0xff &&
    head[1] === 0xd8 &&
    head[2] === 0xff
  ) {
    return "jpeg";
  }
  if (
    head.length >= 8 &&
    head[0] === 0x89 &&
    head[1] === 0x50 &&
    head[2] === 0x4e &&
    head[3] === 0x47 &&
    head[4] === 0x0d &&
    head[5] === 0x0a &&
    head[6] === 0x1a &&
    head[7] === 0x0a
  ) {
    return "png";
  }
  if (
    head.length >= 12 &&
    head.toString("ascii", 0, 4) === "RIFF" &&
    head.toString("ascii", 8, 12) === "WEBP"
  ) {
    return "webp";
  }
  if (
    head.length >= 6 &&
    (head.toString("ascii", 0, 6) === "GIF87a" ||
      head.toString("ascii", 0, 6) === "GIF89a")
  ) {
    return "gif";
  }
  // HEIC/HEIF/AVIF: `....ftyp<brand>` — brand at bytes 8..12.
  if (head.length >= 12 && head.toString("ascii", 4, 8) === "ftyp") {
    const brand = head.toString("ascii", 8, 12);
    if (
      [
        "heic",
        "heix",
        "hevc",
        "hevx",
        "heim",
        "heis",
        "hevm",
        "hevs",
        "mif1",
        "msf1",
      ].includes(brand)
    ) {
      return "heic";
    }
    if (brand === "avif" || brand === "avis") return "avif";
  }
  return null;
}

export async function checkUploadedImage(
  objectName: string | undefined,
  bucketName: string
): Promise<void> {
  if (!objectName || !PREFIXES.some((p) => objectName.startsWith(p))) return;

  const file = admin.storage().bucket(bucketName).file(objectName);
  const chunks: Buffer[] = [];
  try {
    await new Promise<void>((resolve, reject) => {
      file
        .createReadStream({ start: 0, end: 31 })
        .on("data", (d) => chunks.push(d as Buffer))
        .on("end", () => resolve())
        .on("error", (e) => reject(e));
    });
  } catch (e) {
    // The object may already be gone (deleted upload) — nothing to do.
    logger.warn("storageCheck: could not read new object", {
      objectName,
      error: String(e),
    });
    return;
  }

  const kind = sniff(Buffer.concat(chunks));
  if (!kind) {
    logger.warn("storageCheck: deleting non-image upload", { objectName });
    await file.delete().catch(() => undefined);
  }
}
