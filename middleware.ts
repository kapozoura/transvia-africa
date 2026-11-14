import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

// Rafraîchit la session Supabase à chaque requête et protège les espaces
// qui exigent d'être connecté. Si Supabase n'est pas encore configuré
// (variables d'environnement absentes), le site reste consultable.
const PROTECTED_PREFIXES = ["/compte", "/wallet", "/admin", "/covoiturage"];
const TEAM_PREFIXES = ["/admin"];

export async function middleware(request: NextRequest) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return NextResponse.next();

  const response = NextResponse.next({ request: { headers: request.headers } });
  const supabase = createServerClient(url, key, {
    cookies: {
      get(name: string) {
        return request.cookies.get(name)?.value;
      },
      set(name: string, value: string, options: CookieOptions) {
        response.cookies.set({ name, value, ...options });
      },
      remove(name: string, options: CookieOptions) {
        response.cookies.set({ name, value: "", ...options });
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();
  const path = request.nextUrl.pathname;

  if (PROTECTED_PREFIXES.some((p) => path === p || path.startsWith(p + "/")) && !user) {
    const redirectUrl = new URL("/auth/login", request.url);
    redirectUrl.searchParams.set("next", path);
    return NextResponse.redirect(redirectUrl);
  }

  if (TEAM_PREFIXES.some((p) => path === p || path.startsWith(p + "/")) && user) {
    const { data: me } = await supabase.from("profiles").select("staff_role").eq("id", user.id).maybeSingle();
    if (!me || !me.staff_role) return NextResponse.redirect(new URL("/", request.url));
    response.headers.set("X-Robots-Tag", "noindex, nofollow, noarchive");
    response.headers.set("Cache-Control", "no-store");
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|demo/|manifest.webmanifest).*)"],
};
