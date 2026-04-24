const createId = () => {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID()
  }

  return `transfer-${Date.now()}`
}

export interface TransferItem {
  relativePath: string
  size: number
  kind: 'file'
}

export interface TransferManifest {
  transferId: string
  sessionId: string
  items: TransferItem[]
  itemCount: number
  totalBytes: number
}

export const createTransferManifest = (sessionId: string, items: TransferItem[]): TransferManifest => ({
  transferId: createId(),
  sessionId,
  items,
  itemCount: items.length,
  totalBytes: items.reduce((sum, item) => sum + item.size, 0),
})
