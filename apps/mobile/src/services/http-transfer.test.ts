import { describe, expect, it } from 'vitest'
import type { TransferManifest } from '@link-me/shared'
import { buildUploadRequest, retryFailedTransferItems, uploadTransferBatch, uploadTransferItem } from './http-transfer'

describe('http transfer helpers', () => {
  it('builds the upload url and headers from host info and manifest', () => {
    const manifest: TransferManifest = {
      transferId: 'transfer-1',
      sessionId: 'session-1',
      items: [{ relativePath: 'docs/hello.txt', size: 11, kind: 'file' }],
      itemCount: 1,
      totalBytes: 11,
    }

    const request = buildUploadRequest({
      hostIp: '127.0.0.1',
      port: 19090,
      manifest,
      relativePath: 'docs/hello.txt',
    })

    expect(request.url).toBe('http://127.0.0.1:19090/api/transfers/session-1/transfer-1/upload')
    expect(request.headers['x-relative-path']).toBe('docs/hello.txt')
  })

  it('posts binary content with the generated upload request', async () => {
    const manifest: TransferManifest = {
      transferId: 'transfer-1',
      sessionId: 'session-1',
      items: [{ relativePath: 'docs/hello.txt', size: 11, kind: 'file' }],
      itemCount: 1,
      totalBytes: 11,
    }

    const calls: Array<{ url: string; init?: RequestInit }> = []
    const fetcher: typeof fetch = async (input, init) => {
      calls.push({ url: String(input), init })
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      })
    }

    const result = await uploadTransferItem(
      {
        hostIp: '127.0.0.1',
        port: 19090,
        manifest,
        relativePath: 'docs/hello.txt',
      },
      Buffer.from('hello world'),
      fetcher,
    )

    expect(result.ok).toBe(true)
    expect(calls).toHaveLength(1)
    expect(calls[0]?.url).toBe('http://127.0.0.1:19090/api/transfers/session-1/transfer-1/upload')
    expect(calls[0]?.init?.method).toBe('POST')
  })

  it('continues uploading later files after one file fails', async () => {
    const manifest: TransferManifest = {
      transferId: 'transfer-1',
      sessionId: 'session-1',
      items: [
        { relativePath: 'docs/a.txt', size: 5, kind: 'file' },
        { relativePath: 'docs/b.txt', size: 5, kind: 'file' },
        { relativePath: 'docs/c.txt', size: 5, kind: 'file' },
      ],
      itemCount: 3,
      totalBytes: 15,
    }

    const fetcher: typeof fetch = async (input, init) => {
      const headers = (init?.headers ?? {}) as Record<string, string>
      const relativePath = headers['x-relative-path']
      if (relativePath === 'docs/b.txt') {
        return new Response(JSON.stringify({ ok: false, error: 'timeout' }), {
          status: 500,
          headers: { 'content-type': 'application/json' },
        })
      }

      return new Response(JSON.stringify({ ok: true, savedPath: `/save/${relativePath}` }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      })
    }

    const result = await uploadTransferBatch({
      hostIp: '127.0.0.1',
      port: 19090,
      manifest,
      fileBodyLoader: async (relativePath) => Buffer.from(relativePath),
      fetcher,
    })

    expect(result.status).toBe('completed_with_errors')
    expect(result.items).toMatchObject([
      { relativePath: 'docs/a.txt', status: 'success' },
      { relativePath: 'docs/b.txt', status: 'failed', error: 'timeout' },
      { relativePath: 'docs/c.txt', status: 'success' },
    ])
    expect(result.summary).toMatchObject({ successCount: 2, failedCount: 1, totalCount: 3 })
  })

  it('retries only failed items from a previous batch result', async () => {
    const manifest: TransferManifest = {
      transferId: 'transfer-1',
      sessionId: 'session-1',
      items: [
        { relativePath: 'docs/a.txt', size: 5, kind: 'file' },
        { relativePath: 'docs/b.txt', size: 5, kind: 'file' },
      ],
      itemCount: 2,
      totalBytes: 10,
    }

    const failedBatch = {
      status: 'completed_with_errors' as const,
      items: [
        { relativePath: 'docs/a.txt', size: 5, status: 'success', attempts: 1 },
        { relativePath: 'docs/b.txt', size: 5, status: 'failed', attempts: 1, error: 'timeout' },
      ],
      summary: { totalCount: 2, successCount: 1, failedCount: 1 },
    }

    const seen: string[] = []
    const fetcher: typeof fetch = async (input, init) => {
      const headers = (init?.headers ?? {}) as Record<string, string>
      seen.push(headers['x-relative-path'])
      return new Response(JSON.stringify({ ok: true, savedPath: `/save/${headers['x-relative-path']}` }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      })
    }

    const retried = await retryFailedTransferItems({
      hostIp: '127.0.0.1',
      port: 19090,
      manifest,
      previous: failedBatch,
      fileBodyLoader: async (relativePath) => Buffer.from(relativePath),
      fetcher,
    })

    expect(seen).toEqual(['docs/b.txt'])
    expect(retried.status).toBe('completed')
    expect(retried.items).toMatchObject([
      { relativePath: 'docs/a.txt', status: 'success', attempts: 1 },
      { relativePath: 'docs/b.txt', status: 'success', attempts: 2 },
    ])
  })
})
