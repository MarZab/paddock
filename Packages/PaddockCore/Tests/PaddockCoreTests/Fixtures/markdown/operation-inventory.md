---
id: pantry-1
title: Operation inventory (PANTRY-1)
type: other
created_date: '2026-11-01T14:54:00Z'
updated_date: '2026-11-01T14:54:00Z'
---
# Operation inventory (PANTRY-1)

Read from the code of Pantry, a made-up shopping list app, on 2026-11-01. The Where column says which side takes the call: the web page, the command line tool, or both.

## Summary

- Routes: 12 in the typed API, plus 2 top-level handlers
- Tools: 9 for the command line tool
- Proposed operations: 10 for one registry:
  - keep as a pair (one name on both sides): 6
  - merge (several routes become one operation): 2
  - set_item's field patch replaces the whole item, so it stays one-sided
- Biggest shape difference: update_list patches on the tool and replaces on the route

## The cart

Finding: nobody calls the cart from the command line tool.

- GET /api/cart/:id accepts any caller the guard accepts, a token included: it builds a Shopper with the credential's rights and credential: token:<id>|app:<grant>
- Proposal: the cart is served only on /web/cart/:id and refuses a token (403).

## Items

| Proposed op | Route today | Tool today | Does | Perm | Service | Callers | Decision | Where |
|---|---|---|---|---|---|---|---|---|
| list_items | GET /api/items (items.ts:12) | list_items (tool.ts:30) | read all items | any | listItems | web; cli | keep | both |
| add_item | POST /api/items (items.ts:20) | add_item (tool.ts:44) | add one item | Full | addItem | web form; cli | keep | both |
| link_preview_card | GET /api/preview/card (preview.ts:9) | — | the card image | any | drawCard | SPA <img src> (editor/preview.tsx:82) | one-sided | web |
| get_logs | GET /api/logs (logs.ts:25) | get_logs (tool.ts:56) | read the log | any | logsPage | refresh "0"|"1" vs boolean | keep, boolean | both |

## Orders

| Op | Does | Perm |
|---|---|---|
| list_orders | read all orders | any |
| place_order | send the cart to the shop | Full |

## Questions for the owner

1. Uploads as one operation with two input forms? upload_photo and set_avatar
2. add_item and the bulk import on the route too? They write through one service.
3. Refresh as an input on a GET: a read-only token could then trigger work.
