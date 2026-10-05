import { appName } from "../lib/app-name";

// Placeholder page so the preview and staging deploys have something to serve (#48). Replace with the real app.
export default function Home() {
  return (
    <main>
      <h1>{appName}</h1>
      <p>Deploy pipeline placeholder.</p>
    </main>
  );
}
