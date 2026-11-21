import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_controller.dart';
import 'widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = context.read<AppController>();
    final error = await controller.login(_username.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF041824), Color(0xFF0A2A3E)]
                : const [Color(0xFFEAF6FD), Color(0xFFF8FBFD)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: 'Ganti tema',
                  onPressed: controller.toggleTheme,
                  icon: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  ),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 96,
                            height: 96,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.cardTheme.color,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: PosColors.sky.withValues(alpha: 0.18),
                                  blurRadius: 28,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                'assets/img/pangsitmie.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stack) => const Icon(
                                  Icons.ramen_dining_rounded,
                                  size: 46,
                                  color: PosColors.sky,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Mie Pangsit Jakarta',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kasir offline-first · data tersimpan di perangkat',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 26),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Masuk shift',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    controller.apiBase.isEmpty
                                        ? 'Mode lokal — akun tersimpan di perangkat ini.'
                                        : 'Terhubung ke ${controller.apiBase}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: _username,
                                    autofillHints: const [AutofillHints.username],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Nama pengguna',
                                      prefixIcon: Icon(Icons.person_outline_rounded),
                                    ),
                                    validator: (value) =>
                                        (value == null || value.trim().isEmpty)
                                            ? 'Isi nama pengguna.'
                                            : null,
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _password,
                                    obscureText: _obscure,
                                    autofillHints: const [AutofillHints.password],
                                    onFieldSubmitted: (_) => _submit(),
                                    decoration: InputDecoration(
                                      labelText: 'Sandi',
                                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                                      suffixIcon: IconButton(
                                        onPressed: () =>
                                            setState(() => _obscure = !_obscure),
                                        icon: Icon(
                                          _obscure
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                        ),
                                      ),
                                    ),
                                    validator: (value) => (value == null || value.isEmpty)
                                        ? 'Isi sandi.'
                                        : null,
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: toneOf(context, PillTone.danger).background,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color:
                                              toneOf(context, PillTone.danger).foreground,
                                          fontSize: 12.5,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  FilledButton.icon(
                                    onPressed: _busy ? null : _submit,
                                    icon: _busy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.login_rounded, size: 19),
                                    label: Text(_busy ? 'Memeriksa…' : 'Masuk'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          controller.apiBase.isEmpty
                              ? 'Akun bawaan: pemilik / 1234 · kasir / 1234'
                              : 'Sandi diperiksa di server IPOS.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () => showAppSnack(
                            context,
                            'Atur alamat server lewat akun pemilik di Pengaturan → Server & cadangan.',
                          ),
                          icon: const Icon(Icons.help_outline_rounded, size: 17),
                          label: const Text('Tidak bisa masuk?'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
