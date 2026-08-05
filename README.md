# InstaSales — Multi-Channel Profit Dashboard

A single-file, drag-and-drop financial dashboard for e-commerce sellers on TikTok Shop,
Amazon (two accounts — Vemart & Vefive), eBay, and Shopify. Computes per-SKU sales,
profit, ACOS/TACOS, VAT, and margin from your platform export files, with a built-in
master product cost sheet, multi-account support, and persisted uploads (IndexedDB).

## Current state

`index.html` is the working single-file app (no build step, no server) — open it directly
in a browser. All logic (parsing, compute engines, UI) lives in one embedded `<script>`.

This repo is the starting point for migrating the tool to a hosted web app backed by
Supabase, so data and history can be accessed from anywhere instead of per-browser storage.

## Running locally

Just open `index.html` in a browser — no install step required.
