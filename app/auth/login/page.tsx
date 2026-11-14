import Link from "next/link";
import { signIn } from "@/app/auth/actions";

export default function LoginPage({ searchParams }: { searchParams: { error?: string; ok?: string; next?: string } }) {
  return (
    <div className="mx-auto max-w-sm rounded-2xl bg-white p-6 shadow-sm">
      <h1 className="text-xl font-extrabold">Connexion</h1>
      {searchParams.error && <p className="mt-3 rounded bg-red-50 p-2 text-sm font-semibold text-red-700">{searchParams.error}</p>}
      {searchParams.ok && <p className="mt-3 rounded bg-green-50 p-2 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      <form action={signIn} className="mt-4 space-y-3">
        <input type="hidden" name="next" value={searchParams.next ?? "/compte"} />
        <input name="email" type="email" required placeholder="E-mail" className="w-full rounded border px-3 py-2" />
        <input name="password" type="password" required placeholder="Mot de passe" className="w-full rounded border px-3 py-2" />
        <button className="w-full rounded bg-navy py-2 font-bold text-white" type="submit">Se connecter</button>
      </form>
      <p className="mt-4 text-sm">Pas encore de compte ? <Link href="/auth/signup" className="font-bold underline">Créer un compte</Link></p>
    </div>
  );
}
