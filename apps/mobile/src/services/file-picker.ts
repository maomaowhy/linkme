export interface PickedEntry {
  path: string
  kind: 'file' | 'directory'
}

export const ensurePickedEntries = (entries: PickedEntry[]) => {
  if (entries.length === 0) {
    throw new Error('at least one file or folder must be selected')
  }

  return entries
}
