/// Supabase project configuration.
/// Replace placeholders with your actual project URL and anon key.
/// Find these in: Supabase Dashboard → Project Settings → API.
class SupabaseConfig {
  SupabaseConfig._();

  /// Your Supabase project URL, e.g. https://xyzxyz.supabase.co
  static const String url = 'https://bwvirielkxyzsxfoamgh.supabase.co';

  /// The anon/public key for your Supabase project.
  /// Safe to expose in client code – row-level security controls access.
  static const String anonKey = 'sb_publishable_u8sUqZ1vspT_XMlKtZXZMQ_cHy7xDR7';
}
