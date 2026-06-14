# AI playbook: client PO (PDF) → wholesale order

Use this document to learn the **business flow** and **safe behaviour** for turning a customer’s purchase order into a wholesale order in the POS/management system. Client POs may use **many different layouts**; treat extraction as **probabilistic** and **always allow human correction** before anything irreversible is committed.

---

## 1. Your role

- **Assist** staff: extract structured data from PO text or PDF-derived text, map lines to internal products where possible, and produce a **draft** the human can verify.
- **Do not** claim the order is “created” or “submitted” unless the human (or an integrated tool with credentials) has actually called the API or clicked submit in the UI.
- **Never invent** internal `product_id` values. If a line cannot be matched confidently, output the **raw line from the PO** and flag it for manual mapping.

---

## 2. Definition of done

A successful run ends with one of:

| Outcome | Meaning |
|--------|---------|
| **Draft ready** | Structured payload or UI checklist the user can paste or follow; all required fields identified; uncertain rows flagged. |
| **Blocked** | Clear list of what is missing (e.g. which wholesale client, ambiguous quantities) and minimal questions to unblock. |

Optional follow-up (human or automation): **attach the original PDF** to the order as a PO attachment after the order exists.

---

## 3. Inputs you may receive

- PDF file, images, or pasted text from a client PO.
- Sometimes: wholesale client name, email domain, or account hint.
- Sometimes: which **fulfilling store** (`store_id`) applies (operational; often fixed per site).

---

## 4. Target data shape (conceptual)

The system ultimately needs a **create wholesale order** request with at least:

| Concept | Notes |
|--------|--------|
| **Wholesale client** | Must resolve to an existing wholesale client record (`wholesale_client_id`). |
| **Fulfilling store** | `store_id` — warehouse/site that supplies the order (required by API). |
| **Shipping address** | Often `wholesale_client_store_id` (client’s saved store/ship-to). Custom one-off addresses may need saving as a client store first, depending on product flow. |
| **Line items** | Each line: internal `product_id` + `quantity` (> 0). Optional per-line discount as amount in GBP (`line_discount_amount`). |
| **PO metadata** | `po_number`, `po_date` (ISO date string if known), `order_channel` (e.g. `po`, `email`, `whatsapp`), `payment_terms`, `notes`. |
| **Order-level money** | `total_discount` (GBP amount), `shipping_fee` (GBP) when applicable. |

**Order channel:** For a formal client PO, `order_channel` is typically `po`. Use other channels only if the user says the order came that way.

---

## 5. End-to-end flow (phases)

Work in order. Do not skip validation phases.

### Phase A — Ingest

1. Obtain text: native PDF text extraction, or OCR if the PDF is scanned.
2. If text is empty or garbage, say so and ask for a clearer file or pasted content.

### Phase B — Identify parties and document

From the PO, extract when present:

- Buyer / bill-to / ship-to names and addresses  
- Supplier name (should match **your** company; if wrong, warn the user)  
- PO number, PO date, requested delivery date, payment terms, reference codes  
- Currency (note: pricing on the PO may not match system pricing; **quantities and SKU references matter more** than trusting client unit prices for system entry)

**Wholesale client resolution**

- Prefer explicit match to an existing client in the system (name, account code, email domain).
- If multiple candidates: list top matches and **ask the user to pick one**.
- If none: stop and ask the user to create or select the client before line mapping.

### Phase C — Extract line items (raw)

For each table row or line block, output a **neutral structure** before mapping:

- `raw_sku` or `raw_product_code` (as printed)  
- `description` (as printed)  
- `quantity` (number)  
- `unit` if stated (e.g. case, pack) — flag if conversion might be needed  
- `unit_price` / `line_total` from PO **for cross-check only** (do not override system pricing unless the user instructs)

**Normalisation rules**

- Strip thousand separators; use `.` or locale-consistent parsing; flag ambiguity (e.g. `1.000` vs `1,000`).  
- Merge split lines only if the layout clearly continues one item (otherwise keep separate).

### Phase D — Catalog mapping (critical)

For each raw line:

1. Try **exact** match on internal SKU / barcode / client-specific code if the user or system provides a mapping table.  
2. Try **fuzzy** match on name only with **confidence label** (high / medium / low).  
3. If low confidence or no match: mark `needs_human: true` and preserve raw fields.

**Rules**

- Do not drop unmatched lines silently.  
- Do not merge two PO lines into one system line unless the user confirms.

### Phase E — Draft summary for human sign-off

Present:

- Client + ship-to summary  
- PO number / date  
- Line table: PO text ↔ matched product (or “UNMAPPED”)  
- Flags: duplicate SKUs, quantity anomalies, missing mandatory fields  
- Suggested `order_channel`, `payment_terms`, `notes` (e.g. “Imported from PO PDF; please verify line 3”)

Wait for explicit user confirmation before describing the payload as final.

### Phase F — Submit (human or tool)

Creation is **POST** `/wholesale-orders` with JSON body (management/POS API; auth required). After create, PO files may be uploaded via **POST** `/wholesale-orders/{id}/po-attachments` (multipart, field name `po_attachments`).

If you are a **chat-only** assistant without API access: output a **checklist** and, if helpful, a **JSON draft** matching the API shape for a developer or another agent that has credentials.

---

## 6. Decision tree (when things go wrong)

```
PDF unreadable → request re-scan or pasted text
Client unknown → ask user to select/create wholesale client
store_id unknown → ask user (operational default per site)
Line qty missing → flag row; do not guess
Multiple possible products → list options; default to none
PO total ≠ sum of lines → warn; still draft lines from explicit line items
```

---

## 7. Safety and compliance

- **No hallucinated SKUs:** every `product_id` must correspond to a real product the user or API confirmed.  
- **Privacy:** POs may contain personal addresses; do not exfiltrate to untrusted third parties; follow org data policy.  
- **Audit:** real orders should retain the original PO attachment when the product supports it.  
- **Pricing:** wholesale pricing in the system may depend on sector and date; your job is primarily **identity + quantity**; call out when client prices differ.

---

## 8. Quick reference: API body (illustrative)

```json
{
  "wholesale_client_id": 0,
  "wholesale_client_store_id": null,
  "store_id": 0,
  "sector_id": null,
  "po_number": "",
  "order_channel": "po",
  "po_date": "YYYY-MM-DD",
  "payment_terms": "",
  "notes": "",
  "total_discount": 0,
  "shipping_fee": 0,
  "items": [
    { "product_id": 0, "quantity": 1, "line_discount_amount": 0 }
  ]
}
```

Replace `0` / empty strings with real values; omit optional keys if unused. Exact validation is enforced by the server.

---

## 9. Example dialogue pattern (for training)

**User:** Here is a PO PDF for Acme Trading.  
**Assistant:** Extracted PO #4521 dated 2026-03-30, ship-to London. Proposed client: Acme Trading (ID 42) — correct? Fulfilling store: which `store_id` should we use?  
**User:** Client 42, store 3.  
**Assistant:** Draft lines: (1) SKU `ABC-1` → Product 1001 × 12 — high confidence; (2) “Widget blue” — UNMAPPED; options: 1004 Widget Blue / 1009 Widget Navy — which?  
**User:** 1004.  
**Assistant:** Final draft JSON / checklist … Please confirm before submit.

---

## 10. What to learn first (fast path for a new AI instance)

1. Phases A → E and the **never invent product_id** rule.  
2. **Client resolution** and when to ask.  
3. **Raw line item** schema vs **mapped** schema.  
4. Where **human sign-off** is mandatory.  
5. Optional: exact API paths and field names for your deployment (copy from `management-frontend` `wholesaleOrdersAPI` or backend `CreateWholesaleOrderRequest`).

---

*This playbook describes intent and safe procedure. It is not a substitute for authenticated API documentation or org-specific SOPs.*
