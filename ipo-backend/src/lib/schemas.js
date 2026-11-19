import { z } from 'zod';
import { isValidQris } from './qris.js';

export const ID_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/;
export const idStr = z.string().regex(ID_RE, 'ID tidak valid');
export const deviceIdSchema = z.string().regex(/^[A-Za-z0-9._:-]{1,64}$/, 'deviceId tidak valid').optional();

const str = (max) => z.string().max(max);
const optStr = (max) => z.string().max(max).optional().nullable();
const rupiah = z.number().int().min(0).max(100_000_000);
const isoDate = z.string().max(40).refine((s) => !Number.isNaN(Date.parse(s)), 'Tanggal tidak valid');

export const MAX_PAYLOAD_BYTES = 64 * 1024;
export const jsonSize = (v) => Buffer.byteLength(JSON.stringify(v), 'utf8');

// ---------- Auth & pengguna ----------
export const usernameSchema = z
  .string()
  .trim()
  .toLowerCase()
  .regex(/^[a-z0-9._-]{3,32}$/, 'Username 3-32 karakter: huruf kecil, angka, titik, strip, garis bawah');

// bcrypt hanya memakai 72 byte pertama -> tolak lebih panjang agar tidak terpotong diam-diam.
export const passwordSchema = z
  .string()
  .min(8, 'Sandi minimal 8 karakter')
  .refine((s) => Buffer.byteLength(s, 'utf8') <= 72, 'Sandi maksimal 72 byte')
  .refine((s) => !/^(.)\1+$/.test(s) && !/^(12345678|password|qwertyui|11111111)$/i.test(s), 'Sandi terlalu mudah ditebak');

export const loginSchema = z.object({
  username: z.string().trim().toLowerCase().min(1).max(64),
  password: z.string().min(1).max(200),
});

export const changePasswordSchema = z.object({
  currentPassword: z.string().min(1).max(200),
  newPassword: passwordSchema,
});

export const userCreateSchema = z.object({
  username: usernameSchema,
  displayName: z.string().trim().min(1).max(60),
  role: z.enum(['Pemilik', 'Kasir']),
  password: passwordSchema,
});

export const userUpdateSchema = z
  .object({
    displayName: z.string().trim().min(1).max(60).optional(),
    role: z.enum(['Pemilik', 'Kasir']).optional(),
    active: z.boolean().optional(),
    password: passwordSchema.optional(),
  })
  .refine((o) => Object.keys(o).length > 0, 'Tidak ada perubahan');

// ---------- Sinkronisasi ----------
export const productSchema = z.object({
  id: idStr,
  name: z.string().trim().min(1).max(120),
  category: str(120).optional().nullable().default(''),
  price: rupiah,
  stock: z.number().int().min(0).max(1_000_000).nullable().optional().default(null),
  available: z.boolean().optional().default(true),
  description: str(500).optional().nullable().default(''),
  emoji: str(16).optional().nullable().default(''),
});

export const categorySchema = z.object({
  id: idStr,
  emoji: str(16).optional().nullable().default(''),
  label: z.string().trim().min(1).max(80),
});

const primitive = z.union([z.string().max(2000), z.number(), z.boolean(), z.null()]);
export const settingsSchema = z
  .object({
    businessName: str(120).optional(),
    businessAddress: str(300).optional(),
    businessPhone: str(40).optional(),
    taxRate: z.number().min(0).max(100).optional(),
    qrisStaticPayload: z
      .string()
      .trim()
      .max(1024)
      .refine((s) => isValidQris(s), 'String QRIS tidak valid (struktur/CRC)')
      .optional(),
    receiptPaperSize: z.enum(['58mm', '80mm', 'A4']).optional(),
    receiptFooter: str(300).optional(),
    onlineRejectionMessage: str(200).optional(),
  })
  .catchall(primitive);

const itemSchema = z.object({
  productId: str(64).optional().nullable(),
  name: z.string().min(1).max(160),
  price: rupiah,
  qty: z.number().int().min(1).max(999),
  total: z.number().int().min(0).max(2_000_000_000).optional(),
  note: optStr(200),
});

export const pendingOrderSchema = z
  .object({
    id: z.string().regex(/^HOLD-\d{8}-[A-Za-z0-9]{3,12}$/, 'ID pesanan tidak valid'),
    createdAt: isoDate.optional(),
    orderType: optStr(30),
    tableNumber: optStr(20),
    items: z.array(itemSchema).min(1).max(100),
    subtotal: z.number().int().min(0).max(2_000_000_000),
    discount: z.number().int().min(0).max(2_000_000_000).optional(),
    total: z.number().int().min(0).max(2_000_000_000),
    status: str(20).optional(),
    payment: optStr(20),
    cashier: optStr(60),
    note: optStr(500),
  })
  .passthrough();

export const ONLINE_STATUSES = ['baru', 'dibuat', 'siap', 'selesai'];
export const onlineOrderSchema = z
  .object({
    id: z.string().regex(/^ONL-[A-Za-z0-9_-]{1,64}$/, 'ID pesanan online tidak valid'),
    source: z.enum(['gofood', 'grab', 'shopee']),
    partnerOrderId: optStr(80),
    orderType: z.enum(['delivery', 'pickup']).optional().nullable(),
    status: z.enum(['baru', 'dibuat', 'siap', 'selesai']),
    customer: optStr(120),
    note: optStr(500),
    items: z
      .array(z.object({ productId: str(64).optional().nullable(), qty: z.number().int().min(1).max(999), note: optStr(200) }).passthrough())
      .max(100),
    rejectReason: optStr(200),
  })
  .passthrough();

export const syncRowSchema = z.object({
  id: idStr,
  payload: z.record(z.string(), z.any()).optional(),
  deleted: z.boolean().optional().default(false),
});

export const syncPushSchema = z.object({
  table: z.string().min(1).max(40),
  rows: z.array(syncRowSchema).min(1).max(1000),
  deviceId: deviceIdSchema,
});

export const PAYMENTS = ['cash', 'qris', 'transfer', 'card'];
export const orderInputSchema = z.object({
  order: z.object({
    id: z.string().regex(/^MPJ-\d{8}-[A-Za-z0-9]{3,12}$/, 'Nomor struk tidak valid'),
    clientTxnId: z.string().uuid('clientTxnId harus UUID'),
    createdAt: isoDate,
    items: z.array(itemSchema).min(1).max(100),
    orderType: z.string().max(30).regex(/^[A-Za-z0-9_-]*$/).optional().nullable(),
    tableNumber: optStr(20),
    discount: z.number().int().min(0).max(2_000_000_000).optional().default(0),
    payment: z.string().max(20).optional().default('cash'),
    paidAmount: z.number().int().min(0).max(2_000_000_000).optional().default(0),
    status: str(20).optional(),
    cashier: optStr(60),
    note: optStr(500),
  }),
  deviceId: deviceIdSchema,
});

export const menuMapSchema = z.object({
  source: z.enum(['gofood', 'grab', 'shopee']),
  partnerMenuId: z.string().min(1).max(120),
  partnerMenuName: z.string().max(200).optional().nullable(),
  productId: idStr.nullable(),
});
