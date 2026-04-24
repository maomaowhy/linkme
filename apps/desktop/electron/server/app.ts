import express from 'express'
import { createServer } from 'node:http'
import { WebSocketServer } from 'ws'

const setCorsHeaders = (res: express.Response) => {
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'content-type,x-relative-path')
}

export const createHostServer = () => {
  const app = express()
  const server = createServer(app)
  const websocket = new WebSocketServer({ server })

  app.use((req, res, next) => {
    setCorsHeaders(res)
    if (req.method === 'OPTIONS') {
      res.status(204).end()
      return
    }

    next()
  })

  app.get('/health', (_req, res) => {
    res.json({ ok: true })
  })

  return { app, server, websocket }
}
