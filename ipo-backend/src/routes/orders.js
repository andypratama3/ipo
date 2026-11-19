import { Router } from 'express';
import { ah, notFound, badRequest } from '../lib/errors.js';
import { parse } from '../lib/validate.js';
import { orderInputSchema } from '../lib/schemas.js';
import { requireAuth, requireOwner } from '../middleware/auth.js';
import { createOrder, deleteOrder } from '../services/orders.js';

const r = Router();
r.use(requireAuth);

r.post('/', ah(async (req, res) => {
  const input = parse(orderInputSchema, req.body, 'Transaksi');
  const out = await createOrder(input, req.user);
  res.status(out.duplicate ? 200 : 201).json({ ok: true, ...out });
}));

r.delete('/:id', requireOwner, ah(async (req, res) => {
  if (!/^MPJ-\d{8}-[A-Za-z0-9]{3,12}$/.test(req.params.id)) throw badRequest('Nomor struk tidak valid.');
  if (!(await deleteOrder(req.params.id, req.user))) throw notFound('Transaksi tidak ditemukan.');
  res.json({ ok: true, id: req.params.id, stockRestored: false });
}));

export default r;
