// @vitest-environment jsdom
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { WaitlistSignup } from "./waitlist-signup";

const config = { url: "https://example.supabase.co", anonKey: "anon" };
const fetchMock = vi.fn();

beforeEach(() => {
  fetchMock.mockReset().mockResolvedValue(new Response(null, { status: 204 }));
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

async function openForm() {
  const user = userEvent.setup();
  render(<WaitlistSignup config={config} />);
  await user.click(screen.getByRole("button", { name: "Get notified" }));
  return user;
}

async function fillIn(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("First name"), "Ada");
  await user.type(screen.getByLabelText("Last name"), "Lovelace");
  await user.selectOptions(screen.getByLabelText("Role"), "editor");
  await user.type(screen.getByLabelText("Email address"), "ada@example.com");
  await user.selectOptions(screen.getByLabelText("How did you hear about us?"), "tiktok");
}

describe("WaitlistSignup", () => {
  test("keeps the form closed until the button is pressed", async () => {
    render(<WaitlistSignup config={config} />);
    const button = screen.getByRole("button", { name: "Get notified" });
    expect(button.getAttribute("aria-expanded")).toBe("false");
    expect(screen.queryByLabelText("Email address")).toBeNull();
    await userEvent.setup().click(button);
    expect(button.getAttribute("aria-expanded")).toBe("true");
    expect(screen.getByLabelText("Email address")).toBeTruthy();
  });

  test("shows every error and sends nothing when the form is empty", async () => {
    const user = await openForm();
    await user.click(screen.getByRole("button", { name: "Notify me at launch" }));
    expect(screen.getByText("Enter your first name.")).toBeTruthy();
    expect(screen.getByText("Select how you heard about us.")).toBeTruthy();
    expect(screen.getByRole("status").textContent).toContain("fix the highlighted fields");
    expect(screen.getByLabelText("Email address").getAttribute("aria-invalid")).toBe("true");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("sends a complete signup, says thanks and empties the form", async () => {
    const user = await openForm();
    await fillIn(user);
    await user.click(screen.getByRole("button", { name: "Notify me at launch" }));
    await waitFor(() => expect(screen.getByRole("status").textContent).toContain("hear from us"));
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect((screen.getByLabelText("Email address") as HTMLInputElement).value).toBe("");
  });

  test("keeps what was typed and says so when sending fails", async () => {
    fetchMock.mockResolvedValue(new Response(null, { status: 500 }));
    const user = await openForm();
    await fillIn(user);
    await user.click(screen.getByRole("button", { name: "Notify me at launch" }));
    await waitFor(() => expect(screen.getByRole("status").textContent).toContain("Something went wrong"));
    expect((screen.getByLabelText("Email address") as HTMLInputElement).value).toBe("ada@example.com");
  });

  test("thanks a bot that fills the hidden field, without sending", async () => {
    const user = await openForm();
    await fillIn(user);
    await user.type(screen.getByLabelText("Leave this field blank"), "spam");
    await user.click(screen.getByRole("button", { name: "Notify me at launch" }));
    await waitFor(() => expect(screen.getByRole("status").textContent).toContain("hear from us"));
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("cancel empties the form, clears the errors and closes it", async () => {
    const user = await openForm();
    await user.type(screen.getByLabelText("First name"), "Ada");
    await user.click(screen.getByRole("button", { name: "Notify me at launch" }));
    await user.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.queryByLabelText("First name")).toBeNull();
    await user.click(screen.getByRole("button", { name: "Get notified" }));
    expect((screen.getByLabelText("First name") as HTMLInputElement).value).toBe("");
    expect(screen.queryByText("Enter your last name.")).toBeNull();
  });
});
