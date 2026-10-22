import { User, UserManager } from "oidc-client-ts";

// Cognito sign-in: authorization code flow with PKCE (docs/architecture.md, Access protection).
// VITE_COGNITO_* come from Terraform outputs; see .env.development.
const appUrl = `${window.location.origin}/`;

export const userManager = new UserManager({
  authority: import.meta.env.VITE_COGNITO_AUTHORITY ?? "",
  client_id: import.meta.env.VITE_COGNITO_CLIENT_ID ?? "",
  redirect_uri: appUrl,
  post_logout_redirect_uri: appUrl,
  response_type: "code",
  scope: "openid email listings/read listings/decide",
  // Renews the access token with the refresh token before it expires.
  automaticSilentRenew: true,
});

// Finishes a sign-in redirect, or starts one when there is no valid session.
// Resolves with the user once signed in; otherwise the page is navigating away.
export async function ensureSignedIn(): Promise<User | null> {
  const params = new URLSearchParams(window.location.search);
  if (params.has("code") && params.has("state")) {
    const user = await userManager.signinRedirectCallback();
    window.history.replaceState({}, document.title, window.location.pathname);
    return user;
  }
  const user = await userManager.getUser();
  if (user && !user.expired) return user;
  await userManager.signinRedirect();
  return null;
}

export async function accessToken(): Promise<string | undefined> {
  const user = await userManager.getUser();
  return user?.access_token;
}

// Cognito does not implement the OIDC end-session endpoint, so logout uses its own URL.
export async function signOut(): Promise<void> {
  await userManager.removeUser();
  const logout = new URL(`${import.meta.env.VITE_COGNITO_DOMAIN ?? ""}/logout`);
  logout.searchParams.set("client_id", import.meta.env.VITE_COGNITO_CLIENT_ID ?? "");
  logout.searchParams.set("logout_uri", appUrl);
  window.location.assign(logout.toString());
}
