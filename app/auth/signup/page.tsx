import Link from "next/link";
import { signUp } from "@/app/auth/actions";

export default function SignupPage({ searchParams }: { searchParams: { error?: string } }) {
  return (
    <div className="mx-auto max-w-sm rounded-2xl bg-white p-6 shadow-sm">
      <h1 className="text-xl font-extrabold">Créer mon compte unique</h1>
      <p className="mt-1 text-sm text-navy/70">Un seul compte pour tous les services Transvia. Les rôles (conducteur, loueur…) s&apos;ajoutent ensuite.</p>
      {searchParams.error && <p className="mt-3 rounded bg-red-50 p-2 text-sm font-semibold text-red-700">{searchParams.error}</p>}
      <form action={signUp} className="mt-4 space-y-3">
        <input name="full_name" required placeholder="Nom complet" className="w-full rounded border px-3 py-2" />
        <input name="phone" placeholder="Téléphone (+225…)" className="w-full rounded border px-3 py-2" />
        <input name="city" placeholder="Ville" className="w-full rounded border px-3 py-2" />
        <input name="email" type="email" required placeholder="E-mail" className="w-full rounded border px-3 py-2" />
        <input name="password" type="password" required minLength={8} placeholder="Mot de passe (8 caractères min.)" className="w-full rounded border px-3 py-2" />
        <button className="w-full rounded bg-amber py-2 font-bold text-navy" type="submit">Créer mon compte</button>
      </form>
      <p className="mt-4 text-sm">Déjà inscrit ? <Link href="/auth/login" className="font-bold underline">Se connecter</Link></p>
    </div>
  );
}
