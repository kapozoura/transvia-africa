import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";
import { createClient } from "@/lib/supabase/server";
import { configured } from "@/lib/roles";
import { signOut } from "@/app/auth/actions";

export const metadata: Metadata = {
  title: "Transvia Africa",
  description: "Réservez. Voyagez. Suivez. — la plateforme de mobilité et de logistique pour l'Afrique de l'Ouest.",
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  let signedIn = false;
  if (configured()) {
    const {
      data: { user },
    } = await createClient().auth.getUser();
    signedIn = Boolean(user);
  }
  return (
    <html lang="fr">
      <body>
        <header className="bg-navy text-white">
          <nav className="mx-auto flex max-w-4xl items-center justify-between px-4 py-3 text-sm">
            <Link href="/" className="font-extrabold tracking-wide">
              TRANSVIA <span className="text-amber">AFRICA</span>
            </Link>
            <div className="flex items-center gap-4">
              <a href="/demo/index.html" className="hover:text-amber">Démo</a>
              {signedIn ? (
                <>
                  <Link href="/covoiturage" className="hover:text-amber">Covoiturage</Link>
                  <Link href="/compte" className="hover:text-amber">Mon compte</Link>
                  <Link href="/wallet" className="hover:text-amber">Wallet</Link>
                  <form action={signOut}>
                    <button className="hover:text-amber" type="submit">Déconnexion</button>
                  </form>
                </>
              ) : (
                <>
                  <Link href="/auth/login" className="hover:text-amber">Connexion</Link>
                  <Link href="/auth/signup" className="rounded bg-amber px-3 py-1 font-bold text-navy">Créer un compte</Link>
                </>
              )}
            </div>
          </nav>
        </header>
        <main className="mx-auto max-w-4xl px-4 py-6">{children}</main>
      </body>
    </html>
  );
}
