import { jsPDF } from 'jspdf';
import html2canvas from 'html2canvas';
import JSZip from 'jszip';
import type { WholesaleOrder, WholesaleOrderDocument } from '../types';

const NOTO_LINK_ID = 'noto-sans-sc-pdf-export';

const PDF_TABLE_COL_WIDTHS = ['8%', '13%', '13%', '8%', '9%', '8%', '19%', '13%', '9%'];

async function ensureNotoSansScLoaded(): Promise<void> {
  if (!document.getElementById(NOTO_LINK_ID)) {
    const link = document.createElement('link');
    link.id = NOTO_LINK_ID;
    link.rel = 'stylesheet';
    link.href = 'https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;700&display=swap';
    document.head.appendChild(link);
    await new Promise<void>((resolve) => {
      link.onload = () => resolve();
      link.onerror = () => resolve();
      setTimeout(resolve, 4000);
    });
  }
  try {
    await document.fonts.load('12px "Noto Sans SC"');
    await document.fonts.load('700 12px "Noto Sans SC"');
  } catch {
    /* ignore */
  }
  await document.fonts.ready;
}

const tableBaseStyle =
  'border-collapse:collapse;width:100%;table-layout:fixed;font-family:"Noto Sans SC","Source Han Sans SC",sans-serif;font-size:11px;color:#111;';

function appendColGroup(table: HTMLTableElement, widths: string[]): void {
  const cg = document.createElement('colgroup');
  widths.forEach((w) => {
    const col = document.createElement('col');
    col.style.width = w;
    cg.appendChild(col);
  });
  table.appendChild(cg);
}

/** Renders filters + table head and table body separately; repeats the header block on every PDF page (CJK-safe). */
export async function downloadWholesaleOrdersSummaryPdf(options: {
  filterLines: string[];
  filterTitle: string;
  head: string[];
  rows: string[][];
  filename: string;
  /** e.g. "Acme Ltd - Wholesale order report" */
  reportHeadingLeft: string;
  /** Localized printed date/time, top right */
  reportHeadingRight: string;
  /** Optional company logo URL shown in the PDF header */
  logoUrl?: string;
}): Promise<void> {
  const {
    filterLines,
    filterTitle,
    head,
    rows,
    filename,
    reportHeadingLeft,
    reportHeadingRight,
    logoUrl,
  } = options;
  await ensureNotoSansScLoaded();

  const fontStack = '"Noto Sans SC","Source Han Sans SC",sans-serif';

  // No horizontal padding: with border-box, 16px sides shrink the inner table below body (1200px) and columns misalign when both PNGs are scaled to the same PDF width.
  const baseStyle = [
    'position:fixed',
    'left:-10000px',
    'top:0',
    'width:1200px',
    'background:#ffffff',
    'padding:0',
    'box-sizing:border-box',
  ].join(';');

  const headerWrap = document.createElement('div');
  headerWrap.style.cssText = baseStyle;

  const headingRow = document.createElement('div');
  headingRow.style.cssText = [
    `display:flex`,
    `justify-content:space-between`,
    `align-items:flex-start`,
    `gap:20px`,
    `margin-bottom:12px`,
    `width:100%`,
    `font-family:${fontStack}`,
  ].join(';');

  const headingLeftWrap = document.createElement('div');
  headingLeftWrap.style.cssText = 'display:flex;align-items:center;gap:14px;flex:1;min-width:0;';
  if (logoUrl?.trim()) {
    const logoImg = document.createElement('img');
    logoImg.src = logoUrl.trim();
    logoImg.alt = '';
    logoImg.style.cssText = 'max-height:48px;max-width:140px;object-fit:contain;flex-shrink:0;';
    headingLeftWrap.appendChild(logoImg);
    await new Promise<void>((resolve) => {
      if (logoImg.complete) {
        resolve();
        return;
      }
      logoImg.onload = () => resolve();
      logoImg.onerror = () => resolve();
      setTimeout(resolve, 3000);
    });
  }
  const headingLeft = document.createElement('div');
  headingLeft.textContent = reportHeadingLeft;
  headingLeft.style.cssText =
    'font-size:13px;font-weight:700;color:#111;flex:1;min-width:0;line-height:1.35;word-break:break-word;';
  headingLeftWrap.appendChild(headingLeft);
  const headingRight = document.createElement('div');
  headingRight.textContent = reportHeadingRight;
  headingRight.style.cssText =
    'font-size:10px;font-weight:400;color:#546e7a;line-height:1.35;text-align:right;white-space:nowrap;flex-shrink:0;';
  headingRow.appendChild(headingLeftWrap);
  headingRow.appendChild(headingRight);
  headerWrap.appendChild(headingRow);

  const filterBlock = document.createElement('div');
  filterBlock.style.cssText = `margin-bottom:12px;width:100%;font-family:${fontStack};`;
  const filterTitleEl = document.createElement('div');
  filterTitleEl.textContent = filterTitle;
  filterTitleEl.style.cssText = 'font-size:12px;font-weight:700;margin-bottom:8px;color:#37474f;';
  filterBlock.appendChild(filterTitleEl);
  const filterGrid = document.createElement('div');
  filterGrid.style.cssText = [
    'display:grid',
    'grid-template-columns:repeat(3,minmax(0,1fr))',
    'column-gap:24px',
    'row-gap:6px',
    'width:100%',
    'align-items:start',
  ].join(';');
  filterLines.forEach((line) => {
    const cell = document.createElement('div');
    cell.textContent = line;
    cell.style.cssText = 'font-size:10px;line-height:1.45;color:#222;word-break:break-word;min-width:0;';
    filterGrid.appendChild(cell);
  });
  filterBlock.appendChild(filterGrid);
  headerWrap.appendChild(filterBlock);

  const headTable = document.createElement('table');
  headTable.style.cssText = tableBaseStyle;
  appendColGroup(headTable, PDF_TABLE_COL_WIDTHS);
  const thead = document.createElement('thead');
  const trh = document.createElement('tr');
  for (const h of head) {
    const th = document.createElement('th');
    th.textContent = h;
    th.style.cssText =
      'border:1px solid #37474f;padding:8px 10px;background:#37474f;color:#fff;font-weight:700;text-align:left;vertical-align:middle;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;';
    trh.appendChild(th);
  }
  thead.appendChild(trh);
  headTable.appendChild(thead);
  headerWrap.appendChild(headTable);

  const bodyWrap = document.createElement('div');
  // No top/side padding on body capture so the first data row aligns with the header table (padding caused a visual gap/clipping mismatch).
  bodyWrap.style.cssText = [
    'position:fixed',
    'left:-10000px',
    'top:0',
    'width:1200px',
    'background:#ffffff',
    'padding:0',
    'box-sizing:border-box',
  ].join(';');

  const bodyTable = document.createElement('table');
  bodyTable.style.cssText = tableBaseStyle;
  appendColGroup(bodyTable, PDF_TABLE_COL_WIDTHS);
  const tbody = document.createElement('tbody');
  for (const row of rows) {
    const tr = document.createElement('tr');
    tr.style.background = '#fff';
    for (const cell of row) {
      const td = document.createElement('td');
      td.textContent = cell;
      td.style.cssText =
        'border:1px solid #cfd8dc;padding:6px 10px;vertical-align:middle;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;';
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }
  bodyTable.appendChild(tbody);
  bodyWrap.appendChild(bodyTable);

  document.body.appendChild(headerWrap);
  document.body.appendChild(bodyWrap);

  await new Promise<void>((r) => {
    requestAnimationFrame(() => requestAnimationFrame(() => r()));
  });

  const scale = 2;
  const [canvasHeader, canvasBody] = await Promise.all([
    html2canvas(headerWrap, {
      scale,
      useCORS: true,
      backgroundColor: '#ffffff',
      logging: false,
    }),
    html2canvas(bodyWrap, {
      scale,
      useCORS: true,
      backgroundColor: '#ffffff',
      logging: false,
    }),
  ]);

  /** Row bottom edges in canvas Y (must run while nodes are still in the document). */
  const rowBandEndPx: number[] = [];
  if (canvasBody.height > 0 && rows.length > 0) {
    const trs = bodyTable.querySelectorAll('tbody tr');
    const wrapRect = bodyWrap.getBoundingClientRect();
    // html2canvas uses Math.floor(bounds * scale); offsetHeight can differ from getBoundingClientRect().height.
    const wrapH = Math.max(1, wrapRect.height);
    trs.forEach((tr) => {
      const r = tr.getBoundingClientRect();
      const bottomCss = r.bottom - wrapRect.top;
      rowBandEndPx.push(Math.max(0, Math.round((bottomCss / wrapH) * canvasBody.height)));
    });
    if (rowBandEndPx.length) {
      for (let k = 1; k < rowBandEndPx.length; k++) {
        if (rowBandEndPx[k] < rowBandEndPx[k - 1]) {
          rowBandEndPx[k] = rowBandEndPx[k - 1];
        }
      }
      // Map cumulative layout to actual canvas height (fixes drift vs floor(scale * bounds)).
      const lastDom = rowBandEndPx[rowBandEndPx.length - 1];
      if (lastDom > 0 && lastDom !== canvasBody.height) {
        const f = canvasBody.height / lastDom;
        for (let k = 0; k < rowBandEndPx.length; k++) {
          rowBandEndPx[k] = Math.round(rowBandEndPx[k] * f);
        }
      }
      rowBandEndPx[rowBandEndPx.length - 1] = canvasBody.height;
      for (let k = 1; k < rowBandEndPx.length; k++) {
        if (rowBandEndPx[k] < rowBandEndPx[k - 1]) {
          rowBandEndPx[k] = rowBandEndPx[k - 1];
        }
      }
    }
  }

  document.body.removeChild(headerWrap);
  document.body.removeChild(bodyWrap);

  if (canvasHeader.width !== canvasBody.width) {
    console.warn('PDF header/body canvas width mismatch');
  }

  const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });
  const pageWidth = doc.internal.pageSize.getWidth();
  const pageHeight = doc.internal.pageSize.getHeight();
  const margin = 8;
  const footerMm = 6;
  const contentWidthMm = pageWidth - 2 * margin;
  const contentHeightMm = pageHeight - 2 * margin - footerMm;
  const gapMm = 1;

  // Header drawn at full content width; inner table width must match body capture (both 1200px).
  const headerDrawMmW = contentWidthMm;
  const naturalHeaderMmH = (canvasHeader.height / canvasHeader.width) * contentWidthMm;
  const maxHeaderMm = contentHeightMm * 0.42;
  const headerDrawMmH = Math.min(naturalHeaderMmH, maxHeaderMm);

  const headerDataUrl = canvasHeader.toDataURL('image/png', 1.0);

  const bodyAvailableMm = Math.max(12, contentHeightMm - headerDrawMmH - gapMm);
  const maxBodySlicePx = Math.max(
    1,
    Math.floor((bodyAvailableMm / contentWidthMm) * canvasBody.width) - 2,
  );

  const buildBodySlices = (): { start: number; height: number }[] => {
    if (canvasBody.height === 0) return [];
    if (rowBandEndPx.length === 0) {
      const slices: { start: number; height: number }[] = [];
      let y = 0;
      while (y < canvasBody.height) {
        const h = Math.min(maxBodySlicePx, canvasBody.height - y);
        slices.push({ start: y, height: h });
        y += h;
      }
      return slices;
    }
    const ends = Array.from(new Set(rowBandEndPx)).filter((e) => e > 0);
    if (!ends.includes(canvasBody.height)) ends.push(canvasBody.height);
    ends.sort((a, b) => a - b);

    const slices: { start: number; height: number }[] = [];
    let startPx = 0;
    while (startPx < canvasBody.height) {
      let endPx = startPx;
      for (const e of ends) {
        if (e <= startPx) continue;
        if (e - startPx <= maxBodySlicePx) endPx = e;
        else break;
      }
      if (endPx === startPx) {
        const next = ends.find((e) => e > startPx) ?? canvasBody.height;
        endPx = next;
      }
      slices.push({ start: startPx, height: endPx - startPx });
      startPx = endPx;
    }
    return slices.filter((s) => s.height > 0);
  };

  const bodySlices = buildBodySlices();

  if (canvasBody.height === 0) {
    doc.addImage(headerDataUrl, 'PNG', margin, margin, headerDrawMmW, headerDrawMmH);
  } else {
    bodySlices.forEach((sl, pageIdx) => {
      if (pageIdx > 0) doc.addPage();
      const slice = document.createElement('canvas');
      slice.width = canvasBody.width;
      slice.height = sl.height;
      const ctx = slice.getContext('2d');
      if (!ctx) throw new Error('CANVAS_CONTEXT');
      ctx.drawImage(canvasBody, 0, sl.start, canvasBody.width, sl.height, 0, 0, canvasBody.width, sl.height);
      const sliceData = slice.toDataURL('image/png', 1.0);
      const sliceMmH = (sl.height / canvasBody.width) * contentWidthMm;

      const bodyY = margin + headerDrawMmH + gapMm;
      doc.addImage(headerDataUrl, 'PNG', margin, margin, headerDrawMmW, headerDrawMmH);
      doc.addImage(sliceData, 'PNG', margin, bodyY, contentWidthMm, sliceMmH);
    });
  }

  const totalPages = doc.getNumberOfPages();
  const footerY = pageHeight - 4;
  for (let p = 1; p <= totalPages; p++) {
    doc.setPage(p);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.setTextColor(60, 60, 60);
    doc.text(`Page ${p} / ${totalPages}`, pageWidth / 2, footerY, { align: 'center' });
  }

  doc.save(filename);
}

export type BulkAttachmentKind =
  | 'all'
  | 'order_confirmation'
  | 'po_attachment'
  | 'delivery_note'
  | 'signed_delivery_note'
  | 'invoice'
  | 'payment_proof';

const STANDARD_DOC_TYPES: WholesaleOrderDocument['type'][] = [
  'order_confirmation',
  'po_attachment',
  'delivery_note',
  'invoice',
  'payment_proof',
];

function safePathSegment(s: string): string {
  const t = s.replace(/[/\\?*:|"<>]+/g, '_').replace(/\s+/g, ' ').trim();
  const out = t.replace(/[^\w\u0080-\uFFFF .()\-+]+/g, '_').slice(0, 120);
  return out || 'file';
}

function guessExtFromBlob(blob: Blob): string {
  const ty = blob.type || '';
  if (ty.includes('pdf')) return '.pdf';
  if (ty.includes('png')) return '.png';
  if (ty.includes('jpeg') || ty.includes('jpg')) return '.jpg';
  if (ty.includes('webp')) return '.webp';
  return '';
}

/** True when the leaf name already ends with a short extension (.pdf, .png, …). */
function hasFilenameExtension(filename: string): boolean {
  const leaf = filename.split('/').pop() || filename;
  return /\.[a-z0-9]{2,8}$/i.test(leaf);
}

function extensionFromPath(pathLike: string): string {
  const clean = (pathLike || '').split('?')[0].split('#')[0].trim();
  if (!clean) return '';
  const leaf = clean.split('/').pop() || clean;
  const m = leaf.match(/\.([a-z0-9]{2,8})$/i);
  return m ? `.${m[1].toLowerCase()}` : '';
}

type ZipDocKind = WholesaleOrderDocument['type'] | 'signed_dn';

function defaultExtWhenBlobUnknown(kind: ZipDocKind): string {
  if (kind === 'po_attachment') return '.bin';
  return '.pdf';
}

/** Ensures ZIP entries get an extension when the API omits Content-Type (common: octet-stream). */
function zipEntryBaseName(base: string, blob: Blob, kind: ZipDocKind): string {
  if (hasFilenameExtension(base)) return base;
  const fromBlob = guessExtFromBlob(blob);
  if (fromBlob) return `${base}${fromBlob}`;
  return `${base}${defaultExtWhenBlobUnknown(kind)}`;
}

async function defaultFetchRemote(url: string): Promise<Blob> {
  const res = await fetch(url, { mode: 'cors', credentials: 'omit' });
  if (!res.ok) throw new Error('REMOTE_FETCH_FAILED');
  return res.blob();
}

export async function buildWholesaleAttachmentZip(
  orders: WholesaleOrder[],
  kind: BulkAttachmentKind,
  deps: {
    downloadDocument: (orderId: number, docId: number) => Promise<Blob>;
    legacyPaymentProof?: (orderId: number) => Promise<Blob>;
    fetchRemote?: (url: string) => Promise<Blob>;
  },
): Promise<Blob> {
  const fetchRemote = deps.fetchRemote ?? defaultFetchRemote;
  const zip = new JSZip();
  let count = 0;

  for (const order of orders) {
    const folder = safePathSegment(`${order.order_number}_${order.ref_no || order.id}`);
    let fileIdx = 0;
    const nextPath = (prefix: string, base: string, blob: Blob, kind: ZipDocKind) => {
      const named = zipEntryBaseName(base, blob, kind);
      const fname = `${String(++fileIdx).padStart(2, '0')}_${prefix}_${safePathSegment(named)}`;
      return `${folder}/${fname}`;
    };

    const typesToAdd: WholesaleOrderDocument['type'][] =
      kind === 'all'
        ? [...STANDARD_DOC_TYPES]
        : kind === 'signed_delivery_note'
          ? []
          : [kind as WholesaleOrderDocument['type']];

    for (const docType of typesToAdd) {
      const docs = order.documents?.filter((d) => d.type === docType) ?? [];
      for (const doc of docs) {
        const blob = await deps.downloadDocument(order.id, doc.id);
        const base = doc.original_filename?.trim() || `${doc.type}_${doc.id}${extensionFromPath(doc.file_url || '')}`;
        zip.file(nextPath(docType, base, blob, docType), blob);
        count += 1;
      }
      if (
        docType === 'payment_proof' &&
        docs.length === 0 &&
        order.payment_proof_url &&
        deps.legacyPaymentProof
      ) {
        const blob = await deps.legacyPaymentProof(order.id);
        zip.file(nextPath('payment_proof', 'legacy_payment_proof', blob, 'payment_proof'), blob);
        count += 1;
      }
    }

    if (kind === 'all' || kind === 'signed_delivery_note') {
      for (const s of order.shipments ?? []) {
        const url = s.signed_delivery_note_pdf_url?.trim();
        if (!url) continue;
        try {
          const blob = await fetchRemote(url);
          const extFromURL = extensionFromPath(url);
          zip.file(
            nextPath('signed_dn', `shipment_${s.id}_signed_dn${extFromURL}`, blob, 'signed_dn'),
            blob,
          );
          count += 1;
        } catch {
          /* e.g. CORS on storage URL */
        }
      }
    }
  }

  if (count === 0) throw new Error('NO_FILES');
  return zip.generateAsync({ type: 'blob' });
}
