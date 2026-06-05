import fs from "fs";
import path from "path";
import formidable from "formidable";
import { withObservableApi } from "../../lib/observability/sentry-api";

export const config = {
  api: {
    bodyParser: false,
  },
};

const ALLOWED_MIME = new Set([
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/octet-stream",
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
]);

const ALLOWED_EXT = /\.(pdf|doc|docx|jpe?g|png|webp|gif)$/i;

async function uploadResumeHandler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const uploadDir = path.join(process.cwd(), "tmp", "uploads");
  fs.mkdirSync(uploadDir, { recursive: true });

  const form = formidable({
    uploadDir,
    keepExtensions: true,
    maxFiles: 1,
    maxFileSize: 512 * 1024 * 1024,
    filename: (_name, _ext, part) => {
      const safeOriginal = (part.originalFilename || "resume")
        .replace(/[^a-zA-Z0-9._-]/g, "-")
        .slice(0, 80);
      return `${Date.now()}-${safeOriginal}`;
    },
  });

  try {
    const [fields, files] = await form.parse(req);
    const uploadedFile = files.resumeFile?.[0];
    if (!uploadedFile) {
      return res.status(400).json({ error: "No file uploaded" });
    }

    const originalName = uploadedFile.originalFilename || "";
    if (!ALLOWED_EXT.test(originalName)) {
      return res.status(415).json({
        error: "unsupported_file_type",
        message: "Upload PDF, Word (.pdf, .doc, .docx), or images (.jpg, .png, .webp, .gif).",
      });
    }
    const mimeType = (uploadedFile.mimetype || "").toLowerCase();
    if (mimeType && !ALLOWED_MIME.has(mimeType)) {
      return res.status(415).json({
        error: "unsupported_file_type",
        message: "Upload PDF, Word, or images (PNG, JPG).",
      });
    }

    let parsed = { data: null, meta: { parser: "skipped" } };
    try {
      const buffer = fs.readFileSync(uploadedFile.filepath);
      const { parseBossMindResume } = await import("../../lib/resume-parser");
      parsed = await parseBossMindResume(buffer, {
        project: process.env.BOSSMIND_PROJECT ?? "resumora",
      });
    } catch (parseErr) {
      console.warn("[upload-resume] parser skipped:", parseErr?.message || parseErr);
    }

    return res.status(200).json({
      success: true,
      ok: true,
      file: {
        originalName: uploadedFile.originalFilename,
        storedName: path.basename(uploadedFile.filepath),
        size: uploadedFile.size,
        mimeType: mimeType || null,
      },
      resume: parsed?.data ?? null,
      meta: parsed?.meta ?? null,
      fields,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Upload failed";
    console.error("[upload-resume]", error);
    return res.status(500).json({ error: message });
  }
}

export default withObservableApi(uploadResumeHandler, { route: "/api/upload-resume" });
