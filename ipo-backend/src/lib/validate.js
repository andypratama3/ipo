import { badRequest } from './errors.js';

/** Parse dengan zod; kesalahan dikembalikan sebagai 400 tanpa mengulang nilai input. */
export function parse(schema, data, label = 'Data') {
  const r = schema.safeParse(data);
  if (r.success) return r.data;
  const issues = r.error.issues.slice(0, 10).map((i) => ({
    path: i.path.join('.') || '(root)',
    message: i.message,
  }));
  throw badRequest(`${label} tidak valid.`, 'validation_error', { issues });
}
