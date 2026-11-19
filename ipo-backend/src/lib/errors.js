export class AppError extends Error {
  constructor(status, code, message, extra) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

export const badRequest = (msg = 'Permintaan tidak valid.', code = 'bad_request', extra) =>
  new AppError(400, code, msg, extra);
export const unauthorized = (msg = 'Sesi tidak valid. Silakan login ulang.') =>
  new AppError(401, 'unauthorized', msg);
export const forbidden = (msg = 'Anda tidak punya izin untuk aksi ini.') =>
  new AppError(403, 'forbidden', msg);
export const notFound = (msg = 'Data tidak ditemukan.') => new AppError(404, 'not_found', msg);
export const conflict = (msg = 'Konflik data.', code = 'conflict') => new AppError(409, code, msg);

/** Bungkus handler async agar error masuk ke error middleware (Express 4 tidak menangkapnya sendiri). */
export const ah = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
