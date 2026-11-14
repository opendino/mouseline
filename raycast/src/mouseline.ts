import { closeMainWindow, getApplications, open, showToast, Toast } from "@raycast/api";

/** MouseLine's bundle identifier; its mouseline:// URLs are documented in the app's README. */
const BUNDLE_ID = "app.mouseline";
const DOWNLOAD_URL = "https://github.com/opendino/mouseline/releases/latest";

/**
 * Sends a command to MouseLine through its URL scheme, e.g. `send("toggle")` opens
 * `mouseline://toggle`. MouseLine shows its own on-screen confirmation, so the Raycast
 * window just closes. If MouseLine is not installed, a toast offers the download page.
 */
export async function send(command: string): Promise<void> {
  const apps = await getApplications();
  if (!apps.some((app) => app.bundleId === BUNDLE_ID)) {
    await showToast({
      style: Toast.Style.Failure,
      title: "MouseLine is not installed",
      message: "Install it with Homebrew or from GitHub.",
      primaryAction: {
        title: "Open Download Page",
        onAction: () => open(DOWNLOAD_URL),
      },
    });
    return;
  }
  // Close first, so "toggle in current app" sees the app the user was in, not Raycast.
  await closeMainWindow();
  await open(`mouseline://${command}`);
}
