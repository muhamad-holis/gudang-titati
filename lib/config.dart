/// Diisi lewat --dart-define (GitHub Secrets): SUPABASE_URL dan SUPABASE_ANON_KEY
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
bool get cloudReady => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
