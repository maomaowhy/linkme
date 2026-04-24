# Link Me Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐项目状态文档与部署验证文档，并统一现有文档入口与口径。

**Architecture:** 采用“双主文档 + 轻量索引”的方式：`docs/project-status.md` 负责记录当前完成度与边界，`docs/deployment-verification.md` 负责记录部署、联调、打包、验收与排障。`README.md` 提供总入口，现有 `docs/build.md`、`docs/usage.md`、`docs/feature-overview.md` 保持主题化说明。

**Tech Stack:** Markdown, pnpm workspace, Electron, uni-app, Vue 3, HBuilderX build flow

---

### Task 1: Add project status document

**Files:**
- Create: `docs/project-status.md`
- Reference: `README.md`
- Reference: `docs/feature-overview.md`
- Reference: `docs/usage.md`
- Reference: `docs/build.md`

- [ ] **Step 1: Write project status document**
- [ ] **Step 2: Cover completed scope, unfinished scope, limits, deliverables, next steps**
- [ ] **Step 3: Check wording matches current implementation state**

### Task 2: Add deployment and verification guide

**Files:**
- Create: `docs/deployment-verification.md`
- Reference: `apps/desktop/package.json`
- Reference: `apps/mobile/package.json`

- [ ] **Step 1: Write environment and dependency preparation**
- [ ] **Step 2: Write desktop, mobile H5, mobile app-plus deployment steps**
- [ ] **Step 3: Write end-to-end verification checklist and troubleshooting**
- [ ] **Step 4: Record APK output path and HBuilderX follow-up packaging path**

### Task 3: Link docs from README and align wording

**Files:**
- Modify: `README.md`
- Modify: `docs/build.md`
- Modify: `docs/usage.md`
- Modify: `docs/feature-overview.md`

- [ ] **Step 1: Add documentation navigation links**
- [ ] **Step 2: Align current completed and incomplete statements**
- [ ] **Step 3: Ensure no contradictory wording remains**

### Task 4: Verify documentation handoff

**Files:**
- Verify: `docs/project-status.md`
- Verify: `docs/deployment-verification.md`
- Verify: `README.md`

- [ ] **Step 1: Re-read generated docs for consistency**
- [ ] **Step 2: Check files exist and key sections are present**
- [ ] **Step 3: Summarize documentation deliverables to the user**
