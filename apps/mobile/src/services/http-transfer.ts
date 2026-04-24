import type { TransferManifest } from '@link-me/shared'

export interface PendingTransferDecision {
  manifest: TransferManifest
  targetDirectory: string
}

export interface TransferBatchItemResult {
  relativePath: string
  size: number
  status: 'waiting' | 'transferring' | 'success' | 'failed'
  attempts: number
  savedPath?: string
  error?: string
}

export interface TransferBatchResult {
  status: 'running' | 'completed' | 'completed_with_errors'
  items: TransferBatchItemResult[]
  summary: {
    totalCount: number
    successCount: number
    failedCount: number
  }
}

export const createPendingTransferDecision = (
  manifest: TransferManifest,
  targetDirectory: string,
): PendingTransferDecision => ({ manifest, targetDirectory })

export const buildUploadRequest = (input: {
  hostIp: string
  port: number
  manifest: TransferManifest
  relativePath: string
}) => ({
  url: `http://${input.hostIp}:${input.port}/api/transfers/${input.manifest.sessionId}/${input.manifest.transferId}/upload`,
  headers: {
    'content-type': 'application/octet-stream',
    'x-relative-path': input.relativePath,
  },
})

export const uploadTransferItem = async (
  input: {
    hostIp: string
    port: number
    manifest: TransferManifest
    relativePath: string
  },
  body: BodyInit,
  fetcher: typeof fetch = fetch,
) => {
  const request = buildUploadRequest(input)
  const response = await fetcher(request.url, {
    method: 'POST',
    headers: request.headers,
    body,
  })

  return response.json() as Promise<{ ok: boolean; savedPath?: string; error?: string }>
}

const summarize = (items: TransferBatchItemResult[]) => ({
  totalCount: items.length,
  successCount: items.filter((item) => item.status === 'success').length,
  failedCount: items.filter((item) => item.status === 'failed').length,
})

const finalize = (items: TransferBatchItemResult[]): TransferBatchResult => {
  const summary = summarize(items)
  return {
    status: summary.failedCount > 0 ? 'completed_with_errors' : 'completed',
    items,
    summary,
  }
}

export const uploadTransferBatch = async (input: {
  hostIp: string
  port: number
  manifest: TransferManifest
  fileBodyLoader: (relativePath: string) => Promise<BodyInit>
  fetcher?: typeof fetch
}) => {
  const items: TransferBatchItemResult[] = input.manifest.items.map((item) => ({
    relativePath: item.relativePath,
    size: item.size,
    status: 'waiting',
    attempts: 0,
  }))

  for (const item of items) {
    item.status = 'transferring'
    item.attempts += 1

    try {
      const body = await input.fileBodyLoader(item.relativePath)
      const result = await uploadTransferItem(
        {
          hostIp: input.hostIp,
          port: input.port,
          manifest: input.manifest,
          relativePath: item.relativePath,
        },
        body,
        input.fetcher,
      )

      if (!result.ok) {
        item.status = 'failed'
        item.error = result.error ?? 'upload_failed'
        continue
      }

      item.status = 'success'
      item.savedPath = result.savedPath
      item.error = undefined
    } catch (error) {
      item.status = 'failed'
      item.error = error instanceof Error ? error.message : 'upload_failed'
    }
  }

  return finalize(items)
}

export const retryFailedTransferItems = async (input: {
  hostIp: string
  port: number
  manifest: TransferManifest
  previous: {
    items: Array<Pick<TransferBatchItemResult, 'relativePath' | 'size' | 'status' | 'attempts' | 'savedPath' | 'error'>>
  }
  fileBodyLoader: (relativePath: string) => Promise<BodyInit>
  fetcher?: typeof fetch
}) => {
  const items: TransferBatchItemResult[] = input.previous.items.map((item) => ({
    relativePath: item.relativePath,
    size: item.size,
    status: item.status,
    attempts: item.attempts,
    savedPath: item.savedPath,
    error: item.error,
  }))

  for (const item of items) {
    if (item.status !== 'failed') {
      continue
    }

    item.status = 'transferring'
    item.attempts += 1
    item.error = undefined

    try {
      const body = await input.fileBodyLoader(item.relativePath)
      const result = await uploadTransferItem(
        {
          hostIp: input.hostIp,
          port: input.port,
          manifest: input.manifest,
          relativePath: item.relativePath,
        },
        body,
        input.fetcher,
      )

      if (!result.ok) {
        item.status = 'failed'
        item.error = result.error ?? 'upload_failed'
        continue
      }

      item.status = 'success'
      item.savedPath = result.savedPath
    } catch (error) {
      item.status = 'failed'
      item.error = error instanceof Error ? error.message : 'upload_failed'
    }
  }

  return finalize(items)
}
