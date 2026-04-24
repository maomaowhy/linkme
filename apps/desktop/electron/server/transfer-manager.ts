import { randomUUID } from 'node:crypto'
import type { TransferItem } from '@link-me/shared'

type TransferDirection = 'outbound' | 'inbound'
type TransferStatus =
  | 'offered'
  | 'accepted'
  | 'running'
  | 'completed'
  | 'completed_with_errors'
  | 'cancelled'
  | 'rejected'

type TransferItemStatus = 'waiting' | 'transferring' | 'success' | 'failed' | 'cancelled'

interface CreateOfferInput {
  sessionId: string
  direction: TransferDirection
  items: TransferItem[]
  transferId?: string
}

interface ManagedTransferItem extends TransferItem {
  status: TransferItemStatus
  transferredBytes: number
  savedPath?: string
  error?: string
  attempts: number
}

interface TransferSummary {
  totalCount: number
  successCount: number
  failedCount: number
  waitingCount: number
  transferringCount: number
}

interface TransferTask {
  sessionId: string
  direction: TransferDirection
  transferId: string
  status: TransferStatus
  items: ManagedTransferItem[]
  targetDirectory?: string
  rejectionReason?: string
  summary: TransferSummary
}

const summarize = (items: ManagedTransferItem[]): TransferSummary => ({
  totalCount: items.length,
  successCount: items.filter((item) => item.status === 'success').length,
  failedCount: items.filter((item) => item.status === 'failed').length,
  waitingCount: items.filter((item) => item.status === 'waiting').length,
  transferringCount: items.filter((item) => item.status === 'transferring').length,
})

const resolveStatus = (
  currentStatus: TransferStatus,
  items: ManagedTransferItem[],
): TransferStatus => {
  const summary = summarize(items)

  if (currentStatus === 'cancelled' || currentStatus === 'rejected') {
    return currentStatus
  }

  if (summary.transferringCount > 0) {
    return 'running'
  }

  if (summary.waitingCount > 0) {
    return currentStatus === 'offered' ? 'offered' : 'accepted'
  }

  if (summary.failedCount > 0) {
    return 'completed_with_errors'
  }

  return 'completed'
}

export class TransferManager {
  private transfers = new Map<string, TransferTask[]>()

  createOffer(input: CreateOfferInput): TransferTask {
    const transfer: TransferTask = {
      sessionId: input.sessionId,
      direction: input.direction,
      transferId: input.transferId ?? randomUUID(),
      status: 'offered',
      targetDirectory: undefined,
      rejectionReason: undefined,
      items: input.items.map((item) => ({
        ...item,
        status: 'waiting',
        transferredBytes: 0,
        attempts: 0,
      })),
      summary: {
        totalCount: input.items.length,
        successCount: 0,
        failedCount: 0,
        waitingCount: input.items.length,
        transferringCount: 0,
      },
    }

    const current = this.transfers.get(input.sessionId) ?? []
    current.push(transfer)
    this.transfers.set(input.sessionId, current)
    return transfer
  }

  acceptTransfer(sessionId: string, transferId: string, targetDirectory: string) {
    const transfer = this.requireTransfer(sessionId, transferId)
    transfer.status = 'accepted'
    transfer.targetDirectory = targetDirectory
    transfer.rejectionReason = undefined
    transfer.summary = summarize(transfer.items)
    return transfer
  }

  rejectTransfer(sessionId: string, transferId: string, reason: string) {
    const transfer = this.requireTransfer(sessionId, transferId)
    transfer.status = 'rejected'
    transfer.rejectionReason = reason
    transfer.summary = summarize(transfer.items)
    return transfer
  }

  getTransfer(sessionId: string, transferId: string) {
    const current = this.transfers.get(sessionId) ?? []
    return current.find((item) => item.transferId === transferId)
  }

  markCompleted(sessionId: string, transferId: string) {
    const transfer = this.requireTransfer(sessionId, transferId)
    transfer.summary = summarize(transfer.items)
    transfer.status = resolveStatus(transfer.status, transfer.items)
    return transfer
  }

  markItemTransferring(sessionId: string, transferId: string, relativePath: string) {
    const transfer = this.requireTransfer(sessionId, transferId)
    const item = this.requireItem(transfer, relativePath)
    item.status = 'transferring'
    item.error = undefined
    item.attempts += 1
    transfer.summary = summarize(transfer.items)
    transfer.status = resolveStatus('running', transfer.items)
    return transfer
  }

  markItemSucceeded(
    sessionId: string,
    transferId: string,
    relativePath: string,
    savedPath: string,
    transferredBytes: number,
  ) {
    const transfer = this.requireTransfer(sessionId, transferId)
    const item = this.requireItem(transfer, relativePath)
    item.status = 'success'
    item.savedPath = savedPath
    item.transferredBytes = transferredBytes
    item.error = undefined
    transfer.summary = summarize(transfer.items)
    transfer.status = resolveStatus(transfer.status, transfer.items)
    return transfer
  }

  markItemFailed(sessionId: string, transferId: string, relativePath: string, error: string) {
    const transfer = this.requireTransfer(sessionId, transferId)
    const item = this.requireItem(transfer, relativePath)
    if (item.attempts === 0) {
      item.attempts = 1
    }
    item.status = 'failed'
    item.error = error
    transfer.summary = summarize(transfer.items)
    transfer.status = resolveStatus(transfer.status, transfer.items)
    return transfer
  }

  retryFailedItems(sessionId: string, transferId: string) {
    const transfer = this.requireTransfer(sessionId, transferId)
    for (const item of transfer.items) {
      if (item.status !== 'failed') {
        continue
      }

      item.status = 'waiting'
      item.error = undefined
      item.transferredBytes = 0
    }

    transfer.summary = summarize(transfer.items)
    transfer.status = 'accepted'
    return transfer
  }

  listBySession(sessionId: string) {
    return this.transfers.get(sessionId) ?? []
  }

  private requireTransfer(sessionId: string, transferId: string) {
    const transfer = this.getTransfer(sessionId, transferId)
    if (!transfer) {
      throw new Error('transfer not found')
    }

    return transfer
  }

  private requireItem(transfer: TransferTask, relativePath: string) {
    const item = transfer.items.find((entry) => entry.relativePath === relativePath)
    if (!item) {
      throw new Error('transfer item not found')
    }

    return item
  }
}
