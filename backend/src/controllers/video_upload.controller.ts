import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import {
  UploadSessionError,
  startVideoUpload,
  getVideoUpload,
  appendVideoChunk,
  completeVideoUpload,
  abortVideoUpload,
} from '../utils/largeVideoUploads.js';

function handleError(res: Response, error: unknown, context: string): void {
  if (error instanceof UploadSessionError) {
    const payload: Record<string, unknown> = { error: error.message };
    res.status(error.statusCode).json(payload);
    return;
  }
  console.error(`${context} error:`, error);
  res.status(500).json({ error: 'Video upload failed' });
}

export async function initVideoUpload(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const result = await startVideoUpload(
      req.user!.id,
      req.body?.file_name,
      req.body?.file_size
    );
    res.status(201).json(result);
  } catch (error) {
    handleError(res, error, 'initVideoUpload');
  }
}

export async function getVideoUploadStatus(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    res.json(getVideoUpload(req.user!.id, req.params.id));
  } catch (error) {
    handleError(res, error, 'getVideoUploadStatus');
  }
}

export async function putVideoChunk(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const result = await appendVideoChunk(
      req.user!.id,
      req.params.id,
      req.query.offset,
      Buffer.isBuffer(req.body) ? req.body : undefined
    );
    res.json(result);
  } catch (error) {
    if (error instanceof UploadSessionError && error.statusCode === 409) {
      try {
        const { offset } = getVideoUpload(req.user!.id, req.params.id);
        res.status(409).json({ error: error.message, offset });
        return;
      } catch {
        // Fall through to the generic handler below.
      }
    }
    handleError(res, error, 'putVideoChunk');
  }
}

export function finishVideoUpload(req: AuthenticatedRequest, res: Response): void {
  try {
    res.json(completeVideoUpload(req.user!.id, req.params.id));
  } catch (error) {
    handleError(res, error, 'finishVideoUpload');
  }
}

export function cancelVideoUpload(req: AuthenticatedRequest, res: Response): void {
  try {
    abortVideoUpload(req.user!.id, req.params.id);
    res.json({ aborted: true });
  } catch (error) {
    handleError(res, error, 'cancelVideoUpload');
  }
}
