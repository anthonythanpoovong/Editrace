import type { Metadata } from "next";
import Link from "next/link";
import { WaitlistSignup } from "../components/waitlist-signup";
import { getSupabaseConfig } from "../lib/supabase/config";
import styles from "./landing.module.css";

const description =
  "Editrace turns a video's editing style into a reusable template, applied in Premiere Pro, DaVinci Resolve, Final Cut Pro and CapCut.";

export const metadata: Metadata = {
  title: "Editrace: coming soon",
  description,
  openGraph: {
    title: "Editrace: coming soon",
    description: "Editrace turns a video's editing style into a reusable template, applied in the editor you already use.",
    type: "website",
  },
  twitter: { card: "summary" },
};

export const viewport = { themeColor: "#fbf9f5" };

const FEATURES = [
  { title: "Cuts and pacing", text: "Every cut and beat, placed where the original put it." },
  { title: "Transitions and motion", text: "Transitions, push-ins and movement, rebuilt as steps you can edit." },
  { title: "Text and titles", text: "Lower thirds and captions you can change after they are applied." },
];

// The waitlist form posts straight to Supabase with the public anon key. Previews have no Supabase variables
// (docs/environments.md) and must still serve this page, so a missing value is logged, not thrown.
function publicSupabaseConfig() {
  try {
    return getSupabaseConfig();
  } catch (error) {
    console.error("Supabase isn't configured; the waitlist form can't send.", error);
    return null;
  }
}

// The public coming-soon page (#149). Signed-out visitors may open "/" (see lib/auth/guard.ts).
export default function Home() {
  const config = publicSupabaseConfig();
  return (
    <div className={styles.backdrop}>
      <div className={styles.page}>
        <header className={styles.header}>
          <Link href="/" aria-label="Editrace">
            {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size SVG; nothing for next/image to optimise */}
            <img className={styles.logo} src="/images/brand/logo-horizontal-light.svg" width={386} height={60} alt="Editrace" />
          </Link>
          <span className={styles.status}>Coming soon</span>
        </header>

        <main className={styles.main}>
          <div className={styles.hero}>
            <h1 className={styles.title}>
              Rebuild the edit in minutes<span className={styles.accent}>.</span>
            </h1>
            <p className={styles.lede}>
              Editrace reverse-engineers a video&apos;s cuts, pacing and transitions, then rebuilds a faithful version in your own editor.
            </p>
            <p className={styles.tools}>Planned for Premiere Pro, DaVinci Resolve, Final Cut Pro and CapCut.</p>
            <div className={styles.heroVisual}>
              {/* eslint-disable-next-line @next/next/no-img-element -- art-directed crop via object-fit; the file is already sized */}
              <img
                src="/images/Cinematic_Video_Analysis_Interface_1-transparent.png?v=2"
                width={1774}
                height={887}
                alt="A video's edit broken into the layers Editrace extracts: music, camera angles, editing and transitions, color grading, and other elements like location, objects and effects."
              />
            </div>
            <WaitlistSignup config={config} />
          </div>

          <ul className={styles.features}>
            {FEATURES.map((f) => (
              <li key={f.title}>
                <h2>{f.title}</h2>
                <p>{f.text}</p>
              </li>
            ))}
          </ul>
        </main>

        <footer className={styles.footer}>
          {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size SVG */}
          <img className={styles.footerWordmark} src="/images/brand/wordmark-light.svg" width={292} height={59} alt="Editrace" />
          <span className={styles.copyright}>© Editrace</span>
        </footer>
      </div>
    </div>
  );
}
