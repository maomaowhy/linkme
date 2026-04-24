export const normalizeRelativePath = (input: string) => {
  const normalized = input.replaceAll('\\', '/').replace(/^\/+/, '')
  if (normalized === '..' || normalized.startsWith('../') || normalized.includes('/../')) {
    throw new Error('path traversal is not allowed')
  }
  return normalized
}
