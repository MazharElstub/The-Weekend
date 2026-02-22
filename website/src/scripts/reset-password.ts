import { createClient } from '@supabase/supabase-js';

const stateEl = document.getElementById('reset-state');
const formEl = document.getElementById('reset-form');
const submitEl = document.getElementById('reset-submit');
const newPasswordEl = document.getElementById('new-password');
const confirmPasswordEl = document.getElementById('confirm-password');
const configEl = document.getElementById('reset-config');

const setState = (kind: 'error' | 'success', message: string) => {
  if (!stateEl) return;
  stateEl.textContent = message;
  stateEl.setAttribute('data-kind', kind);
};

const setBusy = (isBusy: boolean) => {
  if (!(submitEl instanceof HTMLButtonElement)) return;
  submitEl.disabled = isBusy;
  submitEl.textContent = isBusy ? 'Updating...' : 'Update password';
};

const clearSensitiveURLParams = () => {
  const current = new URL(window.location.href);
  current.hash = '';
  current.searchParams.delete('access_token');
  current.searchParams.delete('refresh_token');
  current.searchParams.delete('expires_at');
  current.searchParams.delete('expires_in');
  current.searchParams.delete('token_type');
  current.searchParams.delete('type');
  current.searchParams.delete('code');
  current.searchParams.delete('token_hash');
  window.history.replaceState({}, '', `${current.pathname}${current.search ? current.search : ''}`);
};

const supabaseURL = configEl?.getAttribute('data-supabase-url') ?? '';
const supabaseAnonKey = configEl?.getAttribute('data-supabase-anon-key') ?? '';

const hasSupabaseConfig = Boolean(supabaseURL && supabaseAnonKey);
const supabase = hasSupabaseConfig
  ? createClient(supabaseURL, supabaseAnonKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false
      }
    })
  : null;

let recoverySessionReady = false;

const establishRecoverySession = async () => {
  if (!supabase) {
    setState('error', 'Reset is not configured yet. Please contact support and try again later.');
    return;
  }

  const searchParams = new URLSearchParams(window.location.search);
  const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ''));

  try {
    const accessToken = hashParams.get('access_token');
    const refreshToken = hashParams.get('refresh_token');

    if (accessToken && refreshToken) {
      const { error } = await supabase.auth.setSession({
        access_token: accessToken,
        refresh_token: refreshToken
      });
      if (error) throw error;
      recoverySessionReady = true;
      setState('success', 'Recovery link verified. Enter your new password.');
      return;
    }

    const code = searchParams.get('code');
    if (code) {
      const { error } = await supabase.auth.exchangeCodeForSession(code);
      if (error) throw error;
      recoverySessionReady = true;
      setState('success', 'Recovery link verified. Enter your new password.');
      return;
    }

    const tokenHash = searchParams.get('token_hash');
    const type = searchParams.get('type');
    if (tokenHash && type === 'recovery') {
      const { error } = await supabase.auth.verifyOtp({
        token_hash: tokenHash,
        type: 'recovery'
      });
      if (error) throw error;
      recoverySessionReady = true;
      setState('success', 'Recovery link verified. Enter your new password.');
      return;
    }

    setState('error', 'This reset link is invalid or expired. Request a new reset email from the app.');
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unable to verify reset link.';
    setState('error', message);
  } finally {
    clearSensitiveURLParams();
  }
};

formEl?.addEventListener('submit', async (event) => {
  event.preventDefault();

  if (!supabase || !(newPasswordEl instanceof HTMLInputElement) || !(confirmPasswordEl instanceof HTMLInputElement)) {
    setState('error', 'Reset is not available right now.');
    return;
  }

  const password = newPasswordEl.value.trim();
  const confirm = confirmPasswordEl.value.trim();

  if (password.length < 6) {
    setState('error', 'Please enter at least 6 characters for your new password.');
    return;
  }

  if (password !== confirm) {
    setState('error', 'Password confirmation does not match.');
    return;
  }

  if (!recoverySessionReady) {
    try {
      const { data, error } = await supabase.auth.getSession();
      if (error) throw error;
      recoverySessionReady = Boolean(data.session);
    } catch {
      recoverySessionReady = false;
    }
  }

  if (!recoverySessionReady) {
    setState('error', 'Your reset session has expired. Request a fresh reset email and try again.');
    return;
  }

  try {
    setBusy(true);
    const { error } = await supabase.auth.updateUser({ password });
    if (error) throw error;
    setState('success', 'Password updated. Redirecting...');
    window.setTimeout(() => {
      window.location.assign('/reset-password/success');
    }, 700);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Could not update password. Please try again.';
    setState('error', message);
  } finally {
    setBusy(false);
  }
});

void establishRecoverySession();
